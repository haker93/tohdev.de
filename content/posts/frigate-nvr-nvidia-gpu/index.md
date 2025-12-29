---
title: "Frigate NVR mit NVIDIA GPU einrichten"
date: 2025-12-28T21:22:18Z
draft: false
tags: ["frigate", "nvr", "nvidia", "docker", "ki", "überwachung", "yolo"]
categories: ["Tutorial", "Smart Home"]
author: "Tobias"
description: "Anleitung zur Installation von Frigate NVR mit NVIDIA GPU-Beschleunigung für KI-basierte Objekterkennung in Überwachungskameras"
cover:
  image: ""
  alt: "Frigate NVR Logo"
  caption: ""
  relative: false
---

## Was ist Frigate?

Frigate ist ein Open-Source Network Video Recorder (NVR) mit KI-gestützter Objekterkennung. Anders als klassische Überwachungssysteme nutzt Frigate moderne Machine-Learning-Modelle wie YOLOv9, um Personen, Fahrzeuge und andere Objekte in Echtzeit zu erkennen. Mit einem KI-Beschleuniger wie einer handelsüblichen GPU läuft die Objekterkennung besonders performant.

In diesem Artikel zeige ich, wie du Frigate auf einem Ubuntu-System mit NVIDIA-GPU einrichten kannst.

## Voraussetzungen

- Ubuntu Server (ich nutze Ubuntu 24.04)
- Nvidia-Grafikkarte mit mindestens 4GB VRAM (Ich nutze eine RTX 5060 Ti mit 16 GB VRAM)
- Docker und Docker Compose
- Ausreichend Speicherplatz für Aufnahmen

## 1. NVIDIA-Treiber installieren

Zuerst prüfen wir, welche Treiber für deine GPU verfügbar sind:

```bash
sudo ubuntu-drivers devices
```

Standardmäßig wird der offene Nouveau Treiber genutzt. Wir benötigen aber den propritären Treiber von Nvidia.

Installiere den empfohlenen Treiber automatisch:

```bash
sudo ubuntu-drivers autoinstall
```

Nach der Installation kannst du das `nvidia-smi` Komamndo nutzen. Es sollte dir deine GPU anzeigen und den Status deiner Grafikkarte (Temperatur, Leistungsaufnahme, GPU-Prozesse, etc)

```bash
sudo nvidia-smi
```

Meine Ausgabge sieht bspw so aus: 

```plain
root@tower7:/home/tobias# sudo nvidia-smi
Sun Dec 28 22:31:56 2025
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.95.05              Driver Version: 580.95.05      CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 5060 Ti     Off |   00000000:01:00.0 Off |                  N/A |
| 31%   38C    P1             51W /  180W |    3482MiB /  16311MiB |      3%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A         1998440      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          166MiB |
|    0   N/A  N/A         3103288      C   frigate.detector:onnx0                  604MiB |
|    0   N/A  N/A         3103291      C   frigate.detector:onnx1                  604MiB |
|    0   N/A  N/A         3103295      C   frigate.detector:onnx2                  604MiB |
|    0   N/A  N/A         3103585      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          218MiB |
|    0   N/A  N/A         3103717      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          234MiB |
|    0   N/A  N/A         3103841      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          234MiB |
|    0   N/A  N/A         3103963      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          234MiB |
|    0   N/A  N/A         3104089      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          188MiB |
|    0   N/A  N/A         3104209      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          156MiB |
|    0   N/A  N/A         3104223      C   /usr/lib/ffmpeg/7.0/bin/ffmpeg          174MiB |
+-----------------------------------------------------------------------------------------+
```

## 2. Nvidia Container Toolkit installieren

Frigate wird in einem Docker Container ausgeführt. Damit Docker die GPU nutzen kann und sie dem Container zur Verfügung stellen kann, benötigen wir das Nvidia Container Toolkit. 

Die offizielle Anleitung dazu in der [Nvidia Dokumentation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) zu finden.

```bash
# Repository-Schlüssel und Paketquelle hinzufügen
sudo apt-get update && sudo apt-get install -y --no-install-recommends curl gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Paketquellen aktualisieren
sudo apt-get update
```
Installiere das Toolkit. Prüfe vorher [hier](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), ob es vielleicht eine aktuellere Version gibt. Bei mir war Version 1.18.1 die aktuellste Version.

```bash
# Installiere das Nvidia Container Toolkit
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.1-1
sudo apt-get install -y nvidia-container-toolkit=$NVIDIA_CONTAINER_TOOLKIT_VERSION

# Konfiguriere Docker für die GPU-Nutzung
sudo nvidia-ctk runtime configure --runtime=docker

# Docker muss einmal neu gestartet werden
sudo systemctl restart docker
```

## 3. Frigate-Verzeichnisse erstellen

Erstelle die benötigten Verzeichnisse für Frigate:

```bash
# Hier packe ich die docker-compose.yml rein.
sudo mkdir -p /mnt/data/frigate

# Hier wird das Konfigurationsverzeichnis von Frigate in den Container gemappt.
sudo mkdir -p /mnt/data/frigate/config

# Hier werden Objekterkennungs-Modelle abgelegt. Beispielsweise YoloV9.
sudo mkdir -p /mnt/data/frigate/config/model_cache

# Hier werden Videodaten und Snapshots abgespeichert. Hier sollte viel Speicherplatz verfügbar sein.
sudo mkdir -p /mnt/cctv/frigate-storage
```

{{< notice tip >}}
**Tipp:** Verwende für `/mnt/cctv/frigate-storage` idealerweise eine separate Festplatte, um die System-SSD zu schonen. 
{{< /notice >}}

## 4. Docker Compose Konfiguration

Erstelle die Docker Compose-Datei für Frigate. Ich nutze das Image `ghcr.io/blakeblackshear/frigate:0.17.0-beta1-tensorrt`. Achte auf das **-tensorrt** Suffix, denn dieses Image unterstützt die Nvidia GPU. 

Ob eine neuere Version von Frigate existiert, kannst du [hier](https://github.com/blakeblackshear/frigate/releases) nachsehen. Passe entsprechend die Version im Image-Tag an.

```bash
sudo tee /mnt/data/frigate/docker-compose.yml << 'EOF'
services:
  frigate:
    container_name: frigate
    image: ghcr.io/blakeblackshear/frigate:0.17.0-beta1-tensorrt
    restart: unless-stopped
    stop_grace_period: 30s
    # Wenn du sehr viele Kameras nutzt, musst du diesen Wert ggf. ein wenig höher stellen. 
    # In der Web-Oberfläche von Frigate siehst du, wie viel /dev/shm ausgelastet ist und 
    # kannst den Wert hier dann anpassen.
    shm_size: "1024mb"
    # Die GPU dem Container zur Verfügung stellen.
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1  # Oder 'all' für alle GPUs
              capabilities: [gpu]
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /mnt/data/frigate/config:/config
      - /mnt/cctv/frigate-storage:/media/frigate
      - type: tmpfs  # Reduziert SSD-Verschleiß
        target: /tmp/cache
        tmpfs:
          # 1 GB
          size: 1000000000
    ports:
      - "8971:8971"  # Hauptwebinterface
      - "5000:5000"  # Ungeschützte API- und Weboberfläche
      - "8554:8554"  # RTSP-Feeds
      - "8555:8555/tcp"  # WebRTC über TCP
      - "8555:8555/udp"  # WebRTC über UDP
    environment:
      FRIGATE_RTSP_PASSWORD: "DEIN_SICHERES_PASSWORT"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
```

Du kannst jetzt schonmal den Container mit `docker compose up -d` starten. Wir müssen allerdings noch ein Objekterkennungsmodell laden und die Konfiguration erstellen.

## 5. YOLOv9-Modell generieren

Frigate benötigt ein KI-Modell für die Objekterkennung. Wir nutzen YOLOv9, das wir für unsere GPU optimieren. Nvidia GPUs arbeiten am besten mit einem Modell im ONNX Format. Beachte, dass nicht jedes Modell mit jedem Format kompatibel ist. 

Wir können das YOLOv9 Modell mit Docker herunterladen und konvertieren:

```bash
# Wechsle ins Heimverzeichnis
cd ~

# Passe die MODEL_SIZE und die IMG_SIZE an. 
docker build . \
  --build-arg MODEL_SIZE=m \
  --build-arg IMG_SIZE=640 \
  --output . \
  -f- <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y libgl1 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /bin/
WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier>=0.4.1 onnxscript openvino-dev
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
# ONNX Format:
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx
# OpenVino Format, komprimiert für FP16 Operationen.
RUN ovc yolov9-${MODEL_SIZE}.onnx --output_model yolov9-${MODEL_SIZE}_fp16 --compress_to_fp16
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}_fp16.xml /yolov9-${MODEL_SIZE}-${IMG_SIZE}.xml
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}_fp16.bin /yolov9-${MODEL_SIZE}-${IMG_SIZE}.bin
EOF
```

### Modell-Parameter erklärt

**MODEL_SIZE:**
- `t` (tiny) - Sehr schnell, dafür aber etwas geringerere Genauigkeit
- `s` (small) - Gute Balance für Echtzeit
- `m` (medium) - Genaue Erkennung, dafür aber etwas langsamer
- `c`, `e` - Sehr genau, aber zu langsam für Echtzeit

**IMG_SIZE:**
- `320` - Sehr schnell, gut um große Objekte zu erkennen
- `640` - Ausgewogen, gut um auch kleinere oder weiter entferntere Objekte erkennen zu können
- `1024`/`1280` - Erkennt noch kleinere Objekte, benötigt allerdings mehr Leistung

{{< notice info >}}
**Faustregel:** Größere Modelle und Bildgrößen verbessern die Erkennungsgenauigkeit, erhöhen aber oft die Inferenzzeit. Also die Objekterkennungszeit. 

Für Echtzeit-Überwachung ist `m` mit `640px` das größte, was man sinnvollerweise einsetzen sollte. Wenn man viele oder sehr hochauflösende Kameras hat, muss man gegebenenfalls ein wenig balancieren und vielleicht ein kleineres Modell nutzen oder die Imagesize reduzieren.
{{< /notice >}}

Kopiere die generierten Modelle ins Frigate Konfigurationsverzeichnis:

```bash
# ONNX:
sudo cp -f yolov9-m-640.onnx /mnt/data/frigate/config/model_cache/yolo.onnx
# OpenVino Format (komprimiert auf FP16)
sudo cp -f yolov9-m-640.xml /mnt/data/frigate/config/model_cache/yolo.xml
sudo cp -f yolov9-m-640.bin /mnt/data/frigate/config/model_cache/yolo.bin
```

Das OpenVino Format benötigen wir nicht wirklich. OpenVino funktioniert in der Regel besser, wenn man es ohne GPU, also nur auf der CPU ausführen möchte. 

## 6. Frigate konfigurieren

Erstelle die Hauptkonfiguration:

```bash
sudo tee /mnt/data/frigate/config/config.yaml << 'EOF'
# MQTT für Home Assistant Integration
mqtt:
  enabled: true
  host: 192.168.178.205
  port: 1883
  topic_prefix: frigate
  client_id: frigate
  user: frigate
  password: DEIN_MQTT_PASSWORT

# GPU-Detektoren konfigurieren
# Ich nutze 3 parallele Detektoren, die alle auf der GPU laufen.
detectors:
  onnx0:
    type: onnx
    device: GPU
  onnx1:
    type: onnx
    device: GPU
  onnx2:
    type: onnx
    device: GPU
# OpenVino kannst du wie folgt nutzen:
  #  type: openvino
  #  device: CPU

# YOLOv9-Modell konfigurieren
model:
  model_type: yolo-generic
  width: 640  # Muss mit IMG_SIZE übereinstimmen
  height: 640
  input_tensor: nchw
  input_dtype: float
  path: /config/model_cache/yolo.onnx
  labelmap_path: /labelmap/coco-80.txt

# FFmpeg Hardware-Beschleunigung (für Video Dekodierung mit GPU)
ffmpeg:
  retry_interval: 10
  hwaccel_args: preset-nvidia

# Objekterkennung aktivieren
detect:
  enabled: true
  # wie oft pro Sekunde die Bilderkennung durchgeführt wird (häufigere Inteferenzen belasten GPU mehr)
  fps: 10

# Zu trackende Objekte. Vorsicht: Nicht jedes Modell ist für alle Objekte trainiert.
# Hier sind die Klassen, die Yolo trainiert: https://github.com/ultralytics/ultralytics/blob/main/ultralytics/cfg/datasets/coco.yaml
objects:
  track:
    - person
    - car
    - bicycle
    - motorcycle
    - cat
    - dog

# Komischer Videostream, der immer aktuelle Ereignisse von anderen Kameras darstellt.
# Siehe Frigate Doku, wenn du das nutzen möchtest: https://docs.frigate.video/configuration/birdseye
birdseye:
  enabled: false

# Review-System für Ereignisse
review:
  alerts:
    enabled: true
    labels:
      - person
      - car
      - bicycle
      - motorcycle
      - cat
      - dog
  detections:
    enabled: true

# Aufnahme-Einstellungen
record:
  enabled: true
  # Anzahl der Minuten zwischen Aufräum-Intervallen.
  expire_interval: 5
  retain:
    days: 3
    mode: all
  alerts:
    pre_capture: 10
    post_capture: 10
    retain:
      # Alle Alarme für 30 Tage aufzeichnen
      days: 30
      mode: all
  detections:
    pre_capture: 10
    post_capture: 10
    retain:
      # Alle erkannten Objekte für 30 Tage aufzeichnen
      days: 30
      mode: all
  # Neu in Frigate 17?
  continuous:
    days: 30
  motion:
    days: 30

# Mit go2rtc kannst du Videostreams in rtsp Streams rekodieren. Frigate kann nur rtsp Streams verarbeiten.
# Die meisten Kameras stellen bereits einen rtsp Stream bereit, manchmal aber auch nur mjpg. In dem Fall
# Kannst du ein rtsp Stream aus dem mjpg Stream erzeugen:
go2rtc:
  streams:
    # erzeuge den rtsp Stream: rtsp://127.0.0.1:8554/achim-carport-alt
    achim-carport-alt:
      ffmpeg:http://user:pass@192.168.0.23/mjpg/video.mjpg#video=h264#hardware

# Kameras konfigurieren

cameras:
  oyten-eingang:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.178.233:88/videoMain
          roles:
            - detect
            - record

  oyten-treppe:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.178.230:88/videoMain
          roles:
            - detect
            - record

  oyten-remise:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.178.231:88/videoMain
          roles:
            - detect
            - record

  oyten-parkplatz:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.178.237:88/videoMain
          roles:
            - detect
            - record

  achim-haupteingang:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.0.21:88/videoMain
          roles:
            - detect
            - record

  # Kamerastream, der zuvor mit go2rtc konvertiert wurde
  achim-carport:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/achim-carport-alt
          roles:
            - detect
            - record

  # Hühnerkamera Stream wird in separatem Docker-Container erstellt.
  # Hier braucht auch keine Objektinferenz stattfinden. 
  chickens:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://chickencam:8554/live
          roles: []

  # Kamera Oyten-Halle ist derzeit deaktiviert:
  oyten-halle:
    enabled: false
    ffmpeg:
      inputs:
        - path: rtsp://user:pass@192.168.178.154:88/videoMain
          roles:
            - detect

# TLS (HTTPS) Deaktivieren
tls:
  enabled: false

# Für welche Frigate Version wurde die Konfiguration erstellt?
version: 0.17-0
EOF
```

{{< notice tip >}}
**Kamera hinzufügen:** Passe den `cameras`-Bereich an deine eigenen Kameras an. Du kannst beliebig viele Kameras hinzufügen, indem du den Block kopierst und anpasst. 

Seit Frigate 17 kann man Kameras auch direkt in der Weboberfläche hinzufügen. In dem Fall braucht man hier
in der Konfigurationsdatei die gar nicht hinzufügen.
{{< /notice >}}

## 7. Frigate starten

Starte Frigate mit Docker Compose:

```bash
docker compose -f /mnt/data/frigate/docker-compose.yml up -d

# Überprüfe die Logs mit 
docker compose -f /mnt/data/frigate/docker-compose.yml logs -tf
```

## 8. Webinterface aufrufen

Öffne deinen Browser und navigiere zu:

```text
http://DEINE-SERVER-IP:5000
```

Du solltest nun das Frigate-Webinterface sehen und deine Kamerastreams mit Live-Objekterkennung betrachten können.

![Frigate Oberfläche](frigate-ui.png)

## Performance-Tipps

1. **Detektoren skalieren:** Erhöhe die Anzahl der Detektoren (`onnx0`, `onnx1`, ...), wenn du viele Kameras hast
2. **Optimiere Bewegungserkennung**: Frigate lässt die Objekterkennung immer nur dann laufen, wenn Bewegung erkannt wird. Daher ist eine funktionierende Bewegungserfassung wichtig. Passe Bewegungsschwellwerte in der Oberfläche an. 
3. **Zones nutzen:** Definiere Zonen in Kameras, um nur relevante Bereiche zu überwachen. Nutze insbesondere Bewegungsmasken um sich im Wind bewegende Bäume/Büsche auszumaskieren. Nutze Objektmasken um Objekte auszumaskieren, die dich nicht interessieren, beispielsweise Fahrzeuge auf öffentlichen Straßen.
4. **Detect FPS reduzieren:** Reduziere `detect.fps: 5`, wenn du viele Kameras hast, auf denen gleichzeitig Bewegung erkannt wird und daher die GPU (oder CPU) zu stark belastet wird. Du kannst auch ein kleineres Modell ausprobieren.
5. **Ungeschützter Port:** Der Port 5000 ist ungeschützt. Richte einen Benutzer mit Passwort ein und nutze zukünftig den geschützten Port 8971. Vergiss nicht den Port 5000 aus der docker-compose.yml zu entfernen.

![Frigate Zonenkonfiguration](frigate-zones.png)

## Fazit

Mit Frigate und GPU-Beschleunigung hast du nun ein leistungsstarkes, KI-gestütztes Überwachungssystem. Die Objekterkennung läuft in Echtzeit und du kannst beliebig viele Kameras anbinden.

Die Integration mit Home Assistant über MQTT ermöglicht zudem smarte Automationen basierend auf erkannten Objekten. 

## Weiterführende Links

- [Frigate Dokumentation](https://docs.frigate.video/)
- [YOLOv9 GitHub](https://github.com/WongKinYiu/yolov9)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
