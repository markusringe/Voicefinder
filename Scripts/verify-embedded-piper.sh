#!/usr/bin/env bash
# Build-Check: alle eingebetteten Piper-Stimmen müssen im Repository liegen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ROOT="$ROOT/Resources/Models/piper-de"

VOICES=(
  "thorsten-medium:de_DE-thorsten-medium.onnx"
  "thorsten-low:de_DE-thorsten-low.onnx"
  "kerstin-low:de_DE-kerstin-low.onnx"
  "eva_k-x_low:de_DE-eva_k-x_low.onnx"
)

missing=()

if [[ ! -d "$BUNDLE_ROOT/espeak-ng-data" ]]; then
  missing+=("espeak-ng-data/")
fi

for entry in "${VOICES[@]}"; do
  folder="${entry%%:*}"
  onnx="${entry##*:}"
  voice_dir="$BUNDLE_ROOT/voices/$folder"
  if [[ ! -f "$voice_dir/$onnx" ]]; then
    missing+=("voices/$folder/$onnx")
  fi
  if [[ ! -f "$voice_dir/tokens.txt" ]]; then
    missing+=("voices/$folder/tokens.txt")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "error: Eingebettete Piper-Stimmen unvollständig unter $BUNDLE_ROOT" >&2
  echo "       Fehlend: ${missing[*]}" >&2
  echo "       Die ONNX-Dateien müssen fest im Repo unter Resources/Models/piper-de liegen." >&2
  exit 1
fi

echo "✓ Alle ${#VOICES[@]} Piper-Stimmen eingebettet ($BUNDLE_ROOT)"
