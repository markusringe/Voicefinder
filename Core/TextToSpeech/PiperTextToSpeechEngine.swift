//
//  PiperTextToSpeechEngine.swift
//  Voicefinder
//
//  On-Device-TTS mit Piper-ONNX über Sherpa-ONNX – Deutsch-first.
//

import Foundation
import SherpaOnnx

// MARK: - Sherpa-ONNX Bridge

/// Ergebnis einer Piper-Synthese: Mono-Float-PCM und Abtastrate.
private struct SherpaPiperSynthesisResult: Sendable {
    let samples: [Float]
    let sampleRate: Int
}

/// Lebenszyklus eines Sherpa-ONNX-Offline-TTS-Handles für Piper-Modelle.
/// Die Swift-Hilfsklassen im SherpaOnnx-SPM-Paket sind `internal` – daher direkte C-API.
private final class SherpaPiperSynthesizer: @unchecked Sendable {
    private let tts: OpaquePointer

    init(paths: PiperVoiceResourcePaths) throws {
        guard let handle = Self.createEngine(paths: paths) else {
            throw PiperTextToSpeechEngineError.initFailed
        }
        tts = handle
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    func synthesize(text: String, speed: Float) throws -> SherpaPiperSynthesisResult {
        try text.withCString { textPointer in
            var generationConfig = SherpaOnnxGenerationConfig(
                silence_scale: 0,
                speed: speed,
                sid: 0,
                reference_audio: nil,
                reference_audio_len: 0,
                reference_sample_rate: 0,
                reference_text: nil,
                num_steps: 0,
                extra: nil
            )

            let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? = withUnsafePointer(to: &generationConfig) { configPointer in
                SherpaOnnxOfflineTtsGenerateWithConfig(
                    tts,
                    textPointer,
                    configPointer,
                    nil,
                    nil
                )
            }

            guard let audio else {
                throw PiperModelProviderError.synthesisFailed
            }
            defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

            let sampleCount = Int(audio.pointee.n)
            let sampleRate = Int(audio.pointee.sample_rate)

            guard sampleCount > 0, let rawSamples = audio.pointee.samples else {
                throw PiperModelProviderError.synthesisFailed
            }

            let samples = Array(UnsafeBufferPointer(start: rawSamples, count: sampleCount))
            return SherpaPiperSynthesisResult(samples: samples, sampleRate: sampleRate)
        }
    }

    private static func createEngine(paths: PiperVoiceResourcePaths) -> OpaquePointer? {
        paths.model.withCString { modelPointer -> OpaquePointer? in
            paths.tokens.withCString { tokensPointer -> OpaquePointer? in
                paths.espeakDataDir.withCString { dataPointer -> OpaquePointer? in
                    var config = SherpaOnnxOfflineTtsConfig()
                    config.model.vits.model = modelPointer
                    config.model.vits.lexicon = nil
                    config.model.vits.tokens = tokensPointer
                    config.model.vits.data_dir = dataPointer
                    config.model.num_threads = 2

                    guard let created = SherpaOnnxCreateOfflineTts(&config) else {
                        return nil
                    }
                    return OpaquePointer(UnsafeRawPointer(created))
                }
            }
        }
    }
}

// MARK: - Piper TTS Engine

/// Piper-TTS-Engine (Sherpa-ONNX Offline TTS, VITS-Piper-Modelle).
actor PiperTextToSpeechEngine: TextToSpeechEngine {
    private let player = PiperPCMPlayer()
    private var synthesizer: SherpaPiperSynthesizer?
    private var loadedVoiceID: String?
    private var selectedVoice: PiperVoice = PiperModelProvider.resolvedVoice()
    private var speed: Float = AppSettingsStore.piperSpeed
    private var preparationTask: Task<Void, Error>?
    private var speakTask: Task<Void, Error>?

    /// True, wenn das aktuelle Modell geladen ist.
    var isReady: Bool {
        synthesizer != nil
    }

    /// True, wenn Piper-Stimmen im App-Bundle liegen.
    var isBundled: Bool {
        PiperModelProvider.isBundled
    }

    /// Aktuell gewählte Stimme (UI / Einstellungen).
    var currentVoice: PiperVoice {
        selectedVoice
    }

    /// Aktuelle Sprechgeschwindigkeit (1.0 = normal).
    var currentSpeed: Float {
        speed
    }

    /// Setzt die Stimme – lädt das ONNX-Modell beim nächsten `speak` neu.
    func setVoice(_ voice: PiperVoice) async {
        selectedVoice = voice
        if loadedVoiceID != voice.rawValue {
            synthesizer = nil
            loadedVoiceID = nil
        }
    }

    /// Setzt die Sprechgeschwindigkeit (0.5 … 2.0 – Sherpa-ONNX `speed`-Parameter).
    func setSpeed(_ speed: Float) async {
        self.speed = min(max(speed, 0.5), 2.0)
    }

    /// Lädt das gewählte Piper-Modell vor (Startup / Vorschau).
    func prepareIfNeeded() async throws {
        if synthesizer != nil, loadedVoiceID == selectedVoice.rawValue { return }

        if let preparationTask {
            try await preparationTask.value
            return
        }

        let task = Task(priority: .userInitiated) {
            try await self.loadEngine()
        }
        preparationTask = task

        do {
            try await task.value
            preparationTask = nil
        } catch {
            preparationTask = nil
            throw error
        }
    }

    func speak(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speakTask?.cancel()
        let task = Task<Void, Error> {
            try await self.performSpeak(trimmed)
        }
        speakTask = task

        defer { speakTask = nil }

        do {
            try await task.value
        } catch is CancellationError {
            throw PiperTextToSpeechEngineError.cancelled
        }
    }

    func speak(stream: AsyncStream<String>) async throws {
        var combined = ""
        for await chunk in stream {
            guard !Task.isCancelled else {
                throw PiperTextToSpeechEngineError.cancelled
            }
            combined += chunk
        }
        try await speak(text: combined)
    }

    func stop() async {
        speakTask?.cancel()
        speakTask = nil
        await player.stop()
    }

    /// Entlädt schwere ONNX-Ressourcen zwischen Runden (Speicher für LLM freigeben).
    func releaseHeavyResourcesAfterSpeak() async {
        await stop()
        preparationTask?.cancel()
        preparationTask = nil
        synthesizer = nil
        loadedVoiceID = nil
    }

    private func performSpeak(_ trimmed: String) async throws {
        try Task.checkCancellation()
        try await prepareIfNeeded()
        try Task.checkCancellation()

        guard let synthesizer else {
            throw PiperTextToSpeechEngineError.notPrepared
        }

        let currentSpeed = speed
        let synthesisStart = CFAbsoluteTimeGetCurrent()
        let result = try await synthesizeOffMainThread(
            text: trimmed,
            speed: currentSpeed,
            using: synthesizer
        )
        let synthesisSeconds = CFAbsoluteTimeGetCurrent() - synthesisStart
        NSLog(
            "[Voicefinder] Piper Synthese fertig (%.2f s, %d Samples @ %d Hz)",
            synthesisSeconds,
            result.samples.count,
            result.sampleRate
        )

        try Task.checkCancellation()
        try await player.play(samples: result.samples, sampleRate: result.sampleRate)
    }

    private func loadEngine() async throws {
        guard PiperModelProvider.isSupported else {
            throw PiperTextToSpeechEngineError.notSupported
        }

        selectedVoice = PiperModelProvider.resolvedVoice()
        speed = AppSettingsStore.piperSpeed

        let paths = try PiperModelProvider.paths(for: selectedVoice)
        let engine = try await createEngineOffMainThread(paths: paths)

        synthesizer = engine
        loadedVoiceID = selectedVoice.rawValue
        let voiceLabel = selectedVoice.displayName
        NSLog("[Voicefinder] Piper bereit: \(voiceLabel)")
    }

    /// Erstellt Sherpa-ONNX auf einem Hintergrund-Thread (blockierende Initialisierung).
    private func createEngineOffMainThread(paths: PiperVoiceResourcePaths) async throws -> SherpaPiperSynthesizer {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let engine = try SherpaPiperSynthesizer(paths: paths)
                    continuation.resume(returning: engine)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Führt Piper-Synthese auf einem Hintergrund-Thread aus.
    private func synthesizeOffMainThread(
        text: String,
        speed: Float,
        using synthesizer: SherpaPiperSynthesizer
    ) async throws -> SherpaPiperSynthesisResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try synthesizer.synthesize(text: text, speed: speed)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Fehler der Piper-TTS-Engine.
enum PiperTextToSpeechEngineError: LocalizedError, Sendable, Equatable {
    case notPrepared
    case notSupported
    case notBundled
    case cancelled
    case initFailed
    case playbackFailed
    case speakTimedOut

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            "Piper ist noch nicht bereit."
        case .notSupported:
            "Piper wird auf dieser Plattform nicht unterstützt."
        case .notBundled:
            PiperModelProviderError.notBundled.errorDescription
        case .cancelled:
            "Piper-Sprachausgabe wurde unterbrochen."
        case .initFailed:
            "Piper-Modell konnte nicht initialisiert werden (Pfade prüfen)."
        case .playbackFailed:
            "Piper-Audio konnte nicht abgespielt werden."
        case .speakTimedOut:
            "Piper-Sprachausgabe hat zu lange gedauert."
        }
    }
}
