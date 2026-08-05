#!/usr/bin/env bash
# Build-Check: eingebettetes LLM muss im Repository liegen, bevor die App gebaut wird.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="$ROOT/Resources/Models/qwen3-1.7B-4bit"
MARKERS=(config.json model.safetensors tokenizer.json)

missing=()
for file in "${MARKERS[@]}"; do
  if [[ ! -f "$MODEL_DIR/$file" ]]; then
    missing+=("$file")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "error: Eingebettetes LLM fehlt unter $MODEL_DIR" >&2
  echo "       Fehlend: ${missing[*]}" >&2
  echo "       Einmalig ausführen: Scripts/setup-llm-bundle.sh" >&2
  exit 1
fi

echo "✓ Eingebettetes LLM vorhanden ($MODEL_DIR)"
