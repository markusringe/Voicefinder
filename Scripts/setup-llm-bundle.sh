#!/usr/bin/env bash
# Legt das eingebettete MLX-Sprachmodell ins Repository (einmalig für Entwickler).
#
# Standard: Qwen3-1.7B-4bit (~970 MB) – etwas schlauer als 2.5-1.5B, ähnlicher RAM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="mlx-community/Qwen3-1.7B-4bit"
TARGET="$ROOT/Resources/Models/qwen3-1.7B-4bit"
BASE_URL="https://huggingface.co/${REPO}/resolve/main"

FILES=(
  config.json
  model.safetensors
  model.safetensors.index.json
  tokenizer.json
  tokenizer_config.json
  vocab.json
  merges.txt
  added_tokens.json
  special_tokens_map.json
)

echo "→ Ziel (fest eingebettet): $TARGET"
echo "-> Modell: ${REPO} (~970 MB – Qwen3 1.7B, 4-Bit quantisiert)"

if test -f "$TARGET/config.json" && test -f "$TARGET/model.safetensors" && test -f "$TARGET/tokenizer.json"; then
  echo "✓ Eingebettetes LLM bereits vorhanden."
  exit 0
fi

mkdir -p "$TARGET"

download_file() {
  local file="$1"
  local dest="${TARGET}/${file}"
  if test -f "${dest}"; then
    echo "  skip ${file}"
    return 0
  fi
  echo "  get ${file}"
  curl -fL "${BASE_URL}/${file}" -o "${dest}"
}

echo "→ Lade ${REPO} …"
for file in "${FILES[@]}"; do
  download_file "$file"
done

echo ""
echo "✓ Modell unter Resources/Models/qwen3-1.7B-4bit verankert."
echo "  In Xcode: Ordner als blaue Ordnerreferenz unter „Copy Bundle Resources“."
echo "  Danach Clean Build (⇧⌘K). App-Größe steigt um ~970 MB."
