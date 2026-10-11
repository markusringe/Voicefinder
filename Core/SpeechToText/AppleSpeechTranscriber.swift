//
//  AppleSpeechTranscriber.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import AVFoundation
import Foundation
import Speech

/// Fehler bei der Apple-Spracherkennung.
enum AppleSpeechTranscriberError: LocalizedError, Sendable {
    case recognizerUnavailable
    case audioSessionFailed(String)
    case audioEngineFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Apple-Spracherkennung ist für die gewählte Sprache nicht verfügbar."
        case let .audioSessionFailed(message):
            "Audio-Session konnte nicht gestartet werden: \(message)"
        case let .audioEngineFailed(message):
            "Audio-Engine konnte nicht gestartet werden: \(message)"
        }
    }
}

/// Thread-sichere Referenz auf den Erkennungs-Request (Audio-Tap ≠ Actor).
///
/// `SFSpeechAudioBufferRecognitionRequest` ist in Swift 6 MainActor-isoliert – deshalb werden
/// Request und Pause-Flag getrennt mit Lock bzw. `nonisolated(unsafe)` gehalten.
private final class LiveRecognitionState: @unchecked Sendable {
    private let lock = NSLock()

    /// Vom Realtime-Audio-Tap gelesen – bewusst ohne Actor-Isolation.
    nonisolated(unsafe) var request: SFSpeechAudioBufferRecognitionRequest?

    /// Pause-Flag separat ohne MainActor-Kopplung (Klasse enthält Speech-Typen).
    nonisolated(unsafe) private var paused = false

    nonisolated func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }

    nonisolated func isPaused() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    nonisolated func clearRequest() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    nonisolated func assignRequest(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = newRequest
        accumulator.reset()
        lock.unlock()
    }

    #if DEBUG
    /// Diagnose (Launch-Argument `-voicefinder.debug.meter YES`): Pegel-Spitze und -Boden je ~0,5 s.
    nonisolated static let isMeterLoggingEnabled = UserDefaults.standard.bool(forKey: "voicefinder.debug.meter")
    nonisolated(unsafe) private var meterPeak: Float = 0
    nonisolated(unsafe) private var meterFloor: Float = 1
    nonisolated(unsafe) private var meterFrames: AVAudioFrameCount = 0

    nonisolated func recordMeter(level: Float, frames: AVAudioFrameCount, sampleRate: Double) {
        lock.lock()
        meterPeak = max(meterPeak, level)
        meterFloor = min(meterFloor, level)
        meterFrames += frames
        let shouldLog = Double(meterFrames) >= sampleRate * 0.5
        let peak = meterPeak
        let floor = meterFloor
        if shouldLog {
            meterPeak = 0
            meterFloor = 1
            meterFrames = 0
        }
        lock.unlock()

        if shouldLog {
            NSLog("[Voicefinder] Mic-Pegel: Spitze %.3f, Boden %.3f", peak, floor)
        }
    }
    #endif

    /// Führt Teilergebnisse über Apple-Speech-Resets (nach Sprechpausen) zusammen.
    nonisolated(unsafe) private var accumulator = TranscriptAccumulator()

    /// Liefert den vollständigen Äußerungstext für ein Roh-Ergebnis (in Callback-Reihenfolge aufrufen).
    nonisolated func accumulate(_ text: String, segmentCount: Int, isFinal: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        let full = accumulator.ingest(text, segmentCount: segmentCount, at: ProcessInfo.processInfo.systemUptime)
        if isFinal {
            accumulator.reset()
        }
        return full
    }
}

/// On-Device-/System-STT über `SFSpeechRecognizer` und `AVAudioEngine`.
///
/// Liefert partielle und finale Transkripte über AsyncStreams und ist der Standard-Pfad
/// für Live-Mikrofon-Eingaben gemäß Projekt-Architektur.
actor AppleSpeechTranscriber: SpeechToTextEngine, PausableSpeechToTextEngine {
    private(set) var partialTextStream: AsyncStream<String>
    private(set) var finalTextStream: AsyncStream<String>
    private(set) var audioLevelStream: AsyncStream<Float>

    private var partialContinuation: AsyncStream<String>.Continuation
    private var finalContinuation: AsyncStream<String>.Continuation
    private var levelContinuation: AsyncStream<Float>.Continuation

    private let locale: Locale
    private var speechRecognizer: SFSpeechRecognizer?
    /// `AVAudioEngine` ist MainActor-isoliert (Swift 6) – Erstellung erfolgt in `acquireAudioEngine()`.
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Gemeinsamer Zustand für den Audio-Tap (aktualisierbar bei Pause/Resume).
    private let liveRecognition: LiveRecognitionState
    /// Bündelt schnelle Partial-Updates – vermeidet hunderte gleichzeitiger Actor-Tasks.
    private var pendingRecognitionText: String?
    private var pendingRecognitionIsFinal = false
    private var recognitionFlushTask: Task<Void, Never>?
    /// True, solange der Mikrofon-Tap auf der laufenden Engine installiert ist.
    private var isTapInstalled = false

    init(locale: Locale = Locale(identifier: "de-DE")) {
        self.locale = locale
        self.liveRecognition = LiveRecognitionState()

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

    func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAuthorized else { return false }

        return await AVAudioApplication.requestRecordPermission()
    }

    func startStreaming() async throws {
        resetStreams()
        cleanupRecognition()
        liveRecognition.setPaused(false)

        do {
            try await AudioSessionCoordinator.shared.activateRecording()
        } catch {
            throw AppleSpeechTranscriberError.audioSessionFailed(error.localizedDescription)
        }

        try await ensureAudioCaptureRunning()
        try startRecognitionSession()
    }

    /// Pausiert Spracherkennung während KI-Antwort/TTS.
    ///
    /// Mikrofon-Engine und Audio-Session laufen weiter (Gesprächsprofil) – der Tap verwirft Audio,
    /// solange pausiert ist. So ist das Mikrofon nach der Antwort sofort wieder bereit.
    func pauseStreaming() async {
        liveRecognition.setPaused(true)
        cleanupRecognition()
    }

    /// Setzt Aufnahme und Erkennung nach TTS fort – ohne neue AsyncStreams (Orchestrator behält Consumer).
    func resumeStreaming() async throws {
        do {
            try await AudioSessionCoordinator.shared.activateRecording()
        } catch {
            throw AppleSpeechTranscriberError.audioSessionFailed(error.localizedDescription)
        }

        try await ensureAudioCaptureRunning()
        liveRecognition.setPaused(false)
        try startRecognitionSession()
        #if DEBUG
        NSLog("[Voicefinder] STT bereit (Resume).")
        #endif
    }

    func stopStreaming() async {
        liveRecognition.setPaused(true)
        cleanupRecognition()

        if let audioEngine, audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        self.audioEngine = nil
        isTapInstalled = false

        await AudioSessionCoordinator.shared.deactivate()

        partialContinuation.finish()
        finalContinuation.finish()
        levelContinuation.finish()
    }

    // MARK: - Intern

    /// Stellt Mikrofon-Tap und laufende Engine wieder her (ohne Stream-Reset).
    private func ensureAudioCaptureRunning() async throws {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable
        }

        let audioEngine = await acquireAudioEngine()
        // Läuft noch aus der letzten Runde (Pause) – Tap ist installiert, nichts neu aufbauen.
        if audioEngine.isRunning, isTapInstalled {
            return
        }
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        #if DEBUG
        NSLog(
            "[Voicefinder] STT Eingang: %.0f Hz, %d Kanäle, Route: %@",
            recordingFormat.sampleRate,
            recordingFormat.channelCount,
            AVAudioSession.sharedInstance().currentRoute.inputs.map(\.portName).joined(separator: ", ")
        )
        #endif

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw AppleSpeechTranscriberError.audioEngineFailed(
                "Mikrofonformat ungültig (Simulator ohne Mic?). Bitte echtes Gerät verwenden."
            )
        }

        inputNode.removeTap(onBus: 0)

        let liveState = liveRecognition
        let levelCont = levelContinuation
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            guard buffer.frameLength > 0 else { return }

            if liveState.isPaused() {
                return
            }

            liveState.request?.append(buffer)
            let level = AudioLevelNormalizer.normalizedRMS(from: buffer)
            #if DEBUG
            if LiveRecognitionState.isMeterLoggingEnabled {
                liveState.recordMeter(level: level, frames: buffer.frameLength, sampleRate: buffer.format.sampleRate)
            }
            #endif
            levelCont.yield(level)
        }

        isTapInstalled = true
        audioEngine.prepare()

        guard !audioEngine.isRunning else { return }

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
            throw AppleSpeechTranscriberError.audioEngineFailed(error.localizedDescription)
        }
    }

    /// Erstellt `AVAudioEngine` auf dem MainActor (SDK-Anforderung in Swift 6).
    private func acquireAudioEngine() async -> AVAudioEngine {
        if let audioEngine {
            return audioEngine
        }
        let engine = await MainActor.run { AVAudioEngine() }
        audioEngine = engine
        return engine
    }

    /// Startet einen neuen `SFSpeechRecognitionTask` auf dem laufenden Audio-Tap.
    private func startRecognitionSession() throws {
        cleanupRecognition()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        #if !targetEnvironment(simulator)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        #endif

        recognitionRequest = request
        liveRecognition.assignRequest(request)

        let liveState = liveRecognition
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let rawText = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Leere Ergebnisse (z. B. beim Abbrechen) nicht mit altem Text auffüllen.
                let text = rawText.isEmpty
                    ? rawText
                    : liveState.accumulate(
                        rawText,
                        segmentCount: result.bestTranscription.segments.count,
                        isFinal: result.isFinal
                    )
                #if DEBUG
                // Diagnose: jedes Roh-Ergebnis mit Segmentanzahl (Transkript-Resets sichtbar machen).
                NSLog(
                    "[Voicefinder] STT roh (final=%d, Segmente=%d): %@ → %@",
                    result.isFinal ? 1 : 0,
                    result.bestTranscription.segments.count,
                    rawText,
                    text
                )
                #endif
                if result.isFinal {
                    // Finale Segmente sofort verarbeiten – Pipeline darf nicht warten.
                    Task {
                        await self.enqueueRecognitionUpdate(text: text, isFinal: true)
                    }
                } else {
                    Task {
                        await self.enqueueRecognitionUpdate(text: text, isFinal: false)
                    }
                }
            }

            if let error {
                #if DEBUG
                NSLog("[Voicefinder] STT Fehler: %@", error.localizedDescription)
                #endif
                Task {
                    await self.cleanupRecognition()
                }
            }
        }
    }

    /// Sammelt Partial-Transkripte und flusht sie gebündelt (~30 ms), statt pro Token einen Task zu erzeugen.
    private func enqueueRecognitionUpdate(text: String, isFinal: Bool) {
        pendingRecognitionText = text
        pendingRecognitionIsFinal = pendingRecognitionIsFinal || isFinal

        if isFinal {
            recognitionFlushTask?.cancel()
            recognitionFlushTask = Task {
                await self.flushPendingRecognitionUpdate()
            }
            return
        }

        guard recognitionFlushTask == nil else { return }
        recognitionFlushTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            await self.flushPendingRecognitionUpdate()
        }
    }

    private func flushPendingRecognitionUpdate() async {
        recognitionFlushTask = nil
        guard let text = pendingRecognitionText else { return }
        let isFinal = pendingRecognitionIsFinal
        pendingRecognitionText = nil
        pendingRecognitionIsFinal = false
        handleRecognition(text: text, isFinal: isFinal)
    }

    private func handleRecognition(text: String, isFinal: Bool) {
        guard !liveRecognition.isPaused() else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isFinal {
            finalContinuation.yield(trimmed)
        } else {
            partialContinuation.yield(trimmed)
        }
    }

    private func cleanupRecognition() {
        recognitionFlushTask?.cancel()
        recognitionFlushTask = nil
        pendingRecognitionText = nil
        pendingRecognitionIsFinal = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        liveRecognition.clearRequest()
    }

    private func resetStreams() {
        // Alte Continuations sauber beenden, bevor neue Streams erzeugt werden (sonst hängende Consumer).
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
}
