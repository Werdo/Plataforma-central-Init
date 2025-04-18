#!/bin/bash
#
# Script de Implementación para la Zona C (IoT Gateways)
# Plataforma Centralizada de Información
# Para Ubuntu 24.04 LTS
#
# Este script crea la estructura de directorios y archivos necesarios para la Zona C,
# que incluye el gateway IoT principal y el adaptador M2M.
#

# Colores para los mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes de error y salir
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Función para mostrar mensajes informativos
info() {
    echo -e "${BLUE}Info: $1${NC}"
}

# Función para mostrar mensajes de éxito
success() {
    echo -e "${GREEN}Éxito: $1${NC}"
}

# Función para mostrar mensajes de advertencia
warning() {
    echo -e "${YELLOW}Advertencia: $1${NC}"
}

# Directorio base para la implementación
BASE_DIR="$HOME/central-platform"
GATEWAYS_DIR="$BASE_DIR/gateways"

# Verificar si los directorios ya existen
if [ -d "$GATEWAYS_DIR" ]; then
    warning "El directorio $GATEWAYS_DIR ya existe. ¿Desea continuar y sobrescribir archivos existentes? (s/n)"
    read -r response
    if [[ "$response" != "s" && "$response" != "S" ]]; then
        info "Operación cancelada por el usuario."
        exit 0
    fi
fi

# Actualizar el sistema e instalar dependencias
info "Actualizando sistema e instalando dependencias necesarias..."
sudo apt update || error_exit "No se pudo actualizar la lista de paquetes"
sudo apt install -y curl wget unzip git nodejs npm docker.io docker-compose jq || error_exit "No se pudieron instalar las dependencias"

# Verificar si Docker está en ejecución
if ! sudo systemctl is-active --quiet docker; then
    info "Iniciando servicio Docker..."
    sudo systemctl start docker || error_exit "No se pudo iniciar Docker"
fi

# Añadir usuario actual al grupo docker
sudo usermod -aG docker "$(whoami)"
info "Usuario $(whoami) añadido al grupo docker. Es posible que necesite cerrar sesión y volver a iniciarla para que los cambios surtan efecto."

# Crear estructura de directorios
info "Creando estructura de directorios para IoT Gateways..."
mkdir -p "$GATEWAYS_DIR/iot-gateway/src/"{config,clients,models,protocols/{mqtt,tcp,http},services,utils,handlers,middleware,routes}
mkdir -p "$GATEWAYS_DIR/iot-gateway/"{tests/{integration,unit},tools/{simulator,monitor}}
mkdir -p "$GATEWAYS_DIR/m2m-adapter/src/"{config,adapters,models,services,utils,routes}
mkdir -p "$GATEWAYS_DIR/m2m-adapter/tests/"{integration,unit}

success "Estructura de directorios creada correctamente."

# Navegando al directorio de gateways
cd "$GATEWAYS_DIR" || error_exit "No se pudo navegar al directorio $GATEWAYS_DIR"

# Creación de archivos para IoT Gateway
info "Creando estructura base para IoT Gateway..."
info "Creando archivos para IoT Gateway..."

# Archivo gateway.js
cat > "$GATEWAYS_DIR/iot-gateway/src/gateway.js" << 'EOF

# Archivo utils/retry.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/utils/retry.js" << 'EOF'
// src/utils/retry.js
const logger = require('./logger');

/**
 * Ejecuta una función con reintento exponencial
 * @param {Function} fn - Función a ejecutar
 * @param {number} maxRetries - Número máximo de reintentos
 * @param {number} initialDelayMs - Retraso inicial en milisegundos
 * @returns {Promise<any>} - Resultado de la función
 */
async function exponentialBackoff(fn, maxRetries = 3, initialDelayMs = 1000) {
  let retries = 0;
  let delay = initialDelayMs;
  
  while (true) {
    try {
      return await fn();
    } catch (error) {
      retries++;
      
      if (retries > maxRetries) {
        logger.error(`Failed after ${maxRetries} retries:`, error);
        throw error;
      }
      
      logger.warn(`Retry ${retries}/${maxRetries} after ${delay}ms`, { error: error.message });
      
      // Esperar el tiempo de retraso
      await new Promise(resolve => setTimeout(resolve, delay));
      
      // Aumentar el retraso exponencialmente
      delay *= 2;
    }
  }
}

module.exports = {
  exponentialBackoff
};
EOF

# Archivo utils/credentials.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/utils/credentials.js" << 'EOF'
// src/utils/credentials.js
const logger = require('./logger');
const fs = require('fs').promises;
const path = require('path');

// Directorio para credenciales
const CREDENTIALS_DIR = process.env.CREDENTIALS_DIR || path.join(process.cwd(), 'credentials');

/**
 * Obtiene una credencial del almacén
 * @param {string} credentialId - ID de la credencial
 * @returns {Promise<Object|null>} - Credencial o null si no se encuentra
 */
async function getCredential(credentialId) {
  try {
    // Verificar si el directorio existe
    try {
      await fs.access(CREDENTIALS_DIR);
    } catch (error) {
      await fs.mkdir(CREDENTIALS_DIR, { recursive: true });
      logger.info(`Created credentials directory: ${CREDENTIALS_DIR}`);
    }
    
    // Ruta del archivo de credencial
    const credentialFile = path.join(CREDENTIALS_DIR, `${credentialId}.json`);
    
    try {
      // Intentar leer el archivo
      const data = await fs.readFile(credentialFile, 'utf8');
      return JSON.parse(data);
    } catch (readError) {
      // Si el archivo no existe, intentar usar variables de entorno
      if (readError.code === 'ENOENT') {
        logger.warn(`Credential file ${credentialId}.json not found, trying environment variables`);
        
        // Buscar credenciales en variables de entorno
        const username = process.env[`${credentialId.toUpperCase()}_USERNAME`];
        const password = process.env[`${credentialId.toUpperCase()}_PASSWORD`];
        
        if (username && password) {
          logger.info(`Using environment variables for ${credentialId}`);
          
          // Guardar credenciales en archivo para uso futuro
          const credential = { username, password };
          await fs.writeFile(credentialFile, JSON.stringify(credential, null, 2));
          
          return credential;
        }
        
        logger.error(`No credentials found for ${credentialId}`);
        return null;
      }
      
      throw readError;
    }
  } catch (error) {
    logger.error(`Error getting credential ${credentialId}:`, error);
    return null;
  }
}

/**
 * Guarda una credencial en el almacén
 * @param {string} credentialId - ID de la credencial
 * @param {Object} credential - Credencial a guardar
 * @returns {Promise<boolean>} - true si se guardó correctamente
 */
async function saveCredential(credentialId, credential) {
  try {
    // Verificar si el directorio existe
    try {
      await fs.access(CREDENTIALS_DIR);
    } catch (error) {
      await fs.mkdir(CREDENTIALS_DIR, { recursive: true });
      logger.info(`Created credentials directory: ${CREDENTIALS_DIR}`);
    }
    
    // Ruta del archivo de credencial
    const credentialFile = path.join(CREDENTIALS_DIR, `${credentialId}.json`);
    
    // Guardar credencial
    await fs.writeFile(credentialFile, JSON.stringify(credential, null, 2));
    logger.info(`Credential ${credentialId} saved successfully`);
    
    return true;
  } catch (error) {
    logger.error(`Error saving credential ${credentialId}:`, error);
    return false;
  }
}

module.exports = {
  getCredential,
  saveCredential
};
EOF

# Archivo services/mappingService.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/services/mappingService.js" << 'EOF'
// src/services/mappingService.js
const logger = require('../utils/logger');

/**
 * Mapea un dispositivo de la API M2M al formato local
 * @param {Object} m2mDevice - Dispositivo de la API M2M
 * @returns {Object} - Dispositivo en formato local
 */
function mapM2MDeviceToLocal(m2mDevice) {
  try {
    // Validar que el dispositivo tenga un ID
    if (!m2mDevice.deviceId && !m2mDevice.id) {
      throw new Error('Device must have an id or deviceId');
    }
    
    // Crear objeto de dispositivo para nuestro formato
    const device = {
      deviceId: m2mDevice.deviceId || m2mDevice.id,
      name: m2mDevice.name || m2mDevice.deviceId || m2mDevice.id,
      type: m2mDevice.type || 'unknown',
      status: m2mDevice.status || 'unknown',
      model: m2mDevice.model,
      manufacturer: m2mDevice.manufacturer,
      firmware: m2mDevice.firmware,
      lastActive: m2mDevice.lastActive || m2mDevice.lastSeen || null,
      
      // Metadatos adicionales
      metadata: {
        source: 'm2m-api',
        originalId: m2mDevice.id || m2mDevice.deviceId,
        attributes: m2mDevice.attributes || m2mDevice.metadata || {},
        syncDate: new Date().toISOString()
      }
    };
    
    // Mapear ubicación si existe
    if (m2mDevice.location) {
      // Si la ubicación viene como objeto con lat/lng
      if (m2mDevice.location.lat && m2mDevice.location.lng) {
        device.location = {
          type: 'Point',
          coordinates: [m2mDevice.location.lng, m2mDevice.location.lat]
        };
      }
      // Si la ubicación viene como array de coordenadas [lng, lat]
      else if (Array.isArray(m2mDevice.location) && m2mDevice.location.length >= 2) {
        device.location = {
          type: 'Point',
          coordinates: [m2mDevice.location[0], m2mDevice.location[1]]
        };
      }
    }
    
    // Mapear campos específicos del proveedor si existen
    if (m2mDevice.simNumber) {
      device.metadata.simNumber = m2mDevice.simNumber;
    }
    
    if (m2mDevice.imei) {
      device.metadata.imei = m2mDevice.imei;
    }
    
    if (m2mDevice.serialNumber) {
      device.metadata.serialNumber = m2mDevice.serialNumber;
    }
    
    return device;
  } catch (error) {
    logger.error('Error mapping M2M device:', error);
    throw new Error(`Error mapping device: ${error.message}`);
  }
}

module.exports = {
  mapM2MDeviceToLocal
};
EOF

# Archivo models/device.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/models/device.js" << 'EOF'
// src/models/device.js
const mongoose = require('mongoose');

// Esquema para la ubicación (GeoJSON Point)
const locationSchema = new mongoose.Schema({
  type: {
    type: String,
    enum: ['Point'],
    default: 'Point'
  },
  coordinates: {
    type: [Number],
    required: true
  }
});

// Esquema para dispositivos
const deviceSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  name: {
    type: String,
    required: true
  },
  type: {
    type: String,
    required: true,
    index: true
  },
  status: {
    type: String,
    default: 'unknown',
    index: true
  },
  model: String,
  manufacturer: String,
  firmware: String,
  lastActive: Date,
  location: {
    type: locationSchema,
    index: '2dsphere'
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true,
  versionKey: false
});

// Índices
deviceSchema.index({ deviceId: 1 }, { unique: true });
deviceSchema.index({ type: 1 });
deviceSchema.index({ status: 1 });
deviceSchema.index({ 'location.coordinates': '2dsphere' });

const Device = mongoose.model('Device', deviceSchema);

module.exports = Device;
EOF

# Archivo routes/devices.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/routes/devices.js" << 'EOF'
// src/routes/devices.js
const express = require('express');
const router = express.Router();
const m2mApiAdapter = require('../adapters/m2mApiAdapter');
const Device = require('../models/device');
const logger = require('../utils/logger');

/**
 * @route GET /api/devices
 * @description Obtener todos los dispositivos
 * @access Public
 */
router.get('/', async (req, res) => {
  try {
    const { skip, limit, search, type } = req.query;
    
    // Construir filtros
    const filter = {};
    
    if (search) {
      filter.$or = [
        { deviceId: { $regex: search, $options: 'i' } },
        { name: { $regex: search, $options: 'i' } }
      ];
    }
    
    if (type) {
      filter.type = type;
    }
    
    // Obtener dispositivos paginados
    const devices = await Device.find(filter)
      .skip(parseInt(skip) || 0)
      .limit(parseInt(limit) || 100)
      .sort({ updatedAt: -1 });
    
    // Obtener cuenta total
    const total = await Device.countDocuments(filter);
    
    res.json({
      devices,
      total,
      skip: parseInt(skip) || 0,
      limit: parseInt(limit) || 100
    });
  } catch (error) {
    logger.error('Error getting devices:', error);
    res.status(500).json({
      message: 'Error getting devices',
      error: error.message
    });
  }
});

/**
 * @route GET /api/devices/:deviceId
 * @description Obtener un dispositivo por ID
 * @access Public
 */
router.get('/:deviceId', async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    // Buscar en base de datos local
    const device = await Device.findOne({ deviceId });
    
    if (!device) {
      return res.status(404).json({
        message: `Device ${deviceId} not found`
      });
    }
    
    res.json(device);
  } catch (error) {
    logger.error(`Error getting device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error getting device',
      error: error.message
    });
  }
});

/**
 * @route GET /api/devices/:deviceId/positions
 * @description Obtener posiciones de un dispositivo
 * @access Public
 */
router.get('/:deviceId/positions', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { from, to, limit } = req.query;
    
    // Verificar que el dispositivo existe
    const device = await Device.findOne({ deviceId });
    
    if (!device) {
      return res.status(404).json({
        message: `Device ${deviceId} not found`
      });
    }
    
    // Obtener posiciones desde la API M2M
    const positions = await m2mApiAdapter.getDevicePositions(
      deviceId,
      from,
      to,
      parseInt(limit) || 100
    );
    
    res.json(positions);
  } catch (error) {
    logger.error(`Error getting positions for device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error getting device positions',
      error: error.message
    });
  }
});

/**
 * @route GET /api/devices/:deviceId/last-position
 * @description Obtener última posición de un dispositivo
 * @access Public
 */
router.get('/:deviceId/last-position', async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    // Verificar que el dispositivo existe
    const device = await Device.findOne({ deviceId });
    
    if (!device) {
      return res.status(404).json({
        message: `Device ${deviceId} not found`
      });
    }
    
    // Si el dispositivo tiene una ubicación local, devolverla
    if (device.location && device.location.coordinates) {
      return res.json({
        deviceId,
        location: {
          lng: device.location.coordinates[0],
          lat: device.location.coordinates[1]
        },
        timestamp: device.updatedAt,
        source: 'local'
      });
    }
    
    // Si no hay ubicación local, intentar obtenerla de la API M2M
    const position = await m2mApiAdapter.getDeviceLastPosition(deviceId);
    
    res.json(position);
  } catch (error) {
    logger.error(`Error getting last position for device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error getting device last position',
      error: error.message
    });
  }
});

/**
 * @route GET /api/devices/:deviceId/status
 * @description Verificar estado de un dispositivo
 * @access Public
 */
router.get('/:deviceId/status', async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    // Verificar que el dispositivo existe
    const device = await Device.findOne({ deviceId });
    
    if (!device) {
      return res.status(404).json({
        message: `Device ${deviceId} not found`
      });
    }
    
    // Verificar si el dispositivo está conectado usando la API M2M
    const status = await m2mApiAdapter.isDeviceAlive(deviceId);
    
    // Actualizar estado en la base de datos local
    await Device.updateOne(
      { deviceId },
      {
        $set: {
          status: status.isAlive ? 'online' : 'offline',
          lastActive: new Date()
        }
      }
    );
    
    res.json({
      deviceId,
      status: status.isAlive ? 'online' : 'offline',
      lastCheck: new Date(),
      details: status
    });
  } catch (error) {
    logger.error(`Error checking status for device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error checking device status',
      error: error.message
    });
  }
});

module.exports = router;
EOF

# Archivo routes/telemetry.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/routes/telemetry.js" << 'EOF'
// src/routes/telemetry.js
const express = require('express');
const router = express.Router();
const logger = require('../utils/logger');

/**
 * @route GET /api/telemetry/:deviceId
 * @description Obtener telemetría de un dispositivo
 * @access Public
 */
router.get('/:deviceId', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { from, to, limit } = req.query;
    
    // Esta implementación es un placeholder
    // En una implementación real, se obtendría la telemetría de una base de datos
    res.json({
      deviceId,
      message: "Telemetry data would be returned here",
      params: {
        from: from || 'not specified',
        to: to || 'not specified',
        limit: limit || '100'
      }
    });
  } catch (error) {
    logger.error(`Error getting telemetry for device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error getting telemetry data',
      error: error.message
    });
  }
});

/**
 * @route POST /api/telemetry/:deviceId
 * @description Recibir telemetría de un dispositivo
 * @access Public
 */
router.post('/:deviceId', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const telemetryData = req.body;
    
    logger.info(`Received telemetry from ${deviceId}:`, { data: telemetryData });
    
    // Esta implementación es un placeholder
    // En una implementación real, se almacenaría la telemetría en una base de datos
    
    res.status(201).json({
      deviceId,
      message: "Telemetry data received",
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error(`Error processing telemetry for device ${req.params.deviceId}:`, error);
    res.status(500).json({
      message: 'Error processing telemetry data',
      error: error.message
    });
  }
});

module.exports = router;
EOF

# Archivo routes/sync.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/routes/sync.js" << 'EOF'
// src/routes/sync.js
const express = require('express');
const router = express.Router();
const { synchronizeDevices, getSyncStatus } = require('../services/synchronizationService');
const logger = require('../utils/logger');

/**
 * @route GET /api/sync/status
 * @description Obtener estado de sincronización
 * @access Public
 */
router.get('/status', async (req, res) => {
  try {
    const status = getSyncStatus();
    res.json(status);
  } catch (error) {
    logger.error('Error getting sync status:', error);
    res.status(500).json({
      message: 'Error getting synchronization status',
      error: error.message
    });
  }
});

/**
 * @route POST /api/sync
 * @description Iniciar sincronización manual
 * @access Public
 */
router.post('/', async (req, res) => {
  try {
    // Iniciar sincronización asíncrona
    const syncPromise = synchronizeDevices();
    
    // Responder inmediatamente que la sincronización ha sido iniciada
    res.json({
      message: 'Synchronization started',
      timestamp: new Date().toISOString()
    });
    
    // Continuar con la sincronización en segundo plano
    syncPromise
      .then(result => {
        logger.info('Manual synchronization completed:', result);
      })
      .catch(error => {
        logger.error('Manual synchronization failed:', error);
      });
  } catch (error) {
    logger.error('Error starting synchronization:', error);
    res.status(500).json({
      message: 'Error starting synchronization',
      error: error.message
    });
  }
});

module.exports = router;
EOF

# Archivo package.json para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/package.json" << 'EOF'
{
  "name": "central-platform-m2m-adapter",
  "version": "1.0.0",
  "description": "M2M API Adapter for Central Platform",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js",
    "test": "jest",
    "lint": "eslint --ext .js src/"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.3.5",
    "mongoose": "^7.0.3",
    "dotenv": "^16.0.3",
    "winston": "^3.8.2",
    "node-cache": "^5.1.2",
    "cron": "^2.3.0"
  },
  "devDependencies": {
    "jest": "^29.5.0",
    "nodemon": "^2.0.22",
    "eslint": "^8.38.0",
    "eslint-config-prettier": "^8.8.0",
    "eslint-plugin-prettier": "^4.2.1",
    "prettier": "^2.8.7",
    "supertest": "^6.3.3"
  }
}
EOF

# Archivo Dockerfile para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/Dockerfile" << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copiar package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm ci --only=production

# Copiar código fuente
COPY . .

# Exponer puerto
EXPOSE 8082

# Comando para iniciar la aplicación
CMD ["node", "src/server.js"]
EOF

# Archivo .env para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/.env" << 'EOF'
# Configuración general
NODE_ENV=development
PORT=8082
LOG_LEVEL=info
VERSION=1.0.0

# MongoDB
MONGODB_URI=mongodb://mongodb:27017/central_platform
MONGODB_POOL_SIZE=10

# API M2M
M2M_API_URL=https://api.m2msystemsource.com/v1
M2M_API_CREDENTIAL_ID=m2m-api-creds

# Sincronización
SYNC_ENABLED=true
SYNC_INTERVAL=60
SYNC_ON_START=true
SYNC_BATCH_SIZE=1000

# Caché
CACHE_TTL=300
CACHE_CHECK_PERIOD=60
EOF

# Archivo docker-compose.yml para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  m2m-adapter:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8082:8082"
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
      - ./credentials:/app/credentials
    depends_on:
      - mongodb
    restart: unless-stopped
    networks:
      - central-platform-network

  # MongoDB (compartido con otros servicios)
  mongodb:
    image: mongo:5.0
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    networks:
      - central-platform-network

volumes:
  mongodb_data:

networks:
  central-platform-network:
    driver: bridge
EOF

# Crear docker-compose.yml principal para toda la Zona C
cat > "$GATEWAYS_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # Gateway IoT
  iot-gateway:
    build:
      context: ./iot-gateway
      dockerfile: Dockerfile
    ports:
      - "8080:8080"  # TCP
      - "8081:8081"  # HTTP
      - "1883:1883"  # MQTT
    env_file:
      - ./iot-gateway/.env
    volumes:
      - ./iot-gateway/logs:/app/logs
    depends_on:
      - mongodb
      - redis
    restart: unless-stopped
    networks:
      - central-platform-network

  # Adaptador M2M
  m2m-adapter:
    build:
      context: ./m2m-adapter
      dockerfile: Dockerfile
    ports:
      - "8082:8082"
    env_file:
      - ./m2m-adapter/.env
    volumes:
      - ./m2m-adapter/logs:/app/logs
      - ./m2m-adapter/credentials:/app/credentials
    depends_on:
      - mongodb
    restart: unless-stopped
    networks:
      - central-platform-network

  # HAProxy para balanceo de carga de gateways
  haproxy:
    image: haproxy:2.4-alpine
    ports:
      - "9080:9080"  # Puerto público para TCP
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - iot-gateway
    restart: unless-stopped
    networks:
      - central-platform-network

  # Servicios compartidos
  mongodb:
    image: mongo:5.0
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    restart: unless-stopped
    networks:
      - central-platform-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped
    networks:
      - central-platform-network

volumes:
  mongodb_data:
  redis_data:

networks:
  central-platform-network:
    driver: bridge
EOF

# Crear configuración de HAProxy
mkdir -p "$GATEWAYS_DIR/haproxy"
cat > "$GATEWAYS_DIR/haproxy/haproxy.cfg" << 'EOF'
global
    log stdout format raw local0 info
    maxconn 4096
    user haproxy
    group haproxy

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend tcp_devices
    bind *:9080
    mode tcp
    default_backend tcp_gateway

backend tcp_gateway
    mode tcp
    balance roundrobin
    option tcp-check
    server gateway1 iot-gateway:8080 check
    # Para escalar horizontalmente, añadir más servidores:
    # server gateway2 iot-gateway-2:8080 check
    # server gateway3 iot-gateway-3:8080 check
EOF

# Crea el script de inicio
cat > "$GATEWAYS_DIR/start-gateways.sh" << 'EOF'
#!/bin/bash

# Colores para los mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verifica si Docker está en ejecución
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Docker no está en ejecución. Por favor, inicia Docker y vuelve a intentarlo.${NC}"
    exit 1
fi

# Verifica si docker-compose está instalado
if ! command -v docker-compose >/dev/null 2>&1; then
    echo -e "${YELLOW}docker-compose no está instalado, se intentará usar el plugin docker compose...${NC}"
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Crear directorios de logs si no existen
mkdir -p iot-gateway/logs
mkdir -p m2m-adapter/logs
mkdir -p m2m-adapter/credentials

echo -e "${BLUE}Iniciando servicios de la Zona C (IoT Gateways)...${NC}"

# Iniciar los servicios con docker-compose
$DOCKER_COMPOSE up -d

# Verificar si los servicios se iniciaron correctamente
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Los servicios de la Zona C se han iniciado correctamente.${NC}"
    echo -e "${BLUE}Puedes verificar el estado de los servicios con:${NC}"
    echo -e "  $DOCKER_COMPOSE ps"
    echo -e "${BLUE}Para ver los logs de los servicios:${NC}"
    echo -e "  $DOCKER_COMPOSE logs -f [servicio]"
    echo -e "${BLUE}Para detener los servicios:${NC}"
    echo -e "  $DOCKER_COMPOSE down"
    echo -e "${BLUE}Servicios disponibles:${NC}"
    echo -e "  - IoT Gateway TCP: localhost:8080"
    echo -e "  - IoT Gateway HTTP: localhost:8081"
    echo -e "  - M2M Adapter API: localhost:8082"
    echo -e "  - HAProxy TCP Balance: localhost:9080"
else
    echo -e "${RED}Error al iniciar los servicios.${NC}"
    exit 1
fi

# Dar permisos de ejecución al script
chmod +x start-gateways.sh
EOF

# Dar permisos de ejecución al script de inicio
chmod +x "$GATEWAYS_DIR/start-gateways.sh"

# Crear un script de simulación básico para pruebas
mkdir -p "$GATEWAYS_DIR/iot-gateway/tools/simulator"
cat > "$GATEWAYS_DIR/iot-gateway/tools/simulator/deviceSimulator.js" << 'EOF'
// deviceSimulator.js
const net = require('net');
const readline = require('readline');

// Configuración del simulador
const DEFAULT_CONFIG = {
  host: 'localhost',
  port: 8080,
  deviceId: `device-${Math.floor(Math.random() * 10000)}`,
  interval: 5000 // ms
};

// Parsear argumentos de la línea de comandos
const args = process.argv.slice(2);
const config = { ...DEFAULT_CONFIG };

for (let i = 0; i < args.length; i += 2) {
  const key = args[i].replace('--', '');
  const value = args[i + 1];
  
  if (key === 'interval' || key === 'port') {
    config[key] = parseInt(value, 10);
  } else {
    config[key] = value;
  }
}

// Crear interfaz de línea de comandos
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Variables globales
let client = null;
let interval = null;
let connected = false;
let authenticated = false;

// Conexión al servidor
function connect() {
  console.log(`Connecting to ${config.host}:${config.port}...`);
  
  // Crear socket TCP
  client = new net.Socket();
  
  // Configurar manejadores de eventos
  client.on('connect', () => {
    console.log(`Connected to ${config.host}:${config.port}`);
    connected = true;
    
    // Enviar mensaje de autenticación
    const authMessage = `AUTH:deviceId:${config.deviceId};key:simulator-key`;
    client.write(authMessage + '\n');
    console.log(`> ${authMessage}`);
  });
  
  client.on('data', (data) => {
    const message = data.toString().trim();
    console.log(`< ${message}`);
    
    // Procesar respuesta del servidor
    if (!authenticated && message.includes('success')) {
      authenticated = true;
      console.log('Authentication successful!');
      
      // Iniciar envío periódico de telemetría
      startTelemetry();
      
      // Mostrar menú de comandos
      showMenu();
    }
  });
  
  client.on('close', () => {
    console.log('Connection closed');
    connected = false;
    authenticated = false;
    
    // Detener envío de telemetría
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
    
    // Intentar reconectar después de 5 segundos
    setTimeout(() => {
      if (!connected) {
        connect();
      }
    }, 5000);
  });
  
  client.on('error', (err) => {
    console.error('Connection error:', err.message);
  });
  
  // Conectar al servidor
  client.connect(config.port, config.host);
}

// Iniciar envío periódico de telemetría
function startTelemetry() {
  if (interval) {
    clearInterval(interval);
  }
  
  interval = setInterval(() => {
    if (connected && authenticated) {
      const telemetry = generateTelemetry();
      client.write(telemetry + '\n');
      console.log(`> ${telemetry}`);
    }
  }, config.interval);
  
  console.log(`Sending telemetry every ${config.interval}ms`);
}

// Generar datos de telemetría aleatorios
function generateTelemetry() {
  const now = Date.now();
  const temperature = (15 + Math.random() * 15).toFixed(1);
  const humidity = (30 + Math.random() * 50).toFixed(1);
  const voltage = (11 + Math.random() * 3).toFixed(2);
  
  // Generar ubicación aleatoria (Ciudad de México como centro)
  const lat = 19.4326 + (Math.random() - 0.5) * 0.1;
  const lng = -99.1332 + (Math.random() - 0.5) * 0.1;
  
  return `DATA:TIME:${now};LOC:${lng},${lat};TEMP:${temperature};HUM:${humidity};VOLT:${voltage}`;
}

// Mostrar menú de comandos
function showMenu() {
  console.log('\nComandos disponibles:');
  console.log('  status - Enviar actualización de estado');
  console.log('  telemetry - Enviar telemetría inmediatamente');
  console.log('  interval <ms> - Cambiar intervalo de telemetría');
  console.log('  quit - Salir del simulador');
  console.log('');
}

// Procesar comandos del usuario
rl.on('line', (line) => {
  const command = line.trim().toLowerCase();
  
  if (command === 'status') {
    if (connected && authenticated) {
      const status = `STATUS:status:online;battery:${Math.floor(70 + Math.random() * 30)};signal:${Math.floor(60 + Math.random() * 40)}`;
      client.write(status + '\n');
      console.log(`> ${status}`);
    } else {
      console.log('Not connected or authenticated');
    }
  } else if (command === 'telemetry') {
    if (connected && authenticated) {
      const telemetry = generateTelemetry();
      client.write(telemetry + '\n');
      console.log(`> ${telemetry}`);
    } else {
      console.log('Not connected or authenticated');
    }
  } else if (command.startsWith('interval ')) {
    const newInterval = parseInt(command.split(' ')[1], 10);
    if (isNaN(newInterval) || newInterval < 1000) {
      console.log('Invalid interval. Use interval <ms> with at least 1000ms');
    } else {
      config.interval = newInterval;
      console.log(`Telemetry interval changed to ${newInterval}ms`);
      
      if (connected && authenticated) {
        startTelemetry();
      }
    }
  } else if (command === 'quit' || command === 'exit') {
    console.log('Disconnecting and exiting...');
    
    if (interval) {
      clearInterval(interval);
    }
    
    if (client) {
      client.destroy();
    }
    
    rl.close();
    process.exit(0);
  } else if (command === 'help' || command === '?') {
    showMenu();
  } else if (command !== '') {
    console.log('Unknown command. Type help for available commands.');
  }
});

// Manejar cierre del programa
process.on('SIGINT', () => {
  console.log('\nDisconnecting and exiting...');
  
  if (interval) {
    clearInterval(interval);
  }
  
  if (client) {
    client.destroy();
  }
  
  rl.close();
  process.exit(0);
});

// Iniciar simulador
console.log('IoT Device Simulator');
console.log(`Device ID: ${config.deviceId}`);
console.log(`Server: ${config.host}:${config.port}`);
console.log(`Telemetry interval: ${config.interval}ms`);
console.log('Press Ctrl+C to exit');

// Conectar al servidor
connect();
EOF

# Finalización del script
success "Implementación de la Zona C (IoT Gateways) completada correctamente."
info "La estructura de directorios y archivos ha sido creada en: $GATEWAYS_DIR"
info "Para iniciar los servicios, ejecuta:"
echo -e "  cd $GATEWAYS_DIR"
echo -e "  ./start-gateways.sh"
info "Para simular un dispositivo IoT, ejecuta:"
echo -e "  cd $GATEWAYS_DIR/iot-gateway"
echo -e "  npm i"
echo -e "  node tools/simulator/deviceSimulator.js"

# Mostrar instrucciones adicionales
echo ""
echo -e "${GREEN}====================== INSTRUCCIONES ADICIONALES ======================${NC}"
echo -e "${BLUE}1. Instala las dependencias de Node.js para cada componente:${NC}"
echo -e "   cd $GATEWAYS_DIR/iot-gateway && npm install"
echo -e "   cd $GATEWAYS_DIR/m2m-adapter && npm install"
echo ""
echo -e "${BLUE}2. Configura las credenciales para la API M2M:${NC}"
echo -e "   Edita el archivo $GATEWAYS_DIR/m2m-adapter/credentials/m2m-api-creds.json"
echo -e "   o establece las variables de entorno M2M_API_CREDS_USERNAME y M2M_API_CREDS_PASSWORD"
echo ""
echo -e "${BLUE}3. Puedes ejecutar cada componente de forma independiente:${NC}"
echo -e "   cd $GATEWAYS_DIR/iot-gateway && npm run dev"
echo -e "   cd $GATEWAYS_DIR/m2m-adapter && npm run dev"
echo ""
echo -e "${BLUE}4. Puedes modificar los puertos y otras configuraciones en los archivos .env${NC}"
echo ""
echo -e "${BLUE}5. Los logs se guardarán en los directorios:${NC}"
echo -e "   $GATEWAYS_DIR/iot-gateway/logs/"
echo -e "   $GATEWAYS_DIR/m2m-adapter/logs/"
echo ""
echo -e "${GREEN}================================================================${NC}"
'
// src/gateway.js
const logger = require('./utils/logger');
const config = require('./config');
const tcpServer = require('./protocols/tcp/tcpServer');
const mqttHandler = require('./protocols/mqtt/mqttHandler');
const httpServer = require('./protocols/http/httpServer');
const mongoClient = require('./clients/mongoClient');
const redisClient = require('./clients/redisClient');
const deviceService = require('./services/deviceService');
const connectionMonitor = require('./tools/monitor/connectionMonitor');

// Banner de inicio
logger.info('====================================');
logger.info('Central Platform - IoT Gateway');
logger.info(`Version: ${config.version}`);
logger.info(`Environment: ${config.env}`);
logger.info('====================================');

// Inicializar componentes
async function initialize() {
  try {
    // Conectar a MongoDB
    await mongoClient.connect();
    logger.info('MongoDB connected successfully');
    
    // Conectar a Redis
    await redisClient.connect();
    logger.info('Redis connected successfully');
    
    // Inicializar servicio de dispositivos
    await deviceService.initialize();
    logger.info('Device service initialized');
    
    // Iniciar servidores por protocolo
    if (config.protocols.tcp.enabled) {
      await tcpServer.start();
      logger.info(`TCP server started on port ${config.protocols.tcp.port}`);
    }
    
    if (config.protocols.mqtt.enabled) {
      await mqttHandler.start();
      logger.info(`MQTT handler connected to ${config.protocols.mqtt.broker}`);
    }
    
    if (config.protocols.http.enabled) {
      await httpServer.start();
      logger.info(`HTTP server started on port ${config.protocols.http.port}`);
    }
    
    // Iniciar monitor de conexiones
    connectionMonitor.start();
    logger.info('Connection monitor started');
    
    // Suscribirse a comandos de dispositivos
    redisClient.subscribeToCommands(handleCommand);
    logger.info('Subscribed to device commands');
    
    logger.info('Gateway initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize gateway:', error);
    process.exit(1);
  }
}

// Manejador de comandos recibidos desde Redis
function handleCommand(command) {
  logger.debug(`Command received: ${JSON.stringify(command)}`);
  
  const { deviceId, action, parameters } = command;
  
  try {
    // Enviar comando al dispositivo adecuado
    deviceService.sendCommand(deviceId, action, parameters)
      .then(result => {
        logger.info(`Command sent to device ${deviceId}: ${action}`);
        // Publicar resultado en Redis
        redisClient.publishCommandResult(command.commandId, {
          status: 'sent',
          deviceId,
          timestamp: new Date().toISOString()
        });
      })
      .catch(error => {
        logger.error(`Failed to send command to device ${deviceId}:`, error);
        // Publicar error en Redis
        redisClient.publishCommandResult(command.commandId, {
          status: 'failed',
          deviceId,
          error: error.message,
          timestamp: new Date().toISOString()
        });
      });
  } catch (error) {
    logger.error(`Error processing command:`, error);
  }
}

// Manejo de señales de proceso
process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Función de apagado controlado
async function gracefulShutdown() {
  logger.info('Shutting down gateway...');
  
  try {
    // Detener servidores
    if (config.protocols.tcp.enabled) {
      await tcpServer.stop();
      logger.info('TCP server stopped');
    }
    
    if (config.protocols.mqtt.enabled) {
      await mqttHandler.stop();
      logger.info('MQTT handler stopped');
    }
    
    if (config.protocols.http.enabled) {
      await httpServer.stop();
      logger.info('HTTP server stopped');
    }
    
    // Detener monitor de conexiones
    connectionMonitor.stop();
    logger.info('Connection monitor stopped');
    
    // Desconectar de Redis
    await redisClient.disconnect();
    logger.info('Redis disconnected');
    
    // Desconectar de MongoDB
    await mongoClient.disconnect();
    logger.info('MongoDB disconnected');
    
    logger.info('Gateway shutdown complete');
    process.exit(0);
  } catch (error) {
    logger.error('Error during shutdown:', error);
    process.exit(1);
  }
}

// Iniciar el gateway
initialize();
EOF

# Archivo de configuración
cat > "$GATEWAYS_DIR/iot-gateway/src/config/index.js" << 'EOF'
// src/config/index.js
const env = require('./env');

const config = {
  // Información de versión y entorno
  version: '1.0.0',
  env: env.NODE_ENV || 'development',
  
  // Configuración de protocolos
  protocols: {
    tcp: {
      enabled: env.TCP_ENABLED === 'true',
      host: env.TCP_HOST || '0.0.0.0',
      port: parseInt(env.TCP_PORT || '8080', 10),
      timeout: parseInt(env.TCP_TIMEOUT || '300000', 10) // 5 minutos por defecto
    },
    mqtt: {
      enabled: env.MQTT_ENABLED === 'true',
      broker: env.MQTT_BROKER || 'mqtt://localhost:1883',
      clientId: env.MQTT_CLIENT_ID || 'central-platform-gateway',
      username: env.MQTT_USERNAME,
      password: env.MQTT_PASSWORD,
      topics: {
        telemetry: env.MQTT_TOPIC_TELEMETRY || 'devices/+/telemetry',
        commands: env.MQTT_TOPIC_COMMANDS || 'devices/+/commands',
        status: env.MQTT_TOPIC_STATUS || 'devices/+/status'
      }
    },
    http: {
      enabled: env.HTTP_ENABLED === 'true',
      host: env.HTTP_HOST || '0.0.0.0',
      port: parseInt(env.HTTP_PORT || '8081', 10)
    }
  },
  
  // Configuración de bases de datos
  mongodb: {
    uri: env.MONGODB_URI || 'mongodb://localhost:27017/central_platform',
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      poolSize: parseInt(env.MONGODB_POOL_SIZE || '10', 10)
    }
  },
  
  // Configuración de Redis
  redis: {
    url: env.REDIS_URL || 'redis://localhost:6379/0',
    channels: {
      telemetry: 'telemetry',
      deviceStatus: 'device-status',
      deviceCommands: 'device:commands',
      commandStatus: 'command-status'
    }
  },
  
  // Seguridad
  security: {
    jwtSecret: env.JWT_SECRET || 'your-secret-key',
    deviceAuthEnabled: env.DEVICE_AUTH_ENABLED === 'true'
  },
  
  // Límites y Throttling
  rateLimiting: {
    enabled: env.RATE_LIMIT_ENABLED === 'true',
    maxRequests: parseInt(env.RATE_LIMIT_MAX || '60', 10),
    windowMs: parseInt(env.RATE_LIMIT_WINDOW_MS || '60000', 10) // 1 minuto por defecto
  },
  
  // Integración con API M2M
  m2mApi: {
    enabled: env.M2M_API_ENABLED === 'true',
    url: env.M2M_API_URL || 'https://api.m2msystemsource.com/v1',
    credentialId: env.M2M_API_CREDENTIAL_ID || 'm2m-api-creds'
  },
  
  // Logging
  logging: {
    level: env.LOG_LEVEL || 'info',
    console: true,
    file: {
      enabled: true,
      path: env.LOG_FILE_PATH || 'logs/gateway.log'
    }
  }
};

module.exports = config;
EOF

# Archivo env.js
cat > "$GATEWAYS_DIR/iot-gateway/src/config/env.js" << 'EOF'
// src/config/env.js
const dotenv = require('dotenv');
const path = require('path');

// Cargar variables de entorno desde archivo .env
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

module.exports = process.env;
EOF

# Archivo logger.js
cat > "$GATEWAYS_DIR/iot-gateway/src/utils/logger.js" << 'EOF'
// src/utils/logger.js
const winston = require('winston');
const path = require('path');
const fs = require('fs');
const config = require('../config');

// Asegurarse de que el directorio de logs exista
const logDir = path.dirname(config.logging.file.path);
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

// Crear formato personalizado
const customFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ level, message, timestamp, stack }) => {
    return `${timestamp} [${level.toUpperCase()}]: ${message}${stack ? '\n' + stack : ''}`;
  })
);

// Configurar transports
const transports = [];

// Añadir transport para consola si está habilitado
if (config.logging.console) {
  transports.push(
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        customFormat
      )
    })
  );
}

// Añadir transport para archivo si está habilitado
if (config.logging.file.enabled) {
  transports.push(
    new winston.transports.File({
      filename: config.logging.file.path,
      maxsize: 5242880, // 5MB
      maxFiles: 5,
      format: customFormat
    })
  );
}

// Crear logger
const logger = winston.createLogger({
  level: config.logging.level,
  levels: winston.config.npm.levels,
  format: customFormat,
  transports
});

module.exports = logger;
EOF

# Archivo tcpServer.js
cat > "$GATEWAYS_DIR/iot-gateway/src/protocols/tcp/tcpServer.js" << 'EOF'
// src/protocols/tcp/tcpServer.js
const net = require('net');
const logger = require('../../utils/logger');
const config = require('../../config');
const tcpParser = require('./tcpParser');
const connectionHandler = require('../../handlers/connectionHandler');
const telemetryHandler = require('../../handlers/telemetryHandler');
const { authenticate } = require('../../middleware/authentication');
const { throttle } = require('../../middleware/throttling');

// Mapa de conexiones activas
const activeConnections = new Map();

// Servidor TCP
let server = null;

/**
 * Inicia el servidor TCP
 */
function start() {
  return new Promise((resolve, reject) => {
    try {
      server = net.createServer((socket) => {
        handleNewConnection(socket);
      });
      
      server.on('error', (err) => {
        logger.error('TCP Server error:', err);
      });
      
      server.listen(config.protocols.tcp.port, config.protocols.tcp.host, () => {
        logger.info(`TCP Server listening on ${config.protocols.tcp.host}:${config.protocols.tcp.port}`);
        resolve();
      });
    } catch (error) {
      reject(error);
    }
  });
}

/**
 * Detiene el servidor TCP
 */
function stop() {
  return new Promise((resolve, reject) => {
    if (!server) {
      resolve();
      return;
    }
    
    // Cerrar todas las conexiones activas
    for (const [deviceId, connection] of activeConnections.entries()) {
      try {
        connection.socket.end();
        logger.debug(`Closed connection for device ${deviceId}`);
      } catch (err) {
        logger.error(`Error closing connection for device ${deviceId}:`, err);
      }
    }
    
    // Limpiar mapa de conexiones
    activeConnections.clear();
    
    // Cerrar servidor
    server.close((err) => {
      if (err) {
        reject(err);
      } else {
        server = null;
        resolve();
      }
    });
  });
}

/**
 * Maneja una nueva conexión TCP
 * @param {net.Socket} socket - Socket TCP
 */
function handleNewConnection(socket) {
  const clientAddress = `${socket.remoteAddress}:${socket.remotePort}`;
  logger.info(`New TCP connection from ${clientAddress}`);
  
  let deviceId = null;
  let authenticated = false;
  let buffer = '';
  
  // Configurar timeout de inactividad
  socket.setTimeout(config.protocols.tcp.timeout || 300000); // Default: 5 minutos
  
  // Manejar datos recibidos
  socket.on('data', async (data) => {
    try {
      // Aplicar throttling
      if (!throttle(deviceId || clientAddress)) {
        logger.warn(`Rate limit exceeded for ${deviceId || clientAddress}`);
        return;
      }
      
      buffer += data.toString();
      
      // Procesar buffer para extraer mensajes completos
      const { messages, remaining } = tcpParser.parseBuffer(buffer);
      buffer = remaining;
      
      for (const message of messages) {
        // Si no está autenticado, intentar autenticar
        if (!authenticated) {
          const authResult = await authenticate(message);
          
          if (authResult.success) {
            authenticated = true;
            deviceId = authResult.deviceId;
            
            // Registrar conexión
            activeConnections.set(deviceId, {
              socket,
              connectedAt: new Date(),
              lastActivity: new Date()
            });
            
            // Notificar conexión de dispositivo
            await connectionHandler.handleConnect(deviceId, socket);
            
            logger.info(`Device ${deviceId} authenticated successfully`);
          } else {
            logger.warn(`Authentication failed from ${clientAddress}: ${authResult.error}`);
            socket.end();
            return;
          }
        } else {
          // Actualizar timestamp de última actividad
          if (activeConnections.has(deviceId)) {
            activeConnections.get(deviceId).lastActivity = new Date();
          }
          
          // Procesar mensaje según tipo
          if (message.type === 'telemetry') {
            // Procesar datos de telemetría
            await telemetryHandler.handleTelemetry(deviceId, message);
          } else if (message.type === 'status') {
            // Procesar actualización de estado
            await connectionHandler.handleStatusUpdate(deviceId, message);
          } else if (message.type === 'ack') {
            // Procesar confirmación de comando
            await connectionHandler.handleCommandAck(deviceId, message);
          } else {
            logger.warn(`Unknown message type from device ${deviceId}: ${message.type}`);
          }
        }
      }
    } catch (error) {
      logger.error(`Error processing data from ${deviceId || clientAddress}:`, error);
    }
  });
  
  // Manejar timeout
  socket.on('timeout', () => {
    logger.info(`Connection timeout for ${deviceId || clientAddress}`);
    socket.end();
  });
  
  // Manejar cierre de conexión
  socket.on('close', async () => {
    if (deviceId) {
      // Eliminar de conexiones activas
      activeConnections.delete(deviceId);
      
      // Notificar desconexión de dispositivo
      await connectionHandler.handleDisconnect(deviceId);
      
      logger.info(`Device ${deviceId} disconnected`);
    } else {
      logger.info(`Connection closed from ${clientAddress}`);
    }
  });
  
  // Manejar errores
  socket.on('error', (err) => {
    logger.error(`Socket error from ${deviceId || clientAddress}:`, err);
  });
}

/**
 * Envía un comando a un dispositivo conectado
 * @param {string} deviceId - ID del dispositivo
 * @param {string} command - Comando a enviar
 * @returns {Promise<boolean>} - True si el comando se envió correctamente
 */
async function sendCommand(deviceId, command) {
  return new Promise((resolve, reject) => {
    if (!activeConnections.has(deviceId)) {
      reject(new Error(`Device ${deviceId} not connected`));
      return;
    }
    
    const { socket } = activeConnections.get(deviceId);
    
    try {
      // Formatear comando según protocolo
      const formattedCommand = tcpParser.formatCommand(command);
      
      // Enviar comando
      socket.write(formattedCommand + '\n', (err) => {
        if (err) {
          reject(err);
        } else {
          resolve(true);
        }
      });
    } catch (error) {
      reject(error);
    }
  });
}

// Exponer API
module.exports = {
  start,
  stop,
  sendCommand,
  getActiveConnections: () => activeConnections.size,
  getActiveDevices: () => Array.from(activeConnections.keys())
};
EOF

# Archivo tcpParser.js
cat > "$GATEWAYS_DIR/iot-gateway/src/protocols/tcp/tcpParser.js" << 'EOF'
// src/protocols/tcp/tcpParser.js
const logger = require('../../utils/logger');

/**
 * Parsea un buffer de datos para extraer mensajes completos
 * @param {string} buffer - Buffer de datos a parsear
 * @returns {Object} - Objeto con mensajes parseados y buffer restante
 */
function parseBuffer(buffer) {
  const delimiter = '\n';
  const parts = buffer.split(delimiter);
  const messages = [];
  
  // El último elemento puede estar incompleto
  const remaining = parts.pop();
  
  // Procesar partes completas
  for (const part of parts) {
    if (part.trim() === '') continue;
    
    try {
      // Intentar parsear como JSON
      const message = JSON.parse(part);
      messages.push(message);
    } catch (error) {
      // Intentar parsear en formato propietario
      try {
        const parsedMessage = parseProprietaryFormat(part);
        messages.push(parsedMessage);
      } catch (parseError) {
        logger.error(`Error parsing message: ${part}`, parseError);
      }
    }
  }
  
  return { messages, remaining };
}

/**
 * Parsea un mensaje en formato propietario
 * @param {string} message - Mensaje a parsear
 * @returns {Object} - Mensaje parseado
 */
function parseProprietaryFormat(message) {
  // Implementación específica según protocolo propietario
  // Ejemplo: formato "KEY1:VALUE1;KEY2:VALUE2;..."
  
  if (!message || typeof message !== 'string') {
    throw new Error('Invalid message format');
  }
  
  const result = {
    raw: message
  };
  
  try {
    // Detectar tipo de mensaje basado en prefijo o contenido
    if (message.startsWith('AUTH:')) {
      result.type = 'auth';
      const parts = message.substring(5).split(';');
      
      for (const part of parts) {
        const [key, value] = part.split(':');
        if (key && value) {
          result[key.toLowerCase()] = value;
        }
      }
    } else if (message.startsWith('DATA:')) {
      result.type = 'telemetry';
      result.data = {};
      const parts = message.substring(5).split(';');
      
      for (const part of parts) {
        const [key, value] = part.split(':');
        if (key && value) {
          if (key === 'TIME') {
            result.timestamp = new Date(parseInt(value));
          } else if (key === 'LOC') {
            const [lng, lat] = value.split(',').map(Number);
            result.location = { lng, lat };
          } else {
            // Intentar convertir valores numéricos
            result.data[key.toLowerCase()] = isNaN(value) ? value : Number(value);
          }
        }
      }
    } else if (message.startsWith('STATUS:')) {
      result.type = 'status';
      const parts = message.substring(7).split(';');
      
      for (const part of parts) {
        const [key, value] = part.split(':');
        if (key && value) {
          result[key.toLowerCase()] = value;
        }
      }
    } else if (message.startsWith('ACK:')) {
      result.type = 'ack';
      const parts = message.substring(4).split(';');
      
      for (const part of parts) {
        const [key, value] = part.split(':');
        if (key && value) {
          result[key.toLowerCase()] = value;
        }
      }
    } else {
      throw new Error('Unknown message format');
    }
  } catch (error) {
    throw new Error(`Error parsing proprietary format: ${error.message}`);
  }
  
  return result;
}

/**
 * Formatea un comando para enviarlo a un dispositivo
 * @param {Object} command - Comando a formatear
 * @returns {string} - Comando formateado
 */
function formatCommand(command) {
  // Si el comando ya es un string, devolverlo tal cual
  if (typeof command === 'string') {
    return command;
  }
  
  // Si es un objeto, convertirlo a JSON
  if (typeof command === 'object') {
    return JSON.stringify(command);
  }
  
  throw new Error('Invalid command format');
}

module.exports = {
  parseBuffer,
  parseProprietaryFormat,
  formatCommand
};
EOF

# Archivo telemetryHandler.js
cat > "$GATEWAYS_DIR/iot-gateway/src/handlers/telemetryHandler.js" << 'EOF'
// src/handlers/telemetryHandler.js
const logger = require('../utils/logger');
const telemetryService = require('../services/telemetryService');
const redisClient = require('../clients/redisClient');
const deviceService = require('../services/deviceService');

/**
 * Maneja datos de telemetría recibidos de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @param {Object} message - Mensaje de telemetría
 * @returns {Promise<void>}
 */
async function handleTelemetry(deviceId, message) {
  try {
    logger.debug(`Telemetry received from device ${deviceId}`);
    
    // Validar datos
    if (!message.data) {
      logger.warn(`Invalid telemetry data from device ${deviceId}`);
      return;
    }
    
    // Normalizar timestamp
    const timestamp = message.timestamp || new Date();
    
    // Guardar telemetría en base de datos
    const telemetry = await telemetryService.saveTelemetry(deviceId, {
      timestamp,
      data: message.data,
      location: message.location
    });
    
    // Actualizar estado y ubicación del dispositivo si es necesario
    if (message.location) {
      await deviceService.updateDeviceLocation(deviceId, message.location);
    }
    
    // Publicar telemetría en Redis para otros servicios
    redisClient.publishTelemetry({
      deviceId,
      timestamp: timestamp.toISOString(),
      data: message.data,
      location: message.location,
      deviceType: await deviceService.getDeviceType(deviceId)
    });
    
    logger.debug(`Telemetry from device ${deviceId} processed successfully`);
  } catch (error) {
    logger.error(`Error processing telemetry from device ${deviceId}:`, error);
    throw error;
  }
}

module.exports = {
  handleTelemetry
};
EOF

# Archivo redisClient.js
cat > "$GATEWAYS_DIR/iot-gateway/src/clients/redisClient.js" << 'EOF'
// src/clients/redisClient.js
const Redis = require('ioredis');
const logger = require('../utils/logger');
const config = require('../config');

// Clientes Redis
let pubClient = null;
let subClient = null;

// Callback para comandos
let commandCallback = null;

/**
 * Conecta a Redis
 * @returns {Promise<void>}
 */
async function connect() {
  try {
    // Cliente para publicación
    pubClient = new Redis(config.redis.url, {
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      }
    });
    
    // Cliente para suscripción
    subClient = new Redis(config.redis.url, {
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      }
    });
    
    // Manejar errores
    pubClient.on('error', (err) => {
      logger.error('Redis pub client error:', err);
    });
    
    subClient.on('error', (err) => {
      logger.error('Redis sub client error:', err);
    });
    
    // Esperar a que ambos clientes estén listos
    await Promise.all([
      new Promise((resolve) => pubClient.on('ready', resolve)),
      new Promise((resolve) => subClient.on('ready', resolve))
    ]);
    
    logger.info('Redis clients connected successfully');
  } catch (error) {
    logger.error('Error connecting to Redis:', error);
    throw error;
  }
}

/**
 * Desconecta de Redis
 * @returns {Promise<void>}
 */
async function disconnect() {
  try {
    if (pubClient) {
      await pubClient.quit();
    }
    
    if (subClient) {
      await subClient.quit();
    }
    
    logger.info('Redis clients disconnected');
  } catch (error) {
    logger.error('Error disconnecting from Redis:', error);
    throw error;
  }
}

/**
 * Publica telemetría en Redis
 * @param {Object} telemetry - Datos de telemetría
 * @returns {Promise<void>}
 */
async function publishTelemetry(telemetry) {
  if (!pubClient) {
    throw new Error('Redis client not initialized');
  }
  
  try {
    await pubClient.publish(config.redis.channels.telemetry, JSON.stringify(telemetry));
    logger.debug(`Telemetry published for device ${telemetry.deviceId}`);
  } catch (error) {
    logger.error(`Error publishing telemetry for device ${telemetry.deviceId}:`, error);
    throw error;
  }
}

/**
 * Publica estado de dispositivo en Redis
 * @param {Object} status - Estado del dispositivo
 * @returns {Promise<void>}
 */
async function publishDeviceStatus(status) {
  if (!pubClient) {
    throw new Error('Redis client not initialized');
  }
  
  try {
    await pubClient.publish(config.redis.channels.deviceStatus, JSON.stringify(status));
    logger.debug(`Status published for device ${status.deviceId}`);
  } catch (error) {
    logger.error(`Error publishing status for device ${status.deviceId}:`, error);
    throw error;
  }
}

/**
 * Publica resultado de comando en Redis
 * @param {string} commandId - ID del comando
 * @param {Object} result - Resultado del comando
 * @returns {Promise<void>}
 */
async function publishCommandResult(commandId, result) {
  if (!pubClient) {
    throw new Error('Redis client not initialized');
  }
  
  try {
    await pubClient.publish(config.redis.channels.commandStatus, JSON.stringify({
      commandId,
      ...result
    }));
    logger.debug(`Command result published for command ${commandId}`);
  } catch (error) {
    logger.error(`Error publishing command result for command ${commandId}:`, error);
    throw error;
  }
}

/**
 * Suscribe a comandos de dispositivos
 * @param {Function} callback - Función de callback para comandos
 */
function subscribeToCommands(callback) {
  if (!subClient) {
    throw new Error('Redis client not initialized');
  }
  
  commandCallback = callback;
  
  // Suscribirse al canal de comandos
  subClient.subscribe(config.redis.channels.deviceCommands);
  
  // Configurar manejador de mensajes
  subClient.on('message', (channel, message) => {
    try {
      if (channel === config.redis.channels.deviceCommands && commandCallback) {
        const command = JSON.parse(message);
        commandCallback(command);
      }
    } catch (error) {
      logger.error('Error processing Redis message:', error);
    }
  });
  
  logger.info('Subscribed to device commands');
}

module.exports = {
  connect,
  disconnect,
  publishTelemetry,
  publishDeviceStatus,
  publishCommandResult,
  subscribeToCommands
};
EOF

# Archivo connectionHandler.js
cat > "$GATEWAYS_DIR/iot-gateway/src/handlers/connectionHandler.js" << 'EOF'
// src/handlers/connectionHandler.js
const logger = require('../utils/logger');
const deviceService = require('../services/deviceService');
const redisClient = require('../clients/redisClient');

/**
 * Maneja la conexión de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @param {Object} socket - Socket de conexión
 * @returns {Promise<void>}
 */
async function handleConnect(deviceId, socket) {
  try {
    logger.info(`Device ${deviceId} connected`);
    
    // Actualizar estado del dispositivo
    await deviceService.updateDeviceStatus(deviceId, 'online');
    
    // Publicar estado en Redis
    redisClient.publishDeviceStatus({
      deviceId,
      status: 'online',
      timestamp: new Date().toISOString(),
      ipAddress: socket.remoteAddress
    });
  } catch (error) {
    logger.error(`Error handling connect for device ${deviceId}:`, error);
  }
}

/**
 * Maneja la desconexión de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @returns {Promise<void>}
 */
async function handleDisconnect(deviceId) {
  try {
    logger.info(`Device ${deviceId} disconnected`);
    
    // Actualizar estado del dispositivo
    await deviceService.updateDeviceStatus(deviceId, 'offline');
    
    // Publicar estado en Redis
    redisClient.publishDeviceStatus({
      deviceId,
      status: 'offline',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error(`Error handling disconnect for device ${deviceId}:`, error);
  }
}

/**
 * Maneja actualización de estado de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @param {Object} message - Mensaje de estado
 * @returns {Promise<void>}
 */
async function handleStatusUpdate(deviceId, message) {
  try {
    logger.debug(`Status update from device ${deviceId}`);
    
    const status = message.status || 'online';
    
    // Actualizar estado del dispositivo
    await deviceService.updateDeviceStatus(deviceId, status);
    
    // Actualizar metadata si está presente
    if (message.metadata) {
      await deviceService.updateDeviceMetadata(deviceId, message.metadata);
    }
    
    // Publicar estado en Redis
    redisClient.publishDeviceStatus({
      deviceId,
      status,
      timestamp: new Date().toISOString(),
      metadata: message.metadata
    });
  } catch (error) {
    logger.error(`Error handling status update for device ${deviceId}:`, error);
  }
}

/**
 * Maneja confirmación de comando de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @param {Object} message - Mensaje de confirmación
 * @returns {Promise<void>}
 */
async function handleCommandAck(deviceId, message) {
  try {
    logger.debug(`Command acknowledgment from device ${deviceId}`);
    
    if (!message.commandId) {
      logger.warn(`Invalid command acknowledgment from device ${deviceId}: missing commandId`);
      return;
    }
    
    // Publicar resultado del comando en Redis
    redisClient.publishCommandResult(message.commandId, {
      deviceId,
      status: message.status || 'acknowledged',
      result: message.result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error(`Error handling command acknowledgment for device ${deviceId}:`, error);
  }
}

module.exports = {
  handleConnect,
  handleDisconnect,
  handleStatusUpdate,
  handleCommandAck
};
EOF

# Archivo authentication.js
cat > "$GATEWAYS_DIR/iot-gateway/src/middleware/authentication.js" << 'EOF'
// src/middleware/authentication.js
const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');
const config = require('../config');
const deviceService = require('../services/deviceService');

/**
 * Autentica un dispositivo basado en el mensaje recibido
 * @param {Object} message - Mensaje de autenticación
 * @returns {Promise<Object>} - Resultado de la autenticación
 */
async function authenticate(message) {
  try {
    // Si la autenticación de dispositivos está deshabilitada, aceptamos cualquier dispositivo
    if (!config.security.deviceAuthEnabled) {
      // Aún así, necesitamos un deviceId
      if (!message.deviceId) {
        return { success: false, error: 'Device ID is required' };
      }
      return { success: true, deviceId: message.deviceId };
    }
    
    // Verificar tipo de mensaje
    if (message.type !== 'auth') {
      return { success: false, error: 'Authentication required' };
    }
    
    // Verificar deviceId
    if (!message.deviceId) {
      return { success: false, error: 'Device ID is required' };
    }
    
    // Verificar si es autenticación por token o por credenciales
    if (message.token) {
      // Autenticación por token JWT
      try {
        const decoded = jwt.verify(message.token, config.security.jwtSecret);
        
        // Verificar que el deviceId en el token coincida con el del mensaje
        if (decoded.deviceId !== message.deviceId) {
          return { success: false, error: 'Invalid token for this device' };
        }
        
        // Verificar que el dispositivo existe y está habilitado
        const deviceExists = await deviceService.validateDevice(message.deviceId);
        if (!deviceExists) {
          return { success: false, error: 'Device not found or disabled' };
        }
        
        return { success: true, deviceId: message.deviceId };
      } catch (jwtError) {
        logger.error(`JWT authentication error for device ${message.deviceId}:`, jwtError);
        return { success: false, error: 'Invalid token' };
      }
    } else if (message.key) {
      // Autenticación por clave API
      const isValid = await deviceService.validateDeviceKey(message.deviceId, message.key);
      
      if (isValid) {
        return { success: true, deviceId: message.deviceId };
      } else {
        return { success: false, error: 'Invalid API key' };
      }
    } else {
      return { success: false, error: 'Authentication credentials required' };
    }
  } catch (error) {
    logger.error('Authentication error:', error);
    return { success: false, error: 'Internal authentication error' };
  }
}

module.exports = {
  authenticate
};
EOF

# Archivo throttling.js
cat > "$GATEWAYS_DIR/iot-gateway/src/middleware/throttling.js" << 'EOF'
// src/middleware/throttling.js
const logger = require('../utils/logger');
const config = require('../config');

// Mapa para almacenar contadores por cliente
const rateLimitMap = new Map();

// Última vez que se realizó limpieza
let lastCleanup = Date.now();

/**
 * Limpia entradas antiguas en el mapa de throttling
 */
function cleanup() {
  const now = Date.now();
  // Realizar limpieza cada 5 minutos
  if (now - lastCleanup > 300000) {
    const windowMs = config.rateLimiting.windowMs;
    
    for (const [key, entry] of rateLimitMap.entries()) {
      if (now - entry.timestamp > windowMs) {
        rateLimitMap.delete(key);
      }
    }
    
    lastCleanup = now;
    logger.debug('Rate limit map cleanup performed');
  }
}

/**
 * Verifica si una petición debe ser throttled
 * @param {string} clientId - ID del cliente (dispositivo o dirección IP)
 * @returns {boolean} - true si la petición es permitida, false si debe ser throttled
 */
function throttle(clientId) {
  // Si el rate limiting está deshabilitado, permitir todo
  if (!config.rateLimiting.enabled) {
    return true;
  }
  
  // Limpiar entradas antiguas periódicamente
  cleanup();
  
  const now = Date.now();
  const windowMs = config.rateLimiting.windowMs;
  const maxRequests = config.rateLimiting.maxRequests;
  
  // Obtener o crear entrada para este cliente
  let entry = rateLimitMap.get(clientId);
  if (!entry) {
    entry = {
      count: 0,
      timestamp: now
    };
    rateLimitMap.set(clientId, entry);
  }
  
  // Reiniciar contador si ha pasado la ventana de tiempo
  if (now - entry.timestamp > windowMs) {
    entry.count = 0;
    entry.timestamp = now;
  }
  
  // Incrementar contador
  entry.count++;
  
  // Verificar si excede el límite
  if (entry.count > maxRequests) {
    logger.warn(`Rate limit exceeded for client ${clientId}: ${entry.count} requests in window`);
    return false;
  }
  
  return true;
}

module.exports = {
  throttle
};
EOF

# Archivo package.json para IoT Gateway
cat > "$GATEWAYS_DIR/iot-gateway/package.json" << 'EOF'
{
  "name": "central-platform-iot-gateway",
  "version": "1.0.0",
  "description": "IoT Gateway for Central Platform",
  "main": "src/gateway.js",
  "scripts": {
    "start": "node src/gateway.js",
    "dev": "nodemon src/gateway.js",
    "simulator": "node tools/simulator/deviceSimulator.js",
    "test": "jest",
    "lint": "eslint --ext .js src/"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "mongoose": "^7.0.3",
    "mqtt": "^4.3.7",
    "jsonwebtoken": "^9.0.0",
    "dotenv": "^16.0.3",
    "winston": "^3.8.2",
    "axios": "^1.3.5",
    "node-cache": "^5.1.2"
  },
  "devDependencies": {
    "jest": "^29.5.0",
    "nodemon": "^2.0.22",
    "eslint": "^8.38.0",
    "eslint-config-prettier": "^8.8.0",
    "eslint-plugin-prettier": "^4.2.1",
    "prettier": "^2.8.7",
    "supertest": "^6.3.3"
  }
}
EOF

# Archivo Dockerfile para IoT Gateway
cat > "$GATEWAYS_DIR/iot-gateway/Dockerfile" << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copiar package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm ci --only=production

# Copiar código fuente
COPY . .

# Exponer puertos (TCP, HTTP, etc.)
EXPOSE 8080 8081 1883

# Punto de entrada con variables de entorno
CMD ["node", "src/gateway.js"]
EOF

# Archivo .env para IoT Gateway
cat > "$GATEWAYS_DIR/iot-gateway/.env" << 'EOF'
# Configuración general
NODE_ENV=development
LOG_LEVEL=info
VERSION=1.0.0

# Servidor TCP
TCP_ENABLED=true
TCP_PORT=8080
TCP_HOST=0.0.0.0
TCP_TIMEOUT=300000

# Servidor MQTT
MQTT_ENABLED=true
MQTT_BROKER=mqtt://localhost:1883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_CLIENT_ID=central-platform-gateway

# Servidor HTTP
HTTP_ENABLED=true
HTTP_PORT=8081
HTTP_HOST=0.0.0.0

# MongoDB
MONGODB_URI=mongodb://mongodb:27017/central_platform
MONGODB_POOL_SIZE=10

# Redis
REDIS_URL=redis://redis:6379/0

# Seguridad
JWT_SECRET=your-secret-key
DEVICE_AUTH_ENABLED=true

# Límites y Throttling
RATE_LIMIT_ENABLED=true
RATE_LIMIT_MAX=60
RATE_LIMIT_WINDOW_MS=60000

# Integración M2M
M2M_API_ENABLED=true
M2M_API_URL=https://api.m2msystemsource.com/v1
M2M_API_CREDENTIAL_ID=m2m-api-creds
EOF

# Archivo docker-compose.yml para IoT Gateway
cat > "$GATEWAYS_DIR/iot-gateway/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  iot-gateway:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"  # TCP
      - "8081:8081"  # HTTP
      - "1883:1883"  # MQTT
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
    depends_on:
      - mongodb
      - redis
    restart: unless-stopped
    networks:
      - central-platform-network

  # Servicios de apoyo para desarrollo
  mongodb:
    image: mongo:5.0
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    networks:
      - central-platform-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - central-platform-network

volumes:
  mongodb_data:
  redis_data:

networks:
  central-platform-network:
    driver: bridge
EOF

# Ahora crearemos los archivos básicos para el adaptador M2M
info "Creando archivos para M2M Adapter..."

# Archivo server.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/server.js" << 'EOF'
// src/server.js
const express = require('express');
const mongoose = require('mongoose');
const logger = require('./utils/logger');
const config = require('./config');
const deviceRoutes = require('./routes/devices');
const telemetryRoutes = require('./routes/telemetry');
const syncRoutes = require('./routes/sync');
const { scheduleSync } = require('./services/synchronizationService');

// Crear aplicación Express
const app = express();

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Banner de inicio
logger.info('====================================');
logger.info('Central Platform - M2M Adapter');
logger.info(`Version: ${config.version}`);
logger.info(`Environment: ${config.env}`);
logger.info('====================================');

// Inicializar
async function initialize() {
  try {
    // Conectar a MongoDB
    await mongoose.connect(config.mongodb.uri, config.mongodb.options);
    logger.info('MongoDB connected successfully');
    
    // Configurar rutas
    app.use('/api/devices', deviceRoutes);
    app.use('/api/telemetry', telemetryRoutes);
    app.use('/api/sync', syncRoutes);
    
    // Ruta de health check
    app.get('/health', (req, res) => {
      res.status(200).json({ status: 'ok' });
    });
    
    // Middleware de manejo de errores
    app.use((err, req, res, next) => {
      logger.error('API error:', err);
      res.status(err.status || 500).json({
        error: {
          message: err.message,
          code: err.code || 'SERVER_ERROR'
        }
      });
    });
    
    // Iniciar servidor
    const server = app.listen(config.port, () => {
      logger.info(`M2M Adapter listening on port ${config.port}`);
    });
    
    // Manejar señales de proceso
    process.on('SIGTERM', () => gracefulShutdown(server));
    process.on('SIGINT', () => gracefulShutdown(server));
    
    // Programar sincronización periódica si está habilitada
    if (config.synchronization.enabled) {
      scheduleSync();
      logger.info(`Scheduled synchronization every ${config.synchronization.interval} minutes`);
    }
    
    logger.info('M2M Adapter initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize M2M Adapter:', error);
    process.exit(1);
  }
}

// Apagado controlado
async function gracefulShutdown(server) {
  logger.info('Shutting down M2M Adapter...');
  
  // Cerrar servidor HTTP
  server.close(() => {
    logger.info('HTTP server closed');
    
    // Cerrar conexión MongoDB
    mongoose.connection.close(false, () => {
      logger.info('MongoDB connection closed');
      process.exit(0);
    });
  });
  
  // Forzar cierre después de timeout
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000);
}

// Iniciar
initialize();
EOF

# Archivo config/index.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/config/index.js" << 'EOF'
// src/config/index.js
const env = require('./env');

const config = {
  // Información general
  version: '1.0.0',
  env: env.NODE_ENV || 'development',
  port: parseInt(env.PORT || '8082', 10),
  
  // Configuración de MongoDB
  mongodb: {
    uri: env.MONGODB_URI || 'mongodb://localhost:27017/central_platform',
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      poolSize: parseInt(env.MONGODB_POOL_SIZE || '10', 10)
    }
  },
  
  // Configuración de la API M2M
  m2mApi: {
    url: env.M2M_API_URL || 'https://api.m2msystemsource.com/v1',
    credentialId: env.M2M_API_CREDENTIAL_ID || 'm2m-api-creds'
  },
  
  // Configuración de sincronización
  synchronization: {
    enabled: env.SYNC_ENABLED === 'true',
    interval: parseInt(env.SYNC_INTERVAL || '60', 10), // minutos
    runOnStart: env.SYNC_ON_START === 'true',
    batchSize: parseInt(env.SYNC_BATCH_SIZE || '1000', 10)
  },
  
  // Configuración de caché
  cache: {
    ttl: parseInt(env.CACHE_TTL || '300', 10), // segundos
    checkPeriod: parseInt(env.CACHE_CHECK_PERIOD || '60', 10) // segundos
  },
  
  // Logging
  logging: {
    level: env.LOG_LEVEL || 'info',
    console: true,
    file: {
      enabled: true,
      path: env.LOG_FILE_PATH || 'logs/m2m-adapter.log'
    }
  }
};

module.exports = config;
EOF

# Archivo config/env.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/config/env.js" << 'EOF'
// src/config/env.js
const dotenv = require('dotenv');
const path = require('path');

// Cargar variables de entorno desde archivo .env
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

module.exports = process.env;
EOF

# Archivo utils/logger.js para M2M Adapter
cat > "$GATEWAYS_DIR/m2m-adapter/src/utils/logger.js" << 'EOF'
// src/utils/logger.js
const winston = require('winston');
const path = require('path');
const fs = require('fs');
const config = require('../config');

// Asegurarse de que el directorio de logs exista
const logDir = path.dirname(config.logging.file.path);
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

// Crear formato personalizado
const customFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ level, message, timestamp, stack }) => {
    return `${timestamp} [${level.toUpperCase()}]: ${message}${stack ? '\n' + stack : ''}`;
  })
);

// Configurar transports
const transports = [];

// Añadir transport para consola si está habilitado
if (config.logging.console) {
  transports.push(
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        customFormat
      )
    })
  );
}

// Añadir transport para archivo si está habilitado
if (config.logging.file.enabled) {
  transports.push(
    new winston.transports.File({
      filename: config.logging.file.path,
      maxsize: 5242880, // 5MB
      maxFiles: 5,
      format: customFormat
    })
  );
}

// Crear logger
const logger = winston.createLogger({
  level: config.logging.level,
  levels: winston.config.npm.levels,
  format: customFormat,
  transports
});

module.exports = logger;
EOF

# Archivo services/synchronizationService.js para M2M Adapter
mkdir -p "$GATEWAYS_DIR/m2m-adapter/src/services"
cat > "$GATEWAYS_DIR/m2m-adapter/src/services/synchronizationService.js" << 'EOF'
// src/services/synchronizationService.js
const logger = require('../utils/logger');
const config = require('../config');
const m2mApiAdapter = require('../adapters/m2mApiAdapter');
const mappingService = require('./mappingService');
const Device = require('../models/device');

// Estado de la sincronización
let isRunning = false;
let lastSyncTime = null;
let syncInterval = null;

/**
 * Programa la sincronización periódica
 */
function scheduleSync() {
  // Limpiar intervalo existente
  if (syncInterval) {
    clearInterval(syncInterval);
  }
  
  // Configurar nuevo intervalo
  const intervalMs = config.synchronization.interval * 60 * 1000; // minutos a ms
  syncInterval = setInterval(async () => {
    try {
      await synchronizeDevices();
    } catch (error) {
      logger.error('Scheduled synchronization failed:', error);
    }
  }, intervalMs);
  
  // Ejecutar sincronización inicial
  if (config.synchronization.runOnStart) {
    setTimeout(async () => {
      try {
        await synchronizeDevices();
      } catch (error) {
        logger.error('Initial synchronization failed:', error);
      }
    }, 5000);
  }
}

/**
 * Sincroniza dispositivos con la API M2M
 * @returns {Promise<Object>} - Resultados de la sincronización
 */
async function synchronizeDevices() {
  // Evitar ejecuciones simultáneas
  if (isRunning) {
    logger.warn('Synchronization already in progress, skipping...');
    return {
      success: false,
      error: 'Synchronization already in progress'
    };
  }
  
  isRunning = true;
  const startTime = Date.now();
  logger.info('Starting device synchronization with M2M API...');
  
  const result = {
    success: true,
    total: 0,
    added: 0,
    updated: 0,
    errors: 0,
    duration: 0
  };
  
  try {
    // Obtener todos los dispositivos desde la API M2M
    const remoteDevices = await m2mApiAdapter.getDevices({
      limit: config.synchronization.batchSize || 1000
    });
    
    result.total = remoteDevices.length;
    logger.info(`Found ${result.total} devices in M2M API`);
    
    // Procesar cada dispositivo
    for (const remoteDevice of remoteDevices) {
      try {
        // Mapear datos del dispositivo remoto al formato local
        const mappedDevice = mappingService.mapM2MDeviceToLocal(remoteDevice);
        
        // Verificar si el dispositivo ya existe
        const existingDevice = await Device.findOne({ deviceId: mappedDevice.deviceId });
        
        if (existingDevice) {
          // Actualizar dispositivo existente
          await Device.updateOne(
            { deviceId: mappedDevice.deviceId },
            { $set: mappedDevice }
          );
          result.updated++;
          logger.debug(`Updated device ${mappedDevice.deviceId}`);
        } else {
          // Crear nuevo dispositivo
          await Device.create(mappedDevice);
          result.added++;
          logger.debug(`Added new device ${mappedDevice.deviceId}`);
        }
      } catch (deviceError) {
        result.errors++;
        logger.error(`Error processing device ${remoteDevice.deviceId || 'unknown'}:`, deviceError);
      }
    }
    
    // Actualizar estado de sincronización
    lastSyncTime = new Date();
    result.duration = (Date.now() - startTime) / 1000; // en segundos
    
    logger.info(`Synchronization completed in ${result.duration}s. Added: ${result.added}, Updated: ${result.updated}, Errors: ${result.errors}`);
  } catch (error) {
    result.success = false;
    result.error = error.message;
    logger.error('Synchronization failed:', error);
  } finally {
    isRunning = false;
  }
  
  return result;
}

/**
 * Obtiene el estado de la sincronización
 * @returns {Object} - Estado de la sincronización
 */
function getSyncStatus() {
  return {
    enabled: config.synchronization.enabled,
    interval: config.synchronization.interval,
    isRunning,
    lastSyncTime,
    nextSyncTime: syncInterval && lastSyncTime ? new Date(lastSyncTime.getTime() + (config.synchronization.interval * 60 * 1000)) : null
  };
}

module.exports = {
  scheduleSync,
  synchronizeDevices,
  getSyncStatus
};
EOF

# Archivo adapters/m2mApiAdapter.js para M2M Adapter
mkdir -p "$GATEWAYS_DIR/m2m-adapter/src/adapters"
cat > "$GATEWAYS_DIR/m2m-adapter/src/adapters/m2mApiAdapter.js" << 'EOF'
// src/adapters/m2mApiAdapter.js
const axios = require('axios');
const logger = require('../utils/logger');
const config = require('../config');
const { getCredential } = require('../utils/credentials');
const { exponentialBackoff } = require('../utils/retry');

// Cliente Axios con configuración base
const apiClient = axios.create({
  baseURL: config.m2mApi.baseUrl,
  timeout: 10000
});

// Token y tiempo de expiración
let authToken = null;
let tokenExpiry = null;

/**
 * Obtiene un token de autenticación
 * @returns {Promise<string>} - Token de autenticación
 */
async function getAuthToken() {
  try {
    // Si el token es válido, reutilizarlo
    if (authToken && tokenExpiry && new Date() < tokenExpiry) {
      return authToken;
    }
    
    // Obtener credenciales
    const credential = await getCredential(config.m2mApi.credentialId);
    
    if (!credential) {
      throw new Error('M2M API credentials not found');
    }
    
    // Autenticar con API M2M
    const response = await apiClient.post('/auth/login', {
      username: credential.username,
      password: credential.password
    });
    
    authToken = response.data.token;
    
    // Calcular expiración (10 minutos antes del tiempo real)
    const expirySeconds = response.data.expiresIn || 3600;
    tokenExpiry = new Date(Date.now() + (expirySeconds - 600) * 1000);
    
    logger.debug('Successfully authenticated with M2M API');
    
    return authToken;
  } catch (error) {
    logger.error('Failed to authenticate with M2M API:', error);
    throw new Error('Authentication with M2M API failed');
  }
}

/**
 * Obtiene dispositivos desde la API M2M
 * @param {Object} filters - Filtros de búsqueda
 * @returns {Promise<Array>} - Lista de dispositivos
 */
async function getDevices(filters = {}) {
  return exponentialBackoff(async () => {
    const token = await getAuthToken();
    
    const params = new URLSearchParams();
    
    // Aplicar filtros
    if (filters.search) {
      params.append('search', filters.search);
    }
    
    if (filters.type) {
      params.append('type', filters.type);
    }
    
    if (filters.limit) {
      params.append('limit', filters.limit);
    }
    
    if (filters.skip) {
      params.append('skip', filters.skip);
    }
    
    const response = await apiClient.get('/devices', {
      headers: {
        Authorization: `Bearer ${token}`
      },
      params
    });
    
    return response.data;
  }, 3);
}

/**
 * Obtiene un dispositivo específico
 * @param {string} deviceId - ID del dispositivo
 * @returns {Promise<Object>} - Información del dispositivo
 */
async function getDevice(deviceId) {
  return exponentialBackoff(async () => {
    const token = await getAuthToken();
    
    const response = await apiClient.get(`/devices/${deviceId}`, {
      headers: {
        Authorization: `Bearer ${token}`
      }
    });
    
    return response.data;
  }, 3);
}

/**
 * Obtiene posiciones de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @param {number} from - Timestamp de inicio
 * @param {number} to - Timestamp de fin
 * @param {number} limit - Límite de resultados
 * @returns {Promise<Array>} - Lista de posiciones
 */
async function getDevicePositions(deviceId, from, to, limit = 100) {
  return exponentialBackoff(async () => {
    const token = await getAuthToken();
    
    const params = new URLSearchParams();
    
    if (from) {
      params.append('from', from);
    }
    
    if (to) {
      params.append('to', to);
    }
    
    if (limit) {
      params.append('limit', limit);
    }
    
    const response = await apiClient.get(`/devices/positions/${deviceId}`, {
      headers: {
        Authorization: `Bearer ${token}`
      },
      params
    });
    
    return response.data;
  }, 3);
}

/**
 * Obtiene la última posición de un dispositivo
 * @param {string} deviceId - ID del dispositivo
 * @returns {Promise<Object>} - Última posición
 */
async function getDeviceLastPosition(deviceId) {
  return exponentialBackoff(async () => {
    const token = await getAuthToken();
    
    const response = await apiClient.get(`/devices/last-position/${deviceId}`, {
      headers: {
        Authorization: `Bearer ${token}`
      }
    });
    
    return response.data;
  }, 3);
}

/**
 * Verifica si un dispositivo está conectado
 * @param {string} deviceId - ID del dispositivo
 * @returns {Promise<Object>} - Estado de conexión
 */
async function isDeviceAlive(deviceId) {
  return exponentialBackoff(async () => {
    const token = await getAuthToken();
    
    const response = await apiClient.get(`/devices/isalive/${deviceId}`, {
      headers: {
        Authorization: `Bearer ${token}`
      }
    });
    
    return response.data;
  }, 3);
}

module.exports = {
  getDevices,
  getDevice,
  getDevicePositions,
  getDeviceLastPosition,
  isDeviceAlive
};
