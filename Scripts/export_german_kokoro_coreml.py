#!/usr/bin/env python3
"""
Exportiert ein deutsch feinjustiertes Kokoro-PyTorch-Modell nach CoreML
(kokoro_frontend.mlmodelc + kokoro_backend.mlmodelc) via Jud/kokoro-coreml.

Voraussetzungen:
  - macOS mit Xcode (coremlcompiler)
  - Python-Venv mit torch, coremltools, kokoro (idark-Fork für DE)
  - Geklontes Jud/kokoro-coreml unter KOKORO_COREML_SCRIPTS

Beispiel:
  python Scripts/export_german_kokoro_coreml.py \\
    --kokoro-scripts /tmp/kokoro-coreml/scripts \\
    --config /tmp/thorsten/config.json \\
    --weights /tmp/thorsten/model.pth \\
    --output-dir Resources/Models/kokoro-de-export
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _patch_load_kokoro_model(scripts_dir: Path, config_path: Path, weights_path: Path, lang_code: str):
    """Ersetzt load_kokoro_model() in export_coreml durch deutsche Gewichte."""
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))

    import export_coreml as ec  # noqa: WPS433 – absichtlicher Side-Import
    from kokoro.istftnet import CustomSTFT

    def load_german_kokoro_model():
        from kokoro import KModel

        print(f"Lade deutsches Kokoro-Modell:\n  config={config_path}\n  weights={weights_path}")
        # KModel ist sprachneutral – für CoreML-Export reicht das Modell ohne KPipeline.
        model = KModel(
            repo_id="hexgrad/Kokoro-82M",
            config=str(config_path),
            model=str(weights_path),
        )
        model.eval()

        gen = model.decoder.generator
        gen.stft = CustomSTFT(
            filter_length=gen.stft.filter_length,
            hop_length=gen.stft.hop_length,
            win_length=gen.stft.win_length,
        )
        return None, model

    ec.load_kokoro_model = load_german_kokoro_model
    return ec


def main() -> None:
    parser = argparse.ArgumentParser(description="Deutsches Kokoro → CoreML exportieren")
    parser.add_argument(
        "--kokoro-scripts",
        type=Path,
        required=True,
        help="Pfad zu Jud/kokoro-coreml/scripts",
    )
    parser.add_argument("--config", type=Path, required=True, help="config.json des DE-Modells")
    parser.add_argument("--weights", type=Path, required=True, help=".pth Gewichte")
    parser.add_argument(
        "--lang-code",
        default="d",
        help="Kokoro-Sprachcode (Thorsten/kikiri: d oder de)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("Resources/Models/kokoro-de-export"),
        help="Zielverzeichnis für .mlmodelc",
    )
    parser.add_argument(
        "--skip-palettize",
        action="store_true",
        help="Keine 8-bit-Palettisierung (schneller, größere Dateien)",
    )
    args = parser.parse_args()

    for path in (args.kokoro_scripts, args.config, args.weights):
        if not path.exists():
            raise SystemExit(f"Pfad fehlt: {path}")

    os.makedirs(args.output_dir, exist_ok=True)

    # coreml_ops aus Jud-Repo registrieren
    from coreml_ops import register_missing_torch_ops  # noqa: WPS433

    register_missing_torch_ops()

    ec = _patch_load_kokoro_model(
        args.kokoro_scripts,
        args.config,
        args.weights,
        args.lang_code,
    )

    from reference import patch_pack_padded_sequence, patch_sinegen_for_production  # noqa: WPS433

    print("Lade Modell und starte CoreML-Export (kann 15–45 Min. dauern) …")
    pipeline, model = ec.load_kokoro_model()
    set_phases_fn = patch_sinegen_for_production(model)
    patch_pack_padded_sequence()

    ec.export_dynamic(
        pipeline,
        model,
        set_phases_fn,
        str(args.output_dir),
        verify=False,
    )

    if not args.skip_palettize:
        ec._export_palettized(str(args.output_dir))

    print(f"\n✓ Export abgeschlossen unter: {args.output_dir}")


if __name__ == "__main__":
    main()
