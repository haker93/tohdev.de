---
title: "Lokales LLM als Copilot-Alternative: llama-server + AI Chat in VS Code"
date: 2026-05-05T12:00:00Z
draft: false
tags: ["llm", "llama.cpp", "qwen", "continue", "vscode", "copilot-alternative", "lokal", "wsl2", "nvidia", "ki", "unsloth", "open code"]
categories: ["Tutorial", "DevTools"]
author: "Tobias"
description: "Wie ich einen lokalen llama-server mit Qwen3.6-27B aufgesetzt und über Continue.dev als kostenlosen GitHub Copilot Ersatz in VS Code eingebunden habe."
cover:
    image: "cover.svg"
    alt: "Lokaler LLM-Server mit llama.cpp, GPU-Beschleunigung und VS Code Integration"
    caption: "Lokaler LLM-Server einrichten – 100% lokal, keine Cloud"
    relative: false
---

GitHub Copilot kostet Geld, schickt deinen Code in die Cloud und wird ab Juni 2026 richtig teuer. Mit einer halbwegs modernen NVIDIA-GPU lässt sich das komplett lokal lösen. In diesem Artikel zeige ich, wie ich [llama.cpp](https://github.com/ggml-org/llama.cpp) als OpenAI-kompatibler API-Server nutze und ihn über die [Continue.dev](https://continue.dev)-Extension in VS Code sowie [Open Code](https://opencode.ai) als CLI-Tool eingebunden habe – vollständig kostenlos, ohne API-Key und ohne Datenweitergabe.

**Mein System:** Windows 11 | RTX 4090 (24 GB VRAM) | 64 GB DDR5 RAM | WSL2

## Voraussetzungen

- Windows 11 mit WSL2
- NVIDIA GPU (mindestens 8 GB VRAM empfohlen, ich nutze eine RTX 4090 mit 24 GB VRAM)
- VS Code

## 1. WSL2 einrichten

Das Modell läuft in einer separaten WSL2-Distribution. Öffne **PowerShell als Administrator**:

```powershell
# WSL2 als Standard aktivieren
wsl --install --no-distribution

# Neustart erforderlich
Restart-Computer
```

Nach dem Neustart WSL2 als Standardversion verifizieren:

```powershell
wsl --set-default-version 2
wsl --version
```

### 1.1 Separate Distribution erstellen

Ich lege eine eigene Distribution mit dem Namen `unsloth` an, um sie sauber vom Rest zu trennen:

```powershell
wsl --install -d Ubuntu-24.04 --name unsloth
```

Es öffnet sich ein Terminal – dort Benutzername und Passwort vergeben. Danach das Fenster schließen und prüfen ob die Distribution korrekt angelegt wurde:

```powershell
wsl --list --verbose
```

Erwartete Ausgabe:

```plain
  NAME      STATE           VERSION
* unsloth   Stopped         2
```

### 1.2 Arbeitsspeicher-Limit anpassen

Windows limitiert WSL2 standardmäßig auf 50 % RAM. Für KI-Workloads brauchen wir mehr. Datei `C:\Users\WIN11\.wslconfig` erstellen oder bearbeiten:

```ini
[wsl2]
memory=56GB
processors=16
swap=32GB
swapFile=D:\\WSL\\swap.vhdx
localhostForwarding=true
```

Danach WSL neu starten:

```powershell
wsl --shutdown
wsl -d unsloth
```

### 1.3 DNS-Auflösung fixieren

WSL2 hat bei mir ein Problem mit `systemd-resolved`. Ohne diesen Fix schlägt `apt update` mit `Temporary failure in name resolution` fehl.

In der WSL2-Shell:

```bash
# Schritt 1: generateResolvConf deaktivieren
sudo tee -a /etc/wsl.conf << EOF

[network]
generateResolvConf = false
EOF

# Schritt 2: systemd-resolved deaktivieren
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Schritt 3: Zurück in der WSL2-Shell resolv.conf manuell setzen:
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf << EOF
nameserver 192.168.178.1
search fritz.box
EOF

# Schritt 4: Verbindung testen
ping -c 2 google.com
```

{{< notice tip >}}
`192.168.178.1` ist die IP des Fritzbox-Routers. Bei einem anderen Router entsprechend anpassen. `8.8.8.8` (Google DNS) funktioniert immer als Alternative.
{{< /notice >}}

### 1.4 Grundpakete installieren

```bash
sudo apt update && sudo apt dist-upgrade -y
sudo apt install -y build-essential git curl wget unzip htop nvtop ca-certificates
```

## 2. Unsloth installieren und Modell laden

[Unsloth](https://unsloth.ai) stellt eine einfache Web-Oberfläche bereit, mit der man GGUF-Modelle herunterladen und testen kann. Die Installation läuft über ein offizielles Skript:

```bash
curl -fsSL https://unsloth.ai/install.sh | sh
```

Die Installation dauert ca. 1–2 Minuten. Danach WSL neu starten:

```powershell
wsl --shutdown
wsl -d unsloth
```

Unsloth Studio starten:

```bash
unsloth studio -H 0.0.0.0 -p 8888
```

Dann im Browser `http://localhost:8888` öffnen. Über die Oberfläche das gewünschte Modell herunterladen – ich nutze **Qwen3.6-27B**.

### 2.1 Modell- und Quantwahl

Qwen3.6-27B ist im GGUF-Format in verschiedenen Quantisierungsstufen verfügbar. Welche Quants bei 24 GB VRAM passen (inklusive KV-Cache in q8_0):

| Quant        | KV Cache | Kontextgröße (max) | Kontextgröße (empfohlen) |
|--------------|----------|--------------------|--------------------------|
| UD-Q2_K_XL   | q8_0     | 262144             | 262144                   |
| UD-Q3_K_XL   | q8_0     | 190720             | 150528                   |
| UD-Q4_K_XL   | q8_0     | 119552             | 98304                    |
| UD-Q5_K_XL   | q8_0     | 55040              | 45056                    |
| UD-Q2_K_XL   | f16      | 152064             | 123904                   |
| UD-Q3_K_XL   | f16      | 112128             | 91136                    |
| UD-Q4_K_XL   | f16      | 64768              | 52224                    |
| UD-Q5_K_XL   | f16      | 28416              | 22528                    |

Ich nutze **UD-Q4_K_XL** mit 98304 Token Kontext – das ist ein guter Kompromiss. Das Modell läuft dann komplett im VRAM und erreicht ca. **45 Token/s** bei der Generierung und **1500 Token/s** beim Verarbeiten des Kontexts. Der Stromverbrauch beträgt dabei ca. 350 W.

{{< notice tip >}}
Wenn Layer in den RAM ausgelagert werden (weil das Modell nicht komplett in den VRAM passt), sinkt die Geschwindigkeit auf ca. 15 Token/s. Es lohnt sich also, einen Quant zu wählen, der vollständig in den VRAM passt.
{{< /notice >}}

{{< notice tip >}}
Mit `uvx hf` lässt sich auch die Huggingface CLI direkt nutzen, um weitere Modelle zu laden. Für schnelles Ausprobieren ist aber Unsloth Studio meist komfortabler.

`llama-server` kennt auch das Argument `-hf`, mit dem direkt Modelle von Huggingface genutzt werden können.
{{< /notice >}}

## 3. llama.cpp bauen

llama.cpp ist die empfohlene Inference-Engine für GGUF-Modelle – stabil, GPU-beschleunigt und OpenAI-API-kompatibel. Unsloth nutzt llama.cpp intern selbst. Wir bauen es separat, damit wir den Port und alle Parameter selbst kontrollieren können.

### 3.1 CUDA Toolkit installieren

Das Unsloth-Installationsskript richtet CUDA nur für Python ein. `cmake` benötigt zusätzlich das systemweite CUDA Toolkit (`nvcc` + Header). Wir installieren CUDA **13.1** per Runfile.

{{< notice warning >}}
Nutze nicht CUDA 13.2 – diese Version enthält Bugs, die bei stark quantisierten Modellen zu kryptischem oder gibberish Output führen, insbesondere in Verbindung mit Compiler-Optimierung `-O3`. Mehr dazu auf [Reddit](https://www.reddit.com/r/unsloth/comments/1sgl0wh/do_not_use_cuda_132_to_run_models/).
{{< /notice >}}

```bash
# Build-Tools installieren
sudo apt-get install -y pciutils build-essential cmake curl libcurl4-openssl-dev

# CUDA 13.1 Runfile herunterladen
cd ~
wget https://developer.download.nvidia.com/compute/cuda/13.1.2/local_installers/cuda_13.1.2_590.48.01_linux.run

# Installieren
sudo sh cuda_13.1.2_590.48.01_linux.run
# → "accept" eingeben, Haken bei Dokumentation entfernen, dann "install" auswählen
```

Umgebungsvariablen setzen und WSL neu starten:

```bash
echo 'export PATH=/usr/local/cuda-13.1/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
```

```powershell
wsl --shutdown
wsl -d unsloth
```

Installation verifizieren:

```bash
nvcc --version
```

Erwartete Ausgabe:

```plain
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2025 NVIDIA Corporation
Built on ...
Cuda compilation tools, release 13.1, V13.1.x
```

### 3.2 llama.cpp kompilieren

```bash
cd ~
git clone https://github.com/ggml-org/llama.cpp

# Mit CUDA-Unterstützung bauen (-DGGML_CUDA=ON für GPU-Beschleunigung)
cmake llama.cpp -B llama.cpp/build \
    -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=ON

cmake --build llama.cpp/build --config Release -j --clean-first \
    --target llama-cli llama-server

# Binaries ins llama.cpp-Verzeichnis kopieren
cp llama.cpp/build/bin/llama-* llama.cpp
```

Der Build dauert je nach CPU ein paar Minuten. Danach verifizieren:

```bash
~/llama.cpp/llama-server --version
```

## 4. llama-server starten

`llama-server` stellt eine **OpenAI-kompatible REST-API** bereit – direkt nutzbar für Continue.dev, Open Code und andere Tools. In einem WSL2-Terminal ausführen (Terminal-Tab offen lassen, solange der Server laufen soll):

```bash
~/llama.cpp/llama-server \
    --model $(find ~ -name "Qwen3.6-27B-UD-Q4_K_XL.gguf" | head -1) \
    --mmproj $(find ~ -path "*Qwen3.6-27B-GGUF*" -name "mmproj-BF16.gguf" | head -1) \
    --alias "unsloth/Qwen3.6-27B" \
    --ctx-size 98304 \
    --chat-template-kwargs "{\"enable_thinking\": true, \"preserve_thinking\":true}" \
    --reasoning on \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --flash-attn on \
    --gpu-layers -1 \
    --parallel 1 \
    --jinja \
    --port 8001 \
    --host 0.0.0.0 \
    --threads 16 \
    --batch-size 512 --ubatch-size 256 \
    --temp 0.2 --top-p 0.95 --min-p 0.00 --top-k 20 \
    --presence-penalty 0.0 --frequency-penalty 0.1 \
    --seed 3407
```

### 4.1 Parameter erklärt

**Technische Parameter:**

| Parameter | Wert | Erklärung |
|---|---|---|
| `--gpu-layers -1` | alle | Alle Layer in den VRAM laden – maximale Geschwindigkeit |
| `--flash-attn on` | on | Reduziert VRAM-Bedarf des KV-Caches spürbar |
| `--cache-type-k/v` | q8_0 | KV-Cache in 8-Bit – spart VRAM bei minimalem Qualitätsverlust |
| `--reasoning on` | on | Aktiviert `<think>`-Tags von Qwen3 (Chain-of-Thought) |
| `--parallel 1` | 1 | Nur eine gleichzeitige Anfrage – spart KV-Cache-Speicher |
| `--jinja` | – | Jinja-Rendering für Chat-Templates aktivieren |

**Inferenzparameter:**

| Parameter | Wert | Erklärung |
|---|---|---|
| `--temp` | 0.2 | Unsloth empfiehlt 0.6 – das ist für Coding viel zu hoch und führt zu häufigen Halluzinationen. Mit 0.2 verhält sich das Modell deutlich zuverlässiger. |
| `--top-p` | 0.95 | Von Unsloth empfohlen |
| `--top-k` | 20 | Von Unsloth empfohlen |
| `--min-p` | 0.00 | Von Unsloth empfohlen |
| `--presence-penalty` | 0.0 | Von Unsloth empfohlen |
| `--frequency-penalty` | 0.1 | Unsloth empfiehlt 1.0, ich hatte damit aber keine Probleme mit Looping – daher auf 0.1 gesenkt. |

Wenn der Server lädt, erscheint im Terminal u.a.:

```plain
llm_load_tensors: offloading 64 repeating layers to GPU
llm_load_tensors: offloaded 65/65 layers to GPU
...
main: server is listening on http://0.0.0.0:8001 - starting the main loop
```

### 4.2 API testen

```bash
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.6-27B",
    "messages": [{"role": "user", "content": "Write a Python hello world"}]
  }'
```

## 5. Networking: Zugriff aus dem LAN

WSL2 nutzt NAT. Dank `localhostForwarding=true` in der `.wslconfig` ist der llama-server unter Windows automatisch per `localhost:8001` erreichbar. Damit andere Geräte im LAN (z.B. ein zweiter Rechner mit VS Code) ebenfalls zugreifen können, brauchen wir eine Portweiterleitung. `192.168.178.115` ist dabei die LAN-IP meines Windows-Hosts – entsprechend anpassen.

Dazu einfach in PowerShell **als Administrator**:

```powershell
# llama.cpp (OpenAI API)
netsh interface portproxy add v4tov4 `
   listenport=8001 `
   listenaddress=192.168.178.115 `
   connectport=8001 `
   connectaddress=127.0.0.1

# Unsloth Studio
netsh interface portproxy add v4tov4 `
   listenport=8888 `
   listenaddress=192.168.178.115 `
   connectport=8888 `
   connectaddress=127.0.0.1
```

{{< notice warning >}}
Als `listenaddress` unbedingt die konkrete LAN-IP des Windows-Hosts angeben, **nicht** `0.0.0.0`. Wenn `0.0.0.0` genutzt wird, versucht der Portproxy auch `127.0.0.1` zu binden – und verhindert damit genau das Localhost-Forwarding von WSL, das wir nutzen wollen.
{{< /notice >}}

Anschließend noch eine eingehende Windows-Firewall-Regel anlegen. Das geht am einfachsten über die Firewall-UI (`Windows Defender Firewall mit erweiterter Sicherheit → Eingehende Regeln → Neue Regel`):

- Protocol: TCP
- Ports: 8001, 8888

## 6. Chat-Clients einrichten

Alle drei Tools verbinden sich über die OpenAI-kompatible API des llama-servers.

### 6.1 Qwen Code Companion

**Qwen Code Companion** ist die offizielle VS Code Extension von Alibaba. Von der Bedienung her ähnelt sie GitHub Copilot Chat am stärksten – besonders die Tool-Nutzung funktioniert hier sehr gut.

**Installation:** Extension `Qwen.qwen-coder` im VS Code Marketplace suchen und installieren.

Konfigurationsdatei `%USERPROFILE%\.qwen\settings.json` öffnen (ggf. erstellen):

```json
{
  "security": {
    "auth": {
      "selectedType": "openai"
    }
  },
  "env": {
    "OPENAI_API_KEY": "dummy"
  },
  "modelProviders": {
    "openai": [
      {
        "id": "qwen36-27b",
        "name": "qwen36-27b",
        "baseUrl": "http://192.168.178.115:8001/v1",
        "envKey": "OPENAI_API_KEY",
        "generationConfig": {
          "timeout": 300000,
          "maxRetries": 2,
          "contextWindowSize": 98304,
          "samplingParams": {
            "temperature": 0.2,
            "top_p": 0.95,
            "min_p": 0.00,
            "top_k": 20,
            "max_tokens": 8192,
            "presence_penalty": 0.0,
            "frequency_penalty": 0.1
          }
        }
      }
    ]
  },
  "model": {
    "name": "qwen36-27b"
  },
  "$version": 3
}
```

VS Code neu starten und den Chat mit `Strg+L` öffnen.

{{< notice tip >}}
Mit dem `/init`-Befehl lässt Qwen Companion die gesamte Codebase einmalig analysieren und legt eine `QWEN.md` mit allen wichtigen Projektdetails an – vergleichbar mit der `CLAUDE.md` bei Claude Code.
{{< /notice >}}

### 6.2 Continue.dev

[Continue](https://marketplace.visualstudio.com/items?itemName=Continue.continue) ist eine Open-Source VS Code Extension für KI-gestütztes Coding – Chat, Inline-Edits und Tab-Autocomplete in einem.

**Installation:** Extension `Continue.continue` im VS Code Marketplace suchen und installieren.

Konfigurationsdatei `%USERPROFILE%\.continue\config.yaml` öffnen:

```yaml
name: Local Config
version: 1.0.0
schema: v1
models:
  - name: Qwen3.6-27B (lokal)
    provider: openai
    model: unsloth/Qwen3.6-27B
    apiBase: http://192.168.178.115:8001/v1
    apiKey: dummy
    contextLength: 98304
    defaultCompletionOptions:
      temperature: 0.2
      topP: 0.95
      minP: 0.0
      topK: 20
      maxTokens: 8192
      presencePenalty: 0.0
      frequencyPenalty: 0.1
tabAutocomplete:
  - name: Qwen3.6-27B Autocomplete
    provider: openai
    model: unsloth/Qwen3.6-27B
    apiBase: http://192.168.178.115:8001/v1
    apiKey: dummy
```

{{< notice tip >}}
Das `apiKey`-Feld ist ein Pflichtfeld in Continue, wird vom lokalen llama-server aber nicht ausgewertet – ein beliebiger Wert wie `dummy` reicht aus.
{{< /notice >}}

VS Code neu starten. Shortcuts:

| Shortcut | Funktion |
|----------|----------|
| `Strg+L` | Chat öffnen (agentic, mit Dateikontext) |
| `Strg+I` | Inline-Edit im Editor |
| `Strg+Shift+R` | Tab-Autocomplete manuell triggern |

### 6.3 Open Code

[Open Code](https://opencode.ai) ist ein Agentic-Coding-CLI-Tool – vergleichbar mit Claude Code, aber vollständig mit lokalen Modellen. Es gibt auch einen Desktop-Client, der die Einrichtung vereinfacht.

**Installation:** Desktop-Client von [opencode.ai/de/download](https://opencode.ai/de/download) herunterladen und installieren.

Konfigurationsdatei `%USERPROFILE%\.config\opencode\opencode.jsonc` anpassen:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "lokal": {
      "name": "lokal",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://192.168.178.115:8001/v1"
      },
      "models": {
        "unsloth/Qwen3.6-27B": {
          "name": "Qwen3.6-27B",
          "limit": {
            "context": 98304,
            "output": 8192
          }
        }
      }
    }
  }
}
```

Nach dem Speichern Open Code einmal neu starten – erst dann erscheint der neue Provider in der Oberfläche.

## 7. Test-Prompts

Hier sind ein paar Prompts, mit denen ich das Modell teste. Man sieht deutliche Unterschiede im Verhalten, wenn die Temperatur z.B. auf 0.6 gestellt ist.

### 7.1 OAuth2 Client Beispiel

{{< prompt >}}Kannst du mir ein oauth2 Beispiel bauen in c#, ohne externe libs. Also einfach nur ein program.cs das eine api per client credential grant aufruft.{{< /prompt >}}

{{< prompt >}}Haufenweise key value pairs... Bitte nutze .net 10 und die coolen shortcuts. Dann kannst du diese ganzen new KeyValuePair&lt;string,string&gt; weglassen.

Bitte nutze die neusten c# language features{{< /prompt >}}

### 7.2 OpenIddict Knowledge

{{< prompt >}}Kennst du OpenIddict?{{< /prompt >}}

{{< prompt >}}Ich habe in meinem Projekt OpenIddict genutzt. Und zwar im degraded mode. Ich möchte nun, dass du den authorization code beim pkce grant kürzer machst. Speicher einfach den code in einem memory cache und ersetz den einfach mit einem reference code. Kannst du mir zeigen, wie man das konkret implementieren würde?{{< /prompt >}}

{{< prompt >}}Du brauchst Handler für ProcessSignInContext und ExtractTokenRequestContext.{{< /prompt >}}

### 7.3 WSL Networking

{{< prompt >}}Ich hab wsl und hoste einen http server da drin. Ich kann nun aber nicht von anderen Rechnern im LAN darauf zugreifen. Meine ip ist 192.168.178.115 und mein server unter port 8001 gehostet. Wenn ich per localhost von Windows aus draufgehe geht es. Aber selbst wenn ich http://192.168.178.115:8001 in Windows eingebe gehts schon nicht. Es geht auch nicht wenn ich das von anderen Rechnern im LAN aus aufrufe. Ne idee was man machn kann?{{< /prompt >}}

Eine gute Antwort erwähnt:
- Windows Firewall konfigurieren
- `netsh portproxy` mit `listenaddress=192.168.178.115` – **nicht** `0.0.0.0`, da das die WSL-Bindung stört
- `connectaddress=127.0.0.1`, weil Windows Ports dank `localhostForwarding=true` dort bindet
- Optional: `networkingMode=mirrored` als Alternative (Bei temp=0.6 halluziniert er den Parameter zu `networkMode=mirrored`)

## Fazit

Qwen3.6 27B ist beeindruckend. Es hält locker mit Claude Sonnet 4.5 mit und läuft dabei auf einfacher Consumer Hardware – vollständig lokal und kostenlos.

Der Einrichtungsaufwand ist einmalig hoch: WSL2, CUDA, llama.cpp bauen, Networking konfigurieren. Wer das einmal durchgezogen hat, bekommt dafür einen vollwertigen KI-Coding-Assistenten, der dauerhaft nichts kostet und keinen API-Key braucht.

Schwächen zeigen sich bei komplexen Mehrschrittaufgaben: Qwen neigt gelegentlich dazu, Syntaxfehler zu produzieren oder suboptimale Architekturentscheidungen zu treffen, bei denen Sonnet besser abschneiden würde. Außerdem ist er mit ~45 t/s spürbar langsamer als Claude.

Für den alltäglichen Einsatz im Homelab oder für datenschutzsensible Projekte ist das Setup aber klar empfehlenswert. Die Kombination aus Qwen Companion, Continue.dev und Open Code deckt praktisch jeden Anwendungsfall ab.