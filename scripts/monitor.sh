#!/bin/bash

################################################################################
# SCRIPT DE MONITOREO DE DIRECTORIO
# Detecta archivos nuevos en /opt/streaming/entrada y los procesa automáticamente
################################################################################

INPUT_DIR="/opt/streaming/entrada"
LOG_FILE="/opt/streaming/logs/monitor.log"
PROCESS_SCRIPT="/opt/streaming/scripts/process_video.sh"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# Crear directorio de logs si no existe
mkdir -p "$(dirname "${LOG_FILE}")"

log "=== Script de monitoreo iniciado ==="
log "Directorio monitoreado: ${INPUT_DIR}"
log "Script de procesamiento: ${PROCESS_SCRIPT}"

# Verificar que el script de procesamiento existe
if [[ ! -f "${PROCESS_SCRIPT}" ]]; then
    log "Error: Script de procesamiento no encontrado: ${PROCESS_SCRIPT}"
    exit 1
fi

# Verificar que el directorio de entrada existe
if [[ ! -d "${INPUT_DIR}" ]]; then
    log "Error: Directorio de entrada no encontrado: ${INPUT_DIR}"
    exit 1
fi

# Verificar que inotifywait está instalado
if ! command -v inotifywait &> /dev/null; then
    log "Error: inotifywait no está instalado"
    exit 1
fi

log "Monitoreo iniciado. Esperando archivos nuevos..."
echo "Monitoreo iniciado en: ${INPUT_DIR}"
echo "Presione Ctrl+C para detener"
echo ""

# Loop de monitoreo
inotifywait -m -e create -e moved_to --format '%f' "${INPUT_DIR}" | while read FILE
do
    # Verificar que el archivo existe y es un archivo regular
    if [[ -f "${INPUT_DIR}/${FILE}" ]]; then
        
        # Ignorar archivos ocultos y temporales
        if [[ "$FILE" == .* ]] || [[ "$FILE" == *~ ]]; then
            log "Archivo ignorado (oculto/temporal): ${FILE}"
            continue
        fi
        
        # Verificar que sea un archivo de video
        EXT="${FILE##*.}"
        case "${EXT,,}" in
            mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|m2ts|ts)
                log "=== Nuevo archivo de video detectado: ${FILE} ==="
                
                # Esperar a que el archivo se haya completado de copiar
                sleep 2
                
                # Verificar que el archivo todavía existe (no se movió)
                if [[ -f "${INPUT_DIR}/${FILE}" ]]; then
                    
                    # Procesar el video
                    log "Iniciando procesamiento de: ${FILE}"
                    ${PROCESS_SCRIPT} "${FILE}" > /dev/null 2>&1
                    
                    if [[ $? -eq 0 ]]; then
                        log "Procesamiento completado: ${FILE}"
                    else
                        log "Error al procesar: ${FILE}"
                    fi
                else
                    log "Archivo desapareció antes de procesarse: ${FILE}"
                fi
                ;;
            *)
                log "Archivo no es video, ignorando: ${FILE} (extensión: ${EXT})"
                ;;
        esac
    fi
done

log "=== Script de monitoreo detenido ==="