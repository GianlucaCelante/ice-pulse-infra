{{/* Nome semplice del chart */}}
{{- define "hub-central.name" -}}
hub-central
{{- end }}

{{/* Nome completo: <release>-hub-central */}}
{{- define "hub-central.fullname" -}}
{{ printf "%s-%s" .Release.Name (include "hub-central.name" .) }}
{{- end }}

{{/* Label standard applicate a ogni resource */}}
{{- define "hub-central.labels" -}}
app.kubernetes.io/name: {{ include "hub-central.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
