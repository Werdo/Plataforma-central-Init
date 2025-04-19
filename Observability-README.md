
Este script integral hace lo siguiente:

1. **Crea una estructura de directorios** completa para la zona de Monitoreo y Observabilidad
2. **Configura todos los componentes** de monitoreo:
   - Prometheus (sistema de monitoreo y almacenamiento de series temporales)
   - Grafana (visualización de datos y dashboards)
   - AlertManager (gestión de alertas)
   - Loki (agregación y búsqueda de logs)
   - Promtail (recolector de logs)
   - Tempo (trazabilidad distribuida)
   - Node Exporter (métricas del sistema)
   - Kube State Metrics (métricas de Kubernetes)

3. **Crea scripts de backup** para persistencia de datos:
   - Backups de Prometheus
   - Backups de Grafana
   - Backups de Loki
   - Configuración de cron para backups automáticos

4. **Proporciona herramientas de gestión**:
   - Exportación e importación de dashboards de Grafana
   - Exportación y creación de alertas de Prometheus

5. **Genera un script de instalación principal** que:
   - Verifica prerrequisitos
   - Despliega todos los componentes en el orden correcto
   - Configura los directorios de backup
   - Establece tareas programadas para backups

El script está diseñado para funcionar en Ubuntu 24.04 LTS y utiliza la función "here document" (EOF) para evitar problemas de interpretación en Bash. Todos los archivos de configuración se crean en sus ubicaciones correspondientes y siguen la estructura del proyecto que definiste.

Para utilizar el script, simplemente guárdalo como un archivo ejecutable y ejecútalo. Después, puedes instalar todo el stack de monitoreo ejecutando el script principal de instalación que se generó.
