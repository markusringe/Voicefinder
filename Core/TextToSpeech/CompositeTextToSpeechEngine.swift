//
//  CompositeTextToSpeechEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Piper-TTS – einzige Sprachausgabe (kein Apple-System-Fallback).
struct CompositeTextToSpeechEngine: TextToSpeechEngine {
    private let piper: PiperTextToSpeechEngine

    init(piper: PiperTextToSpeechEngine) {
        self.piper = piper
    }

    /// Aktualisiert Piper-Stimme und Geschwindigkeit aus den App-Einstellungen.
    func applyVoiceSettings(voice: PiperVoice, speed: Float) async {
        await piper.setVoice(voice)
        await piper.setSpeed(speed)
    }

    func speak(text: String) async throws {
        guard PiperModelProvider.isFullyBundled else {
            throw PiperTextToSpeechEngineError.notPrepared
        }

        let timeout = Self.speakTimeoutSeconds(for: text)
        NSLog("[Voicefinder] TTS: Piper startet … (Timeout %llu s)", timeout)
        try await speakPiperWithTimeout(text: text, seconds: timeout)
        NSLog("[Voicefinder] TTS: Piper fertig.")
    }

    /// Timeout ab Textlänge – Synthese plus Wiedergabe können >12 s dauern.
    nonisolated private static func speakTimeoutSeconds(for text: String) -> UInt64 {
        let chars = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        // Grob ~8 Zeichen/s gesprochen + Puffer für ONNX-Synthese.
        let estimated = UInt64(chars / 8) + 15
        return min(max(estimated, 25), 90)
    }

    /// Führt Piper-Sprache mit hartem Timeout aus.
    private func speakPiperWithTimeout(text: String, seconds: UInt64) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.piper.speak(text: text)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw PiperTextToSpeechEngineError.speakTimedOut
            }

            try await group.next()
            group.cancelAll()
        }
    }

    func speak(stream: AsyncStream<String>) async throws {
        var combined = ""
        for await chunk in stream {
            combined += chunk
        }
        try await speak(text: combined)
    }

    func stop() async {
        await piper.stop()
    }

    func releaseHeavyResourcesAfterSpeak() async {
        await piper.releaseHeavyResourcesAfterSpeak()
    }
}
