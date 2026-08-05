//
//  WebSearchProviding.swift
//  Voicefinder
//
//  Liefert optionalen Web-Kontext – nur bei explizitem Bedarf.
//

import Foundation

/// Liefert kompakten Web-Kontext für das lokale LLM (ohne Cloud-LLM).
protocol WebSearchProviding: Sendable {
    /// Sucht passende Kurzinformationen zur Nutzerfrage.
    func fetchContext(for query: String) async throws -> String
}

/// Entscheidet, ob eine Web-Recherche wirklich nötig ist (selten – Fundus zuerst).
enum WebSearchHeuristic: Sendable {
    /// Grüße, Smalltalk und lokale Zeit/Datum brauchen kein Internet.
    nonisolated private static let skipPhrases = [
        "hallo", "hi", "hey", "danke", "thanks", "tschüss", "bye",
        "guten tag", "guten morgen", "guten abend", "wie geht", "was geht",
        "uhrzeit", "wie spät", "wie spaet", "welche uhr", "wie viel uhr",
        "datum", "welcher tag", "welches datum", "welchen tag",
        "what time", "what date", "what day",
        "ja", "nein", "ok", "okay", "verstanden", "alles klar",
    ]

    /// Nur explizite Anlässe für externe Fakten – alles andere beantwortet das lokale LLM.
    nonisolated private static let explicitWebTriggers = [
        "wetter", "nachrichten", "news", "schlagzeilen",
        "aktienkurs", "börsenkurs", "boersenkurs", "kurs von", "wechselkurs",
        "recherchier", "recherch", "google ", "wikipedia",
        "im internet", "online suchen", "such im web", "such mal",
        "was passiert gerade", "aktuell in ", "heute in der welt",
    ]

    /// True nur bei klarem Bedarf nach frischen externen Fakten.
    nonisolated static func shouldFetchWebContext(for text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 5 else { return false }

        if MissionQuestionDetector.isRoleOrMissionQuestion(lower) {
            return false
        }

        if skipPhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
            return false
        }

        // Kein generelles „?“ mehr – fast alles kommt aus KI-Gehirn + lokalem LLM.
        return explicitWebTriggers.contains { lower.contains($0) }
    }

    /// True, wenn Web-Kontext lang genug und nicht nur Platzhalter/Leerzeichen ist.
    nonisolated static func isUsefulWebContext(_ context: String) -> Bool {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }

        let lower = trimmed.lowercased()
        let uselessMarkers = [
            "keine ergebnisse",
            "no results",
            "nicht gefunden",
            "not found",
            "disambiguation",
            "begriffsklärung",
        ]
        if uselessMarkers.contains(where: { lower.contains($0) }) {
            return false
        }

        // Mindestens ein paar echte Wörter (nicht nur Satzzeichen/Zahlen).
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount >= 4
    }
}
