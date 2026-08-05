//
//  Intent.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Klassifizierte Nutzerabsicht – offline per Regeln oder später per lokalem LLM.
enum UserIntent: String, Codable, Sendable, CaseIterable {
    /// Begrüßung (z. B. „Hallo“, „Moin“).
    case greeting
    /// Hilfe oder Fähigkeiten erfragen.
    case help
    /// Uhrzeit oder Datum erfragen.
    case timeQuery
    /// Dank oder positives Feedback.
    case thanks
    /// Verabschiedung.
    case farewell
    /// Letzte Assistentenantwort wiederholen.
    case repeatLast
    /// Leere oder unverständliche Eingabe.
    case empty
    /// Keiner speziellen Kategorie zugeordnet.
    case unknown
}
