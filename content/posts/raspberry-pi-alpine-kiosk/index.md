---
title: "Raspberry Pi als HMI mit Alpine Linux"
date: 2025-12-23
draft: false
tags: ["raspberry-pi", "alpine", "kiosk", "hmi", "embedded", "linux"]
categories: ["Embedded", "Tutorial", "Hardware"]
author: "Tobias"
description: "Einrichtung eines Raspberry Pi mit Alpine Linux als schnellen Kiosk für HMI-Anwendungen."
cover:
    image: "raspberry-pi-kiosk-dashboard.svg"
    alt: "Raspberry Pi Kiosk mit Home Assistant Dashboard"
    caption: "Raspberry Pi als HMI-Kiosk mit Alpine Linux"
    relative: false
---

# Raspberry Pi als HMI-Kiosk mit Alpine Linux

In diesem Artikel zeige ich, wie du einen Raspberry Pi mit Alpine Linux als Chromium-Kiosk-System einrichtest.

## Warum Alpine Linux?

Alpine Linux bietet mehrere Vorteile:

- **Schneller Boot**: Im Vergleich zu [FullPageOS](https://github.com/guysoft/FullPageOS) benötigt es nur etwa die Hälfte der Zeit, bis die Website angezeigt wird. Der Raspberry Pi 4 braucht ca. 35 Sekunden.
- **Kleiner Footprint**: Nur ~1 GB installierte Größe. Eine 2 GB SD-Karte reicht aus.
- **Sicherheit**: Kleinere Angriffsfläche durch minimale Installation.
- **Stabilität**: Alpine unterstützt einen Read-Only-Modus, wodurch es robust gegen unsauberes Herunterfahren (z.B. Stromausfall) ist.

## Hardware & Vorbereitung

**Benötigte Hardware:**
- Raspberry Pi 3 oder neuer (mit mindestens 1 GB RAM)
- SD-Karte mit mindestens 2 GB Kapazität

Ich habe die Einrichtung mit einem Raspberry Pi 3B und Raspberry Pi 4 getestet. Der Pi 4 ist dabei um ~10 Sekunden schneller.

**Alpine Linux Installation:**

1. [Raspberry Pi Imager](https://www.raspberrypi.com/software/) installieren und starten
2. Raspberry Pi-Modell auswählen
3. Alpine Linux auswählen (zu finden unter "Other General Purpose OS")
   
   Idealerweise solltest du die 64-bit-Variante auswählen. Allerdings ist diese auf dem Pi 3B relativ instabil. Chromium stürzt beim Aufstarten mehrmals ab, bis es dann endlich läuft. Beim Pi 3B würde ich daher zur 32-bit-Version raten.
4. Auf SD-Karte schreiben und in den Pi einlegen
5. Raspberry Pi starten (Tastatur und Bildschirm anschließen)

## Grundinstallation

Nach dem ersten Boot als `root` anmelden (es ist kein Passwort erforderlich).

Gib Folgendes ein, um die Einrichtung zu starten:

```bash
setup-alpine
```

Ich konfiguriere dann die Installation wie folgt:

```text
Keymap: de
Variant: de
System Name: kamin

Interface: eth0
  IP-Adresse: 192.168.178.204
  Subnet: 255.255.255.0
  Gateway: 192.168.178.1

DNS Domain Name: local
DNS Server: 192.168.178.1

Timezone: Europe/Berlin
Proxy: none (Default)
NTP Client: busybox (Default)
APK Mirror: 1 (Default)
Setup a user: n (Default, wir richten später einen ein) 
SSH Server: openssh (Default)
Allow Root Login: yes
Installationtyp: sys (auf /dev/mmcblk0)
```


{{< notice tip >}}
 - **Statische IP**: Eine statische IP ist vorteilhaft, da keine IP-Adresse per DHCP bezogen werden muss, was Zeit beim Hochfahren spart.
 - **Reboot:** Nach Abschluss des Setups empfiehlt Alpine einen Reboot. Das RAM-System kann jedoch noch genutzt werden, um weitere Änderungen vorzunehmen.
 - **SSH**: Nach dem Setup passt Alpine auch die Netzwerkeinstellungen des RAM-Systems an. Ab jetzt kann die Einrichtung per SSH fortgesetzt werden.
{{< /notice >}}


### Partition optimieren

Standardmäßig partitioniert Alpine die SD-Karte vollständig und erstellt ein Dateisystem in maximaler Größe. Das ist aber nicht optimal für Backups – eine kleinere Partition mit unfragmentiertem Dateisystem ist hier vorteilhafter.

Bevor wir rebooten, verkleinern wir daher das Dateisystem und die Partition. 

```bash
# Die e2fs Tools werden nur temporär im RAM installiert und sind nach dem Reboot nicht mit im System.
apk add e2fsprogs-extra

# Dateisystem Checken (resize2fs verweigert sonst seine Arbeit)
e2fsck -f /dev/mmcblk0p2

# Dateisystem auf 1 GB verkleinern
resize2fs /dev/mmcblk0p2 1G

# Finde die Blocksize und den Blockcount heraus
dumpe2fs -h /dev/mmcblk0p2

# Partition mit fdisk anpassen
fdisk /dev/mmcblk0

# 1. Partitionen mit p anzeigen
# 2. Startsektor der Partition 2 notieren
# 3. Partition 2 mit d löschen
# 4. Neue primäre Partition 2 mit n erstellen
# 5. Startsektor aus Schritt 2 eingeben
# 6. Endsektor eingeben
#
# Üblicherweise beträgt die Blockgröße bei ext4 4096 Bytes.
# fdisk rechnet jedoch in Sektoren, die jeweils 512 Bytes groß sind.
# Für eine 1 GB große Partition ist folgende Rechnung erforderlich:
# 
# Bei 1 GB Dateisystemgröße und Blockgröße von 4096 haben wir einen Block Count: 262144
# Pro Block werden 8 Sektoren benötigt (8*512=4096)
# Der Endsektor von Partition 2 muss also auf +2097152 gesetzt werden (8 * 262144)
# Alternativ könnte auch einfach +1G eingegeben werden, damit fdisk die Berechnung übernimmt.

# Nun das System neu starten
reboot
```

## Der erste Boot

Alpine ist nicht so umfangreich vorkonfiguriert wie Raspbian. Daher müssen einige Anpassungen manuell vorgenommen werden.

### 1. Bootkonfiguration

Bearbeite `/boot/config.txt` für maximale Performance:

```bash
vi /boot/config.txt
```

Füge hinzu:

```ini
########################################
# Hardware
########################################
# Nicht benötigte Hardware deaktivieren
dtoverlay=disable-wifi
dtoverlay=disable-bt
dtparam=audio=off
#
# CPU mit maximaler von der Firmware erlaubter Geschwindigkeit betreiben
arm_boost=1
#
########################################
# LEDs
########################################
#
# LEDs deaktivieren (spart Strom)
dtparam=pwr_led_trigger=none
dtparam=pwr_led_activelow=off
dtparam=act_led_trigger=none
dtparam=act_led_activelow=off
#
# Deaktivieren der Ethernet-LEDs funktioniert nur auf RPi 4
dtparam=eth_led0=14
dtparam=eth_led1=14
#
########################################
# Video-Treiber
########################################
#
disable_overscan=1
disable_splash=1
camera_auto_detect=0
max_framebuffers=2
#
disable_fw_kms_setup=1
#
# Tipp: Bei der 32-bit-Variante von Alpine funktioniert vc4-kms-v3d möglicherweise nicht. 
#       Falls nur ein schwarzer Bildschirm angezeigt wird, sollte stattdessen vc4-fkms-v3d verwendet werden.
dtoverlay=vc4-kms-v3d

```

### 2. MOTD anpassen 

Die nervig lange MOTD kann man wie folgt anpassen:

```bash
tee /etc/motd << 'EOF'
Welcome to Alpine!
EOF
```

### 3. Pakete installieren

```bash
# System-Updates und X11-Installation
apk update && apk upgrade

# Video-Treiber
apk add mesa-dri-gallium
apk add mesa-egl dbus kbd

# X11/XOrg
setup-xorg-base
apk add xf86-video-fbdev setxkbmap xrandr xset

# Chromium und VNC
apk add chromium x11vnc

# xdotool erlaubt das Simulieren von Tastendrücken. Beispiels F5 zum Aktualisieren der Website im Browser. 
apk add xdotool
```

### 4. Kiosk-Benutzer anlegen

```bash
adduser kiosk

# Den Benutzer zur Gruppe video und input hinzufügen
# Dadurch erhält er Zugriff auf die Ein- und Ausgabegeräte.
addgroup kiosk video
addgroup kiosk input

# Den Benutzer automatisch einloggen lassen
sed -i 's|^tty1::.*$|tty1::respawn:/bin/login -f kiosk|' /etc/inittab

# Profil einrichten, das für den Kiosk-Benutzer automatisch den X-Server startet
tee /home/kiosk/.profile << EOF
#!/bin/sh
# start X server
exec startx -- -nocursor
EOF
chmod u+x /home/kiosk/.profile
```

### 5. URL-Konfiguration

Die URL wird einfach im Heimverzeichnis des Kiosk-Benutzers abgelegt. Diese URL wird dann vom Browser
später aufgerufen.

```bash
tee /home/kiosk/url << 'EOF'
http://hmi/lan/hmi/
EOF
```

### 6. X-Session Konfiguration

Das Ziel ist es, lediglich Chromium im Kiosk-Modus zu starten. Zusätzlich wird der VNC-Server
im Hintergrund gestartet, um eine spätere Fernsteuerung zu ermöglichen.

```bash
tee /home/kiosk/.xinitrc << 'EOF'
#!/bin/sh

# turn off screensaver
xset -dpms
xset s off
xset s noblank

# screen size
width="1920"
height="1080"

# Je nach Auflösung:
# width="1280"
# height="720"

# URL laden
url=$(cat /home/kiosk/url)

# start VNC server in background
function vnc() {
  sleep 30
  x11vnc -display :0 -forever -shared -nopw
}

vnc &
VNC_PID=$!

chromium-browser $url \
  --window-size=$width,$height \
  --window-position=0,0 \
  --kiosk --no-sandbox  \
  --incognito \
  --noerrdialogs \
  --disable-translate \
  --no-first-run \
  --fast \
  --fast-start \
  --ignore-gpu-blacklist \
  --disable-quic \
  --enable-fast-unload \
  --enable-tcp-fast-open \
  --enable-native-gpu-memory-buffers \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --disable-infobars \
  --full-screen \
  --disable-web-security \
  --disk-cache-dir=/tmp \
  --enable-low-end-device-mode \

# Hinweis: --enable-low-end-device-mode kann weggelassen werden, wenn Bilder mit voller Farbtiefe 
# angezeigt werden sollen, da diese sonst möglicherweise nur mit 16-bit-Farbtiefe dargestellt werden.
# Bei zu hoher CPU-Last kann die Anzahl der Renderer-Prozesse reduziert werden:
# --renderer-process-limit=1

# Signale abfangen und VNC bei Beendigung stoppen
cleanup() {
  echo "Stopping Kiosk Server"
  kill -9 $VNC_PID 2>/dev/null
  wait $VNC_PID 2>/dev/null
}

trap cleanup EXIT INT TERM

EOF
chmod u+x /home/kiosk/.xinitrc
```

Abschließend alle Dateien im Heimverzeichnis dem Kiosk-Benutzer zuweisen:

```bash
chown -R kiosk:kiosk /home/kiosk
```

### 7. URL-Monitoring und Auto-Refresh

Dieser Service überwacht die URL und aktualisiert den Browser automatisch, sobald die Website unter der konfigurierten URL verfügbar wird:

```bash
tee /usr/local/bin/kiosk-url-monitor << 'EOF'
#!/bin/sh

URL_FILE="/home/kiosk/url"
CHECK_INTERVAL=5

test_url() {
  url=$(cat "$URL_FILE" 2>/dev/null)
  if [ -z "$url" ]; then
    return 1
  fi
  wget --spider --timeout=5 --tries=1 -q "$url" 2>/dev/null
  return $?
}

refresh_browser() {
  DISPLAY=:0 xdotool key F5
}

# Track previous state (0=available, 1=unavailable)
prev_state=1

while true; do
  if test_url; then
    # URL is available
    if [ "$prev_state" -eq 1 ]; then
      # State changed from unavailable to available
      sleep 2  # Brief delay before refresh
      refresh_browser
    fi
    prev_state=0
  else
    # URL is unavailable
    prev_state=1
  fi
  
  sleep "$CHECK_INTERVAL"
done
EOF

chmod +x /usr/local/bin/kiosk-url-monitor
```

**OpenRC Service erstellen:**

```bash
tee /etc/init.d/kiosk-url-monitor << 'EOF'
#!/sbin/openrc-run

name="Kiosk URL Monitor"
description="Monitors URL availability and refreshes browser when it becomes available"

supervisor="supervise-daemon"
command="/usr/local/bin/kiosk-url-monitor"
command_user="kiosk:kiosk"
command_background="yes"
pidfile="/run/kiosk-url-monitor.pid"

depend() {
    need net
}

start_pre() {
    # Ensure xdotool is installed
    if ! command -v xdotool >/dev/null 2>&1; then
        eerror "xdotool is not installed. Install with: apk add xdotool"
        return 1
    fi
    
    # Ensure URL file exists
    if [ ! -f /home/kiosk/url ]; then
        eerror "URL file /home/kiosk/url does not exist"
        return 1
    fi
}
EOF

chmod +x /etc/init.d/kiosk-url-monitor
rc-update add kiosk-url-monitor default
rc-service kiosk-url-monitor start
```

### 8. Regelmäßiger Refresh

Browser-Seite alle 15 Minuten aktualisieren:

```bash
tee /etc/crontabs/kiosk << 'EOF'
*/15 * * * * DISPLAY=:0 xdotool key F5
EOF
```

### 9. Read-Only Filesystem

Für maximale Stabilität und Langlebigkeit der SD-Karte wird ein Read-Only-Overlay-Dateisystem verwendet. 

{{< notice tip >}}
SD-Karten, die nur gelesen werden, haben eine nahezu unbegrenzte Lebensdauer. 

Zusätzlich: Da nie auf den Datenträger geschrieben wird, kann das Dateisystem durch eventuelle Stromausfälle nicht beschädigt werden. 
{{< /notice >}}

Wir erstellen zwei Skripte, um das System zwischen Read-Only- und beschreibbarem Modus umzuschalten. Beachte, dass dafür immer ein Neustart erforderlich ist.

```bash
tee /usr/bin/make-ro << 'EOF'
#!/bin/sh
set -e
mount /boot -o rw,remount
sed -i '/overlaytmpfs=/! s/$/ overlaytmpfs=yes/; s/\(overlaytmpfs=\)[^ ]*/\1yes/' /boot/cmdline.txt
sed -i '/overlaytmpfsflags=/! s/$/ overlaytmpfsflags=size=500M/; s/\(overlaytmpfsflags=\)[^ ]*/\1size=500M/' /boot/cmdline.txt
reboot
EOF

tee /usr/bin/make-rw << 'EOF'
#!/bin/sh
set -e
mount /boot -o rw,remount
sed -i '/overlaytmpfs=/! s/$/ overlaytmpfs=no/; s/\(overlaytmpfs=\)[^ ]*/\1no/' /boot/cmdline.txt
reboot
EOF

# Ausführrechte setzen
chmod +x /usr/bin/make-ro /usr/bin/make-rw

# Read-Only aktivieren
/usr/bin/make-ro
```

{{< notice info >}}
Im Read-Only-Modus gilt:
- Änderungen im Dateisystem gehen beim Neustart verloren
- Mit `make-rw` in einen beschreibbaren Modus booten (für dauerhafte Änderungen)
- Nach Änderungen wieder `make-ro` ausführen
{{< /notice >}}


## Fazit

Mit Alpine Linux als Basis werden folgende Vorteile erreicht:

✅ **35 Sekunden Boot-Zeit** - 30 % schneller als mit Raspbian oder FullPageOS  
✅ **Minimales System** - nur ~1 GB auf der SD-Karte  
✅ **Read-Only-Dateisystem** - maximale Stabilität und SD-Karten-Langlebigkeit  
✅ **VNC-Zugriff** - einfaches Remote-Debugging  
✅ **Auto-Refresh** - regelmäßige Aktualisierung der Website im Browser  

Die Lösung eignet sich perfekt für HMI-Anwendungen, bei denen schneller Boot, Stabilität und minimaler Wartungsaufwand entscheidend sind.

