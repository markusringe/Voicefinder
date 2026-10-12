//
//  WebSearchQuery.swift
//  Voicefinder
//
//  Macht aus einer gesprochenen Frage Suchbegriffe – der ganze Satz als Suchbegriff liefert
//  falsche Artikel („Such mal im Internet, wie hoch die Zugspitze ist“ → Todesfälle-Liste).
//

import Foundation

/// Schlüsselwörter einer Faktenfrage plus Hinweis, ob eine Zahl erwartet wird.
nonisolated struct WebSearchQuery: Sendable, Equatable {
    /// Inhaltswörter in Originalschreibweise und -reihenfolge.
    let keywords: [String]
    /// True bei Fragen nach Mengen, Maßen, Jahren („wie viele“, „wie hoch“, „wann“).
    let expectsNumber: Bool

    /// Suchbegriffe für die Wikipedia-Suche.
    var searchTerms: String {
        keywords.joined(separator: " ")
    }

    /// Frage-, Füll- und Funktionswörter, die in keinem Artikeltitel zu erwarten sind.
    private static let stopWords: Set<String> = [
        // Fragewörter
        "was", "wer", "wen", "wem", "wessen", "wie", "wo", "wann", "warum", "wieso", "weshalb", "woher", "wohin",
        "welche", "welcher", "welches", "welchen", "welchem", "viele", "viel",
        // Artikel, Präpositionen, Konjunktionen
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "einem", "einen", "eines",
        "von", "vom", "im", "in", "am", "an", "auf", "aus", "bei", "mit", "nach", "zu", "zum", "zur", "für", "fuer",
        "und", "oder", "aber", "auch", "noch", "schon", "nur", "ob", "dass",
        // Hilfsverben und Füllwörter
        "ist", "sind", "war", "waren", "wird", "wurde", "wurden", "hat", "haben", "hatte", "gibt", "kann", "können",
        "bin", "bist", "sein", "ich", "du", "er", "sie", "es", "wir", "ihr", "mir", "dir", "mich", "dich",
        "mal", "bitte", "eigentlich", "denn", "doch", "eben", "halt", "also", "so", "ja", "nein", "heute", "jetzt",
        "gerade", "genau", "ungefähr", "etwa", "ca",
        // Aufforderungen
        "such", "suche", "suchen", "recherchier", "recherchiere", "recherchieren", "sag", "sage", "sagen",
        "kennst", "weißt", "weisst", "internet", "web", "google", "wikipedia", "nachschauen", "nachsehen",
        "erzähl", "erzähle", "erzaehl", "erzaehle",
    ]

    /// Fragen, deren Antwort eine Zahl ist.
    private static let numberTriggers = [
        "wie viele", "wie viel", "wie hoch", "wie groß", "wie gross", "wie lang", "wie alt", "wie weit",
        "wie schwer", "wie breit", "wie tief", "wie schnell", "wie teuer", "wie oft", "wann", "in welchem jahr",
        "welches jahr", "wie lange", "wie viele einwohner",
    ]

    nonisolated static func make(from question: String) -> WebSearchQuery {
        let lower = question.lowercased()
        let expectsNumber = numberTriggers.contains { lower.contains($0) }

        let words = question
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)

        let keywords = words.filter { word in
            let key = word.lowercased()
            if stopWords.contains(key) { return false }
            // „Hauptstadt“ ist ein Inhaltswort, „ist“ nicht – sehr kurze Wörter sind selten Suchbegriffe.
            return key.count >= 3 || word.first?.isNumber == true
        }
        return WebSearchQuery(keywords: keywords, expectsNumber: expectsNumber)
    }
}
