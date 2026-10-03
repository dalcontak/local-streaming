# Stack de Streaming Local

Sistema de streaming local automatizado para Orange Pi 5 Plus (Rockchip RK3588):
recibe videos desde carpetas locales o NFS, los recodifica a **H.264/AAC**
(usando aceleración hardware cuando está disponible) y publica el resultado en
**Jellyfin**.

## Características

- **Procesamiento automático**: un servicio (`streaming-monitor`) vigila la
  carpeta de entrada y lanza la recodificación sin intervención manual.
- **Clasificación automática** de Películas y Series según la carpeta de origen.
- **Aceleración hardware** Rockchip (RKMPP en kernel vendor, V4L2 en kernel
  current) con *fallback* automático a `libx264` (software).
- **Jellyfin integrado** en el mismo contenedor que sirve el catálogo.
- **Entrada por NFS** opcional para montar las carpetas desde otro equipo.
- **Configuración sencilla** vía `scripts/config.sh` (paralelismo, codecs, calidad).

## Arquitectura

```
[Usuario] → Copia video → [entrada/] → [Monitor] → [procesando/] → [final/] → [Jellyfin]
                                             ↓
                                  [FFmpeg (RKMPP / V4L2)]
                                  (dentro del contenedor Jellyfin)
```

Un solo contenedor Docker (`nyanmisaka/jellyfin:latest-rockchip`) que incluye:

- Jellyfin como servidor de media.
- FFmpeg con aceleración hardware para Rockchip RK3588.
- Fallback automático a `libx264` (software) si el hardware no está disponible.

## Requisitos

- **Hardware**: Orange Pi 5 Plus (RK3588) o placa RK3588 equivalente.
- **Sistema**: Armbian con kernel que exponga los codecs Rockchip:
  - kernel **vendor** (`linux-image-vendor-rk35xx`): codecs vía `/dev/mpp_service`.
  - kernel **current** (`linux-image-current-rockchip-rk3588`): codecs vía V4L2
    (`/dev/video*`, `/dev/media*`).
- **Docker** y **Docker Compose** instalados.
- Grupo **`render`** en el sistema (su ID se ajusta en el compose).
- **FFmpeg con soporte Rockchip**: ya incluido en la imagen de Jellyfin.

Para verificar los dispositivos disponibles:

```bash
ls -la /dev/video* /dev/media* /dev/mpp_service /dev/dri/ /dev/dma_heap 2>&1
uname -r
getent group render
```

## Instalación

1. **Clonar el repositorio en el equipo:**

   ```bash
   cd /opt
   git clone <repositorio> streaming
   cd streaming
   ```

2. **Ejecutar la instalación:**

   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

3. **Configurar Jellyfin:**
   - Acceder a `http://<IP-ORANGEPI>:8096`.
   - Completar la configuración inicial.
   - Crear biblioteca de **Películas** apuntando a `/media/Peliculas`.
   - Crear biblioteca de **Series** apuntando a `/media/Series`.

## Uso

### Agregar videos al sistema

El sistema clasifica automáticamente las películas y series según la carpeta de
origen. **Importante**: los nombres deben ser reconocibles por Jellyfin para
descargar metadata, carátulas y descripciones.

#### Naming para Películas

Copiar a `/opt/streaming/entrada/Peliculas/` con el formato:

```
Nombre de la Pelicula (Año).ext
```

Ejemplos:

```bash
cp pelicula.mp4 "/opt/streaming/entrada/Peliculas/Inception (2010).mp4"
cp otra.mkv    "/opt/streaming/entrada/Peliculas/The Matrix (1999).mkv"
cp archivo.avi "/opt/streaming/entrada/Peliculas/Coco (2017).avi"
```

#### Naming para Series

Copiar a `/opt/streaming/entrada/Series/` con el formato:

```
Nombre de la Serie S01E01.ext
```

O mejor, organizados en subcarpetas:

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

### Procesamiento manual

```bash
# Para película
/opt/streaming/scripts/process_video.sh "Peliculas/nombre_pelicula.mp4"

# Para serie
/opt/streaming/scripts/process_video.sh "Series/S01E01_episodio.mp4"
```

### Entrada vía NFS

Montar las carpetas compartidas del servidor y enlazarlas a la entrada:

- `/mnt/nfs/peliculas` → `/opt/streaming/entrada/Peliculas`
- `/mnt/nfs/series` → `/opt/streaming/entrada/Series`

Ver la sección [Configuración NFS](#configuración-nfs-opcional).

### Ver progreso del procesamiento

```bash
# Ver logs de procesamiento en tiempo real
tail -f /opt/streaming/logs/process_*.log

# Ver log de monitoreo
tail -f /opt/streaming/logs/monitor.log
```

### Gestionar servicios

```bash
cd /opt/streaming

# Estado
docker compose ps

# Reiniciar
docker compose restart

# Detener
docker compose down

# Iniciar
docker compose up -d

# Logs del contenedor Jellyfin
docker logs jellyfin
```

## Directorios del sistema

```
/opt/streaming/
├── entrada/              # Videos a procesar (input)
│   ├── Peliculas/        # Carpeta para películas
│   └── Series/           # Carpeta para series
├── procesando/           # Videos en proceso de transcodificación
├── final/                # Videos procesados (input para Jellyfin)
│   ├── Peliculas/        # Películas procesadas
│   └── Series/           # Series procesadas
├── scripts/              # Scripts de automatización
│   ├── config.sh         # Configuración del sistema
│   ├── process_video.sh  # Procesamiento individual
│   └── monitor.sh        # Monitoreo continuo
├── configs/              # Configuraciones
│   └── jellyfin/         # Configuración Jellyfin
├── data/                 # Datos
│   └── jellyfin/cache/   # Cache Jellyfin
├── logs/                 # Logs del sistema
└── docker-compose.yml    # Configuración Docker
```

## Configuración avanzada

### Configuración general

Editar `/opt/streaming/scripts/config.sh`:

```bash
# Número máximo de procesos paralelos (1 = secuencial, 2+ = paralelo)
MAX_PARALLEL_PROCES=2

# Codec objetivo (h264, h265)
VIDEO_CODEC_TARGET="h264"
AUDIO_CODEC_TARGET="aac"

# Calidad de video (menor = mejor calidad)
VIDEO_CRF=23

# Preset FFmpeg
FFMPEG_PRESET="medium"
```

**Importante**: después de modificar la configuración, reinicia el servicio de
monitoreo:

```bash
systemctl restart streaming-monitor.service
```

### Ajustar procesamiento paralelo

Editar `/opt/streaming/scripts/config.sh`:

```bash
MAX_PARALLEL_PROCES=2  # Procesar hasta 2 videos al mismo tiempo
```

Recomendaciones para Orange Pi 5 Plus:

- **4 GB RAM**: 1 proceso (secuencial).
- **8 GB+ RAM**: 2-3 procesos (paralelo).

### Ajustar calidad de video

Editar `/opt/streaming/scripts/config.sh`:

```bash
VIDEO_CRF=23             # Menor número = mejor calidad (rango 18-28)
FFMPEG_PRESET="medium"   # ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
```

### Configurar zona horaria

Editar `docker-compose.yml`:

```yaml
environment:
  - TZ=America/Mexico_City  # Cambiar a tu zona horaria
```

## Mantenimiento

### Actualizar imágenes Docker

```bash
cd /opt/streaming
docker compose pull
docker compose up -d
```

### Limpiar cache de Jellyfin

```bash
rm -rf /opt/streaming/data/jellyfin/cache/*
docker compose restart jellyfin
```

### Limpiar logs antiguos

```bash
# Eliminar logs mayores a 7 días
find /opt/streaming/logs -name "*.log" -mtime +7 -delete
```

### Verificar espacio en disco

```bash
df -h /opt/streaming
du -sh /opt/streaming/final/
du -sh /opt/streaming/data/
```

## Rendimiento y optimización

Recomendaciones para Orange Pi 5 Plus:

- **CRF FFmpeg**: `23` (buena calidad sin sacrificar velocidad).
- **Preset FFmpeg**: `medium`.
- **Procesamiento concurrente**: no superar 1-2 videos simultáneos con 4 GB RAM.

Monitorear recursos:

```bash
htop              # Uso de CPU
free -h           # Uso de memoria
df -h             # Uso de disco
```

## Seguridad

### Configurar firewall

```bash
# Habilitar firewall
sudo ufw enable

# Ver estado
sudo ufw status

# Permitir puertos
sudo ufw allow 8096/tcp  # Jellyfin
sudo ufw allow 1900/udp  # DLNA
sudo ufw allow 7359/udp  # DLNA Discovery
```

### Backup de configuración

```bash
# Backup completo
tar -czf streaming_backup_$(date +%Y%m%d).tar.gz \
  /opt/streaming/configs/ /opt/streaming/scripts/

# Backup Jellyfin config
tar -czf jellyfin_config_$(date +%Y%m%d).tar.gz \
  /opt/streaming/configs/jellyfin/
```

## Configuración NFS (opcional)

Si prefieres montar las carpetas de videos vía NFS:

```bash
# Crear puntos de montaje
sudo mkdir -p /mnt/nfs/peliculas
sudo mkdir -p /mnt/nfs/series

# Agregar a /etc/fstab
echo "<SERVER_IP>:/path/to/peliculas /mnt/nfs/peliculas nfs defaults 0 0" | sudo tee -a /etc/fstab
echo "<SERVER_IP>:/path/to/series    /mnt/nfs/series    nfs defaults 0 0" | sudo tee -a /etc/fstab

# Montar
sudo mount -a

# Crear symlinks a las carpetas de entrada
sudo ln -sf /mnt/nfs/peliculas /opt/streaming/entrada/Peliculas
sudo ln -sf /mnt/nfs/series    /opt/streaming/entrada/Series
```

## Actualización del sistema

### Actualizar scripts

```bash
cd /opt/streaming
git pull
```

### Actualizar sistema operativo

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

## Soporte y documentación

- **Jellyfin**: https://jellyfin.org/docs/
- **FFmpeg**: https://ffmpeg.org/documentation.html
- **Docker**: https://docs.docker.com/

## Licencia

Este sistema utiliza software open-source:

- Jellyfin: GPL v2.0
- FFmpeg: GPL/LGPL
- Docker: Apache 2.0

## Contribuciones

Para mejoras o reporte de bugs, utiliza el sistema de tickets del proyecto.

---

**Versión**: 1.2
**Fecha**: 2026-02-09
**Desarrollado para**: Orange Pi 5 Plus con Armbian
