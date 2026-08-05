//
//  CompositeSpeechToTextEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Kombiniert Live-Mikrofon-STT mit Offline-Datei-Transkription (WhisperKit).
///
/// - Live-Eingabe: `AppleSpeechTranscriber` (Gerät) oder `WhisperKitRecordingTranscriber` (Simulator)
/// - Sample-/Datei-Transkription: `WhisperKitTranscriber`
actor CompositeSpeechToTextEngine: SpeechToTextEngine, FileTranscribing, StopFinalizingSpeechToTextEngine,
    PausableSpeechToTextEngine {
    private let liveEngine: any SpeechToTextEngine
    private let fileEngine: any FileTranscribing
    private let whisperFileEngine: WhisperKitTranscriber?

    init(
        liveEngine: any SpeechToTextEngine,
        fileEngine: any FileTranscribing,
        whisperFileEngine: WhisperKitTranscriber? = nil
    ) {
        self.liveEngine = liveEngine
        self.fileEngine = fileEngine
        self.whisperFileEngine = whisperFileEngine
        // Platzhalter bis startStreaming() die echten Live-Streams vom Unter-Engine übernimmt.
        self.partialTextStream = Self.emptyStringStream
        self.finalTextStream = Self.emptyStringStream
        self.audioLevelStream = Self.emptyLevelStream
    }

    private static let emptyStringStream = AsyncStream<String> { $0.finish() }
    private static let emptyLevelStream = AsyncStream<Float> { $0.finish() }

    private(set) var partialTextStream: AsyncStream<String>
    private(set) var finalTextStream: AsyncStream<String>
    private(set) var audioLevelStream: AsyncStream<Float>

    func requestAuthorization() async -> Bool {
        async let liveGranted = liveEngine.requestAuthorization()
        async let fileGranted = fileEngine.requestAuthorization()
        let (live, file) = await (liveGranted, fileGranted)
        return live && file
    }

    func startStreaming() async throws {
        try await liveEngine.startStreaming()
        partialTextStream = await liveEngine.partialTextStream
        finalTextStream = await liveEngine.finalTextStream
        audioLevelStream = await liveEngine.audioLevelStream
    }

    func stopStreaming() async {
        await liveEngine.stopStreaming()
    }

    func pauseStreaming() async {
        if let pausable = liveEngine as? PausableSpeechToTextEngine {
            await pausable.pauseStreaming()
        }
    }

    func resumeStreaming() async throws {
        if let pausable = liveEngine as? PausableSpeechToTextEngine {
            try await pausable.resumeStreaming()
        }
    }

    func stopStreamingAndFinalize() async -> String? {
        if let finalizer = liveEngine as? StopFinalizingSpeechToTextEngine {
            return await finalizer.stopStreamingAndFinalize()
        }
        await liveEngine.stopStreaming()
        return nil
    }

    func transcribeFile(at path: String, language: String = "de") async throws -> String {
        // Mikrofon und Apple-Speech freigeben, damit WhisperKit die Audio-Hardware nutzen kann.
        await liveEngine.stopStreaming()
        await AudioSessionCoordinator.shared.deactivate()
        return try await fileEngine.transcribeFile(at: path, language: language)
    }

    /// Lädt das WhisperKit-Modell im Hintergrund vor (ca. 4–5 s), damit Sample-Tests schneller reagieren.
    func prepareOfflineModelsIfNeeded() async throws {
        try await whisperFileEngine?.prepareModelsIfNeeded()
    }
}
