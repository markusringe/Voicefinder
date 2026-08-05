//
//  SpeechToTextEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Basisprotokoll für Live-Spracherkennung (Mikrofon → partielle/finale Transkripte).
protocol SpeechToTextEngine: Sendable {
    /// Async-Zugriff, damit Actor-Implementierungen Swift-6-konform am Protokoll teilnehmen können.
    var partialTextStream: AsyncStream<String> { get async }
    var finalTextStream: AsyncStream<String> { get async }
    /// Normalisierter Pegel 0…1 für UI; ohne Mikrofon-Monitoring leerer Stream.
    var audioLevelStream: AsyncStream<Float> { get async }

    func requestAuthorization() async -> Bool
    func startStreaming() async throws
    func stopStreaming() async
}

/// Offline-Transkription einer Audiodatei (Sample-Tests, WhisperKit-Fallback).
protocol FileTranscribing: Sendable {
    func requestAuthorization() async -> Bool
    func transcribeFile(at path: String, language: String) async throws -> String
}

/// Pausieren/Fortsetzen ohne den Erkennungs-Task komplett neu zu starten (z. B. während TTS).
protocol PausableSpeechToTextEngine: SpeechToTextEngine {
    func pauseStreaming() async
    func resumeStreaming() async throws
}

/// Stoppt die Aufnahme und liefert optional ein finales Transkript (WhisperKit-Aufnahme-Pfad).
protocol StopFinalizingSpeechToTextEngine: SpeechToTextEngine {
    func stopStreamingAndFinalize() async -> String?
}
