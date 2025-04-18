#!/bin/bash

# Script para desplegar la Zona E (Persistencia) de la Plataforma Centralizada
# Compatible con Ubuntu 24.04 LTS
# Autor: Claude - Fecha: $(date +%Y-%m-%d)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mensajes
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Verificar si se está ejecutando como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root"
   exit 1
fi

# Crear estructura de directorios base
BASE_DIR="/opt/central-platform"
K8S_DIR="${BASE_DIR}/k8s"
SCRIPTS_DIR="${BASE_DIR}/scripts"
DOCS_DIR="${BASE_DIR}/docs"
HELM_DIR="${BASE_DIR}/helm"

create_directory_structure() {
    log_info "Creando estructura de directorios..."
    
    # Directorios principales
    mkdir -p ${K8S_DIR}/databases/mongodb
    mkdir -p ${K8S_DIR}/databases/postgresql
    mkdir -p ${K8S_DIR}/databases/elasticsearch/kibana
    mkdir -p ${K8S_DIR}/databases/redis
    
    # Directorios de monitoreo
    mkdir -p ${K8S_DIR}/databases/mongodb/monitoring
    mkdir -p ${K8S_DIR}/databases/postgresql/monitoring
    mkdir -p ${K8S_DIR}/databases/redis/monitoring
    
    # Directorios de scripts
    mkdir -p ${SCRIPTS_DIR}/mongodb/{backup,init,maintenance}
    mkdir -p ${SCRIPTS_DIR}/postgresql/{backup,init,maintenance}
    mkdir -p ${SCRIPTS_DIR}/elasticsearch/{backup,init,maintenance}
    mkdir -p ${SCRIPTS_DIR}/redis/{backup,maintenance}
    
    # Directorios de documentación
    mkdir -p ${DOCS_DIR}/persistence/{mongodb,postgresql,elasticsearch,redis}
    
    # Directorios de Helm
    mkdir -p ${HELM_DIR}/{mongodb,postgresql,elasticsearch,redis}
    mkdir -p ${HELM_DIR}/elasticsearch/charts/kibana
    
    log_success "Estructura de directorios creada correctamente"
}

# Generar archivos Kubernetes para MongoDB
create_mongodb_k8s_files() {
    log_info "Generando archivos Kubernetes para MongoDB..."
    
    # StatefulSet
    cat > ${K8S_DIR}/databases/mongodb/statefulset.yaml << 'EOF'
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
        readinessProbe:
          exec:
            command:
            - mongo
            - --eval
            - "db.adminCommand('ping')"
          initialDelaySeconds: 5
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

    # ConfigMap
    cat > ${K8S_DIR}/databases/mongodb/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-config
  namespace: central-platform
  labels:
    app: mongodb
    component: database
data:
  mongodb.conf: |
    # MongoDB Configuration File
    
    # Network settings
    net:
      port: 27017
      bindIp: 0.0.0.0
    
    # Storage settings
    storage:
      dbPath: /data/db
      journal:
        enabled: true
      wiredTiger:
        engineConfig:
          cacheSizeGB: 1
    
    # Replication settings
    replication:
      replSetName: rs0
    
    # Security settings
    security:
      authorization: enabled
    
    # Monitoring settings
    operationProfiling:
      mode: slowOp
      slowOpThresholdMs: 100
    
    # Log settings
    systemLog:
      destination: file
      path: /var/log/mongodb/mongod.log
      logAppend: true
      verbosity: 1

# ConfigMap para scripts de inicialización
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-init-scripts
  namespace: central-platform
  labels:
    app: mongodb
    component: database
data:
  init-replica.js: |
    // Wait for MongoDB to start
    sleep(10000);
    
    // Initialize replica set
    if (rs.status().code === 94) {
      var config = {
        _id: "rs0",
        members: [
          { _id: 0, host: "mongodb-0.mongodb-headless.central-platform.svc.cluster.local:27017" },
          { _id: 1, host: "mongodb-1.mongodb-headless.central-platform.svc.cluster.local:27017" },
          { _id: 2, host: "mongodb-2.mongodb-headless.central-platform.svc.cluster.local:27017" }
        ]
      };
      rs.initiate(config);
      print("Replica set initialized");
    } else {
      print("Replica set already initialized");
    }
    
    // Create application user
    sleep(5000);
    db = db.getSiblingDB('admin');
    if (db.auth(process.env.MONGO_INITDB_ROOT_USERNAME, process.env.MONGO_INITDB_ROOT_PASSWORD)) {
      db = db.getSiblingDB('central_platform');
      if (!db.getUser('app_user')) {
        db.createUser({
          user: 'app_user',
          pwd: process.env.MONGODB_APP_PASSWORD,
          roles: [
            { role: 'readWrite', db: 'central_platform' }
          ]
        });
        print("Application user created");
      } else {
        print("Application user already exists");
      }
    }
  
  create-indexes.js: |
    // Create indexes for device collection
    db = db.getSiblingDB('central_platform');
    db.devices.createIndex({ deviceId: 1 }, { unique: true });
    db.devices.createIndex({ status: 1 });
    db.devices.createIndex({ type: 1 });
    db.devices.createIndex({ "location.coordinates": "2dsphere" });
    
    // Create indexes for telemetry collection
    db.telemetry.createIndex({ deviceId: 1, timestamp: -1 });
    db.telemetry.createIndex({ timestamp: -1 });
    db.telemetry.createIndex({ "data.temperature": 1 });
    
    // Create indexes for alerts collection
    db.alerts.createIndex({ deviceId: 1, status: 1 });
    db.alerts.createIndex({ severity: 1 });
    db.alerts.createIndex({ createdAt: -1 });
    
    print("All indexes created successfully");
EOF

    # Service
    cat > ${K8S_DIR}/databases/mongodb/service.yaml << 'EOF'
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

# Headless service for StatefulSet DNS
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

    # Secret (plantilla)
    cat > ${K8S_DIR}/databases/mongodb/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-secret
  namespace: central-platform
  labels:
    app: mongodb
    component: database
type: Opaque
data:
  root-username: "YWRtaW4=" # admin
  root-password: "cGFzc3dvcmQ=" # Cambiar por un valor seguro
  app-username: "YXBwX3VzZXI=" # app_user
  app-password: "cGFzc3dvcmQ=" # Cambiar por un valor seguro
EOF

    # Exportador para Prometheus
    cat > ${K8S_DIR}/databases/mongodb/monitoring/mongodb-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-exporter
  namespace: central-platform
  labels:
    app: mongodb-exporter
    component: monitoring
spec:
  selector:
    matchLabels:
      app: mongodb-exporter
  replicas: 1
  template:
    metadata:
      labels:
        app: mongodb-exporter
    spec:
      containers:
      - name: mongodb-exporter
        image: bitnami/mongodb-exporter:latest
        ports:
        - name: metrics
          containerPort: 9216
        env:
        - name: MONGODB_URI
          valueFrom:
            secretKeyRef:
              name: mongodb-secret
              key: connection-string
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-exporter
  namespace: central-platform
  labels:
    app: mongodb-exporter
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9216"
spec:
  selector:
    app: mongodb-exporter
  ports:
  - name: metrics
    port: 9216
    targetPort: metrics
  type: ClusterIP
EOF

    # ServiceMonitor
    cat > ${K8S_DIR}/databases/mongodb/monitoring/servicemonitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb
  namespace: central-platform
  labels:
    app: mongodb
    component: monitoring
spec:
  selector:
    matchLabels:
      app: mongodb-exporter
  endpoints:
  - port: metrics
    interval: 30s
EOF

    log_success "Archivos Kubernetes para MongoDB generados correctamente"
}

# Generar archivos Kubernetes para PostgreSQL
create_postgresql_k8s_files() {
    log_info "Generando archivos Kubernetes para PostgreSQL..."
    
    # StatefulSet
    cat > ${K8S_DIR}/databases/postgresql/statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: central-platform
  labels:
    app: postgresql
    component: database
spec:
  serviceName: postgresql-headless
  replicas: 1  # Single instance for PostgreSQL
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
        component: database
    spec:
      terminationGracePeriodSeconds: 30
      securityContext:
        fsGroup: 999
        runAsUser: 999
      containers:
      - name: postgresql
        image: postgres:14-alpine
        imagePullPolicy: IfNotPresent
        ports:
        - name: postgres
          containerPort: 5432
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: postgres-user
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: postgres-password
        - name: POSTGRES_DB
          value: "central_platform"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        volumeMounts:
        - name: postgresql-data
          mountPath: /var/lib/postgresql/data
        - name: postgresql-init-scripts
          mountPath: /docker-entrypoint-initdb.d
        - name: postgresql-config
          mountPath: /etc/postgresql/postgresql.conf
          subPath: postgresql.conf
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
            - /bin/sh
            - -c
            - pg_isready -U postgres -h 127.0.0.1 -p 5432
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 6
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U postgres -h 127.0.0.1 -p 5432
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 6
      volumes:
      - name: postgresql-init-scripts
        configMap:
          name: postgresql-init-scripts
      - name: postgresql-config
        configMap:
          name: postgresql-config
  volumeClaimTemplates:
  - metadata:
      name: postgresql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 20Gi
EOF

    # ConfigMap
    cat > ${K8S_DIR}/databases/postgresql/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-config
  namespace: central-platform
  labels:
    app: postgresql
    component: database
data:
  postgresql.conf: |
    # PostgreSQL Configuration File
    
    # Connection settings
    listen_addresses = '*'
    max_connections = 100
    
    # Memory settings
    shared_buffers = 256MB
    effective_cache_size = 768MB
    work_mem = 4MB
    maintenance_work_mem = 64MB
    
    # WAL settings
    wal_level = replica
    max_wal_size = 1GB
    min_wal_size = 80MB
    
    # Query optimization
    random_page_cost = 1.1
    effective_io_concurrency = 200
    
    # Logging
    log_destination = 'stderr'
    logging_collector = on
    log_directory = 'pg_log'
    log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
    log_truncate_on_rotation = off
    log_rotation_age = 1d
    log_rotation_size = 100MB
    log_statement = 'none'
    log_min_duration_statement = 1000
    
    # Statistics
    track_activities = on
    track_counts = on
    
    # SSL
    ssl = on
    ssl_cert_file = '/etc/postgresql/ssl/server.crt'
    ssl_key_file = '/etc/postgresql/ssl/server.key'

# ConfigMap para scripts de inicialización
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-init-scripts
  namespace: central-platform
  labels:
    app: postgresql
    component: database
data:
  01-init-schema.sql: |
    -- Create schema for central platform
    
    -- Users table
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username VARCHAR(255) NOT NULL UNIQUE,
      email VARCHAR(255) NOT NULL UNIQUE,
      full_name VARCHAR(255) NOT NULL,
      hashed_password VARCHAR(255) NOT NULL,
      is_active BOOLEAN DEFAULT TRUE,
      is_superuser BOOLEAN DEFAULT FALSE,
      is_sso BOOLEAN DEFAULT FALSE,
      role VARCHAR(50) DEFAULT 'user',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Groups table
    CREATE TABLE IF NOT EXISTS groups (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL UNIQUE,
      description TEXT,
      created_by INTEGER REFERENCES users(id),
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
    -- User-Group association table
    CREATE TABLE IF NOT EXISTS user_group (
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      group_id INTEGER REFERENCES groups(id) ON DELETE CASCADE,
      PRIMARY KEY (user_id, group_id)
    );
    
    -- Devices table
    CREATE TABLE IF NOT EXISTS devices (
      id SERIAL PRIMARY KEY,
      device_id VARCHAR(255) NOT NULL UNIQUE,
      name VARCHAR(255) NOT NULL,
      type VARCHAR(50) NOT NULL,
      status VARCHAR(50) DEFAULT 'offline',
      model VARCHAR(255),
      manufacturer VARCHAR(255),
      firmware VARCHAR(255),
      metadata JSONB,
      owner_id INTEGER REFERENCES users(id),
      group_id INTEGER REFERENCES groups(id),
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Create indexes
    CREATE INDEX idx_devices_status ON devices(status);
    CREATE INDEX idx_devices_type ON devices(type);
    CREATE INDEX idx_devices_owner ON devices(owner_id);
    CREATE INDEX idx_devices_group ON devices(group_id);
    CREATE INDEX idx_users_username ON users(username);
    CREATE INDEX idx_users_email ON users(email);
    CREATE INDEX idx_users_role ON users(role);
    
    -- Create update timestamp trigger function
    CREATE OR REPLACE FUNCTION update_timestamp()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    
    -- Apply trigger to tables
    CREATE TRIGGER update_users_timestamp BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    
    CREATE TRIGGER update_groups_timestamp BEFORE UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    
    CREATE TRIGGER update_devices_timestamp BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    
  02-init-data.sql: |
    -- Insert initial data
    
    -- Create admin user (password: admin123)
    INSERT INTO users (username, email, full_name, hashed_password, is_active, is_superuser, role)
    VALUES ('admin', 'admin@central-platform.local', 'System Administrator', 
            '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', 
            TRUE, TRUE, 'admin')
    ON CONFLICT (username) DO NOTHING;
    
    -- Create demo user (password: demo123)
    INSERT INTO users (username, email, full_name, hashed_password, is_active, is_superuser, role)
    VALUES ('demo', 'demo@central-platform.local', 'Demo User', 
            '$2b$12$tP.7lcMH86PFzLzSD9.wJe9GD9ovmlLdSJ9/2nIEjhi/kWFnECExy', 
            TRUE, FALSE, 'user')
    ON CONFLICT (username) DO NOTHING;
    
    -- Create default groups
    INSERT INTO groups (name, description, created_by)
    VALUES ('Administrators', 'System administrators with full access', 
            (SELECT id FROM users WHERE username = 'admin'))
    ON CONFLICT (name) DO NOTHING;
    
    INSERT INTO groups (name, description, created_by)
    VALUES ('Users', 'Regular platform users', 
            (SELECT id FROM users WHERE username = 'admin'))
    ON CONFLICT (name) DO NOTHING;
    
    -- Assign users to groups
    INSERT INTO user_group (user_id, group_id)
    VALUES (
        (SELECT id FROM users WHERE username = 'admin'),
        (SELECT id FROM groups WHERE name = 'Administrators')
    )
    ON CONFLICT DO NOTHING;
    
    INSERT INTO user_group (user_id, group_id)
    VALUES (
        (SELECT id FROM users WHERE username = 'demo'),
        (SELECT id FROM groups WHERE name = 'Users')
    )
    ON CONFLICT DO NOTHING;
EOF

    # Service
    cat > ${K8S_DIR}/databases/postgresql/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: central-platform
  labels:
    app: postgresql
    component: database
spec:
  ports:
  - port: 5432
    targetPort: postgres
    protocol: TCP
    name: postgresql
  selector:
    app: postgresql
  type: ClusterIP

# Headless service for StatefulSet DNS
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql-headless
  namespace: central-platform
  labels:
    app: postgresql
    component: database
spec:
  ports:
  - port: 5432
    targetPort: postgres
    protocol: TCP
    name: postgresql
  selector:
    app: postgresql
  clusterIP: None
EOF

    # Secret (plantilla)
    cat > ${K8S_DIR}/databases/postgresql/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-secret
  namespace: central-platform
  labels:
    app: postgresql
    component: database
type: Opaque
data:
  postgres-user: "cG9zdGdyZXM=" # postgres
  postgres-password: "cGFzc3dvcmQ=" # Cambiar por un valor seguro
EOF

    # Exportador para Prometheus
    cat > ${K8S_DIR}/databases/postgresql/monitoring/postgres-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: central-platform
  labels:
    app: postgres-exporter
    component: monitoring
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  replicas: 1
  template:
    metadata:
      labels:
        app: postgres-exporter
    spec:
      containers:
      - name: postgres-exporter
        image: quay.io/prometheuscommunity/postgres-exporter
        ports:
        - name: metrics
          containerPort: 9187
        env:
        - name: DATA_SOURCE_NAME
          valueFrom:
            secretKeyRef:
              name: postgresql-exporter-secret
              key: connection-string
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: central-platform
  labels:
    app: postgres-exporter
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9187"
spec:
  selector:
    app: postgres-exporter
  ports:
  - name: metrics
    port: 9187
    targetPort: metrics
  type: ClusterIP
EOF

    # ServiceMonitor
    cat > ${K8S_DIR}/databases/postgresql/monitoring/servicemonitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgresql
  namespace: central-platform
  labels:
    app: postgresql
    component: monitoring
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  endpoints:
  - port: metrics
    interval: 30s
EOF

    log_success "Archivos Kubernetes para PostgreSQL generados correctamente"
}

# Generar archivos Kubernetes para ElasticSearch
create_elasticsearch_k8s_files() {
    log_info "Generando archivos Kubernetes para ElasticSearch..."
    
    # StatefulSet
    cat > ${K8S_DIR}/databases/elasticsearch/statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: central-platform
  labels:
    app: elasticsearch
    component: database
spec:
  serviceName: elasticsearch-headless
  replicas: 3
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
        component: database
    spec:
      terminationGracePeriodSeconds: 120
      initContainers:
      - name: sysctl
        image: busybox:1.32
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      - name: set-permissions
        image: busybox:1.32
        command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
        volumeMounts:
        - name: elasticsearch-data
          mountPath: /usr/share/elasticsearch/data
      containers:
      - name: elasticsearch
        image: elasticsearch:7.17.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9200
        - name: transport
          containerPort: 9300
        env:
        - name: node.name
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: cluster.name
          value: "central-platform"
        - name: discovery.seed_hosts
          value: "elasticsearch-0.elasticsearch-headless,elasticsearch-1.elasticsearch-headless,elasticsearch-2.elasticsearch-headless"
        - name: cluster.initial_master_nodes
          value: "elasticsearch-0,elasticsearch-1,elasticsearch-2"
        - name: bootstrap.memory_lock
          value: "true"
        - name: ES_JAVA_OPTS
          value: "-Xms1g -Xmx1g"
        - name: xpack.security.enabled
          value: "true"
        - name: ELASTIC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: elasticsearch-secret
              key: elastic-password
        envFrom:
        - configMapRef:
            name: elasticsearch-config
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: elasticsearch-data
          mountPath: /usr/share/elasticsearch/data
        - name: elasticsearch-config
          mountPath: /usr/share/elasticsearch/config/elasticsearch.yml
          subPath: elasticsearch.yml
        securityContext:
          runAsUser: 1000
          privileged: false
          capabilities:
            add:
              - IPC_LOCK
              - SYS_RESOURCE
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - |
              #!/usr/bin/env bash
              set -e
              
              # Wait for Elasticsearch to start
              echo 'Checking Elasticsearch readiness'
              ELASTIC_PASSWORD=${ELASTIC_PASSWORD} curl -k -s -u "elastic:${ELASTIC_PASSWORD}" --insecure https://localhost:9200/_cluster/health | grep -v '"status":"red"'
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 6
      volumes:
      - name: elasticsearch-config
        configMap:
          name: elasticsearch-config
  volumeClaimTemplates:
  - metadata:
      name: elasticsearch-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 30Gi
EOF

    # ConfigMap
    cat > ${K8S_DIR}/databases/elasticsearch/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: elasticsearch-config
  namespace: central-platform
  labels:
    app: elasticsearch
    component: database
data:
  elasticsearch.yml: |
    # Elasticsearch Configuration File
    
    # Cluster settings
    cluster.name: central-platform
    
    # Node settings
    node.master: true
    node.data: true
    node.ingest: true
    node.name: ${HOSTNAME}
    
    # Network settings
    network.host: 0.0.0.0
    http.port: 9200
    transport.port: 9300
    
    # Discovery settings
    discovery.seed_hosts: ["elasticsearch-0.elasticsearch-headless", "elasticsearch-1.elasticsearch-headless", "elasticsearch-2.elasticsearch-headless"]
    cluster.initial_master_nodes: ["elasticsearch-0", "elasticsearch-1", "elasticsearch-2"]
    
    # Path settings
    path.data: /usr/share/elasticsearch/data
    path.logs: /usr/share/elasticsearch/logs
    
    # Memory settings
    bootstrap.memory_lock: true
    
    # Security settings
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.keystore.path: config/certs/elastic-certificates.p12
    xpack.security.transport.ssl.truststore.path: config/certs/elastic-certificates.p12
    
    # Monitoring
    xpack.monitoring.collection.enabled: true
    
    # Indexing settings
    action.auto_create_index: .monitoring-*,
                              .watches,
                              .triggered_watches,
                              .watcher-history-*,
                              .ml-*,
                              *
    
    # JVM options
    processors: ${PROCESSORS:1}
EOF

    # Service
    cat > ${K8S_DIR}/databases/elasticsearch/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: central-platform
  labels:
    app: elasticsearch
    component: database
spec:
  ports:
  - port: 9200
    targetPort: http
    protocol: TCP
    name: http
  - port: 9300
    targetPort: transport
    protocol: TCP
    name: transport
  selector:
    app: elasticsearch
  type: ClusterIP

# Headless service for StatefulSet DNS
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-headless
  namespace: central-platform
  labels:
    app: elasticsearch
    component: database
spec:
  ports:
  - port: 9200
    targetPort: http
    protocol: TCP
    name: http
  - port: 9300
    targetPort: transport
    protocol: TCP
    name: transport
  selector:
    app: elasticsearch
  clusterIP: None
EOF

    # Secret (plantilla)
    cat > ${K8S_DIR}/databases/elasticsearch/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: elasticsearch-secret
  namespace: central-platform
  labels:
    app: elasticsearch
    component: database
type: Opaque
data:
  elastic-password: "ZWxhc3RpYw==" # Cambiar por un valor seguro (elastic)
EOF

    # Kibana Deployment
    cat > ${K8S_DIR}/databases/elasticsearch/kibana/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: central-platform
  labels:
    app: kibana
    component: analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
        component: analytics
    spec:
      containers:
      - name: kibana
        image: kibana:7.17.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 5601
        env:
        - name: ELASTICSEARCH_HOSTS
          value: "https://elasticsearch:9200"
        - name: ELASTICSEARCH_USERNAME
          value: "elastic"
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: elasticsearch-secret
              key: elastic-password
        - name: ELASTICSEARCH_SSL_VERIFICATIONMODE
          value: "certificate"
        - name: SERVER_NAME
          value: "kibana.central-platform.local"
        envFrom:
        - configMapRef:
            name: kibana-config
        resources:
          requests:
            memory: "1Gi"
            cpu: "200m"
          limits:
            memory: "2Gi"
            cpu: "500m"
        volumeMounts:
        - name: kibana-config
          mountPath: /usr/share/kibana/config/kibana.yml
          subPath: kibana.yml
        livenessProbe:
          httpGet:
            path: /api/status
            port: http
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 10
          periodSeconds: 30
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /api/status
            port: http
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 10
          periodSeconds: 30
          failureThreshold: 5
      volumes:
      - name: kibana-config
        configMap:
          name: kibana-config
EOF

    # Kibana ConfigMap
    cat > ${K8S_DIR}/databases/elasticsearch/kibana/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-config
  namespace: central-platform
  labels:
    app: kibana
    component: analytics
data:
  kibana.yml: |
    server.name: kibana
    server.host: "0.0.0.0"
    server.publicBaseUrl: "https://kibana.central-platform.local"
    
    elasticsearch.hosts: ["https://elasticsearch:9200"]
    elasticsearch.username: elastic
    elasticsearch.password: ${ELASTICSEARCH_PASSWORD}
    elasticsearch.ssl.verificationMode: certificate
    
    xpack.monitoring.ui.container.elasticsearch.enabled: true
    xpack.reporting.enabled: true
    xpack.security.enabled: true
    
    telemetry.enabled: false
EOF

    # Kibana Service
    cat > ${K8S_DIR}/databases/elasticsearch/kibana/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: central-platform
  labels:
    app: kibana
    component: analytics
spec:
  ports:
  - port: 5601
    targetPort: http
    protocol: TCP
    name: http
  selector:
    app: kibana
  type: ClusterIP
EOF

    log_success "Archivos Kubernetes para ElasticSearch generados correctamente"
}

# Generar archivos Kubernetes para Redis
create_redis_k8s_files() {
    log_info "Generando archivos Kubernetes para Redis..."
    
    # StatefulSet
    cat > ${K8S_DIR}/databases/redis/statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: central-platform
  labels:
    app: redis
    component: cache
spec:
  serviceName: redis-headless
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        component: cache
    spec:
      containers:
      - name: redis
        image: redis:7.0-alpine
        imagePullPolicy: IfNotPresent
        command:
        - redis-server
        - /etc/redis/redis.conf
        - --requirepass
        - $(REDIS_PASSWORD)
        ports:
        - name: redis
          containerPort: 6379
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: redis-password
        volumeMounts:
        - name: redis-data
          mountPath: /data
        - name: redis-config
          mountPath: /etc/redis
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - redis-cli -a $REDIS_PASSWORD ping | grep PONG
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - redis-cli -a $REDIS_PASSWORD ping | grep PONG
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: redis-config
        configMap:
          name: redis-config
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 10Gi
EOF

    # ConfigMap
    cat > ${K8S_DIR}/databases/redis/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: central-platform
  labels:
    app: redis
    component: cache
data:
  redis.conf: |
    # Redis Configuration File
    
    # Network settings
    bind 0.0.0.0
    port 6379
    protected-mode yes
    
    # General settings
    daemonize no
    pidfile /var/run/redis.pid
    loglevel notice
    logfile ""
    
    # Snapshotting
    save 900 1
    save 300 10
    save 60 10000
    stop-writes-on-bgsave-error yes
    rdbcompression yes
    rdbchecksum yes
    dbfilename dump.rdb
    dir /data
    
    # Memory settings
    maxmemory 800mb
    maxmemory-policy allkeys-lru
    
    # Persistence settings
    appendonly yes
    appendfilename "appendonly.aof"
    appendfsync everysec
    no-appendfsync-on-rewrite no
    auto-aof-rewrite-percentage 100
    auto-aof-rewrite-min-size 64mb
    
    # Security settings
    # requirepass is passed as command line argument
    
    # Client settings
    timeout 0
    tcp-keepalive 300
    
    # Cluster settings
    cluster-enabled no
    
    # Performance settings
    io-threads 4
    io-threads-do-reads yes
EOF

    # Service
    cat > ${K8S_DIR}/databases/redis/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: central-platform
  labels:
    app: redis
    component: cache
spec:
  ports:
  - port: 6379
    targetPort: redis
    protocol: TCP
    name: redis
  selector:
    app: redis
  type: ClusterIP

# Headless service for StatefulSet DNS
---
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: central-platform
  labels:
    app: redis
    component: cache
spec:
  ports:
  - port: 6379
    targetPort: redis
    protocol: TCP
    name: redis
  selector:
    app: redis
  clusterIP: None
EOF

    # Secret (plantilla)
    cat > ${K8S_DIR}/databases/redis/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: central-platform
  labels:
    app: redis
    component: cache
type: Opaque
data:
  redis-password: "cmVkaXNwYXNzd29yZA==" # Cambiar por un valor seguro (redispassword)
EOF

    # Redis Exporter
    cat > ${K8S_DIR}/databases/redis/monitoring/redis-exporter.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-exporter
  namespace: central-platform
  labels:
    app: redis-exporter
    component: monitoring
spec:
  selector:
    matchLabels:
      app: redis-exporter
  replicas: 1
  template:
    metadata:
      labels:
        app: redis-exporter
    spec:
      containers:
      - name: redis-exporter
        image: oliver006/redis_exporter:latest
        env:
        - name: REDIS_ADDR
          value: "redis:6379"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: redis-password
        ports:
        - name: metrics
          containerPort: 9121
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: redis-exporter
  namespace: central-platform
  labels:
    app: redis-exporter
    component: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9121"
spec:
  selector:
    app: redis-exporter
  ports:
  - name: metrics
    port: 9121
    targetPort: metrics
  type: ClusterIP
EOF

    # ServiceMonitor
    cat > ${K8S_DIR}/databases/redis/monitoring/servicemonitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis
  namespace: central-platform
  labels:
    app: redis
    component: monitoring
spec:
  selector:
    matchLabels:
      app: redis-exporter
  endpoints:
  - port: metrics
    interval: 30s
EOF

    log_success "Archivos Kubernetes para Redis generados correctamente"
}

# Generar scripts de backup para MongoDB
create_mongodb_scripts() {
    log_info "Generando scripts para MongoDB..."
    
    # Script de backup
    cat > ${SCRIPTS_DIR}/mongodb/backup/backup.sh << 'EOF'
#!/bin/bash
# MongoDB Backup Script

# Configuration
BACKUP_DIR="/backup/mongodb"
RETENTION_DAYS=7
MONGODB_URI="mongodb://app_user:${MONGODB_APP_PASSWORD}@mongodb-0.mongodb-headless.central-platform.svc.cluster.local,mongodb-1.mongodb-headless.central-platform.svc.cluster.local,mongodb-2.mongodb-headless.central-platform.svc.cluster.local/central_platform?replicaSet=rs0&authSource=central_platform"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/mongodb-backup-${DATE}.gz"

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}

echo "Starting MongoDB backup at $(date)"

# Perform the backup
mongodump --uri="${MONGODB_URI}" --gzip --archive=${BACKUP_FILE}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: ${BACKUP_FILE}"
    
    # Set permissions
    chmod 600 ${BACKUP_FILE}
    
    # Delete old backups
    find ${BACKUP_DIR} -name "mongodb-backup-*" -type f -mtime +${RETENTION_DAYS} -delete
    echo "Deleted backups older than ${RETENTION_DAYS} days"
else
    echo "Backup failed!"
    exit 1
fi

echo "Backup process completed at $(date)"
EOF

    # Script de restauración
    cat > ${SCRIPTS_DIR}/mongodb/backup/restore.sh << 'EOF'
#!/bin/bash
# MongoDB Restore Script

# Configuration
BACKUP_FILE="$1"
MONGODB_URI="mongodb://app_user:${MONGODB_APP_PASSWORD}@mongodb-0.mongodb-headless.central-platform.svc.cluster.local,mongodb-1.mongodb-headless.central-platform.svc.cluster.local,mongodb-2.mongodb-headless.central-platform.svc.cluster.local/central_platform?replicaSet=rs0&authSource=central_platform"

# Validate input
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file '$BACKUP_FILE' not found"
    exit 1
fi

echo "Starting MongoDB restore from $BACKUP_FILE at $(date)"

# Perform the restore
mongorestore --uri="${MONGODB_URI}" --gzip --archive=${BACKUP_FILE}

# Check if restore was successful
if [ $? -eq 0 ]; then
    echo "Restore completed successfully from ${BACKUP_FILE}"
else
    echo "Restore failed!"
    exit 1
fi

echo "Restore process completed at $(date)"
EOF

    # Script para crear índices
    cat > ${SCRIPTS_DIR}/elasticsearch/init/create-indices.sh << 'EOF'
#!/bin/bash
# Elasticsearch Create Indices Script

# Configuration
ES_HOST="elasticsearch.central-platform.svc.cluster.local"
ES_PORT="9200"
ES_USER="elastic"
ES_PASSWORD="${ELASTIC_PASSWORD}"

echo "Creating Elasticsearch indices at $(date)"

# Create devices index
echo "Creating devices index..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/devices" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "name": { "type": "text", "fields": { "keyword": { "type": "keyword" } } },
      "type": { "type": "keyword" },
      "status": { "type": "keyword" },
      "model": { "type": "keyword" },
      "manufacturer": { "type": "keyword" },
      "firmware": { "type": "keyword" },
      "location": { "type": "geo_point" },
      "lastTelemetry": { "type": "date" },
      "metadata": { "type": "object", "dynamic": true },
      "ownerId": { "type": "keyword" },
      "groupId": { "type": "keyword" },
      "createdAt": { "type": "date" },
      "updatedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}'

# Create telemetry index
echo "Creating telemetry index..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/telemetry" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "data": { "type": "object", "dynamic": true },
      "location": { "type": "geo_point" },
      "receivedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}'

# Create alerts index
echo "Creating alerts index..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/alerts" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "ruleId": { "type": "keyword" },
      "message": { "type": "text" },
      "severity": { "type": "keyword" },
      "status": { "type": "keyword" },
      "telemetryData": { "type": "object", "dynamic": true },
      "acknowledgedBy": { "type": "keyword" },
      "acknowledgedAt": { "type": "date" },
      "resolvedAt": { "type": "date" },
      "createdAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  }
}'

echo "Index creation completed at $(date)"
EOF

    # Script para crear templates
    cat > ${SCRIPTS_DIR}/elasticsearch/init/create-templates.sh << 'EOF'
#!/bin/bash
# Elasticsearch Create Templates Script

# Configuration
ES_HOST="elasticsearch.central-platform.svc.cluster.local"
ES_PORT="9200"
ES_USER="elastic"
ES_PASSWORD="${ELASTIC_PASSWORD}"

echo "Creating Elasticsearch templates at $(date)"

# Create template for telemetry data
echo "Creating telemetry template..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_template/telemetry_template" -H 'Content-Type: application/json' -d '{
  "index_patterns": ["telemetry-*"],
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "data": { "type": "object", "dynamic": true },
      "location": { "type": "geo_point" },
      "receivedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1,
    "index.lifecycle.name": "telemetry_policy",
    "index.lifecycle.rollover_alias": "telemetry"
  }
}'

# Create template for security logs
echo "Creating security logs template..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_template/security_logs_template" -H 'Content-Type: application/json' -d '{
  "index_patterns": ["security-*"],
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "event": {
        "properties": {
          "category": { "type": "keyword" },
          "type": { "type": "keyword" },
          "action": { "type": "keyword" },
          "outcome": { "type": "keyword" },
          "severity": { "type": "short" },
          "sequence": { "type": "long" }
        }
      },
      "user": {
        "properties": {
          "name": { "type": "keyword" },
          "id": { "type": "keyword" },
          "email": { "type": "keyword" },
          "groups": { "type": "keyword" }
        }
      },
      "source": {
        "properties": {
          "ip": { "type": "ip" },
          "port": { "type": "integer" },
          "geo": {
            "properties": {
              "country_name": { "type": "keyword" },
              "region_name": { "type": "keyword" },
              "city_name": { "type": "keyword" },
              "location": { "type": "geo_point" }
            }
          }
        }
      },
      "message": { "type": "text" },
      "log": {
        "properties": {
          "level": { "type": "keyword" },
          "logger": { "type": "keyword" }
        }
      }
    }
  },
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "index.lifecycle.name": "security_policy"
  }
}'

# Create ILM policies
echo "Creating ILM policies..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_ilm/policy/telemetry_policy" -H 'Content-Type: application/json' -d '{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_size": "50gb"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "forcemerge": {
            "max_num_segments": 1
          },
          "shrink": {
            "number_of_shards": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'

echo "Template creation completed at $(date)"
EOF

    # Script para optimización de índices
    cat > ${SCRIPTS_DIR}/elasticsearch/maintenance/optimize.sh << 'EOF'
#!/bin/bash
# Elasticsearch Optimize Indices Script

# Configuration
ES_HOST="elasticsearch.central-platform.svc.cluster.local"
ES_PORT="9200"
ES_USER="elastic"
ES_PASSWORD="${ELASTIC_PASSWORD}"

echo "Starting Elasticsearch optimization at $(date)"

# Get all indices
INDICES=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_cat/indices?h=index" | sort)

# Force merge all indices
for INDEX in $INDICES; do
    echo "Optimizing index: ${INDEX}"
    curl -X POST -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/${INDEX}/_forcemerge?max_num_segments=1"
    echo ""
done

echo "Optimization completed at $(date)"
EOF

    # Hacer ejecutables los scripts
    chmod +x ${SCRIPTS_DIR}/elasticsearch/backup/snapshot.sh
    chmod +x ${SCRIPTS_DIR}/elasticsearch/backup/restore.sh
    chmod +x ${SCRIPTS_DIR}/elasticsearch/init/create-indices.sh
    chmod +x ${SCRIPTS_DIR}/elasticsearch/init/create-templates.sh
    chmod +x ${SCRIPTS_DIR}/elasticsearch/maintenance/optimize.sh
    
    log_success "Scripts para Elasticsearch generados correctamente"
}

# Generar scripts de backup para Redis
create_redis_scripts() {
    log_info "Generando scripts para Redis..."
    
    # Script de backup
    cat > ${SCRIPTS_DIR}/redis/backup/backup.sh << 'EOF'
#!/bin/bash
# Redis Backup Script

# Configuration
BACKUP_DIR="/backup/redis"
RETENTION_DAYS=7
REDIS_HOST="redis.central-platform.svc.cluster.local"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/redis-backup-${DATE}.rdb"

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}

echo "Starting Redis backup at $(date)"

# Trigger BGSAVE to create a snapshot
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} BGSAVE

# Wait for BGSAVE to complete
echo "Waiting for BGSAVE to complete..."
while true; do
    SAVE_IN_PROGRESS=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} INFO Persistence | grep rdb_bgsave_in_progress | cut -d':' -f2 | tr -d '\r\n')
    
    if [ "$SAVE_IN_PROGRESS" -eq 0 ]; then
        echo "BGSAVE completed"
        break
    fi
    
    echo "BGSAVE still in progress..."
    sleep 5
done

# Get the RDB file path
RDB_PATH=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} CONFIG GET dir | grep -A 1 dir | tail -n 1 | tr -d '\r\n')
RDB_FILENAME=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} CONFIG GET dbfilename | grep -A 1 dbfilename | tail -n 1 | tr -d '\r\n')
RDB_FILE="${RDB_PATH}/${RDB_FILENAME}"

# Copy the RDB file (this assumes you're running the script with appropriate access or from within the pod)
echo "Copying RDB file to backup location..."
cp ${RDB_FILE} ${BACKUP_FILE}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: ${BACKUP_FILE}"
    
    # Set permissions
    chmod 600 ${BACKUP_FILE}
    
    # Delete old backups
    find ${BACKUP_DIR} -name "redis-backup-*" -type f -mtime +${RETENTION_DAYS} -delete
    echo "Deleted backups older than ${RETENTION_DAYS} days"
else
    echo "Backup failed!"
    exit 1
fi

echo "Backup process completed at $(date)"
EOF

    # Script de restauración
    cat > ${SCRIPTS_DIR}/redis/backup/restore.sh << 'EOF'
#!/bin/bash
# Redis Restore Script

# Configuration
BACKUP_FILE="$1"
REDIS_HOST="redis.central-platform.svc.cluster.local"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Validate input
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file '$BACKUP_FILE' not found"
    exit 1
fi

echo "Starting Redis restore from $BACKUP_FILE at $(date)"

# Get the current RDB file path and name
RDB_PATH=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} CONFIG GET dir | grep -A 1 dir | tail -n 1 | tr -d '\r\n')
RDB_FILENAME=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} CONFIG GET dbfilename | grep -A 1 dbfilename | tail -n 1 | tr -d '\r\n')
RDB_FILE="${RDB_PATH}/${RDB_FILENAME}"

# Save a backup of the current RDB file
CURRENT_BACKUP="${RDB_FILE}.$(date +%Y%m%d-%H%M%S).bak"
echo "Backing up current RDB file to ${CURRENT_BACKUP}..."
cp ${RDB_FILE} ${CURRENT_BACKUP}

# Copy the backup file to the RDB location
echo "Copying backup file to Redis data directory..."
cp ${BACKUP_FILE} ${RDB_FILE}

# Ensure correct permissions
chmod 644 ${RDB_FILE}
chown redis:redis ${RDB_FILE}

# Restart Redis to load the new RDB file
echo "Restarting Redis to load the backup..."
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} SHUTDOWN SAVE

# Wait for Redis to come back up
echo "Waiting for Redis to restart..."
while ! redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} PING > /dev/null 2>&1; do
    sleep 1
done

echo "Redis restarted successfully"
echo "Restore process completed at $(date)"
EOF

    # Script para análisis de memoria
    cat > ${SCRIPTS_DIR}/redis/maintenance/memory.sh << 'EOF'
#!/bin/bash
# Redis Memory Analysis Script

# Configuration
REDIS_HOST="redis.central-platform.svc.cluster.local"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD}"

echo "Starting Redis memory analysis at $(date)"

# Run INFO command to get memory usage
echo "Memory Usage:"
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} INFO memory | grep -E "used_memory|maxmemory"

# Get the biggest keys
echo -e "\nBiggest Keys by Type:"
for TYPE in string hash list set zset; do
    echo -e "\nTop 10 ${TYPE} keys:"
    redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} --bigkeys-api | grep -A 10 "# ${TYPE}" | grep -v "^#"
done

# Get key statistics
echo -e "\nKey Space Statistics:"
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} INFO keyspace

# Get memory statistics with MEMORY STATS
echo -e "\nDetailed Memory Stats:"
redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} MEMORY STATS

echo "Memory analysis completed at $(date)"
EOF

    # Script para gestión de claves
    cat > ${SCRIPTS_DIR}/redis/maintenance/keys.sh << 'EOF'
#!/bin/bash
# Redis Keys Management Script

# Configuration
REDIS_HOST="redis.central-platform.svc.cluster.local"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD}"
PATTERN="$1"
ACTION="$2"

# Validate input
if [ -z "$PATTERN" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <key_pattern> <action>"
    echo "Actions: count, list, delete"
    exit 1
fi

echo "Starting Redis keys management at $(date)"

case "$ACTION" in
    "count")
        echo "Counting keys matching pattern: ${PATTERN}"
        COUNT=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} --scan --pattern "${PATTERN}" | wc -l)
        echo "Number of matching keys: ${COUNT}"
        ;;
        
    "list")
        echo "Listing keys matching pattern: ${PATTERN}"
        redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} --scan --pattern "${PATTERN}" | head -n 100
        COUNT=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} --scan --pattern "${PATTERN}" | wc -l)
        echo "Total number of matching keys: ${COUNT}"
        ;;
        
    "delete")
        echo "WARNING: About to delete keys matching pattern: ${PATTERN}"
        echo "Are you sure you want to continue? (yes/no)"
        read CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            echo "Operation cancelled"
            exit 0
        fi
        
        echo "Deleting keys matching pattern: ${PATTERN}"
        
        # Using scan + del for safe deletion
        redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} --scan --pattern "${PATTERN}" | while read KEY; do
            redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} -a ${REDIS_PASSWORD} DEL "$KEY"
            echo "Deleted: $KEY"
        done
        
        echo "Deletion completed"
        ;;
        
    *)
        echo "Unknown action: ${ACTION}"
        echo "Supported actions: count, list, delete"
        exit 1
        ;;
esac

echo "Keys management completed at $(date)"
EOF

    # Hacer ejecutables los scripts
    chmod +x ${SCRIPTS_DIR}/redis/backup/backup.sh
    chmod +x ${SCRIPTS_DIR}/redis/backup/restore.sh
    chmod +x ${SCRIPTS_DIR}/redis/maintenance/memory.sh
    chmod +x ${SCRIPTS_DIR}/redis/maintenance/keys.sh
    
    log_success "Scripts para Redis generados correctamente"
}

# Generar documentación
create_documentation() {
    log_info "Generando documentación..."
    
    # Documentación de esquema MongoDB
    cat > ${DOCS_DIR}/persistence/mongodb/schema.md << 'EOF'
# MongoDB Schema Documentation

## Overview

This document describes the MongoDB schema structure used in the Central Platform for IoT telemetry, device data, and alerts.

## Databases and Collections

The Central Platform uses the `central_platform` database with the following collections:

### 1. `devices` Collection

Stores the information about IoT devices.

```javascript
{
  "_id": ObjectId,                // Unique identifier
  "deviceId": String,             // External device identifier
  "name": String,                 // Device name
  "type": String,                 // Device type (e.g., "tracker", "sensor")
  "status": String,               // Current status ("online", "offline", "maintenance")
  "model": String,                // Device model
  "manufacturer": String,         // Device manufacturer
  "firmware": String,             // Current firmware version
  "location": {                   // GeoJSON format location
    "type": "Point",
    "coordinates": [Number, Number]  // [longitude, latitude]
  },
  "lastTelemetry": ISODate,       // Timestamp of last telemetry data
  "metadata": Object,             // Arbitrary metadata
  "ownerId": String,              // Reference to the user who owns the device
  "groupId": String,              // Reference to the group the device belongs to
  "createdAt": ISODate,           // Creation timestamp
  "updatedAt": ISODate            // Last update timestamp
}
```

### 2. `telemetry` Collection

Stores telemetry data received from IoT devices.

```javascript
{
  "_id": ObjectId,                // Unique identifier
  "deviceId": String,             // Reference to the device
  "timestamp": ISODate,           // Timestamp when the data was generated
  "data": {                       // Telemetry data
    "temperature": Number,        // Temperature in Celsius
    "humidity": Number,           // Humidity percentage
    "batteryLevel": Number,       // Battery level percentage
    "speed": Number,              // Speed in km/h
    // Other sensor-specific fields
  },
  "location": {                   // GeoJSON format location
    "type": "Point",
    "coordinates": [Number, Number]  // [longitude, latitude]
  },
  "receivedAt": ISODate           // Timestamp when the data was received
}
```

### 3. `alerts` Collection

Stores alerts generated from telemetry data and rule conditions.

```javascript
{
  "_id": ObjectId,                // Unique identifier
  "deviceId": String,             // Reference to the device
  "ruleId": String,               // Reference to the alert rule
  "message": String,              // Alert message
  "severity": String,             // Severity level ("info", "warning", "error", "critical")
  "status": String,               // Alert status ("active", "acknowledged", "resolved")
  "telemetryData": Object,        // Copy of the telemetry data that triggered the alert
  "acknowledgedBy": String,       // Reference to the user who acknowledged the alert
  "acknowledgedAt": ISODate,      // Timestamp when the alert was acknowledged
  "resolvedAt": ISODate,          // Timestamp when the alert was resolved
  "createdAt": ISODate            // Timestamp when the alert was created
}
```

### 4. `alert_rules` Collection

Stores rules for generating alerts from telemetry data.

```javascript
{
  "_id": ObjectId,                // Unique identifier
  "name": String,                 // Rule name
  "description": String,          // Rule description
  "deviceId": String,             // Target specific device (optional)
  "deviceType": String,           // Target specific device type (optional)
  "condition": Object,            // Condition definition
  "message": String,              // Alert message template
  "severity": String,             // Alert severity level
  "enabled": Boolean,             // Whether the rule is enabled
  "notifications": {              // Notification settings
    "email": Boolean,
    "sms": Boolean,
    "push": Boolean,
    "webhook": String
  },
  "cooldown": Number,             // Minimum seconds between alerts from this rule
  "createdBy": String,            // Reference to the user who created the rule
  "createdAt": ISODate,           // Creation timestamp
  "updatedAt": ISODate            // Last update timestamp
}
```

## Indexes

### devices Collection

```javascript
// Create a unique index on deviceId
db.devices.createIndex({ deviceId: 1 }, { unique: true });

// Create an index on status for quick filtering
db.devices.createIndex({ status: 1 });

// Create an index on type for quick filtering
db.devices.createIndex({ type: 1 });

// Create a geospatial index on location
db.devices.createIndex({ "location.coordinates": "2dsphere" });
```

### telemetry Collection

```javascript
// Create a compound index on deviceId and timestamp for quick lookups
db.telemetry.createIndex({ deviceId: 1, timestamp: -1 });

// Create an index on timestamp for time-based queries
db.telemetry.createIndex({ timestamp: -1 });

// Create an index on specific telemetry data fields 
db.telemetry.createIndex({ "data.temperature": 1 });
```

### alerts Collection

```javascript
// Create a compound index on deviceId and status
db.alerts.createIndex({ deviceId: 1, status: 1 });

// Create an index on severity
db.alerts.createIndex({ severity: 1 });

// Create an index on creation timestamp
db.alerts.createIndex({ createdAt: -1 });
```
EOF

    # Documentación de PostgreSQL
    cat > ${DOCS_DIR}/persistence/postgresql/schema.md << 'EOF'
# PostgreSQL Schema Documentation

## Overview

This document describes the PostgreSQL database schema used in the Central Platform for structured data such as users, groups, and devices metadata.

## Database Schema

The Central Platform uses the `central_platform` database with the following tables:

### 1. `users` Table

Stores user accounts and authentication information.

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) NOT NULL UNIQUE,
  email VARCHAR(255) NOT NULL UNIQUE,
  full_name VARCHAR(255) NOT NULL,
  hashed_password VARCHAR(255) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  is_superuser BOOLEAN DEFAULT FALSE,
  is_sso BOOLEAN DEFAULT FALSE,
  role VARCHAR(50) DEFAULT 'user',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### 2. `groups` Table

Stores user groups for organizing users and devices.

```sql
CREATE TABLE groups (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  description TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### 3. `user_group` Table

Associates users with groups (many-to-many relationship).

```sql
CREATE TABLE user_group (
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  group_id INTEGER REFERENCES groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_id)
);
```

### 4. `devices` Table

Stores device information and metadata. Note that telemetry data is stored in MongoDB, while this table stores structural information.

```sql
CREATE TABLE devices (
  id SERIAL PRIMARY KEY,
  device_id VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  type VARCHAR(50) NOT NULL,
  status VARCHAR(50) DEFAULT 'offline',
  model VARCHAR(255),
  manufacturer VARCHAR(255),
  firmware VARCHAR(255),
  metadata JSONB,
  owner_id INTEGER REFERENCES users(id),
  group_id INTEGER REFERENCES groups(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## Indexes

### users Table

```sql
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
```

### devices Table

```sql
CREATE INDEX idx_devices_status ON devices(status);
CREATE INDEX idx_devices_type ON devices(type);
CREATE INDEX idx_devices_owner ON devices(owner_id);
CREATE INDEX idx_devices_group ON devices(group_id);
```

## Triggers

The Central Platform uses triggers to automatically update the `updated_at` field when records are modified:

```sql
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$ LANGUAGE plpgsql;

-- Apply trigger to tables
CREATE TRIGGER update_users_timestamp BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_groups_timestamp BEFORE UPDATE ON groups
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_devices_timestamp BEFORE UPDATE ON devices
FOR EACH ROW EXECUTE FUNCTION update_timestamp();
```

## Entity-Relationship Diagram

```
+---------------+       +----------------+       +----------------+
|    users      |       |   user_group   |       |     groups     |
+---------------+       +----------------+       +----------------+
| id            |       | user_id        |       | id             |
| username      |       | group_id       |       | name           |
| email         |       +----------------+       | description    |
| full_name     |       |                |       | created_by     |
| hashed_password|      | Foreign Keys:  |       | created_at     |
| is_active     |      <--user_id to users.id    | updated_at     |
| is_superuser  |       | group_id to groups.id->|                |
| is_sso        |       |                |       +----------------+
| role          |       +----------------+               ^
| created_at    |                                        |
| updated_at    |                                        |
+---------------+                                        |
       ^                                                 |
       |                                                 |
       |          +----------------+                     |
       |          |    devices     |                     |
       |          +----------------+                     |
       |          | id             |                     |
       |          | device_id      |                     |
       |          | name           |                     |
       +----------| owner_id       |                     |
                  | group_id       |---------------------+
                  | type           |
                  | status         |
                  | model          |
                  | manufacturer   |
                  | firmware       |
                  | metadata       |
                  | created_at     |
                  | updated_at     |
                  +----------------+
```
EOF

    # Documentación de elasticsearch
    cat > ${DOCS_DIR}/persistence/elasticsearch/indices.md << 'EOF'
# Elasticsearch Indices Documentation

## Overview

This document describes the Elasticsearch indices used in the Central Platform for search, analytics, and log aggregation.

## Index Structure

The Central Platform uses the following Elasticsearch indices:

### 1. `devices` Index

Stores searchable device information for quick lookups and analytics.

```json
{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "name": { "type": "text", "fields": { "keyword": { "type": "keyword" } } },
      "type": { "type": "keyword" },
      "status": { "type": "keyword" },
      "model": { "type": "keyword" },
      "manufacturer": { "type": "keyword" },
      "firmware": { "type": "keyword" },
      "location": { "type": "geo_point" },
      "lastTelemetry": { "type": "date" },
      "metadata": { "type": "object", "dynamic": true },
      "ownerId": { "type": "keyword" },
      "groupId": { "type": "keyword" },
      "createdAt": { "type": "date" },
      "updatedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}
```

### 2. `telemetry` Index

Stores telemetry data for analytics and visualization.

```json
{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "data": { "type": "object", "dynamic": true },
      "location": { "type": "geo_point" },
      "receivedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1
  }
}
```

### 3. `alerts` Index

Stores alert information for search and analytics.

```json
{
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "ruleId": { "type": "keyword" },
      "message": { "type": "text" },
      "severity": { "type": "keyword" },
      "status": { "type": "keyword" },
      "telemetryData": { "type": "object", "dynamic": true },
      "acknowledgedBy": { "type": "keyword" },
      "acknowledgedAt": { "type": "date" },
      "resolvedAt": { "type": "date" },
      "createdAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  }
}
```

### 4. `security-*` Indices

Time-based indices for security events and logs.

```json
{
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "event": {
        "properties": {
          "category": { "type": "keyword" },
          "type": { "type": "keyword" },
          "action": { "type": "keyword" },
          "outcome": { "type": "keyword" },
          "severity": { "type": "short" },
          "sequence": { "type": "long" }
        }
      },
      "user": {
        "properties": {
          "name": { "type": "keyword" },
          "id": { "type": "keyword" },
          "email": { "type": "keyword" },
          "groups": { "type": "keyword" }
        }
      },
      "source": {
        "properties": {
          "ip": { "type": "ip" },
          "port": { "type": "integer" },
          "geo": {
            "properties": {
              "country_name": { "type": "keyword" },
              "region_name": { "type": "keyword" },
              "city_name": { "type": "keyword" },
              "location": { "type": "geo_point" }
            }
          }
        }
      },
      "message": { "type": "text" },
      "log": {
        "properties": {
          "level": { "type": "keyword" },
          "logger": { "type": "keyword" }
        }
      }
    }
  },
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "index.lifecycle.name": "security_policy"
  }
}
```

## Index Lifecycle Management (ILM)

The Central Platform uses Index Lifecycle Management (ILM) to manage time-series indices:

### Telemetry ILM Policy

```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_size": "50gb"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "forcemerge": {
            "max_num_segments": 1
          },
          "shrink": {
            "number_of_shards": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

## Index Templates

The Central Platform uses index templates to automatically apply mappings and settings to new indices:

### Telemetry Template

```json
{
  "index_patterns": ["telemetry-*"],
  "mappings": {
    "properties": {
      "deviceId": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "data": { "type": "object", "dynamic": true },
      "location": { "type": "geo_point" },
      "receivedAt": { "type": "date" }
    }
  },
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1,
    "index.lifecycle.name": "telemetry_policy",
    "index.lifecycle.rollover_alias": "telemetry"
  }
}
```

### Security Logs Template

```json
{
  "index_patterns": ["security-*"],
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "event": {
        "properties": {
          "category": { "type": "keyword" },
          "type": { "type": "keyword" },
          "action": { "type": "keyword" },
          "outcome": { "type": "keyword" },
          "severity": { "type": "short" },
          "sequence": { "type": "long" }
        }
      },
      "user": {
        "properties": {
          "name": { "type": "keyword" },
          "id": { "type": "keyword" },
          "email": { "type": "keyword" },
          "groups": { "type": "keyword" }
        }
      },
      "source": {
        "properties": {
          "ip": { "type": "ip" },
          "port": { "type": "integer" },
          "geo": {
            "properties": {
              "country_name": { "type": "keyword" },
              "region_name": { "type": "keyword" },
              "city_name": { "type": "keyword" },
              "location": { "type": "geo_point" }
            }
          }
        }
      },
      "message": { "type": "text" },
      "log": {
        "properties": {
          "level": { "type": "keyword" },
          "logger": { "type": "keyword" }
        }
      }
    }
  },
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "index.lifecycle.name": "security_policy"
  }
}
```
EOF

    # Documentación de Redis
    cat > ${DOCS_DIR}/persistence/redis/keys.md << 'EOF'
# Redis Keys Structure Documentation

## Overview

This document describes the Redis key structure and patterns used in the Central Platform for caching, messaging, and real-time data.

## Key Namespaces

The Central Platform uses the following key namespaces in Redis:

### 1. `device:{deviceId}` Keys

Store the current state of devices for quick access without database queries.

```
device:{deviceId}                # Hash containing device state
  - status                       # Current device status
  - lastSeen                     # Timestamp of last activity
  - battery                      # Current battery level
  - location                     # Current location (as JSON string)
  - metadata                     # Additional metadata (as JSON string)
```

### 2. `device:{deviceId}:telemetry` Keys

Store recent telemetry data for devices in a time series.

```
device:{deviceId}:telemetry      # Time series of recent telemetry data
```

### 3. `device:{deviceId}:cmd:{commandId}` Keys

Store pending commands for devices.

```
device:{deviceId}:cmd:{commandId}  # Hash containing command details
  - action                         # Command action to execute
  - params                         # Command parameters (as JSON string)
  - timestamp                      # When the command was issued
  - status                         # Command status (pending, sent, ack, completed, failed)
  - timeout                        # Command timeout in seconds
  - response                       # Command response (as JSON string)
```

### 4. `session:{sessionId}` Keys

Store user session data with expiration.

```
session:{sessionId}              # Hash containing session data
  - userId                       # User ID
  - username                     # Username
  - roles                        # User roles (as JSON array)
  - created                      # Session creation timestamp
  - lastActive                   # Last activity timestamp
  - ip                           # Client IP address
  - userAgent                    # Client user agent
```

### 5. `alert:{alertId}` Keys

Store active alerts for quick access.

```
alert:{alertId}                  # Hash containing alert details
  - deviceId                     # Device ID
  - ruleId                       # Rule ID that triggered the alert
  - severity                     # Alert severity
  - message                      # Alert message
  - timestamp                    # Alert timestamp
  - status                       # Alert status
```

## Pub/Sub Channels

The Central Platform uses the following Redis Pub/Sub channels for real-time messaging:

### 1. `device:status`

Channel for device status updates.

```json
{
  "deviceId": "device123",
  "status": "online",
  "timestamp": 1600000000000,
  "metadata": { ... }
}
```

### 2. `device:telemetry`

Channel for real-time telemetry data.

```json
{
  "deviceId": "device123",
  "timestamp": 1600000000000,
  "data": {
    "temperature": 25.5,
    "humidity": 60,
    "batteryLevel": 85
  },
  "location": {
    "lat": 40.7128,
    "lng": -74.0060
  }
}
```

### 3. `alerts`

Channel for real-time alert notifications.

```json
{
  "alertId": "alert123",
  "deviceId": "device123",
  "severity": "critical",
  "message": "Temperature exceeds threshold",
  "timestamp": 1600000000000
}
```

### 4. `command:status`

Channel for command status updates.

```json
{
  "commandId": "cmd123",
  "deviceId": "device123",
  "status": "completed",
  "timestamp": 1600000000000,
  "response": { ... }
}
```

## Expiration and TTL

The Central Platform uses the following TTL (Time-To-Live) settings for Redis keys:

| Key Pattern | TTL | Description |
|-------------|-----|-------------|
| `device:{deviceId}` | None | Persistent device state |
| `device:{deviceId}:telemetry` | 24 hours | Recent telemetry data |
| `device:{deviceId}:cmd:{commandId}` | 1 hour | Command details (after completion) |
| `session:{sessionId}` | 1 hour (refreshable) | User session data |
| `alert:{alertId}` | None (removed when resolved) | Active alert data |

## Stream Keys

The Central Platform uses Redis Streams for some time-series data:

### 1. `telemetry-stream`

Stream of all telemetry data for analysis and processing.

```
telemetry-stream                 # Stream of telemetry events
  - deviceId                     # Device ID
  - timestamp                    # Event timestamp
  - temperature                  # Temperature reading
  - humidity                     # Humidity reading
  - batteryLevel                 # Battery level
  - ... other telemetry fields
```

### 2. `events-stream`

Stream of system events for auditing and monitoring.

```
events-stream                    # Stream of system events
  - type                         # Event type
  - source                       # Event source
  - timestamp                    # Event timestamp
  - userId                       # Associated user (if applicable)
  - deviceId                     # Associated device (if applicable)
  - details                      # Event details (as JSON string)
```

## Consumer Groups

The following consumer groups are used for processing Redis Streams:

| Stream | Consumer Group | Description |
|--------|---------------|-------------|
| `telemetry-stream` | `analytics` | Analytics processing |
| `telemetry-stream` | `alerts` | Alert processing |
| `events-stream` | `audit` | Audit trail processing |
| `events-stream` | `monitoring` | System monitoring |
EOF

    log_success "Documentación generada correctamente"
}

# Generar script de despliegue principal
create_deploy_script() {
    log_info "Generando script de despliegue principal..."
    
    cat > ${BASE_DIR}/deploy-zone-e.sh << 'EOF'
#!/bin/bash
# Script para desplegar la Zona E (Persistencia) en Kubernetes

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mensajes
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Verificar si kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl no está instalado. Por favor instálelo antes de continuar."
    exit 1
fi

# Verificar si el namespace existe
NAMESPACE="central-platform"
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    log_info "Creando namespace ${NAMESPACE}..."
    kubectl create namespace ${NAMESPACE}
    log_success "Namespace ${NAMESPACE} creado."
else
    log_info "Namespace ${NAMESPACE} ya existe."
fi

# Configurar secretos
configure_secrets() {
    log_info "Configurando secretos..."
    
    # Generar contraseñas aleatorias si no existen
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 12)
    MONGO_APP_PASSWORD=$(openssl rand -base64 12)
    POSTGRES_PASSWORD=$(openssl rand -base64 12)
    ELASTIC_PASSWORD=$(openssl rand -base64 12)
    REDIS_PASSWORD=$(openssl rand -base64 12)
    
    # MongoDB secrets
    kubectl create secret generic mongodb-secret \
        --namespace=${NAMESPACE} \
        --from-literal=root-username=admin \
        --from-literal=root-password=${MONGO_ROOT_PASSWORD} \
        --from-literal=app-username=app_user \
        --from-literal=app-password=${MONGO_APP_PASSWORD} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # PostgreSQL secrets
    kubectl create secret generic postgresql-secret \
        --namespace=${NAMESPACE} \
        --from-literal=postgres-user=postgres \
        --from-literal=postgres-password=${POSTGRES_PASSWORD} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Elasticsearch secrets
    kubectl create secret generic elasticsearch-secret \
        --namespace=${NAMESPACE} \
        --from-literal=elastic-password=${ELASTIC_PASSWORD} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Redis secrets
    kubectl create secret generic redis-secret \
        --namespace=${NAMESPACE} \
        --from-literal=redis-password=${REDIS_PASSWORD} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secretos configurados."
    
    # Guardar contraseñas en un archivo seguro
    SECRETS_FILE="/root/.central-platform-secrets"
    echo "# Central Platform Secrets - Generados el $(date)" > ${SECRETS_FILE}
    echo "MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}" >> ${SECRETS_FILE}
    echo "MONGO_APP_PASSWORD=${MONGO_APP_PASSWORD}" >> ${SECRETS_FILE}
    echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> ${SECRETS_FILE}
    echo "ELASTIC_PASSWORD=${ELASTIC_PASSWORD}" >> ${SECRETS_FILE}
    echo "REDIS_PASSWORD=${REDIS_PASSWORD}" >> ${SECRETS_FILE}
    chmod 600 ${SECRETS_FILE}
    
    log_info "Contraseñas guardadas en ${SECRETS_FILE}"
}

# Desplegar MongoDB
deploy_mongodb() {
    log_info "Desplegando MongoDB..."
    
    kubectl apply -f /opt/central-platform/k8s/databases/mongodb/configmap.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/mongodb/service.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/mongodb/statefulset.yaml
    
    log_info "Esperando a que MongoDB esté listo..."
    kubectl rollout status statefulset/mongodb -n ${NAMESPACE} --timeout=300s
    
    log_success "MongoDB desplegado correctamente."
}

# Desplegar PostgreSQL
deploy_postgresql() {
    log_info "Desplegando PostgreSQL..."
    
    kubectl apply -f /opt/central-platform/k8s/databases/postgresql/configmap.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/postgresql/service.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/postgresql/statefulset.yaml
    
    log_info "Esperando a que PostgreSQL esté listo..."
    kubectl rollout status statefulset/postgresql -n ${NAMESPACE} --timeout=300s
    
    log_success "PostgreSQL desplegado correctamente."
}

# Desplegar Elasticsearch
deploy_elasticsearch() {
    log_info "Desplegando Elasticsearch..."
    
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/configmap.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/service.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/statefulset.yaml
    
    log_info "Esperando a que Elasticsearch esté listo..."
    kubectl rollout status statefulset/elasticsearch -n ${NAMESPACE} --timeout=600s
    
    log_info "Desplegando Kibana..."
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/kibana/configmap.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/kibana/service.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/elasticsearch/kibana/deployment.yaml
    
    log_info "Esperando a que Kibana esté listo..."
    kubectl rollout status deployment/kibana -n ${NAMESPACE} --timeout=300s
    
    log_success "Elasticsearch y Kibana desplegados correctamente."
}

# Desplegar Redis
deploy_redis() {
    log_info "Desplegando Redis..."
    
    kubectl apply -f /opt/central-platform/k8s/databases/redis/configmap.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/redis/service.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/redis/statefulset.yaml
    
    log_info "Esperando a que Redis esté listo..."
    kubectl rollout status statefulset/redis -n ${NAMESPACE} --timeout=300s
    
    log_success "Redis desplegado correctamente."
}

# Desplegar monitoreo
deploy_monitoring() {
    log_info "Desplegando componentes de monitoreo..."
    
    # MongoDB exporter
    kubectl apply -f /opt/central-platform/k8s/databases/mongodb/monitoring/mongodb-exporter.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/mongodb/monitoring/servicemonitor.yaml
    
    # PostgreSQL exporter
    kubectl apply -f /opt/central-platform/k8s/databases/postgresql/monitoring/postgres-exporter.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/postgresql/monitoring/servicemonitor.yaml
    
    # Redis exporter
    kubectl apply -f /opt/central-platform/k8s/databases/redis/monitoring/redis-exporter.yaml
    kubectl apply -f /opt/central-platform/k8s/databases/redis/monitoring/servicemonitor.yaml
    
    log_success "Componentes de monitoreo desplegados correctamente."
}

# Verificar el estado de los servicios
check_services() {
    log_info "Verificando el estado de los servicios..."
    
    echo ""
    echo "MongoDB:"
    kubectl get pods -l app=mongodb -n ${NAMESPACE}
    echo ""
    
    echo "PostgreSQL:"
    kubectl get pods -l app=postgresql -n ${NAMESPACE}
    echo ""
    
    echo "Elasticsearch:"
    kubectl get pods -l app=elasticsearch -n ${NAMESPACE}
    echo ""
    
    echo "Kibana:"
    kubectl get pods -l app=kibana -n ${NAMESPACE}
    echo ""
    
    echo "Redis:"
    kubectl get pods -l app=redis -n ${NAMESPACE}
    echo ""
    
    echo "Servicios:"
    kubectl get services -n ${NAMESPACE} | grep -E 'mongodb|postgresql|elasticsearch|kibana|redis'
    echo ""
    
    echo "Exporters:"
    kubectl get pods -n ${NAMESPACE} | grep -E 'exporter'
    echo ""
    
    log_success "Verificación completada."
}

# Menu principal
echo "=================================================="
echo "    Despliegue de Zona E (Persistencia)          "
echo "=================================================="
echo ""
echo "Este script desplegará los componentes de persistencia:"
echo ""
echo "1. MongoDB (Replica Set)"
echo "2. PostgreSQL"
echo "3. Elasticsearch + Kibana"
echo "4. Redis"
echo "5. Componentes de monitoreo"
echo ""
echo "=================================================="
echo ""

read -p "¿Desea proceder con el despliegue? (y/n): " CONFIRM
if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    log_info "Operación cancelada."
    exit 0
fi

# Ejecutar despliegue
configure_secrets
deploy_mongodb
deploy_postgresql
deploy_elasticsearch
deploy_redis
deploy_monitoring
check_services

log_success "Despliegue de la Zona E (Persistencia) completado exitosamente."
echo ""
echo "Próximos pasos recomendados:"
echo "1. Configurar réplica de MongoDB ejecutando el script /opt/central-platform/scripts/mongodb/init/create-replica-set.js"
echo "2. Crear índices en MongoDB ejecutando el script /opt/central-platform/scripts/mongodb/init/create-indexes.js"
echo "3. Crear índices en Elasticsearch ejecutando el script /opt/central-platform/scripts/elasticsearch/init/create-indices.sh"
echo "4. Configurar respaldos programados para todos los componentes"
echo ""
echo "Para más información, consultar la documentación en /opt/central-platform/docs/persistence/"
echo ""
EOF

    chmod +x ${BASE_DIR}/deploy-zone-e.sh
    
    log_success "Script de despliegue principal generado correctamente"
}

# Función principal
main() {
    log_info "Iniciando la generación de los archivos para la Zona E (Persistencia)..."
    
    # Crear estructura de directorios
    create_directory_structure
    
    # Generar archivos Kubernetes
    create_mongodb_k8s_files
    create_postgresql_k8s_files
    create_elasticsearch_k8s_files
    create_redis_k8s_files
    
    # Generar scripts
    create_mongodb_scripts
    create_postgresql_scripts
    create_elasticsearch_scripts
    create_redis_scripts
    
    # Generar documentación
    create_documentation
    
    # Generar script de despliegue principal
    create_deploy_script
    
    log_success "Generación de archivos completada exitosamente"
    echo ""
    echo "Los archivos se han generado en: ${BASE_DIR}"
    echo "Para desplegar la Zona E, ejecute el script: ${BASE_DIR}/deploy-zone-e.sh"
    echo ""
    
    # Establecer permisos correctos
    chown -R root:root ${BASE_DIR}
    chmod -R 755 ${BASE_DIR}
    find ${SCRIPTS_DIR} -type f -name "*.sh" -exec chmod +x {} \;
}

# Ejecutar función principal
main

EOF

    # Script de compactación
    cat > ${SCRIPTS_DIR}/mongodb/maintenance/compact.js << 'EOF'
// MongoDB Compact Script
// This script compacts all collections in all databases

// Connect to replica set
var conn = new Mongo("mongodb://mongodb-0.mongodb-headless.central-platform.svc.cluster.local:27017,mongodb-1.mongodb-headless.central-platform.svc.cluster.local:27017,mongodb-2.mongodb-headless.central-platform.svc.cluster.local:27017/?replicaSet=rs0");

// Authenticate
conn.getDB("admin").auth(process.env.MONGO_ADMIN_USER, process.env.MONGO_ADMIN_PASSWORD);

// Get all database names (excluding system databases)
var dbs = conn.getDBNames().filter(function(db) {
  return db !== "admin" && db !== "config" && db !== "local";
});

// Process each database
dbs.forEach(function(dbName) {
  var db = conn.getDB(dbName);
  
  // Get all collections in the database
  var collections = db.getCollectionNames();
  
  print("Compacting database: " + dbName);
  
  // Process each collection
  collections.forEach(function(collName) {
    try {
      print("  Compacting collection: " + collName);
      db.runCommand({ compact: collName });
    } catch (e) {
      print("  Error compacting collection " + collName + ": " + e);
    }
  });
});

print("Compaction complete");
EOF

    # Script para configuración del ReplicaSet
    cat > ${SCRIPTS_DIR}/mongodb/init/create-replica-set.js << 'EOF'
// MongoDB Replica Set Initialization Script

// Wait for MongoDB to start
sleep(5000);

// Connect to the primary node
var conn = new Mongo("mongodb://mongodb-0.mongodb-headless.central-platform.svc.cluster.local:27017");

// Check if replica set already initialized
var status = rs.status();
if (status.code === 94) {
  print("Initializing replica set...");
  
  // Define replica set configuration
  var config = {
    _id: "rs0",
    members: [
      { _id: 0, host: "mongodb-0.mongodb-headless.central-platform.svc.cluster.local:27017", priority: 3 },
      { _id: 1, host: "mongodb-1.mongodb-headless.central-platform.svc.cluster.local:27017", priority: 2 },
      { _id: 2, host: "mongodb-2.mongodb-headless.central-platform.svc.cluster.local:27017", priority: 1 }
    ]
  };
  
  // Initialize the replica set
  rs.initiate(config);
  
  // Wait for replica set to initialize
  sleep(10000);
  
  // Check status
  var rsStatus = rs.status();
  print("Replica set status: " + JSON.stringify(rsStatus));
} else {
  print("Replica set already initialized. Status: " + JSON.stringify(status));
}

// Create admin users (only on primary)
if (rs.isMaster().ismaster) {
  print("Creating admin user...");
  db = db.getSiblingDB('admin');
  
  // Create admin user if it doesn't exist
  var adminUsers = db.getUsers();
  var adminUserExists = false;
  
  for (var i = 0; i < adminUsers.users.length; i++) {
    if (adminUsers.users[i].user === "admin") {
      adminUserExists = true;
      break;
    }
  }
  
  if (!adminUserExists) {
    db.createUser({
      user: "admin",
      pwd: process.env.MONGO_ADMIN_PASSWORD,
      roles: [
        { role: "userAdminAnyDatabase", db: "admin" },
        { role: "dbAdminAnyDatabase", db: "admin" },
        { role: "readWriteAnyDatabase", db: "admin" },
        { role: "clusterAdmin", db: "admin" }
      ]
    });
    print("Admin user created");
  } else {
    print("Admin user already exists");
  }
  
  // Create application user
  print("Creating application user...");
  db = db.getSiblingDB('central_platform');
  
  var appUsers = db.getUsers();
  var appUserExists = false;
  
  for (var i = 0; i < appUsers.users.length; i++) {
    if (appUsers.users[i].user === "app_user") {
      appUserExists = true;
      break;
    }
  }
  
  if (!appUserExists) {
    db.createUser({
      user: "app_user",
      pwd: process.env.MONGO_APP_PASSWORD,
      roles: [
        { role: "readWrite", db: "central_platform" }
      ]
    });
    print("Application user created");
  } else {
    print("Application user already exists");
  }
}

print("Initialization complete");
EOF

    # Hacer ejecutables los scripts
    chmod +x ${SCRIPTS_DIR}/mongodb/backup/backup.sh
    chmod +x ${SCRIPTS_DIR}/mongodb/backup/restore.sh
    
    log_success "Scripts para MongoDB generados correctamente"
}

# Generar scripts de backup para PostgreSQL
create_postgresql_scripts() {
    log_info "Generando scripts para PostgreSQL..."
    
    # Script de backup
    cat > ${SCRIPTS_DIR}/postgresql/backup/backup.sh << 'EOF'
#!/bin/bash
# PostgreSQL Backup Script

# Configuration
BACKUP_DIR="/backup/postgresql"
RETENTION_DAYS=7
DB_NAME="central_platform"
DB_USER="app_user"
DB_PASSWORD="${POSTGRES_APP_PASSWORD}"
DB_HOST="postgresql.central-platform.svc.cluster.local"
DB_PORT="5432"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/postgresql-backup-${DATE}.sql.gz"

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}

echo "Starting PostgreSQL backup at $(date)"

# Set environment variables for pg_dump
export PGPASSWORD="${DB_PASSWORD}"

# Perform the backup with compression
pg_dump -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -F c | gzip > ${BACKUP_FILE}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: ${BACKUP_FILE}"
    
    # Set permissions
    chmod 600 ${BACKUP_FILE}
    
    # Delete old backups
    find ${BACKUP_DIR} -name "postgresql-backup-*" -type f -mtime +${RETENTION_DAYS} -delete
    echo "Deleted backups older than ${RETENTION_DAYS} days"
else
    echo "Backup failed!"
    exit 1
fi

# Unset password environment variable
unset PGPASSWORD

echo "Backup process completed at $(date)"
EOF

    # Script de restauración
    cat > ${SCRIPTS_DIR}/postgresql/backup/restore.sh << 'EOF'
#!/bin/bash
# PostgreSQL Restore Script

# Configuration
BACKUP_FILE="$1"
DB_NAME="central_platform"
DB_USER="app_user"
DB_PASSWORD="${POSTGRES_APP_PASSWORD}"
DB_HOST="postgresql.central-platform.svc.cluster.local"
DB_PORT="5432"

# Validate input
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file '$BACKUP_FILE' not found"
    exit 1
fi

echo "Starting PostgreSQL restore from $BACKUP_FILE at $(date)"

# Set environment variables for pg_restore
export PGPASSWORD="${DB_PASSWORD}"

# Check if it's a compressed file
if [[ "$BACKUP_FILE" == *.gz ]]; then
    # Decompress and restore
    gunzip -c ${BACKUP_FILE} | pg_restore -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} --clean --if-exists
else
    # Direct restore
    pg_restore -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} --clean --if-exists ${BACKUP_FILE}
fi

# Check if restore was successful
if [ $? -eq 0 ]; then
    echo "Restore completed successfully from ${BACKUP_FILE}"
else
    echo "Restore failed!"
    exit 1
fi

# Unset password environment variable
unset PGPASSWORD

echo "Restore process completed at $(date)"
EOF

    # Script de vacuum
    cat > ${SCRIPTS_DIR}/postgresql/maintenance/vacuum.sql << 'EOF'
-- PostgreSQL Vacuum Script

-- Vacuum all tables in the database
VACUUM VERBOSE ANALYZE;

-- More aggressive vacuum for specific tables (if needed)
-- VACUUM FULL VERBOSE ANALYZE users;
-- VACUUM FULL VERBOSE ANALYZE devices;
EOF

    # Script de reindexación
    cat > ${SCRIPTS_DIR}/postgresql/maintenance/reindex.sql << 'EOF'
-- PostgreSQL Reindex Script

-- Reindex all tables and indexes in the database
REINDEX DATABASE central_platform;

-- Alternative: Reindex specific tables (if needed)
-- REINDEX TABLE users;
-- REINDEX TABLE devices;
EOF

    # Hacer ejecutables los scripts
    chmod +x ${SCRIPTS_DIR}/postgresql/backup/backup.sh
    chmod +x ${SCRIPTS_DIR}/postgresql/backup/restore.sh
    
    log_success "Scripts para PostgreSQL generados correctamente"
}

# Generar scripts de backup para Elasticsearch
create_elasticsearch_scripts() {
    log_info "Generando scripts para Elasticsearch..."
    
    # Script de snapshot
    cat > ${SCRIPTS_DIR}/elasticsearch/backup/snapshot.sh << 'EOF'
#!/bin/bash
# Elasticsearch Snapshot Script

# Configuration
ES_HOST="elasticsearch.central-platform.svc.cluster.local"
ES_PORT="9200"
ES_USER="elastic"
ES_PASSWORD="${ELASTIC_PASSWORD}"
REPO_NAME="backup_repo"
SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"
RETENTION_COUNT=7

echo "Starting Elasticsearch snapshot at $(date)"

# Check if repository exists, create if it doesn't
REPO_EXISTS=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}" | grep -c "${REPO_NAME}")

if [ "$REPO_EXISTS" -eq 0 ]; then
    echo "Error: Snapshot repository does not exist!"
    exit 1
fi

# Check if snapshot exists
SNAPSHOT_EXISTS=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/${SNAPSHOT_NAME}" | grep -c "${SNAPSHOT_NAME}")

if [ "$SNAPSHOT_EXISTS" -eq 0 ]; then
    echo "Error: Snapshot ${SNAPSHOT_NAME} not found!"
    exit 1
fi

# Close all indices before restore
echo "Closing all indices..."
curl -X POST -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_all/_close"

# Restore snapshot
echo "Restoring snapshot ${SNAPSHOT_NAME}..."
curl -X POST -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/${SNAPSHOT_NAME}/_restore" -H 'Content-Type: application/json' -d '{
  "indices": "*",
  "ignore_unavailable": true,
  "include_global_state": true
}'

if [ $? -ne 0 ]; then
    echo "Failed to initiate restore!"
    exit 1
fi

echo "Restore initiated, waiting for completion..."

# Wait for restore to complete (check cluster health)
while true; do
    HEALTH=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_cluster/health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$HEALTH" == "green" ] || [ "$HEALTH" == "yellow" ]; then
        echo "Restore completed, cluster health is ${HEALTH}"
        break
    else
        echo "Restore in progress, cluster health is ${HEALTH:-red}"
        sleep 10
    fi
done

echo "Restore process completed at $(date)" ]; then
    echo "Creating snapshot repository..."
    curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}" -H 'Content-Type: application/json' -d '{
      "type": "fs",
      "settings": {
        "location": "/usr/share/elasticsearch/backup"
      }
    }'
    
    if [ $? -ne 0 ]; then
        echo "Failed to create snapshot repository!"
        exit 1
    fi
    
    echo "Snapshot repository created"
fi

# Create snapshot
echo "Creating snapshot ${SNAPSHOT_NAME}..."
curl -X PUT -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/${SNAPSHOT_NAME}" -H 'Content-Type: application/json' -d '{
  "indices": "*",
  "ignore_unavailable": true,
  "include_global_state": true
}'

if [ $? -ne 0 ]; then
    echo "Failed to create snapshot!"
    exit 1
fi

echo "Snapshot initiated, waiting for completion..."

# Check snapshot status until complete
while true; do
    STATUS=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/${SNAPSHOT_NAME}/_status" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$STATUS" == "SUCCESS" ]; then
        echo "Snapshot completed successfully"
        break
    elif [ "$STATUS" == "FAILED" ]; then
        echo "Snapshot failed!"
        exit 1
    else
        echo "Snapshot in progress, status: ${STATUS:-IN_PROGRESS}"
        sleep 10
    fi
done

# Delete old snapshots (keep only the most recent RETENTION_COUNT)
echo "Cleaning up old snapshots..."
OLD_SNAPSHOTS=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/_all" | grep -o '"snapshot":"[^"]*"' | cut -d'"' -f4 | sort | head -n -${RETENTION_COUNT})

for SNAPSHOT in $OLD_SNAPSHOTS; do
    echo "Deleting old snapshot: ${SNAPSHOT}"
    curl -X DELETE -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}/${SNAPSHOT}"
done

echo "Snapshot process completed at $(date)"
EOF

    # Script de restauración
    cat > ${SCRIPTS_DIR}/elasticsearch/backup/restore.sh << 'EOF'
#!/bin/bash
# Elasticsearch Restore Script

# Configuration
ES_HOST="elasticsearch.central-platform.svc.cluster.local"
ES_PORT="9200"
ES_USER="elastic"
ES_PASSWORD="${ELASTIC_PASSWORD}"
REPO_NAME="backup_repo"
SNAPSHOT_NAME="$1"

# Validate input
if [ -z "$SNAPSHOT_NAME" ]; then
    echo "Usage: $0 <snapshot_name>"
    exit 1
fi

echo "Starting Elasticsearch restore from snapshot ${SNAPSHOT_NAME} at $(date)"

# Check if repository exists
REPO_EXISTS=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "https://${ES_HOST}:${ES_PORT}/_snapshot/${REPO_NAME}" | grep -c "${REPO_NAME}")

if [ "$REPO_EXISTS" -eq 0
