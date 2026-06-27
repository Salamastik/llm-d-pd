{{- define "minimax-m2p5-precise-pd.httpRouteName" -}}
{{- if .Values.httpRoute.nameOverride -}}
{{- .Values.httpRoute.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "minimax-m2p5-precise-pd.gatewayName" -}}
{{- if .Values.infra.gateway.fullnameOverride -}}
{{- .Values.infra.gateway.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "inference-gateway" .Values.infra.gateway.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
