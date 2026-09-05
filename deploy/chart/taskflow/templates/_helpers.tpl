{{- define "taskflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "taskflow.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "taskflow.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "taskflow.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "taskflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "taskflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "taskflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "taskflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "taskflow.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "taskflow.image" -}}
{{- if .Values.image.digest -}}
{{ printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end -}}
{{- end }}

{{- define "taskflow.postgresqlImage" -}}
{{- if .Values.postgresql.image.digest -}}
{{ printf "%s@%s" .Values.postgresql.image.repository .Values.postgresql.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.postgresql.image.repository .Values.postgresql.image.tag }}
{{- end -}}
{{- end }}

{{- define "taskflow.databaseEnv" -}}
- name: DB_HOST
  value: {{ include "taskflow.fullname" . }}-postgresql
- name: DB_PORT
  value: "5432"
- name: DB_NAME
  value: {{ .Values.postgresql.database | quote }}
- name: DB_USER
  value: {{ .Values.postgresql.username | quote }}
- name: DB_SSLMODE
  value: disable
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.existingSecret }}
      key: {{ .Values.postgresql.passwordKey }}
{{- end }}

{{- define "taskflow.containerSecurityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: {{ .Values.podSecurity.runAsUser }}
runAsGroup: {{ .Values.podSecurity.runAsGroup }}
seccompProfile:
  type: RuntimeDefault
{{- end }}
