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

# Variables globales
APACHE_CONFIG_DIR="./apache-config"
WEB_CONTENT_DIR="./www-data"
MONITORING_DIR="./monitoring"

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

# Función para comprobar si el contenedor Apache está en ejecución
comprobar_apache_activo() {
    if ! docker ps --format '{{.Names}}' | grep -q "^apache-server$"; then
        error_exit "El contenedor 'apache-server' no está en ejecución. Inícialo primero con './script.sh iniciar'."
    fi
}

# Función para crear la red de Docker
crear_red_docker() {
    if ! docker network inspect apache-net &> /dev/null; then
        echo -e "${AMARILLO}Creando red Docker 'apache-net'...${NC}"
        docker network create apache-net || error_exit "No se pudo crear la red Docker"
        echo -e "${VERDE}Red 'apache-net' creada correctamente.${NC}"
    else
        echo -e "${VERDE}La red 'apache-net' ya existe.${NC}"
    fi
}

# Función para crear volúmenes persistentes
crear_volumenes() {
    if ! docker volume inspect apache-logs &> /dev/null; then
        echo -e "${AMARILLO}Creando volumen 'apache-logs' para logs...${NC}"
        docker volume create apache-logs || error_exit "No se pudo crear el volumen apache-logs"
        echo -e "${VERDE}Volumen 'apache-logs' creado correctamente.${NC}"
    else
        echo -e "${VERDE}El volumen 'apache-logs' ya existe.${NC}"
    fi
    # Nota: El volumen apache-data no se usa actualmente, se monta directamente www-data
}

# Función para inicializar la estructura de configuración si no existe
inicializar_configuracion_apache() {
    # Asegurarse de que todos los directorios necesarios existan
    echo -e "${AMARILLO}Asegurando la estructura de directorios de configuración de Apache en $APACHE_CONFIG_DIR...${NC}"
    mkdir -p "$APACHE_CONFIG_DIR/sites-available"
    mkdir -p "$APACHE_CONFIG_DIR/sites-enabled"
    mkdir -p "$APACHE_CONFIG_DIR/mods-available"
    mkdir -p "$APACHE_CONFIG_DIR/mods-enabled"
    mkdir -p "$APACHE_CONFIG_DIR/conf-available"
    mkdir -p "$APACHE_CONFIG_DIR/conf-enabled"

    # Crear configuración por defecto solo si no existen archivos clave
    DEFAULT_SITE_CONF="$APACHE_CONFIG_DIR/sites-available/000-default.conf"
    SERVERNAME_CONF="$APACHE_CONFIG_DIR/conf-available/servername.conf"
    STATUS_MOD_LOAD="$APACHE_CONFIG_DIR/mods-available/status.load"

    if [ ! -f "$DEFAULT_SITE_CONF" ] || [ ! -f "$SERVERNAME_CONF" ] || [ ! -f "$STATUS_MOD_LOAD" ]; then
        echo -e "${AMARILLO}Inicializando archivos de configuración por defecto...${NC}"

        # Crear configuración por defecto del sitio 000-default si no existe
        if [ ! -f "$DEFAULT_SITE_CONF" ]; then
            echo "<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/local/apache2/htdocs

    # Grant access to the document root
    <Directory /usr/local/apache2/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>" > "$DEFAULT_SITE_CONF"
            ln -sf "../sites-available/000-default.conf" "$APACHE_CONFIG_DIR/sites-enabled/000-default.conf"
        fi

        # Crear configuración global de ServerName si no existe
        if [ ! -f "$SERVERNAME_CONF" ]; then
            echo "ServerName localhost" > "$SERVERNAME_CONF"
            ln -sf "../conf-available/servername.conf" "$APACHE_CONFIG_DIR/conf-enabled/servername.conf"
        fi

        # Crear configuración para exponer métricas de Apache (mod_status) si no existe
        STATUS_CONF="$APACHE_CONFIG_DIR/conf-available/server-status.conf"
        if [ ! -f "$STATUS_CONF" ]; then
            echo "<IfModule mod_status.c>
    <Location \"/server-status\">
        SetHandler server-status
        Require all granted
    </Location>
    ExtendedStatus On
</IfModule>" > "$STATUS_CONF"
            ln -sf "../conf-available/server-status.conf" "$APACHE_CONFIG_DIR/conf-enabled/server-status.conf"
        fi

        # Crear archivos .load para módulos comunes si no existen
        REWRITE_MOD_LOAD="$APACHE_CONFIG_DIR/mods-available/rewrite.load"
        if [ ! -f "$REWRITE_MOD_LOAD" ]; then
             echo "LoadModule rewrite_module modules/mod_rewrite.so" > "$REWRITE_MOD_LOAD"
        fi
        if [ ! -f "$STATUS_MOD_LOAD" ]; then
            echo "LoadModule status_module modules/mod_status.so" > "$STATUS_MOD_LOAD"
            # NO LONGER creating link in mods-enabled: ln -sf "../mods-available/status.load" "$APACHE_CONFIG_DIR/mods-enabled/status.load"
        fi

        echo -e "${VERDE}Archivos de configuración por defecto creados/verificados.${NC}"
    else
         echo -e "${VERDE}La estructura de configuración y archivos por defecto ya existen.${NC}"
    fi

    # Crear directorio para el contenido web si no existe
    if [ ! -d "$WEB_CONTENT_DIR" ]; then
        mkdir -p "$WEB_CONTENT_DIR"
        echo "<html><body><h1>¡Bienvenido al servidor Apache en Docker!</h1></body></html>" > "$WEB_CONTENT_DIR/index.html"
        echo -e "${VERDE}Directorio de contenido web $WEB_CONTENT_DIR creado.${NC}"
    fi
}

# Función para iniciar el contenedor de Apache
iniciar_apache() {
    if docker ps -a --format '{{.Names}}' | grep -q "^apache-server$"; then
        echo -e "${AMARILLO}El contenedor 'apache-server' ya existe. Deteniéndolo y eliminándolo...${NC}"
        docker stop apache-server > /dev/null
        docker rm apache-server > /dev/null
    fi

    echo -e "${AMARILLO}Iniciando contenedor Apache 'apache-server'...${NC}"
    inicializar_configuracion_apache # Asegura que la estructura de config existe

    # Crear un httpd.conf personalizado para incluir las configuraciones modulares
    HTTPD_CONF_CUSTOM="$APACHE_CONFIG_DIR/httpd-custom.conf"
    echo "# httpd.conf personalizado para incluir configuraciones modulares
# Definir la variable del directorio de logs estándar
Define APACHE_LOG_DIR /usr/local/apache2/logs

# Carga la configuración por defecto de la imagen
Include /usr/local/apache2/conf/httpd.conf

# Incluir configuraciones habilitadas
IncludeOptional conf-enabled/*.conf
IncludeOptional sites-enabled/*.conf

# Incluir cargas de módulos habilitados
IncludeOptional mods-enabled/*.load
# Incluir configuraciones de módulos habilitados (si existen)
IncludeOptional mods-enabled/*.conf
" > "$HTTPD_CONF_CUSTOM"

    # Iniciar el contenedor con las mejores prácticas
    docker run -d \
        --name apache-server \
        --hostname apache-server \
        --network apache-net \
        -p 80:80 \
        -p 443:443 \
        --restart unless-stopped \
        --health-cmd="curl -f http://localhost/server-status?auto || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --health-start-period=40s \
        --memory="512m" \
        --memory-swap="1g" \
        --cpu-shares=1024 \
        -v "$PWD/$HTTPD_CONF_CUSTOM:/usr/local/apache2/conf/httpd-custom.conf:ro,z" \
        -v "$PWD/$APACHE_CONFIG_DIR/sites-available:/usr/local/apache2/sites-available:ro,z" \
        -v "$PWD/$APACHE_CONFIG_DIR/sites-enabled:/usr/local/apache2/sites-enabled:z" \
        -v "$PWD/$APACHE_CONFIG_DIR/mods-available:/usr/local/apache2/mods-available:ro,z" \
        -v "$PWD/$APACHE_CONFIG_DIR/mods-enabled:/usr/local/apache2/mods-enabled:z" \
        -v "$PWD/$APACHE_CONFIG_DIR/conf-available:/usr/local/apache2/conf-available:ro,z" \
        -v "$PWD/$APACHE_CONFIG_DIR/conf-enabled:/usr/local/apache2/conf-enabled:z" \
        -v "$PWD/$WEB_CONTENT_DIR:/usr/local/apache2/htdocs:z" \
        -v apache-logs:/usr/local/apache2/logs \
        -e TZ=Europe/Madrid \
        --label "com.example.description=Servidor Apache gestionado por script" \
        --label "com.example.department=IT" \
        httpd:2.4 \
        httpd-foreground -f /usr/local/apache2/conf/httpd-custom.conf || error_exit "No se pudo iniciar el contenedor Apache"
        # Usamos httpd-custom.conf que incluye el original y nuestras adiciones

    echo -e "${VERDE}Contenedor Apache iniciado correctamente.${NC}"
    echo -e "${VERDE}Puedes acceder al servidor web en http://localhost${NC}"
    echo -e "${VERDE}Las métricas de estado están en http://localhost/server-status${NC}"
}

# Función para reiniciar Apache (graceful)
reiniciar_apache_contenedor() {
    comprobar_apache_activo
    echo -e "${AMARILLO}Realizando reinicio 'graceful' del contenedor Apache...${NC}"
    docker exec apache-server apachectl -k graceful || echo -e "${ROJO}Advertencia: Falló el reinicio graceful, intentando restart normal...${NC}" && docker exec apache-server apachectl restart
    echo -e "${VERDE}Apache reiniciado.${NC}"
}

# Función para instalar y configurar Grafana y Prometheus
instalar_monitoreo() {
    echo -e "${AMARILLO}Instalando y configurando Grafana, Prometheus y Exporters...${NC}"

    # Detener y eliminar contenedores de monitoreo existentes si existen
    for container in prometheus grafana node-exporter cadvisor apache-exporter; do
        if docker ps -a --format '{{.Names}}' | grep -q "^$container$"; then
            echo -e "${AMARILLO}El contenedor '$container' ya existe. Deteniéndolo y eliminándolo...${NC}"
            docker stop "$container" > /dev/null
            docker rm "$container" > /dev/null
        fi
    done

    # Crear directorios para la configuración
    mkdir -p "$MONITORING_DIR/prometheus"
    mkdir -p "$MONITORING_DIR/grafana/provisioning/datasources"
    mkdir -p "$MONITORING_DIR/grafana/provisioning/dashboards"
    mkdir -p "$MONITORING_DIR/grafana/dashboards"

    # Crear configuración de Prometheus (usando nombres de contenedor)
    echo "global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['prometheus:9090'] # Apunta a sí mismo

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'apache-exporter' # Usar el exporter dedicado
    static_configs:
      - targets: ['apache-exporter:9117']
" > "$MONITORING_DIR/prometheus/prometheus.yml"

    # Crear configuración de datasource para Grafana (usando nombre de contenedor)
    echo '{
    "apiVersion": 1,
    "datasources": [
        {
            "access": "proxy",
            "editable": true,
            "name": "Prometheus",
            "orgId": 1,
            "type": "prometheus",
            "url": "http://prometheus:9090",
            "version": 1,
            "isDefault": true
        }
    ]
}' > "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml"

    # Crear configuración para el proveedor de dashboards de Grafana
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

    # Descargar dashboards para Grafana
    echo -e "${AMARILLO}Descargando dashboards para Grafana...${NC}"
    # Node Exporter Full Dashboard
    curl -s https://grafana.com/api/dashboards/1860/revisions/latest/download -o "$MONITORING_DIR/grafana/dashboards/node-exporter-full.json" || echo -e "${ROJO}Error descargando dashboard Node Exporter.${NC}"
    # Apache Exporter Dashboard
    curl -s https://grafana.com/api/dashboards/3894/revisions/latest/download -o "$MONITORING_DIR/grafana/dashboards/apache-exporter.json" || echo -e "${ROJO}Error descargando dashboard Apache Exporter.${NC}"
    # Docker Monitoring Dashboard (cAdvisor)
    curl -s https://grafana.com/api/dashboards/193/revisions/latest/download -o "$MONITORING_DIR/grafana/dashboards/docker-cadvisor.json" || echo -e "${ROJO}Error descargando dashboard Docker/cAdvisor.${NC}"

    # Ajustar datasource en dashboards descargados (si es necesario, aunque los IDs suelen funcionar)
    # sed -i 's/"datasource": "${DS_PROMETHEUS}"/"datasource": "Prometheus"/g' "$MONITORING_DIR/grafana/dashboards/apache-exporter.json"
    # sed -i 's/"datasource": null/"datasource": "Prometheus"/g' "$MONITORING_DIR/grafana/dashboards/*.json" # Ejemplo más genérico

    # Iniciar Node Exporter
    echo -e "${AMARILLO}Iniciando Node Exporter...${NC}"
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
    echo -e "${AMARILLO}Iniciando cAdvisor...${NC}"
    docker run -d \
        --name cadvisor \
        --hostname cadvisor \
        --network apache-net \
        --restart unless-stopped \
        -p 8080:8080 \
        --volume=/:/rootfs:ro \
        --volume=/var/run:/var/run:rw \
        --volume=/sys:/sys:ro \
        --privileged \
        --device=/dev/kmsg \
        --label "com.example.description=cAdvisor para monitoreo de contenedores" \
        zcube/cadvisor:latest || error_exit "No se pudo iniciar cAdvisor"

    # Iniciar Apache Exporter
    echo -e "${AMARILLO}Iniciando Apache Exporter...${NC}"
    docker run -d \
        --name apache-exporter \
        --hostname apache-exporter \
        --network apache-net \
        --restart unless-stopped \
        -p 9117:9117 \
        --label "com.example.description=Apache Exporter para monitoreo de Apache" \
        lusotycoon/apache-exporter \
        --scrape_uri=http://apache-server/server-status?auto || error_exit "No se pudo iniciar Apache Exporter" 


    # Iniciar Prometheus
    echo -e "${AMARILLO}Iniciando Prometheus...${NC}"
    docker run -d \
        --name prometheus \
        --hostname prometheus \
        --network apache-net \
        --restart unless-stopped \
        -p 9090:9090 \
        --user "$(id -u):$(id -g)" \
        -v "$PWD/$MONITORING_DIR/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro,z" \
        --label "com.example.description=Prometheus para recolección de métricas" \
        prom/prometheus:latest || error_exit "No se pudo iniciar Prometheus"

    # Iniciar Grafana con provisioning
    echo -e "${AMARILLO}Iniciando Grafana...${NC}"
    docker run -d \
        --name grafana \
        --hostname grafana \
        --network apache-net \
        --restart unless-stopped \
        -p 3000:3000 \
        --user "$(id -u):$(id -g)" \
        -v "$PWD/$MONITORING_DIR/grafana/provisioning:/etc/grafana/provisioning:ro,z" \
        -v "$PWD/$MONITORING_DIR/grafana/dashboards:/var/lib/grafana/dashboards:ro,z" \
        -e "GF_SECURITY_ADMIN_USER=admin" \
        -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
        -e "GF_USERS_ALLOW_SIGN_UP=false" \
        -e "GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource" \
        --label "com.example.description=Grafana para visualización de métricas" \
        grafana/grafana:latest || error_exit "No se pudo iniciar Grafana"

    echo -e "${VERDE}Stack de monitorización instalado y configurado correctamente.${NC}"
    echo -e "${VERDE}Puedes acceder a Grafana en http://localhost:3000 (usuario: admin, contraseña: admin)${NC}"
    echo -e "${VERDE}Puedes acceder a Prometheus en http://localhost:9090${NC}"
    echo -e "${VERDE}Dashboards instalados automáticamente.${NC}"
}

# Función para mostrar el estado de los contenedores
mostrar_estado() {
    echo -e "${AZUL}Estado actual de los contenedores gestionados:${NC}"
    docker ps -a --filter "name=apache-server" --filter "name=prometheus" --filter "name=grafana" --filter "name=node-exporter" --filter "name=cadvisor" --filter "name=apache-exporter"

    if docker ps --format '{{.Names}}' | grep -q "^apache-server$"; then
      echo -e "\n${AZUL}Información del contenedor Apache:${NC}"
      docker inspect apache-server --format "Estado: {{.State.Status}}, Salud: {{.State.Health.Status}}"
      echo -e "\n${AZUL}Logs del contenedor Apache (últimas 10 líneas):${NC}"
      docker logs --tail 10 apache-server
    else
      echo -e "\n${AMARILLO}El contenedor apache-server no está en ejecución.${NC}"
    fi
}

# Función para crear un nuevo sitio web
crear_sitio() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar un nombre de dominio para el sitio web (ej: misitio.local)"
    fi

    DOMINIO=$1
    SITIO_CONF_FILE="$APACHE_CONFIG_DIR/sites-available/$DOMINIO.conf"
    SITIO_DOC_ROOT="$WEB_CONTENT_DIR/$DOMINIO"

    if [ -f "$SITIO_CONF_FILE" ]; then
        error_exit "Ya existe un archivo de configuración para $DOMINIO en sites-available."
    fi
    if [ -d "$SITIO_DOC_ROOT" ]; then
        echo -e "${AMARILLO}Advertencia: El directorio $SITIO_DOC_ROOT ya existe.${NC}"
    else
        mkdir -p "$SITIO_DOC_ROOT"
    fi

    echo -e "${AMARILLO}Creando nuevo sitio web para $DOMINIO...${NC}"

    # Crear página de inicio básica
    echo "<html><head><title>Bienvenido a $DOMINIO</title></head><body><h1>¡Éxito! El sitio $DOMINIO funciona.</h1></body></html>" > "$SITIO_DOC_ROOT/index.html"

    # Crear archivo de configuración de Apache
    echo "<VirtualHost *:80>
    ServerName $DOMINIO
    # ServerAlias www.$DOMINIO # Descomentar si se necesita alias www
    DocumentRoot /usr/local/apache2/htdocs/$DOMINIO # Ruta dentro del contenedor

    <Directory /usr/local/apache2/htdocs/$DOMINIO>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMINIO-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMINIO-access.log combined
</VirtualHost>" > "$SITIO_CONF_FILE"

    echo -e "${VERDE}Archivo de configuración $DOMINIO.conf creado en sites-available.${NC}"
    echo -e "${VERDE}Contenido web inicial creado en $SITIO_DOC_ROOT.${NC}"
    echo -e "${AMARILLO}Para activar el sitio, usa: ./script.sh activar-sitio $DOMINIO${NC}"
    echo -e "${AMARILLO}Recuerda añadir '$DOMINIO 127.0.0.1' a tu archivo hosts local si es necesario.${NC}"
}

# Función para activar un sitio web
activar_sitio() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar el nombre del sitio a activar (ej: misitio.local)"
    fi
    DOMINIO=$1
    SITIO_CONF_FILE="$APACHE_CONFIG_DIR/sites-available/$DOMINIO.conf"
    SITIO_ENLACE="$APACHE_CONFIG_DIR/sites-enabled/$DOMINIO.conf"

    if [ ! -f "$SITIO_CONF_FILE" ]; then
        error_exit "El archivo de configuración $DOMINIO.conf no existe en sites-available."
    fi
    if [ -L "$SITIO_ENLACE" ]; then
        echo -e "${AMARILLO}El sitio $DOMINIO ya está activado.${NC}"
        exit 0
    fi

    echo -e "${AMARILLO}Activando sitio web $DOMINIO...${NC}"
    ln -sf "../sites-available/$DOMINIO.conf" "$SITIO_ENLACE"
    reiniciar_apache_contenedor
    echo -e "${VERDE}Sitio web $DOMINIO activado.${NC}"
}

# Función para desactivar un sitio web
desactivar_sitio() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar el nombre del sitio a desactivar (ej: misitio.local)"
    fi
    DOMINIO=$1
    SITIO_ENLACE="$APACHE_CONFIG_DIR/sites-enabled/$DOMINIO.conf"

    if [ "$DOMINIO.conf" == "000-default.conf" ]; then
        error_exit "No se puede desactivar el sitio por defecto 000-default.conf."
    fi

    if [ ! -L "$SITIO_ENLACE" ]; then
        error_exit "El sitio $DOMINIO no está activado actualmente."
    fi

    echo -e "${AMARILLO}Desactivando sitio web $DOMINIO...${NC}"
    rm -f "$SITIO_ENLACE"
    reiniciar_apache_contenedor
    echo -e "${VERDE}Sitio web $DOMINIO desactivado.${NC}"
}

# Función para eliminar un sitio web (configuración y opcionalmente datos)
eliminar_sitio() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar el nombre del sitio a eliminar (ej: misitio.local)"
    fi
    DOMINIO=$1
    SITIO_CONF_FILE="$APACHE_CONFIG_DIR/sites-available/$DOMINIO.conf"
    SITIO_ENLACE="$APACHE_CONFIG_DIR/sites-enabled/$DOMINIO.conf"
    SITIO_DOC_ROOT="$WEB_CONTENT_DIR/$DOMINIO"

    echo -e "${AMARILLO}Eliminando sitio web $DOMINIO...${NC}"

    # Desactivar primero si está activo
    if [ -L "$SITIO_ENLACE" ]; then
        echo -e "${AMARILLO}Desactivando sitio $DOMINIO antes de eliminar...${NC}"
        rm -f "$SITIO_ENLACE"
        NECESITA_REINICIO=1
    else
        NECESITA_REINICIO=0
    fi

    # Eliminar archivo de configuración
    if [ -f "$SITIO_CONF_FILE" ]; then
        rm -f "$SITIO_CONF_FILE"
        echo -e "${VERDE}Archivo de configuración $DOMINIO.conf eliminado de sites-available.${NC}"
    else
        echo -e "${AMARILLO}Advertencia: No se encontró el archivo de configuración $DOMINIO.conf en sites-available.${NC}"
    fi

    # Preguntar si eliminar el contenido web
    read -p "¿Deseas eliminar también el directorio de contenido web '$SITIO_DOC_ROOT'? (s/N): " RESPUESTA
    if [[ "$RESPUESTA" =~ ^[Ss]$ ]]; then
        if [ -d "$SITIO_DOC_ROOT" ]; then
            rm -rf "$SITIO_DOC_ROOT"
            echo -e "${VERDE}Directorio de contenido web $SITIO_DOC_ROOT eliminado.${NC}"
        else
            echo -e "${AMARILLO}Advertencia: No se encontró el directorio de contenido web $SITIO_DOC_ROOT.${NC}"
        fi
    fi

    if [ "$NECESITA_REINICIO" -eq 1 ]; then
        reiniciar_apache_contenedor
    fi

    echo -e "${VERDE}Sitio web $DOMINIO eliminado.${NC}"
}

# Función para activar un módulo de Apache
activar_modulo() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar el nombre del módulo a activar (ej: rewrite)"
    fi
    MODULO=$1
    MODULO_LOAD_FILE="$APACHE_CONFIG_DIR/mods-available/$MODULO.load"
    MODULO_CONF_FILE="$APACHE_CONFIG_DIR/mods-available/$MODULO.conf" # Archivo .conf opcional
    MODULO_LOAD_ENLACE="$APACHE_CONFIG_DIR/mods-enabled/$MODULO.load"
    MODULO_CONF_ENLACE="$APACHE_CONFIG_DIR/mods-enabled/$MODULO.conf"

    if [ ! -f "$MODULO_LOAD_FILE" ]; then
        error_exit "El archivo de carga $MODULO.load no existe en mods-available. Asegúrate de crearlo primero con la directiva LoadModule."
    fi

    NECESITA_REINICIO=0
    if [ ! -L "$MODULO_LOAD_ENLACE" ]; then
        echo -e "${AMARILLO}Activando módulo $MODULO...${NC}"
        ln -sf "../mods-available/$MODULO.load" "$MODULO_LOAD_ENLACE"
        NECESITA_REINICIO=1
    else
        echo -e "${VERDE}El archivo de carga $MODULO.load ya está activado.${NC}"
    fi

    # Activar también el .conf si existe
    if [ -f "$MODULO_CONF_FILE" ]; then
        if [ ! -L "$MODULO_CONF_ENLACE" ]; then
            ln -sf "../mods-available/$MODULO.conf" "$MODULO_CONF_ENLACE"
            echo -e "${VERDE}Archivo de configuración $MODULO.conf activado.${NC}"
            NECESITA_REINICIO=1
        else
             echo -e "${VERDE}El archivo de configuración $MODULO.conf ya está activado.${NC}"
        fi
    fi

    if [ "$NECESITA_REINICIO" -eq 1 ]; then
        reiniciar_apache_contenedor
        echo -e "${VERDE}Módulo $MODULO activado.${NC}"
    fi
}

# Función para desactivar un módulo de Apache
desactivar_modulo() {
    if [ -z "$1" ]; then
        error_exit "Debes especificar el nombre del módulo a desactivar (ej: rewrite)"
    fi
    MODULO=$1
    MODULO_LOAD_ENLACE="$APACHE_CONFIG_DIR/mods-enabled/$MODULO.load"
    MODULO_CONF_ENLACE="$APACHE_CONFIG_DIR/mods-enabled/$MODULO.conf"

    if [ "$MODULO" == "status" ]; then
        echo -e "${AMARILLO}Advertencia: Desactivar 'status' puede afectar la monitorización.${NC}"
    fi

    NECESITA_REINICIO=0
    if [ -L "$MODULO_LOAD_ENLACE" ]; then
        echo -e "${AMARILLO}Desactivando módulo $MODULO...${NC}"
        rm -f "$MODULO_LOAD_ENLACE"
        NECESITA_REINICIO=1
    else
        echo -e "${AMARILLO}El archivo de carga $MODULO.load no está activado.${NC}"
    fi

    if [ -L "$MODULO_CONF_ENLACE" ]; then
        rm -f "$MODULO_CONF_ENLACE"
        echo -e "${VERDE}Archivo de configuración $MODULO.conf desactivado.${NC}"
        NECESITA_REINICIO=1
    fi

    if [ "$NECESITA_REINICIO" -eq 1 ]; then
        reiniciar_apache_contenedor
        echo -e "${VERDE}Módulo $MODULO desactivado.${NC}"
    fi
}

# Función para listar módulos disponibles y activados
listar_modulos() {
    echo -e "${AZUL}Módulos disponibles (en $APACHE_CONFIG_DIR/mods-available):${NC}"
    ls -1 "$APACHE_CONFIG_DIR/mods-available" | sed 's/\.\(load\|conf\)$//' | sort -u || echo "No hay módulos disponibles definidos."

    echo -e "\n${AZUL}Módulos activados (en $APACHE_CONFIG_DIR/mods-enabled):${NC}"
    ls -l "$APACHE_CONFIG_DIR/mods-enabled" | grep '\->' | sed 's/.* -> ..\/mods-available\///' | sed 's/\.\(load\|conf\)$//' | sort -u || echo "No hay módulos activados."
}

# Función para listar sitios disponibles y activados
listar_sitios() {
    echo -e "${AZUL}Sitios disponibles (en $APACHE_CONFIG_DIR/sites-available):${NC}"
    ls -1 "$APACHE_CONFIG_DIR/sites-available" | grep '\.conf$' || echo "No hay sitios disponibles definidos."

    echo -e "\n${AZUL}Sitios activados (en $APACHE_CONFIG_DIR/sites-enabled):${NC}"
    ls -l "$APACHE_CONFIG_DIR/sites-enabled" | grep '\->' | sed 's/.* -> ..\/sites-available\///' || echo "No hay sitios activados."
}

# Función para detener todos los contenedores gestionados
detener_contenedores() {
    echo -e "${AMARILLO}Deteniendo todos los contenedores gestionados...${NC}"
    docker stop apache-server prometheus grafana node-exporter cadvisor apache-exporter > /dev/null 2>&1
    echo -e "${VERDE}Contenedores detenidos.${NC}"
}

# Función para eliminar todos los contenedores, redes y volúmenes (¡CUIDADO!)
limpiar_todo() {
    read -p "${ROJO}¡ADVERTENCIA! Esto eliminará TODOS los contenedores, la red y los volúmenes creados por este script. ¿Estás seguro? (s/N): ${NC}" RESPUESTA
    if [[ "$RESPUESTA" =~ ^[Ss]$ ]]; then
        echo -e "${AMARILLO}Deteniendo y eliminando contenedores...${NC}"
        docker stop apache-server prometheus grafana node-exporter cadvisor apache-exporter > /dev/null 2>&1
        docker rm apache-server prometheus grafana node-exporter cadvisor apache-exporter > /dev/null 2>&1

        echo -e "${AMARILLO}Eliminando red 'apache-net'...${NC}"
        docker network rm apache-net > /dev/null 2>&1

        echo -e "${AMARILLO}Eliminando volumen 'apache-logs'...${NC}"
        docker volume rm apache-logs > /dev/null 2>&1

        # Opcional: Preguntar si eliminar directorios locales
        read -p "¿Deseas eliminar también los directorios locales de configuración ($APACHE_CONFIG_DIR), contenido web ($WEB_CONTENT_DIR) y monitorización ($MONITORING_DIR)? (s/N): " RESP_DIRS
        if [[ "$RESP_DIRS" =~ ^[Ss]$ ]]; then
            echo -e "${AMARILLO}Eliminando directorios locales...${NC}"
            rm -rf "$APACHE_CONFIG_DIR" "$WEB_CONTENT_DIR" "$MONITORING_DIR"
        fi

        echo -e "${VERDE}Limpieza completada.${NC}"
    else
        echo -e "${VERDE}Operación de limpieza cancelada.${NC}"
    fi
}

# Función para mostrar la ayuda
mostrar_ayuda() {
    echo -e "${AZUL}Sistema de Gestión de Servicios Web Apache con Docker${NC}"
    echo -e "Uso: $0 [comando] [argumentos...]"
    echo -e "\n${AZUL}Comandos Principales:${NC}"
    echo -e "  ${VERDE}iniciar${NC}                       Inicia el contenedor Apache (lo recrea si existe)"
    echo -e "  ${VERDE}reiniciar${NC}                     Realiza un reinicio 'graceful' del contenedor Apache"
    echo -e "  ${VERDE}estado${NC}                        Muestra el estado de los contenedores gestionados"
    echo -e "  ${VERDE}detener${NC}                       Detiene todos los contenedores gestionados"
    echo -e "\n${AZUL}Gestión de Sitios Web:${NC}"
    echo -e "  ${VERDE}crear-sitio${NC} <dominio>         Crea la configuración y directorio para un nuevo sitio"
    echo -e "  ${VERDE}activar-sitio${NC} <dominio>       Activa un sitio web existente (crea enlace simbólico)"
    echo -e "  ${VERDE}desactivar-sitio${NC} <dominio>    Desactiva un sitio web (elimina enlace simbólico)"
    echo -e "  ${VERDE}eliminar-sitio${NC} <dominio>      Elimina la configuración de un sitio (y opcionalmente los datos)"
    echo -e "  ${VERDE}listar-sitios${NC}                 Lista los sitios disponibles y activados"
    echo -e "\n${AZUL}Gestión de Módulos Apache:${NC}"
    echo -e "  ${VERDE}activar-modulo${NC} <modulo>       Activa un módulo de Apache (crea enlaces .load/.conf)"
    echo -e "  ${VERDE}desactivar-modulo${NC} <modulo>    Desactiva un módulo de Apache (elimina enlaces)"
    echo -e "  ${VERDE}listar-modulos${NC}                Lista los módulos disponibles y activados"
    echo -e "\n${AZUL}Monitorización:${NC}"
    echo -e "  ${VERDE}instalar-monitoreo${NC}            Instala/Reinstala Grafana, Prometheus y Exporters"
    echo -e "\n${AZUL}Otros Comandos:${NC}"
    echo -e "  ${VERDE}limpiar-todo${NC}                  ${ROJO}¡PELIGRO!${NC} Elimina contenedores, red y volúmenes"
    echo -e "  ${VERDE}ayuda${NC}                         Muestra esta ayuda"
    echo -e "\n${AZUL}Notas:${NC}"
    echo -e "  - La configuración de Apache se gestiona en el directorio local '$APACHE_CONFIG_DIR'"
    echo -e "  - El contenido web se encuentra en '$WEB_CONTENT_DIR'"
    echo -e "  - La configuración de monitorización está en '$MONITORING_DIR'"
    echo -e "  - Los cambios en sitios/módulos requieren reiniciar Apache (se hace automáticamente)"
}

# Función principal
main() {
    comprobar_docker

    # Procesar argumentos
    case "$1" in
        iniciar)
            crear_red_docker
            crear_volumenes
            iniciar_apache
            ;;
        reiniciar)
            reiniciar_apache_contenedor
            ;;
        estado)
            mostrar_estado
            ;;
        crear-sitio)
            crear_sitio "$2"
            ;;
        activar-sitio)
            activar_sitio "$2"
            ;;
        desactivar-sitio)
            desactivar_sitio "$2"
            ;;
        eliminar-sitio)
            eliminar_sitio "$2"
            ;;
        listar-sitios)
            listar_sitios
            ;;
        activar-modulo)
            activar_modulo "$2"
            ;;
        desactivar-modulo)
            desactivar_modulo "$2"
            ;;
        listar-modulos)
            listar_modulos
            ;;
        instalar-monitoreo)
            crear_red_docker # Asegura que la red existe
            instalar_monitoreo
            ;;
        detener)
            detener_contenedores
            ;;
        limpiar-todo)
            limpiar_todo
            ;;
        ayuda|--help|-h|*)
            mostrar_ayuda
            ;;
    esac
}

# Ejecutar la función principal pasando todos los argumentos
main "$@"