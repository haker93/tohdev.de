# TohDev - Hugo Blog mit Docker

Ein einfacher Entwickler-Blog, gebaut mit Hugo, Docker und deploybar per FTP zu Hetzner.

## 🚀 Features

- ✅ Hugo Static Site Generator
- ✅ PaperMod Theme
- ✅ Docker-basierte Entwicklung und Build
- ✅ Nginx-basiertes Production Image
- ✅ FTP-Upload zu Hetzner
- ✅ Deutsche Lokalisierung
- ✅ Syntax-Highlighting für Code
- ✅ Responsive Design

## 📋 Voraussetzungen

- Docker & Docker Compose installiert
- Git installiert (für Theme-Installation)

## 🛠️ Installation & Setup

### 1. Theme installieren

Beim ersten Start das Hugo-Theme installieren:

```bash
git init
git submodule add --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod
```

### 2. FTP-Credentials einrichten

Für den Upload zu Hetzner:

```bash
# Windows
copy ftp-credentials.env.example ftp-credentials.env

# Linux/Mac
cp ftp-credentials.env.example ftp-credentials.env
```

Dann `ftp-credentials.env` mit deinen Hetzner-Zugangsdaten bearbeiten:

```env
FTP_HOST=dein-server.hetzner.com
FTP_USER=dein-username
FTP_PASS=dein-passwort
FTP_REMOTE_DIR=/public_html
```

**⚠️ WICHTIG:** Diese Datei ist in `.gitignore` und wird NICHT ins Repository committed!

## 💻 Entwicklung

### Entwicklungsserver starten

```bash
docker-compose up hugo-dev
```

Die Website ist dann unter http://localhost:1313 erreichbar.

Der Server lädt automatisch neu, wenn du Änderungen machst.

### Neuen Artikel erstellen

```bash
docker-compose run --rm hugo-dev new posts/mein-neuer-artikel.md
```

Die Datei wird unter `content/posts/mein-neuer-artikel.md` erstellt.

### Draft-Status entfernen

Öffne den Artikel und setze `draft: false`, damit er veröffentlicht wird.

## 🏗️ Build

### Lokaler Build

```bash
docker-compose run --rm hugo-build
```

Die gebaute Website wird im `public/` Verzeichnis erstellt.

### Docker Image bauen

```bash
docker build -t tohdev-site .
```

### Docker Image lokal testen

```bash
docker-compose up tohdev-site
```

Die Website ist dann unter http://localhost:8080 erreichbar.

## 🚀 Deployment

### Per FTP zu Hetzner hochladen

**Windows:**
```cmd
upload-ftp.bat
```

**Linux/Mac:**
```bash
chmod +x upload-ftp.sh
./upload-ftp.sh
```

Das Script:
1. Baut die Hugo-Website neu
2. Lädt alle Dateien per FTP zu Hetzner hoch
3. Löscht alte Dateien auf dem Server (Mirror-Modus)

Nach dem Upload ist die Website unter https://tohdev.de erreichbar.

## 📁 Projektstruktur

```
tohdev/
├── content/              # Markdown-Inhalte
│   ├── posts/           # Blog-Artikel
│   └── about.md         # Über-Seite
├── themes/              # Hugo-Themes
│   └── PaperMod/       # PaperMod Theme (Git Submodule)
├── public/              # Generierte Website (nach Build)
├── archetypes/          # Templates für neue Inhalte
├── hugo.toml            # Hugo-Konfiguration
├── Dockerfile           # Multi-stage Docker Build
├── docker-compose.yml   # Docker Compose Services
├── nginx.conf           # Nginx-Konfiguration
├── upload-ftp.sh        # FTP-Upload (Linux/Mac)
├── upload-ftp.bat       # FTP-Upload (Windows)
└── ftp-credentials.env  # FTP-Credentials (nicht in Git!)
```

## 📝 Konfiguration anpassen

### Website-Einstellungen

Bearbeite [hugo.toml](hugo.toml):

- `baseURL`: Deine Domain
- `title`: Website-Titel
- `params`: Theme-Parameter
- `menu`: Navigation

### Theme anpassen

Das PaperMod Theme ist hochgradig anpassbar. Siehe [PaperMod-Dokumentation](https://github.com/adityatelange/hugo-PaperMod/wiki).

## 🔧 Nützliche Befehle

```bash
# Entwicklungsserver mit Draft-Artikeln
docker-compose up hugo-dev

# Build ohne Draft-Artikel
docker-compose run --rm hugo-build

# Neuen Post erstellen
docker-compose run --rm hugo-dev new posts/artikel-name.md

# Server aufräumen
docker-compose down

# Production Image bauen und starten
docker-compose up --build tohdev-site
```

## 📚 Weitere Ressourcen

- [Hugo-Dokumentation](https://gohugo.io/documentation/)
- [PaperMod Theme](https://github.com/adityatelange/hugo-PaperMod)
- [Markdown-Syntax](https://www.markdownguide.org/)

## 🤝 Lizenz

Dieses Projekt steht unter der MIT-Lizenz.

---

**Happy Blogging! 🎉**

Bei Fragen oder Problemen, erstelle ein Issue auf GitHub.
