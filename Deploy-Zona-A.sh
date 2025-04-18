#!/bin/bash

# Script de despliegue de la Zona A (Frontend) para la Plataforma Centralizada de Información
# Para Ubuntu 24.04 LTS

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes con formato
print_message() {
    local type=$1
    local message=$2
    
    case $type in
        "info")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Verificar que se está ejecutando como root o con sudo
if [ "$EUID" -ne 0 ]; then
    print_message "error" "Este script debe ejecutarse como root o con sudo."
    exit 1
fi

# Verificar Ubuntu 24.04 LTS
if ! grep -q 'VERSION="24.04' /etc/os-release; then
    print_message "warning" "Este script está diseñado para Ubuntu 24.04 LTS. La ejecución en otras versiones puede causar problemas."
    
    read -p "¿Desea continuar de todas formas? (s/n): " CONTINUE
    if [[ ! $CONTINUE =~ ^[Ss]$ ]]; then
        print_message "info" "Operación cancelada."
        exit 0
    fi
fi

# Directorio raiz para la Plataforma Centralizada
BASE_DIR="/opt/central-platform"
FRONTEND_DIR="$BASE_DIR/frontend"
CURRENT_DIR=$(pwd)

# Función para crear directorios
create_directories() {
    print_message "info" "Creando estructura de directorios..."
    
    # Crear directorio base si no existe
    mkdir -p $BASE_DIR
    
    # Crear estructura de directorios para el frontend
    mkdir -p $FRONTEND_DIR/{public,src}
    mkdir -p $FRONTEND_DIR/src/{assets,components,hooks,layouts,pages,redux,services,utils,types,config}
    mkdir -p $FRONTEND_DIR/src/assets/{images,fonts,styles}
    mkdir -p $FRONTEND_DIR/src/assets/images/{backgrounds,icons}
    
    # Crear subdirectorios de componentes
    mkdir -p $FRONTEND_DIR/src/components/{common,dashboard,devices,analytics,alerts,credentials,layout}
    mkdir -p $FRONTEND_DIR/src/components/common/{Button,Card,Input,Modal,Loader,Alert,DataTable}
    mkdir -p $FRONTEND_DIR/src/components/dashboard/{StatCard,DevicesMap,DeviceStatusChart,LatestAlerts,ActivityTimeline,MetricsChart}
    mkdir -p $FRONTEND_DIR/src/components/devices/{DeviceForm,DeviceDetails,DevicesTable,DevicesGrid,DeviceStatusBadge}
    mkdir -p $FRONTEND_DIR/src/components/analytics/{AnalyticsSummary,DeviceAnalytics,PredictiveAnalytics,MongoDBAnalytics,QueryEditor,QueryResultTable,QueryResultChart}
    mkdir -p $FRONTEND_DIR/src/components/alerts/{AlertsList,AlertForm,AlertRuleForm,AlertDetails}
    mkdir -p $FRONTEND_DIR/src/components/credentials/{CredentialsTable,CredentialForm,CredentialDialog}
    mkdir -p $FRONTEND_DIR/src/components/layout/{MainLayout,Sidebar,Navbar,Footer,PageHeader,UserMenu}
    
    # Crear subdirectorios de páginas
    mkdir -p $FRONTEND_DIR/src/pages/{auth,dashboard,devices,analytics,alerts,settings}
    
    # Crear subdirectorios de Redux
    mkdir -p $FRONTEND_DIR/src/redux/slices
    
    print_message "success" "Estructura de directorios creada correctamente."
}

# Instalar dependencias necesarias
install_dependencies() {
    print_message "info" "Actualizando e instalando dependencias..."
    
    apt-get update
    apt-get install -y curl nodejs npm nginx
    
    # Actualizar a la última versión de Node.js y npm
    npm install -g n
    n stable
    
    # Recargar el PATH para usar la nueva versión de Node.js
    PATH="$PATH"
    
    # Verificar instalación
    node_version=$(node -v)
    npm_version=$(npm -v)
    
    print_message "success" "Node.js $node_version y npm $npm_version instalados correctamente."
}

# Crear archivos principales del proyecto
create_main_files() {
    print_message "info" "Creando archivos principales del proyecto..."
    
    # Crear package.json
    cat > $FRONTEND_DIR/package.json << 'EOF'
{
  "name": "central-platform-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@emotion/react": "^11.10.6",
    "@emotion/styled": "^11.10.6",
    "@mui/icons-material": "^5.11.16",
    "@mui/material": "^5.12.0",
    "@reduxjs/toolkit": "^1.9.5",
    "axios": "^1.3.5",
    "date-fns": "^2.29.3",
    "formik": "^2.2.9",
    "i18next": "^22.4.15",
    "lodash": "^4.17.21",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-grid-layout": "^1.3.4",
    "react-i18next": "^12.2.0",
    "react-redux": "^8.0.5",
    "react-router-dom": "^6.10.0",
    "recharts": "^2.5.0",
    "socket.io-client": "^4.6.1",
    "yup": "^1.1.1"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^5.16.5",
    "@testing-library/react": "^14.0.0",
    "@testing-library/user-event": "^14.4.3",
    "@types/jest": "^29.5.0",
    "@types/lodash": "^4.14.195",
    "@types/node": "^18.15.11",
    "@types/react": "^18.0.37",
    "@types/react-dom": "^18.0.11",
    "@types/react-grid-layout": "^1.3.2",
    "eslint": "^8.38.0",
    "eslint-config-prettier": "^8.8.0",
    "eslint-plugin-prettier": "^4.2.1",
    "eslint-plugin-react": "^7.32.2",
    "eslint-plugin-react-hooks": "^4.6.0",
    "prettier": "^2.8.7",
    "typescript": "^5.0.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject",
    "lint": "eslint --ext .ts,.tsx src/",
    "lint:fix": "eslint --fix --ext .ts,.tsx src/",
    "format": "prettier --write \"src/**/*.{ts,tsx}\""
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOF

    # Crear archivo tsconfig.json
    cat > $FRONTEND_DIR/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "es5",
    "lib": [
      "dom",
      "dom.iterable",
      "esnext"
    ],
    "allowJs": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "module": "esnext",
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "baseUrl": "src"
  },
  "include": [
    "src"
  ]
}
EOF

    # Crear archivos de entorno
    cat > $FRONTEND_DIR/.env.development << 'EOF'
# API URLs
REACT_APP_API_URL=http://localhost:8000/api/v1
REACT_APP_WS_URL=ws://localhost:3000

# Auth
REACT_APP_AUTH_DOMAIN=central-platform.local
REACT_APP_CLIENT_ID=your-client-id
REACT_APP_CLIENT_SECRET=your-client-secret

# Features
REACT_APP_ENABLE_ANALYTICS=true
REACT_APP_ENABLE_PREDICTIONS=true

# Maps
REACT_APP_MAPS_API_KEY=your-maps-api-key

# Version
REACT_APP_VERSION=1.0.0
EOF

    cat > $FRONTEND_DIR/.env.production << 'EOF'
# API URLs
REACT_APP_API_URL=https://api.central-platform.local/api/v1
REACT_APP_WS_URL=wss://ws.central-platform.local

# Auth
REACT_APP_AUTH_DOMAIN=central-platform.local
REACT_APP_CLIENT_ID=your-client-id
REACT_APP_CLIENT_SECRET=your-client-secret

# Features
REACT_APP_ENABLE_ANALYTICS=true
REACT_APP_ENABLE_PREDICTIONS=true

# Maps
REACT_APP_MAPS_API_KEY=your-maps-api-key

# Version
REACT_APP_VERSION=1.0.0
EOF

    # Crear Dockerfile
    cat > $FRONTEND_DIR/Dockerfile << 'EOF'
# Etapa de construcción
FROM node:18-alpine as build

WORKDIR /app

# Copiar package.json y package-lock.json
COPY package*.json ./

# Instalar dependencias
RUN npm ci

# Copiar código fuente
COPY . .

# Construir la aplicación
RUN npm run build

# Etapa de producción
FROM nginx:alpine

# Copiar archivos de construcción
COPY --from=build /app/build /usr/share/nginx/html

# Copiar configuración de nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Exponer puerto
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

    # Crear configuración de nginx
    cat > $FRONTEND_DIR/nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Compresión gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Configuración de seguridad
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;";

    # Rutas API
    location /api/ {
        proxy_pass http://api-rest-service:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Ruta WebSocket
    location /ws/ {
        proxy_pass http://websocket-service:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }

    # Todas las demás solicitudes van al index.html para SPA
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

    # Crear .eslintrc.js
    cat > $FRONTEND_DIR/.eslintrc.js << 'EOF'
module.exports = {
  parser: '@typescript-eslint/parser',
  extends: [
    'plugin:react/recommended',
    'plugin:react-hooks/recommended',
    'plugin:@typescript-eslint/recommended',
    'prettier'
  ],
  parserOptions: {
    ecmaVersion: 2020,
    sourceType: 'module',
    ecmaFeatures: {
      jsx: true
    }
  },
  rules: {
    'react/prop-types': 'off',
    'react/react-in-jsx-scope': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'off'
  },
  settings: {
    react: {
      version: 'detect'
    }
  }
};
EOF

    # Crear .prettierrc
    cat > $FRONTEND_DIR/.prettierrc << 'EOF'
{
  "semi": true,
  "trailingComma": "none",
  "singleQuote": true,
  "printWidth": 100,
  "tabWidth": 2
}
EOF

    print_message "success" "Archivos principales creados correctamente."
}

# Crear archivos de aplicación React
create_react_files() {
    print_message "info" "Creando archivos de la aplicación React..."
    
    # Crear archivos públicos
    cat > $FRONTEND_DIR/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta
      name="description"
      content="Plataforma Centralizada de Información"
    />
    <link rel="apple-touch-icon" href="%PUBLIC_URL%/logo192.png" />
    <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
    <title>Plataforma Centralizada</title>
  </head>
  <body>
    <noscript>Necesita habilitar JavaScript para ejecutar esta aplicación.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

    cat > $FRONTEND_DIR/public/manifest.json << 'EOF'
{
  "short_name": "Plataforma",
  "name": "Plataforma Centralizada de Información",
  "icons": [
    {
      "src": "favicon.ico",
      "sizes": "64x64 32x32 24x24 16x16",
      "type": "image/x-icon"
    },
    {
      "src": "logo192.png",
      "type": "image/png",
      "sizes": "192x192"
    },
    {
      "src": "logo512.png",
      "type": "image/png",
      "sizes": "512x512"
    }
  ],
  "start_url": ".",
  "display": "standalone",
  "theme_color": "#000000",
  "background_color": "#ffffff"
}
EOF

    cat > $FRONTEND_DIR/public/robots.txt << 'EOF'
# https://www.robotstxt.org/robotstxt.html
User-agent: *
Disallow:
EOF

    # Crear archivos principales de React
    cat > $FRONTEND_DIR/src/index.tsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { store } from './redux/store';
import App from './App';
import './assets/styles/globals.css';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    <Provider store={store}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </Provider>
  </React.StrictMode>
);
EOF

    cat > $FRONTEND_DIR/src/App.tsx << 'EOF'
import { ThemeProvider } from '@mui/material/styles';
import { CssBaseline } from '@mui/material';
import { Routes, Route } from 'react-router-dom';
import theme from './assets/styles/theme';
import MainLayout from './layouts/MainLayout';
import AuthLayout from './layouts/AuthLayout';
import Dashboard from './pages/dashboard/Dashboard';
import Login from './pages/auth/Login';
import DevicesPage from './pages/devices/DevicesPage';
import DeviceDetails from './pages/devices/DeviceDetails';
import AnalyticsPage from './pages/analytics/AnalyticsPage';
import AlertsPage from './pages/alerts/AlertsPage';
import Settings from './pages/settings/Settings';
import NotFound from './pages/NotFound';

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Routes>
        <Route path="/auth" element={<AuthLayout />}>
          <Route path="login" element={<Login />} />
        </Route>
        <Route path="/" element={<MainLayout />}>
          <Route index element={<Dashboard />} />
          <Route path="devices" element={<DevicesPage />} />
          <Route path="devices/:id" element={<DeviceDetails />} />
          <Route path="analytics" element={<AnalyticsPage />} />
          <Route path="alerts" element={<AlertsPage />} />
          <Route path="settings" element={<Settings />} />
        </Route>
        <Route path="*" element={<NotFound />} />
      </Routes>
    </ThemeProvider>
  );
}

export default App;
EOF

    cat > $FRONTEND_DIR/src/routes.tsx << 'EOF'
import { RouteObject } from 'react-router-dom';
import MainLayout from './layouts/MainLayout';
import AuthLayout from './layouts/AuthLayout';
import Dashboard from './pages/dashboard/Dashboard';
import Login from './pages/auth/Login';
import DevicesPage from './pages/devices/DevicesPage';
import DeviceDetails from './pages/devices/DeviceDetails';
import AnalyticsPage from './pages/analytics/AnalyticsPage';
import AlertsPage from './pages/alerts/AlertsPage';
import Settings from './pages/settings/Settings';
import NotFound from './pages/NotFound';

const routes: RouteObject[] = [
  {
    path: '/',
    element: <MainLayout />,
    children: [
      {
        index: true,
        element: <Dashboard />
      },
      {
        path: 'devices',
        element: <DevicesPage />
      },
      {
        path: 'devices/:id',
        element: <DeviceDetails />
      },
      {
        path: 'analytics',
        element: <AnalyticsPage />
      },
      {
        path: 'alerts',
        element: <AlertsPage />
      },
      {
        path: 'settings',
        element: <Settings />
      }
    ]
  },
  {
    path: '/auth',
    element: <AuthLayout />,
    children: [
      {
        path: 'login',
        element: <Login />
      }
    ]
  },
  {
    path: '*',
    element: <NotFound />
  }
];

export default routes;
EOF

    # Crear estilos y tema
    cat > $FRONTEND_DIR/src/assets/styles/globals.css << 'EOF'
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  font-family: 'Roboto', 'Helvetica', 'Arial', sans-serif;
  background-color: #f5f5f5;
}

a {
  color: inherit;
  text-decoration: none;
}
EOF

    cat > $FRONTEND_DIR/src/assets/styles/theme.ts << 'EOF'
import { createTheme } from '@mui/material/styles';

// Crear tema personalizado
const theme = createTheme({
  palette: {
    primary: {
      main: '#1976d2',
      light: '#42a5f5',
      dark: '#1565c0',
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#9c27b0',
      light: '#ba68c8',
      dark: '#7b1fa2',
      contrastText: '#ffffff',
    },
    error: {
      main: '#d32f2f',
      light: '#ef5350',
      dark: '#c62828',
    },
    warning: {
      main: '#ed6c02',
      light: '#ff9800',
      dark: '#e65100',
    },
    info: {
      main: '#0288d1',
      light: '#03a9f4',
      dark: '#01579b',
    },
    success: {
      main: '#2e7d32',
      light: '#4caf50',
      dark: '#1b5e20',
    },
    background: {
      default: '#f5f5f5',
      paper: '#ffffff',
    },
  },
  typography: {
    fontFamily: '"Roboto", "Helvetica", "Arial", sans-serif',
    h1: {
      fontWeight: 500,
      fontSize: '2.5rem',
    },
    h2: {
      fontWeight: 500,
      fontSize: '2rem',
    },
    h3: {
      fontWeight: 500,
      fontSize: '1.75rem',
    },
    h4: {
      fontWeight: 500,
      fontSize: '1.5rem',
    },
    h5: {
      fontWeight: 500,
      fontSize: '1.25rem',
    },
    h6: {
      fontWeight: 500,
      fontSize: '1rem',
    },
  },
  shape: {
    borderRadius: 8,
  },
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          textTransform: 'none',
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          boxShadow: '0px 3px 6px rgba(0, 0, 0, 0.1)',
        },
      },
    },
  },
});

export default theme;
EOF

    # Crear componentes de layout
    cat > $FRONTEND_DIR/src/layouts/MainLayout.tsx << 'EOF'
import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { Box, useMediaQuery, useTheme } from '@mui/material';
import Sidebar from '../components/layout/Sidebar/Sidebar';
import Navbar from '../components/layout/Navbar/Navbar';

const MainLayout = () => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  const [sidebarOpen, setSidebarOpen] = useState(!isMobile);

  const handleToggleSidebar = () => {
    setSidebarOpen(!sidebarOpen);
  };

  return (
    <Box sx={{ display: 'flex', height: '100vh' }}>
      <Sidebar open={sidebarOpen} onClose={handleToggleSidebar} />
      <Box component="main" sx={{ flexGrow: 1, overflow: 'auto' }}>
        <Navbar onToggleSidebar={handleToggleSidebar} />
        <Box sx={{ p: 3 }}>
          <Outlet />
        </Box>
      </Box>
    </Box>
  );
};

export default MainLayout;
EOF

    cat > $FRONTEND_DIR/src/layouts/AuthLayout.tsx << 'EOF'
import { Outlet } from 'react-router-dom';
import { Box, Container, Paper, Typography } from '@mui/material';

const AuthLayout = () => {
  return (
    <Box
      sx={{
        display: 'flex',
        minHeight: '100vh',
        backgroundColor: 'primary.main',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundImage: 'linear-gradient(45deg, #1976d2 0%, #9c27b0 100%)',
      }}
    >
      <Container maxWidth="sm">
        <Paper
          elevation={5}
          sx={{
            p: 4,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <Typography variant="h4" component="h1" gutterBottom>
            Plataforma Centralizada
          </Typography>
          <Outlet />
        </Paper>
      </Container>
    </Box>
  );
};

export default AuthLayout;
EOF

    # Crear Redux store
    cat > $FRONTEND_DIR/src/redux/store.ts << 'EOF'
import { configureStore } from '@reduxjs/toolkit';
import authReducer from './slices/authSlice';
import deviceReducer from './slices/deviceSlice';
import alertReducer from './slices/alertSlice';
import uiReducer from './slices/uiSlice';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    device: deviceReducer,
    alert: alertReducer,
    ui: uiReducer
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: false
    })
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
EOF

    # Crear Redux slices
    cat > $FRONTEND_DIR/src/redux/slices/authSlice.ts << 'EOF'
import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { authService } from '../../services/authService';

export interface AuthState {
  user: any | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
}

const initialState: AuthState = {
  user: null,
  token: localStorage.getItem('token'),
  isAuthenticated: !!localStorage.getItem('token'),
  isLoading: false,
  error: null
};

export const login = createAsyncThunk(
  'auth/login',
  async ({ username, password }: { username: string; password: string }, { rejectWithValue }) => {
    try {
      const response = await authService.login(username, password);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al iniciar sesión');
    }
  }
);

export const logout = createAsyncThunk('auth/logout', async () => {
  await authService.logout();
});

export const getUserProfile = createAsyncThunk('auth/getUserProfile', async (_, { rejectWithValue }) => {
  try {
    const response = await authService.getUserProfile();
    return response;
  } catch (error: any) {
    return rejectWithValue(error.response?.data?.message || 'Error al obtener perfil');
  }
});

const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    }
  },
  extraReducers: (builder) => {
    builder
      // Login
      .addCase(login.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(login.fulfilled, (state, action) => {
        state.isLoading = false;
        state.isAuthenticated = true;
        state.token = action.payload.token;
        localStorage.setItem('token', action.payload.token);
      })
      .addCase(login.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      // Logout
      .addCase(logout.fulfilled, (state) => {
        state.isAuthenticated = false;
        state.user = null;
        state.token = null;
        localStorage.removeItem('token');
      })
      // Get User Profile
      .addCase(getUserProfile.pending, (state) => {
        state.isLoading = true;
      })
      .addCase(getUserProfile.fulfilled, (state, action) => {
        state.isLoading = false;
        state.user = action.payload;
      })
      .addCase(getUserProfile.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });
  }
});

export const { clearError } = authSlice.actions;
export default authSlice.reducer;
EOF

    cat > $FRONTEND_DIR/src/redux/slices/deviceSlice.ts << 'EOF'
import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { deviceService } from '../../services/deviceService';

export interface DeviceState {
  devices: any[];
  currentDevice: any | null;
  isLoading: boolean;
  error: string | null;
}

const initialState: DeviceState = {
  devices: [],
  currentDevice: null,
  isLoading: false,
  error: null
};

export const fetchDevices = createAsyncThunk(
  'device/fetchDevices',
  async (_, { rejectWithValue }) => {
    try {
      const response = await deviceService.getDevices();
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al obtener dispositivos');
    }
  }
);

export const fetchDeviceById = createAsyncThunk(
  'device/fetchDeviceById',
  async (id: string, { rejectWithValue }) => {
    try {
      const response = await deviceService.getDeviceById(id);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al obtener dispositivo');
    }
  }
);

export const createDevice = createAsyncThunk(
  'device/createDevice',
  async (deviceData: any, { rejectWithValue }) => {
    try {
      const response = await deviceService.createDevice(deviceData);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al crear dispositivo');
    }
  }
);

export const updateDevice = createAsyncThunk(
  'device/updateDevice',
  async ({ id, data }: { id: string; data: any }, { rejectWithValue }) => {
    try {
      const response = await deviceService.updateDevice(id, data);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al actualizar dispositivo');
    }
  }
);

export const deleteDevice = createAsyncThunk(
  'device/deleteDevice',
  async (id: string, { rejectWithValue }) => {
    try {
      await deviceService.deleteDevice(id);
      return id;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.message || 'Error al eliminar dispositivo');
    }
  }
);

const deviceSlice = createSlice({
  name: 'device',
  initialState,
  reducers: {
    clearDeviceError: (state) => {
      state.error = null;
    },
    clearCurrentDevice: (state) => {
      state.currentDevice = null;
    }
  },
  extraReducers: (builder) => {
    builder
      // Fetch Devices
      .addCase(fetchDevices.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchDevices.fulfilled, (state, action) => {
        state.isLoading = false;
        state.devices = action.payload;
      })
      .addCase(fetchDevices.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      // Fetch Device By Id
      .addCase(fetchDeviceById.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchDeviceById.fulfilled, (state, action) => {
        state.isLoading = false;
        state.currentDevice = action.payload;
      })
      .addCase(fetchDeviceById.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      // Create Device
      .addCase(createDevice.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(createDevice.fulfilled, (state, action) => {
        state.isLoading = false;
        state.devices.push(action.payload);
      })
      .addCase(createDevice.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      // Update Device
      .addCase(updateDevice.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(updateDevice.fulfilled, (state, action) => {
        state.isLoading = false;
        const index = state.devices.findIndex((device) => device.id === action.payload.id);
        if (index !== -1) {
          state.devices[index] = action.payload;
        }
        state.currentDevice = action.payload;
      })
      .addCase(updateDevice.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      // Delete Device
      .addCase(deleteDevice.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(deleteDevice.fulfilled, (state, action) => {
        state.isLoading = false;
        state.devices = state.devices.filter((device) => device.id !== action.payload);
        if (state.currentDevice && state.currentDevice.id === action.payload) {
          state.currentDevice = null;
        }
      })
      .addCase(deleteDevice.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });
  }
});

export const { clearDeviceError, clearCurrentDevice } = deviceSlice.actions;
export default deviceSlice.reducer;
EOF

    cat > $FRONTEND_DIR/src/redux/slices/uiSlice.ts << 'EOF'
import { createSlice, PayloadAction } from '@reduxjs/toolkit';

export interface UiState {
  sidebarOpen: boolean;
  loading: {
    [key: string]: boolean;
  };
  notifications: {
    id: string;
    type: 'success' | 'error' | 'info' | 'warning';
    message: string;
  }[];
}

const initialState: UiState = {
  sidebarOpen: true,
  loading: {},
  notifications: []
};

const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    toggleSidebar: (state) => {
      state.sidebarOpen = !state.sidebarOpen;
    },
    setSidebarOpen: (state, action: PayloadAction<boolean>) => {
      state.sidebarOpen = action.payload;
    },
    setLoading: (state, action: PayloadAction<{ key: string; isLoading: boolean }>) => {
      const { key, isLoading } = action.payload;
      state.loading[key] = isLoading;
    },
    addNotification: (state, action: PayloadAction<Omit<UiState['notifications'][0], 'id'>>) => {
      state.notifications.push({
        id: Date.now().toString(),
        ...action.payload
      });
    },
    removeNotification: (state, action: PayloadAction<string>) => {
      state.notifications = state.notifications.filter((notification) => notification.id !== action.payload);
    }
  }
});

export const { toggleSidebar, setSidebarOpen, setLoading, addNotification, removeNotification } =
  uiSlice.actions;
export default uiSlice.reducer;
EOF

    # Crear servicios básicos
    cat > $FRONTEND_DIR/src/services/api.ts << 'EOF'
import axios, { AxiosRequestConfig } from 'axios';

// Crear instancia de axios con configuración base
const api = axios.create({
  baseURL: process.env.REACT_APP_API_URL || 'http://localhost:8000/api/v1',
  headers: {
    'Content-Type': 'application/json'
  }
});

// Interceptor para agregar token de autenticación
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token');
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Interceptor para manejar errores
api.interceptors.response.use(
  (response) => response,
  (error) => {
    // Manejar error 401 (no autorizado)
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('token');
      window.location.href = '/auth/login';
    }
    return Promise.reject(error);
  }
);

// Funciones helper
export const get = <T>(url: string, config?: AxiosRequestConfig) => 
  api.get<T>(url, config).then(response => response.data);

export const post = <T>(url: string, data?: any, config?: AxiosRequestConfig) => 
  api.post<T>(url, data, config).then(response => response.data);

export const put = <T>(url: string, data?: any, config?: AxiosRequestConfig) => 
  api.put<T>(url, data, config).then(response => response.data);

export const patch = <T>(url: string, data?: any, config?: AxiosRequestConfig) => 
  api.patch<T>(url, data, config).then(response => response.data);

export const del = <T>(url: string, config?: AxiosRequestConfig) => 
  api.delete<T>(url, config).then(response => response.data);

export default api;
EOF

    cat > $FRONTEND_DIR/src/services/authService.ts << 'EOF'
import { get, post } from './api';

export interface LoginResponse {
  token: string;
  user: any;
}

export interface UserProfile {
  id: string;
  username: string;
  email: string;
  fullName: string;
  role: string;
}

// Función para iniciar sesión
const login = async (username: string, password: string): Promise<LoginResponse> => {
  return post<LoginResponse>('/auth/login', { username, password });
};

// Función para cerrar sesión
const logout = async (): Promise<void> => {
  localStorage.removeItem('token');
};

// Función para obtener el perfil del usuario
const getUserProfile = async (): Promise<UserProfile> => {
  return get<UserProfile>('/auth/me');
};

export const authService = {
  login,
  logout,
  getUserProfile
};
EOF

    cat > $FRONTEND_DIR/src/services/deviceService.ts << 'EOF'
import { get, post, put, del } from './api';

export interface Device {
  id: string;
  deviceId: string;
  name: string;
  type: string;
  status: string;
  model?: string;
  manufacturer?: string;
  firmware?: string;
  metadata?: Record<string, any>;
  ownerId: string;
  groupId?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface DeviceCreate {
  deviceId: string;
  name: string;
  type: string;
  model?: string;
  manufacturer?: string;
  firmware?: string;
  metadata?: Record<string, any>;
  groupId?: string;
}

export interface DeviceUpdate {
  name?: string;
  type?: string;
  status?: string;
  model?: string;
  manufacturer?: string;
  firmware?: string;
  metadata?: Record<string, any>;
  groupId?: string;
}

// Función para obtener todos los dispositivos
const getDevices = async (): Promise<Device[]> => {
  return get<Device[]>('/devices');
};

// Función para obtener un dispositivo por ID
const getDeviceById = async (id: string): Promise<Device> => {
  return get<Device>(`/devices/${id}`);
};

// Función para crear un dispositivo
const createDevice = async (device: DeviceCreate): Promise<Device> => {
  return post<Device>('/devices', device);
};

// Función para actualizar un dispositivo
const updateDevice = async (id: string, device: DeviceUpdate): Promise<Device> => {
  return put<Device>(`/devices/${id}`, device);
};

// Función para eliminar un dispositivo
const deleteDevice = async (id: string): Promise<void> => {
  return del(`/devices/${id}`);
};

export const deviceService = {
  getDevices,
  getDeviceById,
  createDevice,
  updateDevice,
  deleteDevice
};
EOF

    cat > $FRONTEND_DIR/src/services/socketService.ts << 'EOF'
import { io, Socket } from 'socket.io-client';

class SocketService {
  private socket: Socket | null = null;
  private listeners = new Map<string, Set<(data: any) => void>>();

  // Inicializar conexión WebSocket
  connect() {
    if (this.socket) {
      return;
    }

    const token = localStorage.getItem('token');
    if (!token) {
      console.error('No authentication token available for WebSocket connection');
      return;
    }

    // Conectar al servidor WebSocket
    this.socket = io(process.env.REACT_APP_WS_URL || 'ws://localhost:3000', {
      auth: {
        token
      },
      transports: ['websocket']
    });

    // Manejador de conexión exitosa
    this.socket.on('connect', () => {
      console.log('WebSocket connected');
    });

    // Manejador de errores
    this.socket.on('connect_error', (error) => {
      console.error('WebSocket connection error:', error);
    });

    // Manejador de desconexión
    this.socket.on('disconnect', (reason) => {
      console.log('WebSocket disconnected:', reason);
    });

    // Configurar listeners registrados
    this.listeners.forEach((callbacks, event) => {
      callbacks.forEach(callback => {
        this.socket?.on(event, callback);
      });
    });
  }

  // Desconectar WebSocket
  disconnect() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }

  // Suscribirse a un evento
  subscribe(event: string, callback: (data: any) => void) {
    // Registrar callback en los listeners
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event)?.add(callback);

    // Si el socket ya está conectado, añadir el listener
    if (this.socket) {
      this.socket.on(event, callback);
    }

    // Devolver función para cancelar suscripción
    return () => this.unsubscribe(event, callback);
  }

  // Cancelar suscripción a un evento
  unsubscribe(event: string, callback: (data: any) => void) {
    // Remover callback de los listeners
    this.listeners.get(event)?.delete(callback);
    
    // Si el socket está conectado, remover el listener
    if (this.socket) {
      this.socket.off(event, callback);
    }
  }

  // Emitir un evento
  emit(event: string, data?: any) {
    if (this.socket) {
      this.socket.emit(event, data);
    } else {
      console.error('Cannot emit event, WebSocket not connected');
    }
  }

  // Suscribirse a actualizaciones de dispositivos
  subscribeToDevices(deviceIds: string[]) {
    this.emit('subscribe-devices', deviceIds);
  }

  // Enviar comando a un dispositivo
  sendCommand(deviceId: string, action: string, parameters?: Record<string, any>) {
    this.emit('send-command', {
      deviceId,
      action,
      parameters,
      commandId: Date.now().toString()
    });
  }
}

// Crear y exportar instancia singleton
export const socketService = new SocketService();
export default socketService;
EOF

    # Crear páginas básicas
    cat > $FRONTEND_DIR/src/pages/NotFound.tsx << 'EOF'
import { Box, Button, Container, Typography } from '@mui/material';
import { useNavigate } from 'react-router-dom';

const NotFound = () => {
  const navigate = useNavigate();

  return (
    <Container maxWidth="md">
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '80vh',
          textAlign: 'center',
        }}
      >
        <Typography variant="h1" component="h1" gutterBottom>
          404
        </Typography>
        <Typography variant="h4" component="h2" gutterBottom>
          Página no encontrada
        </Typography>
        <Typography variant="body1" paragraph>
          La página que estás buscando no existe o ha sido movida.
        </Typography>
        <Button variant="contained" color="primary" onClick={() => navigate('/')}>
          Volver al inicio
        </Button>
      </Box>
    </Container>
  );
};

export default NotFound;
EOF

    cat > $FRONTEND_DIR/src/pages/auth/Login.tsx << 'EOF'
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import { Box, Button, TextField, Typography, Alert, CircularProgress } from '@mui/material';
import { login, clearError } from '../../redux/slices/authSlice';
import type { AppDispatch, RootState } from '../../redux/store';

const Login = () => {
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  const { isLoading, error } = useSelector((state: RootState) => state.auth);
  
  const [formData, setFormData] = useState({
    username: '',
    password: ''
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: value
    }));
    
    // Limpiar error al cambiar los campos
    if (error) {
      dispatch(clearError());
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      await dispatch(login(formData)).unwrap();
      navigate('/');
    } catch (err) {
      // Error ya es manejado en el slice
    }
  };

  return (
    <Box sx={{ width: '100%' }}>
      <Typography variant="h5" component="h2" align="center" gutterBottom>
        Iniciar Sesión
      </Typography>
      
      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}
      
      <form onSubmit={handleSubmit}>
        <TextField
          label="Nombre de usuario"
          name="username"
          value={formData.username}
          onChange={handleChange}
          fullWidth
          margin="normal"
          required
          autoFocus
        />
        
        <TextField
          label="Contraseña"
          name="password"
          type="password"
          value={formData.password}
          onChange={handleChange}
          fullWidth
          margin="normal"
          required
        />
        
        <Button
          type="submit"
          fullWidth
          variant="contained"
          color="primary"
          size="large"
          disabled={isLoading}
          sx={{ mt: 3, mb: 2 }}
        >
          {isLoading ? <CircularProgress size={24} /> : 'Iniciar Sesión'}
        </Button>
      </form>
    </Box>
  );
};

export default Login;
EOF

    cat > $FRONTEND_DIR/src/pages/dashboard/Dashboard.tsx << 'EOF'
import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Grid, Paper, Typography, Box } from '@mui/material';
import { fetchDevices } from '../../redux/slices/deviceSlice';
import type { AppDispatch, RootState } from '../../redux/store';
import StatCard from '../../components/dashboard/StatCard/StatCard';

const Dashboard = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { devices, isLoading } = useSelector((state: RootState) => state.device);
  
  useEffect(() => {
    dispatch(fetchDevices());
  }, [dispatch]);
  
  // Calcular estadísticas
  const totalDevices = devices.length;
  const onlineDevices = devices.filter(device => device.status === 'online').length;
  const offlineDevices = devices.filter(device => device.status === 'offline').length;
  const maintenanceDevices = devices.filter(device => device.status === 'maintenance').length;
  
  return (
    <Box>
      <Typography variant="h4" component="h1" gutterBottom>
        Dashboard
      </Typography>
      
      <Grid container spacing={3}>
        {/* Tarjetas de estadísticas */}
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Total Dispositivos"
            value={totalDevices}
            icon="devices"
            color="#1976d2"
            isLoading={isLoading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Dispositivos Online"
            value={onlineDevices}
            icon="wifi"
            color="#4caf50"
            isLoading={isLoading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Dispositivos Offline"
            value={offlineDevices}
            icon="wifi_off"
            color="#f44336"
            isLoading={isLoading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="En Mantenimiento"
            value={maintenanceDevices}
            icon="build"
            color="#ff9800"
            isLoading={isLoading}
          />
        </Grid>
        
        {/* Gráficos y widgets adicionales irían aquí */}
        <Grid item xs={12} md={8}>
          <Paper sx={{ p: 3, height: 400 }}>
            <Typography variant="h6" gutterBottom>
              Actividad Reciente
            </Typography>
            {/* Aquí iría un componente de actividad reciente */}
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={4}>
          <Paper sx={{ p: 3, height: 400 }}>
            <Typography variant="h6" gutterBottom>
              Alertas Activas
            </Typography>
            {/* Aquí iría un componente de alertas */}
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;
EOF

    # Crear componentes básicos comunes
    mkdir -p "$FRONTEND_DIR/src/components/common/Button"
    cat > $FRONTEND_DIR/src/components/common/Button/Button.tsx << 'EOF'
import { Button as MuiButton, ButtonProps as MuiButtonProps } from '@mui/material';

export interface ButtonProps extends MuiButtonProps {
  // Propiedades personalizadas adicionales pueden ir aquí
}

const Button = ({ children, ...props }: ButtonProps) => {
  return <MuiButton {...props}>{children}</MuiButton>;
};

export default Button;
EOF

    cat > $FRONTEND_DIR/src/components/common/Button/index.ts << 'EOF'
export { default } from './Button';
export type { ButtonProps } from './Button';
EOF

    # Crear componente de layout - Sidebar
    mkdir -p "$FRONTEND_DIR/src/components/layout/Sidebar"
    cat > $FRONTEND_DIR/src/components/layout/Sidebar/Sidebar.tsx << 'EOF'
import { useLocation, useNavigate } from 'react-router-dom';
import {
  Box,
  Drawer,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Divider,
  IconButton,
  useTheme,
  useMediaQuery
} from '@mui/material';
import ChevronLeftIcon from '@mui/icons-material/ChevronLeft';
import DashboardIcon from '@mui/icons-material/Dashboard';
import DevicesIcon from '@mui/icons-material/Devices';
import AssessmentIcon from '@mui/icons-material/Assessment';
import NotificationsIcon from '@mui/icons-material/Notifications';
import SettingsIcon from '@mui/icons-material/Settings';

const drawerWidth = 240;

interface SidebarProps {
  open: boolean;
  onClose: () => void;
}

const Sidebar = ({ open, onClose }: SidebarProps) => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  const location = useLocation();
  const navigate = useNavigate();

  // Lista de elementos del menú
  const menuItems = [
    { text: 'Dashboard', icon: <DashboardIcon />, path: '/' },
    { text: 'Dispositivos', icon: <DevicesIcon />, path: '/devices' },
    { text: 'Analíticas', icon: <AssessmentIcon />, path: '/analytics' },
    { text: 'Alertas', icon: <NotificationsIcon />, path: '/alerts' },
    { text: 'Configuración', icon: <SettingsIcon />, path: '/settings' },
  ];

  // Verificar si un item está activo
  const isActive = (path: string) => {
    if (path === '/') {
      return location.pathname === '/';
    }
    return location.pathname.startsWith(path);
  };

  // Manejar clic en un item del menú
  const handleMenuItemClick = (path: string) => {
    navigate(path);
    if (isMobile) {
      onClose();
    }
  };

  // Contenido del drawer
  const drawerContent = (
    <>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'flex-end',
          padding: theme.spacing(0, 1),
          ...theme.mixins.toolbar,
        }}
      >
        <IconButton onClick={onClose}>
          <ChevronLeftIcon />
        </IconButton>
      </Box>
      <Divider />
      <List>
        {menuItems.map((item) => (
          <ListItem key={item.text} disablePadding>
            <ListItemButton
              selected={isActive(item.path)}
              onClick={() => handleMenuItemClick(item.path)}
              sx={{
                '&.Mui-selected': {
                  backgroundColor: 'primary.light',
                  color: 'primary.contrastText',
                  '&:hover': {
                    backgroundColor: 'primary.main',
                  },
                  '& .MuiListItemIcon-root': {
                    color: 'primary.contrastText',
                  },
                },
              }}
            >
              <ListItemIcon
                sx={{
                  color: isActive(item.path) ? 'primary.contrastText' : 'inherit',
                }}
              >
                {item.icon}
              </ListItemIcon>
              <ListItemText primary={item.text} />
            </ListItemButton>
          </ListItem>
        ))}
      </List>
    </>
  );

  return (
    <Drawer
      variant={isMobile ? 'temporary' : 'persistent'}
      open={open}
      onClose={onClose}
      sx={{
        width: drawerWidth,
        flexShrink: 0,
        '& .MuiDrawer-paper': {
          width: drawerWidth,
          boxSizing: 'border-box',
        },
      }}
    >
      {drawerContent}
    </Drawer>
  );
};

export default Sidebar;
EOF

    cat > $FRONTEND_DIR/src/components/layout/Sidebar/index.ts << 'EOF'
export { default } from './Sidebar';
EOF

    # Crear componente de layout - Navbar
    mkdir -p "$FRONTEND_DIR/src/components/layout/Navbar"
    mkdir -p "$FRONTEND_DIR/src/components/layout/Navbar"
    cat > $FRONTEND_DIR/src/components/layout/Navbar/Navbar.tsx << 'EOF'
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import {
  AppBar,
  Toolbar,
  IconButton,
  Typography,
  Box,
  Menu,
  MenuItem,
  Avatar,
  Tooltip,
  Badge
} from '@mui/material';
import MenuIcon from '@mui/icons-material/Menu';
import NotificationsIcon from '@mui/icons-material/Notifications';
import AccountCircleIcon from '@mui/icons-material/AccountCircle';
import { logout } from '../../../redux/slices/authSlice';
import type { AppDispatch, RootState } from '../../../redux/store';

interface NavbarProps {
  onToggleSidebar: () => void;
}

const Navbar = ({ onToggleSidebar }: NavbarProps) => {
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  
  const [anchorElUser, setAnchorElUser] = useState<null | HTMLElement>(null);
  
  const handleOpenUserMenu = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorElUser(event.currentTarget);
  };
  
  const handleCloseUserMenu = () => {
    setAnchorElUser(null);
  };
  
  const handleLogout = async () => {
    handleCloseUserMenu();
    await dispatch(logout());
    navigate('/auth/login');
  };
  
  const handleProfile = () => {
    handleCloseUserMenu();
    navigate('/settings/profile');
  };
  
  return (
    <AppBar position="sticky" color="default" elevation={0} sx={{ borderBottom: '1px solid #e0e0e0' }}>
      <Toolbar>
        <IconButton
          edge="start"
          color="inherit"
          aria-label="menu"
          onClick={onToggleSidebar}
          sx={{ mr: 2 }}
        >
          <MenuIcon />
        </IconButton>
        
        <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
          Plataforma Centralizada
        </Typography>
        
        <Box sx={{ display: 'flex', alignItems: 'center' }}>
          <IconButton color="inherit" sx={{ mr: 1 }}>
            <Badge badgeContent={0} color="error">
              <NotificationsIcon />
            </Badge>
          </IconButton>
          
          <Tooltip title="Abrir configuración">
            <IconButton onClick={handleOpenUserMenu} sx={{ p: 0 }}>
              {user?.avatar ? (
                <Avatar alt={user.fullName || 'Usuario'} src={user.avatar} />
              ) : (
                <Avatar>
                  <AccountCircleIcon />
                </Avatar>
              )}
            </IconButton>
          </Tooltip>
          
          <Menu
            id="menu-appbar"
            anchorEl={anchorElUser}
            open={Boolean(anchorElUser)}
            onClose={handleCloseUserMenu}
            anchorOrigin={{
              vertical: 'bottom',
              horizontal: 'right',
            }}
            transformOrigin={{
              vertical: 'top',
              horizontal: 'right',
            }}
          >
            <MenuItem onClick={handleProfile}>
              <Typography textAlign="center">Perfil</Typography>
            </MenuItem>
            <MenuItem onClick={handleLogout}>
              <Typography textAlign="center">Cerrar Sesión</Typography>
            </MenuItem>
          </Menu>
        </Box>
      </Toolbar>
    </AppBar>
  );
};

export default Navbar;
EOF

    cat > $FRONTEND_DIR/src/components/layout/Navbar/index.ts << 'EOF'
export { default } from './Navbar';
EOF

    # Crear componente de dashboard - StatCard
    mkdir -p "$FRONTEND_DIR/src/components/dashboard/StatCard"
    cat > $FRONTEND_DIR/src/components/dashboard/StatCard/StatCard.tsx << 'EOF'
import { Paper, Box, Typography, Skeleton, Icon } from '@mui/material';

interface StatCardProps {
  title: string;
  value: number;
  icon: string;
  color: string;
  isLoading?: boolean;
}

const StatCard = ({ title, value, icon, color, isLoading = false }: StatCardProps) => {
  return (
    <Paper
      elevation={3}
      sx={{
        height: '100%',
        padding: 2,
        display: 'flex',
        flexDirection: 'column',
        borderTop: `4px solid ${color}`,
      }}
    >
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography variant="h6" component="h2" gutterBottom>
          {title}
        </Typography>
        <Icon sx={{ color, fontSize: 40 }}>{icon}</Icon>
      </Box>
      
      {isLoading ? (
        <Skeleton variant="rectangular" width="60%" height={40} />
      ) : (
        <Typography variant="h3" component="p">
          {value}
        </Typography>
      )}
    </Paper>
  );
};

export default StatCard;
EOF

    cat > $FRONTEND_DIR/src/components/dashboard/StatCard/index.ts << 'EOF'
export { default } from './StatCard';
EOF

    print_message "success" "Archivos de la aplicación React creados correctamente."
}

# Configurar NGINX
configure_nginx() {
    print_message "info" "Configurando NGINX para el frontend..."
    
    # Crear archivo de configuración de sitio para NGINX
    cat > /etc/nginx/sites-available/central-platform << 'EOF'
server {
    listen 80;
    server_name central-platform.local;
    root /opt/central-platform/frontend/build;
    index index.html;

    # Compresión gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Configuración de seguridad
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;";

    # Rutas API
    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Ruta WebSocket
    location /ws/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }

    # Todas las demás solicitudes van al index.html para SPA
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

    # Habilitar el sitio
    ln -sf /etc/nginx/sites-available/central-platform /etc/nginx/sites-enabled/
    
    # Verificar configuración
    nginx -t
    
    # Reiniciar NGINX
    systemctl restart nginx
    
    print_message "success" "NGINX configurado correctamente."
}

# Crear script de despliegue para desarrollo
create_deployment_script() {
    print_message "info" "Creando script de despliegue para desarrollo..."
    
    cat > $BASE_DIR/deploy-frontend-dev.sh << 'EOF'
#!/bin/bash

# Script para desplegar el frontend en modo desarrollo
cd /opt/central-platform/frontend

# Instalar dependencias
npm install

# Iniciar servidor de desarrollo
npm start
EOF

    # Dar permisos de ejecución
    chmod +x $BASE_DIR/deploy-frontend-dev.sh
    
    print_message "success" "Script de despliegue para desarrollo creado."
}

# Crear script de construcción para producción
create_build_script() {
    print_message "info" "Creando script de construcción para producción..."
    
    cat > $BASE_DIR/build-frontend-prod.sh << 'EOF'
#!/bin/bash

# Script para construir el frontend para producción
cd /opt/central-platform/frontend

# Instalar dependencias
npm ci

# Construir para producción
npm run build
EOF

    # Dar permisos de ejecución
    chmod +x $BASE_DIR/build-frontend-prod.sh
    
    print_message "success" "Script de construcción para producción creado."
}

# Configurar permisos
set_permissions() {
    print_message "info" "Configurando permisos..."
    
    # Establecer propietario
    chown -R www-data:www-data $BASE_DIR
    
    # Establecer permisos
    find $BASE_DIR -type d -exec chmod 755 {} \;
    find $BASE_DIR -type f -exec chmod 644 {} \;
    
    # Dar permisos de ejecución a scripts
    chmod +x $BASE_DIR/*.sh
    
    print_message "success" "Permisos configurados correctamente."
}

# Configurar hosts locales
configure_hosts() {
    print_message "info" "Configurando hosts locales..."
    
    # Verificar si ya existe la entrada
    if ! grep -q "central-platform.local" /etc/hosts; then
        echo "127.0.0.1 central-platform.local" >> /etc/hosts
        echo "127.0.0.1 api.central-platform.local" >> /etc/hosts
        print_message "success" "Hosts configurados correctamente."
    else
        print_message "info" "Las entradas de hosts ya existían."
    fi
}

# Función principal
main() {
    print_message "info" "Iniciando despliegue de la Zona A (Frontend) para la Plataforma Centralizada..."
    
    # Crear directorios
    create_directories
    
    # Instalar dependencias
    install_dependencies
    
    # Crear archivos principales
    create_main_files
    
    # Crear archivos de React
    create_react_files
    
    # Configurar NGINX
    configure_nginx
    
    # Crear script de despliegue para desarrollo
    create_deployment_script
    
    # Crear script de construcción para producción
    create_build_script
    
    # Configurar permisos
    set_permissions
    
    # Configurar hosts locales
    configure_hosts
    
    print_message "success" "Despliegue de la Zona A (Frontend) completado correctamente."
    print_message "info" "Para iniciar el servidor de desarrollo, ejecute: $BASE_DIR/deploy-frontend-dev.sh"
    print_message "info" "Para construir la aplicación para producción, ejecute: $BASE_DIR/build-frontend-prod.sh"
    print_message "info" "La aplicación estará disponible en: http://central-platform.local"
}

# Ejecutar función principal
main

exit 0
