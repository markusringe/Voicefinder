#!/usr/bin/env python3
"""
Konvertiert ein Kokoro-Voice-Pack (.pt) in das binäre VoiceStore-Format (.bin)
für Jud/kokoro-coreml.

Unterstützt typische Formate aus Thorsten-Voice/Kokoro und kikiri-tts:
  - Tensor (510, 1, 256) oder (510, 256)
  - Dict mit numerischen Schlüsseln und/oder "embedding"

Ausgabeformat (VoiceStore):
  Header: num_keys (UInt16 LE), dim (UInt16 LE)
  Pro Eintrag: key_id (UInt16 LE) + dim × Float32 LE
  key_id 0 = generisches Embedding, 1..510 = längenindexiert (Token-Anzahl - 1)
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

import numpy as np

try:
    import torch
except ImportError as exc:  # pragma: no cover
    print("Fehler: PyTorch fehlt. Installiere mit: pip install torch", file=sys.stderr)
    raise SystemExit(1) from exc


def _to_float32_matrix(raw) -> np.ndarray:
    """Normalisiert verschiedene PyTorch-/NumPy-Formate auf (N, 256)."""
    if isinstance(raw, dict):
        rows: dict[int, np.ndarray] = {}
        generic: np.ndarray | None = None

        for key, value in raw.items():
            arr = np.asarray(value, dtype=np.float32).reshape(-1)
            if key in ("embedding", "generic", 0, "0"):
                generic = arr[:256]
                continue
            try:
                idx = int(key)
            except (TypeError, ValueError):
                continue
            rows[idx] = arr[:256]

        if not rows and generic is not None:
            return generic.reshape(1, -1)

        max_idx = max(rows.keys()) if rows else 0
        dim = 256
        matrix = np.zeros((max_idx + 1, dim), dtype=np.float32)
        for idx, vec in rows.items():
            matrix[idx] = vec[:dim]
        if generic is not None:
            matrix[0] = generic[:dim]
        return matrix

    tensor = raw
    if hasattr(tensor, "detach"):
        tensor = tensor.detach().cpu().numpy()
    arr = np.asarray(tensor, dtype=np.float32)

    if arr.ndim == 3 and arr.shape[1] == 1:
        arr = arr.squeeze(1)
    if arr.ndim == 1:
        arr = arr.reshape(1, -1)
    if arr.ndim != 2:
        raise ValueError(f"Unerwartete Voice-Form: {arr.shape}")

    return arr


def write_voice_bin(matrix: np.ndarray, output_path: Path) -> None:
    """Schreibt das VoiceStore-Binärformat."""
    if matrix.shape[1] != 256:
        raise ValueError(f"Erwarte 256-dim Embeddings, erhalten: {matrix.shape[1]}")

    num_rows = matrix.shape[0]
    # key 0 = generic (Zeile 0), keys 1..num_rows-1 = längenindexiert
    keys: dict[int, np.ndarray] = {0: matrix[0]}
    for i in range(1, num_rows):
        keys[i] = matrix[i]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as handle:
        handle.write(struct.pack("<HH", len(keys), 256))
        for key_id in sorted(keys.keys()):
            vec = keys[key_id].astype(np.float32)
            handle.write(struct.pack("<H", key_id))
            handle.write(vec.tobytes())

    print(f"✓ Voice geschrieben: {output_path} ({len(keys)} Einträge, dim=256)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Kokoro .pt Voice-Pack → VoiceStore .bin konvertieren"
    )
    parser.add_argument("input_pt", type=Path, help="Pfad zur .pt Voice-Datei")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        required=True,
        help="Zielpfad für die .bin-Datei",
    )
    args = parser.parse_args()

    if not args.input_pt.is_file():
        raise SystemExit(f"Eingabedatei fehlt: {args.input_pt}")

    voice = torch.load(args.input_pt, map_location="cpu", weights_only=False)
    matrix = _to_float32_matrix(voice)
    write_voice_bin(matrix, args.output)


if __name__ == "__main__":
    main()
