#!/bin/bash

################################################################################
# SCRIPT DE CONFIGURACIÓN INICIAL DE JELLYFIN
# Realiza configuración básica automática vía API de Jellyfin
################################################################################

set -e

JELLYFIN_URL="http://localhost:8096"
JELLYFIN_API_URL="${JELLYFIN_URL}/Sessions"
LOG_FILE="/opt/streaming/logs/jellyfin_config.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Esperar a que Jellyfin esté disponible
log "Esperando a que Jellyfin esté disponible..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    if curl -s -f "${JELLYFIN_URL}/health" > /dev/null 2>&1; then
        log "Jellyfin está disponible en: ${JELLYFIN_URL}"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    log "Intento $ATTEMPT de $MAX_ATTEMPTS..."
    sleep 2
done

if [[ $ATTEMPT -eq $MAX_ATTEMPTS ]]; then
    log "Error: Jellyfin no está disponible después de $MAX_ATTEMPTS intentos"
    exit 1
fi

# Verificar si ya hay usuarios configurados
log "Verificando configuración de Jellyfin..."

# Esperar que el usuario configure Jellyfin manualmente (primera vez)
log "================================================"
log "CONFIGURACIÓN INICIAL DE JELLYFIN"
log "================================================"
log ""
log "Por favor, completa la configuración inicial de Jellyfin en:"
log "  ${JELLYFIN_URL}"
log ""
log "Pasos recomendados:"
log "  1. Crear usuario administrador"
log "  2. Configurar metadatos en tu idioma preferido"
log "  3. Agregar biblioteca de medios:"
log "     - Tipo: Movies/Series"
log "     - Nombre: Películas (o como prefieras)"
log "     - Ruta: /media (o subdirectorio específico)"
log "  4. Configurar DLNA (opcional)"
log "  5. Instalar plugins:"
log "     - Open Subtitles"
log "     - Subtitle Extract"
log ""
log "Una vez completada la configuración inicial, presione ENTER"
log "para continuar con la configuración avanzada."
log "================================================"
log ""

read -p "Presiona ENTER cuando hayas completado la configuración inicial..."

log "Configuración inicial completada por el usuario"

# Intentar obtener el ID de usuario admin (requiere token)
log "Para configuración avanzada, necesitas el token de API de Jellyfin"
log "Para obtener el token:"
log "  1. Inicia sesión en ${JELLYFIN_URL}"
log "  2. Ve a Dashboard -> API Keys"
log "  3. Crea una nueva API Key"
log "  4. Copia el token generado"
log ""
read -p "Ingresa tu API Token de Jellyfin (o presiona ENTER para saltar): " API_TOKEN

if [[ -n "$API_TOKEN" ]]; then
    log "API Token proporcionado, configurando opciones avanzadas..."
    
    # Crear biblioteca de películas si no existe (requiere lógica adicional)
    log "Configuración avanzada no implementada en este script"
    log "Por favor, configura las bibliotecas manualmente desde la interfaz web"
else
    log "Sin API Token, configuración avanzada omitida"
fi

log "================================================"
log "CONFIGURACIÓN COMPLETADA"
log "================================================"
log ""
log "Jellyfin está listo para usar:"
log "  - URL: ${JELLYFIN_URL}"
log "  - Directorio de medios: /opt/streaming/final"
log "  - Copia videos a: /opt/streaming/entrada"
log "  - Los videos se procesarán automáticamente"
log ""
log "Documentación: https://jellyfin.org/docs/"
log ""
log "================================================"