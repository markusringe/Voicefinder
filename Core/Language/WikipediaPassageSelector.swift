//
//  WikipediaPassageSelector.swift
//  Voicefinder
//
//  Wählt aus Wikipedia-Treffern die Passage, die zur Frage passt – statt blind die ersten
//  120 Zeichen des ersten Artikels zu nehmen.
//

import Foundation

/// Ein Wikipedia-Treffer: Titel, Artikelanfang und Suchtreffer-Ausschnitte.
nonisolated struct WikipediaPage: Sendable, Equatable {
    let title: String
    /// Rang in der Wikipedia-Suche (1 = bester Treffer).
    let index: Int
    let intro: String
    let snippets: [String]
}

nonisolated enum WikipediaPassageSelector {
    /// Abkürzungen, nach denen ein Punkt keinen Satz beendet (kleingeschrieben, ohne Punkt).
    private static let abbreviations: Set<String> = [
        "z", "b", "d", "h", "u", "a", "ca", "bzw", "usw", "etc", "vgl", "ggf", "inkl", "nr", "dr", "prof",
        "st", "str", "geb", "gest", "mio", "mrd", "ü", "nhn", "ev", "kath", "bzgl", "evtl", "sog",
    ]

    /// Beste Passage (mit Artikeltitel) für die Frage – `nil`, wenn nichts passt.
    nonisolated static func bestPassage(
        pages: [WikipediaPage],
        query: WebSearchQuery,
        maxCharacters: Int
    ) -> String? {
        guard !pages.isEmpty, !query.keywords.isEmpty else { return nil }

        struct Scored {
            let page: WikipediaPage
            let sentences: [(text: String, score: Double)]
            let total: Double
        }

        let scored: [Scored] = pages.map { page in
            let pool = (sentences(in: page.intro) + page.snippets.map(cleanSnippet))
                .filter { !looksLikeNavigationList($0) }
            let rated = pool.enumerated().map { offset, text -> (String, Double) in
                var score = keywordScore(of: text, keywords: query.keywords)
                if query.expectsNumber, containsNumber(text) { score += 0.75 }
                // Erster Satz ist die Definition – kleiner Bonus als Kontext.
                if offset == 0 { score += 0.25 }
                return (text, score)
            }

            let best = rated.map(\.1).max() ?? 0
            let title = titleScore(page.title, keywords: query.keywords)
            // Rangbonus: bei Gleichstand gewinnt der bessere Suchtreffer.
            let rank = 0.1 / Double(max(page.index, 1))
            var total = best + title * 2 + rank
            if isListOrDisambiguation(page) { total -= 1.5 }
            return Scored(page: page, sentences: rated, total: total)
        }

        guard let winner = scored.max(by: { $0.total < $1.total }), winner.total > 0.3 else { return nil }

        // Zwei beste Sätze des Artikels, in Originalreihenfolge.
        let ranked = winner.sentences.enumerated()
            .filter { $0.element.score > 0 }
            .sorted { $0.element.score > $1.element.score }
            .prefix(2)
            .sorted { $0.offset < $1.offset }
            .map(\.element.text)
        guard !ranked.isEmpty else { return nil }

        var text = "\(winner.page.title): " + ranked.joined(separator: " ")
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
            // Nicht mitten im Wort enden.
            if let lastSpace = text.lastIndex(of: " ") {
                text = String(text[..<lastSpace])
            }
        }
        return text
    }

    /// Ausgeschriebene Zahlen – „Spinnen haben acht Beine“ enthält keine Ziffer.
    private static let numberWords: Set<String> = [
        "ein", "eine", "einer", "zwei", "drei", "vier", "fuenf", "sechs", "sieben", "acht", "neun", "zehn",
        "elf", "zwoelf", "dutzend", "hundert", "tausend", "million", "millionen", "milliarde", "milliarden",
    ]

    private static func containsNumber(_ text: String) -> Bool {
        if text.contains(where: \.isNumber) { return true }
        // „ein/eine“ ist zu häufig als Artikel – nur echte Zahlwörter zählen.
        let articles: Set<String> = ["ein", "eine", "einer"]
        return tokens(of: text).contains { numberWords.contains($0) && !articles.contains($0) }
    }

    /// Zerlegt Fließtext in Sätze – ohne an Zahlen („27. August“), Einzelbuchstaben und Abkürzungen zu trennen.
    nonisolated static func sentences(in text: String) -> [String] {
        let characters = Array(text.replacingOccurrences(of: "\n", with: " "))
        var result: [String] = []
        var start = 0

        for index in characters.indices {
            let character = characters[index]
            guard character == "." || character == "!" || character == "?" else { continue }
            guard index + 1 < characters.count, characters[index + 1] == " " else { continue }
            if character == ".", isNonTerminalPeriod(at: index, in: characters) { continue }

            let sentence = String(characters[start ... index]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { result.append(sentence) }
            start = index + 1
        }

        let tail = String(characters[start...]).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    // MARK: - Bewertung

    /// Anteil der Suchbegriffe, die im Text vorkommen (Präfixvergleich, ohne Umlaute und Groß-/Kleinschreibung).
    private static func keywordScore(of text: String, keywords: [String]) -> Double {
        let words = tokens(of: text)
        var matched = 0.0
        for keyword in keywords {
            let key = fold(keyword)
            if words.contains(where: { wordsMatch($0, key) }) { matched += 1 }
        }
        return matched
    }

    /// Anteil der Titelwörter, die von Suchbegriffen abgedeckt sind – „Zugspitze“ schlägt „Liste der höchsten Berge …“.
    private static func titleScore(_ title: String, keywords: [String]) -> Double {
        let titleWords = tokens(of: title)
        guard !titleWords.isEmpty else { return 0 }
        let keys = keywords.map(fold)
        let covered = titleWords.filter { word in keys.contains { wordsMatch(word, $0) } }.count
        return Double(covered) / Double(titleWords.count)
    }

    private static func isListOrDisambiguation(_ page: WikipediaPage) -> Bool {
        let title = page.title.lowercased()
        if title.hasPrefix("liste ") || title.hasPrefix("liste_") { return true }
        let intro = page.intro.lowercased()
        return intro.hasSuffix("steht für:") || intro.contains("steht für:")
    }

    private static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { fold(String($0)) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
    }

    /// Gleich, oder eines ist Präfix des anderen (mindestens 4 Zeichen): „hoch“ ↔ „höchste“.
    private static func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        return shorter.count >= 4 && longer.hasPrefix(shorter)
    }

    private static func isNonTerminalPeriod(at index: Int, in characters: [Character]) -> Bool {
        var start = index
        while start > 0, !characters[start - 1].isWhitespace, characters[start - 1] != "(" {
            start -= 1
        }
        let token = String(characters[start ..< index]).lowercased()
        guard !token.isEmpty else { return true }
        if token.allSatisfy(\.isNumber) { return true }
        if token.count == 1 { return true }
        if token.contains(".") { return true }
        return abbreviations.contains(token)
    }

    /// Wikipedia-Extrakte enthalten teils Navigationszeilen („Hauptstädte der Erde Hauptstädte Australiens …“):
    /// viele Wörter, fast alle großgeschrieben, kein Satzbau.
    nonisolated static func looksLikeNavigationList(_ sentence: String) -> Bool {
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 6 else { return false }
        let capitalized = words.filter { $0.first?.isUppercase == true }.count
        return Double(capitalized) / Double(words.count) > 0.6
    }

    /// Entfernt HTML aus Wikipedia-Suchausschnitten (`<span class="searchmatch">`) und Entities.
    private static func cleanSnippet(_ snippet: String) -> String {
        var text = snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&quot;", "\""), ("&amp;", "&"), ("&#039;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
