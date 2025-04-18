#!/bin/bash

#########################################################################
# Script de despliegue para la Zona G (Seguridad)                       #
# Plataforma Centralizada de Información                                #
# Compatible con Ubuntu 24.04 LTS                                       #
#########################################################################

set -e

# Colores para salida
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Función de ayuda para imprimir mensajes
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validar que se ejecuta como root o con sudo
if [ "$EUID" -ne 0 ]; then
    log_error "Por favor, ejecute este script como root o con sudo"
    exit 1
fi

# Configuración de variables
BASE_DIR="/opt/central-platform"
SECURITY_DIR="${BASE_DIR}/security"
K8S_DIR="${BASE_DIR}/k8s/security"
HELM_DIR="${BASE_DIR}/helm/security"
SCRIPTS_DIR="${BASE_DIR}/scripts/security"
DOCS_DIR="${BASE_DIR}/docs/security"

# Crear directorios base
create_directory_structure() {
    log_info "Creando estructura de directorios..."
    
    # Directorios principales
    mkdir -p "${SECURITY_DIR}/auth/oauth2-proxy/src/config"
    mkdir -p "${SECURITY_DIR}/auth/oauth2-proxy/src/templates"
    mkdir -p "${SECURITY_DIR}/auth/oauth2-proxy/src/middleware"
    mkdir -p "${SECURITY_DIR}/auth/keycloak/themes/central-platform"
    mkdir -p "${SECURITY_DIR}/auth/keycloak/extensions"
    mkdir -p "${SECURITY_DIR}/auth/keycloak/scripts"
    
    mkdir -p "${SECURITY_DIR}/secrets/vault/config"
    mkdir -p "${SECURITY_DIR}/secrets/vault/scripts"
    mkdir -p "${SECURITY_DIR}/secrets/certificates/ca"
    mkdir -p "${SECURITY_DIR}/secrets/certificates/certs"
    
    mkdir -p "${SECURITY_DIR}/compliance/scanners/trivy"
    mkdir -p "${SECURITY_DIR}/compliance/scanners/clair"
    mkdir -p "${SECURITY_DIR}/compliance/scanners/sonarqube"
    mkdir -p "${SECURITY_DIR}/compliance/policies/pod-security"
    mkdir -p "${SECURITY_DIR}/compliance/policies/network-security"
    mkdir -p "${SECURITY_DIR}/compliance/policies/data-security"
    mkdir -p "${SECURITY_DIR}/compliance/reports"
    
    mkdir -p "${SECURITY_DIR}/monitoring/falco/rules"
    mkdir -p "${SECURITY_DIR}/monitoring/falco/alerts"
    mkdir -p "${SECURITY_DIR}/monitoring/wazuh/config"
    mkdir -p "${SECURITY_DIR}/monitoring/wazuh/rules"

    mkdir -p "${SECURITY_DIR}/scripts/audit"
    mkdir -p "${SECURITY_DIR}/scripts/hardening"
    mkdir -p "${SECURITY_DIR}/scripts/incident-response"
    
    # Directorios de Kubernetes
    mkdir -p "${K8S_DIR}/namespace"
    mkdir -p "${K8S_DIR}/network-policies"
    mkdir -p "${K8S_DIR}/oauth2-proxy"
    mkdir -p "${K8S_DIR}/cert-manager/configs"
    mkdir -p "${K8S_DIR}/passbolt"
    mkdir -p "${K8S_DIR}/keycloak/realm-config"
    mkdir -p "${K8S_DIR}/vault/policies"
    mkdir -p "${K8S_DIR}/waf/modsecurity"
    mkdir -p "${K8S_DIR}/waf/rules"
    mkdir -p "${K8S_DIR}/siem"
    
    # Directorios de Helm
    mkdir -p "${HELM_DIR}/oauth2-proxy/templates"
    mkdir -p "${HELM_DIR}/cert-manager/templates"
    mkdir -p "${HELM_DIR}/keycloak/templates"
    mkdir -p "${HELM_DIR}/vault/templates"
    mkdir -p "${HELM_DIR}/passbolt/templates"
    
    # Directorios de documentación
    mkdir -p "${DOCS_DIR}/architecture"
    mkdir -p "${DOCS_DIR}/policies"
    mkdir -p "${DOCS_DIR}/procedures"
    mkdir -p "${DOCS_DIR}/guidelines"
    mkdir -p "${DOCS_DIR}/compliance"
    
    log_success "Estructura de directorios creada correctamente"
}

# Crea archivos de Kubernetes - Namespace y Network Policies
create_k8s_base_files() {
    log_info "Creando archivos base de Kubernetes..."
    
    # Crear namespace.yaml
    cat > "${K8S_DIR}/namespace/namespace.yaml" << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: central-platform
  labels:
    name: central-platform
    environment: production
    managed-by: terraform
    security-zone: true
EOF

    # Crear default-deny.yaml
    cat > "${K8S_DIR}/network-policies/default-deny.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: central-platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

    # Crear ingress-rules.yaml
    cat > "${K8S_DIR}/network-policies/ingress-rules.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ingress
  namespace: central-platform
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-ingress
  namespace: central-platform
spec:
  podSelector:
    matchLabels:
      app: api-rest
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    - podSelector:
        matchLabels:
          app: websocket
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-websocket-ingress
  namespace: central-platform
spec:
  podSelector:
    matchLabels:
      app: websocket
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
EOF

    # Crear egress-rules.yaml
    cat > "${K8S_DIR}/network-policies/egress-rules.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: central-platform
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-db-egress
  namespace: central-platform
spec:
  podSelector:
    matchLabels:
      app: api-rest
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - podSelector:
        matchLabels:
          app: mongodb
    ports:
    - protocol: TCP
      port: 27017
EOF

    log_success "Archivos base de Kubernetes creados correctamente"
}

# Crear archivos de OAuth2 Proxy
create_oauth2_proxy_files() {
    log_info "Creando archivos de OAuth2 Proxy..."
    
    # Crear deployment.yaml
    cat > "${K8S_DIR}/oauth2-proxy/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy
  namespace: central-platform
  labels:
    app: oauth2-proxy
    component: security
spec:
  replicas: 2
  selector:
    matchLabels:
      app: oauth2-proxy
  template:
    metadata:
      labels:
        app: oauth2-proxy
        component: security
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:v7.4.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 4180
        env:
        - name: OAUTH2_PROXY_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-id
        - name: OAUTH2_PROXY_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-secret
        - name: OAUTH2_PROXY_COOKIE_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: cookie-secret
        args:
        - --http-address=0.0.0.0:4180
        - --provider=azure
        - --azure-tenant=$(OAUTH2_PROXY_AZURE_TENANT)
        - --email-domain=*
        - --cookie-secure=true
        - --cookie-samesite=lax
        - --reverse-proxy=true
        - --set-xauthrequest=true
        - --pass-access-token=true
        - --pass-user-headers=true
        - --pass-host-header=true
        - --skip-provider-button=true
        - --whitelist-domain=*.central-platform.local
        - --redirect-url=https://central-platform.local/oauth2/callback
        - --upstream=http://frontend:80
        envFrom:
        - configMapRef:
            name: oauth2-proxy-config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /ping
            port: http
          initialDelaySeconds: 10
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /ping
            port: http
          initialDelaySeconds: 5
          timeoutSeconds: 2
EOF

    # Crear service.yaml
    cat > "${K8S_DIR}/oauth2-proxy/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy
  namespace: central-platform
  labels:
    app: oauth2-proxy
    component: security
spec:
  ports:
  - name: http
    port: 4180
    targetPort: http
  selector:
    app: oauth2-proxy
EOF

    # Crear configmap.yaml
    cat > "${K8S_DIR}/oauth2-proxy/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
  namespace: central-platform
  labels:
    app: oauth2-proxy
    component: security
data:
  OAUTH2_PROXY_AZURE_TENANT: "common"
  OAUTH2_PROXY_SCOPE: "openid profile email"
  OAUTH2_PROXY_ALLOWED_GROUPS: "central-platform-users,central-platform-admins"
  OAUTH2_PROXY_EMAIL_DOMAINS: "*"
  OAUTH2_PROXY_SESSION_STORE_TYPE: "cookie"
  OAUTH2_PROXY_SESSION_COOKIE_NAME: "central_platform_session"
  OAUTH2_PROXY_SESSION_COOKIE_MINIMAL: "true"
  OAUTH2_PROXY_SESSION_COOKIE_EXPIRE: "24h"
  OAUTH2_PROXY_SESSION_COOKIE_REFRESH: "1h"
  OAUTH2_PROXY_STANDARD_LOGGING: "true"
  OAUTH2_PROXY_REQUEST_LOGGING: "true"
  OAUTH2_PROXY_REQUEST_LOGGING_FORMAT: "{{.Client}} - {{.Username}} [{{.Timestamp}}] {{.Host}} {{.Method}} {{.Path}} {{.Protocol}} {{.StatusCode}} {{.ResponseSize}} {{.RequestDuration}}"
  OAUTH2_PROXY_SILENCE_PING_LOGGING: "true"
EOF

    # Crear secret.yaml
    cat > "${K8S_DIR}/oauth2-proxy/secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secret
  namespace: central-platform
  labels:
    app: oauth2-proxy
    component: security
type: Opaque
data:
  client-id: "YmFzZTY0ZW5jb2RlZC1jbGllbnQtaWQ="  # base64 encoded
  client-secret: "YmFzZTY0ZW5jb2RlZC1jbGllbnQtc2VjcmV0"  # base64 encoded
  cookie-secret: "YmFzZTY0ZW5jb2RlZC1jb29raWUtc2VjcmV0"  # base64 encoded
EOF

    log_success "Archivos de OAuth2 Proxy creados correctamente"
}

# Crear archivos de Cert-Manager
create_cert_manager_files() {
    log_info "Creando archivos de Cert-Manager..."
    
    # Crear cluster-issuer.yaml
    cat > "${K8S_DIR}/cert-manager/cluster-issuer.yaml" << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@central-platform.local
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  namespace: cert-manager
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@central-platform.local
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

    # Crear certificate.yaml
    cat > "${K8S_DIR}/cert-manager/certificate.yaml" << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: central-platform-tls
  namespace: central-platform
spec:
  secretName: central-platform-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: central-platform.local
  dnsNames:
  - central-platform.local
  - www.central-platform.local
  - api.central-platform.local
  - passbolt.central-platform.local
  - keycloak.central-platform.local
EOF

    log_success "Archivos de Cert-Manager creados correctamente"
}

# Crear archivos de Passbolt
create_passbolt_files() {
    log_info "Creando archivos de Passbolt..."
    
    # Crear deployment.yaml
    cat > "${K8S_DIR}/passbolt/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: passbolt
  namespace: central-platform
  labels:
    app: passbolt
    component: security
spec:
  replicas: 1
  selector:
    matchLabels:
      app: passbolt
  template:
    metadata:
      labels:
        app: passbolt
        component: security
    spec:
      securityContext:
        fsGroup: 33
      containers:
      - name: passbolt
        image: passbolt/passbolt:3.8.3-ce
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 80
        - name: https
          containerPort: 443
        env:
        - name: APP_FULL_BASE_URL
          value: "https://passbolt.central-platform.local"
        - name: DATASOURCES_DEFAULT_HOST
          value: "postgresql"
        - name: DATASOURCES_DEFAULT_USERNAME
          valueFrom:
            secretKeyRef:
              name: passbolt-secret
              key: db-username
        - name: DATASOURCES_DEFAULT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: passbolt-secret
              key: db-password
        - name: DATASOURCES_DEFAULT_DATABASE
          value: "passbolt"
        - name: PASSBOLT_REGISTRATION_PUBLIC
          value: "false"
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_CLASS_NAME
          value: "Smtp"
        - name: PASSBOLT_EMAIL_DEFAULT_FROM
          value: "passbolt@central-platform.local"
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_HOST
          value: "smtp.central-platform.local"
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_PORT
          value: "587"
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_USERNAME
          valueFrom:
            secretKeyRef:
              name: passbolt-secret
              key: smtp-username
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: passbolt-secret
              key: smtp-password
        - name: PASSBOLT_EMAIL_TRANSPORT_DEFAULT_TLS
          value: "true"
        volumeMounts:
        - name: passbolt-data
          mountPath: /var/www/passbolt/config/gpg
        - name: passbolt-jwt
          mountPath: /etc/passbolt/jwt
        livenessProbe:
          httpGet:
            path: /healthcheck/status
            port: http
          initialDelaySeconds: 180
          timeoutSeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthcheck/status
            port: http
          initialDelaySeconds: 180
          timeoutSeconds: 5
          periodSeconds: 10
        resources:
          requests:
            memory: "512Mi"
            cpu: "300m"
          limits:
            memory: "1Gi"
            cpu: "600m"
      volumes:
      - name: passbolt-data
        persistentVolumeClaim:
          claimName: passbolt-data
      - name: passbolt-jwt
        persistentVolumeClaim:
          claimName: passbolt-jwt
EOF

    # Crear service.yaml
    cat > "${K8S_DIR}/passbolt/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: passbolt
  namespace: central-platform
  labels:
    app: passbolt
    component: security
spec:
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
  selector:
    app: passbolt
EOF

    # Crear configmap.yaml
    cat > "${K8S_DIR}/passbolt/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: passbolt-config
  namespace: central-platform
  labels:
    app: passbolt
    component: security
data:
  passbolt.php: |
    <?php
    return [
        'debug' => false,
        'App' => [
            'fullBaseUrl' => 'https://passbolt.central-platform.local',
            'cookieSecure' => true
        ],
        'passbolt' => [
            'selenium' => [
                'active' => false
            ],
            'registration' => [
                'public' => false
            ],
            'security' => [
                'setHeaders' => true,
                'csp' => true,
                'cspReportOnly' => false
            ],
            'plugins' => [
                'multiFactorAuthentication' => [
                    'enabled' => true
                ],
                'directorySync' => [
                    'enabled' => true
                ],
                'sso' => [
                    'enabled' => true
                ]
            ]
        ]
    ];
EOF

    # Crear secret.yaml
    cat > "${K8S_DIR}/passbolt/secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: passbolt-secret
  namespace: central-platform
  labels:
    app: passbolt
    component: security
type: Opaque
data:
  db-username: "cGFzc2JvbHQ="  # base64 encoded "passbolt"
  db-password: "c3VwZXJTZWNyZXRQYXNzd29yZA=="  # base64 encoded
  smtp-username: "cGFzc2JvbHRAbWFpbC5jb20="  # base64 encoded
  smtp-password: "c210cFBhc3N3b3Jk"  # base64 encoded
  app-key: "YXBwbGljYXRpb25LZXk="  # base64 encoded
EOF

    # Crear pvc.yaml
    cat > "${K8S_DIR}/passbolt/pvc.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: passbolt-data
  namespace: central-platform
  labels:
    app: passbolt
    component: security
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: passbolt-jwt
  namespace: central-platform
  labels:
    app: passbolt
    component: security
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 256Mi
EOF

    # Crear ingress.yaml
    cat > "${K8S_DIR}/passbolt/ingress.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: passbolt-ingress
  namespace: central-platform
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - passbolt.central-platform.local
    secretName: passbolt-tls
  rules:
  - host: passbolt.central-platform.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: passbolt
            port:
              name: http
EOF

    log_success "Archivos de Passbolt creados correctamente"
}

# Crear archivos de Keycloak
create_keycloak_files() {
    log_info "Creando archivos de Keycloak..."
    
    # Crear statefulset.yaml
    cat > "${K8S_DIR}/keycloak/statefulset.yaml" << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak
  namespace: central-platform
  labels:
    app: keycloak
    component: security
spec:
  serviceName: keycloak-headless
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
        component: security
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:20.0.3
        imagePullPolicy: IfNotPresent
        args:
          - start
          - --import-realm
        ports:
        - name: http
          containerPort: 8080
        - name: https
          containerPort: 8443
        env:
        - name: KEYCLOAK_ADMIN
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: admin-user
        - name: KEYCLOAK_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: admin-password
        - name: KC_DB
          value: "postgres"
        - name: KC_DB_URL
          value: "jdbc:postgresql://postgresql:5432/keycloak"
        - name: KC_DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: db-username
        - name: KC_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-secret
              key: db-password
        - name: KC_HOSTNAME
          value: "keycloak.central-platform.local"
        - name: KC_PROXY
          value: "edge"
        - name: KC_HTTP_RELATIVE_PATH
          value: "/auth"
        volumeMounts:
        - name: keycloak-data
          mountPath: /opt/keycloak/data
        - name: keycloak-providers
          mountPath: /opt/keycloak/providers
        - name: keycloak-themes
          mountPath: /opt/keycloak/themes/central-platform
        - name: realm-config
          mountPath: /opt/keycloak/data/import
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /auth/health/live
            port: http
          initialDelaySeconds: 300
          timeoutSeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /auth/health/ready
            port: http
          initialDelaySeconds: 300
          timeoutSeconds: 5
          periodSeconds: 10
      volumes:
      - name: keycloak-providers
        emptyDir: {}
      - name: keycloak-themes
        configMap:
          name: keycloak-themes
      - name: realm-config
        configMap:
          name: keycloak-realm-config
  volumeClaimTemplates:
  - metadata:
      name: keycloak-data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 2Gi
EOF

    # Crear service.yaml
    cat > "${K8S_DIR}/keycloak/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: central-platform
  labels:
    app: keycloak
    component: security
spec:
  ports:
  - name: http
    port: 8080
    targetPort: http
  - name: https
    port: 8443
    targetPort: https
  selector:
    app: keycloak
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak-headless
  namespace: central-platform
  labels:
    app: keycloak
    component: security
spec:
  clusterIP: None
  ports:
  - name: http
    port: 8080
    targetPort: http
  - name: https
    port: 8443
    targetPort: https
  selector:
    app: keycloak
EOF

    # Crear ingress.yaml
    cat > "${K8S_DIR}/keycloak/ingress.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: central-platform
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "64k"
    nginx.ingress.kubernetes.io/proxy-buffering: "on"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: SAMEORIGIN";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Content-Security-Policy: frame-ancestors 'self'; default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;";
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - keycloak.central-platform.local
    secretName: keycloak-tls
  rules:
  - host: keycloak.central-platform.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              name: http
EOF

    # Crear secret.yaml
    cat > "${K8S_DIR}/keycloak/secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-secret
  namespace: central-platform
  labels:
    app: keycloak
    component: security
type: Opaque
data:
  admin-user: "YWRtaW4="  # base64 encoded "admin"
  admin-password: "YWRtaW4xMjM0NTY="  # base64 encoded "admin123456"
  db-username: "a2V5Y2xvYWs="  # base64 encoded "keycloak"
  db-password: "a2V5Y2xvYWtQYXNzd29yZA=="  # base64 encoded "keycloakPassword"
EOF

    # Crear parte del realm config
    cat > "${K8S_DIR}/keycloak/realm-config/realm.json" << 'EOF'
{
  "id": "central-platform",
  "realm": "central-platform",
  "displayName": "Plataforma Centralizada",
  "displayNameHtml": "<div class=\"kc-logo-text\"><span>Plataforma Centralizada</span></div>",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "permanentLockout": false,
  "maxFailureWaitSeconds": 900,
  "minimumQuickLoginWaitSeconds": 60,
  "waitIncrementSeconds": 60,
  "quickLoginCheckMilliSeconds": 1000,
  "maxDeltaTimeSeconds": 43200,
  "failureFactor": 5,
  "defaultRoles": [
    "usuario_basico"
  ],
  "requiredCredentials": [
    "password"
  ],
  "passwordPolicy": "hashIterations(27500) specialChars(1) upperCase(1) lowerCase(1) digits(1) length(10) forceExpiredPasswordChange(365) notUsername",
  "otpPolicyType": "totp",
  "otpPolicyAlgorithm": "HmacSHA1",
  "otpPolicyInitialCounter": 0,
  "otpPolicyDigits": 6,
  "otpPolicyLookAheadWindow": 1,
  "otpPolicyPeriod": 30
}
EOF

    log_success "Archivos de Keycloak creados correctamente"
}

# Crear archivos de Vault
create_vault_files() {
    log_info "Creando archivos de HashiCorp Vault..."
    
    # Crear statefulset.yaml
    cat > "${K8S_DIR}/vault/statefulset.yaml" << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: central-platform
  labels:
    app: vault
    component: security
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
        component: security
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: vault
        image: hashicorp/vault:1.12.2
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8200
        - name: https
          containerPort: 8201
        env:
        - name: VAULT_LOCAL_CONFIG
          valueFrom:
            configMapKeyRef:
              name: vault-config
              key: vault-config.json
        - name: SKIP_CHOWN
          value: "true"
        - name: SKIP_SETCAP
          value: "true"
        securityContext:
          capabilities:
            add:
            - IPC_LOCK
        volumeMounts:
        - name: vault-data
          mountPath: /vault/file
        - name: vault-logs
          mountPath: /vault/logs
        - name: vault-config
          mountPath: /vault/config
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /v1/sys/health?standbyok=true
            port: 8200
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /v1/sys/health?standbyok=true
            port: 8200
            scheme: HTTP
          initialDelaySeconds: 10
          timeoutSeconds: 5
          periodSeconds: 10
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/sh
              - -c
              - sleep 5 && kill -SIGTERM $(pidof vault)
      volumes:
      - name: vault-config
        configMap:
          name: vault-config
      - name: vault-logs
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: vault-data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 1Gi
EOF

    # Crear service.yaml
    cat > "${K8S_DIR}/vault/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: central-platform
  labels:
    app: vault
    component: security
spec:
  ports:
  - name: http
    port: 8200
    targetPort: 8200
  - name: https
    port: 8201
    targetPort: 8201
  selector:
    app: vault
EOF

    # Crear configmap.yaml
    cat > "${K8S_DIR}/vault/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: central-platform
  labels:
    app: vault
    component: security
data:
  vault-config.json: |
    {
      "ui": true,
      "listener": {
        "tcp": {
          "address": "0.0.0.0:8200",
          "tls_disable": 1
        }
      },
      "storage": {
        "file": {
          "path": "/vault/file"
        }
      },
      "api_addr": "http://vault.central-platform.svc.cluster.local:8200",
      "max_lease_ttl": "768h",
      "default_lease_ttl": "768h",
      "cluster_name": "central-platform-vault"
    }
EOF

    # Crear políticas de Vault
    cat > "${K8S_DIR}/vault/policies/admin-policy.hcl" << 'EOF'
# Política para administradores de Vault
path "sys/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Permitir gestión completa de secretos
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Permitir gestión completa de PKI
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Permitir configuración de métodos de autenticación
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

    # Script de inicialización de Vault
    cat > "${SECURITY_DIR}/secrets/vault/scripts/init-vault.sh" << 'EOF'
#!/bin/bash
# Script para inicializar HashiCorp Vault en Central Platform

set -e

# Configuración
VAULT_ADDR="http://vault.central-platform.svc.cluster.local:8200"
KEY_SHARES=5
KEY_THRESHOLD=3
OUTPUT_FILE="/tmp/vault-init.json"
SECRET_NAME="vault-unseal-keys"
NAMESPACE="central-platform"

echo "Inicializando Vault en $VAULT_ADDR"

# Verificar si Vault ya está inicializado
INITIALIZED=$(curl -s ${VAULT_ADDR}/v1/sys/init | jq .initialized)

if [ "$INITIALIZED" == "true" ]; then
  echo "Vault ya está inicializado."
  exit 0
fi

# Inicializar Vault
echo "Inicializando Vault con $KEY_SHARES shares y $KEY_THRESHOLD threshold..."
curl -s \
  --request POST \
  --data "{\"secret_shares\": $KEY_SHARES, \"secret_threshold\": $KEY_THRESHOLD}" \
  ${VAULT_ADDR}/v1/sys/init > ${OUTPUT_FILE}

if [ $? -ne 0 ]; then
  echo "Error al inicializar Vault."
  exit 1
fi

echo "Vault inicializado correctamente."

# Extraer claves y token
ROOT_TOKEN=$(cat ${OUTPUT_FILE} | jq -r ".root_token")
UNSEAL_KEY_1=$(cat ${OUTPUT_FILE} | jq -r ".unseal_keys_b64[0]")
UNSEAL_KEY_2=$(cat ${OUTPUT_FILE} | jq -r ".unseal_keys_b64[1]")
UNSEAL_KEY_3=$(cat ${OUTPUT_FILE} | jq -r ".unseal_keys_b64[2]")
UNSEAL_KEY_4=$(cat ${OUTPUT_FILE} | jq -r ".unseal_keys_b64[3]")
UNSEAL_KEY_5=$(cat ${OUTPUT_FILE} | jq -r ".unseal_keys_b64[4]")

# Guardar claves en un Secret de Kubernetes
echo "Guardando claves en Secret de Kubernetes..."
kubectl create secret generic ${SECRET_NAME} \
  --namespace=${NAMESPACE} \
  --from-literal=root-token=${ROOT_TOKEN} \
  --from-literal=unseal-key-1=${UNSEAL_KEY_1} \
  --from-literal=unseal-key-2=${UNSEAL_KEY_2} \
  --from-literal=unseal-key-3=${UNSEAL_KEY_3} \
  --from-literal=unseal-key-4=${UNSEAL_KEY_4} \
  --from-literal=unseal-key-5=${UNSEAL_KEY_5}

if [ $? -ne 0 ]; then
  echo "Error al crear el Secret de Kubernetes."
  echo "Por favor guarde el contenido de ${OUTPUT_FILE} en un lugar seguro."
  exit 1
fi

echo "Secret ${SECRET_NAME} creado correctamente."
echo "Guardando claves en un lugar seguro y eliminando el archivo temporal..."
rm ${OUTPUT_FILE}

# Dessellar Vault
echo "Dessellando Vault..."
curl -s --request POST --data "{\"key\": \"$UNSEAL_KEY_1\"}" ${VAULT_ADDR}/v1/sys/unseal
curl -s --request POST --data "{\"key\": \"$UNSEAL_KEY_2\"}" ${VAULT_ADDR}/v1/sys/unseal
curl -s --request POST --data "{\"key\": \"$UNSEAL_KEY_3\"}" ${VAULT_ADDR}/v1/sys/unseal

echo "Vault inicializado y dessellado correctamente."
echo "Por favor, haga una copia de seguridad del Secret ${SECRET_NAME} y guárdelo en un lugar seguro."
EOF
    chmod +x "${SECURITY_DIR}/secrets/vault/scripts/init-vault.sh"

    # Script de backup de Vault
    cat > "${SECURITY_DIR}/secrets/vault/scripts/backup-vault.sh" << 'EOF'
#!/bin/bash
# Script para realizar backup de Vault

set -e

# Variables de configuración
BACKUP_DIR="/backups/vault"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/vault-backup-${DATE}.snap"

# Crear directorio de backup si no existe
mkdir -p ${BACKUP_DIR}

echo "Iniciando backup de Vault en ${BACKUP_FILE}"

# Realizar snapshot de Vault
vault operator raft snapshot save ${BACKUP_FILE}

# Verificar resultado
if [ $? -eq 0 ]; then
    echo "Backup completado exitosamente"
    # Encriptar backup
    gpg --recipient vault-backup --encrypt ${BACKUP_FILE}
    rm ${BACKUP_FILE}
    echo "Backup encriptado como ${BACKUP_FILE}.gpg"
    
    # Eliminar backups antiguos (más de 30 días)
    find ${BACKUP_DIR} -name "vault-backup-*.snap.gpg" -mtime +30 -delete
else
    echo "Error al realizar backup"
    exit 1
fi
EOF
    chmod +x "${SECURITY_DIR}/secrets/vault/scripts/backup-vault.sh"

    log_success "Archivos de HashiCorp Vault creados correctamente"
}

# Crear archivos de WAF (ModSecurity)
create_waf_files() {
    log_info "Creando archivos de WAF (ModSecurity)..."
    
    # Crear deployment.yaml
    cat > "${K8S_DIR}/waf/modsecurity/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: modsecurity
  namespace: central-platform
  labels:
    app: modsecurity
    component: security
spec:
  replicas: 2
  selector:
    matchLabels:
      app: modsecurity
  template:
    metadata:
      labels:
        app: modsecurity
        component: security
    spec:
      containers:
      - name: modsecurity
        image: owasp/modsecurity-crs:3.3.4-nginx
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 80
        env:
        - name: BACKEND
          value: "http://frontend.central-platform.svc.cluster.local:80"
        - name: PROXY_TIMEOUT
          value: "60s"
        - name: PARANOIA
          value: "1"
        - name: ANOMALY_INBOUND
          value: "10"
        - name: ANOMALY_OUTBOUND
          value: "5"
        - name: ALLOWED_METHODS
          value: "GET HEAD POST OPTIONS PUT DELETE"
        - name: ENABLE_DOS_PROTECTION
          value: "1"
        - name: LOGLEVEL
          value: "warn"
        volumeMounts:
        - name: modsecurity-config
          mountPath: /etc/modsecurity.d/modsecurity-override.conf
          subPath: modsecurity-override.conf
        - name: modsecurity-rules
          mountPath: /etc/modsecurity.d/custom-rules
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "400m"
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 10
          timeoutSeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          timeoutSeconds: 2
          periodSeconds: 10
      volumes:
      - name: modsecurity-config
        configMap:
          name: modsecurity-config
      - name: modsecurity-rules
        configMap:
          name: modsecurity-rules
EOF

    # Crear service.yaml
    cat > "${K8S_DIR}/waf/modsecurity/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: modsecurity
  namespace: central-platform
  labels:
    app: modsecurity
    component: security
spec:
  ports:
  - name: http
    port: 80
    targetPort: 80
  selector:
    app: modsecurity
EOF

    # Crear configmap.yaml
    cat > "${K8S_DIR}/waf/modsecurity/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: modsecurity-config
  namespace: central-platform
  labels:
    app: modsecurity
    component: security
data:
  modsecurity-override.conf: |
    # ModSecurity Core Rules Configuration

    # Enable ModSecurity
    SecRuleEngine On

    # HTTP Body Processing
    SecRequestBodyAccess On
    SecResponseBodyAccess On
    SecResponseBodyMimeType text/plain text/html text/xml application/json application/xml
    SecResponseBodyLimit 1024000

    # File Uploads
    SecUploadDir /tmp
    SecUploadFileMode 0600
    SecUploadKeepFiles Off

    # Logging
    SecAuditEngine RelevantOnly
    SecAuditLogRelevantStatus "^(?:5|4(?!04))"
    SecAuditLogParts ABCEFHJZ
    SecAuditLogType Serial
    SecAuditLog /dev/stdout

    # Misc
    SecConnEngine Off
    SecArgumentSeparator &
    SecCookieFormat 0
    SecUnicodeMapFile unicode.mapping 20127
    SecDataDir /tmp

    # Central Platform specific rules
    SecRule REQUEST_URI "@beginsWith /api/v1/auth" "id:1000,phase:1,t:none,nolog,allow,ctl:ruleRemoveTargetById=920440;ARGS:password"
    SecRule REQUEST_URI "@beginsWith /api/v1/users" "id:1001,phase:1,t:none,nolog,allow,ctl:ruleRemoveTargetById=920440;ARGS:password"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: modsecurity-rules
  namespace: central-platform
  labels:
    app: modsecurity
    component: security
data:
  custom-rules.conf: |
    # Custom rules for Central Platform
    # Block common attack vectors

    # XSS Protection
    SecRule REQUEST_COOKIES|REQUEST_COOKIES_NAMES|REQUEST_HEADERS|ARGS_NAMES|ARGS|XML:/* "@detectXSS" \
        "id:1002,\
        phase:2,\
        deny,\
        status:403,\
        log,\
        msg:'XSS Attack Detected',\
        logdata:'Matched Data: %{MATCHED_VAR} found within %{MATCHED_VAR_NAME}',\
        severity:'CRITICAL'"

    # SQL Injection Protection
    SecRule REQUEST_COOKIES|REQUEST_COOKIES_NAMES|REQUEST_HEADERS|ARGS_NAMES|ARGS|XML:/* "@detectSQLi" \
        "id:1003,\
        phase:2,\
        deny,\
        status:403,\
        log,\
        msg:'SQL Injection Attack Detected',\
        logdata:'Matched Data: %{MATCHED_VAR} found within %{MATCHED_VAR_NAME}',\
        severity:'CRITICAL'"

    # Allow specific endpoints for file uploads
    SecRule REQUEST_URI "@beginsWith /api/v1/devices/upload" \
        "id:1004,\
        phase:1,\
        t:none,\
        nolog,\
        pass,\
        ctl:ruleRemoveById=200003"
EOF

    log_success "Archivos de WAF (ModSecurity) creados correctamente"
}

# Crear archivos de Falco (Detección de Intrusiones)
create_falco_files() {
    log_info "Creando archivos de Falco (Detección de Intrusiones)..."
    
    # Crear daemonset.yaml
    cat > "${K8S_DIR}/siem/falco/daemonset.yaml" << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: falco
  namespace: central-platform
  labels:
    app: falco
    component: security
spec:
  selector:
    matchLabels:
      app: falco
  template:
    metadata:
      labels:
        app: falco
        component: security
    spec:
      serviceAccountName: falco
      hostPID: true
      containers:
      - name: falco
        image: falcosecurity/falco:0.33.1
        securityContext:
          privileged: true
        args:
          - /usr/bin/falco
          - -K
          - /var/run/secrets/kubernetes.io/serviceaccount/token
          - -k
          - https://kubernetes.default.svc.cluster.local
          - -pk
        env:
        - name: FALCO_BPF_PROBE
          value: ""
        - name: SYSDIG_BPF_PROBE
          value: ""
        volumeMounts:
        - mountPath: /host/var/run/docker.sock
          name: docker-socket
        - mountPath: /host/dev
          name: dev-fs
        - mountPath: /host/proc
          name: proc-fs
          readOnly: true
        - mountPath: /host/boot
          name: boot-fs
          readOnly: true
        - mountPath: /host/lib/modules
          name: lib-modules
          readOnly: true
        - mountPath: /host/usr
          name: usr-fs
          readOnly: true
        - mountPath: /etc/falco
          name: falco-config
      volumes:
      - name: docker-socket
        hostPath:
          path: /var/run/docker.sock
      - name: dev-fs
        hostPath:
          path: /dev
      - name: proc-fs
        hostPath:
          path: /proc
      - name: boot-fs
        hostPath:
          path: /boot
      - name: lib-modules
        hostPath:
          path: /lib/modules
      - name: usr-fs
        hostPath:
          path: /usr
      - name: falco-config
        configMap:
          name: falco-config
EOF

    # Crear configuración de Falco
    cat > "${K8S_DIR}/siem/falco/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-config
  namespace: central-platform
  labels:
    app: falco
    component: security
data:
  falco.yaml: |
    program_output:
      enabled: true
      keep_alive: false
      program: "curl -s -o /dev/null -w '%{http_code}' -d @- -H 'Content-Type: application/json' -H 'Authorization: Bearer ${FALCO_ALERT_TOKEN}' ${FALCO_ALERT_ENDPOINT}"

    http_output:
      enabled: true
      url: "http://loki.central-platform.svc.cluster.local:3100/loki/api/v1/push"

    file_output:
      enabled: true
      filename: /var/log/falco/falco.log
      
    syslog_output:
      enabled: true
      
    stdout_output:
      enabled: true

  central-platform-rules.yaml: |
    - rule: Unauthorized Process in Container
      desc: Detect a process running in a container that is not expected
      condition: >
        container
        and container.image.repository in (frontend, api-rest, websocket, iot-gateway)
        and not proc.name in (node, npm, python, fastapi, gunicorn, uvicorn, bash, sh, ps, ls, netstat, mount, hostname)
      output: Unexpected process running in container (user=%user.name user_loginuid=%user.loginuid command=%proc.cmdline container_id=%container.id container_name=%container.name image=%container.image.repository)
      priority: WARNING
      tags: [process, container, mitre_execution]

    - rule: Sensitive File Accessed
      desc: Detect sensitive file access
      condition: >
        open_read and
        fd.name startswith /etc/passwd or fd.name startswith /etc/shadow or
        fd.name startswith /etc/hosts or
        fd.name startswith /etc/kubernetes/admin.conf or
        fd.name startswith /var/run/secrets
      output: Sensitive file accessed (user=%user.name user_loginuid=%user.loginuid command=%proc.cmdline file=%fd.name container_id=%container.id container_name=%container.name image=%container.image.repository)
      priority: WARNING
      tags: [file, container, mitre_credential_access]

    - rule: Outbound Connection to Suspicious Network
      desc: Detect outbound network connections to suspicious networks
      condition: >
        outbound and
        not socket.remote.ip in (127.0.0.1/8) and
        not socket.remote.ip in (10.0.0.0/8) and
        not socket.remote.ip in (172.16.0.0/12) and
        not socket.remote.ip in (192.168.0.0/16) and
        container and
        container.image.repository in (frontend, api-rest, websocket, iot-gateway) and
        not (container.image.repository=frontend and dest_port=443) and
        not (container.image.repository=api-rest and dest_port=443)
      output: Suspicious outbound connection (user=%user.name user_loginuid=%user.loginuid command=%proc.cmdline container_id=%container.id container_name=%container.name image=%container.image.repository connection=%fd.name)
      priority: WARNING
      tags: [network, container, mitre_command_and_control]

    - rule: API Credential Access
      desc: Detect access to API credentials
      condition: >
        spawned_process and
        container and
        proc.cmdline contains "password" or
        proc.cmdline contains "secret" or
        proc.cmdline contains "token" or
        proc.cmdline contains "apikey" or
        proc.cmdline contains "credential"
      output: API credential access detected (user=%user.name user_loginuid=%user.loginuid command=%proc.cmdline container_id=%container.id container_name=%container.name image=%container.image.repository)
      priority: WARNING
      tags: [process, container, mitre_credential_access]
EOF

    # Crear rbac.yaml para Falco
    cat > "${K8S_DIR}/siem/falco/rbac.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: falco
  namespace: central-platform
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: falco
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "namespaces", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: falco
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: falco
subjects:
- kind: ServiceAccount
  name: falco
  namespace: central-platform
EOF

    log_success "Archivos de Falco (Detección de Intrusiones) creados correctamente"
}

# Crear scripts de auditoría y respuesta a incidentes
create_security_scripts() {
    log_info "Creando scripts de auditoría y respuesta a incidentes..."
    
    # Script de auditoría de accesos
    cat > "${SECURITY_DIR}/scripts/audit/audit-access.sh" << 'EOF'
#!/bin/bash
# Script para auditar accesos a la plataforma

set -e

# Variables de configuración
LOG_DIR="/var/log/central-platform/audit"
REPORT_DIR="/var/log/central-platform/reports"
DATE=$(date +%Y%m%d)
REPORT_FILE="${REPORT_DIR}/access-audit-${DATE}.log"

# Crear directorios si no existen
mkdir -p ${LOG_DIR}
mkdir -p ${REPORT_DIR}

echo "=== Informe de auditoría de accesos - $(date) ===" > ${REPORT_FILE}
echo "" >> ${REPORT_FILE}

# Obtener logs de autenticación de Keycloak
echo "== Logs de autenticación de Keycloak ==" >> ${REPORT_FILE}
kubectl logs -n central-platform -l app=keycloak --since=24h | grep -E "LOGIN|LOGOUT" | sort -k1,1 >> ${REPORT_FILE}

# Obtener logs de OAuth2 Proxy
echo "" >> ${REPORT_FILE}
echo "== Logs de OAuth2 Proxy ==" >> ${REPORT_FILE}
kubectl logs -n central-platform -l app=oauth2-proxy --since=24h | grep -E "authentication|session" | sort -k1,1 >> ${REPORT_FILE}

# Obtener accesos a la API
echo "" >> ${REPORT_FILE}
echo "== Accesos a la API ==" >> ${REPORT_FILE}
kubectl logs -n central-platform -l app=api-rest --since=24h | grep -E "auth|user" | sort -k1,1 >> ${REPORT_FILE}

# Sumarizar resultados
echo "" >> ${REPORT_FILE}
echo "== Resumen ==" >> ${REPORT_FILE}
echo "Total de inicios de sesión: $(grep -c "LOGIN" ${REPORT_FILE})" >> ${REPORT_FILE}
echo "Total de cierres de sesión: $(grep -c "LOGOUT" ${REPORT_FILE})" >> ${REPORT_FILE}
echo "Fallos de autenticación: $(grep -c "authentication failure" ${REPORT_FILE})" >> ${REPORT_FILE}

echo "Informe de auditoría generado: ${REPORT_FILE}"
EOF
    chmod +x "${SECURITY_DIR}/scripts/audit/audit-access.sh"

    # Script de recolección de evidencia forense
    cat > "${SECURITY_DIR}/scripts/incident-response/collect-evidence.sh" << 'EOF'
#!/bin/bash
# Script para recolectar evidencia forense

# Configuración
POD_NAME=$1
NAMESPACE=$2
OUTPUT_DIR="/forensics/${NAMESPACE}_${POD_NAME}_$(date +%Y%m%d%H%M%S)"
LOG_FILE="${OUTPUT_DIR}/collection.log"

# Validar argumentos
if [ -z "$POD_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "Uso: $0 <nombre-del-pod> <namespace>"
  exit 1
fi

# Crear directorio de salida
mkdir -p $OUTPUT_DIR
echo "Iniciando recolección forense para ${NAMESPACE}/${POD_NAME} en $(date)" | tee -a $LOG_FILE

# Obtener información del pod
echo "Recolectando información básica del pod..." | tee -a $LOG_FILE
kubectl get pod $POD_NAME -n $NAMESPACE -o json > "${OUTPUT_DIR}/pod_info.json"
kubectl describe pod $POD_NAME -n $NAMESPACE > "${OUTPUT_DIR}/pod_describe.txt"

# Obtener logs del pod
echo "Recolectando logs del pod..." | tee -a $LOG_FILE
kubectl logs $POD_NAME -n $NAMESPACE --all-containers=true > "${OUTPUT_DIR}/pod_logs.txt"
kubectl logs $POD_NAME -n $NAMESPACE --all-containers=true --previous > "${OUTPUT_DIR}/pod_logs_previous.txt" 2>/dev/null

# Crear directorio para cada contenedor
containers=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].name}')
for container in $containers; do
  echo "Recolectando datos para contenedor: $container" | tee -a $LOG_FILE
  container_dir="${OUTPUT_DIR}/${container}"
  mkdir -p $container_dir
  
  # Obtener logs específicos del contenedor
  kubectl logs $POD_NAME -n $NAMESPACE -c $container > "${container_dir}/container_logs.txt"
  
  # Obtener información de procesos en ejecución
  kubectl exec $POD_NAME -n $NAMESPACE -c $container -- ps auxwf > "${container_dir}/processes.txt" 2>/dev/null
  
  # Obtener información de red
  kubectl exec $POD_NAME -n $NAMESPACE -c $container -- netstat -antup > "${container_dir}/network_connections.txt" 2>/dev/null
  
  # Obtener historial de comandos
  kubectl exec $POD_NAME -n $NAMESPACE -c $container -- cat /root/.bash_history > "${container_dir}/bash_history.txt" 2>/dev/null
  
  # Obtener archivos modificados recientemente
  kubectl exec $POD_NAME -n $NAMESPACE -c $container -- find / -type f -mtime -1 -not -path "/proc/*" -not -path "/sys/*" > "${container_dir}/recent_files.txt" 2>/dev/null
  
  # Obtener lista de paquetes instalados (para imágenes basadas en apt)
  kubectl exec $POD_NAME -n $NAMESPACE -c $container -- dpkg -l > "${container_dir}/packages.txt" 2>/dev/null
  
  # Intentar obtener binarios sospechosos
  suspicious_procs=$(kubectl exec $POD_NAME -n $NAMESPACE -c $container -- sh -c "ls -la /proc/*/exe | grep deleted" 2>/dev/null)
  if [ ! -z "$suspicious_procs" ]; then
    echo "$suspicious_procs" > "${container_dir}/suspicious_processes.txt"
    echo "¡ALERTA! Procesos sospechosos detectados en el contenedor $container" | tee -a $LOG_FILE
  fi
done

# Recolectar información de eventos del cluster
echo "Recolectando eventos del namespace..." | tee -a $LOG_FILE
kubectl get events -n $NAMESPACE > "${OUTPUT_DIR}/namespace_events.txt"

# Comprimir la evidencia
cd $(dirname $OUTPUT_DIR)
tar -czf "${OUTPUT_DIR}.tar.gz" $(basename $OUTPUT_DIR)
echo "Evidencia recolectada y comprimida en ${OUTPUT_DIR}.tar.gz" | tee -a $LOG_FILE

# Hash de verificación
sha256sum "${OUTPUT_DIR}.tar.gz" > "${OUTPUT_DIR}.tar.gz.sha256"
echo "Proceso de recolección forense completado en $(date)" | tee -a $LOG_FILE
EOF
chmod +x "${SECURITY_DIR}/scripts/incident-response/collect-evidence.sh"

# Script para habilitar MFA para usuarios con roles específicos
cat > "${SECURITY_DIR}/scripts/hardening/enable-mfa-for-roles.sh" << 'EOF'
#!/bin/bash
# Script para aplicar MFA a usuarios con roles específicos

# Parámetros
ROLES="$1" # Roles que requieren MFA separados por coma

# Obtener token de administrador
admin_token=$(curl -s -X POST \
  "https://keycloak.central-platform.local/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r '.access_token')

# Obtener todos los usuarios
users=$(curl -s -X GET \
  "https://keycloak.central-platform.local/admin/realms/central-platform/users" \
  -H "Authorization: Bearer ${admin_token}")

# Procesar cada usuario
echo $users | jq -c '.[]' | while read -r user; do
  user_id=$(echo $user | jq -r '.id')
  username=$(echo $user | jq -r '.username')
  
  # Obtener roles del usuario
  user_roles=$(curl -s -X GET \
    "https://keycloak.central-platform.local/admin/realms/central-platform/users/${user_id}/role-mappings/realm" \
    -H "Authorization: Bearer ${admin_token}" | jq -r '.[].name')
  
  # Verificar si el usuario tiene alguno de los roles que requieren MFA
  IFS=',' read -ra ROLE_ARRAY <<< "$ROLES"
  require_mfa=false
  
  for role in "${ROLE_ARRAY[@]}"; do
    if echo "$user_roles" | grep -q "^$role$"; then
      require_mfa=true
      break
    fi
  done
  
  # Aplicar acción requerida si es necesario
  if [ "$require_mfa" = true ]; then
    echo "Habilitando MFA para usuario: $username"
    
    curl -s -X PUT \
      "https://keycloak.central-platform.local/admin/realms/central-platform/users/${user_id}" \
      -H "Authorization: Bearer ${admin_token}" \
      -H "Content-Type: application/json" \
      -d "$(echo $user | jq '. + {requiredActions: ["CONFIGURE_TOTP"]}')"
  fi
done

echo "Proceso completado."
EOF
chmod +x "${SECURITY_DIR}/scripts/hardening/enable-mfa-for-roles.sh"

# Script para configurar hardening de nodos
cat > "${SECURITY_DIR}/scripts/hardening/harden-nodes.sh" << 'EOF'
#!/bin/bash
# Script para endurecer la seguridad de los nodos de Kubernetes
# Ejecutar en cada nodo del cluster

set -e

echo "Iniciando endurecimiento de seguridad para nodo $(hostname)..."

# 1. Actualizar el sistema
echo "Actualizando paquetes del sistema..."
apt-get update
apt-get upgrade -y

# 2. Configurar firewall (UFW)
echo "Configurando firewall..."
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
# Puertos necesarios para Kubernetes
ufw allow 22/tcp
ufw allow 6443/tcp # API server
ufw allow 2379:2380/tcp # etcd
ufw allow 10250/tcp # Kubelet
ufw allow 10251/tcp # kube-scheduler
ufw allow 10252/tcp # kube-controller-manager
ufw allow 10255/tcp # Kubelet read-only
ufw allow 8472/udp # Flannel/Calico
ufw allow 179/tcp # Calico BGP
ufw allow 51820/udp # Wireguard if used
echo "y" | ufw enable

# 3. Endurecer la configuración de SSH
echo "Endureciendo configuración SSH..."
cat > /etc/ssh/sshd_config.d/hardening.conf << 'EOL'
# Valores recomendados para SSH
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
Protocol 2
MaxAuthTries 3
LoginGraceTime 60
AllowTcpForwarding no
X11Forwarding no
EOL
systemctl restart sshd

# 4. Configurar kernel securely
echo "Configurando parámetros de kernel..."
cat > /etc/sysctl.d/99-kubernetes-security.conf << 'EOL'
# Parámetros de seguridad del kernel
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOL
sysctl -p /etc/sysctl.d/99-kubernetes-security.conf

# 5. Configurar auditd
echo "Configurando auditoría del sistema..."
apt-get install -y auditd audispd-plugins
cat > /etc/audit/rules.d/kubernetes.rules << 'EOL'
# Reglas Kubernetes para auditd
-w /etc/kubernetes/admin.conf -p wa -k kubernetes_conf
-w /etc/kubernetes/scheduler.conf -p wa -k kubernetes_conf
-w /etc/kubernetes/controller-manager.conf -p wa -k kubernetes_conf
-w /etc/kubernetes/kubelet.conf -p wa -k kubernetes_conf
-w /etc/kubernetes/manifests/ -p wa -k kubernetes_manifests
-w /var/lib/kubelet/ -p wa -k kubelet
-w /var/log/audit/ -p wa -k audit_log
-w /etc/kubernetes/ -p wa -k kubernetes
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity
EOL
systemctl restart auditd

# 6. Instalar y configurar AIDE (Advanced Intrusion Detection Environment)
echo "Instalando AIDE..."
apt-get install -y aide
cat > /etc/aide/aide.conf.d/kubernetes.conf << 'EOL'
# Reglas AIDE para directorios de Kubernetes
/etc/kubernetes R
/var/lib/kubelet R
/var/lib/etcd R
EOL
aideinit
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# 7. Configurar tarea cron para AIDE
echo "Configurando tarea cron para AIDE..."
echo "0 3 * * * /usr/bin/aide --check -V4 | mail -s 'AIDE check report for $(hostname)' root" > /etc/cron.d/aide-check
chmod 644 /etc/cron.d/aide-check

# 8. Configurar LogRotate
echo "Configurando LogRotate..."
cat > /etc/logrotate.d/kubernetes << 'EOL'
/var/log/kubernetes/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOL

# 9. Limitar acceso a binarios críticos
echo "Restringiendo acceso a binarios críticos..."
chmod 750 /usr/bin/kubectl
chmod 750 /usr/bin/kubelet
chmod 750 /usr/bin/kubeadm

echo "Endurecimiento de seguridad del nodo completado."
EOF
chmod +x "${SECURITY_DIR}/scripts/hardening/harden-nodes.sh"

# Script para endurecimiento de contenedores
cat > "${SECURITY_DIR}/scripts/hardening/harden-containers.sh" << 'EOF'
#!/bin/bash
# Script para aplicar políticas de seguridad a nivel de contenedores

set -e

echo "Implementando políticas de seguridad para contenedores..."

# 1. Crear PodSecurityPolicy para la plataforma
cat > "${K8S_DIR}/pod-security-policy.yaml" << 'EOT'
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: central-platform-restricted
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'runtime/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName: 'runtime/default'
    apparmor.security.beta.kubernetes.io/allowedProfileNames: 'runtime/default'
    apparmor.security.beta.kubernetes.io/defaultProfileName: 'runtime/default'
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      - min: 1
        max: 65535
  readOnlyRootFilesystem: true
EOT

# 2. Aplicar la política
kubectl apply -f "${K8S_DIR}/pod-security-policy.yaml"

# 3. Crear rol y rolebinding para PSP
cat > "${K8S_DIR}/psp-rbac.yaml" << 'EOT'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: psp:central-platform-restricted
  namespace: central-platform
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs: ['use']
  resourceNames: ['central-platform-restricted']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: central-platform:psp:restricted
  namespace: central-platform
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: psp:central-platform-restricted
subjects:
- kind: ServiceAccount
  name: default
  namespace: central-platform
EOT

kubectl apply -f "${K8S_DIR}/psp-rbac.yaml"

# 4. Crear NetworkPolicy para aislar contenedores
cat > "${K8S_DIR}/network-policies/container-isolation.yaml" << 'EOT'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all-pods
  namespace: central-platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: central-platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOT

kubectl apply -f "${K8S_DIR}/network-policies/container-isolation.yaml"

# 5. Verificar aplicación de políticas
kubectl get podsecuritypolicy central-platform-restricted
kubectl get networkpolicies -n central-platform

echo "Políticas de seguridad para contenedores aplicadas correctamente."
EOF
chmod +x "${SECURITY_DIR}/scripts/hardening/harden-containers.sh"

# Script de respuesta a incidentes - Contención
cat > "${SECURITY_DIR}/scripts/incident-response/containment.sh" << 'EOF'
#!/bin/bash
# Script para contención de incidentes de seguridad

set -e

# Verificar argumentos
if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <namespace> <pod-o-deployment> [tipo: pod|deployment]"
  exit 1
fi

NAMESPACE=$1
TARGET=$2
TYPE=${3:-pod}  # Por defecto asume que es un pod

echo "Iniciando procedimiento de contención para $TYPE: $TARGET en namespace: $NAMESPACE"

# Función para aislar un pod mediante NetworkPolicy
isolate_pod() {
  local pod=$1
  local ns=$2
  
  echo "Aislando el pod $pod mediante NetworkPolicy..."
  
  # Obtener etiquetas del pod para selector
  local pod_labels=$(kubectl get pod $pod -n $ns -o jsonpath='{.metadata.labels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
  
  # Crear NetworkPolicy para aislar el pod
  cat > isolation-policy.yaml << EOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-${pod}
  namespace: ${ns}
spec:
  podSelector:
    matchLabels:
      $(echo $pod_labels | sed 's/,/\n      /g')
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOL
  
  kubectl apply -f isolation-policy.yaml
  echo "Pod $pod aislado. Solo se permite tráfico DNS."
}

# Función para tomar una imagen forense del pod
take_forensic_image() {
  local pod=$1
  local ns=$2
  
  echo "Tomando imagen forense del pod $pod..."
  
  # Directorio para evidencia
  local evidence_dir="/var/log/security/forensics/${ns}_${pod}_$(date +%Y%m%d%H%M%S)"
  mkdir -p $evidence_dir
  
  # Obtener información y logs del pod
  kubectl get pod $pod -n $ns -o json > "${evidence_dir}/pod-info.json"
  kubectl logs $pod -n $ns --all-containers > "${evidence_dir}/all-logs.txt"
  
  # Para cada contenedor en el pod
  containers=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}')
  for container in $containers; do
    echo "Obteniendo datos de contenedor: $container"
    mkdir -p "${evidence_dir}/${container}"
    
    # Obtener información del sistema de archivos
    kubectl exec $pod -n $ns -c $container -- find / -type f -mtime -1 > "${evidence_dir}/${container}/recent-files.txt" 2>/dev/null || true
    kubectl exec $pod -n $ns -c $container -- ps auxwf > "${evidence_dir}/${container}/processes.txt" 2>/dev/null || true
    kubectl exec $pod -n $ns -c $container -- netstat -antup > "${evidence_dir}/${container}/network.txt" 2>/dev/null || true
    kubectl exec $pod -n $ns -c $container -- lsof > "${evidence_dir}/${container}/open-files.txt" 2>/dev/null || true
  done
  
  # Empaquetar evidencia
  tar -czf "${evidence_dir}.tar.gz" $evidence_dir
  echo "Imagen forense guardada en: ${evidence_dir}.tar.gz"
  
  # Calcular hash de la evidencia para cadena de custodia
  sha256sum "${evidence_dir}.tar.gz" > "${evidence_dir}.tar.gz.sha256"
}

# Función para aislar un deployment
isolate_deployment() {
  local deployment=$1
  local ns=$2
  
  echo "Aislando el deployment $deployment..."
  
  # Obtener etiquetas del deployment para selector
  local deploy_labels=$(kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
  
  # Crear NetworkPolicy para aislar el deployment
  cat > isolation-policy-deployment.yaml << EOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-${deployment}
  namespace: ${ns}
spec:
  podSelector:
    matchLabels:
      $(echo $deploy_labels | sed 's/,/\n      /g')
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOL
  
  kubectl apply -f isolation-policy-deployment.yaml
  
  # Escalar el deployment a 0 réplicas si es necesario
  read -p "¿Desea escalar el deployment a 0 réplicas? (s/n): " scale_down
  if [[ $scale_down == "s" ]]; then
    kubectl scale deployment $deployment -n $ns --replicas=0
    echo "Deployment $deployment escalado a 0 réplicas."
  fi
}

# Ejecutar acciones según el tipo
if [[ "$TYPE" == "pod" ]]; then
  # Verificar si el pod existe
  if ! kubectl get pod $TARGET -n $NAMESPACE &> /dev/null; then
    echo "Error: El pod $TARGET no existe en el namespace $NAMESPACE"
    exit 1
  fi
  
  take_forensic_image $TARGET $NAMESPACE
  
  read -p "¿Desea aislar el pod del resto de la red? (s/n): " isolate
  if [[ $isolate == "s" ]]; then
    isolate_pod $TARGET $NAMESPACE
  fi
  
  read -p "¿Desea eliminar el pod después de la contención? (s/n): " delete_pod
  if [[ $delete_pod == "s" ]]; then
    kubectl delete pod $TARGET -n $NAMESPACE
    echo "Pod $TARGET eliminado."
  fi
  
elif [[ "$TYPE" == "deployment" ]]; then
  # Verificar si el deployment existe
  if ! kubectl get deployment $TARGET -n $NAMESPACE &> /dev/null; then
    echo "Error: El deployment $TARGET no existe en el namespace $NAMESPACE"
    exit 1
  fi
  
  # Obtener pods asociados con el deployment
  pods=$(kubectl get pods -n $NAMESPACE -l app=$TARGET -o name | cut -d/ -f2)
  
  echo "Pods asociados con el deployment $TARGET:"
  echo $pods
  
  for pod in $pods; do
    take_forensic_image $pod $NAMESPACE
  done
  
  read -p "¿Desea aislar el deployment del resto de la red? (s/n): " isolate
  if [[ $isolate == "s" ]]; then
    isolate_deployment $TARGET $NAMESPACE
  fi
else
  echo "Tipo no válido. Use 'pod' o 'deployment'."
  exit 1
fi

echo "Procedimiento de contención completado."
EOF
chmod +x "${SECURITY_DIR}/scripts/incident-response/containment.sh"

log_success "Scripts de seguridad creados correctamente"
}

# Crear archivos de documentación de seguridad
create_security_docs() {
    log_info "Creando documentación de seguridad..."
    
    # Documento de visión general de arquitectura de seguridad
    cat > "${DOCS_DIR}/architecture/overview.md" << 'EOF'
# Arquitectura de Seguridad - Plataforma Centralizada de Información

## Visión General

La arquitectura de seguridad de la Plataforma Centralizada de Información está diseñada siguiendo el principio de defensa en profundidad, implementando múltiples capas de seguridad para proteger los datos, servicios y usuarios de la plataforma.

## Componentes Principales

### 1. Autenticación y Autorización

#### 1.1. OAuth2 Proxy con Microsoft 365 SSO
- **Propósito**: Proporcionar autenticación única para todos los servicios de la plataforma utilizando las cuentas corporativas de Microsoft 365.
- **Implementación**: Despliegue de OAuth2 Proxy como intermediario para validar tokens JWT y sesiones.
- **Beneficios**: Experiencia de usuario unificada, políticas de seguridad centralizadas, y cumplimiento de políticas corporativas existentes.

#### 1.2. Keycloak (Servidor de Identidad)
- **Propósito**: Gestión de identidades, autenticación y autorización para aplicaciones y servicios.
- **Implementación**: Servidor Keycloak con integración a Microsoft 365 y gestión de roles específicos de la plataforma.
- **Beneficios**: Gestión granular de permisos, federación de identidades, y flujos OAuth2/OIDC estándar.

### 2. Seguridad de Red

#### 2.1. Network Policies
- **Propósito**: Controlar el tráfico de red entre pods y servicios dentro del cluster Kubernetes.
- **Implementación**: Políticas restrictivas con enfoque "deny-by-default".
- **Beneficios**: Aislamiento de componentes, limitación de movimiento lateral, y protección contra comunicaciones no autorizadas.

#### 2.2. Web Application Firewall (WAF)
- **Propósito**: Proteger aplicaciones web contra ataques comunes (OWASP Top 10).
- **Implementación**: ModSecurity con OWASP Core Rule Set (CRS).
- **Beneficios**: Protección contra XSS, inyección SQL, y otros ataques web comunes.

### 3. Gestión de Secretos

#### 3.1. HashiCorp Vault
- **Propósito**: Almacenamiento seguro de secretos, credenciales y material criptográfico.
- **Implementación**: Servidor Vault con políticas de acceso estrictas.
- **Beneficios**: Gestión centralizada de secretos, rotación automática, y auditoría detallada.

#### 3.2. Passbolt
- **Propósito**: Gestión de contraseñas para usuarios finales y equipos.
- **Implementación**: Servidor Passbolt con cifrado OpenPGP.
- **Beneficios**: Compartición segura de credenciales en equipos, gestión de acceso, y recuperación controlada.

### 4. Seguridad de Infraestructura

#### 4.1. Cert-Manager
- **Propósito**: Gestión automatizada de certificados TLS.
- **Implementación**: Cert-Manager con Let's Encrypt para emisión y renovación automática.
- **Beneficios**: Comunicaciones cifradas, confianza del usuario, y cumplimiento de políticas de seguridad.

#### 4.2. Falco (Detección de Intrusiones)
- **Propósito**: Monitoreo de comportamiento del sistema para detectar actividades maliciosas.
- **Implementación**: Reglas personalizadas para detectar comportamientos anómalos en contenedores y nodos.
- **Beneficios**: Detección temprana de intrusiones, visibilidad de actividades sospechosas, y evidencia para análisis forense.

### 5. Cumplimiento y Auditoría

#### 5.1. Registro y Monitoreo
- **Propósito**: Capturar y analizar eventos de seguridad en toda la plataforma.
- **Implementación**: Centralización de logs con Loki, alertas con Prometheus, y visualización con Grafana.
- **Beneficios**: Visibilidad completa, detección de anomalías, y cumplimiento de requisitos de auditoría.

#### 5.2. Escaneo de Vulnerabilidades
- **Propósito**: Identificación proactiva de vulnerabilidades en imágenes y código.
- **Implementación**: Trivy para escaneo de imágenes de contenedores y SonarQube para análisis de código.
- **Beneficios**: Reducción de superficie de ataque, corrección temprana, y mejora continua de seguridad.

## Arquitectura de Capas

La seguridad está implementada en múltiples capas:

1. **Capa de Perímetro**:
   - Ingress Controllers con TLS
   - Web Application Firewall
   - DDoS Protection

2. **Capa de Acceso**:
   - OAuth2 Proxy
   - Keycloak
   - Network Policies

3. **Capa de Aplicación**:
   - Validación de entradas
   - Sanitización de datos
   - Protección contra ataques OWASP Top 10

4. **Capa de Datos**:
   - Cifrado en reposo
   - Control de acceso basado en roles
   - Política de datos mínimos necesarios

5. **Capa de Monitoreo**:
   - Detección de intrusiones
   - Análisis de comportamiento
   - Alertas en tiempo real

## Consideraciones y Mejores Prácticas

### Principio de Privilegio Mínimo
Todos los componentes operan con los mínimos privilegios necesarios para realizar sus funciones.

### Seguridad por Diseño
La seguridad está integrada desde el inicio del diseño, no como una capa añadida posteriormente.

### Estrategia de Respuesta a Incidentes
Se han definido procedimientos claros de respuesta a incidentes para garantizar una acción rápida y efectiva.

### Actualizaciones y Parches
Proceso automatizado para la aplicación de parches de seguridad críticos en todos los componentes.

### Segmentación
Separación clara de entornos y componentes para limitar el impacto de posibles brechas.
EOF

    # Documento de política de control de acceso
    cat > "${DOCS_DIR}/policies/access-control.md" << 'EOF'
# Política de Control de Acceso

## Propósito

Esta política define los requisitos y procedimientos para garantizar un control de acceso adecuado a los sistemas, aplicaciones y datos de la Plataforma Centralizada de Información.

## Alcance

Esta política aplica a todos los usuarios, sistemas, aplicaciones y servicios dentro de la Plataforma Centralizada de Información.

## Principios Generales

1. **Principio de privilegio mínimo**: Los usuarios, procesos y sistemas solo deben tener acceso a los recursos que necesitan para realizar sus funciones.

2. **Segregación de funciones**: Las responsabilidades críticas deben estar divididas entre diferentes individuos para prevenir conflictos de interés y reducir el riesgo de actividades maliciosas.

3. **Necesidad de conocer**: El acceso a la información debe limitarse a las personas que necesitan conocerla para realizar sus tareas.

4. **Control de acceso basado en roles (RBAC)**: Los permisos se asignan a roles, y los roles se asignan a usuarios.

## Roles y Responsabilidades

### Roles del Sistema

1. **usuario_basico**: Acceso básico a la plataforma
2. **operador**: Operador de la plataforma
3. **administrador**: Administrador de la plataforma
4. **gestor_dispositivos**: Puede gestionar dispositivos
5. **gestor_alertas**: Puede gestionar alertas
6. **analista**: Puede acceder a analíticas
7. **auditor**: Puede auditar acciones

### Matriz de Permisos

| Rol | Dispositivos | Alertas | Analíticas | Configuración | Usuarios |
|-----|--------------|---------|------------|---------------|----------|
| usuario_basico | Ver | Ver propias | - | - | - |
| operador | Ver, Editar | Ver, Gestionar | Ver | Ver | - |
| gestor_dispositivos | Ver, Crear, Editar, Eliminar | - | - | - | - |
| gestor_alertas | Ver | Ver, Crear, Editar, Eliminar | - | - | - |
| analista | Ver | Ver | Ver, Crear informes | - | - |
| administrador | Ver, Crear, Editar, Eliminar | Ver, Crear, Editar, Eliminar | Ver, Crear informes | Ver, Editar | Ver, Crear, Editar, Eliminar |
| auditor | Ver | Ver | Ver | Ver | Ver |

## Gestión de Acceso

### Aprovisionamiento de Usuarios

1. Los usuarios se crean principalmente a través de la integración con Microsoft 365.
2. Para usuarios que no están en Azure AD, se utiliza un proceso manual aprobado por el administrador del sistema.

### Autenticación

1. **Autenticación Single Sign-On (SSO)**: Se utiliza Microsoft 365 como proveedor de identidad principal.
2. **Autenticación Multi-Factor (MFA)**: Obligatoria para roles con privilegios elevados (administrador, operador).
3. **Gestión de Contraseñas**: Las contraseñas deben cumplir los requisitos de complejidad y expiración.

### Revocación de Acceso

1. Los accesos deben ser revocados inmediatamente cuando un usuario:
   - Deja la organización
   - Cambia de rol
   - Ya no necesita acceso a un recurso específico

2. Se realizará una revisión trimestral de todos los accesos.

## Auditoría y Monitoreo

1. Todos los inicios y cierres de sesión se registran.
2. Los cambios en los permisos y roles se auditan.
3. Los intentos fallidos de autenticación se monitorizan para detectar posibles ataques.
4. Se generan informes de auditoría de acceso mensuales.

## Procedimientos de Excepción

1. Las excepciones a esta política deben ser aprobadas por el administrador de seguridad.
2. Todas las excepciones deben ser documentadas y tener una fecha de expiración.
3. Las excepciones deben ser revisadas periódicamente.

## Cumplimiento y Consecuencias

1. El cumplimiento de esta política es obligatorio para todos los usuarios.
2. Las violaciones pueden resultar en acciones disciplinarias, hasta e incluyendo la terminación del acceso o empleo.

## Revisión y Mantenimiento

Esta política será revisada anualmente o cuando ocurran cambios significativos en la infraestructura o requisitos de seguridad.
EOF

    # Documento de política de protección de datos
    cat > "${DOCS_DIR}/policies/data-protection.md" << 'EOF'
# Política de Protección de Datos

## Propósito

Esta política establece los requisitos para la protección de datos dentro de la Plataforma Centralizada de Información, asegurando la confidencialidad, integridad y disponibilidad de la información.

## Alcance

Esta política aplica a todos los datos procesados, almacenados o transmitidos por la Plataforma Centralizada de Información, independientemente del medio en el que residan.

## Clasificación de Datos

Los datos se clasifican en las siguientes categorías:

1. **Públicos**: Información que puede ser divulgada sin restricciones.
2. **Internos**: Información para uso dentro de la organización.
3. **Confidenciales**: Información sensible cuya divulgación podría causar daño.
4. **Restringidos**: Información altamente sensible cuya divulgación podría causar daño grave.

## Requisitos de Protección por Clasificación

| Categoría | Cifrado en Tránsito | Cifrado en Reposo | Control de Acceso | Auditoría | Retención |
|-----------|---------------------|-------------------|-------------------|-----------|-----------|
| Públicos | Opcional | Opcional | Básico | Básica | 1 año |
| Internos | Requerido | Recomendado | Basado en roles | Estándar | 3 años |
| Confidenciales | Requerido | Requerido | Estricto | Detallada | 5 años |
| Restringidos | Requerido (Fuerte) | Requerido (Fuerte) | Muy estricto | Exhaustiva | 7 años |

## Cifrado de Datos

### Cifrado en Tránsito

1. Todas las comunicaciones externas deben utilizar TLS 1.2 o superior.
2. Las comunicaciones internas entre microservicios deben estar cifradas cuando transmitan datos confidenciales o restringidos.
3. Los certificados deben ser gestionados por Cert-Manager y renovados automáticamente.

### Cifrado en Reposo

1. Datos confidenciales y restringidos deben estar cifrados en reposo.
2. Las claves de cifrado deben ser gestionadas por HashiCorp Vault.
3. Se debe utilizar algoritmos de cifrado fuertes (AES-256, RSA-2048 o superior).

## Gestión de Secretos

1. Las credenciales y secretos deben ser gestionados por HashiCorp Vault o Passbolt.
2. Los secretos no deben ser almacenados en código fuente, configuraciones no cifradas o variables de entorno.
3. Las credenciales deben ser rotadas periódicamente.

## Protección de Datos Personales

En cumplimiento con regulaciones de protección de datos (como GDPR):

1. Los datos personales deben ser identificados y tratados con protección adicional.
2. Se debe mantener un registro de las actividades de procesamiento.
3. Los datos personales deben ser retenidos solo mientras sean necesarios.
4. Se debe proporcionar mecanismos para que los usuarios ejerzan sus derechos.

## Respaldos de Datos

1. Los datos críticos deben ser respaldados regularmente.
2. Los respaldos deben ser cifrados y almacenados de forma segura.
3. Se deben realizar pruebas periódicas de restauración.

## Eliminación Segura de Datos

1. Los datos deben ser eliminados de forma segura cuando ya no sean necesarios.
2. Los medios físicos deben ser sanitizados antes de su reutilización o eliminación.
3. La eliminación de datos confidenciales o restringidos debe ser auditada.

## Integridad de Datos

1. Se deben implementar controles para mantener la integridad de los datos.
2. Los cambios en datos críticos deben ser registrados.
3. Se deben utilizar sumas de verificación para detectar modificaciones no autorizadas.

## Gestión de Incidentes de Datos

1. Los incidentes de seguridad de datos deben ser reportados inmediatamente.
2. Se debe seguir el procedimiento de respuesta a incidentes.
3. Las brechas de datos deben ser documentadas y analizadas para prevenir recurrencias.

## Cumplimiento y Auditoría

1. El cumplimiento de esta política será auditado regularmente.
2. Se mantendrán registros de auditoría para demostrar cumplimiento.
3. Las deficiencias identificadas deben ser remediadas oportunamente.

## Revisión y Actualización

Esta política será revisada anualmente o cuando cambien significativamente los requisitos de protección de datos.
EOF

    # Documento de procedimiento de respuesta a incidentes
    cat > "${DOCS_DIR}/procedures/incident-response.md" << 'EOF'
# Procedimiento de Respuesta a Incidentes

## Propósito

Este procedimiento define los pasos para responder efectivamente a incidentes de seguridad en la Plataforma Centralizada de Información, minimizando el impacto y restaurando la operación normal de manera segura.

## Alcance

Este procedimiento aplica a todos los incidentes de seguridad que afecten a la Plataforma Centralizada de Información, incluyendo infraestructura, aplicaciones, servicios y datos.

## Equipo de Respuesta a Incidentes

| Rol | Responsabilidades |
|-----|-------------------|
| Coordinador de Incidentes | Coordinar la respuesta global, comunicación |
| Analista de Seguridad | Investigar el incidente, análisis forense |
| Administrador de Sistemas | Contención técnica, recuperación |
| Administrador de Aplicaciones | Análisis de impacto en aplicaciones |
| Asesor Legal | Asesoramiento sobre implicaciones legales |
| Comunicaciones | Gestión de comunicaciones internas/externas |

## Niveles de Severidad de Incidentes

| Nivel | Descripción | Tiempo de Respuesta | Ejemplo |
|-------|-------------|---------------------|---------|
| 1 - Crítico | Impacto severo, daño significativo actual | Inmediato (24/7) | Brecha de datos activa, ransomware |
| 2 - Alto | Impacto significativo o daño potencial alto | 2 horas (horario laboral) | Intrusión detectada, malware |
| 3 - Medio | Impacto moderado o limitado | 24 horas | Intento de ataque fallido, vulnerabilidad crítica |
| 4 - Bajo | Impacto mínimo | 48 horas | Incidente menor, eventos sospechosos |

## Fases de Respuesta a Incidentes

### 1. Preparación

* Mantener actualizados los procedimientos de respuesta
* Realizar simulacros periódicos
* Asegurar herramientas de respuesta disponibles
* Mantener la lista de contactos actualizada

### 2. Detección e Identificación

* Identificar y documentar detalles del incidente:
  - Fecha y hora
  - Sistemas afectados
  - Indicadores de compromiso
  - Fuente de detección
  - Impacto inicial

* Clasificar la severidad del incidente
* Notificar al Coordinador de Incidentes

### 3. Contención

#### Contención Inmediata
* Aislar sistemas afectados
* Bloquear direcciones IP maliciosas
* Desactivar cuentas comprometidas
* Implementar controles temporales

#### Contención a Corto Plazo
* Aplicar parches de emergencia
* Reforzar controles de seguridad
* Aumentar monitoreo de sistemas relacionados

### 4. Erradicación

* Identificar y eliminar la causa raíz
* Remover malware, backdoors o código malicioso
* Corregir vulnerabilidades explotadas
* Reforzar defensas

### 5. Recuperación

* Restaurar sistemas afectados desde backups limpios
* Validar el estado de los sistemas
* Monitorizar estrechamente para detectar recurrencias
* Implementar controles adicionales si es necesario
* Retornar sistemas a producción de forma gradual

### 6. Lecciones Aprendidas

* Realizar análisis post-incidente dentro de 48-72 horas
* Documentar:
  - Cronología del incidente
  - Acciones tomadas
  - Efectividad de la respuesta
  - Áreas de mejora
  - Recomendaciones

* Actualizar procedimientos según sea necesario
* Implementar medidas preventivas

## Procedimientos Específicos por Tipo de Incidente

### Respuesta a Intento de Acceso No Autorizado

1. **Contención Inmediata**
   * Identificar IP origen de los intentos
   * Implementar bloqueo temporal en WAF/firewall
   * Revisar logs de autenticación
   * Bloquear temporalmente cuentas afectadas si es necesario

2. **Análisis**
   * Examinar patrones de intentos
   * Verificar actividades sospechosas de la misma IP
   * Correlacionar con otros eventos de seguridad
   * Determinar si el ataque está en curso o ha cesado

3. **Mitigación y Recuperación**
   * Extender bloqueo de IP si se confirma ataque
   * Resetear contraseñas de cuentas comprometidas
   * Revisar y revocar tokens/sesiones activas
   * Implementar reglas adicionales según patrón identificado

### Respuesta a Actividad Sospechosa en Contenedor

1. **Contención Inmediata**
   * Identificar el contenedor/pod comprometido
   * Aislar el pod mediante Network Policy
   * Obtener evidencia forense
   * Terminar y reemplazar el pod sospechoso

2. **Análisis**
   * Revisar logs del contenedor
   * Analizar imágenes para vulnerabilidades
   * Revisar políticas de seguridad de pods
   * Verificar vector de ataque

3. **Mitigación y Recuperación**
   * Actualizar imágenes con parches
   * Implementar políticas más estrictas
   * Verificar integridad de secretos
   * Implementar reglas de detección mejoradas

## Comunicación durante Incidentes

### Comunicación Interna

* Usar canales seguros predefinidos
* Mantener actualizados a stakeholders clave
* Seguir la matriz de escalamiento
* Evitar comunicaciones que puedan filtrar detalles sensibles

### Comunicación Externa

* Toda comunicación externa debe ser aprobada por el Coordinador y Asesor Legal
* Designar un único punto de contacto para comunicaciones externas
* Seguir obligaciones regulatorias de notificación
* Mantener transparencia apropiada sin comprometer la seguridad

## Herramientas y Recursos

* Script de recolección forense: `/opt/central-platform/security/scripts/incident-response/collect-evidence.sh`
* Script de contención: `/opt/central-platform/security/scripts/incident-response/containment.sh`
* Plantillas de documentación: `/opt/central-platform/docs/templates/incident-*.md`
* Herramientas forenses: `/opt/central-platform/security/tools/forensics/`

## Contactos de Escalado

* Nivel 1: SOC Analyst (soc@central-platform.local)
* Nivel 2: Security Team Lead (security-lead@central-platform.local)
* Nivel 3: CISO (ciso@central-platform.local)
* Emergencias 24/7: +1-555-123-4567

## Aprobaciones y Revisiones

| Versión | Fecha | Aprobador | Cambios |
|---------|-------|-----------|---------|
| 1.0 | 2023-01-15 | CISO | Versión inicial |
| 1.1 | 2023-04-20 | CISO | Actualización de contactos y herramientas |
EOF

    log_success "Documentación de seguridad creada correctamente"
}

# Función principal
main() {
    log_info "Iniciando script de despliegue para la Zona G (Seguridad) en Ubuntu 24.04 LTS"
    
    # Verificar dependencias
    log_info "Verificando dependencias..."
    deps=("kubectl" "jq" "curl" "openssl")
    missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing_deps+=($dep)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_warning "Faltan las siguientes dependencias: ${missing_deps[*]}"
        log_info "Instalando dependencias..."
        
        apt-get update
        apt-get install -y ${missing_deps[*]}
        
        log_success "Dependencias instaladas correctamente"
    else
        log_success "Todas las dependencias están instaladas"
    fi
    
    # Crear estructura de directorios
    create_directory_structure
    
    # Crear archivos Kubernetes
    create_k8s_base_files
    create_oauth2_proxy_files
    create_cert_manager_files
    create_passbolt_files
    create_keycloak_files
    create_vault_files
    create_waf_files
    create_falco_files
    
    # Crear scripts de seguridad
    create_security_scripts
    
    # Crear documentación
    create_security_docs
    
    # Script de despliegue
    cat > "${BASE_DIR}/deploy-security-zone.sh" << 'EOF'
#!/bin/bash
# Script para desplegar la Zona G (Seguridad) en Kubernetes

# Variables
BASE_DIR="/opt/central-platform"
K8S_DIR="${BASE_DIR}/k8s/security"

# Función para aplicar los manifiestos de Kubernetes
deploy_k8s_manifests() {
    echo "Desplegando componentes de seguridad en Kubernetes..."
    
    # 1. Crear namespace
    kubectl apply -f "${K8S_DIR}/namespace/namespace.yaml"
    
    # 2. Aplicar Network Policies
    kubectl apply -f "${K8S_DIR}/network-policies/"
    
    # 3. Desplegar Cert-Manager
    kubectl apply -f "${K8S_DIR}/cert-manager/"
    
    # Esperar a que Cert-Manager esté listo
    echo "Esperando a que Cert-Manager esté listo..."
    kubectl wait --for=condition=ready pod -l app=cert-manager --timeout=120s -n cert-manager
    
    # 4. Desplegar OAuth2 Proxy
    kubectl apply -f "${K8S_DIR}/oauth2-proxy/"
    
    # 5. Desplegar Passbolt
    kubectl apply -f "${K8S_DIR}/passbolt/"
    
    # 6. Desplegar Keycloak
    kubectl apply -f "${K8S_DIR}/keycloak/"
    
    # 7. Desplegar Vault
    kubectl apply -f "${K8S_DIR}/vault/"
    
    # 8. Desplegar WAF
    kubectl apply -f "${K8S_DIR}/waf/modsecurity/"
    
    # 9. Desplegar Falco
    kubectl apply -f "${K8S_DIR}/siem/falco/"
    
    echo "Componentes de seguridad desplegados. Verificando estado..."
    
    # Verificar estado de los pods
    kubectl get pods -n central-platform
}

# Ejecutar la función de despliegue
deploy_k8s_manifests

# Inicializar Vault
echo "¿Desea inicializar Vault ahora? (s/n)"
read init_vault

if [[ "$init_vault" == "s" ]]; then
    echo "Inicializando Vault..."
    ${BASE_DIR}/security/secrets/vault/scripts/init-vault.sh
fi

echo "Despliegue de la Zona G (Seguridad) completado."
EOF
    chmod +x "${BASE_DIR}/deploy-security-zone.sh"
    
    log_success "¡Despliegue de la Zona G (Seguridad) preparado correctamente!"
    log_info "Para desplegar los componentes en Kubernetes, ejecute: ${BASE_DIR}/deploy-security-zone.sh"
}

# Ejecutar la función principal
main
