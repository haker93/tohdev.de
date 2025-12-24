# TohDev - Hugo Blog

Ein Blog mit Hugo und GitHub Pages, gebaut mit PaperMod Theme. Wird gehostet unter [tohdev.de](https://tohdev.de/).

## 📋 Voraussetzungen

- Docker & Docker Compose installiert
- Visual Studio Code (optional, aber empfohlen)

## 💻 Entwicklung

### Entwicklungsserver starten

**Mit VS Code:**

Drücke `F5` oder starte die "Hugo Dev Server" Launch-Konfiguration. Der Container startet automatisch und öffnet den Browser.

**Manuell:**

```bash
docker-compose up
```

Die Website ist dann unter http://localhost:1313 erreichbar und lädt bei Änderungen automatisch neu.

### Neuen Artikel erstellen

```bash
docker-compose run --rm hugo-dev hugo new posts/mein-neuer-artikel.md
```

Die Datei wird unter `content/posts/mein-neuer-artikel.md` erstellt.

### Draft-Status entfernen

Öffne den Artikel und setze `draft: false`, damit er veröffentlicht wird.

## 🚀 Deployment

Das Deployment erfolgt automatisch über GitHub Actions:

1. Push zu `master` Branch
2. GitHub Actions baut die Website mit Hugo
3. Deployment zu GitHub Pages
4. Website ist unter https://tohdev.de erreichbar

Siehe [.github/workflows/deploy.yml](.github/workflows/deploy.yml) für Details.
