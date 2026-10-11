#!/usr/bin/env python3
"""Automatisierter Sprachtest: spielt Äußerungen über die Mac-Lautsprecher zum iPhone ab.

Erzeugt jede Äußerung per macOS-`say`, startet Voicefinder per `devicectl` mit Live-Log,
wartet, bis die App zuhört, spielt die Äußerung per `afplay` ab und misst anhand des Logs:
erkannter Text, Antwort und Latenzen ab Satzende (Ende der Wiedergabe).

Voraussetzungen:
  - Debug-Build von Voicefinder auf dem iPhone installiert (Debug-Logs nötig)
  - iPhone per Kabel verbunden und entsperrt, Mac-Lautsprecher hörbar nahe am iPhone

Beispiel:
  ./Scripts/voice-test.py --device 00008140-00163C113E09801C
  ./Scripts/voice-test.py --device <id> --scenario Scripts/voice-test-scenarios/standard.txt --voice Anna
"""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import queue
import re
import subprocess
import sys
import threading
import time
import unicodedata
import wave

BUNDLE_ID = "mbk.Voicefinder"
LOG_PREFIX = "[Voicefinder] "


class DeviceLog:
    """Liest das Konsolen-Log der App zeilenweise mit Ankunftszeit (Mac-Uhr)."""

    def __init__(self, device: str, raw_log_path: pathlib.Path, app_args: list[str]):
        command = [
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", device, "--terminate-existing", "--console", BUNDLE_ID,
        ]
        if app_args:
            command += ["--", *app_args]
        self.raw_log = raw_log_path.open("w", encoding="utf-8")
        self.process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        self.events: queue.Queue[tuple[float, str]] = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.raw_log.write(line)
            self.raw_log.flush()
            if LOG_PREFIX in line:
                message = line.split(LOG_PREFIX, 1)[1].rstrip("\n")
                self.events.put((time.monotonic(), message))

    def drain(self) -> None:
        while not self.events.empty():
            self.events.get_nowait()

    def wait_for(self, predicate, timeout: float, collect: list | None = None):
        """Wartet auf eine Log-Zeile, für die `predicate` wahr ist. Sammelt alle Zeilen optional."""
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            try:
                stamp, message = self.events.get(timeout=remaining)
            except queue.Empty:
                return None
            if collect is not None:
                collect.append((stamp, message))
            if predicate(message):
                return stamp, message

    def close(self) -> None:
        self.process.terminate()
        self.raw_log.close()


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w\s]", " ", text).split())


def synthesize(utterances: list[str], voice: str, rate: int, out_dir: pathlib.Path) -> list[pathlib.Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for index, text in enumerate(utterances, start=1):
        path = out_dir / f"{index:02d}.wav"
        subprocess.run(
            ["say", "-v", voice, "-r", str(rate), "--data-format=LEI16@22050", "-o", str(path), text],
            check=True,
        )
        files.append(path)
    return files


def trailing_silence(path: pathlib.Path, threshold: int = 300) -> float:
    """Dauer der Stille am Dateiende – `say` hängt Stille an, das letzte Wort endet früher."""
    with wave.open(str(path), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
        rate = wav.getframerate()
    samples = memoryview(frames).cast("h")
    last_loud = len(samples) - 1
    while last_loud > 0 and abs(samples[last_loud]) < threshold:
        last_loud -= 1
    return (len(samples) - 1 - last_loud) / rate


def first(collected: list[tuple[float, str]], prefix: str, after: float | None = None):
    for stamp, message in collected:
        if message.startswith(prefix) and (after is None or stamp >= after):
            return stamp, message
    return None


def seconds(value: float | None) -> str:
    return "–" if value is None else f"{value:.2f} s"


def run_turn(log: DeviceLog, text: str, audio: pathlib.Path, turn_timeout: float) -> dict:
    collected: list[tuple[float, str]] = []
    log.drain()
    subprocess.run(["afplay", str(audio)], check=True)
    # Satzende = Ende des letzten Worts, nicht Ende der Datei.
    speech_end = time.monotonic() - trailing_silence(audio)

    # Runde endet mit „TTS fertig“; ohne Pipeline-Start innerhalb von 6 s wurde die Äußerung verworfen.
    started = log.wait_for(lambda m: m.startswith("Pipeline-Start:"), timeout=6.0, collect=collected)
    if started is not None:
        log.wait_for(lambda m: m == "TTS fertig.", timeout=turn_timeout, collect=collected)
    else:
        log.wait_for(lambda m: False, timeout=0.5, collect=collected)

    pipeline = first(collected, "Pipeline-Start:")
    token = first(collected, "MLX erstes Token")
    audio_start = first(collected, "Piper Synthese fertig")
    answer = first(collected, "Antwort (Debug):")
    echo = first(collected, "Echo erkannt")

    recognized = pipeline[1].split(":", 1)[1].strip() if pipeline else ""
    if pipeline is None:
        status = "verworfen (Echo)" if echo else "nicht erkannt"
    elif normalize(recognized) == normalize(text):
        status = "ok"
    elif normalize(text).endswith(normalize(recognized)):
        status = "Anfang abgeschnitten"
    else:
        status = "abweichend"

    return {
        "spoken": text,
        "recognized": recognized,
        "answer": answer[1].split(":", 1)[1].strip() if answer else "",
        "status": status,
        "to_pipeline": pipeline[0] - speech_end if pipeline else None,
        "to_token": token[0] - speech_end if token else None,
        "to_audio": audio_start[0] - speech_end if audio_start else None,
    }


def write_report(results: list[dict], path: pathlib.Path, voice: str) -> str:
    lines = [
        f"# Voicefinder Sprachtest – {dt.datetime.now():%Y-%m-%d %H:%M}",
        "",
        f"Stimme: {voice} · Zeiten ab Ende des letzten Worts bis zum Ereignis im App-Log.",
        "",
        "| # | Gesprochen | Erkannt | Status | → Pipeline | → 1. Token | → Audio | Antwort |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for index, r in enumerate(results, start=1):
        answer = r["answer"].replace("|", "/")
        lines.append(
            f"| {index} | {r['spoken']} | {r['recognized'] or '–'} | {r['status']} | "
            f"{seconds(r['to_pipeline'])} | {seconds(r['to_token'])} | {seconds(r['to_audio'])} | {answer or '–'} |"
        )

    audio = [r["to_audio"] for r in results if r["to_audio"] is not None]
    ok = sum(1 for r in results if r["status"] == "ok")
    lines += [
        "",
        f"Vollständig erkannt: {ok}/{len(results)}",
    ]
    if audio:
        lines.append(f"Satzende → Audio: Median {sorted(audio)[len(audio) // 2]:.2f} s, min {min(audio):.2f} s, max {max(audio):.2f} s")
    report = "\n".join(lines) + "\n"
    path.write_text(report, encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", required=True, help="iPhone-UDID (xcrun devicectl list devices)")
    parser.add_argument("--scenario", default=str(pathlib.Path(__file__).parent / "voice-test-scenarios" / "standard.txt"))
    parser.add_argument("--voice", default="Anna", help="macOS-Stimme (say -v '?' | grep de_DE)")
    parser.add_argument("--rate", type=int, default=175, help="Sprechtempo in Wörtern pro Minute")
    parser.add_argument("--gap", type=float, default=0.8, help="Pause nach KI-Antwort, bevor gesprochen wird (s)")
    parser.add_argument("--turn-timeout", type=float, default=40.0)
    parser.add_argument("--out", default="build/voice-test", help="Ausgabeordner für Audio, Log und Bericht")
    parser.add_argument("--app-arg", action="append", default=[], help="Launch-Argument für die App (mehrfach möglich)")
    args = parser.parse_args()

    utterances = [
        line.strip() for line in pathlib.Path(args.scenario).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    run_dir = pathlib.Path(args.out) / dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    print(f"Erzeuge {len(utterances)} Äußerungen mit Stimme {args.voice} …")
    files = synthesize(utterances, args.voice, args.rate, run_dir / "audio")

    print("Starte Voicefinder auf dem iPhone …")
    log = DeviceLog(args.device, run_dir / "device.log", args.app_arg)
    try:
        if log.wait_for(lambda m: m.startswith("STT Eingang"), timeout=180) is None:
            print("App hört nicht zu (kein „STT Eingang“ im Log). iPhone entsperrt? Debug-Build installiert?")
            return 1
        time.sleep(1.5)

        results = []
        for index, (text, audio) in enumerate(zip(utterances, files), start=1):
            print(f"[{index}/{len(utterances)}] » {text}")
            result = run_turn(log, text, audio, args.turn_timeout)
            print(f"    erkannt: {result['recognized'] or '–'}  [{result['status']}]  Audio nach {seconds(result['to_audio'])}")
            print(f"    Antwort: {result['answer'] or '–'}")
            results.append(result)
            time.sleep(args.gap)
    finally:
        log.close()

    report_path = run_dir / "bericht.md"
    print()
    print(write_report(results, report_path, args.voice))
    print(f"Bericht: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
