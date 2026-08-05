//
//  AppMemoryCoordinator.swift
//  Voicefinder
//
//  Reagiert auf iOS-Speicherwarnungen und drosselt parallele Modell-Last.
//

import Foundation

/// Globale Speicher-Steuerung – verhindert gleichzeitig MLX, Piper und Hintergrund-LLM.
enum AppMemoryCoordinator: Sendable {
    /// True nach `UIApplication.didReceiveMemoryWarningNotification`.
    private nonisolated(unsafe) static var _shouldReduceMemoryUse = false

    /// Zeitpunkt der letzten iOS-Speicherwarnung – Vorsichtsphase danach.
    private nonisolated(unsafe) static var _memoryWarningAt: Date?

    /// Abgeschlossene Dialog-Runden – nur für Hintergrund-KI-Gehirn, nicht für Hauptantworten.
    private nonisolated(unsafe) static var _completedDialogRounds = 0

    /// Runden seit der letzten Speicherwarnung – für schrittweises Entspannen.
    private nonisolated(unsafe) static var _roundsSinceMemoryWarning = 0

    /// Vorsichtsphase nach Speicherwarnung (Sekunden) – Hintergrund-LLM und Piper-Preload pausieren.
    private nonisolated static let memoryCautionInterval: TimeInterval = 120

    /// True nach Speicherwarnung oder innerhalb der Vorsichtsphase.
    nonisolated static var shouldReduceMemoryUse: Bool {
        if _shouldReduceMemoryUse { return true }
        guard let warningAt = _memoryWarningAt else { return false }
        return Date().timeIntervalSince(warningAt) < memoryCautionInterval
    }

    /// Abwärtskompatibel – gleiche Bedeutung wie `shouldReduceMemoryUse`.
    nonisolated static var isUnderMemoryPressure: Bool {
        shouldReduceMemoryUse
    }

    /// Zusatz-MLX (Fortsetzung, Polish-Retry) nur unter echtem iOS-Speicherdruck – nicht proaktiv ab Runde 2.
    nonisolated static var shouldLimitExtraLLMRounds: Bool {
        _shouldReduceMemoryUse
    }

    /// Hintergrund-KI-Gehirn per LLM nur unter echtem Speicherdruck auslassen (Regel-Extraktion läuft weiter).
    nonisolated static var shouldSkipBrainEnrichmentLLM: Bool {
        _shouldReduceMemoryUse
    }

    /// Piper vor MLX entladen – auf dem Gerät immer (MLX ~1,7 GB), im Simulator nur unter Druck.
    nonisolated static var shouldUnloadPiperBeforeLLM: Bool {
        #if targetEnvironment(simulator)
        shouldReduceMemoryUse
        #else
        true
        #endif
    }

    /// Piper nach TTS entladen – nur bei aktivem Speicherdruck, sonst schnelleres Folge-TTS.
    nonisolated static var shouldUnloadPiperAfterTTS: Bool {
        shouldReduceMemoryUse
    }

    /// Wird bei iOS-Speicherwarnung aufgerufen.
    nonisolated static func handleMemoryWarning() {
        _shouldReduceMemoryUse = true
        _memoryWarningAt = Date()
        _roundsSinceMemoryWarning = 0
        NSLog("[Voicefinder] Speicherwarnung – Piper-Cache entladen, Hintergrund-LLM pausiert (Vorsicht: 120 s).")
    }

    /// Nach erfolgreicher Assistenten-Antwort – Zähler für Diagnose und schrittweises Entspannen.
    nonisolated static func markDialogRoundCompleted() {
        _completedDialogRounds += 1
        guard _shouldReduceMemoryUse || _memoryWarningAt != nil else { return }

        _roundsSinceMemoryWarning += 1
        // Erst nach mehreren stabilen Runden wieder normal laden – nicht direkt nach der Warnung.
        guard _roundsSinceMemoryWarning >= 3 else { return }

        _shouldReduceMemoryUse = false
        _memoryWarningAt = nil
        let roundsSinceWarning = _roundsSinceMemoryWarning
        _roundsSinceMemoryWarning = 0
        NSLog("[Voicefinder] Speicher-Vorsichtsphase beendet nach %d Runden seit Warnung.", roundsSinceWarning)
    }

    /// Setzt den Dialog-Zähler zurück (z. B. wenn das Gespräch komplett beendet wird).
    nonisolated static func resetDialogRoundCounter() {
        _completedDialogRounds = 0
        _roundsSinceMemoryWarning = 0
    }

    /// Nur nach expliziter Nutzer-Aktion in den Einstellungen – nicht automatisch nach Piper-Entladung.
    nonisolated static func clearMemoryPressureAfterManualRelease() {
        _shouldReduceMemoryUse = false
        _memoryWarningAt = nil
        _roundsSinceMemoryWarning = 0
        NSLog("[Voicefinder] Speicher manuell entlastet – Pipeline wieder voll aktiv.")
    }

    /// Nach TTS-Ressourcenfreigabe – Zähler/Hook ohne automatisches Zurücksetzen der iOS-Warnung.
    nonisolated static func markResourcesReleased() {
        // iOS-Speicherwarnung bleibt aktiv, bis clearMemoryPressureAfterManualRelease() aufgerufen wird.
    }

    /// Nur für Tests und manuelle Zurücksetzung.
    nonisolated static func clearMemoryPressureIfNeeded() {
        _shouldReduceMemoryUse = false
        _completedDialogRounds = 0
    }
}
