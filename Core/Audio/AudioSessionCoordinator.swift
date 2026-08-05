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
        case recording
        case playback
        case microphoneOnly
    }

    private var activeProfile: SessionProfile = .none

    private init() {}

    /// Aktiviert oder deaktiviert Barge-in: Mikrofon bleibt während TTS weiterhin nutzbar.
    func setBargeInEnabled(_ enabled: Bool) {
        bargeInEnabled = enabled
    }

    /// Gibt die Audio-Session frei, bevor TTS die Hardware übernimmt (nach STT-Pause).
    func releaseForHandoff() async {
        await deactivateInternal()
    }

    /// Aktiviert die Session für Mikrofon-Eingabe (Apple Speech).
    func activateRecording() async throws {
        try await applyProfile(.recording)
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
        try await applyProfile(.playback)
    }

    /// Deaktiviert die Session, z. B. beim vollständigen Stoppen des Mikrofons.
    func deactivate() async {
        await deactivateInternal()
    }

    // MARK: - Intern

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
        case .recording:
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )

        case .playback:
            if bargeInEnabled {
                try session.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
                )
            } else {
                // Gleiche Basiskategorie wie STT – nur Modus für Sprachausgabe angepasst.
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
                )
            }

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
