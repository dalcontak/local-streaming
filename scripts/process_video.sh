#!/bin/bash

# NOTA: Este archivo es de referencia. El install.sh genera la versión
# actualizada en /opt/streaming/scripts/process_video.sh

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
SUBFOLDER=""
if [[ "$VIDEO_FILE" == Peliculas/* ]]; then
    SUBFOLDER="Peliculas"
elif [[ "$VIDEO_FILE" == Series/* ]]; then
    SUBFOLDER="Series"
fi

# Función de limpieza en caso de error
cleanup_on_error() {
    echo "ERROR: Proceso interrumpido o fallido para ${JUST_FILENAME}"
    # Eliminar archivo parcial de recodificación si existe
    rm -f "${PROCESS_DIR}/${BASE_NAME}_recode.mp4"
    # Devolver archivo original a entrada/ si sigue en procesando/
    if [[ -f "${PROCESS_DIR}/${JUST_FILENAME}" ]]; then
        echo "Devolviendo ${JUST_FILENAME} a entrada/..."
        if [[ -n "$SUBFOLDER" ]]; then
            mkdir -p "${INPUT_DIR}/${SUBFOLDER}"
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${INPUT_DIR}/${SUBFOLDER}/${JUST_FILENAME}"
        else
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${INPUT_DIR}/${JUST_FILENAME}"
        fi
        echo "Archivo devuelto a entrada/ para reprocesar"
    fi
}

{
    echo "=== $(date) ==="
    echo "Procesando: $VIDEO_FILE"
    echo "Configuración: codec=$VIDEO_CODEC_TARGET/$AUDIO_CODEC_TARGET, crf=$VIDEO_CRF, preset=$FFMPEG_PRESET"
    if [[ -n "$SUBFOLDER" ]]; then
        echo "Subcarpeta detectada: $SUBFOLDER"
    fi
    
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
        
        # Intentar con aceleración hardware RKMPP (Rockchip), si falla usar libx264
        RKMPP_OK=0
        if [[ -e /dev/mpp_service ]]; then
            echo "Intentando recodificación con RKMPP (aceleración hardware Rockchip)..."
            if docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} \
                -hwaccel rkmpp -hwaccel_output_format drm_prime -afbc rga \
                -i "/videos/${JUST_FILENAME}" \
                -vf 'scale_rkrga=format=nv12' \
                -c:v h264_rkmpp -qp_init ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                RKMPP_OK=1
                echo "Recodificación con RKMPP exitosa"
            else
                echo "RKMPP falló, usando libx264 (software)..."
            fi
        fi
        
        if [[ $RKMPP_OK -eq 0 ]]; then
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
    if [[ -n "$SUBFOLDER" ]]; then
        mkdir -p "${OUTPUT_DIR}/${SUBFOLDER}"
        mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${SUBFOLDER}/${JUST_FILENAME}"
    else
        mv "${PROCESS_DIR}/${JUST_FILENAME}" "${OUTPUT_DIR}/${JUST_FILENAME}"
    fi
    
    # Limpiar archivos temporales
    rm -f "${PROCESS_DIR}/${JUST_FILENAME}"
    
    # Desactivar trap - proceso exitoso
    trap - ERR EXIT
    
    echo "=== Proceso completado ==="
    
} >> "${LOG_FILE}" 2>&1
