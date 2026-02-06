# Stack de Streaming Local con Orange Pi 5 Plus

## Resumen del Proyecto

Implementación de servicio de streaming local en LAN utilizando **Jellyfin** como servidor de media, **Whisper** para generación automática de subtítulos mediante IA, y **FFmpeg** para recodificación y estandarización de videos, todo ejecutado en una Orange Pi 5 Plus con 8GB RAM y NVMe 2TB.

## Hardware Disponible

- **Orange Pi 5 Plus**
  - CPU: Rockchip RK3588 (8-core ARM Cortex-A76/A55)
  - RAM: 8GB
  - Almacenamiento: NVMe M.2 2TB
  - GPU: ARM Mali-G610
  - Sistema: Armbian Linux
  - Servicio NFS configurado exportando carpeta de videos

## Arquitectura del Sistema

```
[Dispositivos LAN] → [Jellyfin (8096)] → [Videos procesados]
                         ↑
[Sistema de Procesamiento]
[NFS/entrada] → [Whisper → FFmpeg] → [Final/Jellyfin]
```

## Componentes del Stack

### 1. **Jellyfin** - Servidor de Media
- **Función**: Gestión, streaming y transcoding de videos
- **Características**:
  - Open-source, completamente gratuito
  - Transcodificación al vuelo
  - DLNA integrado para TVs y dispositivos
  - Apps para todos los dispositivos móviles y desktop
  - Plugins para búsqueda de subtítulos
- **Soporte Docker**: Sí, con passthrough de dispositivos /dev/dri para aceleración

### 2. **Whisper** - Generación de Subtítulos con IA
- **Función**: Transcripción automática de audio a texto con reconocimiento multilingüe
- **Implementación recomendada**: **whisper.cpp** (high-performance C/C++)
- **Características**:
  - Modelo medium recomendado para calidad/performance balanceada
  - Soporte para múltiples idiomas
  - Salida en formato SRT
- **Soporte Docker**: Sí, con imágenes optimizadas para CPU y GPU (CUDA, Vulkan, OpenCL)
- **Aceleración hardware**:
  - Vulkan (funciona con Mali GPU en Orange Pi)
  - OpenCL
  - Optimizaciones específicas ARM (dotprod, fp16, sve, i8mm)

### 3. **FFmpeg** - Procesamiento de Video
- **Función**: Recodificación de videos y hardcoding de subtítulos
- **Características**:
  - Transcodificación H.264/H.265 optimizada
  - Incrustación de subtítulos durante encoding
  - Compatibilidad con aceleración hardware
- **Soporte Docker**: Sí, con passthrough de dispositivos /dev/dri
- **Aceleración hardware**: VAAPI para ARM, VDPAU, CUDA (si aplica)

### 4. **Automatización**
- **inotifywait**: Detección de archivos nuevos en NFS
- **systemd**: Servicios automáticos
- **scripts bash**: Orquestación del pipeline

## Análisis: Docker vs Instalación Nativa

### **Opción Recomendada: Implementación Híbrida con Docker**

**Jellyfin con Docker** ✅ **RECOMENDADO**
- **Ventajas**:
  - Gestión simplificada con Docker Compose
  - Actualizaciones fáciles
  - Aislamiento de dependencias
  - **Soporte completo de hardware** mediante passthrough de `/dev/dri/renderD128`
  - Mantiene transcodificación hardware-accelerada
- **Configuración**:
```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    group_add:
      - '122'  # Render group ID
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
      - /dev/dri/card0:/dev/dri/card0
    volumes:
      - /path/to/jellyfin-config:/config
      - /path/to/media:/media
```

**Whisper con Docker** ✅ **RECOMENDADO**
- **Ventajas**:
  - Imágenes optimizadas para diferentes backends
  - Imagen `ghcr.io/ggml-org/whisper.cpp:main` para CPU
  - Imagen `ghcr.io/ggml-org/whisper.cpp:main-cuda` para NVIDIA
  - **Soporte Vulkan para Mali GPU** (Orange Pi)
  - Compilación personalizada con backends específicos
- **Configuración**:
```bash
# Imagen CPU optimizada
docker pull ghcr.io/ggml-org/whisper.cpp:main

# Imagen con aceleración GPU (NVIDIA)
docker pull ghcr.io/ggml-org/whisper.cpp:main-cuda

# Compilación personalizada con Vulkan para Mali GPU
docker build -t whisper-vulkan .
```

**FFmpeg con Docker** ✅ **RECOMENDADO**
- **Ventajas**:
  - Imágenes oficiales mantenidas
  - Passthrough de dispositivos `/dev/dri` para VAAPI
  - Aislamiento de versiones y codecs
- **Configuración**:
```bash
docker run --device /dev/dri/renderD128:/dev/dri/renderD128 \
  -v $(pwd)/videos:/videos \
  linuxserver/ffmpeg:latest \
  -i input.mp4 -vf "subtitles=input.srt" -c:v h264 output.mp4
```

**Scripts de Automatización: Instalación Nativa** ⚠️ **CONSIDERAR**
- **Razón**: Los scripts de automatización (inotifywait, systemd) funcionan mejor fuera de Docker
- **Alternativa**: Ejecutar scripts nativos que llamen contenedores Docker

## Directorios de Trabajo

```
/opt/streaming/
├── entrada/          # Montaje NFS o symlink a carpeta NFS
├── procesando/       # Archivos en proceso
├── final/            # Videos procesados (input para Jellyfin)
├── scripts/          # Scripts de automatización
├── configs/          # Configuraciones
└── logs/             # Logs del sistema
```

## Pipeline de Procesamiento

1. **Upload**: Usuario copia video a `/opt/streaming/entrada/`
2. **Detección**: inotifywait detecta archivo nuevo
3. **Generación Subtítulos**: Whisper procesa audio → genera `.srt`
4. **Recodificación**: FFmpeg recodifica video + incrusta subtítulos
5. **Movimiento**: Archivo final movido a `/opt/streaming/final/`
6. **Indexación**: Jellyfin detecta nuevo archivo automáticamente

## Comandos del Pipeline

### Generación de Subtítulos con Whisper
```bash
# CPU nativo
whisper input_video.mp4 --model medium --language es --output_format srt

# Whisper.cpp (optimizado)
whisper-cli -m /models/ggml-medium.bin -f input_video.mp4 -osrt

# Docker con Whisper.cpp
docker run --rm \
  -v $(pwd)/videos:/videos \
  -v $(pwd)/models:/models \
  whisper.cpp:main \
  "whisper-cli -m /models/ggml-medium.bin -f /videos/input.mp4 -osrt"
```

### Recodificación e Incrustación de Subtítulos con FFmpeg
```bash
# Nativo
ffmpeg -i input_video.mp4 \
  -vf "subtitles=input_video.srt" \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  output_video.mp4

# Con aceleración VAAPI (ARM)
ffmpeg -i input_video.mp4 \
  -vf "subtitles=input_video.srt" \
  -c:v h264_vaapi -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  output_video.mp4

# Docker con FFmpeg
docker run --rm \
  --device /dev/dri/renderD128:/dev/dri/renderD128 \
  -v $(pwd)/videos:/videos \
  linuxserver/ffmpeg:latest \
  -i /videos/input_video.mp4 \
  -vf "subtitles=/videos/input_video.srt" \
  -c:v h264_vaapi -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  /videos/output_video.mp4
```

### Pipeline Completo Automatizado
```bash
#!/bin/bash
# Script de procesamiento de video

VIDEO="$1"
BASENAME=$(basename "$VIDEO" .mp4)
INPUT_DIR="/opt/streaming/entrada"
PROCESS_DIR="/opt/streaming/procesando"
FINAL_DIR="/opt/streaming/final"

# Mover a procesando
mv "$INPUT_DIR/$VIDEO" "$PROCESS_DIR/$VIDEO"

# Generar subtítulos con Whisper
docker run --rm \
  -v "$PROCESS_DIR:/videos" \
  whisper.cpp:main \
  "whisper-cli -m /models/ggml-medium.bin -f /videos/$VIDEO -osrt"

# Recodificar e incrustar subtítulos
docker run --rm \
  --device /dev/dri/renderD128:/dev/dri/renderD128 \
  -v "$PROCESS_DIR:/videos" \
  linuxserver/ffmpeg:latest \
  -i "/videos/$VIDEO" \
  -vf "subtitles=/videos/${BASENAME}.srt" \
  -c:v h264_vaapi -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  "/videos/${BASENAME}_processed.mp4"

# Mover a final
mv "$PROCESS_DIR/${BASENAME}_processed.mp4" "$FINAL_DIR/"

# Limpiar
rm "$PROCESS_DIR/$VIDEO" "$PROCESS_DIR/${BASENAME}.srt"
```

## Plugins de Jellyfin

### Plugins Oficiales
1. **Open Subtitles**
   - Descarga subtítulos de internet
   - Configurable por idioma y biblioteca
   - Fallback cuando Whisper no genera subtítulos

2. **Subtitle Extract**
   - Extrae subtítulos embebidos automáticamente
   - Útil para archivos que ya tienen subtítulos

## Instalación Automatizada

### Script de Instalación Principal

El sistema incluye un script de instalación automatizado (`install.sh`) que realiza todas las configuraciones necesarias automáticamente:

```bash
# Ejecutar como root o con sudo
sudo ./install.sh
```

**Funciones del script:**
- ✅ Verificación de hardware y requisitos
- ✅ Instalación de Docker y Docker Compose
- ✅ Configuración de permisos y grupos (render group)
- ✅ Creación de estructura de directorios completa
- ✅ Descarga y configuración del modelo medium de Whisper
- ✅ Creación de archivo docker-compose.yml
- ✅ Creación de scripts de automatización
- ✅ Configuración de servicios systemd
- ✅ Configuración de firewall
- ✅ Inicio automático de todos los servicios

**Intervención manual mínima:**
1. Ejecutar el script: `sudo ./install.sh`
2. Configurar Jellyfin vía interfaz web (crear usuario, bibliotecas)
3. Copiar videos a `/opt/streaming/entrada/`

Todo lo demás es completamente automático.

### Archivos de Automatización

#### 1. **docker-compose.yml**
Configura los tres servicios principales:

- **jellyfin**: Servidor de media con aceleración hardware
- **whisper**: Whisper.cpp con modelo medium pre-cargado
- **ffmpeg**: FFmpeg con soporte VAAPI para recodificación

#### 2. **scripts/process_video.sh**
Script de procesamiento individual de videos:

```bash
# Uso básico
./process_video.sh video.mp4

# Con idioma específico
./process_video.sh video.mp4 en
```

**Funciones:**
- Mueve video a `/procesando/`
- Genera subtítulos con Whisper
- Recodifica video e incrusta subtítulos
- Mueve resultado a `/final/`
- Limpia archivos temporales
- Logging detallado

#### 3. **scripts/monitor.sh**
Script de monitoreo continuo con inotifywait:

- Detecta automáticamente archivos nuevos en `/entrada/`
- Filtra solo archivos de video
- Llama al script de procesamiento
- Logging de todas las operaciones
- Se ejecuta como servicio systemd

#### 4. **scripts/configure_jellyfin.sh**
Script de ayuda para configuración inicial de Jellyfin:

- Verifica disponibilidad de Jellyfin
- Guía paso a paso la configuración
- Permite configuración avanzada via API

#### 5. **services/streaming-monitor.service**
Servicio systemd para monitoreo automático:

- Se inicia automáticamente con el sistema
- Reinicio automático en caso de error
- Logging de stdout/stderr
- Configuración de seguridad

### Flujo de Instalación Automatizado

```
1. Ejecutar install.sh
   ↓
2. Verificación de hardware
   ↓
3. Instalación de Docker
   ↓
4. Configuración de grupos
   ↓
5. Creación de directorios
   ↓
6. Descarga de modelo Whisper
   ↓
7. Creación de docker-compose.yml
   ↓
8. Creación de scripts
   ↓
9. Configuración de servicios systemd
   ↓
10. Configuración de firewall
    ↓
11. Inicio de servicios
    ↓
12. Configurar Jellyfin (manual)
    ↓
13. Sistema listo para uso
```

### Comandos de Gestión Automatizada

```bash
# Instalar todo automáticamente
sudo ./install.sh

# Ver estado de servicios
cd /opt/streaming
docker-compose ps

# Ver logs en tiempo real
tail -f /opt/streaming/logs/process_*.log
tail -f /opt/streaming/logs/monitor.log

# Reiniciar todo
docker-compose restart && systemctl restart streaming-monitor

# Actualizar imágenes
docker-compose pull && docker-compose up -d

# Verificar procesamiento
ls -lh /opt/streaming/final/
```

## Documentación de Uso

Para documentación completa de uso, mantenimiento y troubleshooting, consultar `README.md`.

## Plan de Implementación

### Fase 1: Instalación Automatizada
1. ✅ Ejecutar script `install.sh`
2. ✅ Verificar instalación correcta
3. ✅ Configurar Jellyfin (usuario, bibliotecas)
4. ✅ Instalar plugins recomendados

### Fase 2: Testing Básico
1. ✅ Copiar video de prueba a `/entrada/`
2. ✅ Verificar procesamiento automático
3. ✅ Verificar subtítulos generados
4. ✅ Verificar video recodificado en `/final/`

### Fase 3: Testing Completo
1. ✅ Probar streaming desde Jellyfin
2. ✅ Probar DLNA en dispositivos de red
3. ✅ Probar con diferentes formatos de video
4. ✅ Verificar rendimiento del sistema

### Fase 4: Optimización (Opcional)
1. ✅ Ajustar parámetros de FFmpeg
2. ✅ Probar diferentes modelos de Whisper
3. ✅ Configurar backup automáticos
4. ✅ Configurar monitoreo de recursos

## Referencias y Documentación

### Jellyfin
- [Documentación Oficial](https://jellyfin.org/docs/)
- [Hardware Acceleration con Docker](https://jellyfin.org/docs/general/installation/advanced/truenas)
- [Docker Compose con GPU](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia)

### Whisper
- [Repositorio OpenAI Whisper](https://github.com/openai/whisper)
- [Whisper.cpp (High-Performance)](https://github.com/ggml-org/whisper.cpp)
- [Documentación Whisper.cpp](https://github.com/ggml-org/whisper.cpp/blob/master/README.md)

### FFmpeg
- [Documentación Oficial FFmpeg](https://ffmpeg.org/documentation.html)
- [FFmpeg All Documentation](https://ffmpeg.org/ffmpeg-all.html)
- [Hardcoding Subtitles](https://ffmpeg.org/ffmpeg-all.html#index-subtitles-1)

### Docker
- [Documentación Docker](https://docs.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)

## Consideraciones de Hardware

### Orange Pi 5 Plus
- **GPU Mali-G610**: Soporta Vulkan y OpenCL → Ideal para Whisper y FFmpeg
- **CPU RK3588 8-core**: Procesamiento paralelo eficiente para FFmpeg
- **8GB RAM**: Suficiente para modelo medium de Whisper + FFmpeg
- **NVMe 2TB**: Excelente para cache y almacenamiento de videos

### Aceleración de Hardware
- **/dev/dri/renderD128**: Dispositivo principal para aceleración GPU
- **VAAPI**: Video Acceleration API para transcoding en Linux ARM
- **Vulkan**: Cross-platform GPU API para Whisper (Mali compatible)

## Consideraciones de Rendimiento

### Whisper
- **Modelo base**: Más rápido, menos preciso
- **Modelo medium**: Balanceado (recomendado para Orange Pi)
- **Modelo large**: Más preciso, más lento

### FFmpeg
- **Preset ultrafast**: Máxima velocidad, menor calidad
- **Preset medium**: Balanceado (recomendado)
- **Preset slow**: Máxima calidad, mayor tiempo de procesamiento

### CRF (Constant Rate Factor)
- **CRF 18-23**: Alta calidad (recomendado 23)
- **CRF 28-32**: Baja calidad, archivos más pequeños

## Troubleshooting Común

### Problemas de Hardware
```bash
# Verificar dispositivos DRI
ls -la /dev/dri/

# Verificar render group
getent group render

# Verificar soporte Vulkan
vulkaninfo | grep -i mali
```

### Problemas de Whisper
```bash
# Probar modelo base primero
whisper video.mp4 --model base --output_format srt

# Verificar instalación de Whisper.cpp
docker run --rm ghcr.io/ggml-org/whisper.cpp:main whisper-cli --help
```

### Problemas de FFmpeg
```bash
# Verificar códecs disponibles
ffmpeg -codecs | grep h264

# Verificar soporte VAAPI
ffmpeg -hwaccels
ffmpeg -h encoder=h264_vaapi
```

## Notas Importantes

1. **Aceleración Hardware**: Es crucial para el rendimiento en Orange Pi
2. **Docker vs Nativo**: Docker es recomendado para todos los servicios, manteniendo passthrough de dispositivos
3. **Estructura de Directorios**: Mantiene organización clara del pipeline
4. **Logging**: Implementar logs robustos para debugging
5. **Backup**: Configurar backup de configuración de Jellyfin y scripts

## Próximos Pasos

El presente documento servirá como guía durante las sesiones de implementación. Se recomienda seguir el plan por fases y documentar cualquier modificación o problema encontrado durante la implementación.

## Archivos del Sistema Automatizado

### Archivos Principales
- `install.sh` - Script de instalación automatizada completa
- `docker-compose.yml` - Configuración de Docker Compose
- `IMPLEMENTACION_STREAMING.md` - Documento de arquitectura y planificación
- `README.md` - Guía de uso, mantenimiento y troubleshooting

### Scripts de Automatización
- `scripts/process_video.sh` - Procesamiento individual de videos
- `scripts/monitor.sh` - Monitoreo continuo con inotifywait
- `scripts/configure_jellyfin.sh` - Configuración inicial de Jellyfin

### Servicios Systemd
- `services/streaming-monitor.service` - Servicio de monitoreo automático

### Directorios (Creados automáticamente por install.sh)
- `entrada/` - Videos a procesar
- `procesando/` - Videos en proceso de transcodificación
- `final/` - Videos procesados (input para Jellyfin)
- `scripts/` - Scripts de automatización
- `configs/` - Configuraciones (Jellyfin)
- `data/` - Datos (cache, modelos)
- `logs/` - Logs del sistema

## Características de Automatización

### ✅ Instalación Completamente Automatizada
- Un solo comando ejecuta toda la instalación
- Detección automática de hardware
- Configuración de permisos y grupos
- Descarga automática de modelos

### ✅ Procesamiento Automático
- Detección automática de archivos nuevos
- Procesamiento en segundo plano
- Logging detallado
- Manejo de errores

### ✅ Servicios Autónomos
- Inicio automático con el sistema
- Reinicio automático en caso de error
- Monitoreo continuo
- Logs persistentes

### ✅ Mantenimiento Simplificado
- Actualizaciones con docker-compose pull
- Backup de configuración simple
- Troubleshooting documentado
- Comandos de gestión estandarizados