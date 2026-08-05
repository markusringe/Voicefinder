//
//  WhisperKitRecordingTranscriber.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

@preconcurrency import AVFoundation
import Foundation

/// Fehler bei der WhisperKit-Aufnahme-Pipeline.
enum WhisperKitRecordingTranscriberError: LocalizedError, Sendable {
    case recordingFailed(String)
    case recordingTooShort

    var errorDescription: String? {
        switch self {
        case let .recordingFailed(message):
            "Aufnahme fehlgeschlagen: \(message)"
        case .recordingTooShort:
            "Aufnahme zu kurz oder leer. Bitte erneut sprechen (mind. 1 Sekunde)."
        }
    }
}

/// Live-Mikrofon-STT über Aufnahme + WhisperKit (Simulator-Fallback).
///
/// Im iOS-Simulator ist Apple Speech unzuverlässig. Diese Engine nimmt mit `AVAudioRecorder`
/// eine M4A-Datei auf (wie `sample.m4a`) und transkribiert beim Stopp mit WhisperKit.
///
/// Wichtig: Kein `AVAudioEngine`-Tap mit `AVAudioFile.write` – das crasht auf dem
/// Realtime-Audio-Thread (Core Audio Assertion in `ExtAudioFile::WriteInputProc`).
actor WhisperKitRecordingTranscriber: SpeechToTextEngine, StopFinalizingSpeechToTextEngine {
    private(set) var partialTextStream: AsyncStream<String>
    private(set) var finalTextStream: AsyncStream<String>
    private(set) var audioLevelStream: AsyncStream<Float>

    private var partialContinuation: AsyncStream<String>.Continuation
    private var finalContinuation: AsyncStream<String>.Continuation
    private var levelContinuation: AsyncStream<Float>.Continuation

    private let whisperFileEngine: WhisperKitTranscriber
    private let language: String

    /// Recorder ist MainActor-isoliert in Swift 6 – Zugriff nur beim Start/Stopp serialisiert.
    nonisolated(unsafe) private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// Mindestgröße der Audiodatei in Bytes (leere Simulator-Aufnahmen aussortieren).
    private let minimumRecordingBytes = 1_024

    init(whisperFileEngine: WhisperKitTranscriber, language: String = "de") {
        self.whisperFileEngine = whisperFileEngine
        self.language = language

        let partialPair = AsyncStream<String>.makeStream()
        self.partialTextStream = partialPair.stream
        self.partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        self.finalTextStream = finalPair.stream
        self.finalContinuation = finalPair.continuation

        let levelPair = AsyncStream<Float>.makeStream()
        self.audioLevelStream = levelPair.stream
        self.levelContinuation = levelPair.continuation
    }

    /// Pollt `AVAudioRecorder`-Metering für die Pegelanzeige.
    private var meteringTask: Task<Void, Never>?

    func requestAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startStreaming() async throws {
        resetStreams()

        try await AudioSessionCoordinator.shared.activateMicrophoneOnly()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicefinder-\(UUID().uuidString).m4a")
        recordingURL = tempURL

        // Gleiches Container-Format wie die funktionierende Sample-Datei im Bundle.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            // AVAudioRecorder ist in Swift 6 MainActor-gebunden – Erstellung auf dem MainActor.
            let recorder = try await MainActor.run {
                let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()
                return recorder
            }
            guard recorder.record() else {
                throw WhisperKitRecordingTranscriberError.recordingFailed(
                    "AVAudioRecorder konnte nicht starten."
                )
            }
            audioRecorder = recorder
            startMeteringPoll()
        } catch let error as WhisperKitRecordingTranscriberError {
            throw error
        } catch {
            throw WhisperKitRecordingTranscriberError.recordingFailed(error.localizedDescription)
        }

        partialContinuation.yield(
            "Aufnahme läuft … (nach Stopp transkribiert WhisperKit)"
        )
    }

    /// Stoppt Aufnahme und Pegel-Polling.
    func stopStreaming() async {
        stopMeteringPoll()
        _ = await finalizeRecording()
    }

    func stopStreamingAndFinalize() async -> String? {
        await finalizeRecording()
    }

    // MARK: - Intern

    /// Stoppt die Aufnahme, transkribiert mit WhisperKit und liefert den Text direkt zurück.
    private func finalizeRecording() async -> String? {
        await MainActor.run {
            audioRecorder?.stop()
        }
        audioRecorder = nil

        // M4A-Container finalisieren, bevor WhisperKit die Datei liest.
        try? await Task.sleep(for: .milliseconds(200))

        await AudioSessionCoordinator.shared.deactivate()

        defer {
            partialContinuation.finish()
            finalContinuation.finish()
            levelContinuation.finish()
        }

        guard let recordingURL else { return nil }

        guard recordingByteCount(at: recordingURL) >= minimumRecordingBytes else {
            NSLog("[Voicefinder] Aufnahme zu kurz: %d Bytes", recordingByteCount(at: recordingURL))
            partialContinuation.yield(
                WhisperKitRecordingTranscriberError.recordingTooShort.localizedDescription
            )
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            return nil
        }

        partialContinuation.yield("WhisperKit transkribiert …")
        NSLog("[Voicefinder] Starte WhisperKit-Transkription: %@", recordingURL.path)

        var result: String?
        do {
            // Timeout und Serialisierung liegen zentral in WhisperKitTranscriber.
            let text = try await whisperFileEngine.transcribeFile(at: recordingURL.path, language: language)
            NSLog("[Voicefinder] WhisperKit fertig, Länge=%d", text.count)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                print("[Voicefinder] WhisperKit lieferte leeren Text trotz Decoding.")
                partialContinuation.yield(
                    "Keine Sprache erkannt. Bitte lauter sprechen oder Sample-Button nutzen."
                )
            } else {
                result = trimmed
                print("[Voicefinder] WhisperKit-Transkript (Roh): \(trimmed)")
                finalContinuation.yield(trimmed)
            }
        } catch {
            NSLog("[Voicefinder] Transkription Fehler: %@", error.localizedDescription)
            partialContinuation.yield("Transkription fehlgeschlagen: \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
        return result
    }

    private func recordingByteCount(at url: URL) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return 0
        }
        return size
    }

    private func resetStreams() {
        stopMeteringPoll()

        // Vorhandene AsyncStreams beenden – verhindert hängende Orchestrator-Consumer.
        partialContinuation.finish()
        finalContinuation.finish()
        levelContinuation.finish()

        let partialPair = AsyncStream<String>.makeStream()
        partialTextStream = partialPair.stream
        partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        finalTextStream = finalPair.stream
        finalContinuation = finalPair.continuation

        let levelPair = AsyncStream<Float>.makeStream()
        audioLevelStream = levelPair.stream
        levelContinuation = levelPair.continuation
    }

    /// Liest den Aufnahmepegel periodisch aus (WhisperKit hat keinen Live-Tap).
    private func startMeteringPoll() {
        stopMeteringPoll()
        meteringTask = Task {
            while !Task.isCancelled {
                let decibels = await MainActor.run {
                    self.audioRecorder?.updateMeters()
                    return self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                }
                levelContinuation.yield(AudioLevelNormalizer.normalizedDecibels(decibels))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMeteringPoll() {
        meteringTask?.cancel()
        meteringTask = nil
    }
}
