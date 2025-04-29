#!/bin/bash

# =====================================================
# Script de Gestión de Servicios Web Apache con Docker
# =====================================================

# Colores para una mejor visualización
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[0;33m'
AZUL='\033[0;34m'
NC='\033[0m' # Sin Color

# Función para mostrar mensajes de error y salir
error_exit() {
    echo -e "${ROJO}Error: $1${NC}" >&2
    exit 1
}

# Función para comprobar si Docker está instalado
comprobar_docker() {
    if ! command -v docker &> /dev/null; then
        error_exit "Docker no está instalado. Por favor, instálalo primero."
    fi
    
    if ! docker info &> /dev/null; then
        error_exit "El servicio Docker no está en ejecución o no tienes permisos suficientes."
    fi
}
# Función para comprobar si el usuario tiene permisos de administrador
comprobar_permisos_admin() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "Este script debe ejecutarse con permisos de administrador (root)."
    fi
}
# Función para comprobar si el usuario tiene permisos de administrador
comprobar_permisos_admin() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "Este script debe ejecutarse con permisos de administrador (root)."
    fi
}

# Función para crear la red de Docker
crear_red_docker() {
    # Comprobar si la red ya existe
    if ! docker network inspect apache-net &> /dev/null; then
        echo -e "${AMARILLO}Creando red Docker para los servicios Apache...${NC}"
        docker network create apache-net || error_exit "No se pudo crear la red Docker"
        echo -e "${VERDE}Red 'apache-net' creada correctamente.${NC}"
    else
        echo -e "${VERDE}La red 'apache-net' ya existe.${NC}"
    fi
}

# Función para crear volúmenes persistentes
crear_volumenes() {
    # Comprobar si los volúmenes ya existen
    if ! docker volume inspect apache-data &> /dev/null; then
        echo -e "${AMARILLO}Creando volumen para datos de Apache...${NC}"
        docker volume create apache-data || error_exit "No se pudo crear el volumen apache-data"
        echo -e "${VERDE}Volumen 'apache-data' creado correctamente.${NC}"
    else
        echo -e "${VERDE}El volumen 'apache-data' ya existe.${NC}"
    fi
    
    if ! docker volume inspect apache-logs &> /dev/null; then
        echo -e "${AMARILLO}Creando volumen para logs de Apache...${NC}"
        docker volume create apache-logs || error_exit "No se pudo crear el volumen apache-logs"
        echo -e "${VERDE}Volumen 'apache-logs' creado correctamente.${NC}"
    else
        echo -e "${VERDE}El volumen 'apache-logs' ya existe.${NC}"
    fi
}

# Función para iniciar el contenedor de Apache
iniciar_apache() {
    # Comprobar si el contenedor ya existe
    if docker ps -a --format '{{.Names}}' | grep -q "^apache-server$"; then
        echo -e "${AMARILLO}El contenedor 'apache-server' ya existe. Deteniéndolo...${NC}"
        docker stop apache-server
        docker rm apache-server
    fi
    
    echo -e "${AMARILLO}Iniciando contenedor Apache...${NC}"
    
    # Crear directorio para la configuración personalizada si no existe
    APACHE_CONFIG_DIR="./apache-config"
    if [ ! -d "$APACHE_CONFIG_DIR" ]; then
        mkdir -p "$APACHE_CONFIG_DIR/sites-available"
        mkdir -p "$APACHE_CONFIG_DIR/sites-enabled"
        mkdir -p "$APACHE_CONFIG_DIR/conf-available"
        mkdir -p "$APACHE_CONFIG_DIR/conf-enabled"
        
        # Crear un archivo de configuración de ejemplo
        echo "<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" > "$APACHE_CONFIG_DIR/sites-available/000-default.conf"
        
        # Crear enlace simbólico
        ln -sf "../sites-available/000-default.conf" "$APACHE_CONFIG_DIR/sites-enabled/000-default.conf"
        
        # Crear configuración global de ServerName
        echo "ServerName localhost" > "$APACHE_CONFIG_DIR/conf-available/servername.conf"
        ln -sf "../conf-available/servername.conf" "$APACHE_CONFIG_DIR/conf-enabled/servername.conf"
    fi
    
    # Crear directorio para el contenido web si no existe
    WEB_CONTENT_DIR="./www-data"
    if [ ! -d "$WEB_CONTENT_DIR" ]; then
        mkdir -p "$WEB_CONTENT_DIR"
        echo "<html><body><h1>¡Bienvenido al servidor Apache en Docker!</h1></body></html>" > "$WEB_CONTENT_DIR/index.html"
    fi
    
    # Iniciar el contenedor con las mejores prácticas
    docker run -d \
        --name apache-server \
        --hostname apache-server \
        --network apache-net \
        -p 80:80 \
        -p 443:443 \
        --restart unless-stopped \
        --health-cmd="curl --fail http://localhost/ || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --health-start-period=40s \
        --memory="512m" \
        --memory-swap="1g" \
        --cpu-shares=1024 \
        -v "$PWD/$APACHE_CONFIG_DIR/sites-available:/etc/apache2/sites-available" \
        -v "$PWD/$APACHE_CONFIG_DIR/sites-enabled:/etc/apache2/sites-enabled" \
        -v "$PWD/$APACHE_CONFIG_DIR/conf-available:/etc/apache2/conf-available" \
        -v "$PWD/$APACHE_CONFIG_DIR/conf-enabled:/etc/apache2/conf-enabled" \
        -v "$PWD/$WEB_CONTENT_DIR:/var/www/html" \
        -v apache-logs:/var/log/apache2 \
        -e TZ=Europe/Madrid \
        -e APACHE_SERVER_NAME=localhost \
        --label "com.example.description=Servidor Apache para desarrollo web" \
        --label "com.example.department=IT" \
        --label "com.example.label-with-empty-value" \
        httpd:2.4-alpine || error_exit "No se pudo iniciar el contenedor Apache"
    
    echo -e "${VERDE}Contenedor Apache iniciado correctamente.${NC}"
    echo -e "${VERDE}Puedes acceder al servidor web en http://localhost${NC}"
}

# Función para instalar y configurar Grafana y Prometheus
instalar_monitoreo() {
    echo -e "${AMARILLO}Instalando y configurando Grafana y Prometheus para monitorización...${NC}"
    
    # Comprobar si los contenedores ya existen
    if docker ps -a --format '{{.Names}}' | grep -q "^prometheus$"; then
        echo -e "${AMARILLO}El contenedor 'prometheus' ya existe. Deteniéndolo...${NC}"
        docker stop prometheus
        docker rm prometheus
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^grafana$"; then
        echo -e "${AMARILLO}El contenedor 'grafana' ya existe. Deteniéndolo...${NC}"
        docker stop grafana
        docker rm grafana
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^node-exporter$"; then
        echo -e "${AMARILLO}El contenedor 'node-exporter' ya existe. Deteniéndolo...${NC}"
        docker stop node-exporter
        docker rm node-exporter
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^cadvisor$"; then
        echo -e "${AMARILLO}El contenedor 'cadvisor' ya existe. Deteniéndolo...${NC}"
        docker stop cadvisor
        docker rm cadvisor
    fi
    
    # Crear directorios para la configuración
    MONITORING_DIR="./monitoring"
    mkdir -p "$MONITORING_DIR/prometheus"
    mkdir -p "$MONITORING_DIR/grafana/provisioning/datasources"
    mkdir -p "$MONITORING_DIR/grafana/provisioning/dashboards"
    
    # Crear configuración de Prometheus
    echo "global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'apache'
    static_configs:
      - targets: ['apache-server:80']
    metrics_path: /server-status
    params:
      format: [prometheus]" > "$MONITORING_DIR/prometheus/prometheus.yml"
    
    # Crear configuración de datasource para Grafana
    echo '{
    "apiVersion": 1,
    "datasources": [
        {
            "access": "proxy",
            "editable": true,
            "name": "Prometheus",
            "orgId": 1,
            "type": "prometheus",
            "url": "http://10.30.8.94:9090",
            "version": 1
        }
    ]
}' > "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml"

    # Crear configuración para el dashboard de Node Exporter
    echo '{
    "apiVersion": 1,
    "providers": [
        {
            "name": "Default",
            "orgId": 1,
            "folder": "",
            "type": "file",
            "disableDeletion": false,
            "updateIntervalSeconds": 10,
            "allowUiUpdates": true,
            "options": {
                "path": "/var/lib/grafana/dashboards",
                "foldersFromFilesStructure": true
            }
        }
    ]
}' > "$MONITORING_DIR/grafana/provisioning/dashboards/default.yml"

    # Crear directorio para los dashboards
    mkdir -p "$MONITORING_DIR/grafana/dashboards"
    
    # Descargar el dashboard de Node Exporter
    echo -e "${AMARILLO}Descargando dashboard de Node Exporter para Grafana...${NC}"
    curl -s https://grafana.com/api/dashboards/1860/revisions/27/download > "$MONITORING_DIR/grafana/dashboards/node-exporter.json"
    
    # Iniciar Node Exporter
    docker run -d \
        --name node-exporter \
        --hostname node-exporter \
        --network apache-net \
        --restart unless-stopped \
        -p 9100:9100 \
        -v "/proc:/host/proc:ro" \
        -v "/sys:/host/sys:ro" \
        -v "/:/rootfs:ro" \
        --label "com.example.description=Node Exporter para monitoreo del sistema" \
        prom/node-exporter:latest \
        --path.procfs=/host/proc \
        --path.sysfs=/host/sys \
        --path.rootfs=/rootfs \
        --collector.filesystem.ignored-mount-points="^/(sys|proc|dev|host|etc)($$|/)" || error_exit "No se pudo iniciar Node Exporter"
    
    # Iniciar cAdvisor
    docker run -d \
        --name cadvisor \
        --hostname cadvisor \
        --network apache-net \
        --restart unless-stopped \
        -p 8080:8080 \
        --volume=/:/rootfs:ro \
        --volume=/var/run:/var/run:ro \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:ro \
        --volume=/dev/disk/:/dev/disk:ro \
        --label "com.example.description=cAdvisor para monitoreo de contenedores" \
        gcr.io/cadvisor/cadvisor:latest || error_exit "No se pudo iniciar cAdvisor"
    
    # Iniciar Prometheus
    docker run -d \
        --name prometheus \
        --hostname prometheus \
        --network apache-net \
        --restart unless-stopped \
        -p 9090:9090 \
        -v "$PWD/$MONITORING_DIR/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml" \
        --label "com.example.description=Prometheus para recolección de métricas" \
        prom/prometheus:latest || error_exit "No se pudo iniciar Prometheus"
    
    # Iniciar Grafana con provisioning
    docker run -d \
        --name grafana \
        --hostname grafana \
        --network apache-net \
        --restart unless-stopped \
        -p 3000:3000 \
        -v "$PWD/$MONITORING_DIR/grafana/provisioning:/etc/grafana/provisioning" \
        -v "$PWD/$MONITORING_DIR/grafana/dashboards:/var/lib/grafana/dashboards" \
        -e "GF_SECURITY_ADMIN_USER=admin" \
        -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
        -e "GF_USERS_ALLOW_SIGN_UP=false" \
        -e "GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource" \
        --label "com.example.description=Grafana para visualización de métricas" \
        grafana/grafana:latest || error_exit "No se pudo iniciar Grafana"
    
    echo -e "${VERDE}Grafana y Prometheus instalados y configurados correctamente.${NC}"
    echo -e "${VERDE}Puedes acceder a Grafana en http://localhost:3000 (usuario: admin, contraseña: admin)${NC}"
    echo -e "${VERDE}Prometheus configurado con la dirección 10.30.8.94:9090${NC}"
    echo -e "${VERDE}Dashboard de Node Exporter instalado automáticamente${NC}"
}

# Función para mostrar el estado de los contenedores
mostrar_estado() {
    echo -e "${AZUL}Estado actual de los contenedores:${NC}"
    docker ps -a --filter "name=apache-server" --filter "name=prometheus" --filter "name=grafana" --filter "name=node-exporter" --filter "name=cadvisor"
    
    echo -e "\n${AZUL}Información del contenedor Apache:${NC}"
    docker inspect apache-server --format "{{.State.Status}}" 2>/dev/null || echo "El contenedor apache-server no existe"
    
    echo -e "\n${AZUL}Logs del contenedor Apache (últimas 10 líneas):${NC}"
    docker logs --tail 10 apache-server 2>/dev/null || echo "No se pueden obtener los logs del contenedor apache-server"
}

# Función para crear un nuevo sitio web
crear_sitio() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar un nombre para el sitio web"
    fi
    
    SITIO=$1
    echo -e "${AMARILLO}Creando un nuevo sitio web para $SITIO...${NC}"
    
    # Crear directorio para el sitio web
    mkdir -p "./www-data/$SITIO"
    
    # Crear página de inicio básica
    echo "<html>
<head>
    <title>Bienvenido a $SITIO</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Bienvenido a $SITIO</h1>
    <p>Esta es la página de inicio de $SITIO.</p>
    <p>Personaliza este contenido según tus necesidades.</p>
</body>
</html>" > "./www-data/$SITIO/index.html"
    
    # Crear archivo de configuración de Apache
    echo "<VirtualHost *:80>
    ServerName $SITIO
    ServerAlias www.$SITIO
    DocumentRoot /var/www/html/$SITIO
    
    <Directory /var/www/html/$SITIO>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error-$SITIO.log
    CustomLog \${APACHE_LOG_DIR}/access-$SITIO.log combined
</VirtualHost>" > "./apache-config/sites-available/$SITIO.conf"
    
    # Crear enlace simbólico para activar el sitio
    ln -sf "../sites-available/$SITIO.conf" "./apache-config/sites-enabled/$SITIO.conf"
    
    # Reiniciar Apache para aplicar los cambios
    docker exec apache-server apachectl configtest
    docker exec apache-server apachectl restart
    
    echo -e "${VERDE}Sitio web $SITIO creado y activado correctamente.${NC}"
    echo -e "${VERDE}Recuerda añadir una entrada en tu archivo hosts para $SITIO apuntando a 127.0.0.1${NC}"
}

# Función para eliminar un sitio web
eliminar_sitio_web() {
    if [ -z "$1" ]; then
        error_exit "Por favor, proporciona el nombre del sitio web a eliminar."
    fi
    
    DOMINIO=$1
    
    echo -e "${AMARILLO}Eliminando el sitio web $DOMINIO...${NC}"
    
    # Desactivar el sitio web
    rm -f "$APACHE_CONFIG_DIR/sites-enabled/$DOMINIO.conf"
    
    # Eliminar el archivo de configuración
    rm -f "$APACHE_CONFIG_DIR/sites-available/$DOMINIO.conf"
    
    # Preguntar si también se han de eliminar los archivos
    read -p "¿Quieres eliminar también los archivos del sitio web? (s/n): " ELIMINAR_ARCHIVOS
    if [[ $ELIMINAR_ARCHIVOS =~ ^[Ss]$ ]]; then
        rm -rf "$WEB_CONTENT_DIR/$DOMINIO"
        echo -e "${VERDE}Archivos del sitio web eliminados.${NC}"
    fi
    
    # Reiniciar Apache
    docker exec apache-server apachectl -k graceful
    
    echo -e "${VERDE}Sitio web $DOMINIO eliminado correctamente.${NC}"
}

# Función para detener todos los contenedores
detener_contenedores() {
    echo -e "${AMARILLO}Deteniendo todos los contenedores...${NC}"
    
    docker stop apache-server prometheus grafana node-exporter cadvisor 2>/dev/null
    
    echo -e "${VERDE}Contenedores detenidos correctamente.${NC}"
}

# Función para mostrar la ayuda
mostrar_ayuda() {
    echo -e "${AZUL}Sistema de Gestión de Servicios Web Apache con Docker${NC}"
    echo -e "Uso: $0 [opción] [parámetros]"
    echo -e "\nOpciones:"
    echo -e "  ${VERDE}iniciar${NC}                       Inicia el contenedor Apache"
    echo -e "  ${VERDE}estado${NC}                        Muestra el estado actual de los contenedores"
    echo -e "  ${VERDE}crear-sitio${NC} <dominio>         Crea un nuevo sitio web"
    echo -e "  ${VERDE}eliminar-sitio${NC} <dominio>      Elimina un sitio web existente"
    echo -e "  ${VERDE}instalar-monitoreo${NC}            Instala Grafana y Prometheus para monitorización"
    echo -e "  ${VERDE}detener${NC}                       Detiene todos los contenedores"
    echo -e "  ${VERDE}ayuda${NC}                         Muestra esta ayuda"
}

# Función principal
main() {
    # Comprobar si Docker está instalado
    comprobar_docker
    
    # Processar argumentos
    case "$1" in
        iniciar)
            crear_red_docker
            crear_volumenes
            iniciar_apache
            ;;
        estado)
            mostrar_estado
            ;;
        crear-sitio)
            crear_sitio "$2"
            ;;
        eliminar-sitio)
            eliminar_sitio_web "$2"
            ;;
        instalar-monitoreo)
            crear_red_docker
            instalar_monitoreo
            ;;
        detener)
            detener_contenedores
            ;;
        ayuda|*)
            mostrar_ayuda
            ;;
    esac
}

# Ejecutar la función principal
main "$@"