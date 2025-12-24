@echo off
REM FTP Upload Script für Windows
REM Dieses Script lädt die gebaute Hugo-Website per FTP zu Hetzner hoch

echo === TohDev FTP Upload Script ===
echo.

REM Prüfe ob credentials file existiert
if not exist "ftp-credentials.env" (
    echo Fehler: ftp-credentials.env nicht gefunden!
    echo Kopiere ftp-credentials.env.example zu ftp-credentials.env und fülle die Werte aus.
    exit /b 1
)

REM Lade FTP Credentials
for /f "tokens=1,2 delims==" %%a in (ftp-credentials.env) do (
    if "%%a"=="FTP_HOST" set FTP_HOST=%%b
    if "%%a"=="FTP_USER" set FTP_USER=%%b
    if "%%a"=="FTP_PASS" set FTP_PASS=%%b
    if "%%a"=="FTP_REMOTE_DIR" set FTP_REMOTE_DIR=%%b
)

REM Prüfe ob public/ Verzeichnis existiert
if not exist "public\" (
    echo Fehler: public\ Verzeichnis nicht gefunden!
    echo Bitte erst 'docker-compose run hugo-build' ausführen.
    exit /b 1
)

echo 1. Baue Hugo Site...
docker-compose run --rm hugo-build
if errorlevel 1 (
    echo Fehler beim Hugo Build!
    exit /b 1
)

echo.
echo 2. Lade Dateien per FTP hoch...

REM Verwende Docker mit lftp für effizienten Upload
docker run --rm -v "%cd%/public:/local" ^
  -e "FTP_HOST=%FTP_HOST%" ^
  -e "FTP_USER=%FTP_USER%" ^
  -e "FTP_PASS=%FTP_PASS%" ^
  -e "FTP_REMOTE_DIR=%FTP_REMOTE_DIR%" ^
  alpine:latest sh -c "apk add --no-cache lftp && lftp -c 'set ssl:verify-certificate no; open -u $FTP_USER,$FTP_PASS $FTP_HOST; mirror -Rev /local $FTP_REMOTE_DIR --verbose --delete; bye'"

if errorlevel 1 (
    echo Fehler beim FTP Upload!
    exit /b 1
)

echo.
echo Upload erfolgreich abgeschlossen!
echo Website sollte jetzt unter https://tohdev.de erreichbar sein
pause
