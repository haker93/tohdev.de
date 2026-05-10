# Beellama

[BeeLlama.cpp](https://github.com/Anbeeld/beellama.cpp/tree/main) ist ein auf Performance optimierter Fork von llama.cpp, der mehr Geschwindigkeit und größeren Kontext aus der lokalen GGUF-Inferenz herausholt. Er behält die bekannten llama.cpp-Tools und den Server-Workflow bei und fügt DFlash-Spekulatives Decoding, adaptive Draft-Steuerung, TurboQuant/TCQ KV-Cache-Kompression sowie Schutzmechanismen für Reasoning-Loops hinzu – mit vollständiger Multimodal-Unterstützung.

## Compiling

```bash

# OpenSSL is required for beellama
sudo apt-get install -y libssl-dev

cd ~
rm -rf llama.cpp
git clone https://github.com/Anbeeld/beellama.cpp.git llama.cpp

mkdir -p ~/llama.cpp/build

# Tipp: Benutze -DCMAKE_CUDA_ARCHITECTURES=86 für RTX 3090 oder -DCMAKE_CUDA_ARCHITECTURES=89 für RTX 4090
pushd llama.cpp
cmake -B build -DGGML_CUDA=ON -DGGML_NATIVE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON \
  -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DCMAKE_BUILD_TYPE=Release
cmake  --build build --config Release -j --clean-first \
    --target llama-cli llama-mtmd-cli llama-server llama-gguf-split llama-bench llama-fit-params
popd

cp llama.cpp/build/bin/llama-* llama.cpp

```

## Models herunterladen

```bash
uvx hf download unsloth/Qwen3.6-27B-GGUF --include Qwen3.6-27B-Q5_K_S.gguf --include Qwen3.6-27B-Q4_K_M.gguf --include Qwen3.6-27B-Q5_K_M.gguf

uvx hf download Ardenzard/Qwen3.6-27B-DFlash-GGUF --include Qwen3.6-27B-DFlash-Q5_K_M.gguf

uvx hf download spiritbuun/Qwen3.6-27B-DFlash-GGUF --include dflash-draft-3.6-q4_k_m.gguf

```


## Llama Server starten

```bash
~/llama.cpp/llama-server \
  -m `find ~ -name "Qwen3.6-27B-Q5_K_S.gguf"` \
  --mmproj `find ~ -path "*Qwen3.6-27B-GGUF*" -name "mmproj-BF16.gguf"` \
  --no-mmproj-offload \
  --spec-draft-model `find ~ -name "dflash-draft-3.6-q4_k_m.gguf"` \
  --spec-type dflash \
  --spec-dflash-cross-ctx 1024 \
  --port 8001 \
  -np 1 \
  --kv-unified \
  -ngl all \
  --spec-draft-ngl all \
  -b 2048 -ub 256 \
  --ctx-size 122800 \
  --cache-type-k turbo4 --cache-type-v turbo3_tcq \
  --flash-attn on \
  --cache-ram 0 \
  --jinja \
  --no-mmap \
  --no-host --metrics \
  --log-timestamps --log-prefix --log-colors off \
  --reasoning on \
  --chat-template-kwargs '{"preserve_thinking":true}' \
  --temp 0.0 --top-k 20 --min-p 0.0
```