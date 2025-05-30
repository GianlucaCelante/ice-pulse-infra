#!/bin/bash
# devops/staging/deploy-staging.sh
# Script per deploy automatico ambiente staging via Docker Compose

set -e  # Exit on error

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurazione
ENVIRONMENT="staging"
COMPOSE_FILE="docker-compose-staging.yml"
CONTAINER_NAME="ice-pulse-api-staging"
HEALTH_CHECK_URL="http://localhost:8081/health"
MAX_WAIT_TIME=120  # Tempo maggiore per staging

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

# Verifica che la porta 8081 sia disponibile
if ss -tuln | grep -q :8081; then
    warning "Port 8081 is already in use. This might cause conflicts."
fi

# Pre-deployment health check
log "Running pre-deployment checks..."
docker-compose -f "$COMPOSE_FILE" config > /dev/null || error "Docker Compose configuration is invalid"

# Backup del container corrente (se esiste)
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    log "Creating backup of current staging container..."
    docker commit "$CONTAINER_NAME" "ice-pulse-api:staging-backup-$(date +%Y%m%d-%H%M%S)" || warning "Backup failed, continuing..."
fi

# Pull delle nuove immagini
log "Pulling latest images..."
docker-compose -f "$COMPOSE_FILE" pull

# Verifica che le immagini siano state scaricate
log "Verifying downloaded images..."
docker-compose -f "$COMPOSE_FILE" images

# Stop graduale dei servizi
log "Stopping existing containers gracefully..."
docker-compose -f "$COMPOSE_FILE" stop || warning "Some containers were not running"

# Rimozione container e network
log "Removing old containers and networks..."
docker-compose -f "$COMPOSE_FILE" down --remove-orphans

# Pulizia immagini dangling
log "Cleaning up dangling images..."
docker image prune -f || warning "Image cleanup failed, continuing..."

# Start dei nuovi container
log "Starting new containers..."
docker-compose -f "$COMPOSE_FILE" up -d

# Attesa che i servizi siano pronti con timeout esteso
log "Waiting for services to be ready (max ${MAX_WAIT_TIME}s)..."
wait_time=0
healthy=false

while [ $wait_time -lt $MAX_WAIT_TIME ]; do
    if docker-compose -f "$COMPOSE_FILE" ps | grep -E "(Up|healthy)"; then
        # Verifica che l'API risponda
        if command -v curl &> /dev/null; then
            if curl -f -s --max-time 5 "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
                healthy=true
                break
            fi
        else
            # Fallback se curl non disponibile
            if docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up (healthy)"; then
                healthy=true
                break
            fi
        fi
    fi
    
    sleep 10
    wait_time=$((wait_time + 10))
    echo -n "."
done

echo # Nuova riga dopo i punti

if [ "$healthy" = false ]; then
    error "Services failed to become healthy within ${MAX_WAIT_TIME} seconds"
fi

log "✅ Services are healthy and responding!"

# Verifica deployment dettagliata
log "Verifying deployment..."
echo "=== Container Status ==="
docker-compose -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo "=== Service Images ==="
docker-compose -f "$COMPOSE_FILE" images --format "table {{.Service}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Test degli endpoint
log "Testing application endpoints..."
if command -v curl &> /dev/null; then
    echo "Health Check:"
    curl -s "$HEALTH_CHECK_URL" | jq . || curl -s "$HEALTH_CHECK_URL"
    
    echo -e "\nRoot Endpoint:"
    curl -s "http://localhost:8081/" | jq . || curl -s "http://localhost:8081/"
    
    echo -e "\nAPI Status:"
    curl -s "http://localhost:8081/api/v1/status" | jq . || curl -s "http://localhost:8081/api/v1/status"
else
    warning "curl not available, skipping endpoint tests"
fi

# Logging finale
log "📊 Staging Deployment Summary:"
echo "Environment: $ENVIRONMENT"
echo "Compose File: $COMPOSE_FILE"
echo "Health Check URL: $HEALTH_CHECK_URL"
echo "Container Status:"
docker-compose -f "$COMPOSE_FILE" ps

# Resource usage check
log "📈 Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" $(docker-compose -f "$COMPOSE_FILE" ps -q) || warning "Could not get resource stats"

# Cleanup delle immagini vecchie (mantieni ultime 3)
log "Cleaning up old images..."
docker images "docker.io/aipioppi/ice-pulse-api" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | tail -n +2 | sort -k4 -r | tail -n +4 | awk '{print $3}' | xargs -r docker rmi || warning "Old image cleanup failed"

log "🎉 Staging deployment completed successfully!"
echo -e "${BLUE}🌐 Staging environment is ready at: http://localhost:8081${NC}"
echo -e "${BLUE}📊 Nginx proxy available at: http://localhost${NC}"

# Final health verification
sleep 5
if curl -f -s --max-time 10 "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
    log "✅ Final health check: PASSED"
else
    warning "⚠️ Final health check: Application may still be starting up"
fi