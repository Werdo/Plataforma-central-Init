He terminado de crear un script de implementación completo para la Zona C (IoT Gateways) de la Plataforma Centralizada de Información. Este script está diseñado específicamente para Ubuntu 24.04 LTS y se encarga de crear toda la estructura de archivos y directorios necesarios para implementar:

1. El Gateway IoT principal
2. El adaptador M2M
3. La configuración de balanceador de carga (HAProxy)
4. Los servicios de apoyo (MongoDB, Redis)

## Características del script

- **Instalación de dependencias**: Instala automáticamente todas las herramientas necesarias como Node.js, Docker y Docker Compose.
- **Estructura completa**: Crea todos los archivos necesarios mediante `cat` con la sintaxis EOF para evitar problemas con caracteres especiales.
- **Configuración Docker**: Incluye archivos Dockerfile y docker-compose.yml para facilitar el despliegue containerizado.
- **Variables de entorno**: Configura archivos .env para personalizar el comportamiento de los servicios.
- **Simulador de dispositivos**: Incluye un simulador de dispositivos IoT básico para pruebas.
- **Script de inicio**: Crea un script `start-gateways.sh` para iniciar todos los servicios fácilmente.

## Cómo usar el script

1. Descarga el script y dale permisos de ejecución: `chmod +x deploy-iot-gateways-zone-c.sh`
2. Ejecútalo: `./deploy-iot-gateways-zone-c.sh`
3. Navega al directorio creado: `cd ~/central-platform/gateways`
4. Inicia los servicios: `./start-gateways.sh`

Una vez completada la instalación, tendrás la infraestructura de la Zona C funcionando y lista para conectarse con los demás componentes de la plataforma centralizada.

## Servicios disponibles

- **IoT Gateway TCP**: Puerto 8080
- **IoT Gateway HTTP**: Puerto 8081
- **M2M Adapter API**: Puerto 8082
- **HAProxy TCP Balance**: Puerto 9080

¿Necesitas alguna modificación o información adicional sobre el script generado?
