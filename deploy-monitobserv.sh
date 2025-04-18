#!/bin/bash
#
# Script de Instalación y Configuración de Monitoreo y Observabilidad
# Para la Plataforma Centralizada de Información
# Compatible con Ubuntu 24.04 LTS
#

set -e

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
BASE_DIR="/opt/central-platform"
K8S_DIR="$BASE_DIR/k8s"
MONITORING_DIR="$K8S_DIR/monitoring"
SCRIPTS_DIR="$BASE_DIR/scripts/monitoring"
NAMESPACE="central-platform"

# Función para imprimir mensajes
log() {
  local msg="$1"
  local level="${2:-INFO}"
  
  case $level in
    "INFO") echo -e "[${GREEN}INFO${NC}] $msg" ;;
    "WARN") echo -e "[${YELLOW}WARN${NC}] $msg" ;;
    "ERROR") echo -e "[${RED}ERROR${NC}] $msg" ;;
    *) echo -e "[${BLUE}$level${NC}] $msg" ;;
  esac
}

# Función para verificar y crear directorios
create_directories() {
  log "Creando estructura de directorios..."
  
  # Crear directorio base si no existe
  mkdir -p "$BASE_DIR"
  
  # Crear estructura de directorios para Kubernetes
  mkdir -p "$MONITORING_DIR/prometheus"
  mkdir -p "$MONITORING_DIR/grafana"
  mkdir -p "$MONITORING_DIR/alertmanager"
  mkdir -p "$MONITORING_DIR/loki"
  mkdir -p "$MONITORING_DIR/promtail"
  mkdir -p "$MONITORING_DIR/tempo"
  mkdir -p "$MONITORING_DIR/kube-state-metrics"
  mkdir -p "$MONITORING_DIR/node-exporter"
  
  # Crear directorios para scripts
  mkdir -p "$SCRIPTS_DIR/backup"
  mkdir -p "$SCRIPTS_DIR/dashboards"
  mkdir -p "$SCRIPTS_DIR/alerts"
  
  log "Estructura de directorios creada correctamente" "SUCCESS"
}

# Función para crear namespace
create_namespace() {
  log "Creando namespace para monitoreo: $NAMESPACE"
  
  cat > "$K8S_DIR/namespace.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: central-platform
  labels:
    name: central-platform
    purpose: centralized-platform
EOF
  
  log "Archivo de namespace creado en $K8S_DIR/namespace.yaml"
}

# Función para crear configuración de Prometheus
create_prometheus_configs() {
  log "Creando configuración de Prometheus..."
  
  # ConfigMap para Prometheus
  cat > "$MONITORING_DIR/prometheus/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        monitor: 'central-platform-monitor'

    alerting:
      alertmanagers:
      - static_configs:
        - targets:
          - alertmanager:9093

    rule_files:
      - "/etc/prometheus/rules/*.yaml"

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
        - targets: ['localhost:9090']

      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
        - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
          action: keep
          regex: default;kubernetes;https

      - job_name: 'kubernetes-nodes'
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node
        relabel_configs:
        - action: labelmap
          regex: __meta_kubernetes_node_label_(.+)
        - target_label: __address__
          replacement: kubernetes.default.svc:443
        - source_labels: [__meta_kubernetes_node_name]
          regex: (.+)
          target_label: __metrics_path__
          replacement: /api/v1/nodes/${1}/proxy/metrics

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name

      - job_name: 'kubernetes-service-endpoints'
        kubernetes_sd_configs:
        - role: endpoints
        relabel_configs:
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
          action: replace
          target_label: __scheme__
          regex: (https?)
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
          action: replace
          target_label: __address__
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
        - action: labelmap
          regex: __meta_kubernetes_service_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_service_name]
          action: replace
          target_label: kubernetes_name

  recording_rules.yaml: |
    groups:
    - name: central-platform-recording-rules
      rules:
      - record: job:node_cpu_seconds:avg_idle
        expr: avg by(job, instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
      - record: job:node_memory_MemFree_bytes:avg
        expr: avg by(job, instance) (node_memory_MemFree_bytes)
EOF

  # Alert Rules para Prometheus
  cat > "$MONITORING_DIR/prometheus/alerts.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alerts
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
data:
  node_alerts.yaml: |
    groups:
    - name: node-alerts
      rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 85% for 5 minutes on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 85% for 5 minutes on {{ $labels.instance }}"

      - alert: HighDiskUsage
        expr: 100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"}) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage on {{ $labels.instance }}"
          description: "Disk usage is above 85% for 5 minutes on {{ $labels.instance }}"

  app_alerts.yaml: |
    groups:
    - name: app-alerts
      rules:
      - alert: HighErrorRate
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100 > 5
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High HTTP error rate"
          description: "Error rate is above 5% for 2 minutes (current value: {{ $value }}%)"

      - alert: APIHighLatency
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{handler!="prometheus"}[5m])) by (le, handler)) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High API latency on {{ $labels.handler }}"
          description: "95th percentile latency is above 2 seconds for 5 minutes on {{ $labels.handler }}"

      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "{{ $labels.job }} service on {{ $labels.instance }} has been down for more than 1 minute"
EOF

  # StatefulSet para Prometheus
  cat > "$MONITORING_DIR/prometheus/statefulset.yaml" << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
spec:
  serviceName: prometheus
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
        component: monitoring
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.1
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        - "--storage.tsdb.path=/prometheus"
        - "--storage.tsdb.retention.time=15d"
        - "--web.console.libraries=/etc/prometheus/console_libraries"
        - "--web.console.templates=/etc/prometheus/consoles"
        - "--web.enable-lifecycle"
        - "--web.enable-admin-api"
        ports:
        - containerPort: 9090
          name: http
        readinessProbe:
          httpGet:
            path: /-/ready
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 30
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 30
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
          limits:
            cpu: 1000m
            memory: 4Gi
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus/prometheus.yml
          subPath: prometheus.yml
        - name: prometheus-rules
          mountPath: /etc/prometheus/rules/node_alerts.yaml
          subPath: node_alerts.yaml
        - name: prometheus-rules
          mountPath: /etc/prometheus/rules/app_alerts.yaml
          subPath: app_alerts.yaml
        - name: prometheus-storage
          mountPath: /prometheus
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-rules
        configMap:
          name: prometheus-alerts
  volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 50Gi
EOF

  # Service para Prometheus
  cat > "$MONITORING_DIR/prometheus/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:
  type: ClusterIP
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
    name: http
  selector:
    app: prometheus
EOF

  # ServiceAccount para Prometheus
  cat > "$MONITORING_DIR/prometheus/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
  labels:
    app: prometheus
    component: monitoring
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources:
  - configmaps
  verbs: ["get"]
- apiGroups: ["extensions"]
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
  labels:
    app: prometheus
    component: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: central-platform
EOF

  log "Configuración de Prometheus creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Grafana
create_grafana_configs() {
  log "Creando configuración de Grafana..."
  
  # ConfigMap para Grafana
  cat > "$MONITORING_DIR/grafana/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
data:
  grafana.ini: |
    [auth]
    disable_login_form = false
    oauth_auto_login = false
    
    [auth.anonymous]
    enabled = false
    
    [auth.basic]
    enabled = true
    
    [server]
    root_url = https://grafana.central-platform.local
    
    [smtp]
    enabled = true
    host = smtp.central-platform.local:587
    user = grafana@central-platform.local
    password = grafana_smtp_password
    from_address = grafana@central-platform.local
    from_name = Grafana Alert
    
    [dashboards]
    versions_to_keep = 20
    
    [users]
    allow_sign_up = false
    auto_assign_org = true
    auto_assign_org_role = Editor
    
    [security]
    admin_user = admin
    disable_gravatar = true
    cookie_secure = true
    
    [metrics]
    enabled = true
    
    [snapshots]
    external_enabled = false
    
    [alerting]
    enabled = true
    
    [explore]
    enabled = true

  datasources.yaml: |
    apiVersion: 1
    
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus:9090
      isDefault: true
      editable: false
    
    - name: Loki
      type: loki
      access: proxy
      url: http://loki:3100
      editable: false
    
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo:3200
      editable: false
      uid: tempo
      jsonData:
        httpMethod: GET
        tracesToLogs:
          datasourceUid: loki
          tags: ['job', 'instance', 'pod', 'namespace']
          mappedTags: [{ key: 'service.name', value: 'service' }]
          mapTagNamesEnabled: true
          spanStartTimeShift: '-1h'
          spanEndTimeShift: '1h'
          filterByTraceID: true
          filterBySpanID: true
EOF

  # Dashboard provisioning
  cat > "$MONITORING_DIR/grafana/dashboard-provisioning.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provisioning
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
data:
  dashboards.yaml: |
    apiVersion: 1
    
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards
EOF

  # Default dashboards
  cat > "$MONITORING_DIR/grafana/dashboards-configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
data:
  kubernetes-overview.json: |
    {
      "annotations": {
        "list": []
      },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 1,
      "id": 1,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "smooth",
                "lineWidth": 2,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "red",
                    "value": 80
                  }
                ]
              },
              "unit": "percent"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 0,
            "y": 0
          },
          "id": 1,
          "options": {
            "legend": {
              "calcs": ["mean", "max"],
              "displayMode": "table",
              "placement": "right",
              "showLegend": true
            },
            "tooltip": {
              "mode": "multi",
              "sort": "none"
            }
          },
          "pluginVersion": "9.3.0",
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "prometheus"
              },
              "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
              "interval": "",
              "legendFormat": "{{instance}}",
              "refId": "A"
            }
          ],
          "title": "CPU Usage",
          "type": "timeseries"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "smooth",
                "lineWidth": 2,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  },
                  {
                    "color": "red",
                    "value": 80
                  }
                ]
              },
              "unit": "percent"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 12,
            "y": 0
          },
          "id": 2,
          "options": {
            "legend": {
              "calcs": ["mean", "max"],
              "displayMode": "table",
              "placement": "right",
              "showLegend": true
            },
            "tooltip": {
              "mode": "multi",
              "sort": "none"
            }
          },
          "pluginVersion": "9.3.0",
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "prometheus"
              },
              "expr": "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
              "interval": "",
              "legendFormat": "{{instance}}",
              "refId": "A"
            }
          ],
          "title": "Memory Usage",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["kubernetes", "nodes"],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-1h",
        "to": "now"
      },
      "timepicker": {},
      "timezone": "",
      "title": "Kubernetes Overview",
      "uid": "kubernetes-overview",
      "version": 1,
      "weekStart": ""
    }

  application-metrics.json: |
    {
      "annotations": {
        "list": []
      },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 1,
      "id": 2,
      "links": [],
      "liveNow": false,
      "panels": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "smooth",
                "lineWidth": 2,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              },
              "unit": "reqps"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 0,
            "y": 0
          },
          "id": 1,
          "options": {
            "legend": {
              "calcs": ["mean", "max"],
              "displayMode": "table",
              "placement": "right",
              "showLegend": true
            },
            "tooltip": {
              "mode": "multi",
              "sort": "none"
            }
          },
          "pluginVersion": "9.3.0",
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "prometheus"
              },
              "expr": "sum(rate(http_requests_total[5m])) by (handler)",
              "interval": "",
              "legendFormat": "{{handler}}",
              "refId": "A"
            }
          ],
          "title": "HTTP Request Rate",
          "type": "timeseries"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "fieldConfig": {
            "defaults": {
              "color": {
                "mode": "palette-classic"
              },
              "custom": {
                "axisCenteredZero": false,
                "axisColorMode": "text",
                "axisLabel": "",
                "axisPlacement": "auto",
                "barAlignment": 0,
                "drawStyle": "line",
                "fillOpacity": 10,
                "gradientMode": "none",
                "hideFrom": {
                  "legend": false,
                  "tooltip": false,
                  "viz": false
                },
                "lineInterpolation": "smooth",
                "lineWidth": 2,
                "pointSize": 5,
                "scaleDistribution": {
                  "type": "linear"
                },
                "showPoints": "never",
                "spanNulls": false,
                "stacking": {
                  "group": "A",
                  "mode": "none"
                },
                "thresholdsStyle": {
                  "mode": "off"
                }
              },
              "mappings": [],
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  {
                    "color": "green",
                    "value": null
                  }
                ]
              },
              "unit": "s"
            },
            "overrides": []
          },
          "gridPos": {
            "h": 8,
            "w": 12,
            "x": 12,
            "y": 0
          },
          "id": 2,
          "options": {
            "legend": {
              "calcs": ["mean", "max"],
              "displayMode": "table",
              "placement": "right",
              "showLegend": true
            },
            "tooltip": {
              "mode": "multi",
              "sort": "none"
            }
          },
          "pluginVersion": "9.3.0",
          "targets": [
            {
              "datasource": {
                "type": "prometheus",
                "uid": "prometheus"
              },
              "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler))",
              "interval": "",
              "legendFormat": "{{handler}} - p95",
              "refId": "A"
            }
          ],
          "title": "HTTP Request Latency (p95)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["application", "metrics"],
      "templating": {
        "list": []
      },
      "time": {
        "from": "now-1h",
        "to": "now"
      },
      "timepicker": {},
      "timezone": "",
      "title": "Application Metrics",
      "uid": "application-metrics",
      "version": 1,
      "weekStart": ""
    }
EOF

  # Deployment para Grafana
  cat > "$MONITORING_DIR/grafana/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
        component: monitoring
    spec:
      serviceAccountName: grafana
      securityContext:
        fsGroup: 472
        runAsUser: 472
      containers:
      - name: grafana
        image: grafana/grafana:10.2.3
        ports:
        - name: http
          containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-credentials
              key: admin-password
        - name: GF_INSTALL_PLUGINS
          value: "grafana-piechart-panel,grafana-worldmap-panel,grafana-clock-panel"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        - name: grafana-config
          mountPath: /etc/grafana/grafana.ini
          subPath: grafana.ini
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources/datasources.yaml
          subPath: datasources.yaml
        - name: grafana-dashboards-provisioning
          mountPath: /etc/grafana/provisioning/dashboards/dashboards.yaml
          subPath: dashboards.yaml
        - name: grafana-dashboards
          mountPath: /var/lib/grafana/dashboards
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
        livenessProbe:
          failureThreshold: 10
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 60
          timeoutSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 60
          timeoutSeconds: 30
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-storage
      - name: grafana-config
        configMap:
          name: grafana-config
      - name: grafana-datasources
        configMap:
          name: grafana-config
      - name: grafana-dashboards-provisioning
        configMap:
          name: grafana-dashboard-provisioning
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboards
EOF

  # Service para Grafana
  cat > "$MONITORING_DIR/grafana/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
spec:
  type: ClusterIP
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
    name: http
  selector:
    app: grafana
EOF

  # PVC para Grafana
  cat > "$MONITORING_DIR/grafana/pvc.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

  # ServiceAccount para Grafana
  cat > "$MONITORING_DIR/grafana/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
EOF

  # Secret para Grafana (con password placeholder que debe ser cambiado)
  cat > "$MONITORING_DIR/grafana/secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: grafana-credentials
  namespace: central-platform
  labels:
    app: grafana
    component: monitoring
type: Opaque
data:
  admin-password: YWRtaW4xMjM0NQ==  # admin12345 (cambiar en producción)
EOF

  log "Configuración de Grafana creada exitosamente" "SUCCESS"
}

# Función para crear configuración de AlertManager
create_alertmanager_configs() {
  log "Creando configuración de AlertManager..."
  
  # ConfigMap para AlertManager
  cat > "$MONITORING_DIR/alertmanager/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: central-platform
  labels:
    app: alertmanager
    component: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
      smtp_from: 'alertmanager@central-platform.local'
      smtp_smarthost: 'smtp.central-platform.local:587'
      smtp_auth_username: 'alertmanager'
      smtp_auth_password: 'alertmanager_password'
      smtp_require_tls: true

    templates:
      - '/etc/alertmanager/templates/*.tmpl'

    route:
      group_by: ['alertname', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'email-notifications'
      routes:
      - match:
          severity: critical
        receiver: 'critical-alerts'
        continue: true
      - match:
          severity: warning
        receiver: 'warning-alerts'

    receivers:
    - name: 'email-notifications'
      email_configs:
      - to: 'alerts@central-platform.local'
        send_resolved: true

    - name: 'critical-alerts'
      email_configs:
      - to: 'critical-alerts@central-platform.local'
        send_resolved: true

    - name: 'warning-alerts'
      email_configs:
      - to: 'warning-alerts@central-platform.local'
        send_resolved: true

  alert.tmpl: |
    {{ define "email.default.subject" }}[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}{{ end }}
    
    {{ define "email.default.html" }}
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>{{ template "email.default.subject" . }}</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          margin: 0;
          padding: 20px;
          color: #333;
        }
        h2 {
          color: {{ if eq .Status "firing" }}#cc0000{{ else }}#009900{{ end }};
        }
        .alert {
          background-color: #f5f5f5;
          border-left: 5px solid {{ if eq .Status "firing" }}#cc0000{{ else }}#009900{{ end }};
          padding: 15px;
          margin-bottom: 15px;
        }
        .label {
          font-weight: bold;
        }
        .value {
          margin-left: 10px;
        }
        .table {
          width: 100%;
          border-collapse: collapse;
        }
        .table th, .table td {
          text-align: left;
          padding: 8px;
          border-bottom: 1px solid #ddd;
        }
        .footer {
          margin-top: 20px;
          font-size: 0.8em;
          color: #666;
        }
      </style>
    </head>
    <body>
      <h2>{{ .Status | toUpper }}: {{ .GroupLabels.alertname }}</h2>
      
      <p>
        <span class="label">Status:</span>
        <span class="value">{{ .Status | toUpper }}</span>
      </p>
      
      {{ range .Alerts }}
      <div class="alert">
        <p><strong>Alert:</strong> {{ .Annotations.summary }}</p>
        <p><strong>Description:</strong> {{ .Annotations.description }}</p>
        <p><strong>Severity:</strong> {{ .Labels.severity }}</p>
        <p><strong>Started:</strong> {{ .StartsAt }}</p>
        {{ if .EndsAt }}
          <p><strong>Ended:</strong> {{ .EndsAt }}</p>
        {{ end }}
        
        <h4>Labels:</h4>
        <table class="table">
          <tr>
            <th>Label</th>
            <th>Value</th>
          </tr>
          {{ range .Labels.SortedPairs }}
          <tr>
            <td>{{ .Name }}</td>
            <td>{{ .Value }}</td>
          </tr>
          {{ end }}
        </table>
      </div>
      {{ end }}
      
      <div class="footer">
        Sent by AlertManager from Central Platform
      </div>
    </body>
    </html>
    {{ end }}
EOF

  # Deployment para AlertManager
  cat > "$MONITORING_DIR/alertmanager/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: central-platform
  labels:
    app: alertmanager
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
        component: monitoring
    spec:
      serviceAccountName: alertmanager
      containers:
      - name: alertmanager
        image: prom/alertmanager:v0.25.0
        args:
        - "--config.file=/etc/alertmanager/alertmanager.yml"
        - "--storage.path=/alertmanager"
        ports:
        - containerPort: 9093
          name: http
        volumeMounts:
        - name: alertmanager-config
          mountPath: /etc/alertmanager/alertmanager.yml
          subPath: alertmanager.yml
        - name: alertmanager-templates
          mountPath: /etc/alertmanager/templates/alert.tmpl
          subPath: alert.tmpl
        - name: alertmanager-storage
          mountPath: /alertmanager
        resources:
          limits:
            cpu: 100m
            memory: 256Mi
          requests:
            cpu: 50m
            memory: 128Mi
        readinessProbe:
          httpGet:
            path: /-/ready
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 30
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 30
      volumes:
      - name: alertmanager-config
        configMap:
          name: alertmanager-config
      - name: alertmanager-templates
        configMap:
          name: alertmanager-config
      - name: alertmanager-storage
        emptyDir: {}
EOF

  # Service para AlertManager
  cat > "$MONITORING_DIR/alertmanager/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: central-platform
  labels:
    app: alertmanager
    component: monitoring
spec:
  type: ClusterIP
  ports:
  - port: 9093
    targetPort: 9093
    protocol: TCP
    name: http
  selector:
    app: alertmanager
EOF

  # ServiceAccount para AlertManager
  cat > "$MONITORING_DIR/alertmanager/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: alertmanager
  namespace: central-platform
  labels:
    app: alertmanager
    component: monitoring
EOF

  log "Configuración de AlertManager creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Loki
create_loki_configs() {
  log "Creando configuración de Loki..."
  
  # ConfigMap para Loki
  cat > "$MONITORING_DIR/loki/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: central-platform
  labels:
    app: loki
    component: monitoring
data:
  loki.yaml: |
    auth_enabled: false

    server:
      http_listen_port: 3100
      grpc_listen_port: 9096

    common:
      path_prefix: /data
      storage:
        filesystem:
          chunks_directory: /data/chunks
          rules_directory: /data/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory

    schema_config:
      configs:
        - from: 2023-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v12
          index:
            prefix: index_
            period: 24h

    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      max_entries_limit_per_query: 5000

    compactor:
      working_directory: /data/compactor
      compaction_interval: 5m
      retention_enabled: true
      retention_delete_delay: 2h
      retention_delete_worker_count: 150
      shared_store: filesystem

    ruler:
      storage:
        type: local
        local:
          directory: /data/rules
      ring:
        kvstore:
          store: inmemory
      rule_path: /data/rules
      alertmanager_url: http://alertmanager:9093
      enable_alertmanager_v2: true
      enable_api: true
EOF

  # StatefulSet para Loki
  cat > "$MONITORING_DIR/loki/statefulset.yaml" << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: central-platform
  labels:
    app: loki
    component: monitoring
spec:
  serviceName: loki
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
        component: monitoring
    spec:
      serviceAccountName: loki
      securityContext:
        fsGroup: 10001
        runAsGroup: 10001
        runAsNonRoot: true
        runAsUser: 10001
      containers:
      - name: loki
        image: grafana/loki:2.9.2
        args:
        - "-config.file=/etc/loki/loki.yaml"
        ports:
        - name: http
          containerPort: 3100
        - name: grpc
          containerPort: 9096
        volumeMounts:
        - name: loki-config
          mountPath: /etc/loki
        - name: loki-data
          mountPath: /data
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 1
        livenessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 1
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 512Mi
      volumes:
      - name: loki-config
        configMap:
          name: loki-config
  volumeClaimTemplates:
  - metadata:
      name: loki-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 50Gi
EOF

  # Service para Loki
  cat > "$MONITORING_DIR/loki/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: central-platform
  labels:
    app: loki
    component: monitoring
spec:
  type: ClusterIP
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
    name: http
  - port: 9096
    targetPort: 9096
    protocol: TCP
    name: grpc
  selector:
    app: loki
EOF

  # ServiceAccount para Loki
  cat > "$MONITORING_DIR/loki/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: central-platform
  labels:
    app: loki
    component: monitoring
EOF

  log "Configuración de Loki creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Promtail
create_promtail_configs() {
  log "Creando configuración de Promtail..."
  
  # ConfigMap para Promtail
  cat > "$MONITORING_DIR/promtail/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: central-platform
  labels:
    app: promtail
    component: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0

    positions:
      filename: /run/promtail/positions.yaml

    clients:
      - url: http://loki:3100/loki/api/v1/push

    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_controller_name]
            regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
            action: replace
            target_label: __tmp_controller_name
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name, __meta_kubernetes_pod_label_app, __tmp_controller_name, __meta_kubernetes_pod_name]
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: app
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_component, __meta_kubernetes_pod_label_component]
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: component
          - source_labels: [__meta_kubernetes_pod_node_name]
            action: replace
            target_label: node_name
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_container_name]
            action: replace
            target_label: container
          - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance]
            regex: (.+)
            action: replace
            target_label: instance
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_pod_uid, __meta_kubernetes_pod_container_name]
            action: replace
            target_label: uid
            separator: "_"
            replacement: "$1"
          - action: replace
            source_labels: [ __meta_kubernetes_pod_container_name ]
            target_label: container
        pipeline_stages:
          - cri: {}
EOF

  # DaemonSet para Promtail
  cat > "$MONITORING_DIR/promtail/daemonset.yaml" << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: central-platform
  labels:
    app: promtail
    component: monitoring
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
        component: monitoring
    spec:
      serviceAccountName: promtail
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: promtail
        image: grafana/promtail:2.9.2
        args:
        - "-config.file=/etc/promtail/promtail.yaml"
        env:
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        ports:
        - containerPort: 9080
          name: http-metrics
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: run
          mountPath: /run/promtail
        - name: containers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
        securityContext:
          readOnlyRootFilesystem: true
          runAsUser: 0
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: run
        hostPath:
          path: /run/promtail
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
      - name: pods
        hostPath:
          path: /var/log/pods
EOF

  # ServiceAccount para Promtail
  cat > "$MONITORING_DIR/promtail/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail
  namespace: central-platform
  labels:
    app: promtail
    component: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail
  labels:
    app: promtail
    component: monitoring
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail
  labels:
    app: promtail
    component: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail
subjects:
- kind: ServiceAccount
  name: promtail
  namespace: central-platform
EOF

  log "Configuración de Promtail creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Tempo
create_tempo_configs() {
  log "Creando configuración de Tempo..."
  
  # ConfigMap para Tempo
  cat > "$MONITORING_DIR/tempo/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: central-platform
  labels:
    app: tempo
    component: monitoring
data:
  tempo.yaml: |
    auth_enabled: false

    server:
      http_listen_port: 3200

    distributor:
      receivers:
        jaeger:
          protocols:
            thrift_http:
              endpoint: 0.0.0.0:14268
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
        zipkin:
          endpoint: 0.0.0.0:9411

    ingester:
      max_block_duration: 5m

    compactor:
      compaction:
        block_retention: 48h

    storage:
      trace:
        backend: local
        local:
          path: /var/tempo/traces
        wal:
          path: /var/tempo/wal

    overrides:
      metrics_generator:
        processors:
          - service-graphs
          - span-metrics
EOF

  # Deployment para Tempo
  cat > "$MONITORING_DIR/tempo/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: central-platform
  labels:
    app: tempo
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
        component: monitoring
    spec:
      serviceAccountName: tempo
      containers:
      - name: tempo
        image: grafana/tempo:2.3.0
        args:
        - "-config.file=/etc/tempo/tempo.yaml"
        ports:
        - name: http
          containerPort: 3200
        - name: grpc-otlp
          containerPort: 4317
        - name: http-otlp
          containerPort: 4318
        - name: jaeger-thrift
          containerPort: 14268
        - name: zipkin
          containerPort: 9411
        volumeMounts:
        - name: tempo-config
          mountPath: /etc/tempo
        - name: tempo-data
          mountPath: /var/tempo
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 30
          timeoutSeconds: 1
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 512Mi
      volumes:
      - name: tempo-config
        configMap:
          name: tempo-config
      - name: tempo-data
        persistentVolumeClaim:
          claimName: tempo-data
EOF

  # Service para Tempo
  cat > "$MONITORING_DIR/tempo/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: central-platform
  labels:
    app: tempo
    component: monitoring
spec:
  type: ClusterIP
  ports:
  - port: 3200
    targetPort: 3200
    protocol: TCP
    name: http
  - port: 4317
    targetPort: 4317
    protocol: TCP
    name: grpc-otlp
  - port: 4318
    targetPort: 4318
    protocol: TCP
    name: http-otlp
  - port: 14268
    targetPort: 14268
    protocol: TCP
    name: jaeger-thrift
  - port: 9411
    targetPort: 9411
    protocol: TCP
    name: zipkin
  selector:
    app: tempo
EOF

  # PVC para Tempo
  cat > "$MONITORING_DIR/tempo/pvc.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tempo-data
  namespace: central-platform
  labels:
    app: tempo
    component: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
EOF

  # ServiceAccount para Tempo
  cat > "$MONITORING_DIR/tempo/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tempo
  namespace: central-platform
  labels:
    app: tempo
    component: monitoring
EOF

  log "Configuración de Tempo creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Node Exporter
create_node_exporter_configs() {
  log "Creando configuración de Node Exporter..."
  
  # DaemonSet para Node Exporter
  cat > "$MONITORING_DIR/node-exporter/daemonset.yaml" << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: central-platform
  labels:
    app: node-exporter
    component: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
        component: monitoring
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9100"
    spec:
      serviceAccountName: node-exporter
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.6.1
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/host/root
        - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)
        ports:
        - containerPort: 9100
          protocol: TCP
          name: http
        resources:
          limits:
            cpu: 250m
            memory: 180Mi
          requests:
            cpu: 102m
            memory: 180Mi
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host/root
          readOnly: true
          mountPropagation: HostToContainer
      hostNetwork: true
      hostPID: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: root
        hostPath:
          path: /
EOF

  # Service para Node Exporter
  cat > "$MONITORING_DIR/node-exporter/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: central-platform
  labels:
    app: node-exporter
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9100"
spec:
  type: ClusterIP
  ports:
  - port: 9100
    targetPort: 9100
    protocol: TCP
    name: http
  selector:
    app: node-exporter
EOF

  # ServiceAccount para Node Exporter
  cat > "$MONITORING_DIR/node-exporter/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: node-exporter
  namespace: central-platform
  labels:
    app: node-exporter
    component: monitoring
EOF

  log "Configuración de Node Exporter creada exitosamente" "SUCCESS"
}

# Función para crear configuración de Kube State Metrics
create_kube_state_metrics_configs() {
  log "Creando configuración de Kube State Metrics..."
  
  # Deployment para Kube State Metrics
  cat > "$MONITORING_DIR/kube-state-metrics/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: central-platform
  labels:
    app: kube-state-metrics
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
        component: monitoring
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
    serviceAccountName: kube-state-metrics
      containers:
      - name: kube-state-metrics
        image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0
        ports:
        - name: http
          containerPort: 8080
        - name: telemetry
          containerPort: 8081
        readinessProbe:
          httpGet:
            path: /ready
            port: 8081
          initialDelaySeconds: 5
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          timeoutSeconds: 5
        resources:
          limits:
            cpu: 100m
            memory: 256Mi
          requests:
            cpu: 50m
            memory: 128Mi
EOF

  # Service para Kube State Metrics
  cat > "$MONITORING_DIR/kube-state-metrics/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: central-platform
  labels:
    app: kube-state-metrics
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  - port: 8081
    targetPort: 8081
    protocol: TCP
    name: telemetry
  selector:
    app: kube-state-metrics
EOF

  # ServiceAccount para Kube State Metrics
  cat > "$MONITORING_DIR/kube-state-metrics/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: central-platform
  labels:
    app: kube-state-metrics
    component: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
  labels:
    app: kube-state-metrics
    component: monitoring
rules:
- apiGroups: [""]
  resources:
  - configmaps
  - secrets
  - nodes
  - pods
  - services
  - resourcequotas
  - replicationcontrollers
  - limitranges
  - persistentvolumeclaims
  - persistentvolumes
  - namespaces
  - endpoints
  verbs: ["list", "watch"]
- apiGroups: ["apps"]
  resources:
  - statefulsets
  - daemonsets
  - deployments
  - replicasets
  verbs: ["list", "watch"]
- apiGroups: ["batch"]
  resources:
  - cronjobs
  - jobs
  verbs: ["list", "watch"]
- apiGroups: ["autoscaling"]
  resources:
  - horizontalpodautoscalers
  verbs: ["list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources:
  - ingresses
  verbs: ["list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources:
  - storageclasses
  verbs: ["list", "watch"]
- apiGroups: ["policy"]
  resources:
  - poddisruptionbudgets
  verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
  labels:
    app: kube-state-metrics
    component: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: central-platform
EOF

  log "Configuración de Kube State Metrics creada exitosamente" "SUCCESS"
}

# Función para crear script de backup de Prometheus
create_prometheus_backup_script() {
  log "Creando script de backup de Prometheus..."
  
  mkdir -p "$SCRIPTS_DIR/backup"
  
  cat > "$SCRIPTS_DIR/backup/prometheus-backup.sh" << 'EOF'
#!/bin/bash
#
# Script para realizar backup de datos de Prometheus
#

set -e

# Variables de configuración
BACKUP_DIR="/backup/prometheus"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/prometheus-backup-${DATE}.tar.gz"
NAMESPACE="central-platform"
POD_PREFIX="prometheus-0"

# Crear directorio de backup si no existe
mkdir -p "${BACKUP_DIR}"

echo "Iniciando backup de Prometheus en $(date)"

# Obtener nombre del pod
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=prometheus --no-headers | grep ${POD_PREFIX} | awk '{print $1}')

if [ -z "${POD_NAME}" ]; then
  echo "ERROR: No se encontró el pod de Prometheus"
  exit 1
fi

echo "Usando pod: ${POD_NAME}"

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Ejecutar snapshot
echo "Creando snapshot de Prometheus..."
SNAPSHOT_NAME=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot | jq -r .data.name)

if [ -z "${SNAPSHOT_NAME}" ] || [ "${SNAPSHOT_NAME}" == "null" ]; then
  echo "ERROR: No se pudo crear el snapshot"
  exit 1
fi

echo "Snapshot creado: ${SNAPSHOT_NAME}"

# Copiar snapshot al directorio temporal
echo "Copiando snapshot..."
kubectl cp ${NAMESPACE}/${POD_NAME}:/prometheus/snapshots/${SNAPSHOT_NAME}/ ${TEMP_DIR}/

# Comprimir el snapshot
echo "Comprimiendo snapshot..."
tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .

# Verificar que el backup se creó correctamente
if [ -f "${BACKUP_FILE}" ]; then
  echo "Backup completado exitosamente: ${BACKUP_FILE}"
  
  # Calcular tamaño del backup
  BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
  echo "Tamaño del backup: ${BACKUP_SIZE}"
  
  # Eliminar backups antiguos
  find "${BACKUP_DIR}" -name "prometheus-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
  echo "Backups antiguos (>${RETENTION_DAYS} días) eliminados"
else
  echo "ERROR: No se pudo crear el archivo de backup"
  exit 1
fi

echo "Proceso de backup finalizado en $(date)"
EOF

  chmod +x "$SCRIPTS_DIR/backup/prometheus-backup.sh"
  
  log "Script de backup de Prometheus creado exitosamente" "SUCCESS"
}

# Función para crear script de backup de Grafana
create_grafana_backup_script() {
  log "Creando script de backup de Grafana..."
  
  cat > "$SCRIPTS_DIR/backup/grafana-backup.sh" << 'EOF'
#!/bin/bash
#
# Script para realizar backup de datos de Grafana
#

set -e

# Variables de configuración
BACKUP_DIR="/backup/grafana"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/grafana-backup-${DATE}.tar.gz"
NAMESPACE="central-platform"
POD_PREFIX="grafana"

# Crear directorio de backup si no existe
mkdir -p "${BACKUP_DIR}"

echo "Iniciando backup de Grafana en $(date)"

# Obtener nombre del pod
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=grafana --no-headers | grep ${POD_PREFIX} | awk '{print $1}')

if [ -z "${POD_NAME}" ]; then
  echo "ERROR: No se encontró el pod de Grafana"
  exit 1
fi

echo "Usando pod: ${POD_NAME}"

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Directorios a respaldar
BACKUP_DIRS=(
  "/var/lib/grafana/dashboards"
  "/var/lib/grafana/plugins"
  "/var/lib/grafana/grafana.db"
)

# Copiar archivos del pod al directorio temporal
for DIR in "${BACKUP_DIRS[@]}"; do
  BASENAME=$(basename "${DIR}")
  echo "Copiando ${BASENAME}..."
  
  # Verificar si es un archivo o directorio
  IS_DIR=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- sh -c "[ -d ${DIR} ] && echo 'true' || echo 'false'")
  
  if [ "${IS_DIR}" == "true" ]; then
    # Es un directorio
    mkdir -p "${TEMP_DIR}/${BASENAME}"
    kubectl cp ${NAMESPACE}/${POD_NAME}:${DIR} ${TEMP_DIR}/${BASENAME}/
  else
    # Es un archivo
    kubectl cp ${NAMESPACE}/${POD_NAME}:${DIR} ${TEMP_DIR}/
  fi
done

# Comprimir los archivos
echo "Comprimiendo archivos..."
tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .

# Verificar que el backup se creó correctamente
if [ -f "${BACKUP_FILE}" ]; then
  echo "Backup completado exitosamente: ${BACKUP_FILE}"
  
  # Calcular tamaño del backup
  BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
  echo "Tamaño del backup: ${BACKUP_SIZE}"
  
  # Eliminar backups antiguos
  find "${BACKUP_DIR}" -name "grafana-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
  echo "Backups antiguos (>${RETENTION_DAYS} días) eliminados"
else
  echo "ERROR: No se pudo crear el archivo de backup"
  exit 1
fi

echo "Proceso de backup finalizado en $(date)"
EOF

  chmod +x "$SCRIPTS_DIR/backup/grafana-backup.sh"
  
  log "Script de backup de Grafana creado exitosamente" "SUCCESS"
}

# Función para crear script de backup de Loki
create_loki_backup_script() {
  log "Creando script de backup de Loki..."
  
  cat > "$SCRIPTS_DIR/backup/loki-backup.sh" << 'EOF'
#!/bin/bash
#
# Script para realizar backup de datos de Loki
#

set -e

# Variables de configuración
BACKUP_DIR="/backup/loki"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/loki-backup-${DATE}.tar.gz"
NAMESPACE="central-platform"
POD_PREFIX="loki-0"

# Crear directorio de backup si no existe
mkdir -p "${BACKUP_DIR}"

echo "Iniciando backup de Loki en $(date)"

# Obtener nombre del pod
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=loki --no-headers | grep ${POD_PREFIX} | awk '{print $1}')

if [ -z "${POD_NAME}" ]; then
  echo "ERROR: No se encontró el pod de Loki"
  exit 1
fi

echo "Usando pod: ${POD_NAME}"

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Directorios a respaldar
BACKUP_DIRS=(
  "/data/chunks"
  "/data/compactor"
  "/data/rules"
)

# Copiar archivos del pod al directorio temporal
for DIR in "${BACKUP_DIRS[@]}"; do
  BASENAME=$(basename "${DIR}")
  echo "Copiando ${BASENAME}..."
  
  # Verificar si el directorio existe en el pod
  DIR_EXISTS=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- sh -c "[ -d ${DIR} ] && echo 'true' || echo 'false'")
  
  if [ "${DIR_EXISTS}" == "true" ]; then
    mkdir -p "${TEMP_DIR}/${BASENAME}"
    kubectl cp ${NAMESPACE}/${POD_NAME}:${DIR} ${TEMP_DIR}/${BASENAME}/
  else
    echo "El directorio ${DIR} no existe en el pod, omitiendo..."
  fi
done

# Comprimir los archivos
echo "Comprimiendo archivos..."
tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .

# Verificar que el backup se creó correctamente
if [ -f "${BACKUP_FILE}" ]; then
  echo "Backup completado exitosamente: ${BACKUP_FILE}"
  
  # Calcular tamaño del backup
  BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
  echo "Tamaño del backup: ${BACKUP_SIZE}"
  
  # Eliminar backups antiguos
  find "${BACKUP_DIR}" -name "loki-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
  echo "Backups antiguos (>${RETENTION_DAYS} días) eliminados"
else
  echo "ERROR: No se pudo crear el archivo de backup"
  exit 1
fi

echo "Proceso de backup finalizado en $(date)"
EOF

  chmod +x "$SCRIPTS_DIR/backup/loki-backup.sh"
  
  log "Script de backup de Loki creado exitosamente" "SUCCESS"
}

# Función para crear script de respaldo rotativo con cron
create_backup_cron_script() {
  log "Creando script para programar backups con cron..."
  
  cat > "$SCRIPTS_DIR/backup/setup-backup-cron.sh" << 'EOF'
#!/bin/bash
#
# Script para configurar tareas cron de backup
#

set -e

# Comprobar que se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse como root"
  exit 1
fi

SCRIPTS_DIR="/opt/central-platform/scripts/monitoring/backup"
BACKUP_DIR="/backup"
LOG_DIR="/var/log/central-platform/backup"

# Crear directorios necesarios
mkdir -p "${BACKUP_DIR}/prometheus"
mkdir -p "${BACKUP_DIR}/grafana"
mkdir -p "${BACKUP_DIR}/loki"
mkdir -p "${LOG_DIR}"

# Establecer permisos
chmod 755 "${SCRIPTS_DIR}"/*.sh
chown -R root:root "${SCRIPTS_DIR}"
chmod 777 "${BACKUP_DIR}" -R
chmod 755 "${LOG_DIR}"

# Configurar crontab
echo "Configurando tareas cron para backups..."

# Crear archivo temporal
TEMP_CRON=$(mktemp)

# Obtener crontab actual
crontab -l > "${TEMP_CRON}" 2>/dev/null || true

# Eliminar entradas antiguas si existen
sed -i '/central-platform.*backup/d' "${TEMP_CRON}"

# Añadir nuevas entradas
cat >> "${TEMP_CRON}" << EOL
# Backups de la Plataforma Centralizada
0 1 * * * ${SCRIPTS_DIR}/prometheus-backup.sh > ${LOG_DIR}/prometheus-backup.log 2>&1
30 1 * * * ${SCRIPTS_DIR}/grafana-backup.sh > ${LOG_DIR}/grafana-backup.log 2>&1
0 2 * * * ${SCRIPTS_DIR}/loki-backup.sh > ${LOG_DIR}/loki-backup.log 2>&1
EOL

# Instalar la nueva crontab
crontab "${TEMP_CRON}"
rm "${TEMP_CRON}"

echo "Configuración de cron completada. Backups programados:"
echo "- Prometheus: Diariamente a la 1:00 AM"
echo "- Grafana: Diariamente a la 1:30 AM"
echo "- Loki: Diariamente a las 2:00 AM"
echo ""
echo "Los logs se guardarán en: ${LOG_DIR}"
EOF

  chmod +x "$SCRIPTS_DIR/backup/setup-backup-cron.sh"
  
  log "Script de configuración de cron para backups creado exitosamente" "SUCCESS"
}

# Función para crear scripts de gestión de dashboards
create_dashboard_management_scripts() {
  log "Creando scripts de gestión de dashboards..."
  
  mkdir -p "$SCRIPTS_DIR/dashboards"
  
  # Script para exportar dashboards
  cat > "$SCRIPTS_DIR/dashboards/export-dashboards.sh" << 'EOF'
#!/bin/bash
#
# Script para exportar dashboards de Grafana
#

set -e

# Variables
GRAFANA_URL="http://grafana:3000"
GRAFANA_API_KEY=""
OUTPUT_DIR="/opt/central-platform/scripts/monitoring/dashboards/exported"
NAMESPACE="central-platform"

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Funciones
show_help() {
  echo "Uso: $0 [opciones]"
  echo ""
  echo "Opciones:"
  echo "  -k, --api-key API_KEY    Clave de API de Grafana"
  echo "  -u, --url URL            URL de Grafana (default: http://grafana:3000)"
  echo "  -o, --output-dir DIR     Directorio de salida (default: ./exported)"
  echo "  -n, --namespace NS       Namespace de Kubernetes (default: central-platform)"
  echo "  -p, --port-forward       Usar port-forward para conectar a Grafana"
  echo "  -h, --help               Mostrar esta ayuda"
  echo ""
}

# Procesar argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--api-key)
      GRAFANA_API_KEY="$2"
      shift 2
      ;;
    -u|--url)
      GRAFANA_URL="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -p|--port-forward)
      USE_PORT_FORWARD=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Error:${NC} Opción desconocida: $1"
      show_help
      exit 1
      ;;
  esac
done

# Crear directorio de salida
mkdir -p "${OUTPUT_DIR}"

# Iniciar port-forward si es necesario
if [ "${USE_PORT_FORWARD}" = true ]; then
  echo -e "${YELLOW}Iniciando port-forward a Grafana...${NC}"
  
  # Obtener el primer pod de Grafana
  GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "${GRAFANA_POD}" ]; then
    echo -e "${RED}Error:${NC} No se encontró ningún pod de Grafana en el namespace ${NAMESPACE}"
    exit 1
  fi
  
  # Iniciar port-forward en segundo plano
  kubectl port-forward -n "${NAMESPACE}" "${GRAFANA_POD}" 3000:3000 &
  PORT_FORWARD_PID=$!
  
  # Asegurarse de matar el proceso de port-forward al salir
  trap "kill ${PORT_FORWARD_PID}" EXIT
  
  # Esperar a que el port-forward esté listo
  echo "Esperando a que el port-forward esté listo..."
  sleep 3
  
  # Actualizar URL de Grafana
  GRAFANA_URL="http://localhost:3000"
fi

# Si no se proporcionó API key, intentar obtenerla del pod
if [ -z "${GRAFANA_API_KEY}" ]; then
  echo -e "${YELLOW}No se proporcionó API key, intentando obtenerla automáticamente...${NC}"
  
  # Obtener el primer pod de Grafana si no estamos usando port-forward
  if [ "${USE_PORT_FORWARD}" != true ]; then
    GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "${GRAFANA_POD}" ]; then
      echo -e "${RED}Error:${NC} No se encontró ningún pod de Grafana en el namespace ${NAMESPACE}"
      exit 1
    fi
  fi
  
  # Obtener usuario y contraseña de admin
  ADMIN_USER="admin"
  ADMIN_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" grafana-credentials -o jsonpath="{.data.admin-password}" | base64 --decode)
  
  if [ -z "${ADMIN_PASSWORD}" ]; then
    echo -e "${RED}Error:${NC} No se pudo obtener la contraseña de administrador de Grafana"
    exit 1
  fi
  
  # Crear API key
  echo "Creando API key temporal..."
  API_KEY_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"temp-export-key","role":"Admin","secondsToLive":600}' -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${GRAFANA_URL}/api/auth/keys")
  
  GRAFANA_API_KEY=$(echo "${API_KEY_RESPONSE}" | grep -o '"key":"[^"]*' | sed 's/"key":"//')
  
  if [ -z "${GRAFANA_API_KEY}" ]; then
    echo -e "${RED}Error:${NC} No se pudo crear una API key"
    echo "Respuesta de Grafana: ${API_KEY_RESPONSE}"
    exit 1
  fi
  
  echo -e "${GREEN}API key temporal creada con éxito${NC}"
fi

# Obtener lista de dashboards
echo "Obteniendo lista de dashboards..."
DASHBOARDS_JSON=$(curl -s -H "Authorization: Bearer ${GRAFANA_API_KEY}" "${GRAFANA_URL}/api/search?type=dash-db")

# Comprobar si la respuesta es válida
if ! echo "${DASHBOARDS_JSON}" | jq . > /dev/null 2>&1; then
  echo -e "${RED}Error:${NC} No se pudo obtener la lista de dashboards"
  echo "Respuesta de Grafana: ${DASHBOARDS_JSON}"
  exit 1
fi

# Extraer UIDs de los dashboards
DASHBOARD_UIDS=$(echo "${DASHBOARDS_JSON}" | jq -r '.[] | .uid')

if [ -z "${DASHBOARD_UIDS}" ]; then
  echo -e "${YELLOW}Advertencia:${NC} No se encontraron dashboards para exportar"
  exit 0
fi

# Exportar cada dashboard
echo "Exportando dashboards..."
for UID in ${DASHBOARD_UIDS}; do
  echo -n "Exportando dashboard ${UID}... "
  
  # Obtener dashboard
  DASHBOARD_JSON=$(curl -s -H "Authorization: Bearer ${GRAFANA_API_KEY}" "${GRAFANA_URL}/api/dashboards/uid/${UID}")
  
  # Extraer título para usar como nombre de archivo
  TITLE=$(echo "${DASHBOARD_JSON}" | jq -r '.dashboard.title' | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
  
  if [ -z "${TITLE}" ] || [ "${TITLE}" = "null" ]; then
    TITLE="${UID}"
  fi
  
  # Guardar dashboard
  echo "${DASHBOARD_JSON}" | jq '.dashboard | .id = null' > "${OUTPUT_DIR}/${TITLE}-${UID}.json"
  
  echo -e "${GREEN}completado${NC}"
done

echo -e "${GREEN}Exportación de dashboards completada.${NC}"
echo "Los dashboards se han guardado en: ${OUTPUT_DIR}"
EOF

  chmod +x "$SCRIPTS_DIR/dashboards/export-dashboards.sh"
  
  # Script para importar dashboards
  cat > "$SCRIPTS_DIR/dashboards/import-dashboards.sh" << 'EOF'
#!/bin/bash
#
# Script para importar dashboards a Grafana
#

set -e

# Variables
GRAFANA_URL="http://grafana:3000"
GRAFANA_API_KEY=""
INPUT_DIR="/opt/central-platform/scripts/monitoring/dashboards/exported"
NAMESPACE="central-platform"
OVERWRITE=false

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Funciones
show_help() {
  echo "Uso: $0 [opciones] [archivos...]"
  echo ""
  echo "Opciones:"
  echo "  -k, --api-key API_KEY    Clave de API de Grafana"
  echo "  -u, --url URL            URL de Grafana (default: http://grafana:3000)"
  echo "  -i, --input-dir DIR      Directorio de entrada (default: ./exported)"
  echo "  -n, --namespace NS       Namespace de Kubernetes (default: central-platform)"
  echo "  -p, --port-forward       Usar port-forward para conectar a Grafana"
  echo "  -o, --overwrite          Sobrescribir dashboards existentes"
  echo "  -h, --help               Mostrar esta ayuda"
  echo ""
  echo "Si se especifican archivos, sólo se importarán esos archivos."
  echo "De lo contrario, se importarán todos los archivos en el directorio de entrada."
  echo ""
}

# Procesar argumentos
FILES=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--api-key)
      GRAFANA_API_KEY="$2"
      shift 2
      ;;
    -u|--url)
      GRAFANA_URL="$2"
      shift 2
      ;;
    -i|--input-dir)
      INPUT_DIR="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -p|--port-forward)
      USE_PORT_FORWARD=true
      shift
      ;;
    -o|--overwrite)
      OVERWRITE=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo -e "${RED}Error:${NC} Opción desconocida: $1"
      show_help
      exit 1
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

# Iniciar port-forward si es necesario
if [ "${USE_PORT_FORWARD}" = true ]; then
  echo -e "${YELLOW}Iniciando port-forward a Grafana...${NC}"
  
  # Obtener el primer pod de Grafana
  GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "${GRAFANA_POD}" ]; then
    echo -e "${RED}Error:${NC} No se encontró ningún pod de Grafana en el namespace ${NAMESPACE}"
    exit 1
  fi
  
  # Iniciar port-forward en segundo plano
  kubectl port-forward -n "${NAMESPACE}" "${GRAFANA_POD}" 3000:3000 &
  PORT_FORWARD_PID=$!
  
  # Asegurarse de matar el proceso de port-forward al salir
  trap "kill ${PORT_FORWARD_PID}" EXIT
  
  # Esperar a que el port-forward esté listo
  echo "Esperando a que el port-forward esté listo..."
  sleep 3
  
  # Actualizar URL de Grafana
  GRAFANA_URL="http://localhost:3000"
fi

# Si no se proporcionó API key, intentar obtenerla del pod
if [ -z "${GRAFANA_API_KEY}" ]; then
  echo -e "${YELLOW}No se proporcionó API key, intentando obtenerla automáticamente...${NC}"
  
  # Obtener el primer pod de Grafana si no estamos usando port-forward
  if [ "${USE_PORT_FORWARD}" != true ]; then
    GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=grafana -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "${GRAFANA_POD}" ]; then
      echo -e "${RED}Error:${NC} No se encontró ningún pod de Grafana en el namespace ${NAMESPACE}"
      exit 1
    fi
  fi
  
  # Obtener usuario y contraseña de admin
  ADMIN_USER="admin"
  ADMIN_PASSWORD=$(kubectl get secret -n "${NAMESPACE}" grafana-credentials -o jsonpath="{.data.admin-password}" | base64 --decode)
  
  if [ -z "${ADMIN_PASSWORD}" ]; then
    echo -e "${RED}Error:${NC} No se pudo obtener la contraseña de administrador de Grafana"
    exit 1
  fi
  
  # Crear API key
  echo "Creando API key temporal..."
  API_KEY_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"temp-import-key","role":"Admin","secondsToLive":600}' -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${GRAFANA_URL}/api/auth/keys")
  
  GRAFANA_API_KEY=$(echo "${API_KEY_RESPONSE}" | grep -o '"key":"[^"]*' | sed 's/"key":"//')
  
  if [ -z "${GRAFANA_API_KEY}" ]; then
    echo -e "${RED}Error:${NC} No se pudo crear una API key"
    echo "Respuesta de Grafana: ${API_KEY_RESPONSE}"
    exit 1
  fi
  
  echo -e "${GREEN}API key temporal creada con éxito${NC}"
fi

# Si no se especificaron archivos, importar todos los del directorio
if [ ${#FILES[@]} -eq 0 ]; then
  if [ ! -d "${INPUT_DIR}" ]; then
    echo -e "${RED}Error:${NC} El directorio ${INPUT_DIR} no existe"
    exit 1
  fi
  
  echo "Importando todos los dashboards desde ${INPUT_DIR}..."
  FILES=("${INPUT_DIR}"/*.json)
  
  if [ ${#FILES[@]} -eq 0 ] || [ ! -f "${FILES[0]}" ]; then
    echo -e "${YELLOW}Advertencia:${NC} No se encontraron archivos JSON en ${INPUT_DIR}"
    exit 0
  fi
fi

# Importar cada dashboard
for FILE in "${FILES[@]}"; do
  if [ ! -f "${FILE}" ]; then
    echo -e "${YELLOW}Advertencia:${NC} El archivo ${FILE} no existe, omitiendo..."
    continue
  fi
  
  FILENAME=$(basename "${FILE}")
  echo -n "Importando dashboard ${FILENAME}... "
  
  # Preparar payload para la importación
  TMP_FILE=$(mktemp)
  jq -n --arg dashboard "$(cat "${FILE}")" \
    --argjson overwrite $OVERWRITE \
    '{ 
      "dashboard": $dashboard | fromjson, 
      "overwrite": $overwrite,
      "folderId": 0
    }' > "${TMP_FILE}"
  
  # Importar dashboard
  RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    --data @"${TMP_FILE}" \
    "${GRAFANA_URL}/api/dashboards/db")
  
  # Limpiar
  rm "${TMP_FILE}"
  
  # Verificar respuesta
  if echo "${RESPONSE}" | grep -q "success"; then
    echo -e "${GREEN}completado${NC}"
  else
    echo -e "${RED}error${NC}"
    echo "Respuesta de Grafana: ${RESPONSE}"
  fi
done

echo -e "${GREEN}Importación de dashboards completada.${NC}"
EOF

  chmod +x "$SCRIPTS_DIR/dashboards/import-dashboards.sh"
  
  log "Scripts de gestión de dashboards creados exitosamente" "SUCCESS"
}

# Función para crear script de gestión de alertas
create_alert_management_scripts() {
  log "Creando script de gestión de alertas..."
  
  mkdir -p "$SCRIPTS_DIR/alerts"
  
  # Script para exportar alertas
  cat > "$SCRIPTS_DIR/alerts/export-alerts.sh" << 'EOF'
#!/bin/bash
#
# Script para exportar reglas de alertas de Prometheus
#

set -e

# Variables
PROMETHEUS_URL="http://prometheus:9090"
OUTPUT_DIR="/opt/central-platform/scripts/monitoring/alerts/exported"
NAMESPACE="central-platform"

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Funciones
show_help() {
  echo "Uso: $0 [opciones]"
  echo ""
  echo "Opciones:"
  echo "  -u, --url URL            URL de Prometheus (default: http://prometheus:9090)"
  echo "  -o, --output-dir DIR     Directorio de salida (default: ./exported)"
  echo "  -n, --namespace NS       Namespace de Kubernetes (default: central-platform)"
  echo "  -p, --port-forward       Usar port-forward para conectar a Prometheus"
  echo "  -h, --help               Mostrar esta ayuda"
  echo ""
}

# Procesar argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--url)
      PROMETHEUS_URL="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -p|--port-forward)
      USE_PORT_FORWARD=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Error:${NC} Opción desconocida: $1"
      show_help
      exit 1
      ;;
  esac
done

# Crear directorio de salida
mkdir -p "${OUTPUT_DIR}"

# Iniciar port-forward si es necesario
if [ "${USE_PORT_FORWARD}" = true ]; then
  echo -e "${YELLOW}Iniciando port-forward a Prometheus...${NC}"
  
  # Obtener el primer pod de Prometheus
  PROMETHEUS_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "${PROMETHEUS_POD}" ]; then
    echo -e "${RED}Error:${NC} No se encontró ningún pod de Prometheus en el namespace ${NAMESPACE}"
    exit 1
  fi
  
  # Iniciar port-forward en segundo plano
  kubectl port-forward -n "${NAMESPACE}" "${PROMETHEUS_POD}" 9090:9090 &
  PORT_FORWARD_PID=$!
  
  # Asegurarse de matar el proceso de port-forward al salir
  trap "kill ${PORT_FORWARD_PID}" EXIT
  
  # Esperar a que el port-forward esté listo
  echo "Esperando a que el port-forward esté listo..."
  sleep 3
  
  # Actualizar URL de Prometheus
  PROMETHEUS_URL="http://localhost:9090"
fi

# Obtener lista de reglas
echo "Obteniendo reglas de alertas..."
RULES_JSON=$(curl -s "${PROMETHEUS_URL}/api/v1/rules")

# Comprobar si la respuesta es válida
if ! echo "${RULES_JSON}" | jq . > /dev/null 2>&1; then
  echo -e "${RED}Error:${NC} No se pudo obtener la lista de reglas"
  echo "Respuesta de Prometheus: ${RULES_JSON}"
  exit 1
fi

# Verificar si la respuesta contiene reglas
STATUS=$(echo "${RULES_JSON}" | jq -r '.status')
if [ "${STATUS}" != "success" ]; then
  echo -e "${RED}Error:${NC} Error al obtener reglas: $(echo "${RULES_JSON}" | jq -r '.error // "Desconocido"')"
  exit 1
fi

# Extraer grupos de reglas
RULE_GROUPS=$(echo "${RULES_JSON}" | jq -r '.data.groups')

if [ "${RULE_GROUPS}" = "null" ] || [ "${RULE_GROUPS}" = "[]" ]; then
  echo -e "${YELLOW}Advertencia:${NC} No se encontraron grupos de reglas para exportar"
  exit 0
fi

# Exportar cada grupo de reglas
echo "Exportando grupos de reglas..."
echo "${RULES_JSON}" | jq '.data.groups[] | {name: .name, rules: [.rules[] | if .type == "alerting" then {alert: .name, expr: .query, for: .duration, labels: .labels, annotations: .annotations} else {record: .name, expr: .query} end]}' | jq -c '.' | while read -r GROUP; do
  GROUP_NAME=$(echo "${GROUP}" | jq -r '.name' | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
  
  echo -n "Exportando grupo de reglas ${GROUP_NAME}... "
  
  # Formatear y guardar el grupo
  echo "${GROUP}" | jq '.' > "${OUTPUT_DIR}/${GROUP_NAME}-rules.json"
  
  echo -e "${GREEN}completado${NC}"
done

# Generar archivo YAML combinado
echo "Generando archivo YAML combinado..."
YAML_FILE="${OUTPUT_DIR}/prometheus-alert-rules.yaml"

cat > "${YAML_FILE}" << EOL
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alerts
  namespace: central-platform
  labels:
    app: prometheus
    component: monitoring
data:
EOL

for JSON_FILE in "${OUTPUT_DIR}"/*-rules.json; do
  BASENAME=$(basename "${JSON_FILE}" | sed 's/-rules.json/.yaml/')
  GROUP_NAME=$(jq -r '.name' "${JSON_FILE}")
  
  echo "  ${BASENAME}: |" >> "${YAML_FILE}"
  echo "    groups:" >> "${YAML_FILE}"
  echo "    - name: ${GROUP_NAME}" >> "${YAML_FILE}"
  echo "      rules:" >> "${YAML_FILE}"
  
  # Convertir reglas JSON a YAML
  jq -r '.rules[] | if has("alert") then "      - alert: \(.alert)\n        expr: \(.expr)\n        for: \(.for)\n        labels:\n\(.labels | to_entries | map("          \(.key): \"\(.value)\"") | join("\n"))\n        annotations:\n\(.annotations | to_entries | map("          \(.key): \"\(.value)\"") | join("\n"))" else "      - record: \(.record)\n        expr: \(.expr)" end' "${JSON_FILE}" >> "${YAML_FILE}"
done

echo -e "${GREEN}Exportación de reglas de alertas completada.${NC}"
echo "Las reglas se han guardado en: ${OUTPUT_DIR}"
echo "Archivo YAML combinado: ${YAML_FILE}"
EOF

  chmod +x "$SCRIPTS_DIR/alerts/export-alerts.sh"
  
  # Script para crear alerta rápidamente
  cat > "$SCRIPTS_DIR/alerts/create-alert.sh" << 'EOF'
#!/bin/bash
#
# Script para crear rápidamente una alerta en Prometheus
#

set -e

# Variables
PROMETHEUS_URL="http://prometheus:9090"
NAMESPACE="central-platform"
USE_PORT_FORWARD=false
GROUP_NAME=""
ALERT_NAME=""
EXPRESSION=""
DURATION="5m"
SEVERITY="warning"
SUMMARY=""
DESCRIPTION=""

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Funciones
show_help() {
  echo "Uso: $0 [opciones]"
  echo ""
  echo "Opciones:"
  echo "  -u, --url URL                  URL de Prometheus (default: http://prometheus:9090)"
  echo "  -n, --namespace NS             Namespace de Kubernetes (default: central-platform)"
  echo "  -p, --port-forward             Usar port-forward para conectar a Prometheus"
  echo "  -g, --group NAME               Nombre del grupo de alertas (requerido)"
  echo "  -a, --alert NAME               Nombre de la alerta (requerido)"
  echo "  -e, --expr EXPRESSION          Expresión PromQL (requerido)"
  echo "  -d, --duration DURATION        Duración (default: 5m)"
  echo "  -s, --severity SEVERITY        Severidad (default: warning)"
  echo "  -S, --summary SUMMARY          Resumen de la alerta"
  echo "  -D, --description DESCRIPTION  Descripción de la alerta"
  echo "  -h, --help                     Mostrar esta ayuda"
  echo ""
}

# Procesar argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--url)
      PROMETHEUS_URL="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -p|--port-forward)
      USE_PORT_FORWARD=true
      shift
      ;;
    -g|--group)
      GROUP_NAME="$2"
      shift 2
      ;;
    -a|--alert)
      ALERT_NAME="$2"
      shift 2
      ;;
    -e|--expr)
      EXPRESSION="$2"
      shift 2
      ;;
    -d|--duration)
      DURATION="$2"
      shift 2
      ;;
    -s|--severity)
      SEVERITY="$2"
      shift 2
      ;;
    -S|--summary)
      SUMMARY="$2"
      shift 2
      ;;
    -D|--description)
      DESCRIPTION="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Error:${NC} Opción desconocida: $1"
      show_help
      exit 1
      ;;
  esac
done

# Verificar parámetros obligatorios
if [ -z "${GROUP_NAME}" ] || [ -z "${ALERT_NAME}" ] || [ -z "${EXPRESSION}" ]; then
  echo -e "${RED}Error:${NC} Faltan parámetros obligatorios"
  show_help
  exit 1
fi

# Si no se proporcionó un resumen, usar el nombre de la alerta
if [ -z "${SUMMARY}" ]; then
  SUMMARY="${ALERT_NAME}"
fi

# Si no se proporcionó una descripción, usar el resumen
if [ -z "${DESCRIPTION}" ]; then
  DESCRIPTION="${SUMMARY}"
fi

# Iniciar port-forward si es necesario
if [ "${USE_PORT_FORWARD}" = true ]; then
  echo -e "${YELLOW}Iniciando port-forward a Prometheus...${NC}"
  
  # Obtener el primer pod de Prometheus
  PROMETHEUS_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "${PROMETHEUS_POD}" ]; then
    echo -e "${RED}Error:${NC} No se encontró ningún pod de Prometheus en el namespace ${NAMESPACE}"
    exit 1
  fi
  
  # Iniciar port-forward en segundo plano
  kubectl port-forward -n "${NAMESPACE}" "${PROMETHEUS_POD}" 9090:9090 &
  PORT_FORWARD_PID=$!
  
  # Asegurarse de matar el proceso de port-forward al salir
  trap "kill ${PORT_FORWARD_PID}" EXIT
  
  # Esperar a que el port-forward esté listo
  echo "Esperando a que el port-forward esté listo..."
  sleep 3
  
  # Actualizar URL de Prometheus
  PROMETHEUS_URL="http://localhost:9090"
fi

# Preparar el archivo temporal para la nueva alerta
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

RULES_FILE="${TEMP_DIR}/rules.yaml"

# Crear el archivo de reglas
cat > "${RULES_FILE}" << EOL
groups:
- name: ${GROUP_NAME}
  rules:
  - alert: ${ALERT_NAME}
    expr: ${EXPRESSION}
    for: ${DURATION}
    labels:
      severity: ${SEVERITY}
    annotations:
      summary: "${SUMMARY}"
      description: "${DESCRIPTION}"
EOL

echo "Creando nueva alerta con la siguiente configuración:"
echo "----------------------------------------------------"
echo "Grupo: ${GROUP_NAME}"
echo "Alerta: ${ALERT_NAME}"
echo "Expresión: ${EXPRESSION}"
echo "Duración: ${DURATION}"
echo "Severidad: ${SEVERITY}"
echo "Resumen: ${SUMMARY}"
echo "Descripción: ${DESCRIPTION}"
echo "----------------------------------------------------"

# En un entorno real, aquí actualizaríamos Prometheus
# Pero como estamos trabajando con Kubernetes, necesitamos actualizar el ConfigMap
echo "Para aplicar esta alerta, sigue estos pasos:"
echo ""
echo "1. Guarda el contenido siguiente en un archivo llamado 'nueva-alerta.yaml':"
echo ""
cat "${RULES_FILE}"
echo ""
echo "2. Actualiza el ConfigMap de alertas en Kubernetes:"
echo ""
echo "   kubectl get configmap prometheus-alerts -n ${NAMESPACE} -o yaml > alertas-actuales.yaml"
echo "   # Edita alertas-actuales.yaml para añadir la nueva alerta"
echo "   kubectl apply -f alertas-actuales.yaml"
echo ""
echo "3. Recarga la configuración de Prometheus:"
echo ""
echo "   kubectl exec -n ${NAMESPACE} \$(kubectl get pods -n ${NAMESPACE} -l app=prometheus -o jsonpath='{.items[0].metadata.name}') -- curl -X POST http://localhost:9090/-/reload"
echo ""
echo -e "${GREEN}Configuración de alerta generada exitosamente.${NC}"
EOF

  chmod +x "$SCRIPTS_DIR/alerts/create-alert.sh"
  
  log "Scripts de gestión de alertas creados exitosamente" "SUCCESS"
}

# Función para crear script principal de instalación
create_main_installation_script() {
  log "Creando script principal de instalación..."
  
  cat > "$BASE_DIR/install-monitoring.sh" << 'EOF'
#!/bin/bash
#
# Script de Instalación del Stack de Monitoreo y Observabilidad
# Para la Plataforma Centralizada de Información
#

set -e

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
BASE_DIR="/opt/central-platform"
K8S_DIR="$BASE_DIR/k8s"
MONITORING_DIR="$K8S_DIR/monitoring"
NAMESPACE="central-platform"

# Función para imprimir mensajes
log() {
  local msg="$1"
  local level="${2:-INFO}"
  
  case $level in
    "INFO") echo -e "[${GREEN}INFO${NC}] $msg" ;;
    "WARN") echo -e "[${YELLOW}WARN${NC}] $msg" ;;
    "ERROR") echo -e "[${RED}ERROR${NC}] $msg" ;;
    *) echo -e "[${BLUE}$level${NC}] $msg" ;;
  esac
}

# Función para verificar prerrequisitos
check_prerequisites() {
  log "Verificando prerrequisitos..."
  
  # Verificar kubectl
  if ! command -v kubectl &> /dev/null; then
    log "kubectl no está instalado. Instalando..." "WARN"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    log "kubectl instalado correctamente" "SUCCESS"
  else
    log "kubectl ya está instalado: $(kubectl version --client --output=yaml | grep gitVersion)"
  fi
  
  # Verificar conexión a Kubernetes
  if ! kubectl cluster-info &> /dev/null; then
    log "No se puede conectar al cluster de Kubernetes. Verifica tu configuración." "ERROR"
    exit 1
  fi
  
  log "Prerrequisitos verificados correctamente" "SUCCESS"
}

# Función para crear namespace
create_namespace() {
  log "Creando namespace: $NAMESPACE"
  
  if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log "El namespace $NAMESPACE ya existe" "WARN"
  else
    kubectl apply -f "$K8S_DIR/namespace.yaml"
    log "Namespace $NAMESPACE creado correctamente" "SUCCESS"
  fi
}

# Función para desplegar componentes
deploy_component() {
  local component="$1"
  local component_dir="$MONITORING_DIR/$component"
  
  log "Desplegando $component..."
  
  # Desplegar ServiceAccount primero si existe
  if [ -f "$component_dir/serviceaccount.yaml" ]; then
    kubectl apply -f "$component_dir/serviceaccount.yaml"
    log "ServiceAccount para $component desplegado"
  fi
  
  # Desplegar ConfigMap si existe
  if [ -f "$component_dir/configmap.yaml" ]; then
    kubectl apply -f "$component_dir/configmap.yaml"
    log "ConfigMap para $component desplegado"
  fi
  
  # Desplegar Secret si existe
  if [ -f "$component_dir/secret.yaml" ]; then
    kubectl apply -f "$component_dir/secret.yaml"
    log "Secret para $component desplegado"
  fi
  
  # Desplegar PVC si existe
  if [ -f "$component_dir/pvc.yaml" ]; then
    kubectl apply -f "$component_dir/pvc.yaml"
    log "PVC para $component desplegado"
  fi
  
  # Desplegar StatefulSet/Deployment si existe
  if [ -f "$component_dir/statefulset.yaml" ]; then
    kubectl apply -f "$component_dir/statefulset.yaml"
    log "StatefulSet para $component desplegado"
  elif [ -f "$component_dir/deployment.yaml" ]; then
    kubectl apply -f "$component_dir/deployment.yaml"
    log "Deployment para $component desplegado"
  elif [ -f "$component_dir/daemonset.yaml" ]; then
    kubectl apply -f "$component_dir/daemonset.yaml"
    log "DaemonSet para $component desplegado"
  fi
  
  # Desplegar Service si existe
  if [ -f "$component_dir/service.yaml" ]; then
    kubectl apply -f "$component_dir/service.yaml"
    log "Service para $component desplegado"
  fi
  
  # Verificar si se ha desplegado correctamente
  if [ -f "$component_dir/statefulset.yaml" ]; then
    RESOURCE_TYPE="statefulset"
  elif [ -f "$component_dir/deployment.yaml" ]; then
    RESOURCE_TYPE="deployment"
  elif [ -f "$component_dir/daemonset.yaml" ]; then
    RESOURCE_TYPE="daemonset"
  else
    log "$component desplegado, pero no se puede verificar su estado" "WARN"
    return
  fi
  
  # Esperar a que el recurso esté listo
  log "Esperando a que $component esté listo..."
  if [ "$RESOURCE_TYPE" = "daemonset" ]; then
    # Para DaemonSets, verificar que estén desplegados correctamente
    kubectl rollout status $RESOURCE_TYPE $component -n $NAMESPACE --timeout=300s
  else
    # Para StatefulSets y Deployments, esperar a que estén listos
    kubectl rollout status $RESOURCE_TYPE $component -n $NAMESPACE --timeout=300s
  fi
  
  log "$component desplegado correctamente" "SUCCESS"
}

# Función para crear directorios de backup
setup_backup_directories() {
  log "Configurando directorios de backup..."
  
  sudo mkdir -p /backup/prometheus
  sudo mkdir -p /backup/grafana
  sudo mkdir -p /backup/loki
  sudo mkdir -p /var/log/central-platform/backup
  
  sudo chmod 777 /backup -R
  sudo chmod 755 /var/log/central-platform/backup
  
  log "Directorios de backup configurados correctamente" "SUCCESS"
}

# Función para configurar trabajos cron de backup
setup_backup_cron() {
  log "Configurando trabajos de cron para backups..."
  
  if [ -f "$BASE_DIR/scripts/monitoring/backup/setup-backup-cron.sh" ]; then
    sudo "$BASE_DIR/scripts/monitoring/backup/setup-backup-cron.sh"
    log "Trabajos de cron para backups configurados correctamente" "SUCCESS"
  else
    log "No se encontró el script de configuración de cron para backups" "ERROR"
  fi
}

# Función principal
main() {
  log "Iniciando instalación del stack de monitoreo y observabilidad..."
  
  # Verificar prerrequisitos
  check_prerequisites
  
  # Crear namespace
  create_namespace
  
  # Desplegar componentes en orden
  deploy_component "node-exporter"
  deploy_component "kube-state-metrics"
  deploy_component "prometheus"
  log "Esperando 30 segundos para que Prometheus esté completamente inicializado..." "WARN"
  sleep 30
  deploy_component "alertmanager"
  deploy_component "loki"
  log "Esperando 30 segundos para que Loki esté completamente inicializado..." "WARN"
  sleep 30
  deploy_component "promtail"
  deploy_component "tempo"
  deploy_component "grafana"
  
  # Configurar directorios de backup
  setup_backup_directories
  
  # Configurar trabajos cron de backup
  setup_backup_cron
  
  log "Instalación del stack de monitoreo y observabilidad completada exitosamente" "SUCCESS"
  log "Puedes acceder a Grafana en: http://<cluster-ip>:3000" "INFO"
  log "Usuario por defecto: admin" "INFO"
  log "Contraseña por defecto: admin12345 (¡Cámbiala después del primer inicio de sesión!)" "WARN"
}

# Ejecutar la función principal
main
EOF

  chmod +x "$BASE_DIR/install-monitoring.sh"
  
  log "Script principal de instalación creado exitosamente" "SUCCESS"
}

# Función principal
main() {
  log "Iniciando configuración de Monitoreo y Observabilidad..."
  
  # Crear estructura de directorios
  create_directories
  
  # Crear namespace
  create_namespace
  
  # Crear configuraciones para cada componente
  create_prometheus_configs
  create_grafana_configs
  create_alertmanager_configs
  create_loki_configs
  create_promtail_configs
  create_tempo_configs
  create_node_exporter_configs
  create_kube_state_metrics_configs
  
  # Crear scripts de backup
  create_prometheus_backup_script
  create_grafana_backup_script
  create_loki_backup_script
  create_backup_cron_script
  
  # Crear scripts de gestión
  create_dashboard_management_scripts
  create_alert_management_scripts
  
  # Crear script principal de instalación
  create_main_installation_script
  
  log "Configuración de Monitoreo y Observabilidad completada exitosamente" "SUCCESS"
  log "Para instalar el stack, ejecuta: sudo $BASE_DIR/install-monitoring.sh" "INFO"
}

# Ejecutar la función principal
main
