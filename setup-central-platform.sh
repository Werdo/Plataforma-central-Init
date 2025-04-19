#!/bin/bash
#
# Central Platform Setup Script for Ubuntu 24.04 LTS
# This script orchestrates the deployment of the Central Platform system
# by creating the necessary file structure and executing deployment scripts
# in the correct order.
#
# Usage: ./setup-central-platform.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory for the project
BASE_DIR="$HOME/central-platform"

# Log file
LOG_FILE="$BASE_DIR/setup.log"

# Function to log messages
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to print section header
print_header() {
    local title="$1"
    echo -e "\n${BLUE}==== ${title} ====${NC}"
    log "Starting: ${title}" "SECTION"
}

# Function to check if the command was successful
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Success${NC}"
        log "Success: $1" "SUCCESS"
    else
        echo -e "${RED}✗ Failed${NC}"
        log "Failed: $1" "ERROR"
        exit 1
    fi
}

# Create directory structure
create_directory_structure() {
    print_header "Creating Directory Structure"
    
    # Create main project directory if it doesn't exist
    mkdir -p "$BASE_DIR"
    
    # Create subdirectories for each zone
    mkdir -p "$BASE_DIR/k8s/namespaces"
    mkdir -p "$BASE_DIR/k8s/frontend"
    mkdir -p "$BASE_DIR/k8s/backend/api-rest"
    mkdir -p "$BASE_DIR/k8s/backend/websocket"
    mkdir -p "$BASE_DIR/k8s/backend/alerts"
    mkdir -p "$BASE_DIR/k8s/gateways"
    mkdir -p "$BASE_DIR/k8s/databases/mongodb"
    mkdir -p "$BASE_DIR/k8s/databases/postgresql"
    mkdir -p "$BASE_DIR/k8s/databases/elasticsearch"
    mkdir -p "$BASE_DIR/k8s/security/oauth2-proxy"
    mkdir -p "$BASE_DIR/k8s/security/passbolt"
    mkdir -p "$BASE_DIR/k8s/monitoring/prometheus"
    mkdir -p "$BASE_DIR/k8s/monitoring/grafana"
    mkdir -p "$BASE_DIR/k8s/monitoring/loki"
    
    # Create directories for deployment scripts
    mkdir -p "$BASE_DIR/scripts/deploy"
    mkdir -p "$BASE_DIR/scripts/backup"
    mkdir -p "$BASE_DIR/scripts/maintenance"
    
    # Create directories for source code
    mkdir -p "$BASE_DIR/frontend/src"
    mkdir -p "$BASE_DIR/backend/api-rest/app"
    mkdir -p "$BASE_DIR/backend/websocket/src"
    mkdir -p "$BASE_DIR/backend/alerts/src"
    mkdir -p "$BASE_DIR/gateways/iot-gateway/src"
    mkdir -p "$BASE_DIR/gateways/m2m-adapter/src"
    mkdir -p "$BASE_DIR/analytics/mongo-analytics/src"
    mkdir -p "$BASE_DIR/analytics/panda-ai/src"
    
    # Create docs directory
    mkdir -p "$BASE_DIR/docs/architecture"
    mkdir -p "$BASE_DIR/docs/deployment"
    mkdir -p "$BASE_DIR/docs/development"
    mkdir -p "$BASE_DIR/docs/user-manual"
    
    check_success "Directory structure creation"
}

# Create deployment scripts
create_deployment_scripts() {
    print_header "Creating Deployment Scripts"
    
    # Create Deploy-Zona-A.sh script
    cat > "$BASE_DIR/scripts/deploy/Deploy-Zona-A.sh" << 'EOF'
#!/bin/bash
#
# Deploy-Zona-A.sh - Script para desplegar la Zona A (Frontend)
#

set -e

echo "Desplegando Zona A (Frontend)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Aplicar configuraciones de Kubernetes para el frontend
kubectl apply -f ../../k8s/frontend/deployment.yaml
kubectl apply -f ../../k8s/frontend/service.yaml
kubectl apply -f ../../k8s/frontend/configmap.yaml
kubectl apply -f ../../k8s/frontend/ingress.yaml

echo "Zona A (Frontend) desplegada exitosamente."
EOF

    # Create Deploy-Zone-B.sh script
    cat > "$BASE_DIR/scripts/deploy/Deploy-Zone-B.sh" << 'EOF'
#!/bin/bash
#
# Deploy-Zone-B.sh - Script para desplegar la Zona B (Backend)
#

set -e

echo "Desplegando Zona B (Backend)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar API REST
echo "Desplegando API REST..."
kubectl apply -f ../../k8s/backend/api-rest/deployment.yaml
kubectl apply -f ../../k8s/backend/api-rest/service.yaml
kubectl apply -f ../../k8s/backend/api-rest/configmap.yaml

# Desplegar WebSocket
echo "Desplegando WebSocket..."
kubectl apply -f ../../k8s/backend/websocket/deployment.yaml
kubectl apply -f ../../k8s/backend/websocket/service.yaml
kubectl apply -f ../../k8s/backend/websocket/configmap.yaml

# Desplegar Servicio de Alertas
echo "Desplegando Servicio de Alertas..."
kubectl apply -f ../../k8s/backend/alerts/deployment.yaml
kubectl apply -f ../../k8s/backend/alerts/service.yaml
kubectl apply -f ../../k8s/backend/alerts/configmap.yaml

echo "Zona B (Backend) desplegada exitosamente."
EOF

    # Create Deploy-Zone-C.sh script
    cat > "$BASE_DIR/scripts/deploy/Deploy-Zone-C.sh" << 'EOF'
#!/bin/bash
#
# Deploy-Zone-C.sh - Script para desplegar la Zona C (Gateways IoT)
#

set -e

echo "Desplegando Zona C (Gateways IoT)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar Gateway IoT principal
echo "Desplegando Gateway IoT principal..."
kubectl apply -f ../../k8s/gateways/iot-gateway/deployment.yaml
kubectl apply -f ../../k8s/gateways/iot-gateway/service.yaml
kubectl apply -f ../../k8s/gateways/iot-gateway/configmap.yaml

# Desplegar Adaptador M2M
echo "Desplegando Adaptador M2M..."
kubectl apply -f ../../k8s/gateways/m2m-adapter/deployment.yaml
kubectl apply -f ../../k8s/gateways/m2m-adapter/service.yaml
kubectl apply -f ../../k8s/gateways/m2m-adapter/configmap.yaml

echo "Zona C (Gateways IoT) desplegada exitosamente."
EOF

    # Create Deploy-Zone-D.sh script
    cat > "$BASE_DIR/scripts/deploy/Deploy-Zone-D.sh" << 'EOF'
#!/bin/bash
#
# Deploy-Zone-D.sh - Script para desplegar la Zona D (Mensajería)
#

set -e

echo "Desplegando Zona D (Mensajería)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar Redis
echo "Desplegando Redis..."
kubectl apply -f ../../k8s/databases/redis/statefulset.yaml
kubectl apply -f ../../k8s/databases/redis/service.yaml
kubectl apply -f ../../k8s/databases/redis/configmap.yaml

# Desplegar RabbitMQ si es necesario
# echo "Desplegando RabbitMQ..."
# kubectl apply -f ../../k8s/messaging/rabbitmq/statefulset.yaml
# kubectl apply -f ../../k8s/messaging/rabbitmq/service.yaml
# kubectl apply -f ../../k8s/messaging/rabbitmq/configmap.yaml

echo "Zona D (Mensajería) desplegada exitosamente."
EOF

    # Create Deploy-Zone-E.sh script
    cat > "$BASE_DIR/scripts/deploy/deploy-Zone-E.sh" << 'EOF'
#!/bin/bash
#
# deploy-Zone-E.sh - Script para desplegar la Zona E (Persistencia)
#

set -e

echo "Desplegando Zona E (Persistencia)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar MongoDB
echo "Desplegando MongoDB..."
kubectl apply -f ../../k8s/databases/mongodb/statefulset.yaml
kubectl apply -f ../../k8s/databases/mongodb/service.yaml
kubectl apply -f ../../k8s/databases/mongodb/configmap.yaml
kubectl apply -f ../../k8s/databases/mongodb/secret.yaml
kubectl apply -f ../../k8s/databases/mongodb/pvc.yaml

# Desplegar PostgreSQL
echo "Desplegando PostgreSQL..."
kubectl apply -f ../../k8s/databases/postgresql/statefulset.yaml
kubectl apply -f ../../k8s/databases/postgresql/service.yaml
kubectl apply -f ../../k8s/databases/postgresql/configmap.yaml
kubectl apply -f ../../k8s/databases/postgresql/secret.yaml
kubectl apply -f ../../k8s/databases/postgresql/pvc.yaml

# Desplegar ElasticSearch
echo "Desplegando ElasticSearch..."
kubectl apply -f ../../k8s/databases/elasticsearch/statefulset.yaml
kubectl apply -f ../../k8s/databases/elasticsearch/service.yaml
kubectl apply -f ../../k8s/databases/elasticsearch/configmap.yaml
kubectl apply -f ../../k8s/databases/elasticsearch/pvc.yaml

# Desplegar Kibana
echo "Desplegando Kibana..."
kubectl apply -f ../../k8s/databases/elasticsearch/kibana/deployment.yaml
kubectl apply -f ../../k8s/databases/elasticsearch/kibana/service.yaml
kubectl apply -f ../../k8s/databases/elasticsearch/kibana/configmap.yaml

echo "Zona E (Persistencia) desplegada exitosamente."
EOF

    # Create Deploy-Zone-G.sh script
    cat > "$BASE_DIR/scripts/deploy/Deploy-Zone-G.sh" << 'EOF'
#!/bin/bash
#
# Deploy-Zone-G.sh - Script para desplegar la Zona G (Seguridad)
#

set -e

echo "Desplegando Zona G (Seguridad)..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar OAuth2 Proxy
echo "Desplegando OAuth2 Proxy..."
kubectl apply -f ../../k8s/security/oauth2-proxy/deployment.yaml
kubectl apply -f ../../k8s/security/oauth2-proxy/service.yaml
kubectl apply -f ../../k8s/security/oauth2-proxy/configmap.yaml
kubectl apply -f ../../k8s/security/oauth2-proxy/secret.yaml

# Desplegar Cert Manager
echo "Desplegando Cert Manager..."
kubectl apply -f ../../k8s/security/cert-manager/cluster-issuer.yaml
kubectl apply -f ../../k8s/security/cert-manager/certificate.yaml

# Desplegar Passbolt
echo "Desplegando Passbolt..."
kubectl apply -f ../../k8s/security/passbolt/deployment.yaml
kubectl apply -f ../../k8s/security/passbolt/service.yaml
kubectl apply -f ../../k8s/security/passbolt/ingress.yaml
kubectl apply -f ../../k8s/security/passbolt/configmap.yaml
kubectl apply -f ../../k8s/security/passbolt/secret.yaml
kubectl apply -f ../../k8s/security/passbolt/pvc.yaml

# Desplegar Keycloak
echo "Desplegando Keycloak..."
kubectl apply -f ../../k8s/security/keycloak/statefulset.yaml
kubectl apply -f ../../k8s/security/keycloak/service.yaml
kubectl apply -f ../../k8s/security/keycloak/ingress.yaml
kubectl apply -f ../../k8s/security/keycloak/configmap.yaml

# Configurar políticas de red
echo "Configurando políticas de red..."
kubectl apply -f ../../k8s/security/network-policies/default-deny.yaml
kubectl apply -f ../../k8s/security/network-policies/ingress-rules.yaml
kubectl apply -f ../../k8s/security/network-policies/egress-rules.yaml

echo "Zona G (Seguridad) desplegada exitosamente."
EOF

    # Create deploy-monitobserv.sh script
    cat > "$BASE_DIR/scripts/deploy/deploy-monitobserv.sh" << 'EOF'
#!/bin/bash
#
# deploy-monitobserv.sh - Script para desplegar el sistema de monitoreo y observabilidad
#

set -e

echo "Desplegando sistema de monitoreo y observabilidad..."

# Crear namespace si no existe
kubectl get namespace central-platform >/dev/null 2>&1 || kubectl create namespace central-platform

# Desplegar Prometheus
echo "Desplegando Prometheus..."
kubectl apply -f ../../k8s/monitoring/prometheus/deployment.yaml
kubectl apply -f ../../k8s/monitoring/prometheus/service.yaml
kubectl apply -f ../../k8s/monitoring/prometheus/configmap.yaml
kubectl apply -f ../../k8s/monitoring/prometheus/serviceaccount.yaml
kubectl apply -f ../../k8s/monitoring/prometheus/clusterrole.yaml
kubectl apply -f ../../k8s/monitoring/prometheus/clusterrolebinding.yaml

# Desplegar Grafana
echo "Desplegando Grafana..."
kubectl apply -f ../../k8s/monitoring/grafana/deployment.yaml
kubectl apply -f ../../k8s/monitoring/grafana/service.yaml
kubectl apply -f ../../k8s/monitoring/grafana/configmap.yaml
kubectl apply -f ../../k8s/monitoring/grafana/secret.yaml
kubectl apply -f ../../k8s/monitoring/grafana/ingress.yaml

# Desplegar Loki
echo "Desplegando Loki..."
kubectl apply -f ../../k8s/monitoring/loki/statefulset.yaml
kubectl apply -f ../../k8s/monitoring/loki/service.yaml
kubectl apply -f ../../k8s/monitoring/loki/configmap.yaml

# Desplegar Promtail
echo "Desplegando Promtail..."
kubectl apply -f ../../k8s/monitoring/promtail/daemonset.yaml
kubectl apply -f ../../k8s/monitoring/promtail/configmap.yaml
kubectl apply -f ../../k8s/monitoring/promtail/serviceaccount.yaml
kubectl apply -f ../../k8s/monitoring/promtail/clusterrole.yaml
kubectl apply -f ../../k8s/monitoring/promtail/clusterrolebinding.yaml

echo "Sistema de monitoreo y observabilidad desplegado exitosamente."
EOF

    # Make all scripts executable
    chmod +x "$BASE_DIR/scripts/deploy/Deploy-Zona-A.sh"
    chmod +x "$BASE_DIR/scripts/deploy/Deploy-Zone-B.sh"
    chmod +x "$BASE_DIR/scripts/deploy/Deploy-Zone-C.sh"
    chmod +x "$BASE_DIR/scripts/deploy/Deploy-Zone-D.sh"
    chmod +x "$BASE_DIR/scripts/deploy/deploy-Zone-E.sh"
    chmod +x "$BASE_DIR/scripts/deploy/Deploy-Zone-G.sh"
    chmod +x "$BASE_DIR/scripts/deploy/deploy-monitobserv.sh"
    
    check_success "Deployment scripts creation"
}

# Create Kubernetes configuration files
create_kubernetes_files() {
    print_header "Creating Kubernetes Configuration Files"
    
    # Create namespace
    cat > "$BASE_DIR/k8s/namespaces/central-platform.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: central-platform
  labels:
    name: central-platform
EOF

    # Create frontend deployment
    cat > "$BASE_DIR/k8s/frontend/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: central-platform
  labels:
    app: frontend
    component: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        component: frontend
    spec:
      containers:
      - name: frontend
        image: central-platform/frontend:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        env:
        - name: API_URL
          valueFrom:
            configMapKeyRef:
              name: frontend-config
              key: api_url
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
EOF

    # Create frontend service
    cat > "$BASE_DIR/k8s/frontend/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: central-platform
  labels:
    app: frontend
    component: frontend
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: frontend
  type: ClusterIP
EOF

    # Create frontend configmap
    cat > "$BASE_DIR/k8s/frontend/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: central-platform
  labels:
    app: frontend
    component: frontend
data:
  api_url: "https://api.central-platform.local/api/v1"
  ws_url: "wss://ws.central-platform.local"
  auth_domain: "central-platform.local"
  environment: "production"
EOF

    # Create MongoDB statefulset
    cat > "$BASE_DIR/k8s/databases/mongodb/statefulset.yaml" << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: central-platform
  labels:
    app: mongodb
    component: database
spec:
  serviceName: mongodb-headless
  replicas: 3
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
        component: database
    spec:
      terminationGracePeriodSeconds: 30
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
      containers:
      - name: mongodb
        image: mongo:5.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: mongo
          containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          valueFrom:
            secretKeyRef:
              name: mongodb-secret
              key: root-username
        - name: MONGO_INITDB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mongodb-secret
              key: root-password
        - name: MONGO_REPLICA_SET_NAME
          value: "rs0"
        - name: MONGODB_ADVERTISED_HOSTNAME
          value: "$(POD_NAME).mongodb-headless.central-platform.svc.cluster.local"
        envFrom:
        - configMapRef:
            name: mongodb-config
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
        - name: mongodb-scripts
          mountPath: /docker-entrypoint-initdb.d
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          exec:
            command:
            - mongo
            - --eval
            - "db.adminCommand('ping')"
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 6
      volumes:
      - name: mongodb-scripts
        configMap:
          name: mongodb-init-scripts
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 20Gi
EOF

    # Create MongoDB service
    cat > "$BASE_DIR/k8s/databases/mongodb/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: central-platform
  labels:
    app: mongodb
    component: database
spec:
  ports:
  - port: 27017
    targetPort: mongo
    protocol: TCP
    name: mongodb
  selector:
    app: mongodb
  type: ClusterIP

---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-headless
  namespace: central-platform
  labels:
    app: mongodb
    component: database
spec:
  ports:
  - port: 27017
    targetPort: mongo
    protocol: TCP
    name: mongodb
  selector:
    app: mongodb
  clusterIP: None
EOF

    check_success "Kubernetes configuration files creation"
}

# Install required packages
install_prerequisites() {
    print_header "Installing Prerequisites"
    
    # Update package lists
    sudo apt update
    check_success "Package lists update"
    
    # Install required packages
    sudo apt install -y curl wget git jq apt-transport-https ca-certificates software-properties-common gnupg
    check_success "Basic utilities installation"
    
    # Install Docker if not already installed
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
        sudo usermod -aG docker $USER
        check_success "Docker installation"
    else
        echo "Docker is already installed, skipping..."
    fi
    
    # Install kubectl if not already installed
    if ! command -v kubectl &> /dev/null; then
        echo "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        check_success "Kubectl installation"
    else
        echo "Kubectl is already installed, skipping..."
    fi
    
    # Install minikube if not already installed (for local development)
    if ! command -v minikube &> /dev/null; then
        echo "Installing minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
        check_success "Minikube installation"
    else
        echo "Minikube is already installed, skipping..."
    fi
    
    # Install Helm if not already installed
    if ! command -v helm &> /dev/null; then
        echo "Installing Helm..."
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 get_helm.sh
        ./get_helm.sh
        rm get_helm.sh
        check_success "Helm installation"
    else
        echo "Helm is already installed, skipping..."
    fi
}

# Start a local Kubernetes cluster with Minikube (for development)
start_minikube() {
    print_header "Starting Minikube"
    
    # Check if minikube is already running
    if minikube status | grep -q "Running"; then
        echo "Minikube is already running, skipping..."
    else
        # Start minikube with appropriate resources
        minikube start --cpus=4 --memory=8192 --disk-size=50g --driver=docker
        check_success "Minikube start"
        
        # Enable necessary addons
        minikube addons enable ingress
        minikube addons enable metrics-server
        minikube addons enable dashboard
        check_success "Minikube addons"
    fi
}

# Install Kubernetes operators and essential services
install_operators() {
    print_header "Installing Kubernetes Operators"
    
    # Install cert-manager for TLS certificates
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml
    check_success "Cert-manager installation"
    
    # Wait for cert-manager to be ready
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s
    
    # Install prometheus-operator for monitoring
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
    check_success "Prometheus operator installation"
}

# Deploy all components
deploy_all() {
    print_header "Deploying All Components"
    
    # Create namespace
    kubectl apply -f "$BASE_DIR/k8s/namespaces/central-platform.yaml"
    check_success "Namespace creation"
    
    # Change to the deployment scripts directory
    cd "$BASE_DIR/scripts/deploy"
    
    # Execute deployment scripts in the correct order
    echo "Deploying Zona E (Persistencia) - Databases"
    ./deploy-Zone-E.sh
    check_success "Zone E deployment"
    
    echo "Deploying Zona G (Seguridad) - Security"
    ./Deploy-Zone-G.sh
    check_success "Zone G deployment"
    
    echo "Deploying Zona D (Mensajería) - Messaging"
    ./Deploy-Zone-D.sh
    check_success "Zone D deployment"
    
    echo "Deploying Zona B (Backend) - Backend services"
    ./Deploy-Zone-B.sh
    check_success "Zone B deployment"
    
    echo "Deploying Zona C (Gateways IoT) - IoT Gateways"
    ./Deploy-Zone-C.sh
    check_success "Zone C deployment"
    
    echo "Deploying Zona A (Frontend) - Frontend"
    ./Deploy-Zona-A.sh
    check_success "Zone A deployment"
    
    echo "Deploying Monitoring and Observability"
    ./deploy-monitobserv.sh
    check_success "Monitoring deployment"
    
    # Return to the original directory
    cd - > /dev/null
}

# Create README file
create_readme() {
    print_header "Creating README"
    
    cat > "$BASE_DIR/README.md" << 'EOF'
# Central Platform

## Overview

This repository contains the infrastructure and application code for the Central Platform, a comprehensive IoT data management and visualization platform.

## Architecture

The platform is divided into multiple zones:

- **Zona A (Frontend)**: User interface built with React.js
- **Zona B (Backend)**: REST API and WebSocket services
- **Zona C (IoT Gateways)**: Services for connecting IoT devices
- **Zona D (Messaging)**: Message exchange system with Redis/RabbitMQ
- **Zona E (Persistence)**: Data storage with MongoDB, PostgreSQL, and ElasticSearch
- **Zona G (Security)**: Authentication, authorization, and security components

## Getting Started

### Prerequisites

- Ubuntu 24.04 LTS
- Docker and Docker Compose
- Kubernetes (Minikube for local development)
- kubectl, Helm

### Installation

1. Clone this repository
2. Run the setup script: `./setup-central-platform.sh`
3. Access the platform at: https://central-platform.local (add to your /etc/hosts file)

## Development

Check the `docs/development` directory for detailed development guides.

## Deployment

Check the `docs/deployment` directory for detailed deployment instructions.

## Security

Check the `docs/security` directory for security best practices and configurations.

## License

Proprietary - All rights reserved.
EOF

    check_success "README creation"
}

# Main function
main() {
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  Central Platform Setup Script for Ubuntu 24.04 LTS${NC}"
    echo -e "${GREEN}=========================================${NC}"
    
    # Create log directory
    mkdir -p $(dirname "$LOG_FILE")
    
    # Initialize log file
    echo "Central Platform Setup Log - $(date)" > "$LOG_FILE"
    
    # Install prerequisites
    install_prerequisites
    
    # Create directory structure
    create_directory_structure
    
    # Create deployment scripts
    create_deployment_scripts
    
    # Create Kubernetes configuration files
    create_kubernetes_files
    
    # Create README
    create_readme
    
    # Ask if user wants to start Minikube
    read -p "Do you want to start Minikube for local development? (y/n): " start_minikube_answer
    if [[ $start_minikube_answer =~ ^[Yy]$ ]]; then
        start_minikube
        
        # Install operators
        install_operators
        
        # Ask if user wants to deploy all components
        read -p "Do you want to deploy all components to Minikube? (y/n): " deploy_answer
        if [[ $deploy_answer =~ ^[Yy]$ ]]; then
            deploy_all
            
            # Display access information
            minikube_ip=$(minikube ip)
            echo -e "\n${GREEN}=========================================${NC}"
            echo -e "${GREEN}  Deployment Completed Successfully!${NC}"
            echo -e "${GREEN}=========================================${NC}"
            echo -e "\nTo access the platform, add the following entry to your /etc/hosts file:"
            echo -e "${BLUE}$minikube_ip  central-platform.local api.central-platform.local keycloak.central-platform.local${NC}"
            echo -e "\nThen access the platform at: ${BLUE}https://central-platform.local${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}Setup completed successfully!${NC}"
    echo -e "Project directory: ${BLUE}$BASE_DIR${NC}"
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo -e "\nRun the following commands to make the deployment scripts executable:"
    echo -e "${YELLOW}chmod +x $BASE_DIR/scripts/deploy/*.sh${NC}"
    
    echo -e "\nTo deploy individual components, navigate to the scripts directory and run the deployment scripts:"
    echo -e "${YELLOW}cd $BASE_DIR/scripts/deploy${NC}"
    echo -e "${YELLOW}./Deploy-Zone-X.sh${NC}"
}

# Execute main function
main
