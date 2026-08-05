//
//  SpeechDeliveryCoordinator.swift
//  Voicefinder
//
//  Verhindert, dass Speicher-Entladung laufende Piper-Wiedergabe abbricht.
//

import Foundation

/// Zählt aktive TTS-Wiedergaben – Speicherfreigabe darf Piper währenddessen nicht entladen.
enum SpeechDeliveryCoordinator: Sendable {
    private nonisolated(unsafe) static var activeDeliveryCount = 0

    /// True, solange mindestens eine Sprachausgabe läuft.
    nonisolated static var isActive: Bool {
        activeDeliveryCount > 0
    }

    /// Wird zu Beginn jeder TTS-Wiedergabe aufgerufen.
    nonisolated static func begin() {
        activeDeliveryCount += 1
    }

    /// Wird am Ende jeder TTS-Wiedergabe aufgerufen (auch bei Fehler via defer).
    nonisolated static func end() {
        activeDeliveryCount = max(0, activeDeliveryCount - 1)
    }
}
