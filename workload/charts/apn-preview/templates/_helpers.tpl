{{/*
Expand the name of the chart.
*/}}
{{- define "apn-preview.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "apn-preview.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "apn-pr-%v" .Values.pr | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Host domain for the PR preview.
*/}}
{{- define "apn-preview.host" -}}
{{- printf "apn-pr-%v.%s" .Values.pr .Values.domainSuffix }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "apn-preview.labels" -}}
helm.sh/chart: {{ include "apn-preview.name" . }}
app.kubernetes.io/name: {{ include "apn-preview.name" . }}
app.kubernetes.io/instance: {{ include "apn-preview.fullname" . }}
app.kubernetes.io/part-of: apn
pr: {{ .Values.pr | quote }}
{{- end }}
