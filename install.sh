#!/bin/bash

################################################################################
# SCRIPT DE INSTALACIÓN AUTOMATIZADA DEL STACK DE STREAMING LOCAL
# Para Orange Pi 5 Plus con Armbian
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

################################################################################
# VARIABLES DE CONFIGURACIÓN
################################################################################

BASE_DIR="/opt/streaming"
SCRIPT_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/configs"
LOG_DIR="${BASE_DIR}/logs"
DATA_DIR="${BASE_DIR}/data"
VIDEO_INPUT="${BASE_DIR}/entrada"
VIDEO_PROCESS="${BASE_DIR}/procesando"
VIDEO_OUTPUT="${BASE_DIR}/final"
JELLYFIN_CONFIG="${CONFIG_DIR}/jellyfin"
JELLYFIN_CACHE="${DATA_DIR}/jellyfin/cache"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# FUNCIONES DE LOGGING
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# FUNCIONES DE VERIFICACIÓN
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

check_hardware() {
    log_info "Verificando hardware..."
    
    # Verificar ARM
    if [[ $(uname -m) != "aarch64" ]]; then
        log_warning "Arquitectura no es ARM64, se procederá con precaución"
    else
        log_success "Arquitectura ARM64 detectada"
    fi
    
    # Verificar memoria RAM (mínimo 4GB recomendado)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $RAM_GB -lt 4 ]]; then
        log_warning "Memoria RAM baja (${RAM_GB}GB), se recomienda mínimo 4GB"
    else
        log_success "Memoria RAM: ${RAM_GB}GB"
    fi
    
    # Verificar espacio en disco (mínimo 10GB libre)
    DISK_FREE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $DISK_FREE -lt 10 ]]; then
        log_error "Espacio en disco insuficiente (${DISK_FREE}GB libre, mínimo 10GB)"
        exit 1
    else
        log_success "Espacio en disco: ${DISK_FREE}GB libre"
    fi
    
    # Verificar dispositivos DRI para aceleración GPU
    if [[ -d /dev/dri ]]; then
        log_success "Dispositivos DRI detectados:"
        ls -la /dev/dri/
        
        # Verificar render group
        if getent group render > /dev/null 2>&1; then
            RENDER_GROUP_ID=$(getent group render | cut -d: -f3)
            log_success "Render group existe (ID: ${RENDER_GROUP_ID})"
        else
            log_warning "Render group no existe, se creará automáticamente"
            RENDER_GROUP_ID=122
        fi
    else
        log_warning "Dispositivos DRI no detectados, aceleración hardware no disponible"
        RENDER_GROUP_ID=122
    fi
    
    # Verificar dispositivos V4L2 para aceleración de video
    V4L2_DEVICES=$(ls /dev/video* 2>/dev/null | wc -l)
    if [[ $V4L2_DEVICES -gt 0 ]]; then
        log_success "Dispositivos V4L2 detectados: ${V4L2_DEVICES}"
        for dev in /dev/video*; do
            name=$(cat "/sys/class/video4linux/$(basename $dev)/name" 2>/dev/null || echo "desconocido")
            echo "       ${dev} -> ${name}"
        done
    else
        log_warning "Dispositivos V4L2 no detectados"
    fi
}

check_docker() {
    log_info "Verificando Docker..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker ya instalado: versión ${DOCKER_VERSION}"
    else
        log_info "Docker no instalado, se instalará automáticamente"
        return 1
    fi
}

################################################################################
# FUNCIONES DE INSTALACIÓN
################################################################################

install_dependencies() {
    log_info "Actualizando repositorios y paquetes..."
    apt update
    
    log_info "Instalando dependencias base..."
    apt install -y \
        curl \
        git \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        inotify-tools \
        python3 \
        python3-pip \
        ufw
    
    log_success "Dependencias instaladas"
}

install_docker() {
    log_info "Instalando Docker..."
    
    # Agregar repositorio Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Habilitar Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker instalado correctamente"
}

create_render_group() {
    if ! getent group render > /dev/null 2>&1; then
        log_info "Creando grupo render (ID: 122)..."
        groupadd -g 122 render
        log_success "Grupo render creado"
    fi
    
    # Agregar usuario actual a grupos necesarios
    CURRENT_USER=$(logname)
    usermod -aG docker ${CURRENT_USER}
    usermod -aG render ${CURRENT_USER}
    usermod -aG video ${CURRENT_USER}
    
    log_success "Usuario ${CURRENT_USER} agregado a grupos: docker, render, video"
}

create_directory_structure() {
    log_info "Creando estructura de directorios..."
    
    mkdir -p "${BASE_DIR}"
    mkdir -p "${SCRIPT_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${VIDEO_INPUT}"
    mkdir -p "${VIDEO_PROCESS}"
    mkdir -p "${VIDEO_OUTPUT}"
    mkdir -p "${JELLYFIN_CONFIG}"
    mkdir -p "${JELLYFIN_CACHE}"
    
    # Crear subcarpetas para clasificación
    mkdir -p "${VIDEO_INPUT}/Peliculas"
    mkdir -p "${VIDEO_INPUT}/Series"
    mkdir -p "${VIDEO_OUTPUT}/Peliculas"
    mkdir -p "${VIDEO_OUTPUT}/Series"
    
    # Crear archivo .keep en directorios vacíos
    touch "${VIDEO_INPUT}/.keep"
    touch "${VIDEO_PROCESS}/.keep"
    touch "${VIDEO_OUTPUT}/.keep"
    
    # Establecer permisos
    chown -R ${CURRENT_USER}:${CURRENT_USER} "${BASE_DIR}"
    chmod -R 755 "${BASE_DIR}"
    chmod 777 "${VIDEO_INPUT}" "${VIDEO_PROCESS}" "${VIDEO_OUTPUT}"
    
    log_success "Estructura de directorios creada en ${BASE_DIR}"
}

pull_docker_images() {
    log_info "Descargando imagen Docker de Jellyfin con aceleración hardware..."
    
    # Imagen nyanmisaka con soporte RKMPP + V4L2 para RK3588
    if docker image inspect nyanmisaka/jellyfin:latest-rockchip > /dev/null 2>&1; then
        log_success "Imagen Docker nyanmisaka/jellyfin:latest-rockchip ya existe"
    else
        docker pull nyanmisaka/jellyfin:latest-rockchip
        log_success "Imagen Docker nyanmisaka/jellyfin:latest-rockchip descargada"
    fi
    
    # Limpiar imagen ffmpeg-arm64 vieja si existe (ya no se necesita)
    if docker image inspect ffmpeg-arm64 > /dev/null 2>&1; then
        log_info "Eliminando imagen Docker ffmpeg-arm64 obsoleta..."
        docker rm -f ffmpeg 2>/dev/null || true
        docker rmi ffmpeg-arm64 2>/dev/null || true
        log_success "Imagen ffmpeg-arm64 eliminada"
    fi
}

get_docker_devices() {
    local devices=""
    local has_device=false
    
    # Device /dev/dri
    if [[ -e /dev/dri ]]; then
        devices="${devices}      - /dev/dri:/dev/dri\n"
        has_device=true
    fi
    
    # Device /dev/dma_heap
    if [[ -e /dev/dma_heap ]]; then
        devices="${devices}      - /dev/dma_heap:/dev/dma_heap\n"
        has_device=true
    fi
    
    # V4L2 video devices (RK3588 con kernel 6.x)
    for device in /dev/video*; do
        if [[ -e "$device" ]]; then
            devices="${devices}      - ${device}:${device}\n"
            has_device=true
        fi
    done
    
    # V4L2 media devices
    for device in /dev/media*; do
        if [[ -e "$device" ]]; then
            devices="${devices}      - ${device}:${device}\n"
            has_device=true
        fi
    done
    
    # Legacy rockchip devices (solo si existen)
    for device in /dev/mali0 /dev/rga /dev/mpp_service; do
        if [[ -e "$device" ]]; then
            devices="${devices}      - ${device}:${device}\n"
            has_device=true
        fi
    done
    
    if [[ "$has_device" == "true" ]]; then
        echo "    devices:"
        echo -e "$devices"
    fi
}

create_docker_compose() {
    log_info "Creando archivo docker-compose.yml..."
    
    RENDER_GROUP_ID=${RENDER_GROUP_ID:-122}
    DOCKER_DEVICES=$(get_docker_devices)
    
    cat > "${BASE_DIR}/docker-compose.yml" << EOF
services:
  jellyfin:
    image: nyanmisaka/jellyfin:latest-rockchip
    container_name: jellyfin
    user: 1000:1000
    group_add:
      - '${RENDER_GROUP_ID}'
      - '44'
$DOCKER_DEVICES
    volumes:
      - ${JELLYFIN_CONFIG}:/config
      - ${JELLYFIN_CACHE}:/cache
      - ${VIDEO_OUTPUT}:/media
      - ${VIDEO_PROCESS}:/videos
    network_mode: host
    restart: unless-stopped
    environment:
      - TZ=${TZ:-UTC}
EOF

    log_success "Archivo docker-compose.yml creado"
}

create_processing_scripts() {
    log_info "Creando scripts de procesamiento..."
    
    # Script principal de procesamiento
    cat > "${SCRIPT_DIR}/process_video.sh" << 'PROCESS_EOF'
#!/bin/bash

# Cargar configuración
source /opt/streaming/scripts/config.sh

VIDEO_FILE="$1"
if [[ -z "$VIDEO_FILE" ]]; then
    echo "Uso: $0 <archivo_video>"
    exit 1
fi

JUST_FILENAME=$(basename "$VIDEO_FILE")
BASE_NAME=$(echo "$JUST_FILENAME" | sed 's/\.[^.]*$//')
EXT="${VIDEO_FILE##*.}"

LOG_FILE="/opt/streaming/logs/process_${BASE_NAME}.log"
INPUT_DIR="/opt/streaming/entrada"
PROCESS_DIR="/opt/streaming/procesando"
OUTPUT_DIR="/opt/streaming/final"

# Rutas de ffmpeg/ffprobe dentro del contenedor Jellyfin
FFMPEG_BIN="/usr/lib/jellyfin-ffmpeg/ffmpeg"
FFPROBE_BIN="/usr/lib/jellyfin-ffmpeg/ffprobe"
DOCKER_CONTAINER="jellyfin"

# Detectar si el archivo viene de una subcarpeta (Peliculas o Series)
# Extraer la ruta relativa completa (ej: Series/Mi Serie/Season 1)
RELATIVE_PATH=$(dirname "$VIDEO_FILE")

# Validar que esté dentro de Peliculas o Series
if [[ "$RELATIVE_PATH" != "Peliculas"* && "$RELATIVE_PATH" != "Series"* ]]; then
    echo "Advertencia: El archivo no está en Peliculas/ o Series/ ($RELATIVE_PATH)"
    # Aún así procesamos, pero mantenemos la estructura
fi

# Función de limpieza en caso de error
cleanup_on_error() {
    echo "ERROR: Proceso interrumpido o fallido para ${JUST_FILENAME}"
    # Eliminar archivo parcial de recodificación si existe
    rm -f "${PROCESS_DIR}/${BASE_NAME}_recode.mp4"
    # Devolver archivo original a entrada/ si sigue en procesando/
    if [[ -f "${PROCESS_DIR}/${JUST_FILENAME}" ]]; then
        echo "Devolviendo ${JUST_FILENAME} a entrada/..."
        # Crear directorio destino en entrada si no existe
        mkdir -p "${INPUT_DIR}/${RELATIVE_PATH}"
        mv "${PROCESS_DIR}/${JUST_FILENAME}" "${INPUT_DIR}/${RELATIVE_PATH}/${JUST_FILENAME}"
        echo "Archivo devuelto a entrada/ para reprocesar"
    fi
}

{
    echo "=== $(date) ==="
    echo "Procesando: $VIDEO_FILE"
    echo "Configuración: codec=$VIDEO_CODEC_TARGET/$AUDIO_CODEC_TARGET, crf=$VIDEO_CRF, preset=$FFMPEG_PRESET"
    echo "Carpeta origen: $RELATIVE_PATH"
    
    # Activar trap para limpiar en caso de error o interrupción
    trap cleanup_on_error ERR EXIT
    
    # Mover archivo a procesando/ (siempre en la raíz, sin subcarpeta)
    mv "${INPUT_DIR}/${VIDEO_FILE}" "${PROCESS_DIR}/${JUST_FILENAME}"
    
    # A partir de aquí, el archivo está en procesando/nombre.ext
    # Docker monta procesando:/videos, así que la ruta Docker es /videos/nombre.ext
    
    # Analizar codecs del video
    echo "Analizando codecs del video..."
    VIDEO_CODEC=$(docker exec ${DOCKER_CONTAINER} ${FFPROBE_BIN} -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    AUDIO_CODEC=$(docker exec ${DOCKER_CONTAINER} ${FFPROBE_BIN} -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    
    echo "Video codec: ${VIDEO_CODEC:-desconocido}"
    echo "Audio codec: ${AUDIO_CODEC:-desconocido}"
    
    # Verificar si necesita recodificación
    NEEDS_RECODE=0
    if [[ "$VIDEO_CODEC" != "${VIDEO_CODEC_TARGET}" ]]; then
        echo "Video no es ${VIDEO_CODEC_TARGET}, necesita recodificación"
        NEEDS_RECODE=1
    fi
    
    if [[ "$AUDIO_CODEC" != "${AUDIO_CODEC_TARGET}" ]]; then
        echo "Audio no es ${AUDIO_CODEC_TARGET}, necesita recodificación"
        NEEDS_RECODE=1
    fi
    
    if [[ $NEEDS_RECODE -eq 1 ]]; then
        echo "Recodificando video a ${VIDEO_CODEC_TARGET} + ${AUDIO_CODEC_TARGET}..."
        
        # Intentar con aceleración hardware V4L2 (RK3588 kernel 6.x)
        HWACCEL_OK=0
        if [[ -e /dev/video3 ]]; then
            echo "Intentando recodificación con V4L2 (aceleración hardware Rockchip)..."
            if docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} \
                -init_hw_device v4l2m2m_enc=v4l2m2m_enc0:/dev/video3 \
                -i "/videos/${JUST_FILENAME}" \
                -c:v h264_v4l2m2m -b:v 5M \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                HWACCEL_OK=1
                echo "Recodificación con V4L2 exitosa"
            else
                echo "V4L2 falló, usando libx264 (software)..."
            fi
        fi
        
        if [[ -e /dev/mpp_service && $HWACCEL_OK -eq 0 ]]; then
            echo "Intentando recodificación con RKMPP legacy..."
            if docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} \
                -hwaccel rkmpp -hwaccel_output_format drm_prime \
                -i "/videos/${JUST_FILENAME}" \
                -c:v h264_rkmpp -qp_init ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                HWACCEL_OK=1
                echo "Recodificación con RKMPP exitosa"
            else
                echo "RKMPP falló, usando libx264 (software)..."
            fi
        fi
        
        if [[ $HWACCEL_OK -eq 0 ]]; then
            echo "Recodificando con libx264 (software)..."
            docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} -i "/videos/${JUST_FILENAME}" \
                -c:v libx264 -preset ${FFMPEG_PRESET} -crf ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4"
            echo "Recodificación con libx264 completada"
        fi
        
        # Reemplazar archivo original con el recodificado
        mv "${PROCESS_DIR}/${BASE_NAME}_recode.mp4" "${PROCESS_DIR}/${JUST_FILENAME}"
    else
        echo "Video ya tiene buenos codecs, sin recodificar"
    fi
    
    # Mover video a final
    echo "Moviendo video a final..."
    mkdir -p "${OUTPUT_DIR}/${RELATIVE_PATH}"
    mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${RELATIVE_PATH}/${JUST_FILENAME}"
    
    # Limpiar archivos temporales
    rm -f "${PROCESS_DIR}/${JUST_FILENAME}"
    
    # Desactivar trap - proceso exitoso
    trap - ERR EXIT
    
    echo "=== Proceso completado ==="
    
} >> "${LOG_FILE}" 2>&1
PROCESS_EOF

    chmod +x "${SCRIPT_DIR}/process_video.sh"
    
    # Crear archivo de configuración
    cat > "${SCRIPT_DIR}/config.sh" << 'EOF'
#!/bin/bash
# Configuración del sistema de streaming

# Número máximo de procesos paralelos para procesamiento de videos
# 1 = secuencial (recomendado para Orange Pi 5 Plus)
# 2-3 = paralelo (si tienes más RAM/CPU)
MAX_PARALLEL_PROCES=1

# Codec de video para recodificación: h264, h265
VIDEO_CODEC_TARGET="h264"

# Codec de audio para recodificación: aac, opus
AUDIO_CODEC_TARGET="aac"

# Calidad de video para recodificación (CRF): menor = mejor calidad
# H.264: 18-28 (23 recomendado)
# H.265: 20-32 (26 recomendado)
VIDEO_CRF=23

# Preset de FFmpeg: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
FFMPEG_PRESET="medium"
EOF

    chmod +x "${SCRIPT_DIR}/config.sh"
    
    # Script de monitoreo
    cat > "${SCRIPT_DIR}/monitor.sh" << 'EOF'
#!/bin/bash

# Cargar configuración
source /opt/streaming/scripts/config.sh

INPUT_DIR="/opt/streaming/entrada"
PROCESS_DIR="/opt/streaming/procesando"
LOG_FILE="/opt/streaming/logs/monitor.log"
LOCK_DIR="/tmp/streaming_processing"

# Crear directorio de locks si no existe
mkdir -p "$LOCK_DIR"

# Función para limpiar locks huérfanos
cleanup_stale_locks() {
    local lock_file
    for lock_file in "$LOCK_DIR"/*.lock; do
        [[ -e "$lock_file" ]] || continue
        PID=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$PID" ]] && ! kill -0 "$PID" 2>/dev/null; then
            rm -f "$lock_file"
        fi
    done
}

# Función para recuperar archivos huérfanos de procesando/
# Si el servicio se interrumpió, pueden quedar archivos a medio procesar
recover_orphaned_files() {
    local file
    local filename
    local recovered=0
    
    for file in "$PROCESS_DIR"/*; do
        [[ -e "$file" ]] || continue
        [[ -f "$file" ]] || continue
        filename=$(basename "$file")
        [[ "$filename" == .* ]] && continue
        [[ "$filename" == .keep ]] && continue
        
        # Eliminar archivos parciales de recodificación
        if [[ "$filename" == *_recode.mp4 ]]; then
            echo "$(date): Eliminando archivo parcial de recodificación: $filename"
            rm -f "$file"
            continue
        fi
        
        # Devolver archivos originales a entrada/
        echo "$(date): Recuperando archivo huérfano: $filename -> entrada/"
        mv "$file" "${INPUT_DIR}/${filename}"
        recovered=$((recovered + 1))
    done
    
    if [[ $recovered -gt 0 ]]; then
        echo "$(date): $recovered archivo(s) recuperado(s) de procesando/ a entrada/"
    fi
}

# Contar locks activos
count_active_locks() {
    local count=0
    local lock_file
    for lock_file in "$LOCK_DIR"/*.lock; do
        [[ -e "$lock_file" ]] && count=$((count + 1))
    done
    echo "$count"
}

# Función para procesar un archivo respetando el límite de paralelismo
process_file() {
    local REL_PATH="$1"
    local FULL_PATH="${INPUT_DIR}/${REL_PATH}"
    
    # Verificar que el archivo existe y no está oculto
    [[ -f "$FULL_PATH" ]] || return
    [[ "$(basename "$FULL_PATH")" == .* ]] && return
    
    # Esperar si se alcanzó el máximo de procesos paralelos
    while true; do
        cleanup_stale_locks
        ACTIVE_PROCESSES=$(count_active_locks)
        [[ $ACTIVE_PROCESSES -lt $MAX_PARALLEL_PROCES ]] && break
        sleep 2
    done
    
    echo "$(date): Procesando: ${REL_PATH} (activos: $((ACTIVE_PROCESSES + 1))/$MAX_PARALLEL_PROCES)..."
    
    # Procesar archivo en segundo plano con lock gestionado
    (
        LOCK_FILE="$LOCK_DIR/$(basename "$FULL_PATH")_$$.lock"
        echo $$ > "$LOCK_FILE"
        /opt/streaming/scripts/process_video.sh "${REL_PATH}"
        rm -f "$LOCK_FILE"
        echo "$(date): Procesamiento completado para ${REL_PATH}" >> "${LOG_FILE}"
    ) &
}

{
    echo "=== Monitor iniciado $(date) ==="
    echo "Procesamiento paralelo máximo: $MAX_PARALLEL_PROCES archivo(s)"
    echo "Monitoreando: ${INPUT_DIR}"
    
    cleanup_stale_locks
    
    # Recuperar archivos huérfanos de procesando/ (de ejecuciones interrumpidas)
    echo "$(date): Verificando archivos huérfanos en procesando/..."
    recover_orphaned_files
    
    # Escaneo inicial: procesar archivos que ya existen en entrada/
    echo "$(date): Escaneando archivos existentes..."
    EXISTING_COUNT=0
    find "${INPUT_DIR}" -type f ! -name '.*' ! -name '.keep' | sort | while read FULL_PATH; do
        REL_PATH="${FULL_PATH#${INPUT_DIR}/}"
        echo "$(date): Archivo existente encontrado: ${REL_PATH}"
        process_file "${REL_PATH}"
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
    done
    echo "$(date): Escaneo inicial completado. Archivos encontrados: ${EXISTING_COUNT:-0}"
    
    # Monitorear recursivamente para archivos nuevos
    # close_write: se dispara cuando el archivo termina de copiarse
    # moved_to: se dispara cuando un archivo se mueve al directorio
    echo "$(date): Iniciando monitoreo continuo..."
    inotifywait -m -r -e close_write -e moved_to --format '%w%f' "${INPUT_DIR}" | while read FILE
    do
        # Ignorar archivos temporales y directorios
        if [[ ! -f "$FILE" ]]; then
            continue
        fi
        
        # Ignorar archivos ocultos
        if [[ "$(basename "$FILE")" == .* ]]; then
            continue
        fi
        
        # Obtener ruta relativa desde INPUT_DIR
        REL_PATH="${FILE#${INPUT_DIR}/}"
        
        echo "$(date): Nuevo archivo detectado: ${REL_PATH}"
        process_file "${REL_PATH}"
        
    done
    
} >> "${LOG_FILE}" 2>&1
EOF

    chmod +x "${SCRIPT_DIR}/monitor.sh"
    
    log_success "Scripts de procesamiento creados"
}

create_systemd_services() {
    log_info "Creando servicios systemd..."
    
    # Servicio de monitoreo
    cat > /etc/systemd/system/streaming-monitor.service << EOF
[Unit]
Description=Streaming Monitor Service
After=network.target docker.service

[Service]
Type=simple
User=root
ExecStart=/opt/streaming/scripts/monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable streaming-monitor.service
    
    log_success "Servicios systemd creados y habilitados"
}

configure_firewall() {
    log_info "Configurando firewall (ufw)..."
    
    ufw allow 8096/tcp comment 'Jellyfin Web UI'
    ufw allow 1900/udp comment 'DLNA/UPnP'
    ufw allow 7359/udp comment 'DLNA Client Discovery'
    
    log_success "Firewall configurado"
}

start_services() {
    log_info "Iniciando servicios..."
    
    cd "${BASE_DIR}"
    docker compose up -d
    
    sleep 5
    
    # Verificar servicios
    if docker ps | grep -q jellyfin; then
        log_success "Jellyfin iniciado correctamente (nyanmisaka con aceleración V4L2)"
    else
        log_error "Error al iniciar Jellyfin"
        return 1
    fi
    
    # Reiniciar (no solo start) para que tome los scripts actualizados
    systemctl restart streaming-monitor.service
    
    log_success "Todos los servicios iniciados"
}

print_summary() {
    echo ""
    echo "================================================"
    echo "  INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo "================================================"
    echo ""
    echo "Contenedor Docker:"
    echo "  - Jellyfin: http://$(hostname -I | awk '{print $1}'):8096"
    echo "    (imagen nyanmisaka/jellyfin:latest-rockchip con aceleración V4L2)"
    echo "  - Monitor: Automatizacion de procesamiento"
    echo ""
    echo "Aceleracion hardware:"
    echo "  - V4L2: h264_v4l2m2m encoder/decoder (RK3588 kernel 6.x)"
    echo "  - Fallback: libx264 (software)"
    echo "  - Requiere: dispositivos /dev/video* y /dev/media*"
    echo ""
    echo "Directorios:"
    echo "  - Entrada: ${VIDEO_INPUT}"
    echo "  - Procesando: ${VIDEO_PROCESS}"
    echo "  - Final: ${VIDEO_OUTPUT}"
    echo "  - Scripts: ${SCRIPT_DIR}"
    echo "  - Logs: ${LOG_DIR}"
    echo ""
    echo "Próximos pasos:"
    echo "  1. Acceder a Jellyfin para configuración inicial"
    echo "  2. Crear biblioteca apuntando a /media"
    echo "  3. Configurar aceleracion V4L2 en Jellyfin > Panel > Reproduccion"
    echo "  4. Copiar videos a ${VIDEO_INPUT}"
    echo "  5. Los videos se procesaran automaticamente"
    echo ""
    echo "Comandos útiles:"
    echo "  - Ver logs: tail -f ${LOG_DIR}/*.log"
    echo "  - Ver estado: cd ${BASE_DIR} && docker compose ps"
    echo "  - Reiniciar: cd ${BASE_DIR} && docker compose restart"
    echo "  - Detener: cd ${BASE_DIR} && docker compose down"
    echo "  - Verificar decodificadores: docker exec jellyfin ffmpeg -decoders 2>/dev/null | grep v4l2"
    echo ""
    echo "================================================"
}

################################################################################
# FUNCIÓN PRINCIPAL
################################################################################

main() {
    echo "================================================"
    echo "  INSTALACIÓN AUTOMATIZADA DEL STACK DE STREAMING"
    echo "  Orange Pi 5 Plus - Armbian"
    echo "================================================"
    echo ""
    
    # Verificar root
    check_root
    
    # Verificar hardware
    check_hardware
    
    # Verificar/installar Docker
    if ! check_docker; then
        install_docker
    fi
    
    # Instalar dependencias
    install_dependencies
    
    # Crear grupo render
    create_render_group
    
    # Crear estructura de directorios
    create_directory_structure
    
    # Descargar imágenes Docker
    pull_docker_images
    
    # Crear docker-compose
    create_docker_compose
    
    # Crear scripts
    create_processing_scripts
    
    # Crear servicios systemd
    create_systemd_services
    
    # Configurar firewall
    configure_firewall
    
    # Iniciar servicios
    start_services
    
    # Imprimir resumen
    print_summary
    
    log_success "Instalación completada exitosamente!"
}

# Ejecutar función principal
main "$@"