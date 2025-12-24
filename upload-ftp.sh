#!/bin/bash

# FTP Upload Script für Hetzner
# Dieses Script lädt die gebaute Hugo-Website per FTP zu Hetzner hoch

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TohDev FTP Upload Script ===${NC}"

# Prüfe ob credentials file existiert
if [ ! -f "ftp-credentials.env" ]; then
    echo -e "${RED}Fehler: ftp-credentials.env nicht gefunden!${NC}"
    echo -e "${YELLOW}Kopiere ftp-credentials.env.example zu ftp-credentials.env und fülle die Werte aus.${NC}"
    exit 1
fi

# Lade FTP Credentials
source ftp-credentials.env

# Prüfe ob public/ Verzeichnis existiert
if [ ! -d "public" ]; then
    echo -e "${RED}Fehler: public/ Verzeichnis nicht gefunden!${NC}"
    echo -e "${YELLOW}Bitte erst 'docker-compose run hugo-build' ausführen.${NC}"
    exit 1
fi

echo -e "${GREEN}1. Baue Hugo Site...${NC}"
docker-compose run --rm hugo-build

echo -e "${GREEN}2. Lade Dateien per FTP hoch...${NC}"

# Verwende lftp für effizienten Upload
docker run --rm -v "$(pwd)/public:/local" \
  -e "FTP_HOST=$FTP_HOST" \
  -e "FTP_USER=$FTP_USER" \
  -e "FTP_PASS=$FTP_PASS" \
  -e "FTP_REMOTE_DIR=$FTP_REMOTE_DIR" \
  alpine:latest sh -c '
    apk add --no-cache lftp
    lftp -c "
      set ssl:verify-certificate no;
      open -u $FTP_USER,$FTP_PASS $FTP_HOST;
      mirror -Rev /local $FTP_REMOTE_DIR --verbose --delete;
      bye
    "
  '

echo -e "${GREEN}✓ Upload erfolgreich abgeschlossen!${NC}"
echo -e "${GREEN}✓ Website sollte jetzt unter https://tohdev.de erreichbar sein${NC}"
