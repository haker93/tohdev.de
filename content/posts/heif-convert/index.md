---
title: "HEIF Bilder massenweise in JPG konvertieren"
date: 2026-01-06T17:49:00Z
draft: false
tags: []
categories: []
author: "Tobias"
description: "Anleitung zur Konvertierung aller HEIC und HEIF Bilder in JPG"
---

Neuere Kameras speichern Fotos im HEIC Format (High Efficiency Image Container). Ältere Geräte können die Bilder aber nicht anzeigen. Mit folgenden Kommandos lassen sich die Bilder schnell konvertieren.

## HEIC Fotos Konvertieren

```bash
# Starte einen Dockercontainer und mappe das Zielverzeichnis 
docker run --rm -it -v "/mnt/media/Bilder":/img ubuntu bash

# Installiere heif-convert, was im Paket libheif-examples enthalten ist
apt update
apt install -y libheif-examples

# Konvertiere alle heif/heic files zu jpg
find /img -type f -iname "*.hei[cf]" -print0 | while IFS= read -r -d '' file; do heif-convert "$file" "${file%.*}.JPG"; done
```

## Parallelisierung

Wenn man viele Bilder hat und viele Cores, kann man das auch mit `xargs` parallelisieren. Beachte, dass das Konvertieren sehr CPU-intensiv ist.

```bash
CPU_CORES=$(nproc)
find /img -type f -iname "*.hei[cf]" -print0 | xargs --null --max-args 1 --max-procs $CPU_CORES -I {} $(command -v bash) -c 'heif-convert "$1" "${1%.*}.JPG"' _ {}
```