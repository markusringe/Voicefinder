#!/usr/bin/env bash
# Wartungs-Skript: lädt fehlende Piper-Stimmen für Entwickler nach (optional).
# Die App erwartet alle Stimmen fest unter Resources/Models/piper-de – kein Runtime-Download.
#
# Vor dem Build prüfen:
#   ./Scripts/verify-embedded-piper.sh
#
# Fehlende Stimmen nachladen (nur Entwicklung):
#   chmod +x Scripts/setup-piper-german.sh
#   ./Scripts/setup-piper-german.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Resources/Models/piper-de"
WORK="$ROOT/.build/piper-setup"
BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"

# Feste Stimmenliste – muss mit PiperVoice.swift übereinstimmen
ALL_VOICES=(
  "thorsten-medium:vits-piper-de_DE-thorsten-medium-int8:de_DE-thorsten-medium.onnx"
  "thorsten-low:vits-piper-de_DE-thorsten-low-int8:de_DE-thorsten-low.onnx"
  "kerstin-low:vits-piper-de_DE-kerstin-low-int8:de_DE-kerstin-low.onnx"
  "eva_k-x_low:vits-piper-de_DE-eva_k-x_low-int8:de_DE-eva_k-x_low.onnx"
)

SELECTED=("$@")
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  SELECTED=(thorsten-medium thorsten-low kerstin-low eva_k-x_low)
fi

mkdir -p "$TARGET/voices" "$WORK"

download_archive() {
  local archive="$1"
  local dest_dir="$2"
  local url="${BASE_URL}/${archive}.tar.bz2"
  local marker="${dest_dir}/.complete"

  if [[ -f "$marker" ]]; then
    echo "  ✓ bereits vorhanden: ${archive}"
    return 0
  fi

  echo "  ↓ ${archive}.tar.bz2 …"
  local tmp="${WORK}/${archive}.tar.bz2"
  curl -fL "$url" -o "$tmp"
  mkdir -p "$dest_dir"
  tar xjf "$tmp" -C "$dest_dir" --strip-components=0
  rm -f "$tmp"
  touch "$marker"
}

echo "→ Ziel: $TARGET"
echo "→ Stimmen: ${SELECTED[*]}"
echo ""

for voice_spec in "${ALL_VOICES[@]}"; do
  IFS=':' read -r folder archive onnx_name <<< "$voice_spec"

  wanted=0
  for sel in "${SELECTED[@]}"; do
    if [[ "$sel" == "$folder" ]]; then
      wanted=1
      break
    fi
  done
  [[ "$wanted" -eq 1 ]] || continue

  echo "=== ${folder} ==="
  extract_root="${WORK}/${archive}"
  download_archive "$archive" "$extract_root"

  voice_dest="${TARGET}/voices/${folder}"
  mkdir -p "$voice_dest"

  src_dir="$extract_root"
  if [[ -d "${extract_root}/${archive}" ]]; then
    src_dir="${extract_root}/${archive}"
  fi

  cp -f "${src_dir}/${onnx_name}" "${voice_dest}/${onnx_name}"
  cp -f "${src_dir}/tokens.txt" "${voice_dest}/tokens.txt"

  if [[ ! -d "${TARGET}/espeak-ng-data" ]]; then
    echo "  → espeak-ng-data kopieren …"
    cp -R "${src_dir}/espeak-ng-data" "${TARGET}/espeak-ng-data"
  fi

  echo "  ✓ ${folder} → voices/${folder}/"
  echo ""
done

if [[ ! -d "${TARGET}/espeak-ng-data" ]]; then
  echo "Fehler: espeak-ng-data fehlt – mindestens eine Stimme muss erfolgreich geladen werden."
  exit 1
fi

echo "✓ Piper-Modelle unter ${TARGET}"
echo ""
echo "Prüfen: ./Scripts/verify-embedded-piper.sh"
