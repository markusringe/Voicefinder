//
//  WhisperKitTranscriber.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//
import Foundation
import WhisperKit

/// WhisperKit-basierte STT-Implementierung mit lokal gebündeltem Offline-Modell.
final class WhisperKitTranscriber: SpeechToTextEngine, FileTranscribing {
    let partialTextStream: AsyncStream<String>
    let finalTextStream: AsyncStream<String>
    let audioLevelStream: AsyncStream<Float>

    private let partialContinuation: AsyncStream<String>.Continuation
    private let finalContinuation: AsyncStream<String>.Continuation

    private var whisperKit: WhisperKit?
    private let modelName: String

    init(modelName: String = WhisperKitModelProvider.defaultModelName) {
        self.modelName = modelName

        let partialPair = AsyncStream<String>.makeStream()
        self.partialTextStream = partialPair.stream
        self.partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        self.finalTextStream = finalPair.stream
        self.finalContinuation = finalPair.continuation

        // Nur Datei-Transkription – kein Live-Mikrofon-Pegel.
        self.audioLevelStream = AudioLevelNormalizer.emptyStream()
    }

    func requestAuthorization() async -> Bool {
        true
    }

    func startStreaming() async throws {
        _ = try await ensureInitialized()
    }

    func stopStreaming() async {
        partialContinuation.finish()
        finalContinuation.finish()
    }

    func transcribeFile(at path: String, language: String = "de") async throws -> String {
        let whisperKit = try await ensureInitialized()

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            wordTimestamps: false
        )

        let results = try await whisperKit.transcribe(
            audioPath: path,
            decodeOptions: options
        )

        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            finalContinuation.yield(text)
        }

        return text
    }

    /// Lädt WhisperKit vorab (Startbildschirm / Sample-Tests).
    func prepareModelsIfNeeded() async throws {
        _ = try await ensureInitialized()
    }

    /// Initialisiert WhisperKit einmalig mit dem lokal im App-Bundle liegenden Modell.
    private func ensureInitialized() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        let modelFolderURL = try WhisperKitModelProvider.bundledModelFolderURL(modelName: modelName)
        try WhisperKitModelProvider.validateBundledModel(at: modelFolderURL)

        // download: false verhindert Hugging-Face-Downloads; Tokenizer liegt im selben Ordner.
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolderURL.path,
            tokenizerFolder: modelFolderURL,
            download: false
        )

        let instance = try await WhisperKit(config)
        self.whisperKit = instance
        return instance
    }
}
