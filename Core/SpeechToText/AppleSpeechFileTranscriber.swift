//
//  AppleSpeechFileTranscriber.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import Speech

/// Fehler bei der Apple-Spracherkennung für Audiodateien.
enum AppleSpeechFileTranscriberError: LocalizedError, Sendable {
    case recognizerUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Apple-Spracherkennung ist für Datei-Transkription nicht verfügbar."
        case .emptyTranscript:
            "Apple Speech hat keinen Text in der Audiodatei erkannt."
        }
    }
}

/// Transkribiert Audiodateien mit `SFSpeechURLRecognitionRequest`.
///
/// Fallback für Intel-Mac-Simulator (x86_64): WhisperKit-CoreML hängt dort beim Text-Decoder,
/// Apple Speech funktioniert für Sample- und Datei-Tests zuverlässiger.
actor AppleSpeechFileTranscriber: SpeechToTextEngine, FileTranscribing {
    private(set) var partialTextStream: AsyncStream<String>
    private(set) var finalTextStream: AsyncStream<String>
    private(set) var audioLevelStream: AsyncStream<Float>

    private var partialContinuation: AsyncStream<String>.Continuation
    private var finalContinuation: AsyncStream<String>.Continuation

    private let locale: Locale

    init(locale: Locale = Locale(identifier: "de-DE")) {
        self.locale = locale

        let partialPair = AsyncStream<String>.makeStream()
        self.partialTextStream = partialPair.stream
        self.partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        self.finalTextStream = finalPair.stream
        self.finalContinuation = finalPair.continuation

        self.audioLevelStream = AudioLevelNormalizer.emptyStream()
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startStreaming() async throws {
        resetStreams()
    }

    func stopStreaming() async {
        partialContinuation.finish()
        finalContinuation.finish()
    }

    func transcribeFile(at path: String, language: String = "de") async throws -> String {
        let locale = Self.locale(forLanguageCode: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AppleSpeechFileTranscriberError.recognizerUnavailable
        }

        let fileURL = URL(fileURLWithPath: path)
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        NSLog("[Voicefinder] Apple Speech Datei-Transkription start – %@", path)

        let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }

                if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }

                didResume = true
                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: transcript)
            }
        }

        NSLog("[Voicefinder] Apple Speech Datei-Transkription ende – Länge %d", text.count)

        guard !text.isEmpty else {
            throw AppleSpeechFileTranscriberError.emptyTranscript
        }

        finalContinuation.yield(text)
        return text
    }

    /// Mappt Sprachcodes wie „de“ auf passende Apple-Speech-Locales.
    nonisolated private static func locale(forLanguageCode language: String) -> Locale {
        switch language.lowercased() {
        case "de":
            Locale(identifier: "de-DE")
        case "en":
            Locale(identifier: "en-US")
        default:
            Locale(identifier: language)
        }
    }

    private func resetStreams() {
        let partialPair = AsyncStream<String>.makeStream()
        partialTextStream = partialPair.stream
        partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        finalTextStream = finalPair.stream
        finalContinuation = finalPair.continuation
    }
}
