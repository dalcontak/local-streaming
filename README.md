# Stack de Streaming Local - Guía de Uso

## Descripción

Sistema de streaming local automatizado con recodificación de video, ejecutado en Orange Pi 5 Plus.

## Arquitectura

```
[Usuario] → Copia video → [entrada/] → [Monitor] → [procesando/] → [final/] → [Jellyfin]
                                            ↓
                                    [FFmpeg (RKMPP)]
                                   (dentro de Jellyfin)
```

Un solo contenedor Docker (`jellyfin/jellyfin:latest`) que incluye:
- Jellyfin como servidor de media
- FFmpeg con aceleración hardware RKMPP para Rockchip RK3588
- Fallback automático a libx264 (software) si RKMPP no está disponible

## Instalación Rápida

1. **Descargar script de instalación:**
   ```bash
   cd /opt
   git clone <repositorio> streaming
   cd streaming
   ```

2. **Ejecutar instalación:**
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

3. **Configurar Jellyfin:**
    - Acceder a `http://<IP-ORANGEPI>:8096`
    - Completar configuración inicial
    - Crear biblioteca de **Películas** apuntando a `/media/Peliculas`
    - Crear biblioteca de **Series** apuntando a `/media/Series`

## Uso Básico

### Agregar Videos al Sistema

El sistema clasifica automáticamente las películas y series según la carpeta de origen.

**IMPORTANTE**: Los archivos deben tener nombres que Jellyfin pueda reconocer para descargar metadata, carátulas y descripciones.

#### Naming para Películas

Copiar a `/opt/streaming/entrada/Peliculas/` con el formato:

```
Nombre de la Pelicula (Año).ext
```

Ejemplos:
```bash
cp pelicula.mp4 "/opt/streaming/entrada/Peliculas/Inception (2010).mp4"
cp otra.mkv "/opt/streaming/entrada/Peliculas/The Matrix (1999).mkv"
cp archivo.avi "/opt/streaming/entrada/Peliculas/Coco (2017).avi"
```

#### Naming para Series

Copiar a `/opt/streaming/entrada/Series/` con el formato:

```
Nombre de la Serie S01E01.ext
```

O mejor aún, organizados en subcarpetas:

```
entrada/Series/Breaking Bad/S01E01.mp4
entrada/Series/Breaking Bad/S01E02.mp4
entrada/Series/The Office/S02E05.mp4
```

Ejemplos:
```bash
# Opción 1: nombre plano
cp episodio.mp4 "/opt/streaming/entrada/Series/Breaking Bad S01E01.mp4"

# Opción 2: con subcarpeta (recomendado)
mkdir -p "/opt/streaming/entrada/Series/Breaking Bad"
cp episodio.mp4 "/opt/streaming/entrada/Series/Breaking Bad/S01E01.mp4"
```

#### Nombres que Jellyfin NO reconoce

```
video_descargado_720p.mp4        # Sin nombre ni año
pelicula.mp4                     # Muy genérico
EP01.mp4                         # Sin nombre de serie
rip_bluray_final_v2.mkv          # Sin información útil
```

**Nota**: El sistema detecta automáticamente y procesa los videos en ambas carpetas.

3. **Procesamiento manual**
    ```bash
    # Para película
    /opt/streaming/scripts/process_video.sh "Peliculas/nombre_pelicula.mp4"
    
    # Para serie
    /opt/streaming/scripts/process_video.sh "Series/S01E01_episodio.mp4"
    ```

4. **Via NFS**
    Configurar cliente NFS montando las carpetas compartidas:
    - `/mnt/nfs/peliculas` → `/opt/streaming/entrada/Peliculas`
    - `/mnt/nfs/series` → `/opt/streaming/entrada/Series`

### Ver Progreso del Procesamiento

```bash
# Ver logs en tiempo real
tail -f /opt/streaming/logs/process_*.log

# Ver log de monitoreo
tail -f /opt/streaming/logs/monitor.log
```

### Gestionar Servicios

```bash
# Ver estado
cd /opt/streaming
docker compose ps

# Reiniciar servicios
docker compose restart

# Detener servicios
docker compose down

# Iniciar servicios
docker compose up -d

# Ver logs de contenedores
docker logs jellyfin
```

## Directorios del Sistema

```
/opt/streaming/
├── entrada/              # Videos a procesar (input)
│   ├── Peliculas/       # Carpeta para películas
│   └── Series/          # Carpeta para series
├── procesando/          # Videos en proceso de transcodificación
├── final/               # Videos procesados (input para Jellyfin)
│   ├── Peliculas/       # Películas procesadas
│   └── Series/          # Series procesadas
├── scripts/             # Scripts de automatización
│   ├── config.sh        # Configuración del sistema
│   ├── process_video.sh # Procesamiento individual
│   └── monitor.sh       # Monitoreo continuo
├── configs/             # Configuraciones
│   └── jellyfin/        # Configuración Jellyfin
├── data/                # Datos
│   └── jellyfin/cache/  # Cache Jellyfin
├── logs/                # Logs del sistema
└── docker-compose.yml   # Configuración Docker
```

## Configuración Avanzada

### Configuración General

Editar `/opt/streaming/scripts/config.sh`:

```bash
# Número máximo de procesos paralelos (1 = secuencial, 2+ = paralelo)
MAX_PARALLEL_PROCES=1

# Codec objetivo (h264, h265)
VIDEO_CODEC_TARGET="h264"
AUDIO_CODEC_TARGET="aac"

# Calidad de video (menor = mejor calidad)
VIDEO_CRF=23

# Preset FFmpeg
FFMPEG_PRESET="medium"
```

**Importante**: Después de modificar la configuración, reinicia el servicio de monitoreo:

```bash
systemctl restart streaming-monitor.service
```

### Ajustar Procesamiento Paralelo

Para procesar múltiples videos simultáneamente, edita `/opt/streaming/scripts/config.sh`:

```bash
MAX_PARALLEL_PROCES=2  # Procesar hasta 2 videos al mismo tiempo
```

**Recomendaciones para Orange Pi 5 Plus**:
- **4GB RAM**: 1 proceso (secuencial)
- **8GB+ RAM**: 2-3 procesos (paralelo)

### Ajustar Calidad de Video

Editar `/opt/streaming/scripts/config.sh`:
```bash
VIDEO_CRF=23              # Menor número = mejor calidad (18-28)
FFMPEG_PRESET="medium"   # ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
```

### Configurar Zona Horaria

Editar `docker-compose.yml`:
```yaml
environment:
  - TZ=America/Mexico_City  # Cambiar a tu zona horaria
```

## Mantenimiento

### Actualizar Imágenes Docker

```bash
cd /opt/streaming
docker compose pull
docker compose up -d
```

### Limpiar Cache de Jellyfin

```bash
rm -rf /opt/streaming/data/jellyfin/cache/*
docker compose restart jellyfin
```

### Limpiar Logs Antiguos

```bash
# Eliminar logs mayores a 7 días
find /opt/streaming/logs -name "*.log" -mtime +7 -delete
```

### Verificar Espacio en Disco

```bash
df -h /opt/streaming
du -sh /opt/streaming/final/
du -sh /opt/streaming/data/
```

## Troubleshooting

### Jellyfin no inicia

```bash
# Ver logs
docker logs jellyfin

# Verificar permisos
ls -la /opt/streaming/configs/jellyfin/

# Reiniciar
docker compose restart jellyfin
```

### FFmpeg falla al recodificar

```bash
# Verificar dispositivos RKMPP
ls -la /dev/dri/ /dev/mpp_service /dev/rga /dev/dma_heap

# Verificar grupo render
getent group render

# Verificar que RKMPP está disponible
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -encoders 2>/dev/null | grep rkmpp

# Probar recodificación manual con RKMPP
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hwaccel rkmpp -hwaccel_output_format drm_prime -i /videos/test.mp4 -c:v h264_rkmpp -y /videos/test_out.mp4

# Si RKMPP no funciona, verificar kernel (requiere BSP 5.10/6.1)
uname -r
```

### Videos no se procesan automáticamente

```bash
# Verificar servicio de monitoreo
systemctl status streaming-monitor

# Ver logs de monitoreo
tail -f /opt/streaming/logs/monitor.log

# Reiniciar servicio
systemctl restart streaming-monitor
```

### Aceleración Hardware No Disponible

```bash
# Verificar dispositivos RKMPP (Rockchip)
ls -la /dev/dri/ /dev/mpp_service /dev/rga /dev/dma_heap

# Verificar kernel (RKMPP requiere BSP kernel 5.10 o 6.1)
uname -r

# Verificar grupos
groups $(whoami)

# Agregar usuario a grupos
sudo usermod -aG docker,render,video $(whoami)

# Verificar encoders RKMPP disponibles
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -encoders 2>/dev/null | grep rkmpp

# Si RKMPP no funciona, el sistema usa libx264 (software) automáticamente
# Re-iniciar sesión o reiniciar
sudo reboot
```

## Configuración NFS (Opcional)

Si prefieres montar las carpetas de videos via NFS:

```bash
# Crear puntos de montaje
sudo mkdir -p /mnt/nfs/peliculas
sudo mkdir -p /mnt/nfs/series

# Agregar a /etc/fstab
echo "<SERVER_IP>:/path/to/peliculas /mnt/nfs/peliculas nfs defaults 0 0" | sudo tee -a /etc/fstab
echo "<SERVER_IP>:/path/to/series /mnt/nfs/series nfs defaults 0 0" | sudo tee -a /etc/fstab

# Montar
sudo mount -a

# Crear symlinks a las carpetas de entrada
sudo ln -sf /mnt/nfs/peliculas /opt/streaming/entrada/Peliculas
sudo ln -sf /mnt/nfs/series /opt/streaming/entrada/Series
```

## Rendimiento y Optimización

### Recomendaciones para Orange Pi 5 Plus

- **CRF FFmpeg**: `23` (calidad buena sin sacrificar velocidad)
- **Preset FFmpeg**: `medium`
- **Concurrent processing**: Evitar procesar más de 1-2 videos simultáneamente en 4GB RAM

### Monitorear Recursos

```bash
# Uso de CPU
htop

# Uso de memoria
free -h

# Uso de disco
df -h

# Uso de GPU (si aplica)
sudo apt install mesa-utils
glxinfo | grep "OpenGL renderer"
```

## Seguridad

### Configurar Firewall

```bash
# Habilitar firewall
sudo ufw enable

# Ver estado
sudo ufw status

# Permitir puertos específicos
sudo ufw allow 8096/tcp  # Jellyfin
sudo ufw allow 1900/udp  # DLNA
sudo ufw allow 7359/udp  # DLNA Discovery
```

### Backup de Configuración

```bash
# Backup completo
tar -czf streaming_backup_$(date +%Y%m%d).tar.gz /opt/streaming/configs/ /opt/streaming/scripts/

# Backup Jellyfin config
tar -czf jellyfin_config_$(date +%Y%m%d).tar.gz /opt/streaming/configs/jellyfin/
```

## Actualización del Sistema

### Actualizar Scripts

```bash
cd /opt/streaming
git pull
```

### Actualizar Sistema Operativo

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

## Soporte y Documentación

- **Jellyfin**: https://jellyfin.org/docs/
- **FFmpeg**: https://ffmpeg.org/documentation.html
- **Docker**: https://docs.docker.com/

## Licencia

Este sistema utiliza software open-source:

- Jellyfin: GPL v2.0
- FFmpeg: GPL/LGPL
- Docker: Apache 2.0

## Contribuciones

Para mejoras o reporte de bugs, por favor utiliza el sistema de tickets del proyecto.

---

**Versión**: 1.2
**Fecha**: 2026-02-09
**Desarrollado para**: Orange Pi 5 Plus con Armbian
