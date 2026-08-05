#!/usr/bin/env bash
# Richtet ein deutsch trainiertes Kokoro-CoreML-Modell für Voicefinder ein.
#
# Ablauf:
#   1. Thorsten-Voice/Kokoro (Standard) oder kikiri-german-martin (--variant kikiri)
#   2. Voice .pt → .bin konvertieren
#   3. Optional: PyTorch-Gewichte → CoreML exportieren (lange Laufzeit, ~350 MB Download)
#
# Nutzung:
#   chmod +x Scripts/setup-kokoro-german.sh
#   ./Scripts/setup-kokoro-german.sh              # nur Stimme (schnell)
#   ./Scripts/setup-kokoro-german.sh --full       # Stimme + CoreML-Export
#   ./Scripts/setup-kokoro-german.sh --variant kikiri --full
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Resources/Models/kokoro-de"
WORK="$ROOT/.build/kokoro-german-setup"
KOKORO_REPO="$WORK/kokoro-coreml"
VENV="$WORK/.venv"

VARIANT="${VARIANT:-thorsten}"   # thorsten | kikiri
FULL_EXPORT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL_EXPORT=1; shift ;;
    --variant) VARIANT="$2"; shift 2 ;;
    thorsten|kikiri) VARIANT="$1"; shift ;;
    *) echo "Unbekanntes Argument: $1"; exit 1 ;;
  esac
done

mkdir -p "$TARGET/voices" "$WORK"

echo "→ Variante: $VARIANT"
echo "→ Ziel:     $TARGET"

# --- Hugging-Face-Dateien je Variante ---
case "$VARIANT" in
  thorsten)
    HF_REPO="Thorsten-Voice/Kokoro"
    HF_MODEL="model.pth"
    HF_CONFIG="config.json"
    HF_VOICE="voices/thorsten.pt"
    VOICE_NAME="thorsten"
    LANG_CODE="d"
    ;;
  kikiri)
    HF_REPO="kikiri-tts/kikiri-german-martin"
    HF_MODEL="kikiri_german_martin_ep10.pth"
    HF_CONFIG="config.json"
    HF_VOICE="voices/martin.pt"
    VOICE_NAME="dm_martin"
    LANG_CODE="de"
    ;;
  *)
    echo "Unbekannte Variante: $VARIANT (thorsten|kikiri)"
    exit 1
    ;;
esac

hf_download() {
  local repo="$1" file="$2" dest="$3"
  local url="https://huggingface.co/${repo}/resolve/main/${file}"
  if [[ -f "$dest" ]]; then
    echo "  ✓ bereits vorhanden: $(basename "$dest")"
    return 0
  fi
  echo "  ↓ ${file} …"
  curl -fL "$url" -o "$dest"
}

echo ""
echo "=== Schritt 1: Deutsche Stimme herunterladen und konvertieren ==="
VOICE_PT="$WORK/${VOICE_NAME}.pt"
hf_download "$HF_REPO" "$HF_VOICE" "$VOICE_PT"

# Python ≥3.10 für kokoro/coremltools (System-3.9 reicht nicht)
PYTHON=""
for candidate in \
  "$ROOT/.build/python312/bin/python3" \
  python3.12 python3.11 python3.10 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    ver="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    major="${ver%%.*}"
    minor="${ver#*.}"
    if [[ "$major" -ge 3 && "$minor" -ge 10 ]]; then
      PYTHON="$candidate"
      break
    fi
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "→ Python 3.10+ fehlt – lade Standalone-Python 3.12 …"
  PY_DIR="$ROOT/.build/python312"
  mkdir -p "$PY_DIR"
  curl -fL "https://github.com/astral-sh/python-build-standalone/releases/download/20250205/cpython-3.12.9+20250205-aarch64-apple-darwin-install_only.tar.gz" \
    | tar xz -C "$PY_DIR" --strip-components=1
  PYTHON="$PY_DIR/bin/python3"
fi

if [[ ! -d "$VENV" ]]; then
  echo "→ Python-Venv anlegen ($("$PYTHON" --version)) …"
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q torch numpy
fi

echo "→ Konvertiere Voice → .bin …"
"$VENV/bin/python" "$ROOT/Scripts/convert_kokoro_voice_pt_to_bin.py" \
  "$VOICE_PT" \
  -o "$TARGET/voices/${VOICE_NAME}.bin"

echo ""
echo "✓ Stimme gebündelt: voices/${VOICE_NAME}.bin"

if [[ "$FULL_EXPORT" -eq 0 ]]; then
  echo ""
  echo "Hinweis: CoreML-Gewichte sind noch ENGLISCH (Jud-Release)."
  echo "Für natürliches Deutsch CoreML-Export starten:"
  echo "  ./Scripts/setup-kokoro-german.sh --full"
  echo ""
  echo "Die deutsche Stimme (${VOICE_NAME}) wird bereits verwendet, sobald"
  echo "KokoroModelProvider sie findet – akustische Qualität verbessert sich"
  echo "erst nach --full (deutsch trainierte Gewichte)."
  exit 0
fi

echo ""
echo "=== Schritt 2: Deutsch trainierte CoreML-Gewichte exportieren ==="
echo "    (Download ~330 MB, Export 15–45 Min.)"

if [[ ! -d "$KOKORO_REPO/.git" ]]; then
  echo "→ Klone Jud/kokoro-coreml …"
  git clone --depth 1 https://github.com/Jud/kokoro-coreml.git "$KOKORO_REPO"
fi

echo "→ Installiere Export-Abhängigkeiten …"
KOKORO_SRC="$WORK/kokoro-main"
if [[ ! -d "$KOKORO_SRC/kokoro" ]]; then
  echo "  ↓ hexgrad/kokoro …"
  curl -fsSL "https://codeload.github.com/hexgrad/kokoro/zip/refs/heads/main" \
    -o "$WORK/kokoro-main.zip"
  unzip -q -o "$WORK/kokoro-main.zip" -d "$WORK"
fi
"$VENV/bin/pip" install -q coremltools huggingface_hub soundfile loguru transformers
"$VENV/bin/pip" install -q "misaki[en]>=0.9.4"
"$VENV/bin/pip" install -q --no-deps "$KOKORO_SRC"

# coremltools-Patch (Jud-Repo)
if [[ -f "$KOKORO_REPO/scripts/patch_coremltools.py" ]]; then
  "$VENV/bin/python" "$KOKORO_REPO/scripts/patch_coremltools.py" || true
fi

MODEL_DIR="$WORK/model"
mkdir -p "$MODEL_DIR"
hf_download "$HF_REPO" "$HF_CONFIG" "$MODEL_DIR/config.json"
hf_download "$HF_REPO" "$HF_MODEL" "$MODEL_DIR/model.pth"

EXPORT_DIR="$WORK/coreml-export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "→ Starte CoreML-Export …"
(
  cd "$KOKORO_REPO"
  PYTHONPATH=scripts "$VENV/bin/python" "$ROOT/Scripts/export_german_kokoro_coreml.py" \
    --kokoro-scripts "$KOKORO_REPO/scripts" \
    --config "$MODEL_DIR/config.json" \
    --weights "$MODEL_DIR/model.pth" \
    --lang-code "$LANG_CODE" \
    --output-dir "$EXPORT_DIR" \
    --skip-palettize
)

# Palettisierte oder rohe Modelle ins Bundle kopieren
pick_model() {
  local base="$1"
  if [[ -d "$EXPORT_DIR/${base}_pal8.mlpackage" ]]; then
    echo "${base}_pal8"
  elif [[ -d "$EXPORT_DIR/${base}.mlpackage" ]]; then
    echo "${base}"
  else
    echo "$base"
  fi
}

FE="$(pick_model kokoro_frontend)"
BE="$(pick_model kokoro_backend)"

for name in "$FE" "$BE"; do
  pkg="$EXPORT_DIR/${name}.mlpackage"
  compiled="$EXPORT_DIR/${name%.mlpackage}.mlmodelc"
  if [[ -d "$compiled" ]]; then
    echo "→ Kopiere ${name} …"
    rm -rf "$TARGET/${name/kokoro_frontend/kokoro_frontend}.mlmodelc" 2>/dev/null || true
  fi
done

# Kompilierte .mlmodelc aus Export übernehmen
if [[ -d "$EXPORT_DIR/kokoro_frontend.mlmodelc" ]]; then
  rm -rf "$TARGET/kokoro_frontend.mlmodelc"
  cp -R "$EXPORT_DIR/kokoro_frontend.mlmodelc" "$TARGET/"
fi
if [[ -d "$EXPORT_DIR/kokoro_backend.mlmodelc" ]]; then
  rm -rf "$TARGET/kokoro_backend.mlmodelc"
  cp -R "$EXPORT_DIR/kokoro_backend.mlmodelc" "$TARGET/"
fi

# Falls nur mlpackage: mit coremlcompiler kompilieren
if [[ ! -d "$TARGET/kokoro_frontend.mlmodelc" && -d "$EXPORT_DIR/${FE}.mlpackage" ]]; then
  echo "→ Kompiliere CoreML-Modelle …"
  xcrun coremlcompiler compile "$EXPORT_DIR/${FE}.mlpackage" "$TARGET/"
  xcrun coremlcompiler compile "$EXPORT_DIR/${BE}.mlpackage" "$TARGET/"
  # coremlcompiler benennt nach Modellname – ggf. umbenennen
  for compiled in "$TARGET"/*.mlmodelc; do
    base="$(basename "$compiled" .mlmodelc)"
    if [[ "$base" == *frontend* ]]; then
      mv "$compiled" "$TARGET/kokoro_frontend.mlmodelc"
    elif [[ "$base" == *backend* ]]; then
      mv "$compiled" "$TARGET/kokoro_backend.mlmodelc"
    fi
  done
fi

echo ""
echo "✓ Deutsches Kokoro-CoreML unter $TARGET"
echo "  Stimme: voices/${VOICE_NAME}.bin"
echo "  In Xcode: Ordner als blaue Ordnerreferenz unter Copy Bundle Resources."
