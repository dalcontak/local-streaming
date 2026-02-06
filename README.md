# Stack de Streaming Local - Guía de Uso

## Descripción

Sistema de streaming local automatizado con generación de subtítulos mediante IA, ejecutado en Orange Pi 5 Plus.

## Arquitectura

```
[Usuario] → Copia video → [entrada/] → [Automatización] → [procesando/] → [final/] → [Jellyfin]
                                                 ↓
                                         [Whisper → FFmpeg]
```

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
   - Crear biblioteca apuntando a `/media`
   - Instalar plugins: Open Subtitles, Subtitle Extract

## Uso Básico

### Agregar Videos al Sistema

1. **Método 1: Copiar archivos (Automático)**
   ```bash
   cp /ruta/a/video.mp4 /opt/streaming/entrada/
   ```
   El sistema detectará automáticamente y procesará el video.

2. **Método 2: Procesamiento manual**
   ```bash
   /opt/streaming/scripts/process_video.sh video.mp4 [idioma]
   ```

3. **Método 3: Via NFS**
   Configurar cliente NFS montando la carpeta compartida en `/opt/streaming/entrada`.

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
docker logs whisper
docker logs ffmpeg
```

## Directorios del Sistema

```
/opt/streaming/
├── entrada/              # Videos a procesar (input)
├── procesando/          # Videos en proceso de transcodificación
├── final/               # Videos procesados (input para Jellyfin)
├── scripts/             # Scripts de automatización
│   ├── process_video.sh # Procesamiento individual
│   ├── monitor.sh       # Monitoreo continuo
│   └── configure_jellyfin.sh # Configuración Jellyfin
├── configs/             # Configuraciones
│   └── jellyfin/        # Configuración Jellyfin
├── data/                # Datos
│   ├── jellyfin/cache/  # Cache Jellyfin
│   └── whisper/models/  # Modelos Whisper
├── logs/                # Logs del sistema
└── docker compose.yml   # Configuración Docker
```

## Configuración Avanzada

### Modificar Idioma de Subtítulos Predeterminado

Editar `/opt/streaming/scripts/process_video.sh`:
```bash
LANGUAGE="${2:-es}"  # Cambiar 'es' por tu idioma preferido
```

### Ajustar Calidad de Video

Editar `/opt/streaming/scripts/process_video.sh`:
```bash
-crf 23              # Menor número = mejor calidad (18-28)
-preset medium       # ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
```

### Cambiar Modelo de Whisper

Editar `/opt/streaming/scripts/process_video.sh`:
```python
model = whisper.load_model('medium')  # Opciones: base, small, medium, large
```

### Configurar Zona Horaria

Editar `docker compose.yml`:
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

### Actualizar Modelo de Whisper

```bash
docker exec whisper python -c "import whisper; whisper.load_model('medium')"
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

### Whisper falla al generar subtítulos

```bash
# Ver logs de procesamiento
tail -f /opt/streaming/logs/process_*.log

# Verificar modelo existe
ls -la /opt/streaming/data/whisper/models/

# Re-descargar modelo
docker exec whisper python -c "import whisper; whisper.load_model('medium')"
```

### FFmpeg falla al recodificar

```bash
# Verificar dispositivo DRI
ls -la /dev/dri/

# Verificar grupo render
getent group render

# Ver logs de FFmpeg
docker logs ffmpeg

# Probar recodificación manual
docker exec ffmpeg ffmpeg -hwaccels
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
# Verificar dispositivos DRI
ls -la /dev/dri/

# Verificar grupos
groups $(whoami)

# Agregar usuario a grupos
sudo usermod -aG docker,render,video $(whoami)

# Re-iniciar sesión o reiniciar
sudo reboot
```

## Configuración NFS (Opcional)

Si prefieres montar la carpeta de videos via NFS:

```bash
# Crear punto de montaje
sudo mkdir -p /mnt/nfs/videos

# Agregar a /etc/fstab
echo "<SERVER_IP>:/path/to/videos /mnt/nfs/videos nfs defaults 0 0" | sudo tee -a /etc/fstab

# Montar
sudo mount -a

# Crear symlink
sudo ln -s /mnt/nfs/videos /opt/streaming/entrada
```

## Rendimiento y Optimización

### Recomendaciones para Orange Pi 5 Plus

- **Modelo Whisper**: `medium` (balance calidad/velocidad)
- **CRF FFmpeg**: `23` (calidad buena sin牺牲 velocidad)
- **Preset FFmpeg**: `medium`
- **Concurrent processing**: Evitar procesar múltiples videos simultáneamente

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
- **Whisper**: https://github.com/openai/whisper
- **Whisper.cpp**: https://github.com/ggml-org/whisper.cpp
- **FFmpeg**: https://ffmpeg.org/documentation.html
- **Docker**: https://docs.docker.com/

## Licencia

Este sistema utiliza software open-source:

- Jellyfin: GPL v2.0
- Whisper: MIT License
- Whisper.cpp: MIT License
- FFmpeg: GPL/LGPL
- Docker: Apache 2.0

## Contribuciones

Para mejoras o reporte de bugs, por favor utiliza el sistema de tickets del proyecto.

---

**Versión**: 1.0
**Fecha**: 2026-02-05
**Desarrollado para**: Orange Pi 5 Plus con Armbian