//
//  LanguageAnalysis.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Leichte Aktions-Empfehlung für Orchestrator oder spätere UI – rein lokal, ohne Netzwerk.
struct SuggestedAction: Equatable, Codable, Sendable {
    /// Art der empfohlenen Aktion.
    enum Kind: String, Codable, Sendable {
        /// Keine besondere Aktion nötig.
        case none
        /// Hilfe-/Info-Ansicht anzeigen (später).
        case showHelp
        /// Letzte Assistentenantwort erneut vorlesen.
        case repeatLastResponse
        /// Sprachmodell oder Einstellungen öffnen (später).
        case openSettings
    }

    let kind: Kind
    /// Kurzer deutscher Label-Text für Logs oder künftige UI.
    let label: String

    /// Keine Aktion – Standard-Fallback.
    nonisolated static let none = SuggestedAction(kind: .none, label: "Keine Aktion")
}

/// Ergebnis der lokalen Sprachanalyse: Intent, Antwort und optionale Aktion.
struct LanguageAnalysis: Equatable, Sendable {
    let intent: UserIntent
    let response: String
    let suggestedAction: SuggestedAction
}

/// Abstraktion für austauschbare Analyse-Backends (Regeln vs. lokales LLM).
protocol LanguageAnalyzing: Sendable {
    /// Analysiert Nutzertext und liefert Intent, Antwort und Aktionsvorschlag.
    func analyze(text: String, context: [ChatTurn]) async throws -> LanguageAnalysis
}
