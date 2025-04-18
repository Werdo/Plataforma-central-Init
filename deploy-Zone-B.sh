#!/bin/bash

# Script para desplegar la Zona B (Backend) de la Plataforma Centralizada
# Para Ubuntu 24.04 LTS

set -e  # Salir en caso de error

# Colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root."
    exit 1
fi

# Directorios base
BASE_DIR="/opt/central-platform"
BACKEND_DIR="${BASE_DIR}/backend"

# Crear directorios base
log_info "Creando directorios base..."
mkdir -p ${BASE_DIR}
mkdir -p ${BACKEND_DIR}/{api-rest,websocket,alerts}

# Variables de entorno para el despliegue
POSTGRES_PASSWORD="central$ecureP4ss"
MONGO_PASSWORD="central$ecureM0ngo"
REDIS_PASSWORD="central$ecureR3dis"

# Instalar dependencias del sistema
log_info "Instalando dependencias del sistema..."
apt-get update
apt-get install -y python3 python3-pip python3-venv nodejs npm postgresql mongodb redis docker.io docker-compose

# 1. Configurar API REST (FastAPI/Python)
log_info "Configurando API REST (FastAPI/Python)..."

# Crear estructura de directorios para API REST
mkdir -p ${BACKEND_DIR}/api-rest/app/{api,core,db,services,repositories,clients,utils}
mkdir -p ${BACKEND_DIR}/api-rest/tests/{test_api,test_services}
mkdir -p ${BACKEND_DIR}/api-rest/alembic/versions

# Crear entorno virtual Python
python3 -m venv ${BACKEND_DIR}/api-rest/venv
source ${BACKEND_DIR}/api-rest/venv/bin/activate

# Crear requirements.txt
cat > ${BACKEND_DIR}/api-rest/requirements.txt << 'EOF'
fastapi>=0.85.0
uvicorn>=0.18.0
sqlalchemy>=1.4.41
alembic>=1.8.1
pydantic>=1.10.2
python-jose>=3.3.0
passlib>=1.7.4
bcrypt>=4.0.0
python-multipart>=0.0.5
python-dotenv>=0.21.0
aiohttp>=3.8.3
asyncio>=3.4.3
motor>=3.0.0
redis>=4.3.4
psycopg2-binary>=2.9.3
pymongo>=4.2.0
pytest>=7.0.0
pytest-asyncio>=0.19.0
httpx>=0.23.0
EOF

# Instalar dependencias Python
pip install -r ${BACKEND_DIR}/api-rest/requirements.txt

# Crear archivo main.py
cat > ${BACKEND_DIR}/api-rest/app/main.py << 'EOF'
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from typing import List, Optional

from app.api import auth, users, devices, alerts, analytics, credentials
from app.core import config, security
from app.db.session import engine, SessionLocal
from app.db import models, schemas

# Crear tablas en la base de datos
models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Plataforma Centralizada API",
    description="API para la Plataforma Centralizada de Información",
    version="1.0.0"
)

# Configuración CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.ALLOW_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(auth.router, prefix="/api/v1/auth", tags=["Authentication"])
app.include_router(users.router, prefix="/api/v1/users", tags=["Users"])
app.include_router(devices.router, prefix="/api/v1/devices", tags=["Devices"])
app.include_router(alerts.router, prefix="/api/v1/alerts", tags=["Alerts"])
app.include_router(analytics.router, prefix="/api/v1/analytics", tags=["Analytics"])
app.include_router(credentials.router, prefix="/api/v1/credentials", tags=["Credentials"])

# Health check
@app.get("/health", tags=["Health"])
def health_check():
    return {"status": "ok"}
EOF

# Crear archivo config.py en core
cat > ${BACKEND_DIR}/api-rest/app/core/config.py << 'EOF'
import os
from dotenv import load_dotenv
from typing import List, Optional

load_dotenv()

# Configuración de la base de datos
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost/central_platform")
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017/central_platform")

# Configuración de seguridad
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))

# Configuración de autenticación
OAUTH2_CLIENT_ID = os.getenv("OAUTH2_CLIENT_ID")
OAUTH2_CLIENT_SECRET = os.getenv("OAUTH2_CLIENT_SECRET")
OAUTH2_REDIRECT_URL = os.getenv("OAUTH2_REDIRECT_URL")
AZURE_TENANT_ID = os.getenv("AZURE_TENANT_ID", "common")

# Configuración CORS
ALLOW_ORIGINS = os.getenv("ALLOW_ORIGINS", "*").split(",")

# Configuración Redis
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Configuración de la aplicación
APP_ENV = os.getenv("APP_ENV", "development")
DEBUG = APP_ENV == "development"
EOF

# Crear archivo __init__.py para cada directorio de Python
touch ${BACKEND_DIR}/api-rest/app/__init__.py
touch ${BACKEND_DIR}/api-rest/app/api/__init__.py
touch ${BACKEND_DIR}/api-rest/app/core/__init__.py
touch ${BACKEND_DIR}/api-rest/app/db/__init__.py
touch ${BACKEND_DIR}/api-rest/app/services/__init__.py
touch ${BACKEND_DIR}/api-rest/app/repositories/__init__.py
touch ${BACKEND_DIR}/api-rest/app/clients/__init__.py
touch ${BACKEND_DIR}/api-rest/app/utils/__init__.py
touch ${BACKEND_DIR}/api-rest/tests/__init__.py
touch ${BACKEND_DIR}/api-rest/tests/test_api/__init__.py
touch ${BACKEND_DIR}/api-rest/tests/test_services/__init__.py

# Crear archivo de modelos
cat > ${BACKEND_DIR}/api-rest/app/db/models.py << 'EOF'
from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, JSON, Table
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

# Tabla de asociación usuario-grupo
user_group = Table(
    "user_group",
    Base.metadata,
    Column("user_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column("group_id", Integer, ForeignKey("groups.id"), primary_key=True)
)

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    email = Column(String, unique=True, index=True)
    full_name = Column(String)
    hashed_password = Column(String)
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)
    is_sso = Column(Boolean, default=False)
    role = Column(String, default="user")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relaciones
    devices = relationship("Device", back_populates="owner")
    groups = relationship("Group", secondary=user_group, back_populates="users")

class Group(Base):
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String, nullable=True)
    created_by = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relaciones
    users = relationship("User", secondary=user_group, back_populates="groups")
    devices = relationship("Device", back_populates="group")

class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, index=True)
    deviceId = Column(String, unique=True, index=True)
    name = Column(String, index=True)
    type = Column(String, index=True)
    status = Column(String, index=True, default="offline")
    model = Column(String, nullable=True)
    manufacturer = Column(String, nullable=True)
    firmware = Column(String, nullable=True)
    metadata = Column(JSON, nullable=True)
    owner_id = Column(Integer, ForeignKey("users.id"))
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relaciones
    owner = relationship("User", back_populates="devices")
    group = relationship("Group", back_populates="devices")
EOF

# Crear archivo schemas.py
cat > ${BACKEND_DIR}/api-rest/app/db/schemas.py << 'EOF'
from typing import List, Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, EmailStr

# Base User schemas
class UserBase(BaseModel):
    username: str
    email: EmailStr
    full_name: str

class UserCreate(UserBase):
    password: str
    role: Optional[str] = "user"
    is_superuser: Optional[bool] = False
    is_sso: Optional[bool] = False

class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None
    password: Optional[str] = None
    is_active: Optional[bool] = None
    role: Optional[str] = None

class User(UserBase):
    id: int
    is_active: bool
    is_superuser: bool
    role: str
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        orm_mode = True

# Base Device schemas
class DeviceBase(BaseModel):
    deviceId: str
    name: str
    type: str
    model: Optional[str] = None
    manufacturer: Optional[str] = None
    firmware: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class DeviceCreate(DeviceBase):
    group_id: Optional[int] = None

class DeviceUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    status: Optional[str] = None
    model: Optional[str] = None
    manufacturer: Optional[str] = None
    firmware: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    group_id: Optional[int] = None

class Device(DeviceBase):
    id: int
    status: str
    owner_id: int
    group_id: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        orm_mode = True
EOF

# Crear archivo session.py
cat > ${BACKEND_DIR}/api-rest/app/db/session.py << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from app.core.config import DATABASE_URL

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Función para obtener sesión de base de datos
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

# Crear archivo device_service.py
cat > ${BACKEND_DIR}/api-rest/app/services/device_service.py << 'EOF'
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
from datetime import datetime

from app.db import models, schemas
from app.repositories import device_repository
from app.core import exceptions
from app.services import redis_service

def get_devices(
    db: Session, 
    skip: int = 0, 
    limit: int = 100, 
    search: Optional[str] = None,
    status: Optional[str] = None,
    type: Optional[str] = None,
    group: Optional[str] = None,
    user_id: Optional[int] = None
) -> List[models.Device]:
    """
    Retrieve devices with optional filtering
    """
    return device_repository.get_devices(
        db, 
        skip=skip, 
        limit=limit, 
        search=search,
        status=status,
        type=type,
        group=group,
        user_id=user_id
    )

def get_device(db: Session, device_id: str) -> Optional[models.Device]:
    """
    Get a device by ID
    """
    device = device_repository.get_device(db, device_id=device_id)
    if not device:
        return None
    return device

def create_device(db: Session, device: schemas.DeviceCreate, user_id: int) -> models.Device:
    """
    Create a new device
    """
    # Check if device already exists
    existing_device = device_repository.get_device_by_device_id(db, device_id=device.deviceId)
    if existing_device:
        raise exceptions.DeviceAlreadyExistsError(device.deviceId)
    
    # Create device
    db_device = device_repository.create_device(db, device=device, user_id=user_id)
    
    # Publish event
    redis_service.publish_event("device:created", {
        "deviceId": db_device.deviceId,
        "userId": user_id,
        "timestamp": datetime.utcnow().isoformat()
    })
    
    return db_device
EOF

# Crear archivo devices.py para API
cat > ${BACKEND_DIR}/api-rest/app/api/devices.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db.session import get_db
from app.db import models, schemas
from app.core.security import get_current_user
from app.services import device_service, telemetry_service

router = APIRouter()

@router.get("/", response_model=List[schemas.Device])
def get_devices(
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    status: Optional[str] = None,
    type: Optional[str] = None,
    group: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Get all devices with optional filtering
    """
    return device_service.get_devices(
        db, 
        skip=skip, 
        limit=limit, 
        search=search, 
        status=status, 
        type=type, 
        group=group,
        user_id=current_user.id
    )

@router.post("/", response_model=schemas.Device, status_code=status.HTTP_201_CREATED)
def create_device(
    device: schemas.DeviceCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Create a new device
    """
    return device_service.create_device(db, device=device, user_id=current_user.id)
EOF

# Crear Dockerfile para API REST
cat > ${BACKEND_DIR}/api-rest/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Instalar dependencias
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código fuente
COPY . .

# Ejecutar migraciones si es necesario
ENV PYTHONPATH=/app

# Comando para iniciar la aplicación
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# Crear archivo .env
cat > ${BACKEND_DIR}/api-rest/.env << EOF
# Configuración general
APP_ENV=development
DEBUG=true

# Base de datos
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgresql:5432/central_platform
MONGODB_URI=mongodb://app_user:${MONGO_PASSWORD}@mongodb:27017/central_platform

# Seguridad
SECRET_KEY=$(openssl rand -hex 32)
ACCESS_TOKEN_EXPIRE_MINUTES=60

# SSO con Microsoft 365
OAUTH2_CLIENT_ID=
OAUTH2_CLIENT_SECRET=
OAUTH2_REDIRECT_URL=https://central-platform.local/oauth2/callback
AZURE_TENANT_ID=common

# CORS
ALLOW_ORIGINS=http://localhost:3000,https://central-platform.local

# Redis
REDIS_URL=redis://redis:6379/0

# Logging
LOG_LEVEL=info
EOF

# 2. Configurar WebSocket (Node.js)
log_info "Configurando WebSocket (Node.js)..."

# Crear estructura de directorios para WebSocket
mkdir -p ${BACKEND_DIR}/websocket/src/{config,models,utils,handlers,middleware,routes}

# Crear package.json
cat > ${BACKEND_DIR}/websocket/package.json << 'EOF'
{
  "name": "central-platform-websocket",
  "version": "1.0.0",
  "description": "WebSocket service for Central Platform",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js",
    "test": "jest",
    "lint": "eslint --ext .js src/"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.6.1",
    "ioredis": "^5.3.2",
    "mongoose": "^7.0.3",
    "jsonwebtoken": "^9.0.0",
    "dotenv": "^16.0.3",
    "winston": "^3.8.2"
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

# Crear server.js
cat > ${BACKEND_DIR}/websocket/src/server.js << 'EOF'
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const Redis = require('ioredis');
const mongoose = require('mongoose');
const logger = require('./utils/logger');
const config = require('./config');
const authMiddleware = require('./middleware/auth');

// Importar manejadores
const deviceHandler = require('./handlers/device');
const alertHandler = require('./handlers/alert');

// Inicializar express
const app = express();
const server = http.createServer(app);

// Configurar Socket.IO
const io = new Server(server, {
  cors: {
    origin: config.corsOrigins,
    methods: ['GET', 'POST'],
    credentials: true
  }
});

// Conexión a MongoDB
mongoose.connect(config.mongodb.uri, config.mongodb.options)
  .then(() => logger.info('Connected to MongoDB'))
  .catch(err => logger.error('MongoDB connection error:', err));

// Conexión a Redis
const redisClient = new Redis(config.redis.url);
const redisPubSub = new Redis(config.redis.url);

// Ruta de health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Middleware para autenticación de Socket.IO
io.use(authMiddleware);

// Conexión de clientes
io.on('connection', (socket) => {
  const userId = socket.user.id;
  logger.info(`User connected: ${userId}`);
  
  // Unirse a sala personal
  socket.join(`user:${userId}`);
  
  // Configurar manejadores de eventos
  deviceHandler(io, socket);
  alertHandler(io, socket);
  
  // Manejar desconexión
  socket.on('disconnect', () => {
    logger.info(`User disconnected: ${userId}`);
  });
});

// Suscribirse a eventos de Redis
redisPubSub.subscribe('alerts', 'device-status', 'system-events');

redisPubSub.on('message', (channel, message) => {
  try {
    const data = JSON.parse(message);
    
    switch (channel) {
      case 'alerts':
        // Emitir alerta a usuarios afectados
        if (data.userIds && Array.isArray(data.userIds)) {
          data.userIds.forEach(userId => {
            io.to(`user:${userId}`).emit('new-alert', data);
          });
        }
        break;
        
      case 'device-status':
        // Emitir cambio de estado a suscriptores del dispositivo
        io.to(`device:${data.deviceId}`).emit('device-status', data);
        break;
        
      case 'system-events':
        // Emitir evento del sistema a todos los usuarios
        io.emit('system-event', data);
        break;
    }
  } catch (err) {
    logger.error('Error processing Redis message:', err);
  }
});

// Iniciar servidor
const PORT = config.port || 3000;
server.listen(PORT, () => {
  logger.info(`WebSocket server running on port ${PORT}`);
});
EOF

# Crear archivo de configuración
cat > ${BACKEND_DIR}/websocket/src/config/index.js << 'EOF'
require('dotenv').config();

module.exports = {
  port: process.env.PORT || 3000,
  
  mongodb: {
    uri: process.env.MONGODB_URI || 'mongodb://localhost:27017/central_platform',
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 5000
    }
  },
  
  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379'
  },
  
  jwt: {
    secret: process.env.JWT_SECRET || 'your-secret-key',
    expiresIn: process.env.JWT_EXPIRES_IN || '1h'
  },
  
  corsOrigins: process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : ['http://localhost:3000']
};
EOF

# Crear archivo de logger
cat > ${BACKEND_DIR}/websocket/src/utils/logger.js << 'EOF'
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({
      format: 'YYYY-MM-DD HH:mm:ss'
    }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
  ),
  defaultMeta: { service: 'websocket-service' },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(
          info => `${info.timestamp} ${info.level}: ${info.message}`
        )
      )
    })
  ]
});

module.exports = logger;
EOF

# Crear middleware de autenticación
cat > ${BACKEND_DIR}/websocket/src/middleware/auth.js << 'EOF'
const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');
const config = require('../config');

module.exports = (socket, next) => {
  const token = socket.handshake.auth.token;
  
  if (!token) {
    return next(new Error('Authentication error: Token required'));
  }
  
  try {
    const decoded = jwt.verify(token, config.jwt.secret);
    socket.user = decoded;
    next();
  } catch (err) {
    logger.error('Socket authentication error:', err);
    next(new Error('Authentication error: Invalid token'));
  }
};
EOF

# Crear manejador de dispositivos
cat > ${BACKEND_DIR}/websocket/src/handlers/device.js << 'EOF'
const logger = require('../utils/logger');
const Device = require('../models/device');
const { publishToRedis } = require('../services/redis');

module.exports = function deviceHandler(io, socket) {
  // Suscribirse a dispositivos
  socket.on('subscribe-devices', async (deviceIds) => {
    try {
      // Verificar permisos para estos dispositivos
      const user = socket.user;
      const authorizedDevices = await Device.find({
        deviceId: { $in: deviceIds },
        $or: [
          { ownerId: user.id },
          { userIds: user.id }
        ]
      }).select('deviceId');
      
      const authorizedDeviceIds = authorizedDevices.map(dev => dev.deviceId);
      
      // Unirse a salas de dispositivos autorizados
      authorizedDeviceIds.forEach(deviceId => {
        socket.join(`device:${deviceId}`);
      });
      
      logger.info(`User ${user.id} subscribed to devices: ${authorizedDeviceIds.join(', ')}`);
      
      // Confirmar suscripción
      socket.emit('devices-subscribed', {
        deviceIds: authorizedDeviceIds
      });
    } catch (error) {
      logger.error(`Error subscribing to devices: ${error.message}`);
      socket.emit('error', {
        message: 'Failed to subscribe to devices',
        code: 'SUBSCRIPTION_FAILED'
      });
    }
  });
  
  // Recibir datos de dispositivos
  socket.on('device-data', async (data) => {
    try {
      // Validar datos
      if (!data.deviceId) {
        throw new Error('Device ID is required');
      }
      
      // Verificar permisos para este dispositivo
      // ...
      
      // Emitir a todos los suscriptores del dispositivo
      io.to(`device:${data.deviceId}`).emit('device-update', data);
      
      // Publicar en Redis para otros servicios
      publishToRedis('device-data', data);
      
      logger.debug(`Device data received for ${data.deviceId}`);
    } catch (error) {
      logger.error(`Error processing device data: ${error.message}`);
      socket.emit('error', {
        message: 'Failed to process device data',
        code: 'DATA_PROCESSING_FAILED'
      });
    }
  });
  
  // Enviar comando a dispositivo
  socket.on('send-command', async (command) => {
    try {
      // Validar comando
      if (!command.deviceId || !command.action) {
        throw new Error('Device ID and action are required');
      }
      
      // Verificar permisos para este dispositivo
      // ...
      
      // Publicar comando en Redis
      publishToRedis('device-commands', {
        ...command,
        userId: socket.user.id,
        timestamp: new Date().toISOString()
      });
      
      // Confirmar envío
      socket.emit('command-sent', {
        deviceId: command.deviceId,
        commandId: command.commandId || Date.now().toString(),
        status: 'sent'
      });
      
      logger.info(`Command sent to device ${command.deviceId}: ${command.action}`);
    } catch (error) {
      logger.error(`Error sending command: ${error.message}`);
      socket.emit('error', {
        message: 'Failed to send command',
        code: 'COMMAND_FAILED'
      });
    }
  });
};
EOF

# Crear manejador de alertas
cat > ${BACKEND_DIR}/websocket/src/handlers/alert.js << 'EOF'
const logger = require('../utils/logger');

module.exports = function alertHandler(io, socket) {
  // Suscribirse a alertas
  socket.on('subscribe-alerts', async () => {
    try {
      const user = socket.user;
      
      // El usuario ya está suscrito a su sala personal al conectarse
      // socket.join(`user:${user.id}`);
      
      logger.info(`User ${user.id} subscribed to alerts`);
      
      // Enviar confirmar suscripción
      socket.emit('alerts-subscribed', {
        userId: user.id
      });
    } catch (error) {
      logger.error(`Error subscribing to alerts: ${error.message}`);
      socket.emit('error', {
        message: 'Failed to subscribe to alerts',
        code: 'ALERT_SUBSCRIPTION_FAILED'
      });
    }
  });
  
  // Reconocer alerta
  socket.on('acknowledge-alert', async (alertId) => {
    try {
      const user = socket.user;
      
      // Aquí iría la lógica para marcar la alerta como reconocida
      // y actualizar en la base de datos
      
      // Notificar a otros usuarios interesados en esta alerta
      socket.to(`alert:${alertId}`).emit('alert-acknowledged', {
        alertId,
        acknowledgedBy: user.id,
        acknowledgedAt: new Date().toISOString()
      });
      
      logger.info(`Alert ${alertId} acknowledged by user ${user.id}`);
    } catch (error) {
      logger.error(`Error acknowledging alert: ${error.message}`);
      socket.emit('error', {
        message: 'Failed to acknowledge alert',
        code: 'ACKNOWLEDGE_FAILED'
      });
    }
  });
};
EOF

# Crear modelo de dispositivo
cat > ${BACKEND_DIR}/websocket/src/models/device.js << 'EOF'
const mongoose = require('mongoose');

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
    enum: ['online', 'offline', 'maintenance', 'error'],
    default: 'offline',
    index: true
  },
  ownerId: {
    type: String,
    required: true,
    index: true
  },
  userIds: [{
    type: String,
    index: true
  }],
  location: {
    type: {
      type: String,
      enum: ['Point'],
      default: 'Point'
    },
    coordinates: {
      type: [Number],
      default: [0, 0]
    }
  },
  lastActivity: {
    type: Date,
    default: Date.now
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, { timestamps: true });

// Crear índice geoespacial
deviceSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('Device', deviceSchema);
EOF

# Crear Dockerfile para WebSocket
cat > ${BACKEND_DIR}/websocket/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copiar package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm ci --only=production

# Copiar código fuente
COPY . .

# Exponer puerto
EXPOSE 3000

# Comando para iniciar la aplicación
CMD ["node", "src/server.js"]
EOF

# Crear archivo .env para WebSocket
cat > ${BACKEND_DIR}/websocket/.env << EOF
# Configuración general
NODE_ENV=development
PORT=3000

# Seguridad
JWT_SECRET=$(openssl rand -hex 32)

# MongoDB
MONGODB_URI=mongodb://app_user:${MONGO_PASSWORD}@mongodb:27017/central_platform
MONGODB_POOL_SIZE=10

# Redis
REDIS_URL=redis://redis:6379/0

# CORS
CORS_ORIGINS=http://localhost:3000,https://central-platform.local

# Logging
LOG_LEVEL=info
EOF

# 3. Configurar Servicio de Alertas (Node.js)
log_info "Configurando Servicio de Alertas (Node.js)..."

# Crear estructura de directorios para Alertas
mkdir -p ${BACKEND_DIR}/alerts/src/{config,models,services,queues,processors,utils,routes,middleware}

# Crear package.json
cat > ${BACKEND_DIR}/alerts/package.json << 'EOF'
{
  "name": "central-platform-alerts",
  "version": "1.0.0",
  "description": "Alert service for Central Platform",
  "main": "src/alertService.js",
  "scripts": {
    "start": "node src/alertService.js",
    "dev": "nodemon src/alertService.js",
    "test": "jest",
    "lint": "eslint --ext .js src/"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "mongoose": "^7.0.3",
    "bull": "^4.10.4",
    "jsonwebtoken": "^9.0.0",
    "dotenv": "^16.0.3",
    "winston": "^3.8.2",
    "@bull-board/api": "^5.0.0",
    "@bull-board/express": "^5.0.0",
    "nodemailer": "^6.9.1"
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

# Crear alertService.js
cat > ${BACKEND_DIR}/alerts/src/alertService.js << 'EOF'
const express = require('express');
const mongoose = require('mongoose');
const Redis = require('ioredis');
const { createBullBoard } = require('@bull-board/api');
const { BullAdapter } = require('@bull-board/api/bullAdapter');
const { ExpressAdapter } = require('@bull-board/express');
const Queue = require('bull');
const logger = require('./utils/logger');
const config = require('./config');

// Importar modelos y procesadores
const alertProcessor = require('./processors/alertProcessor');
const notificationProcessor = require('./processors/notificationProcessor');

// Importar rutas
const alertRoutes = require('./routes/alerts');
const ruleRoutes = require('./routes/rules');
const telemetryRoutes = require('./routes/telemetry');

// Inicializar express
const app = express();
app.use(express.json());

// Conexión a Redis
const redisClient = new Redis(config.redis.url);
const redisPub = new Redis(config.redis.url);

// Conexión a MongoDB
mongoose.connect(config.mongodb.uri, config.mongodb.options)
  .then(() => logger.info('Connected to MongoDB'))
  .catch(err => logger.error('MongoDB connection error:', err));

// Configurar colas de procesamiento
const alertProcessingQueue = new Queue('alert-processing', {
  redis: config.redis
});

const alertNotificationQueue = new Queue('alert-notification', {
  redis: config.redis
});

// Configurar Bull Board (UI para monitorear colas)
const serverAdapter = new ExpressAdapter();
createBullBoard({
  queues: [
    new BullAdapter(alertProcessingQueue),
    new BullAdapter(alertNotificationQueue)
  ],
  serverAdapter
});
serverAdapter.setBasePath('/admin/queues');
app.use('/admin/queues', serverAdapter.getRouter());

// Configurar procesadores
alertProcessingQueue.process(alertProcessor);
alertNotificationQueue.process(notificationProcessor);

// Rutas API
app.use('/api/v1/alerts', alertRoutes);
app.use('/api/v1/rules', ruleRoutes);
app.use('/api/v1/telemetry', telemetryRoutes);

// Ruta de health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Suscribirse a telemetría desde Redis
redisClient.subscribe('telemetry');

redisClient.on('message', async (channel, message) => {
  if (channel === 'telemetry') {
    try {
      const telemetryData = JSON.parse(message);
      
      // Encolar para procesamiento
      await alertProcessingQueue.add({ telemetryData });
      
      logger.debug(`Telemetry data enqueued for processing: ${telemetryData.deviceId}`);
    } catch (error) {
      logger.error('Error processing telemetry from Redis:', error);
    }
  }
});

// Iniciar servidor
const PORT = config.port || 3001;
app.listen(PORT, () => {
  logger.info(`Alert service running on port ${PORT}`);
});
EOF

# Crear archivo de configuración
cat > ${BACKEND_DIR}/alerts/src/config/index.js << 'EOF'
require('dotenv').config();

module.exports = {
  port: process.env.PORT || 3001,
  
  mongodb: {
    uri: process.env.MONGODB_URI || 'mongodb://localhost:27017/central_platform',
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 5000
    }
  },
  
  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379'
  },
  
  jwt: {
    secret: process.env.JWT_SECRET || 'your-secret-key',
    expiresIn: process.env.JWT_EXPIRES_IN || '1h'
  },
  
  email: {
    smtp: {
      host: process.env.SMTP_HOST || 'smtp.example.com',
      port: parseInt(process.env.SMTP_PORT, 10) || 587,
      secure: process.env.SMTP_SECURE === 'true',
      auth: {
        user: process.env.SMTP_USER || '',
        pass: process.env.SMTP_PASS || ''
      }
    },
    from: process.env.EMAIL_FROM || 'alerts@central-platform.local'
  },
  
  alert: {
    cooldownDefault: parseInt(process.env.ALERT_COOLDOWN_DEFAULT, 10) || 300, // 5 minutos
    batchSize: parseInt(process.env.ALERT_BATCH_SIZE, 10) || 100
  }
};
EOF

# Crear archivo de logger
cat > ${BACKEND_DIR}/alerts/src/utils/logger.js << 'EOF'
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({
      format: 'YYYY-MM-DD HH:mm:ss'
    }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
  ),
  defaultMeta: { service: 'alert-service' },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(
          info => `${info.timestamp} ${info.level}: ${info.message}`
        )
      )
    })
  ]
});

module.exports = logger;
EOF

# Crear evaluador de condiciones
cat > ${BACKEND_DIR}/alerts/src/utils/conditionEvaluator.js << 'EOF'
/**
 * Evalúa una condición contra datos de telemetría
 * @param {Object} condition - Condición a evaluar
 * @param {Object} telemetryData - Datos de telemetría
 * @returns {boolean} - Resultado de la evaluación
 */
function evaluateCondition(condition, telemetryData) {
  // Si es una condición compuesta (AND/OR)
  if (condition.operator === 'AND' && Array.isArray(condition.conditions)) {
    return condition.conditions.every(subCondition => 
      evaluateCondition(subCondition, telemetryData)
    );
  }
  
  if (condition.operator === 'OR' && Array.isArray(condition.conditions)) {
    return condition.conditions.some(subCondition => 
      evaluateCondition(subCondition, telemetryData)
    );
  }
  
  // Si es una condición simple
  const { field, operator, value } = condition;
  
  // Obtener el valor del campo desde los datos de telemetría
  const fieldValue = getFieldValue(telemetryData, field);
  
  // Si el campo no existe
  if (fieldValue === undefined) {
    return false;
  }
  
  // Evaluar según el operador
  switch (operator) {
    case '==':
      return fieldValue == value;
    case '===':
      return fieldValue === value;
    case '!=':
      return fieldValue != value;
    case '!==':
      return fieldValue !== value;
    case '>':
      return fieldValue > value;
    case '>=':
      return fieldValue >= value;
    case '<':
      return fieldValue < value;
    case '<=':
      return fieldValue <= value;
    case 'contains':
      return String(fieldValue).includes(String(value));
    case 'startsWith':
      return String(fieldValue).startsWith(String(value));
    case 'endsWith':
      return String(fieldValue).endsWith(String(value));
    case 'matches':
      return new RegExp(value).test(String(fieldValue));
    case 'exists':
      return fieldValue !== undefined && fieldValue !== null;
    default:
      return false;
  }
}

/**
 * Obtiene el valor de un campo anidado desde un objeto
 * @param {Object} obj - Objeto que contiene el campo
 * @param {string} path - Ruta al campo (ej: "data.temperature")
 * @returns {*} - Valor del campo o undefined si no existe
 */
function getFieldValue(obj, path) {
  const parts = path.split('.');
  let value = obj;
  
  for (const part of parts) {
    if (value === null || value === undefined || typeof value !== 'object') {
      return undefined;
    }
    value = value[part];
  }
  
  return value;
}

module.exports = {
  evaluateCondition,
  getFieldValue
};
EOF

# Crear modelo de regla de alerta
cat > ${BACKEND_DIR}/alerts/src/models/alertRule.js << 'EOF'
const mongoose = require('mongoose');

const alertRuleSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true
  },
  description: {
    type: String,
    trim: true
  },
  deviceId: {
    type: String,
    sparse: true,
    index: true
  },
  deviceType: {
    type: String,
    sparse: true,
    index: true
  },
  condition: {
    type: mongoose.Schema.Types.Mixed,
    required: true
  },
  message: {
    type: String,
    required: true
  },
  severity: {
    type: String,
    enum: ['info', 'warning', 'error', 'critical'],
    default: 'warning'
  },
  enabled: {
    type: Boolean,
    default: true,
    index: true
  },
  notifications: {
    email: {
      type: Boolean,
      default: false
    },
    sms: {
      type: Boolean,
      default: false
    },
    push: {
      type: Boolean,
      default: true
    },
    webhook: {
      type: String
    }
  },
  cooldown: {
    type: Number,
    default: 300, // 5 minutos en segundos
    min: 0
  },
  createdBy: {
    type: String,
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

module.exports = mongoose.model('AlertRule', alertRuleSchema);
EOF

# Crear modelo de alerta
cat > ${BACKEND_DIR}/alerts/src/models/alert.js << 'EOF'
const mongoose = require('mongoose');

const alertSchema = new mongoose.Schema({
  ruleId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AlertRule',
    required: true,
    index: true
  },
  deviceId: {
    type: String,
    required: true,
    index: true
  },
  message: {
    type: String,
    required: true
  },
  severity: {
    type: String,
    enum: ['info', 'warning', 'error', 'critical'],
    default: 'warning',
    index: true
  },
  status: {
    type: String,
    enum: ['active', 'acknowledged', 'resolved'],
    default: 'active',
    index: true
  },
  telemetryData: {
    type: mongoose.Schema.Types.Mixed,
    required: true
  },
  acknowledgedBy: {
    type: String,
    index: true
  },
  acknowledgedAt: {
    type: Date
  },
  resolvedAt: {
    type: Date
  },
  notifiedUsers: [{
    type: String
  }],
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  }
});

module.exports = mongoose.model('Alert', alertSchema);
EOF

# Crear procesador de alertas
cat > ${BACKEND_DIR}/alerts/src/processors/alertProcessor.js << 'EOF'
const logger = require('../utils/logger');
const AlertRule = require('../models/alertRule');
const Alert = require('../models/alert');
const Device = require('../models/device');
const { publishToRedis } = require('../services/redis');
const { evaluateCondition } = require('../utils/conditionEvaluator');

module.exports = async (job) => {
  const { telemetryData } = job.data;
  logger.debug(`Processing telemetry for device ${telemetryData.deviceId}`);
  
  try {
    // Obtener todas las reglas aplicables al dispositivo
    const rules = await AlertRule.find({
      enabled: true,
      $or: [
        { deviceId: telemetryData.deviceId },
        { deviceType: telemetryData.deviceType }
      ]
    });
    
    for (const rule of rules) {
      // Evaluar condición de la regla
      const condition = rule.condition;
      const meetsCondition = evaluateCondition(condition, telemetryData);
      
      if (meetsCondition) {
        // Comprobar cooldown si existe
        if (rule.cooldown) {
          const lastAlert = await Alert.findOne({
            ruleId: rule._id,
            deviceId: telemetryData.deviceId,
            createdAt: { 
              $gte: new Date(Date.now() - rule.cooldown * 1000) 
            }
          });
          
          if (lastAlert) {
            logger.debug(`Alert for rule ${rule._id} skipped due to cooldown`);
            continue;
          }
        }
        
        // Crear alerta
        const alert = new Alert({
          ruleId: rule._id,
          deviceId: telemetryData.deviceId,
          message: rule.message,
          severity: rule.severity,
          status: 'active',
          telemetryData: telemetryData
        });
        
        await alert.save();
        logger.info(`Alert created: ${rule.name} for device ${telemetryData.deviceId}`);
        
        // Obtener dispositivo para detalles adicionales
        const device = await Device.findOne({ deviceId: telemetryData.deviceId });
        const deviceName = device ? device.name : telemetryData.deviceId;
        const userIds = device ? device.userIds : [];
        
        // Publicar alerta para WebSocket
        publishToRedis('alerts', {
          id: alert._id.toString(),
          ruleId: rule._id.toString(),
          ruleName: rule.name,
          deviceId: telemetryData.deviceId,
          deviceName: deviceName,
          message: rule.message,
          severity: rule.severity,
          timestamp: alert.createdAt,
          userIds: userIds
        });
        
        // TODO: Aquí podríamos tener la lógica para actualizar el estado del dispositivo si es necesario
      }
    }
    
    return { processed: true };
  } catch (error) {
    logger.error('Error processing alert rules:', error);
    throw error;
  }
};
EOF

# Crear procesador de notificaciones
cat > ${BACKEND_DIR}/alerts/src/processors/notificationProcessor.js << 'EOF'
const logger = require('../utils/logger');
const config = require('../config');
const nodemailer = require('nodemailer');

// Configurar transporte de email
const emailTransport = nodemailer.createTransport(config.email.smtp);

module.exports = async (job) => {
  const { alert, notificationType, recipients } = job.data;
  logger.debug(`Processing notification for alert ${alert.id}, type: ${notificationType}`);
  
  try {
    switch (notificationType) {
      case 'email':
        await sendEmailNotifications(alert, recipients);
        break;
      case 'push':
        // Implementación futura
        logger.info('Push notifications not implemented yet');
        break;
      case 'sms':
        // Implementación futura
        logger.info('SMS notifications not implemented yet');
        break;
      case 'webhook':
        if (alert.rule && alert.rule.notifications.webhook) {
          await sendWebhookNotification(alert, alert.rule.notifications.webhook);
        }
        break;
      default:
        logger.warn(`Unknown notification type: ${notificationType}`);
        break;
    }
    
    return { notified: true, type: notificationType };
  } catch (error) {
    logger.error(`Error sending ${notificationType} notification:`, error);
    throw error;
  }
};

// Función para enviar notificaciones por email
async function sendEmailNotifications(alert, recipients) {
  if (!recipients || recipients.length === 0) {
    logger.warn('No recipients for email notification');
    return;
  }
  
  const severityColors = {
    info: '#3498db',
    warning: '#f39c12',
    error: '#e74c3c',
    critical: '#c0392b'
  };
  
  const emailBody = `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #2c3e50;">Alerta de la Plataforma Centralizada</h2>
      <div style="padding: 15px; background-color: ${severityColors[alert.severity] || '#f8f9fa'}; color: white; border-radius: 5px;">
        <h3 style="margin-top: 0;">${alert.message}</h3>
        <p><strong>Dispositivo:</strong> ${alert.deviceName || alert.deviceId}</p>
        <p><strong>Severidad:</strong> ${alert.severity.toUpperCase()}</p>
        <p><strong>Fecha:</strong> ${new Date(alert.timestamp).toLocaleString()}</p>
      </div>
      <div style="margin-top: 20px;">
        <p>Datos de telemetría:</p>
        <pre style="background-color: #f8f9fa; padding: 10px; border-radius: 5px; overflow: auto;">${JSON.stringify(alert.telemetryData, null, 2)}</pre>
      </div>
      <div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #7f8c8d;">
        <p>Este es un mensaje automático, por favor no responda a este correo.</p>
      </div>
    </div>
  `;
  
  try {
    const mailOptions = {
      from: config.email.from,
      to: recipients.join(','),
      subject: `[${alert.severity.toUpperCase()}] Alerta: ${alert.message}`,
      html: emailBody
    };
    
    const info = await emailTransport.sendMail(mailOptions);
    logger.info(`Email notification sent: ${info.messageId}`);
    return true;
  } catch (error) {
    logger.error('Error sending email notification:', error);
    throw error;
  }
}

// Función para enviar notificaciones por webhook
async function sendWebhookNotification(alert, webhookUrl) {
  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(alert)
    });
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    logger.info(`Webhook notification sent to ${webhookUrl}`);
    return true;
  } catch (error) {
    logger.error(`Error sending webhook notification to ${webhookUrl}:`, error);
    throw error;
  }
}
EOF

# Crear rutas de alertas
cat > ${BACKEND_DIR}/alerts/src/routes/alerts.js << 'EOF'
const express = require('express');
const router = express.Router();
const Alert = require('../models/alert');
const logger = require('../utils/logger');

// Middleware de autenticación
const authMiddleware = require('../middleware/auth');

// Obtener todas las alertas (con filtros)
router.get('/', authMiddleware, async (req, res) => {
  try {
    const {
      deviceId,
      severity,
      status,
      from,
      to,
      limit = 100,
      skip = 0
    } = req.query;
    
    const query = {};
    
    if (deviceId) {
      query.deviceId = deviceId;
    }
    
    if (severity) {
      query.severity = severity;
    }
    
    if (status) {
      query.status = status;
    }
    
    if (from || to) {
      query.createdAt = {};
      if (from) {
        query.createdAt.$gte = new Date(from);
      }
      if (to) {
        query.createdAt.$lte = new Date(to);
      }
    }
    
    const alerts = await Alert.find(query)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .populate('ruleId', 'name description');
      
    const total = await Alert.countDocuments(query);
    
    res.json({
      data: alerts,
      meta: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip)
      }
    });
  } catch (error) {
    logger.error('Error fetching alerts:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Obtener una alerta por ID
router.get('/:id', authMiddleware, async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id)
      .populate('ruleId', 'name description condition notifications');
      
    if (!alert) {
      return res.status(404).json({ error: 'Alert not found' });
    }
    
    res.json(alert);
  } catch (error) {
    logger.error(`Error fetching alert ${req.params.id}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Actualizar estado de alerta
router.patch('/:id/status', authMiddleware, async (req, res) => {
  try {
    const { status } = req.body;
    
    if (!status || !['active', 'acknowledged', 'resolved'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }
    
    const alert = await Alert.findById(req.params.id);
    
    if (!alert) {
      return res.status(404).json({ error: 'Alert not found' });
    }
    
    // Actualizar estado
    alert.status = status;
    
    // Si se está reconociendo la alerta
    if (status === 'acknowledged') {
      alert.acknowledgedBy = req.user.id;
      alert.acknowledgedAt = new Date();
    }
    
    // Si se está resolviendo la alerta
    if (status === 'resolved') {
      alert.resolvedAt = new Date();
    }
    
    await alert.save();
    
    res.json(alert);
  } catch (error) {
    logger.error(`Error updating alert status ${req.params.id}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
EOF

# Crear rutas de telemetría
cat > ${BACKEND_DIR}/alerts/src/routes/telemetry.js << 'EOF'
const express = require('express');
const router = express.Router();
const Queue = require('bull');
const logger = require('../utils/logger');
const config = require('../config');

// Middleware de autenticación
const authMiddleware = require('../middleware/auth');

// Cola de procesamiento de alertas
const alertProcessingQueue = new Queue('alert-processing', {
  redis: config.redis
});

// Recibir datos de telemetría manualmente
router.post('/', authMiddleware, async (req, res) => {
  try {
    const telemetryData = req.body;
    
    // Validación básica
    if (!telemetryData || !telemetryData.deviceId) {
      return res.status(400).json({ error: 'Invalid telemetry data. deviceId is required.' });
    }
    
    // Añadir a la cola de procesamiento
    await alertProcessingQueue.add({ telemetryData });
    
    logger.info(`Telemetry data manually submitted for device ${telemetryData.deviceId}`);
    
    res.status(202).json({ message: 'Telemetry received and queued for processing' });
  } catch (error) {
    logger.error('Error processing manual telemetry submission:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
EOF

# Crear middleware de autenticación
cat > ${BACKEND_DIR}/alerts/src/middleware/auth.js << 'EOF'
const jwt = require('jsonwebtoken');
const config = require('../config');
const logger = require('../utils/logger');

module.exports = (req, res, next) => {
  // Obtener el token del header Authorization
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  const token = authHeader.split(' ')[1];
  
  try {
    // Verificar el token
    const decoded = jwt.verify(token, config.jwt.secret);
    
    // Añadir la información del usuario a la request
    req.user = decoded;
    
    next();
  } catch (error) {
    logger.error('Authentication error:', error);
    return res.status(401).json({ error: 'Invalid token' });
  }
};
EOF

# Crear servicio Redis
cat > ${BACKEND_DIR}/alerts/src/services/redis.js << 'EOF'
const Redis = require('ioredis');
const config = require('../config');
const logger = require('../utils/logger');

// Cliente Redis para publicación
const redisClient = new Redis(config.redis.url);

/**
 * Publica un evento en Redis
 * @param {string} channel - Canal de publicación
 * @param {Object} data - Datos a publicar
 * @returns {Promise<void>}
 */
async function publishToRedis(channel, data) {
  try {
    await redisClient.publish(channel, JSON.stringify(data));
    logger.debug(`Published to Redis channel ${channel}`);
  } catch (error) {
    logger.error(`Error publishing to Redis channel ${channel}:`, error);
    throw error;
  }
}

module.exports = {
  publishToRedis
};
EOF

# Crear Dockerfile para Alertas
cat > ${BACKEND_DIR}/alerts/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copiar package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm ci --only=production

# Copiar código fuente
COPY . .

# Exponer puerto
EXPOSE 3001

# Comando para iniciar la aplicación
CMD ["node", "src/alertService.js"]
EOF

# Crear archivo .env para Alertas
cat > ${BACKEND_DIR}/alerts/.env << EOF
# Configuración general
NODE_ENV=development
PORT=3001

# Seguridad
JWT_SECRET=$(openssl rand -hex 32)

# MongoDB
MONGODB_URI=mongodb://app_user:${MONGO_PASSWORD}@mongodb:27017/central_platform
MONGODB_POOL_SIZE=10

# Redis
REDIS_URL=redis://redis:6379/0

# Colas (Bull)
QUEUE_CONCURRENCY=5
QUEUE_LIMITER_MAX=100
QUEUE_LIMITER_DURATION=1000

# Notificaciones
SMTP_HOST=smtp.central-platform.local
SMTP_PORT=587
SMTP_USER=alerts
SMTP_PASS=alertPassword
SMTP_FROM=alerts@central-platform.local

# Logging
LOG_LEVEL=info
EOF

# Crear docker-compose.yml para el despliegue integrado
cat > ${BASE_DIR}/docker-compose.yml << EOF
version: '3.8'

services:
  # API REST
  api-rest:
    build:
      context: ./backend/api-rest
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    env_file:
      - ./backend/api-rest/.env
    volumes:
      - ./backend/api-rest:/app
      - /app/venv
    depends_on:
      - postgresql
      - mongodb
      - redis
    restart: unless-stopped

  # WebSocket
  websocket:
    build:
      context: ./backend/websocket
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    env_file:
      - ./backend/websocket/.env
    volumes:
      - ./backend/websocket:/app
      - /app/node_modules
    depends_on:
      - mongodb
      - redis
    restart: unless-stopped

  # Alertas
  alerts:
    build:
      context: ./backend/alerts
      dockerfile: Dockerfile
    ports:
      - "3001:3001"
    env_file:
      - ./backend/alerts/.env
    volumes:
      - ./backend/alerts:/app
      - /app/node_modules
    depends_on:
      - mongodb
      - redis
    restart: unless-stopped

  # PostgreSQL
  postgresql:
    image: postgres:14-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: central_platform
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  # MongoDB
  mongodb:
    image: mongo:5.0
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
    volumes:
      - mongo_data:/data/db
      - ./mongodb-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    restart: unless-stopped

  # Redis
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  postgres_data:
  mongo_data:
  redis_data:
EOF

# Script de inicialización para MongoDB
cat > ${BASE_DIR}/mongodb-init.js << EOF
// MongoDB Init Script
db = db.getSiblingDB('admin');

// Authenticate as root
db.auth('root', '${MONGO_PASSWORD}');

// Create application database
db = db.getSiblingDB('central_platform');

// Create application user
db.createUser({
  user: 'app_user',
  pwd: '${MONGO_PASSWORD}',
  roles: [
    { role: 'readWrite', db: 'central_platform' }
  ]
});

// Create initial collections
db.createCollection('devices');
db.createCollection('telemetry');
db.createCollection('alerts');
db.createCollection('alertRules');

// Create indexes
db.devices.createIndex({ "deviceId": 1 }, { unique: true });
db.devices.createIndex({ "status": 1 });
db.devices.createIndex({ "type": 1 });
db.devices.createIndex({ "location.coordinates": "2dsphere" });

db.telemetry.createIndex({ "deviceId": 1, "timestamp": -1 });
db.telemetry.createIndex({ "timestamp": -1 });

db.alerts.createIndex({ "deviceId": 1, "status": 1 });
db.alerts.createIndex({ "severity": 1 });
db.alerts.createIndex({ "createdAt": -1 });

db.alertRules.createIndex({ "deviceId": 1 });
db.alertRules.createIndex({ "deviceType": 1 });
db.alertRules.createIndex({ "enabled": 1 });

print("MongoDB initialization completed successfully");
EOF

# Script para iniciar los servicios después de la instalación
cat > ${BASE_DIR}/start-services.sh << 'EOF'
#!/bin/bash

# Script para iniciar los servicios de la Zona B (Backend)

BASE_DIR="/opt/central-platform"

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    exit 1
fi

# Navegar al directorio base
cd ${BASE_DIR}

# Iniciar los servicios con Docker Compose
echo "Iniciando servicios de backend..."
docker-compose up -d

# Verificar el estado de los servicios
sleep 10
docker-compose ps

echo "Servicios iniciados. Puede verificar los logs con 'docker-compose logs -f'"
EOF

# Dar permisos de ejecución al script de inicio
chmod +x ${BASE_DIR}/start-services.sh

# Script para detener los servicios
cat > ${BASE_DIR}/stop-services.sh << 'EOF'
#!/bin/bash

# Script para detener los servicios de la Zona B (Backend)

BASE_DIR="/opt/central-platform"

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    exit 1
fi

# Navegar al directorio base
cd ${BASE_DIR}

# Detener los servicios con Docker Compose
echo "Deteniendo servicios de backend..."
docker-compose down

echo "Servicios detenidos."
EOF

# Dar permisos de ejecución al script de detención
chmod +x ${BASE_DIR}/stop-services.sh

# Configurar systemd para iniciar los servicios al arranque
cat > /etc/systemd/system/central-platform-backend.service << EOF
[Unit]
Description=Central Platform Backend Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/central-platform
ExecStart=/opt/central-platform/start-services.sh
ExecStop=/opt/central-platform/stop-services.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar el servicio
systemctl daemon-reload
systemctl enable central-platform-backend.service

# Instalar dependencias Node.js
log_info "Instalando dependencias de Node.js para WebSocket y Alertas..."
cd ${BACKEND_DIR}/websocket && npm install
cd ${BACKEND_DIR}/alerts && npm install

# Construir las imágenes Docker
log_info "Construyendo imágenes Docker..."
cd ${BASE_DIR} && docker-compose build

# Mensaje final
log_success "Despliegue de la Zona B (Backend) completado con éxito."
log_info "La plataforma está configurada con los siguientes servicios:"
echo "  - API REST (FastAPI): http://localhost:8000"
echo "  - WebSocket: ws://localhost:3000"
echo "  - Alertas: http://localhost:3001"
echo "  - PostgreSQL: localhost:5432"
echo "  - MongoDB: localhost:27017"
echo "  - Redis: localhost:6379"
log_info "Para iniciar los servicios manualmente, ejecute: sudo /opt/central-platform/start-services.sh"
log_info "Para detener los servicios manualmente, ejecute: sudo /opt/central-platform/stop-services.sh"
log_info "Los servicios se iniciarán automáticamente en el arranque del sistema."
log_warning "Recuerde revisar y ajustar las credenciales y configuraciones según sea necesario para su entorno."

exit 0
EOF

# Crear rutas de reglas de alerta
cat > ${BACKEND_DIR}/alerts/src/routes/rules.js << 'EOF'
const express = require('express');
const router = express.Router();
const AlertRule = require('../models/alertRule');
const logger = require('../utils/logger');

// Middleware de autenticación
const authMiddleware = require('../middleware/auth');

// Obtener todas las reglas (con filtros)
router.get('/', authMiddleware, async (req, res) => {
  try {
    const {
      deviceId,
      deviceType,
      enabled,
      limit = 100,
      skip = 0
    } = req.query;
    
    const query = {};
    
    if (deviceId) {
      query.deviceId = deviceId;
    }
    
    if (deviceType) {
      query.deviceType = deviceType;
    }
    
    if (enabled !== undefined) {
      query.enabled = enabled === 'true';
    }
    
    const rules = await AlertRule.find(query)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip));
      
    const total = await AlertRule.countDocuments(query);
    
    res.json({
      data: rules,
      meta: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip)
      }
    });
  } catch (error) {
    logger.error('Error fetching alert rules:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Obtener una regla por ID
router.get('/:id', authMiddleware, async (req, res) => {
  try {
    const rule = await AlertRule.findById(req.params.id);
      
    if (!rule) {
      return res.status(404).json({ error: 'Rule not found' });
    }
    
    res.json(rule);
  } catch (error) {
    logger.error(`Error fetching rule ${req.params.id}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Crear nueva regla
router.post('/', authMiddleware, async (req, res) => {
  try {
    // Validar condición mínima
    if (!req.body.condition || typeof req.body.condition !== 'object') {
      return res.status(400).json({ error: 'Valid condition object is required' });
    }
    
    // Crear nueva regla
    const rule = new AlertRule({
      ...req.body,
      createdBy: req.user.id
    });
    
    await rule.save();
    
    res.status(201).json(rule);
  } catch (error) {
    logger.error('Error creating alert rule:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Actualizar regla
router.put('/:id', authMiddleware, async (req, res) => {
  try {
    const rule = await AlertRule.findById(req.params.id);
    
    if (!rule) {
      return res.status(404).json({ error: 'Rule not found' });
    }
    
    // Actualizar campos
    Object.keys(req.body).forEach(key => {
      if (key !== 'createdBy' && key !== 'createdAt') { // No permitir cambiar estos campos
        rule[key] = req.body[key];
      }
    });
    
    await rule.save();
    
    res.json(rule);
  } catch (error) {
    logger.error(`Error updating rule ${req.params.id}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Eliminar regla
router.delete('/:id', authMiddleware, async (req, res) => {
  try {
    const result = await AlertRule.findByIdAndDelete(req.params.id);
    
    if (!result) {
      return res.status(404).json({ error: 'Rule not found' });
    }
    
    res.status(204).send();
  } catch (error) {
    logger.error(`Error deleting rule ${req.params.id}:`, error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
