//
//  WhisperKitTranscriber.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import WhisperKit

final class WhisperKitTranscriber: SpeechToTextEngine {
    let partialTextStream: AsyncStream<String>
    let finalTextStream: AsyncStream<String>

    private let partialContinuation: AsyncStream<String>.Continuation
    private let finalContinuation: AsyncStream<String>.Continuation

    private var whisperKit: WhisperKit?

    init() {
        var partialCont: AsyncStream<String>.Continuation!
        self.partialTextStream = AsyncStream<String> { continuation in
            partialCont = continuation
        }
        self.partialContinuation = partialCont

        var finalCont: AsyncStream<String>.Continuation!
        self.finalTextStream = AsyncStream<String> { continuation in
            finalCont = continuation
        }
        self.finalContinuation = finalCont
    }

    func requestAuthorization() async -> Bool {
        true
    }

    func startStreaming() async throws {
        if whisperKit == nil {
            whisperKit = try await WhisperKit()
        }
    }

    func stopStreaming() async {
    }

    func transcribeFile(at path: String, language: String = "de") async throws -> String {
        if whisperKit == nil {
            whisperKit = try await WhisperKit()
        }

        guard let whisperKit else {
            throw NSError(domain: "WhisperKitTranscriber", code: -1)
        }

        let result = try await whisperKit.transcribe(
            audioPath: path,
            decodeOptions: DecodingOptions(language: language)
        )

        let text = result?.text ?? ""
        finalContinuation.yield(text)
        return text
    }
}
