#!/bin/bash

################################################################################
# SCRIPT DE PROCESAMIENTO DE VIDEOS
# Genera subtítulos con Whisper y recodifica video con FFmpeg
################################################################################

set -e

# Verificar argumentos
if [[ $# -eq 0 ]]; then
    echo "Uso: $0 <archivo_video> [idioma]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 video.mp4"
    echo "  $0 video.mp4 es"
    echo ""
    exit 1
fi

VIDEO_FILE="$1"
LANGUAGE="${2:-es}"  # Español por defecto

# Variables
BASE_NAME=$(basename "$VIDEO_FILE" | sed 's/\.[^.]*$//')
EXT="${VIDEO_FILE##*.}"
LOG_DIR="/opt/streaming/logs"
LOG_FILE="${LOG_DIR}/process_${BASE_NAME}.log"
INPUT_DIR="/opt/streaming/entrada"
PROCESS_DIR="/opt/streaming/procesando"
OUTPUT_DIR="/opt/streaming/final"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Verificar que el archivo existe
if [[ ! -f "${INPUT_DIR}/${VIDEO_FILE}" ]]; then
    echo "Error: Archivo no encontrado: ${INPUT_DIR}/${VIDEO_FILE}"
    exit 1
fi

# Crear directorio de logs si no existe
mkdir -p "${LOG_DIR}"

log "=== Iniciando procesamiento de: ${VIDEO_FILE} ==="
log "Idioma de subtítulos: ${LANGUAGE}"

# Paso 1: Mover a procesando
log "Paso 1: Moviendo archivo a procesando..."
mv "${INPUT_DIR}/${VIDEO_FILE}" "${PROCESS_DIR}/${VIDEO_FILE}"
log "Archivo movido a: ${PROCESS_DIR}/${VIDEO_FILE}"

# Paso 2: Generar subtítulos con Whisper
log "Paso 2: Generando subtítulos con Whisper..."
if docker exec whisper whisper-cli \
    -m /models/ggml-medium.bin \
    -f "/videos/${VIDEO_FILE}" \
    -l "${LANGUAGE}" \
    -osrt; then
    log "Subtítulos generados exitosamente"
else
    log "Error al generar subtítulos"
    # Continuar aunque falle Whisper
fi

# Paso 3: Recodificar e incrustar subtítulos
log "Paso 3: Recodificando video e incrustando subtítulos..."

if [[ -f "${PROCESS_DIR}/${BASE_NAME}.srt" ]]; then
    log "Incrustando subtítulos..."
    docker exec ffmpeg ffmpeg -i "/videos/${VIDEO_FILE}" \
        -vf "subtitles=/videos/${BASE_NAME}.srt:force_style='FontName=Arial,FontSize=24,PrimaryColour=&H00FFFFFF'" \
        -c:v h264_vaapi -vaapi_device /dev/dri/renderD128 \
        -preset medium -crf 23 \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        -y \
        "/output/${VIDEO_FILE}"
else
    log "No se encontraron subtítulos, recodificando sin subtítulos..."
    docker exec ffmpeg ffmpeg -i "/videos/${VIDEO_FILE}" \
        -c:v h264_vaapi -vaapi_device /dev/dri/renderD128 \
        -preset medium -crf 23 \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        -y \
        "/output/${VIDEO_FILE}"
fi

if [[ -f "${OUTPUT_DIR}/${VIDEO_FILE}" ]]; then
    log "Video recodificado exitosamente"
else
    log "Error: No se generó el video de salida"
    # Mover original de vuelta a entrada en caso de error
    mv "${PROCESS_DIR}/${VIDEO_FILE}" "${INPUT_DIR}/${VIDEO_FILE}"
    exit 1
fi

# Paso 4: Limpiar archivos temporales
log "Paso 4: Limpiando archivos temporales..."
rm -f "${PROCESS_DIR}/${VIDEO_FILE}"
rm -f "${PROCESS_DIR}/${BASE_NAME}.srt"
log "Archivos temporales eliminados"

log "=== Procesamiento completado exitosamente ==="
echo ""
echo "Video procesado: ${OUTPUT_DIR}/${VIDEO_FILE}"
echo "Logs: ${LOG_FILE}"
echo ""