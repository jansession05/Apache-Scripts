# Apache Docker Management Script

Una completa solución en Bash para gestionar despliegues de servidores web Apache usando Docker, con capacidades integradas de monitorización a través de Grafana y Prometheus.

## Descripción general

Este script proporciona una interfaz de línea de comandos simple para gestionar servidores web Apache en contenedores Docker. Maneja la creación de redes Docker, volúmenes y contenedores, y ofrece funcionalidad para administrar hosts virtuales.

## Características

- **Despliegue sencillo de Apache**: Despliega un servidor web Apache en Docker con un solo comando
- **Gestión de hosts virtuales**: Crea y elimina hosts virtuales con comandos simples
- **Integración de monitorización**: Soporte integrado para monitorización con Grafana y Prometheus
- **Gestión de contenedores**: Inicia, detiene y comprueba el estado de todos los contenedores
- **Almacenamiento persistente**: Crea automáticamente volúmenes Docker para persistencia de datos

## Requisitos previos

- **Docker instalado y en ejecución** (versión 20.10.7 o superior recomendada)
- **Entorno de shell Bash** (Bash 4.4+)
- **Permisos de sudo** para gestión de contenedores
- **4GB RAM mínimo** para operación con monitorización

## Instalación

1. Clona este repositorio:

```bash
git clone https://github.com/jansession05/Apache-Scripts.git
cd Apache-Scripts
```

2. Haz el script ejecutable:

```bash
chmod +x script.sh
```

## Uso

El script proporciona varios comandos:

```bash
./script.sh [opción] [parámetros]
```

### Opciones disponibles

- `iniciar`: Inicia el contenedor Apache con configuración base
- `estado`: Muestra el estado actual de todos los contenedores
- `crear-sitio <dominio>`: Crea nuevo sitio web con estructura de directorios
- `eliminar-sitio <dominio>`: Elimina sitio web y configuración asociada
- `instalar-monitoreo`: Despliega stack de monitorización (Grafana+Prometheus)
- `detener`: Detiene todos los contenedores asociados
- `ayuda`: Muestra información de ayuda

### Ejemplos

1. **Iniciar servidor Apache**:

```bash
./script.sh iniciar
```

2. **Crear nuevo sitio web**:

```bash
./script.sh crear-sitio ejemplo.com
```

3. **Comprobar estado de contenedores**:

```bash
./script.sh estado
```

4. **Instalar herramientas de monitorización**:

```bash
./script.sh instalar-monitoreo
```

5. **Eliminar sitio web**:

```bash
./script.sh eliminar-sitio ejemplo.com
```

6. **Detener todos los contenedores**:

```bash
./script.sh detener
```

## Estructura de directorios

```
Apache-Scripts/
├── apache-config/
│   ├── sites-available/
│   └── sites-enabled/
├── www-data/
│   └── [dominio]/
│       ├── public_html/
│       └── logs/
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml
│   └── grafana/
│       └── provisioning/
└── script.sh
```

## Monitorización

El sistema incluye estas herramientas:

| Herramienta   | URL Acceso                                     | Función Principal                    |
| ------------- | ---------------------------------------------- | ------------------------------------ |
| Prometheus    | [http://localhost:9090](http://localhost:9090) | Almacenamiento de métricas           |
| Grafana       | [http://localhost:3000](http://localhost:3000) | Visualización de datos (admin/admin) |
| cAdvisor      | [http://localhost:8080](http://localhost:8080) | Monitorización de contenedores       |
| Node Exporter | [http://localhost:9100](http://localhost:9100) | Métricas del sistema host            |

**Configuración recomendada**:

- Importar dashboard **Apache Server Status** en Grafana
- Configurar alertas en Prometheus para uso de CPU >80%
- Usar volumen persistente para datos de Grafana

## Notas importantes

1. **Configuración de hosts**:

Añade dominios a tu archivo `/etc/hosts`:

```
127.0.0.1 ejemplo.com
```

2. **Persistencia de datos**:

- Los volúmenes Docker mantienen datos entre reinicios
- Los logs se almacenan en `www-data/[dominio]/logs/`

3. **Rendimiento**:

Ejemplo de limitación de recursos:

```bash
docker run -d --memory="512m" --cpus="1.5" httpd
```

## Contribuciones

Sigue este flujo:

1. Haz fork del repositorio
2. Crea tu rama:

```bash
git checkout -b feature/nueva-funcionalidad
```

3. Haz commit de tus cambios:

```bash
git commit -am 'Añade nueva funcionalidad'
```

4. Haz push a la rama:

```bash
git push origin feature/nueva-funcionalidad
```

5. Abre un Pull Request

## Licencia

**MIT License** - Ver [LICENSE](LICENSE) para detalles completos.

## Soporte

Para problemas conocidos y soluciones:

- **Contenedor no inicia**: Verificar puertos disponibles (80, 3000, 9090)
- **Permisos denegados**: Ejecutar con `sudo` o añadir usuario al grupo docker
- **Problemas de red**: Verificar configuración de red Docker (`docker network ls`)

## Mejoras planificadas

&#x20;Soporte para Docker Swarm: permitir la orquestación en múltiples nodos para mayor escalabilidad.



&#x20;Auto-configuración de SSL con Let's Encrypt: habilitar HTTPS automático para sitios creados.



&#x20;Integración con CI/CD pipelines: facilitar el despliegue automático desde repositorios como GitHub o GitLab.



&#x20;Interfaz web mínima: crear un panel web ligero para gestionar sitios y contenedores sin usar línea de comandos.



&#x20;Sistema de logs centralizado: añadir integración con herramientas como Loki o ELK stack para visualización avanzada de registros.



&#x20;Compatibilidad con NGINX: posibilidad de desplegar y gestionar servidores web NGINX además de Apache.
