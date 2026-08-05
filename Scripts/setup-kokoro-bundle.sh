#!/usr/bin/env bash
# Legt Kokoro-CoreML-Modelle lokal ins App-Bundle ab (einmalig beim Entwickeln, kein Runtime-Download).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Resources/Models/kokoro-de"
REPO="Jud/kokoro-coreml"
ASSET="kokoro-models.tar.gz"

echo "→ Ziel: $TARGET"

if [[ -d "$TARGET/kokoro_frontend.mlmodelc" && -d "$TARGET/voices" ]]; then
  echo "✓ Kokoro-Modell bereits vorhanden – überspringe Download."
  exit 0
fi

mkdir -p "$TARGET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Ermittle neuestes models-* Release …"
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
  | python3 -c "
import json, sys
releases = json.load(sys.stdin)
for item in releases:
    tag = item.get('tag_name', '')
    if tag.startswith('models-'):
        print(tag)
        break
else:
    print('models-v1')
")

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
echo "→ Lade ${URL} …"
curl -fL "$URL" -o "$TMP/${ASSET}"

echo "→ Entpacke nach ${TARGET} …"
tar xzf "$TMP/${ASSET}" -C "$TARGET"

echo ""
echo "✓ Kokoro-CoreML gebündelt unter Resources/Models/kokoro-de"
echo ""
echo "Optional – deutsche Stimme + Gewichte:"
echo "  ./Scripts/setup-kokoro-german.sh           # Stimme thorsten.bin"
echo "  ./Scripts/setup-kokoro-german.sh --full    # + deutsch trainierte CoreML-Gewichte"
echo ""
echo "In Xcode: Ordner „Resources/Models/kokoro-de“ als blaue Ordnerreferenz"
echo "unter „Copy Bundle Resources“ hinzufügen (wie openai_whisper-base)."
