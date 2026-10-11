//
//  AudioSessionCoordinator.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import AVFoundation
import Foundation

/// Zentraler Koordinator für `AVAudioSession`, damit STT, WhisperKit und TTS sich nicht gegenseitig stören.
actor AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    /// OSStatus `!pri` – Session-Umschaltung abgelehnt, weil Hardware noch belegt ist.
    private static let insufficientPriorityCode = 561017449

    /// True, solange das Mikrofon parallel zur Sprachausgabe aktiv bleiben soll (Barge-in).
    private var bargeInEnabled = false

    /// Merkt sich das aktive Profil, um unnötige `setCategory`-Aufrufe zu vermeiden.
    private enum SessionProfile: Sendable {
        case none
        /// Gespräch ohne Barge-in: STT und TTS teilen sich eine durchgehend aktive Session –
        /// kein Kategorie-/Moduswechsel zwischen Zuhören und Sprechen, Mikrofon sofort wieder bereit.
        case conversation
        /// Sprachausgabe mit Barge-in (Echo-Unterdrückung über `.voiceChat`).
        case bargeInPlayback
        case microphoneOnly
    }

    private var activeProfile: SessionProfile = .none

    private init() {}

    /// Aktiviert oder deaktiviert Barge-in: Mikrofon bleibt während TTS weiterhin nutzbar.
    func setBargeInEnabled(_ enabled: Bool) {
        bargeInEnabled = enabled
    }

    /// Gibt die Audio-Session frei, bevor ein anderes Profil die Hardware übernimmt.
    ///
    /// Im Gesprächsprofil bleibt die Session aktiv – STT und TTS nutzen dieselbe Konfiguration,
    /// ein Deaktivieren würde das Mikrofon nach jeder Antwort ~0,85 s taub machen.
    func releaseForHandoff() async {
        guard activeProfile != .conversation else { return }
        await deactivateInternal()
    }

    /// Aktiviert die Session für Mikrofon-Eingabe (Apple Speech).
    ///
    /// Zuhören in `.measurement`: ohne automatische Verstärkung – mit `.default` regelte die AGC in Sprechpausen
    /// das Raumrauschen ~1,5 s lang über die Stille-Schwelle, und die Satzende-Erkennung griff nicht.
    func activateRecording() async throws {
        try await applyConversation(mode: .measurement)
    }

    /// Nur Aufnahme (WhisperKit-Recorder) – weniger Audio-HAL-Stress im Simulator als `.playAndRecord`.
    func activateMicrophoneOnly() async throws {
        try await applyProfile(.microphoneOnly)
    }

    /// Aktiviert die Session für Sprachausgabe.
    ///
    /// Nutzt `.playAndRecord` + Lautsprecher statt reiner `.playback`-Kategorie, damit der Wechsel
    /// von STT zu TTS keinen `!pri`-Fehler (InsufficientPriority) auslöst und die Stimme hörbar bleibt.
    func activatePlayback() async throws {
        if bargeInEnabled {
            try await applyProfile(.bargeInPlayback)
        } else {
            // Sprechen in `.spokenAudio` – `.measurement` dämpft die Lautsprecher-Ausgabe deutlich.
            try await applyConversation(mode: .spokenAudio)
        }
    }

    /// Deaktiviert die Session, z. B. beim vollständigen Stoppen des Mikrofons.
    func deactivate() async {
        await deactivateInternal()
    }

    // MARK: - Intern

    /// Gesprächsprofil mit Modus je Phase. Nur `setMode` auf der aktiven Session – kein Deaktivieren,
    /// damit das Mikrofon nach der Antwort sofort wieder zuhört.
    private func applyConversation(mode: AVAudioSession.Mode) async throws {
        try await applyProfile(.conversation)
        let session = AVAudioSession.sharedInstance()
        guard session.mode != mode else { return }

        let start = CFAbsoluteTimeGetCurrent()
        try session.setMode(mode)
        #if DEBUG
        NSLog("[Voicefinder] Audio-Modus → %@ (%.0f ms)", mode.rawValue, (CFAbsoluteTimeGetCurrent() - start) * 1000)
        #endif
    }

    private func applyProfile(_ profile: SessionProfile) async throws {
        if activeProfile == profile {
            try await setActiveWithRetry(true)
            return
        }

        // Vor Profilwechsel freigeben – verhindert SessionCore `!pri` bei STT → TTS.
        if activeProfile != .none {
            await deactivateInternal()
            // Kurze Pause, damit HAL/AudioEngine die Hardware wirklich loslässt.
            try await Task.sleep(for: .milliseconds(50))
        }

        let session = AVAudioSession.sharedInstance()

        switch profile {
        case .conversation:
            // Startmodus – `applyConversation(mode:)` schaltet danach je Phase um.
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )

        case .bargeInPlayback:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )

        case .microphoneOnly:
            try session.setCategory(.record, mode: .default, options: [])

        case .none:
            return
        }

        try await setActiveWithRetry(true)
        activeProfile = profile
    }

    private func deactivateInternal() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("[Voicefinder] Audio-Session deaktivieren (best-effort): \(error.localizedDescription)")
        }
        activeProfile = .none
    }

    /// Aktiviert die Session mit Retry bei transientem `!pri` (561017449).
    private func setActiveWithRetry(_ active: Bool, maxAttempts: Int = 4) async throws {
        let session = AVAudioSession.sharedInstance()
        var lastError: Error?

        for attempt in 0 ..< maxAttempts {
            do {
                try session.setActive(active, options: .notifyOthersOnDeactivation)
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                let isPriorityError = nsError.code == Self.insufficientPriorityCode
                guard isPriorityError, attempt < maxAttempts - 1 else {
                    break
                }
                let delayMs = 80 * (attempt + 1)
                NSLog(
                    "[Voicefinder] Audio-Session !pri – Retry %d/%d in %d ms",
                    attempt + 1,
                    maxAttempts,
                    delayMs
                )
                try await Task.sleep(for: .milliseconds(delayMs))
            }
        }

        if let lastError {
            NSLog("[Voicefinder] Audio-Session setActive fehlgeschlagen: \(lastError.localizedDescription)")
            throw lastError
        }
    }
}
