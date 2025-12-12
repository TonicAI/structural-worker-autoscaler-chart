{{/*
Expand the name of the chart.
*/}}
{{- define "structural-worker-autoscaler.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "structural-worker-autoscaler.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "structural-worker-autoscaler.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "structural-worker-autoscaler.labels" -}}
helm.sh/chart: {{ include "structural-worker-autoscaler.chart" . }}
{{ include "structural-worker-autoscaler.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "structural-worker-autoscaler.selectorLabels" -}}
app.kubernetes.io/name: {{ include "structural-worker-autoscaler.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "structural-worker-autoscaler.serviceAccountName" -}}
{{- if .Values.operator.serviceAccount.create }}
{{- default (include "structural-worker-autoscaler.fullname" .) .Values.operator.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.operator.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Create the name of the rbac resources
*/}}
{{- define "structural-worker-autoscaler.rbac.name" -}}
{{- if .Values.operator.rbac.create }}
{{- default (include "structural-worker-autoscaler.fullname" .) .Values.operator.rbac.name }}
{{- else }}
{{- default "default" .Values.operator.rbac.name }}
{{- end }}
{{- end }}

{{- define "structural-worker-autoscaler.rbac.roleKind" -}}
{{- if eq .Values.operator.configuration.scope "namespace" -}}
Role
{{- else if eq .Values.operator.configuration.scope "cluster" -}}
ClusterRole
{{- else }}
{{ fail (printf "Unknown operator scope %q" .Values.operator.configuration.scope) }}
{{- end }}
{{- end }}


{{- define "structural-worker-autoscaler.rbac.roleBindingKind" -}}
{{- include "structural-worker-autoscaler.rbac.roleKind" . }}Binding
{{- end }}

{{- define "structural-worker-autoscaler.imagePullSecrets.list" -}}
{{- range $secret := . }}
- name: {{ $secret.name }}
{{- end }}
{{- end }}

{{- define "structural-worker-autoscaler.imagePullSecrets.create" -}}
{{- $top := first . }}
{{- $secret := index . 1 }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $secret.name }}
  namespace: {{ $top.Release.Namespace }}
data:
  .dockerconfigjson: {{ $secret.value }}
type: kubernetes.io/dockerconfigjson
{{- end }}

{{- define "structural-worker-autoscaler.fullname-with" -}}
{{- $top := first . }}
{{- $name := index . 1 }}
{{- printf "%s-%s" (include "structural-worker-autoscaler.fullname" $top) $name | trunc 63 | trimSuffix "-" }}
{{- end }}