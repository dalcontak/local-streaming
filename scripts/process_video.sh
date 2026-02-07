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
    VIDEO_CODEC=$(docker exec ffmpeg ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    AUDIO_CODEC=$(docker exec ffmpeg ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    
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
