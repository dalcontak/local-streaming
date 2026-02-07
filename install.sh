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
WHISPER_MODELS="${DATA_DIR}/whisper/models"

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
    mkdir -p "${WHISPER_MODELS}"
    
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

install_whisper_model() {
    # Crear directorio de modelos si no existe
    mkdir -p "${WHISPER_MODELS}"
    
    # Verificar si la imagen whisper-arm64 ya existe
    if docker image inspect whisper-arm64 > /dev/null 2>&1; then
        log_success "Imagen Docker whisper-arm64 ya existe, omitiendo construcción"
    else
        log_info "Construyendo imagen Docker de Whisper..."
        cat > /tmp/Dockerfile.whisper << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y ffmpeg
RUN pip install whisper openai-whisper

CMD ["sleep", "infinity"]
EOF
        docker build -t whisper-arm64 /tmp -f /tmp/Dockerfile.whisper
        log_success "Imagen Docker whisper-arm64 construida"
    fi
    
    # Verificar si el modelo medium ya fue descargado
    if ls "${WHISPER_MODELS}"/medium.pt > /dev/null 2>&1; then
        log_success "Modelo medium de Whisper ya existe, omitiendo descarga"
    else
        log_info "Descargando modelo medium de Whisper..."
        docker run --rm \
            -v "${WHISPER_MODELS}:/root/.cache/whisper" \
            whisper-arm64 \
            python -c "import whisper; whisper.load_model('medium')"
        log_success "Modelo medium de Whisper descargado"
    fi
    
    # Verificar si la imagen ffmpeg-arm64 ya existe
    if docker image inspect ffmpeg-arm64 > /dev/null 2>&1; then
        log_success "Imagen Docker ffmpeg-arm64 ya existe, omitiendo construcción"
    else
        log_info "Construyendo imagen Docker de FFmpeg..."
        cat > /tmp/Dockerfile.ffmpeg << 'EOF'
FROM alpine:latest

RUN apk add --no-cache ffmpeg

CMD ["sleep", "infinity"]
EOF
        docker build -t ffmpeg-arm64 /tmp -f /tmp/Dockerfile.ffmpeg
        log_success "Imagen Docker ffmpeg-arm64 construida"
    fi
}

create_docker_compose() {
    log_info "Creando archivo docker-compose.yml..."
    
    RENDER_GROUP_ID=${RENDER_GROUP_ID:-122}
    
    cat > "${BASE_DIR}/docker-compose.yml" << EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    user: 1000:1000
    group_add:
      - '${RENDER_GROUP_ID}'
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
      - /dev/dri/card0:/dev/dri/card0
    volumes:
      - ${JELLYFIN_CONFIG}:/config
      - ${JELLYFIN_CACHE}:/cache
      - ${VIDEO_OUTPUT}:/media
    network_mode: host
    restart: unless-stopped
    environment:
      - TZ=${TZ:-UTC}

  whisper:
    image: whisper-arm64
    container_name: whisper
    volumes:
      - ${WHISPER_MODELS}:/root/.cache/whisper
      - ${VIDEO_PROCESS}:/videos
    restart: unless-stopped
    command: /bin/sh -c "sleep infinity"

  ffmpeg:
    image: ffmpeg-arm64
    container_name: ffmpeg
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
      - /dev/dri/card0:/dev/dri/card0
    volumes:
      - ${VIDEO_PROCESS}:/videos
      - ${VIDEO_OUTPUT}:/output
    restart: unless-stopped
    command: sleep infinity
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

# Detectar si el archivo viene de una subcarpeta (Peliculas o Series)
SUBFOLDER=""
if [[ "$VIDEO_FILE" == Peliculas/* ]]; then
    SUBFOLDER="Peliculas"
elif [[ "$VIDEO_FILE" == Series/* ]]; then
    SUBFOLDER="Series"
fi

{
    echo "=== $(date) ==="
    echo "Procesando: $VIDEO_FILE"
    echo "Configuración: modelo=$WHISPER_MODEL, idioma=$SUBTITLE_LANGUAGE, codec=$VIDEO_CODEC_TARGET/$AUDIO_CODEC_TARGET, crf=$VIDEO_CRF, preset=$FFMPEG_PRESET"
    if [[ -n "$SUBFOLDER" ]]; then
        echo "Subcarpeta detectada: $SUBFOLDER"
    fi
    
    # Mover archivo a procesando/ (siempre en la raíz, sin subcarpeta)
    mv "${INPUT_DIR}/${VIDEO_FILE}" "${PROCESS_DIR}/${JUST_FILENAME}"
    
    # A partir de aquí, el archivo está en procesando/nombre.ext
    # Docker monta procesando:/videos, así que la ruta Docker es /videos/nombre.ext
    
    # Verificar si el video ya tiene subtítulos incrustados
    echo "Verificando subtítulos existentes..."
    HAS_SUBTITLES=$(docker exec ffmpeg ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "/videos/${JUST_FILENAME}" 2>/dev/null | grep -v '^$')
    
    if [[ -n "$HAS_SUBTITLES" ]]; then
        echo "Video ya tiene subtítulos incrustados. Omitiendo procesamiento."
        if [[ -n "$SUBFOLDER" ]]; then
            mkdir -p "${OUTPUT_DIR}/${SUBFOLDER}"
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${SUBFOLDER}/${JUST_FILENAME}"
        else
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${JUST_FILENAME}"
        fi
        echo "=== Video movido a final (sin procesar) ==="
        exit 0
    fi
    
    # Verificar si existe archivo de subtítulos externo
    if [[ -f "${PROCESS_DIR}/${BASE_NAME}.srt" ]] || [[ -f "${PROCESS_DIR}/${BASE_NAME}.vtt" ]] || [[ -f "${PROCESS_DIR}/${BASE_NAME}.ass" ]]; then
        echo "Video tiene archivo de subtítulos externo. Omitiendo generación de subtítulos."
        if [[ -n "$SUBFOLDER" ]]; then
            mkdir -p "${OUTPUT_DIR}/${SUBFOLDER}"
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${SUBFOLDER}/${JUST_FILENAME}"
            mv "${PROCESS_DIR}/${BASE_NAME}".{srt,vtt,ass} "${OUTPUT_DIR}/${SUBFOLDER}/" 2>/dev/null || true
        else
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${JUST_FILENAME}"
            mv "${PROCESS_DIR}/${BASE_NAME}".{srt,vtt,ass} "${OUTPUT_DIR}/" 2>/dev/null || true
        fi
        echo "=== Video movido a final (sin procesar) ==="
        exit 0
    fi
    
    # Analizar codecs del video
    echo "Analizando codecs del video..."
    VIDEO_CODEC=$(docker exec ffmpeg ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    AUDIO_CODEC=$(docker exec ffmpeg ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    
    echo "Video codec: ${VIDEO_CODEC:-desconocido}"
    echo "Audio codec: ${AUDIO_CODEC:-desconocido}"
    
    # Generar subtítulos con Whisper
    echo "Generando subtítulos con Whisper (modelo: $WHISPER_MODEL, idioma: $SUBTITLE_LANGUAGE)..."
    docker exec whisper python3 -c "
import whisper

def format_timestamp(seconds):
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f'{h:02d}:{m:02d}:{s:02d},{ms:03d}'

model = whisper.load_model('${WHISPER_MODEL}')
result = model.transcribe('/videos/${JUST_FILENAME}', language='${SUBTITLE_LANGUAGE}')
with open('/videos/${BASE_NAME}.srt', 'w', encoding='utf-8') as f:
    for i, segment in enumerate(result['segments']):
        f.write(f'{i+1}\n')
        f.write(f'{format_timestamp(segment[\"start\"])} --> {format_timestamp(segment[\"end\"])}\n')
        f.write(f'{segment[\"text\"].strip()}\n\n')
"
    
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
        
        # Intentar con aceleración hardware (VAAPI), si falla usar libx264
        VAAPI_OK=0
        if [[ -e /dev/dri/renderD128 ]]; then
            echo "Intentando recodificación con VAAPI (aceleración hardware)..."
            if docker exec ffmpeg ffmpeg -vaapi_device /dev/dri/renderD128 \
                -i "/videos/${JUST_FILENAME}" \
                -vf 'format=nv12,hwupload' \
                -c:v h264_vaapi -qp ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                VAAPI_OK=1
                echo "Recodificación con VAAPI exitosa"
            else
                echo "VAAPI falló, usando libx264 (software)..."
            fi
        fi
        
        if [[ $VAAPI_OK -eq 0 ]]; then
            echo "Recodificando con libx264 (software)..."
            docker exec ffmpeg ffmpeg -i "/videos/${JUST_FILENAME}" \
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
    
    # Mover video y subtítulos a final
    echo "Moviendo video y subtítulos a final..."
    if [[ -n "$SUBFOLDER" ]]; then
        mkdir -p "${OUTPUT_DIR}/${SUBFOLDER}"
        mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${SUBFOLDER}/${JUST_FILENAME}"
        mv "${PROCESS_DIR}/${BASE_NAME}.srt" "${OUTPUT_DIR}/${SUBFOLDER}/${BASE_NAME}.srt" 2>/dev/null || true
    else
        mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${JUST_FILENAME}"
        mv "${PROCESS_DIR}/${BASE_NAME}.srt" "${OUTPUT_DIR}/${BASE_NAME}.srt" 2>/dev/null || true
    fi
    
    # Limpiar archivos temporales
    rm -f "${PROCESS_DIR}/${JUST_FILENAME}"
    rm -f "${PROCESS_DIR}/${BASE_NAME}.srt"
    
    echo "=== Proceso completado (subtítulos generados) ==="
    
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

# Idioma predeterminado para subtítulos (es, en, fr, de, etc.)
SUBTITLE_LANGUAGE="es"

# Modelo de Whisper: tiny, base, small, medium, large
WHISPER_MODEL="medium"

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
        log_success "Jellyfin iniciado correctamente"
    else
        log_error "Error al iniciar Jellyfin"
        return 1
    fi
    
    if docker ps | grep -q whisper; then
        log_success "Whisper iniciado correctamente"
    else
        log_error "Error al iniciar Whisper"
        return 1
    fi
    
    if docker ps | grep -q ffmpeg; then
        log_success "FFmpeg iniciado correctamente"
    else
        log_error "Error al iniciar FFmpeg"
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
    echo "Servicios instalados:"
    echo "  - Jellyfin: http://$(hostname -I | awk '{print $1}'):8096"
    echo "  - Whisper: Generación de subtítulos con IA"
    echo "  - FFmpeg: Recodificación de videos"
    echo "  - Monitor: Automatización de procesamiento"
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
    echo "  3. Copiar videos a ${VIDEO_INPUT}"
    echo "  4. Los videos se procesarán automáticamente"
    echo ""
    echo "Comandos útiles:"
    echo "  - Ver logs: tail -f ${LOG_DIR}/*.log"
    echo "  - Ver estado: cd ${BASE_DIR} && docker compose ps"
    echo "  - Reiniciar: cd ${BASE_DIR} && docker compose restart"
    echo "  - Detener: cd ${BASE_DIR} && docker compose down"
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
    
    # Instalar modelo Whisper
    install_whisper_model
    
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