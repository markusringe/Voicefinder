//
//  AppleSpeechSynthesizerEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

@preconcurrency import AVFoundation
import Foundation

/// Apple-System-TTS auf Basis von `AVSpeechSynthesizer`.
///
/// Fallback, wenn Piper noch nicht bereit ist oder fehlschlägt.
@MainActor
final class AppleSpeechSynthesizerEngine: TextToSpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechSynthesisDelegate?

    /// Im Simulator kann `AVSpeechSynthesizer` hängen bleiben – dann lieber abbrechen.
    private let simulatorSpeakTimeoutSeconds: UInt64 = 20

    func speak(text: String) async throws {
        try await speak(text: text, languageCode: nil)
    }

    /// Spricht Text mit expliziter Sprach-/Stimmwahl (nil = automatische Erkennung).
    func speak(text: String, languageCode: String?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        #if targetEnvironment(simulator)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.performSpeak(trimmed, languageCode: languageCode)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: self.simulatorSpeakTimeoutSeconds * 1_000_000_000)
                throw AppleSpeechSynthesizerError.simulatorSpeakTimedOut
            }
            try await group.next()
            group.cancelAll()
        }
        #else
        try await performSpeak(trimmed, languageCode: languageCode)
        #endif
    }

    func speak(stream: AsyncStream<String>) async throws {
        var combinedText = ""

        for await chunk in stream {
            combinedText += chunk
        }

        try await speak(text: combinedText)
    }

    func stop() async {
        synthesizer.stopSpeaking(at: .immediate)
        speechDelegate?.cancel()
        speechDelegate = nil
    }

    private func performSpeak(_ trimmed: String, languageCode: String?) async throws {
        do {
            try await AudioSessionCoordinator.shared.activatePlayback()
        } catch {
            NSLog("[Voicefinder] TTS Audio-Session: \(error.localizedDescription)")
            throw error
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = SpeechSynthesisDelegate(continuation: continuation)
            speechDelegate = delegate
            synthesizer.delegate = delegate

            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = Self.voice(for: trimmed, preferredLanguageCode: languageCode)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        }
    }

    /// Wählt eine passende Systemstimme – verhindert Englisch mit deutscher Stimme.
    private static func voice(for text: String, preferredLanguageCode: String?) -> AVSpeechSynthesisVoice? {
        if let preferredLanguageCode,
           let voice = AVSpeechSynthesisVoice(language: preferredLanguageCode) {
            return voice
        }

        switch ResponseLanguage.detect(in: text) {
        case .german:
            return AVSpeechSynthesisVoice(language: "de-DE")
                ?? AVSpeechSynthesisVoice(language: "de")
        case .english:
            return AVSpeechSynthesisVoice(language: "en-US")
                ?? AVSpeechSynthesisVoice(language: "en-GB")
        case .unknown:
            return AVSpeechSynthesisVoice(language: "de-DE")
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
    }
}

/// Fehler bei Apple-TTS.
enum AppleSpeechSynthesizerError: LocalizedError {
    case simulatorSpeakTimedOut

    var errorDescription: String? {
        switch self {
        case .simulatorSpeakTimedOut:
            "Sprachausgabe im Simulator hat zu lange gedauert (Antwort steht im Chat)."
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

/// Thread-sicherer Delegate für `AVSpeechSynthesizer` (Callbacks sind nicht MainActor-isoliert).
private final class SpeechSynthesisDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func cancel() {
        resumeOnce(with: nil)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        resumeOnce(with: nil)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        resumeOnce(with: nil)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFail utterance: AVSpeechUtterance,
        withError error: Error
    ) {
        resumeOnce(with: error)
    }

    private func resumeOnce(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
