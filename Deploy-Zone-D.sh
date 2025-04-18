#!/bin/bash

# Script de instalación y configuración de la Zona D (Mensajería)
# Para Ubuntu 24.04 LTS
# Plataforma Centralizada de Información

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir encabezados
print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE} $1 ${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

# Función para imprimir mensajes de éxito
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Función para imprimir mensajes de error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Función para imprimir mensajes de información
print_info() {
    echo -e "${YELLOW}➤ $1${NC}"
}

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

# Directorio base para la instalación
BASE_DIR="/opt/central-platform"
ZONE_D_DIR="${BASE_DIR}/zone-d"

print_header "Iniciando instalación de la Zona D (Mensajería)"

# Actualizar el sistema
print_info "Actualizando el sistema..."
apt update && apt upgrade -y
print_success "Sistema actualizado"

# Instalar dependencias necesarias
print_info "Instalando dependencias..."
apt install -y docker.io docker-compose curl jq net-tools
print_success "Dependencias instaladas"

# Crear estructura de directorios
print_info "Creando estructura de directorios..."
mkdir -p ${ZONE_D_DIR}/{redis,rabbitmq,kafka,config,scripts,logs}
mkdir -p ${ZONE_D_DIR}/redis/{data,conf}
mkdir -p ${ZONE_D_DIR}/rabbitmq/{data,conf,logs}
mkdir -p ${ZONE_D_DIR}/kafka/{data,config,logs}
print_success "Estructura de directorios creada"

# Crear archivo docker-compose.yml
print_info "Creando archivo docker-compose.yml..."
cat > ${ZONE_D_DIR}/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Redis (Caché y sistema de mensajería PubSub)
  redis:
    image: redis:7.0-alpine
    container_name: central-platform-redis
    command: redis-server /usr/local/etc/redis/redis.conf
    ports:
      - "6379:6379"
    volumes:
      - ./redis/data:/data
      - ./redis/conf/redis.conf:/usr/local/etc/redis/redis.conf
    environment:
      - TZ=UTC
    restart: unless-stopped
    networks:
      - messaging-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # RabbitMQ (Message Broker)
  rabbitmq:
    image: rabbitmq:3.11-management-alpine
    container_name: central-platform-rabbitmq
    ports:
      - "5672:5672"   # AMQP
      - "15672:15672" # Management UI
    volumes:
      - ./rabbitmq/data:/var/lib/rabbitmq
      - ./rabbitmq/conf/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
      - ./rabbitmq/conf/definitions.json:/etc/rabbitmq/definitions.json
      - ./rabbitmq/logs:/var/log/rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=admin
      - RABBITMQ_DEFAULT_PASS=admin_secure_password
    restart: unless-stopped
    networks:
      - messaging-network
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_running"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Kafka (Streaming de datos)
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    container_name: central-platform-zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    volumes:
      - ./kafka/data/zookeeper:/var/lib/zookeeper/data
      - ./kafka/logs/zookeeper:/var/lib/zookeeper/log
    networks:
      - messaging-network

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    container_name: central-platform-kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
    volumes:
      - ./kafka/data/kafka:/var/lib/kafka/data
      - ./kafka/config:/etc/kafka/config
      - ./kafka/logs/kafka:/var/lib/kafka/logs
    networks:
      - messaging-network

  # Kafka UI - Interfaz web para administrar Kafka
  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: central-platform-kafka-ui
    depends_on:
      - kafka
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: central-platform
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181
    networks:
      - messaging-network

networks:
  messaging-network:
    driver: bridge
EOF
print_success "Archivo docker-compose.yml creado"

# Crear configuración de Redis
print_info "Creando configuración de Redis..."
cat > ${ZONE_D_DIR}/redis/conf/redis.conf << 'EOF'
# Redis configuration for Central Platform
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""
databases 16

# Snapshots
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru

# Append only mode
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Security
requirepass SecureRedisPassword!123
EOF
print_success "Configuración de Redis creada"

# Crear configuración de RabbitMQ
print_info "Creando configuración de RabbitMQ..."
cat > ${ZONE_D_DIR}/rabbitmq/conf/rabbitmq.conf << 'EOF'
# RabbitMQ configuration for Central Platform
loopback_users.guest = false
listeners.tcp.default = 5672
management.tcp.port = 15672
management.load_definitions = /etc/rabbitmq/definitions.json

# Memory threshold at which RabbitMQ will start to flow control messages
vm_memory_high_watermark.relative = 0.6

# Disk free space threshold for flow control
disk_free_limit.relative = 2.0

# Maximum number of channels per connection
channel_max = 2047

# Logging
log.file.level = info

# Default user and virtual host
default_vhost = /
default_user = admin
default_pass = admin_secure_password
default_permissions.configure = .*
default_permissions.read = .*
default_permissions.write = .*

# Enable/disable specific plugins
management.load_definitions = /etc/rabbitmq/definitions.json
EOF

# Crear archivo de definiciones para RabbitMQ
cat > ${ZONE_D_DIR}/rabbitmq/conf/definitions.json << 'EOF'
{
  "rabbit_version": "3.11.0",
  "users": [
    {
      "name": "admin",
      "password_hash": "YfXPj0KlY1gKRgm7c9UHJ7GJQi0FytlW5GiGz1dlBQwQxH8m",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": "administrator"
    },
    {
      "name": "central-platform",
      "password_hash": "YfXPj0KlY1gKRgm7c9UHJ7GJQi0FytlW5GiGz1dlBQwQxH8m",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": "management"
    }
  ],
  "vhosts": [
    {
      "name": "/"
    },
    {
      "name": "central-platform"
    }
  ],
  "permissions": [
    {
      "user": "admin",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "admin",
      "vhost": "central-platform",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "central-platform",
      "vhost": "central-platform",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "parameters": [],
  "policies": [
    {
      "vhost": "central-platform",
      "name": "ha-all",
      "pattern": ".*",
      "apply-to": "all",
      "definition": {
        "ha-mode": "all",
        "ha-sync-mode": "automatic"
      },
      "priority": 0
    }
  ],
  "queues": [
    {
      "name": "device-telemetry",
      "vhost": "central-platform",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-queue-type": "classic"
      }
    },
    {
      "name": "device-commands",
      "vhost": "central-platform",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-queue-type": "classic"
      }
    },
    {
      "name": "alerts",
      "vhost": "central-platform",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-queue-type": "classic"
      }
    },
    {
      "name": "notifications",
      "vhost": "central-platform",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-queue-type": "classic"
      }
    }
  ],
  "exchanges": [
    {
      "name": "device-events",
      "vhost": "central-platform",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    },
    {
      "name": "system-events",
      "vhost": "central-platform",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    }
  ],
  "bindings": [
    {
      "source": "device-events",
      "vhost": "central-platform",
      "destination": "device-telemetry",
      "destination_type": "queue",
      "routing_key": "device.telemetry.#",
      "arguments": {}
    },
    {
      "source": "device-events",
      "vhost": "central-platform",
      "destination": "device-commands",
      "destination_type": "queue",
      "routing_key": "device.command.#",
      "arguments": {}
    },
    {
      "source": "system-events",
      "vhost": "central-platform",
      "destination": "alerts",
      "destination_type": "queue",
      "routing_key": "system.alert.#",
      "arguments": {}
    },
    {
      "source": "system-events",
      "vhost": "central-platform",
      "destination": "notifications",
      "destination_type": "queue",
      "routing_key": "system.notification.#",
      "arguments": {}
    }
  ]
}
EOF
print_success "Configuración de RabbitMQ creada"

# Crear configuración de Kafka
print_info "Creando configuración de Kafka..."
mkdir -p ${ZONE_D_DIR}/kafka/config

cat > ${ZONE_D_DIR}/kafka/config/server.properties << 'EOF'
# Kafka configuration for Central Platform
broker.id=1
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/var/lib/kafka/data
num.partitions=8
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=zookeeper:2181
zookeeper.connection.timeout.ms=18000
group.initial.rebalance.delay.ms=0
EOF

# Crear scripts de inicialización para tópicos de Kafka
cat > ${ZONE_D_DIR}/scripts/init-kafka-topics.sh << 'EOF'
#!/bin/bash

# Script para crear tópicos en Kafka
echo "Creando tópicos en Kafka..."
sleep 10 # Esperar a que Kafka esté listo

# Función para crear un tópico si no existe
create_topic() {
    TOPIC_NAME=$1
    PARTITIONS=$2
    REPLICAS=$3
    RETENTION=$4

    echo "Creando tópico: $TOPIC_NAME"
    docker exec central-platform-kafka kafka-topics --create \
        --bootstrap-server localhost:9092 \
        --topic $TOPIC_NAME \
        --partitions $PARTITIONS \
        --replication-factor $REPLICAS \
        --config retention.ms=$RETENTION \
        --if-not-exists
}

# Crear tópicos para telemetría de dispositivos
create_topic "device-telemetry" 8 1 604800000  # 7 días
create_topic "device-commands" 4 1 86400000    # 1 día
create_topic "device-status" 4 1 604800000     # 7 días

# Crear tópicos para alertas y notificaciones
create_topic "system-alerts" 4 1 2592000000    # 30 días
create_topic "system-notifications" 4 1 604800000  # 7 días

# Crear tópicos para analíticas
create_topic "analytics-input" 8 1 604800000   # 7 días
create_topic "analytics-output" 4 1 604800000  # 7 días

echo "Tópicos Kafka creados correctamente."
EOF

chmod +x ${ZONE_D_DIR}/scripts/init-kafka-topics.sh
print_success "Configuración de Kafka creada"

# Crear scripts de inicio y parada
print_info "Creando scripts de inicio y parada..."
cat > ${ZONE_D_DIR}/scripts/start-services.sh << 'EOF'
#!/bin/bash

# Iniciar servicios de la Zona D
ZONE_D_DIR="/opt/central-platform/zone-d"
cd $ZONE_D_DIR

echo "Iniciando servicios de la Zona D (Mensajería)..."
docker-compose up -d

echo "Esperando a que los servicios estén disponibles..."
sleep 10

# Inicializar tópicos de Kafka
${ZONE_D_DIR}/scripts/init-kafka-topics.sh

echo "Servicios de mensajería iniciados correctamente."
echo "URLs de acceso:"
echo " - Redis: localhost:6379"
echo " - RabbitMQ Management: http://localhost:15672 (admin/admin_secure_password)"
echo " - Kafka: localhost:9092 (interno), localhost:29092 (externo)"
echo " - Kafka UI: http://localhost:8080"
EOF

cat > ${ZONE_D_DIR}/scripts/stop-services.sh << 'EOF'
#!/bin/bash

# Detener servicios de la Zona D
ZONE_D_DIR="/opt/central-platform/zone-d"
cd $ZONE_D_DIR

echo "Deteniendo servicios de la Zona D (Mensajería)..."
docker-compose down

echo "Servicios de mensajería detenidos correctamente."
EOF

# Dar permisos de ejecución a los scripts
chmod +x ${ZONE_D_DIR}/scripts/start-services.sh
chmod +x ${ZONE_D_DIR}/scripts/stop-services.sh
print_success "Scripts de inicio y parada creados"

# Crear servicio systemd
print_info "Creando servicio systemd..."
cat > /etc/systemd/system/central-platform-messaging.service << EOF
[Unit]
Description=Central Platform Messaging Services (Zone D)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${ZONE_D_DIR}
ExecStart=${ZONE_D_DIR}/scripts/start-services.sh
ExecStop=${ZONE_D_DIR}/scripts/stop-services.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd
systemctl daemon-reload
print_success "Servicio systemd creado"

# Configurar permisos
print_info "Configurando permisos..."
chown -R 1000:1000 ${ZONE_D_DIR}/redis/data
chown -R 999:999 ${ZONE_D_DIR}/rabbitmq/data
chown -R 999:999 ${ZONE_D_DIR}/rabbitmq/logs
chmod -R 755 ${ZONE_D_DIR}/scripts
print_success "Permisos configurados"

# Crear archivo README con instrucciones
print_info "Creando documentación..."
cat > ${ZONE_D_DIR}/README.md << 'EOF'
# Zona D - Mensajería de la Plataforma Centralizada

Esta zona implementa los servicios de mensajería para la Plataforma Centralizada de Información.

## Componentes

* **Redis**: Caché y sistema de Pub/Sub para mensajes en tiempo real
* **RabbitMQ**: Message Broker para comunicación asíncrona entre servicios
* **Kafka**: Plataforma de streaming para procesamiento de datos a gran escala

## Inicio y Parada

* Para iniciar los servicios:
* ** sudo systemctl start central-platform-messaging
* Para detener los servicios:
* ** sudo systemctl stop central-platform-messaging
* Para habilitar el inicio automático con el sistema:
* ** sudo systemctl enable central-platform-messaging

## Administración

* RabbitMQ Management UI: http://localhost:15672
  * Usuario: admin
  * Contraseña: admin_secure_password

* Kafka UI: http://localhost:8080

## Conexión desde Servicios

### Redis
* Host: redis
* Puerto: 6379
* Contraseña: SecureRedisPassword!123

### RabbitMQ
* Host: rabbitmq
* Puerto: 5672
* Usuario: central-platform
* Contraseña: admin_secure_password
* Virtual Host: central-platform

### Kafka
* Bootstrap Servers: 
  * Interno: kafka:9092
  * Externo: localhost:29092

## Tópicos y Colas Predefinidas

### RabbitMQ

* **device-telemetry**: Telemetría de dispositivos IoT
* **device-commands**: Comandos para dispositivos
* **alerts**: Alertas del sistema
* **notifications**: Notificaciones para usuarios

### Kafka

* **device-telemetry**: Flujo de datos de telemetría
* **device-commands**: Comandos para dispositivos
* **device-status**: Estado de dispositivos
* **system-alerts**: Alertas del sistema
* **system-notifications**: Notificaciones del sistema
* **analytics-input**: Datos de entrada para análisis
* **analytics-output**: Resultados de análisis

## Mantenimiento

Los datos persistentes se almacenan en:
* Redis: /opt/central-platform/zone-d/redis/data
* RabbitMQ: /opt/central-platform/zone-d/rabbitmq/data
* Kafka: /opt/central-platform/zone-d/kafka/data

## Respaldo

Se recomienda realizar respaldos periódicos de los directorios de datos.
EOF
print_success "Documentación creada"

# Finalizar instalación
print_header "Instalación de la Zona D (Mensajería) completada"
print_info "Para iniciar los servicios, ejecute:"
echo "  sudo systemctl start central-platform-messaging"
print_info "Para configurar el inicio automático con el sistema, ejecute:"
echo "  sudo systemctl enable central-platform-messaging"
print_info "Documentación disponible en:"
echo "  ${ZONE_D_DIR}/README.md"

exit 0
