//
//  ResponseLanguage.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import NaturalLanguage

/// Erkennung der dominierenden Sprache in generierten Antworten (LLM/TTS-Routing).
enum ResponseLanguage: Sendable {
    case german
    case english
    case unknown

    /// Ermittelt die wahrscheinlichste Sprache eines Textes.
    nonisolated static func detect(in text: String) -> ResponseLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return .unknown }

        if trimmed.range(of: "[äöüßÄÖÜ]", options: .regularExpression) != nil {
            return .german
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage else {
            return heuristic(from: trimmed)
        }

        switch dominant {
        case .german:
            return .german
        case .english:
            return .english
        default:
            return heuristic(from: trimmed)
        }
    }

    /// True, wenn der Text überwiegend Englisch ist (für MLX-Fallback).
    nonisolated static func isPredominantlyEnglish(_ text: String) -> Bool {
        if case .english = detect(in: text) { return true }
        return false
    }

    /// True, wenn der Text überwiegend Deutsch ist.
    nonisolated static func isPredominantlyGerman(_ text: String) -> Bool {
        if case .german = detect(in: text) { return true }
        return false
    }

    /// Einfache Wortlisten-Heuristik, falls `NLLanguageRecognizer` unsicher ist.
    nonisolated private static func heuristic(from text: String) -> ResponseLanguage {
        let lower = text.lowercased()
        let germanHints = [
            " der ", " die ", " das ", " und ", " ich ", " nicht ", " ist ", " hallo ",
            " danke ", " bitte ", " du ", " sie ", " wir ", " auf ", " für ", " mit ",
        ]
        let englishHints = [
            " the ", " and ", " you ", " is ", " are ", " hello ", " thanks ", " please ",
            " i ", " we ", " your ", " this ", " that ", " can ", " help ",
        ]

        let padded = " \(lower) "
        let germanScore = germanHints.reduce(0) { $0 + (padded.contains($1) ? 1 : 0) }
        let englishScore = englishHints.reduce(0) { $0 + (padded.contains($1) ? 1 : 0) }

        if germanScore > englishScore { return .german }
        if englishScore > germanScore { return .english }
        return .unknown
    }
}
