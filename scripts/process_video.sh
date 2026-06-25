#!/bin/bash

source /opt/streaming/scripts/config.sh

VIDEO_FILE="$1"
if [[ -z "$VIDEO_FILE" ]]; then
    echo "Uso: $0 <archivo_video>"
    exit 1
fi

JUST_FILENAME=$(basename "$VIDEO_FILE")
BASE_NAME=$(echo "$JUST_FILENAME" | sed 's/\.[^.]*$//')
EXT="${JUST_FILENAME##*.}"
REL_DIR=$(dirname "$VIDEO_FILE")
[[ "$REL_DIR" == "." ]] && REL_DIR=""

LOG_FILE="/opt/streaming/logs/process_${BASE_NAME}.log"
INPUT_DIR="/opt/streaming/entrada"
PROCESS_DIR="/opt/streaming/procesando"
OUTPUT_DIR="/opt/streaming/final"

FFMPEG_BIN="/usr/lib/jellyfin-ffmpeg/ffmpeg"
FFPROBE_BIN="/usr/lib/jellyfin-ffmpeg/ffprobe"
DOCKER_CONTAINER="jellyfin"

OUTPUT_NAME="${BASE_NAME}.mp4"

cleanup_on_error() {
    echo "ERROR: Proceso interrumpido o fallido para ${JUST_FILENAME}"
    rm -f "${PROCESS_DIR}/${BASE_NAME}_recode.mp4"
    if [[ -f "${PROCESS_DIR}/${JUST_FILENAME}" ]]; then
        echo "Devolviendo ${JUST_FILENAME} a entrada/..."
        if [[ -n "$REL_DIR" ]]; then
            mkdir -p "${INPUT_DIR}/${REL_DIR}"
            mv "${PROCESS_DIR}/${JUST_FILENAME}" "${INPUT_DIR}/${REL_DIR}/${JUST_FILENAME}"
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
    if [[ -n "$REL_DIR" ]]; then
        echo "Directorio relativo: $REL_DIR"
    fi

    trap cleanup_on_error ERR EXIT

    mv "${INPUT_DIR}/${VIDEO_FILE}" "${PROCESS_DIR}/${JUST_FILENAME}"

    echo "Analizando codecs del video..."
    VIDEO_CODEC=$(docker exec ${DOCKER_CONTAINER} ${FFPROBE_BIN} -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)
    AUDIO_CODEC=$(docker exec ${DOCKER_CONTAINER} ${FFPROBE_BIN} -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/videos/${JUST_FILENAME}" 2>/dev/null | head -1)

    echo "Video codec: ${VIDEO_CODEC:-desconocido}"
    echo "Audio codec: ${AUDIO_CODEC:-desconocido}"

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

        HWACCEL_OK=0
        if [[ -e /dev/mpp_service ]]; then
            echo "Intentando recodificación con RKMPP (aceleración hardware Rockchip)..."
            echo "  - Intento 1: HW decode + HW encode (full HW)"
            if docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} \
                -hwaccel rkmpp -hwaccel_output_format drm_prime \
                -i "/videos/${JUST_FILENAME}" \
                -c:v h264_rkmpp -qp_init ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                HWACCEL_OK=1
                echo "RKMPP full HW exitosa"
            else
                echo "  - Intento 2: SW decode + HW encode (fallback para codecs no soportados por HW)"
                if docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} \
                    -i "/videos/${JUST_FILENAME}" \
                    -c:v h264_rkmpp -qp_init ${VIDEO_CRF} \
                    -c:a aac -b:a 128k \
                    -y \
                    "/videos/${BASE_NAME}_recode.mp4" 2>&1; then
                    HWACCEL_OK=1
                    echo "RKMPP encode HW exitosa"
                else
                    echo "RKMPP falló completamente, usando libx264 (software)..."
                fi
            fi
        fi

        if [[ -e /dev/video3 && $HWACCEL_OK -eq 0 ]]; then
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

        if [[ $HWACCEL_OK -eq 0 ]]; then
            echo "Recodificando con libx264 (software)..."
            docker exec ${DOCKER_CONTAINER} ${FFMPEG_BIN} -i "/videos/${JUST_FILENAME}" \
                -c:v libx264 -preset ${FFMPEG_PRESET} -crf ${VIDEO_CRF} \
                -c:a aac -b:a 128k \
                -y \
                "/videos/${BASE_NAME}_recode.mp4"
            echo "Recodificación con libx264 completada"
        fi

        mv "${PROCESS_DIR}/${BASE_NAME}_recode.mp4" "${PROCESS_DIR}/${OUTPUT_NAME}"
    else
        echo "Video ya tiene buenos codecs, sin recodificar"
        OUTPUT_NAME="${JUST_FILENAME}"
    fi

    echo "Moviendo video a final..."
    if [[ -n "$REL_DIR" ]]; then
        mkdir -p "${OUTPUT_DIR}/${REL_DIR}"
        mv "${PROCESS_DIR}/${OUTPUT_NAME}" "${OUTPUT_DIR}/${REL_DIR}/${OUTPUT_NAME}"
    else
        mv "${PROCESS_DIR}/${OUTPUT_NAME}" "${OUTPUT_DIR}/${OUTPUT_NAME}"
    fi

    trap - ERR EXIT

    echo "=== Proceso completado ==="

} >> "${LOG_FILE}" 2>&1
