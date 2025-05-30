#!/bin/bash
# devops/dev/deploy-dev.sh
# Script per deploy automatico ambiente dev via Docker Compose

set -e  # Exit on error

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurazione
ENVIRONMENT="dev"
COMPOSE_FILE="docker-compose.dev.yml"
CONTAINER_NAME="ice-pulse-api-dev"
HEALTH_CHECK_URL="http://localhost:80/health"
MAX_WAIT_TIME=60

echo -e "${BLUE}🚀 Starting deployment for environment: ${ENVIRONMENT}${NC}"

# Funzione per logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Controllo prerequisiti
log "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    error "Docker not found. Please install Docker first."
fi

if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose not found. Please install Docker Compose first."
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    error "Docker Compose file not found: $COMPOSE_FILE"
fi

# Backup del container corrente (se esiste)
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    log "Creating backup of current container..."
    docker commit "$CONTAINER_NAME" "ice-pulse-api:backup-$(date +%Y%m%d-%H%M%S)" || warning "Backup failed, continuing..."
fi

# Pull delle nuove immagini
log "Pulling latest images..."
docker-compose -f "$COMPOSE_FILE" pull

# Stop e rimozione container esistenti
log "Stopping existing containers..."
docker-compose -f "$COMPOSE_FILE" down --remove-orphans

# Pulizia immagini dangling (opzionale)
log "Cleaning up dangling images..."
docker image prune -f || warning "Image cleanup failed, continuing..."

# Start dei nuovi container
log "Starting new containers..."
docker-compose -f "$COMPOSE_FILE" up -d

# Attesa che i servizi siano pronti
log "Waiting for services to be ready..."
wait_time=0
while [ $wait_time -lt $MAX_WAIT_TIME ]; do
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up (healthy)"; then
        log "✅ Services are healthy!"
        break
    fi
    
    sleep 5
    wait_time=$((wait_time + 5))
    echo -n "."
done

if [ $wait_time -ge $MAX_WAIT_TIME ]; then
    error "Services failed to become healthy within ${MAX_WAIT_TIME} seconds"
fi

# Verifica deployment
log "Verifying deployment..."
docker-compose -f "$COMPOSE_FILE" ps

# Test dell'endpoint (se disponibile)
log "Testing application endpoint..."
if command -v curl &> /dev/null; then
    if curl -f -s "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
        log "✅ Application is responding correctly"
    else
        warning "Health check endpoint not responding, but containers are up"
    fi
else
    warning "curl not available, skipping endpoint test"
fi

# Logging finale
log "📊 Deployment Summary:"
echo "Environment: $ENVIRONMENT"
echo "Compose File: $COMPOSE_FILE"
echo "Container Status:"
docker-compose -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

log "🎉 Deployment completed successfully!"

# Cleanup old images (keep last 3)
log "Cleaning up old images..."
docker images "docker.io/aipioppi/ice-pulse-api" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | tail -n +2 | sort -k4 -r | tail -n +4 | awk '{print $3}' | xargs -r docker rmi || warning "Old image cleanup failed"

echo -e "${BLUE}🚀 Dev environment is ready at: http://localhost${NC}"