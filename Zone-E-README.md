Continuaré con el script para desplegar la zona E (Persistencia) del proyecto. Aquí tienes la continuación del script donde quedó:

He creado un script completo para desplegar la Zona E (Persistencia) de la Plataforma Centralizada de Información en un sistema Ubuntu 24.04 LTS.

El script `deploy-persistence-zone.sh` realiza las siguientes tareas:

1. Crea la estructura de directorios necesaria para la organización de los archivos
2. Genera todos los archivos Kubernetes (StatefulSets, Services, ConfigMaps, etc.)
3. Configura MongoDB, PostgreSQL, Elasticsearch/Kibana y Redis
4. Crea scripts de backup, restauración y mantenimiento para cada base de datos
5. Genera documentación detallada de los esquemas y configuraciones
6. Crea un script principal de despliegue

## Instrucciones de uso

1. Descarga el script en tu sistema Ubuntu 24.04 LTS
2. Dale permisos de ejecución:
   ```bash
   chmod +x deploy-persistence-zone.sh
   ```
3. Ejecútalo como root:
   ```bash
   sudo ./deploy-persistence-zone.sh
   ```
4. Una vez completado, podrás desplegar la zona E en Kubernetes con:
   ```bash
   sudo /opt/central-platform/deploy-zone-e.sh
   ```

## Componentes generados

- **MongoDB**: Despliega un cluster en modo ReplicaSet con 3 nodos
- **PostgreSQL**: Configura una instancia con esquemas completos
- **Elasticsearch**: Despliega un cluster de 3 nodos con Kibana
- **Redis**: Configura un cluster para caché y mensajería

Cada componente incluye:
- Manifiestos Kubernetes completos
- Scripts de backup y restauración
- Scripts de inicialización y mantenimiento
- Exporters para monitoreo con Prometheus

La documentación generada incluye esquemas detallados, índices, y mejores prácticas para cada sistema de base de datos.

El script usa la sintaxis EOF para la creación de archivos, evitando problemas de interpretación de caracteres especiales en bash, y todos los scripts generados tienen los permisos de ejecución apropiados.
