# Unsloth + Qwen3.6 27B auf RTX 4090 – Vollständige Einrichtungsanleitung

**System:** Windows 11 | RTX 4090 | 64 GB DDR5 RAM | WSL2  
**Ziel:** Lokales LLM Inference mit Qwen3-27B via Unsloth + llama.cpp, genutzt in VS Code und Open Code

---

## Inhaltsverzeichnis

1. [WSL2 aktivieren](#1-wsl2-aktivieren)
2. [Separate WSL2-Distribution erstellen](#2-separate-wsl2-distribution-erstellen)
   - [2.1 Ubuntu 24.04 installieren](#21-ubuntu-2404-mit-eigenem-namen-installieren)
   - [2.2 Arbeitsspeicher-Limit setzen](#22-wsl2-arbeitsspeicher-limit-setzen)
   - [2.3 DNS-Auflösung fixieren](#23-dns-auflösung-in-wsl2-fixieren-pflicht)
   - [2.4 Grundpakete installieren](#24-grundpakete-installieren)
3. [Huggingface Cache auslagern](#3-huggingface-cache-auslagern)
4. [Unsloth installieren](#4-unsloth-installieren)
   - [4.1 Unsloth Kennwort](#41-unsloth-kennwort)
   - [4.2 Unsloth Studio](#42-unsloth-studio-starten-optionale-web-ui)
   - [4.3 Modell herunterladen](#43-unsloth-modell-runterladen-qwen36-27b-gguf)
   - [4.4 Kontextgrößen](#44-mögliche-kontextgrößen-bei-rtx-4090)
   - [4.5 Performance](#45-rtx-4090-performance)
   - [4.6 Inferenzparameter](#46-empfohlene-inferenzparameter)
5. [llama.cpp bauen](#5-llamacpp-bauen)
   - [5.1 CUDA Toolkit](#51-cuda-toolkit-installieren)
   - [5.2 Kompilieren](#52-llamacpp-kompilieren)
   - [5.3 Direkter Chat](#54-direkter-chat-via-llama-cli)
6. [Networking](#6-networking)
   - [6.1 Port forwarding](#61-port-forwarding)
   - [6.2 Firewall](#62-firewall)
7. [llama-server starten](#7-llama-server-starten-api-server)
8. [Chats](#8-chats)
   - [8.1 Qwen Companion](#81-qwen-companion-chat-vscode-extensions)
   - [8.2 Continue.dev](#82-continuedev-vscode-extensions)
   - [8.3 Open Code](#83-open-code)
9. [Test Prompts](#9-test-prompts)
10. [Fazit](#10-fazit)

---

## 1. WSL2 aktivieren

Öffne **PowerShell als Administrator**:

```powershell
# WSL2 als Standard setzen und aktivieren
wsl --install --no-distribution

# Neustart erforderlich
Restart-Computer
```

Nach dem Neustart WSL2 als Standardversion verifizieren:

```powershell
wsl --set-default-version 2
wsl --version
```

Erwartete Ausgabe:

```
WSL-Version: 2.x.x.x
Kernelversion: 5.15.x / 6.x.x
```

---

## 2. Separate WSL2-Distribution erstellen

Mit dem `--name`-Flag (verfügbar ab WSL 2.0) kann die Distribution direkt mit einem eigenen Namen installiert werden.

### 2.1 Ubuntu 24.04 mit eigenem Namen installieren

```powershell
wsl --install -d Ubuntu-24.04 --name unsloth
```

Es öffnet sich automatisch ein Terminal – dort **Benutzername und Passwort** vergeben. Danach das Fenster schließen.

Als Passwort Benutzername und Passwort nehme ich `tobias` und `pass`.

```powershell
# Prüfen ob die Distribution korrekt angelegt wurde
wsl --list --verbose
# NAME      STATE           VERSION
# unsloth   Stopped         2
```

### 2.2 WSL2 Arbeitsspeicher-Limit setzen

Windows limitiert WSL2 standardmäßig auf 50% RAM. Für KI ungünstig. Wir wollen mindestens **56 GB** haben:

Datei `C:\Users\WIN11\.wslconfig` erstellen/bearbeiten:

```ini
[wsl2]
memory=56GB          # Mindestens 56 GB für Modell + KV-Cache
processors=16        # CPU-Kerne (passe an deine CPU an)
swap=32GB
swapFile=D:\\WSL\\swap.vhdx
localhostForwarding=true
```

Danach: `wsl --shutdown` und mit `wsl -d unsloth` neu starten.

### 2.3 DNS-Auflösung in WSL2 fixieren (Pflicht!)

WSL2 hat standardmäßig ein Problem mit der DNS-Auflösung über `systemd-resolved`. Ohne diesen Fix schlägt `apt update` mit `Temporary failure in name resolution` fehl.

**Schritt 1: In WSL2-Shell** – anpassen:

```bash
sudo tee -a /etc/wsl.conf << EOF

[network]
generateResolvConf = false
EOF
```

**Schritt 2: In der WSL2-Shell**:

```bash
# systemd-resolved deaktivieren
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

**Schritt 3: In PowerShell** – Distribution neu starten:

```powershell
wsl --shutdown
wsl -d unsloth
```

**Schritt 4: In der WSL2-Shell** – resolv.conf manuell setzen:

```bash
# Symlink entfernen und eigene resolv.conf schreiben
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf << EOF
nameserver 192.168.178.1
search fritz.box
EOF
```

> ⚠️ `192.168.178.1` ist die IP des Fritzbox-Routers. Bei abweichendem Router-Subnetz entsprechend anpassen. Alternativ: `8.8.8.8` (Google DNS) funktioniert immer.

```bash
# Verbindung testen
ping -c 2 google.com
```

### 2.4 Grundpakete installieren

```bash
sudo apt update && sudo apt dist-upgrade -y
sudo apt install -y \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    htop \
    nvtop \
    ca-certificates \
    software-properties-common \
    libssl-dev \
    libffi-dev
```

---

## 3. Huggingface Cache auslagern

Ich empfehle den Huggingface Cache (der all die Models enthält) irgendwo einzuhängen, wo genug Speicherplatz ist. Das hat auch den Vorteil, dass wenn du dein WSL OS einmal neu aufsetzt die Models nicht neu laden musst.

```bash
rm -rf ~/.cache/huggingface
mkdir -p ~/.cache/huggingface

# Verhindert, dass in das Verzeichnis geschrieben werden kann, wenn der Mount nicht existiert.
sudo chattr +i ~/.cache/huggingface

sudo mount --bind /mnt/d/WSL/huggingface ~/.cache/huggingface

# Damit das beim Neustart der WSL-Distribution auch wieder eingehängt wird, in die fstab eintragen.
sudo tee -a /etc/fstab << EOF
/mnt/d/WSL/huggingface  /home/tobias/.cache/huggingface  none  bind,nofail,x-systemd.automount,x-systemd.requires=/mnt/d  0 2
EOF
```

## 4. Unsloth installieren

Unsloth bietet ein offizielles Installationsskript, das alle Abhängigkeiten automatisch einrichtet – kein manuelles CUDA Toolkit oder PyTorch Setup nötig.

```bash
# In der WSL2-Shell (wsl -d unsloth)
curl -fsSL https://unsloth.ai/install.sh | sh
```

Die Installation dauert ca. 1–2 Minuten. Danach WSL neu starten damit alle Pfade aktiv sind:

In **PowerShell**:

```powershell
wsl --shutdown
wsl -d unsloth
```

### 4.1 Unsloth Kennwort

Nachdem unsloth gestartet ist, im Webbrowser aufrufen und Kennwort: `passwort` nutzen.

### 4.2 Unsloth Studio starten (optionale Web-UI)

```bash
unsloth studio -H 0.0.0.0 -p 8888
```

Dann im Browser: `http://localhost:8888` öffnen.

### 4.3 Unsloth Modell runterladen: Qwen3.6-27B-GGUF 

Quants, die bei 24 GB VRAM passen: 
* UD-Q2_K_XL
* UD-Q3_K_XL
* UD-Q4_K_XL
* UD-Q5_K_XL

### 4.6 Empfohlene Inferenzparameter

Ich nutze folgende Inferenzparameter, die das Model besser für Codingartige Aufgaben vorbereiten. Insbesondere die Temperatur ist bei unsloth viel zu hoch eingestellt, sodass er zu häufig fantasiert. Mit 0.3 oder 0.2 sieht das viel besser aus.


| Parameter    | Wert            | Hinweis                                |
| ------------ | --------------- | -------------------------------------- |
| `Temp`     | `0.2`           | Weniger Fantasie beim Coden. 0.6 wird von Unsloth empfohlen, ist aber noch viel zu hoch.            |
| `Top-p`    | `0.95`          | Von Unsloth empfohlen                  |
| `Top-k`    | `20`            | Von Unsloth empfohlen                  |
| `Min-p`    | `0.00`          | Von Unsloth empfohlen                  |
| `Presence Penalty`    | `0.0`          | Von Unsloth empfohlen                 |
| `Frequency Penalty`    | `0.1`          | Unsloth empfiehlt 1.0, ich hatte aber keine Probleme mit Looping, also habe ich es auf 0.1 gesenkt.                |

### 4.7 Huggingface CLI

Tipp: Mit `uvx hf` kannst du auch ganz normal die Huggingface CLI nutzen um weitere Modelle zu laden. Es ist allerdings meistens einfacher direkt Unsloth Studio zu nutzen, wenn man mal schnell ein neues Model ausprobieren will.

llama-server  kennt auch das Argument `-hf`, mit dem direkt Modelle von Huggingface genutzt werden können.

### 4.8. Multi Token Prediction (MTP) / speculative Decoding

Bei [Multi Token Prediction (MTP) / speculative Decoding](https://github.com/ggml-org/llama.cpp/pull/22673) wird ein zusätzlicher Transformer Layer in den VRAM geladen, der es ermöglicht mehrere Tokens parallel auszulesen. Das kann bis zu 2x mehr Geschwindigkeit bei der Tokengenerierung erzeugen. Der zusätzliche Layer muss allerdings ins VRAM passen, was das ganze mitunter sehr kostspielig für die Kontextgröße macht.

Um MTP nutzen zu können braucht es andere Modelle. Unsloth Studio kann MTP noch nicht nutzen, daher bauen wir llama.cpp vom Quellcode und laden entsprechende Modelle von Huggingface.

Mit folgenden Befehlen kannst du die MTP Modelle von [havenoammo/Qwen3.6-27B-MTP-UD-GGUF](https://huggingface.co/havenoammo/Qwen3.6-27B-MTP-UD-GGUF) runterladen:

```bash
uvx hf download havenoammo/Qwen3.6-27B-MTP-UD-GGUF --include Qwen3.6-27B-MTP-UD-Q5_K_XL.gguf --include Qwen3.6-27B-MTP-UD-Q4_K_XL.gguf
```

## 5. llama.cpp bauen

llama.cpp ist die empfohlene Inference-Engine für GGUF-Modelle – stabil, GPU-beschleunigt und OpenAI-API-kompatibel. Da man bei unsloth den OpenAI-Port nicht einstellen kann, starte ich die Modelle direkt mit llama.cpp. Das ist übrigens auch, wie unsloth die Modelle startet.

Wir bauen llama.cpp von source um von den neusten Optimierungen zu profitieren.

### 5.1 CUDA Toolkit installieren

Das Unsloth-Installskript richtet CUDA nur für Python ein. cmake benötigt zusätzlich das system-weite CUDA Toolkit (`nvcc` + Header). Wir installieren es  per Runfile. Alle Versionen kannst du dir [hier](https://developer.nvidia.com/cuda-toolkit-archive) ansehen. 

Tipp: Wir installieren nur 13.1, da Nvidia mit 13.2 irgendwelche Bugs eingebaut hat, die bei stark quantisierten Modellen zu gibberish Output führen. Das tritt wohl insbesondere im Zusammenhang mit -O3 auf. [Hier](https://www.reddit.com/r/unsloth/comments/1sgl0wh/do_not_use_cuda_132_to_run_models/) steht mehr dazu.


```bash
# Installiere die erforderlichen Build Tools:
sudo apt-get install -y pciutils build-essential cmake curl libcurl4-openssl-dev

# Führe Runfile aus.
cd
wget https://developer.download.nvidia.com/compute/cuda/13.1.2/local_installers/cuda_13.1.2_590.48.01_linux.run
sudo sh cuda_13.1.2_590.48.01_linux.run

# accept eingeben und Haken bei Dokumentation rausnehmen, dann install auswählen.

# Umgebungsvariablen setzen
echo 'export PATH=/usr/local/cuda-13.1/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
```

Danach WSL neu starten:

```powershell
wsl --shutdown
wsl -d unsloth
```

```bash
# Verifizieren
nvcc --version
```

### 5.2 llama.cpp Kompilieren

```bash
cd ~
git clone https://github.com/ggml-org/llama.cpp

# Wenn du magst, kannst du den MTP branch mergen für mehr Speed beim Generieren von Tokens
pushd llama.cpp
git fetch origin
git fetch origin pull/22673/head:pr-22673
git checkout pr-22673
popd


# Mit CUDA-Support bauen (GGML_CUDA=ON für GPU-Beschleunigung)
cmake llama.cpp -B llama.cpp/build \
    -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=ON
cmake --build llama.cpp/build --config Release -j --clean-first \
    --target llama-cli llama-mtmd-cli llama-server llama-gguf-split llama-bench llama-fit-params

# Binaries ins llama.cpp-Verzeichnis kopieren
cp llama.cpp/build/bin/llama-* llama.cpp
```

### 5.3 Build verifizieren

```bash
~/llama.cpp/llama-cli --version
```

---

### 5.4 Wie startet Unsloth llama.cpp?

Unsloth Studio lädt Modelle in den ~/.cache/huggingface. Du kannst sie wie folgt finden:

```bash
find ~ -name "*Qwen3.6-27B-*.gguf"
```

Unloth startet sein eigenes llama.cpp bspw mit folgenden Parametern:

```bash
~/llama.cpp/llama-server -m "/home/tobias/.cache/huggingface/hub/models--unsloth--Qwen3.6-27B-GGUF/snapshots/82d411acf4a06cfb8d9b073a5211bf410bfc29bf/Qwen3.6-27B-UD-Q5_K_XL.gguf" --port 8001 -c 34944 --parallel 1 --flash-attn on --no-context-shift -ngl -1 --jinja --cache-type-k q8_0 --cache-type-v q8_0 --chat-template-kwargs "{\"enable_thinking\": true}" --mmproj "/home/tobias/.cache/huggingface/hub/models--unsloth--Qwen3.6-27B-GGUF/snapshots/82d411acf4a06cfb8d9b073a5211bf410bfc29bf/mmproj-BF16.gguf"  --seed 3407
```


### 5.5 Direkter Chat via llama-cli

Du kannst die Inferenz testen, indem du schnell mal die llama cli startest:

```bash
~/llama.cpp/llama-cli \
    --model `find ~ -name "Qwen3.6-27B-UD-Q4_K_XL.gguf"` \
    --seed 3407 \
    --temp 0.2 --top-p 0.95 --min-p 0.00 --top-k 20 \
    --ctx-size 16384
```

### 5.6. Kontext Parameter bestimmen lassen

Mit dem Kommando `llama-fit-params` kann man die optimalen Parameter für seine Hardware berechnen lassen. Mit `--fit-target` stellt man ein wieviel MB er als reserve freilassen soll. 

```bash
~/llama.cpp/llama-fit-params \
    --fit-target 256 \
    --model `find ~ -name "Qwen3.6-27B-UD-Q4_K_XL.gguf"` 

# oder mit anderen kv quants:
~/llama.cpp/llama-fit-params \
    --fit-target 256 \
    --cache-type-k q8_0 --cache-type-v q8_0  \
    --model `find ~ -name "Qwen3.6-27B-UD-Q4_K_XL.gguf"` 
```

## 6. Networking

Damit aus dem LAN auf den llama.cpp Server zugegriffen werden kann ist noch folgendes notwendig.

### 6.1 Port forwarding

wsl nutzt NAT. Daher brauchen wir eine Forwarding Regel. 

Wir nutzen aus, dass wsl automatisch localhost zum WSL Interface NATed. Das heißt Windows kümmert sich darum, dass der Server unter `http://localhost:8001` erreichbar ist (dank `localhostForwarding=true`). Daher brauchen wir nur noch eine NAT Regel, die das auch von unserem LAN Interface aus tut.

> Wichtig: Nutze als listenaddress nicht 0.0.0.0, da der Portproxy dann auch 127.0.0.1 versucht zu binden, was dann Windows davon abhält diesen Port für WSL zu binden.

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

### 6.2 Firewall

In der Firewall muss eine neue Regel erstellt werden. Ich mache das in der UI.

* Protocol: TCP
* Ports: 8001,8888

## 7. llama-server starten (API-Server)

`llama-server` stellt eine **OpenAI-kompatible REST-API** bereit – direkt nutzbar für VS Code (Continue.dev oder Qwen Companion), Open Code und andere Tools.


In einem WSL2-Terminal starten (Terminal-Tab offen lassen, solange der Server laufen soll) und `llama-server` aufrufen.

> Tipp: Du kannst auch Vision Features aktivieren um Bilder verarbeiten zu können. Das kostet aber wieder etwas VRAM und daher Kontextgröße. Nutze einfach `--mmproj $(find ~ -path "*Qwen3.6-27B-GGUF*" -name "mmproj-BF16.gguf" | head -1)`

```bash
# UD-Q4_K_XL kv=q8_0
~/llama.cpp/llama-server \
    --model $(find ~ -name "Qwen3.6-27B-UD-Q4_K_XL.gguf" | head -1) \
    --alias "unsloth/Qwen3.6-27B" \
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
    --fit off \
    --seed 3407 \
    --ctx-size 190000

# UD-Q5_K_XL kv=q8_0
~/llama.cpp/llama-server \
    --model $(find ~ -name "Qwen3.6-27B-UD-Q5_K_XL.gguf" | head -1) \
    --alias "unsloth/Qwen3.6-27B" \
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
    --fit off \
    --seed 3407 \
    --ctx-size 115000

# Wenn du ein MTP Modell hast und llama.cpp mit MTP gebaut hast,
# kannst du --spec-type mtp --spec-draft-n-max 3 nutzen für schnellere Tokengenerierung.
# Der zusätzliche Transformer Layer kostet aber viel VRAM und damit Kontextgröße.
~/llama.cpp/llama-server \
    --model $(find ~ -name "Qwen3.6-27B-MTP-UD-Q4_K_XL.gguf" | head -1) \
    --alias "unsloth/Qwen3.6-27B" \
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
    --seed 3407 \
    --fit off \
    --spec-type mtp  --spec-draft-n-max 3 \
    --ctx-size 96000

# Hier mit den besseren Q5 Quants:
~/llama.cpp/llama-server \
    --model $(find ~ -name "Qwen3.6-27B-MTP-UD-Q5_K_XL.gguf" | head -1) \
    --alias "unsloth/Qwen3.6-27B" \
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
    --seed 3407 \
    --fit off \
    --spec-type mtp  --spec-draft-n-max 3 \
    --ctx-size 37000


```

### 7.2 OpenAI API testen

```bash
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.6-27B",
    "messages": [{"role": "user", "content": "Write a Python hello world"}]
  }'
```

### 7.3. Performance mit RTX 4090 24 GB VRAM

Da die RTX 4090 meine primäre GPU ist, die Windows zum Rendern des Desktops nutzt, büße ich natürlich ein wenig Kontextgröße ein. 

Hier ist eine Tabelle, bei denen ich die unterschiedlichen Quantisierungen getestet habe. Alle Layer passten vollständig ins VRAM. Wichtig: Die Benchmarks habe ich mit deaktiviertem Vision Model gemacht um mehr Platz zu haben. Wenn du das Vision Model aktivierst (`--mmproj` Parameter) verlierst du entsprechend Kontextgröße.

Der Stromverbrauch beträgt etwa 350 W.

| Modell         | KV Quants  | Kontextgröße | t/s   |
|----------------|------------|--------------|-------|
| UD-Q2_K_XL     | q8_0       | 262144       | 59    |
| UD-Q3_K_XL     | q8_0       | 262144       | 51    |
| UD-Q4_K_XL     | q8_0       | 190000       | 44    |
| UD-Q5_K_XL     | q8_0       | 115000       | 40    |
| UD-Q2_K_XL     | f16        | 185000       | 60    |
| UD-Q3_K_XL     | f16        | 146000       | 52    |
| UD-Q4_K_XL     | f16        | 100000       | 45    |
| UD-Q5_K_XL     | f16        | 61000        | 41    |
| MTP-UD-Q4_K_XL | q8_0       | 96000        | 90    |
| MTP-UD-Q5_K_XL | q8_0       | 37000        | 86    |
| MTP-UD-Q4_K_XL | f16        | 52000        | 93    |
| MTP-UD-Q5_K_XL | f16        | 20000        | 89    |

Interessanterweise ergibt sich aus den Daten ein Gewisser Kostenfaktor für die Features. Das wären:

* Aktivierung von MTP kostet ca. 50% Kontextgröße, sorgt aber für einen Geschwindigkeitsboost um den Faktor 2x. Weniger stark quantisierte Modelle leiden stärker, da hier in absoluten Zahlen der Kontextverlust durch den zusätzlichen Transformerlayer stärker ins Gewicht fällt.
* Die Aktivierung der q8_0 Quantisierung für den KV Cache bringt ca. 55% mehr Kontextgröße. Ein Unterschied zu f16 ist selbst bei Coding Aufgaben nicht zu bemerken. Es kommt allerdings auch zu einem kleinen Geschwindigkeitsverlust von ca. 2%. 
* Wenn du eine bessere Quantisierung für das Model auswählst, dann kostet es ca 30% Kontextgröße. Wenn MTP Aktiviert ist sogar 60%. 

Hier sind noch genauere Berechnungen:

#### 7.3.1 Gewinne durch MTP

| Modell (MTP)  | KV Quants  | Kontextgröße | t/s   | Available Ctx | Gain in t/s |
|------------|------------|--------------|-------|-------------|-------------|
| UD-Q4_K_XL | q8_0       | 96000        | 90    | 51%         | 2.0         |
| UD-Q5_K_XL | q8_0       | 37000        | 86    | 32%         | 2.2         |
| UD-Q4_K_XL | f16        | 52000        | 93    | 52%         | 2.1         |
| UD-Q5_K_XL | f16        | 20000        | 89    | 33%         | 2.2         |

#### 7.3.2 Gewinne durch q8_0 Quantisierung des KV Cache

| Modell (KV=q8_0)   | Gain in Ctx | Loss in t/s |
|------------|------------|--------------|
| UD-Q2_K_XL | +42%       | -2%        | 
| UD-Q3_K_XL | +80%       | -2%        |
| UD-Q4_K_XL | +90%        | -2%        | 
| UD-Q5_K_XL | +89%        | -2%        |
| MTP_UD-Q4_K_XL | +85%        | -3%        | 
| MTP_UD-Q5_K_XL | +85%        | -3%        | 

#### 7.3.3 Gewinne durch Quantisierung des Models

| Modell              | KV Quants | Gain in Ctx | 
|---------------------|-----------|-------------|
| Choosing Q3 over Q2 | q8_0      | -0%        |
| Choosing Q4 over Q3 | q8_0      | -38%        |
| Choosing Q5 over Q4 | q8_0      | -65%        |
| Choosing Q5 over Q4 (MTP) | q8_0| -159%        |
| Choosing Q3 over Q2 | f16       | -27%        |
| Choosing Q4 over Q3 | f16       | -46%        |
| Choosing Q5 over Q4 | f16       | -64%        |
| Choosing Q5 over Q4 (MTP) | f16 | -160%       |

Oder andersherum betrachtet, kannst du deinen Kontext ziemlich vergrößern durch mehr Quantisierung.

| Modell              | KV Quants | Gain in Ctx | 
|---------------------|-----------|-------------|
| Choosing Q2 over Q3 | q8_0      | +0%        |
| Choosing Q3 over Q4 | q8_0      | +38%        |
| Choosing Q4 over Q5 | q8_0      | +65%        |
| Choosing Q4 over Q5 (MTP) | q8_0| +159%        |
| Choosing Q2 over Q3 | f16       | +27%        |
| Choosing Q3 over Q4 | f16       | +46%        |
| Choosing Q4 over Q5 | f16       | +64%        |
| Choosing Q4 over Q5 (MTP) | f16 | +160%        |



## 8. Chats

### 8.1 Qwen Companion Chat VSCode Extensions

Die beste Extension, die so ähnlich wie die Github Copilot Extension ist, ist die Qwen Code Companion. Da kann man auch sein eigenes Modell anbinden.

Öffne die settings.json unter `%USERPROFILE%\.qwen\settings.json` und füge das Model wie folgt hinzu:

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
        "baseUrl": "http:/192.168.178.115:8001/v1",
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

Jetzt VS Code einmal neu starten und das Fenster mit `Strg + L` einmal öffnen. 

> Tipp: Wenn du Qwen deine Codebase einmal erkunden lassen willst, nutze /init. Er erstellt sich dann ein QWEN.md mit allen wichtigen Details. Das funktioniert quasi wie die CLAUDE.md


### 8.2 Continue.dev VSCode Extensions 

**Continue** ist ebenfalls eine gute Open-Source-Alternative für agentic coding mit lokalen Modellen.

1. Extension installieren: **Continue** (continue.continue) in VS Code
2. Konfigurationsdatei bearbeiten unter `%USERPROFILE%\.continue\config.yaml`:

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

**Verwendung in VS Code:**

- `Strg+L` – Chat öffnen (agentic Chat)
- `Strg+Shift+R` – Autocomplete manuell triggern

### 8.3 Open Code

**Open Code** ist ein CLI-Tool für Agentic Coding, das wie Claude Code funktioniert, aber vollständig mit lokalen Modellen arbeitet. Es unterstützt jeden OpenAI-kompatiblen Server und damit perfekt unseren `llama-server`.

Es hat ähnlich wie Claude Desktop auch eine Desktop App, die das ganze noch einfacher einzurichten macht. 

#### 8.3.1 Installation

Downloade dir den Desktop Client und installiere ihn. Hier ist die URL: [https://opencode.ai/de/download](https://opencode.ai/de/download).

#### 8.3.2 Konfiguration

Die Konfigurationsdatei liegt bei `%USERPROFILE%\.config\opencode\opencode.jsonc`. Passe Sie wie folgt an:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "disabled_providers": [],
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

Alternativ kannst du das auch über die Oberfläche machen und einen benutzerdefinierten Anbieter hinzufügen und die Parameter manuell eingeben.

> Wichtig: Egal ob via UI oder config.jsonc, Open Code muss einmal neu gestartet werden, andernfalls sieht man den neuen Provider nicht.

### 9. Test Prompts

Hier sind ein paar Prompts, mit denen ich die KI teste. Man sieht deutliche Unterschiede, wenn die Temperatur bspw auf 0.6 gestellt ist.

### 9.1 OAuth2 Client Beispiel

```plain
Kannst du mir ein oauth2 Beispiel bauen in c#, ohne externe libs. Also einfach nur ein program.cs das eine api per client credential grant aufruft.
```

```plain
Haufenweise key value pairs... Bitte nutze .net 10 und die coolen shortcuts. Dann kannst du diese ganzen new KeyValuePair<string,string> weglassen.

Bitte nutze die neusten c# language features
```

### 9.2 OpenIddict Knowledge

```plain
Kennst du OpenIddict?
```

```plain
Ich habe in meinem projekt OpenIddict genutzt. Und zwar im degraded mode. Ich möchte nun dass du den authorization code beim pkce grant kürzer machst. Speicher einfach den code in einem memory cache und ersetz den einfach mit einem reference code. Kannst du mir zeigen, wie man das konkret implementieren würde?
```

```plain
Du brauchst Handler für ProcessSignInContext und ExtractTokenRequestContext.
```

### 9.3 WSL Knowledge

```plain
Ich hab wsl und hoste einen http server da drin. Ich kann nun aber nicht von anderen Rechnern im LAN darauf zugreifen. Meine ip ist 192.168.178.115 und mein server unter port 8001 gehostet. Wenn ich per localhost von Windows aus draufgehe geht es. Aber selbst wenn ich http://192.168.178.115:8001 in Windows eingebe gehts schon nicht. Es geht auch nicht wenn ich das von anderen Rechnern im LAN aus aufrufe. Ne idee was man machn kann?
```

Idealerweise sagt er:

* Windows Firewall muss konfiguriert werden
* Portproxy von Windows mit listen=192.168.178.115 und NICHT 0.0.0.0, weil das ja die WSL Bindung stört
* Portproxy Target gegen 127.0.0.1, weil Windows die Ports automatisch dank `localhostForwarding=true` daran bindet.
* Er weist auf `networkingMode=mirrored` hin

## 10. Fazit

Qwen3.6 27B ist beeindruckend. Es hält locker mit Claude Sonnet 4.5 mit und läuft dabei auf einfacher Consumer Hardware – vollständig lokal und kostenlos.

Der Einrichtungsaufwand ist einmalig hoch: WSL2, CUDA, llama.cpp bauen, Networking konfigurieren. Wer das einmal durchgezogen hat, bekommt dafür einen vollwertigen KI-Coding-Assistenten, der dauerhaft nichts kostet und keinen API-Key braucht.

Schwächen zeigen sich bei komplexen Mehrschrittaufgaben: Qwen neigt gelegentlich dazu, Syntaxfehler zu produzieren oder suboptimale Architekturentscheidungen zu treffen, bei denen Sonnet besser abschneiden würde. Außerdem ist er mit ~45 t/s spürbar langsamer als Claude.

Für den alltäglichen Einsatz im Homelab oder für datenschutzsensible Projekte ist das Setup aber klar empfehlenswert. Die Kombination aus Qwen Companion, Continue.dev und Open Code deckt praktisch jeden Anwendungsfall ab.