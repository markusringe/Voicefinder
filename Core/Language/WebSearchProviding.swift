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
        "was gibt", "was ist los", "was geht", "was machst", "was meinst",
    ]

    /// Themen, die die Geräteuhr beantwortet – kein Internet nötig.
    nonisolated private static let deviceContextTopics = [
        "wochentag", "jahreszeit", "welcher monat", "welchen monat", "welcher tag", "welchen tag",
        "welches jahr", "welche zeit", "wie spät", "wie spaet", "uhrzeit", "datum",
    ]

    /// Wörter, die auf Gespräch über die KI oder den Nutzer hinweisen – dafür gibt es das KI-Gehirn.
    nonisolated private static let personalWords: Set<String> = [
        "du", "dich", "dir", "dein", "deine", "deinen", "deiner", "deinem", "deines",
        "ich", "mich", "mir", "mein", "meine", "meinen", "meiner", "meinem", "meines",
        "wir", "uns", "unser", "unsere", "unseren", "unserer",
    ]

    /// Beginn einer Wissensfrage.
    nonisolated private static let factQuestionStarts = [
        "wer ", "wen ", "wem ", "wessen ", "was ", "wie ", "wo ", "wann ", "woher ", "wohin ",
        "welche ", "welcher ", "welches ", "welchen ", "welchem ",
    ]

    /// Einleitungen, hinter denen direkt das Thema steht („Kennst du Franz Beckenbauer?“).
    nonisolated private static let topicPrefixes = [
        "kennst du ", "was weißt du über ", "was weisst du über ", "weißt du etwas über ",
        "erzähl mir was über ", "erzähl mir etwas über ", "erzähl mir von ", "sag mir was über ",
    ]

    /// Höfliche Vorspänne vor einer Frage.
    nonisolated private static let politePrefixes = [
        "sag mal, ", "sag mal ", "sag mir, ", "sag mir ", "weißt du, ", "weißt du ", "weisst du ",
        "kannst du mir sagen, ", "kannst du mir sagen ", "ich möchte wissen, ", "ich will wissen, ",
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

        if explicitWebTriggers.contains(where: { lower.contains($0) }) {
            return true
        }
        return isFactQuestion(lower) && hasTopic(text)
    }

    /// Wissensfrage über die Welt: Fragewort, Sachbegriff mit Großbuchstaben, kein Smalltalk, keine Uhrzeitfrage,
    /// nichts über die KI oder den Nutzer selbst.
    nonisolated static func isFactQuestion(_ lowercased: String) -> Bool {
        var text = lowercased
        for prefix in politePrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }

        if deviceContextTopics.contains(where: { text.contains($0) }) { return false }

        var isTopicQuestion = false
        for prefix in topicPrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            isTopicQuestion = true
            break
        }

        if !isTopicQuestion, !factQuestionStarts.contains(where: { text.hasPrefix($0) }) {
            return false
        }

        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: { personalWords.contains($0) }) { return false }
        // „bist“ und „heißt“ in Verbindung mit „wer/wie“ meinen fast immer die KI selbst.
        if words.contains("bist") || words.contains("heißt") || words.contains("heisst") { return false }
        return true
    }

    /// True, wenn die Frage ein Sachthema nennt (großgeschriebenes Inhaltswort nach der Fragephrase).
    nonisolated static func hasTopic(_ original: String) -> Bool {
        WebSearchQuery.make(from: original).keywords.contains { $0.first?.isUppercase == true }
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
