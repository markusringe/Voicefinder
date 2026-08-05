# Eingebettete On-Device-Modelle

Dieser Ordner wird als **blaue Ordnerreferenz** ins App-Bundle kopiert (`Models/…` im `.app`-Bundle).

## Aktive Modelle

| Ordner | Verwendung |
|--------|------------|
| `qwen3-1.7B-4bit` | Lokales MLX-Sprachmodell (Standard) |
| `openai_whisper-base` | WhisperKit Offline-STT (Simulator / Datei) |
| `piper-de` | Piper ONNX TTS (deutsche Stimmen) |

## Hinweis

Weitere Modellvarianten (z. B. Qwen2.5, Qwen3.5) gehören **nicht** in diesen Ordner, solange sie nicht aktiv genutzt werden. Gleichnamige Dateien wie `config.json` führen sonst zu Xcode-Build-Fehlern („Multiple commands produce …“), wenn der Ordner flach statt als Ordnerreferenz eingebunden ist.

Setup-Skripte liegen unter `Scripts/`.
