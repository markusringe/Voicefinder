//
//  ResponseSanitizer.swift
//  Voicefinder
//
//  Entfernt Meta-Text aus LLM-Antworten, bevor sie angezeigt oder gesprochen werden.
//

import Foundation

/// Bereinigt KI-Antworten für natürliche Sprachausgabe und Chat-Anzeige.
enum ResponseSanitizer: Sendable {
    /// Entfernt Qwen3-Thinking-Blöcke – die sind englisch und dürfen nicht gesprochen werden.
    nonisolated static func stripThinkingBlocks(_ raw: String) -> String {
        var text = raw

        // Vollständige Thinking-Blöcke (Qwen3-Special-Tokens).
        text = text.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )

        // Falls nur ein schließendes Tag übrig blieb: alles davor verwerfen.
        if let closeTag = text.range(of: "</think>") {
            text = String(text[closeTag.upperBound...])
        }

        // Unvollständiger Block am Anfang – Modell noch im Reasoning.
        if let openTag = text.range(of: "<think>") {
            text = String(text[..<openTag.lowerBound])
        }

        return text
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True, wenn der Text nicht klar englisch ist – Voicefinder ist deutschsprachig.
    nonisolated static func isPredominantlyGerman(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return true }
        if ResponseLanguage.isPredominantlyEnglish(trimmed) { return false }
        return true
    }

    /// Entfernt Regieanweisungen, Technik-Bezüge und typische Prompt-Leaks.
    nonisolated static func sanitizeForSpeech(_ raw: String) -> String {
        var text = stripThinkingBlocks(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Zeilen mit reinen Meta-Labels (z. B. „[Gesprächseröffnung – verbindlich]“).
        text = text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return false }
                if trimmed.hasPrefix("[") && trimmed.contains("]") { return false }
                return !isMetaOnlyLine(trimmed)
            }
            .joined(separator: " ")

        // Eckige Klammern mitten im Text entfernen.
        text = text.replacingOccurrences(
            of: #"\[[^\]]+\]"#,
            with: "",
            options: .regularExpression
        )

        // Prompt-Leaks aus der Nutzer-Rahmung.
        let leakPrefixes = [
            "Nutzer:",
            "Du (natürlich",
            "Du (",
            "[Sprache:",
            "Bekannter Vorname",
        ]
        for prefix in leakPrefixes where text.lowercased().hasPrefix(prefix.lowercased()) {
            if let range = text.range(of: ":", options: [], range: text.startIndex..<text.endIndex) {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        text = removeTechnologySentences(from: text)

        // Wiederholtes Wort direkt hintereinander (mit Leerzeichen) auf einmal reduzieren.
        text = text.replacingOccurrences(
            of: #"\b(\w+)(?:\s+\1){1,}\b"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = collapseWordStutter(in: text)
        text = stripEmojis(text)
        text = deduplicatedForSpeech(text)

        return text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Entfernt Emojis und Piktogramme – Piper/TTS kann damit nicht umgehen.
    nonisolated static func stripEmojis(_ text: String) -> String {
        String(
            text.filter { character in
                !character.unicodeScalars.contains(where: isEmojiScalar)
            }
        )
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True für Emoji-relevante Unicode-Scalar (ohne `Character.isEmoji` – breite SDK-Kompatibilität).
    nonisolated private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1F600...0x1F64F, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF, 0x1F700...0x1F77F,
             0x1F780...0x1F7FF, 0x1F800...0x1F8FF, 0x1F900...0x1F9FF, 0x1FA00...0x1FAFF,
             0x1FB00...0x1FBFF, 0x2600...0x26FF, 0x2700...0x27BF, 0x2300...0x23FF,
             0x2B50, 0x2B55, 0x231A...0x231B, 0x23E9...0x23F3, 0x23F8...0x23FA,
             0x25AA...0x25AB, 0x25B6, 0x25C0, 0x25FB...0x25FE, 0x2614...0x2615,
             0x2648...0x2653, 0x267F, 0x2693, 0x26A1, 0x26AA...0x26AB, 0x26BD...0x26BE,
             0x26C4...0x26C5, 0x26CE, 0x26D4, 0x26EA, 0x26F2...0x26F3, 0x26F5, 0x26FA,
             0x26FD, 0x2702, 0x2705, 0x2708...0x270D, 0x270F, 0x2712, 0x2714, 0x2716,
             0x271D, 0x2721, 0x2728, 0x2733...0x2734, 0x2744, 0x2747, 0x274C, 0x274E,
             0x2753...0x2755, 0x2757, 0x2763...0x2764, 0x2795...0x2797, 0x27A1, 0x27B0,
             0x27BF, 0x2934...0x2935, 0x2B05...0x2B07, 0x2B1B...0x2B1C, 0x3030, 0x303D,
             0x3297, 0x3299, 0xFE0F, 0x200D, 0x00A9, 0x00AE, 0x203C, 0x2049:
            return true
        case 0x1F1E6...0x1F1FF:
            return true
        default:
            return false
        }
    }

    /// Entfernt doppelte Sätze und hängt den Text für TTS wieder zusammen.
    nonisolated static func deduplicatedForSpeech(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        for _ in 0 ..< 3 {
            let before = result
            result = collapseImmediateWordRepetitions(result)
            result = deduplicateSentences(sentencesForSpeech(result)).joined(separator: " ")
            result = collapseRepeatedHalves(result).trimmingCharacters(in: .whitespacesAndNewlines)
            if result == before { break }
        }
        return result
    }

    /// Normalisiert Text für Duplikat-Vergleich (Groß/Klein, Satzzeichen, Umlaute).
    nonisolated static func normalizeForComparison(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True, wenn zwei Sätze inhaltlich dieselbe Aussage tragen.
    nonisolated static func sentencesAreDuplicates(_ a: String, _ b: String) -> Bool {
        let na = normalizeForComparison(a)
        let nb = normalizeForComparison(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }

        if na.count >= 8, nb.count >= 8, (na.contains(nb) || nb.contains(na)) {
            return true
        }

        let wordsA = na.split(whereSeparator: \.isWhitespace).map(String.init)
        let wordsB = nb.split(whereSeparator: \.isWhitespace).map(String.init)
        guard wordsA.count >= 3, wordsB.count >= 3 else {
            return na == nb
        }

        let setA = Set(wordsA)
        let setB = Set(wordsB)
        let overlap = setA.intersection(setB).count
        let minCount = min(setA.count, setB.count)
        return Double(overlap) / Double(minCount) >= 0.82
    }

    /// Entfernt unmittelbare Wortfolgen-Wiederholungen (z. B. „Hallo wie gehts Dir Hallo wie gehts Dir“).
    nonisolated static func collapseImmediateWordRepetitions(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 6 else { return text }

        for unitLength in stride(from: words.count / 2, through: 3, by: -1) {
            let first = words.prefix(unitLength).joined(separator: " ")
            let second = words.dropFirst(unitLength).prefix(unitLength).joined(separator: " ")
            if sentencesAreDuplicates(first, second) {
                return words.prefix(unitLength).joined(separator: " ")
            }
        }
        return text
    }

    /// Fängt exakte Wiederholungen am Textende ab – auch bei ungerader Länge.
    nonisolated static func collapseRepeatedHalves(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return trimmed }

        let normalized = normalizeForComparison(trimmed)
        for length in stride(from: normalized.count / 2, through: 6, by: -1) {
            let first = String(normalized.prefix(length)).trimmingCharacters(in: .whitespaces)
            let second = String(normalized.dropFirst(length)).trimmingCharacters(in: .whitespaces)
            guard first.count >= 6, !second.isEmpty else { continue }

            if second.hasPrefix(first) || sentencesAreDuplicates(first, String(second.prefix(first.count))) {
                return extractOriginalPrefix(matchingNormalizedLength: length, in: trimmed)
            }
        }
        return trimmed
    }

    /// Mappt eine normalisierte Länge zurück auf den Original-Text (erste Hälfte).
    nonisolated private static func extractOriginalPrefix(matchingNormalizedLength: Int, in original: String) -> String {
        var normCount = 0
        var endIndex = original.startIndex

        while endIndex < original.endIndex, normCount < matchingNormalizedLength {
            let char = original[endIndex]
            let piece = normalizeForComparison(String(char))
            normCount += piece.filter { !$0.isWhitespace }.count
            endIndex = original.index(after: endIndex)
        }

        return String(original[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True, wenn derselbe Inhalt innerhalb einer Antwort wiederholt vorkommt.
    nonisolated static func hasInternalDuplication(_ text: String) -> Bool {
        let sentences = sentencesForSpeech(text)
        return deduplicateSentences(sentences).count < sentences.count
    }

    /// True, wenn der Text mit einem vollständigen Satzzeichen endet.
    nonisolated static func endsWithCompleteSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?"
    }

    /// True nur wenn die Antwort wirklich mitten im Satz abbricht – nicht bei knappen oder informellen Antworten.
    nonisolated static func needsContinuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if endsWithCompleteSentence(trimmed) { return false }

        // Ellipsen und informelle Endungen gelten als bewusst abgeschlossen.
        if trimmed.hasSuffix("…") || trimmed.hasSuffix("...") { return false }

        let lower = trimmed.lowercased()
        // Offensichtlich abgebrochene Endungen – hier lohnt sich eine MLX-Fortsetzung.
        let incompleteSuffixes = [
            ",", ":", ";", " und", " oder", " aber", " weil", " dass", " wenn", " ob",
            " der", " die", " das", " ein", " eine", " zu", " mit", " von", " im", " am",
        ]
        if incompleteSuffixes.contains(where: { lower.hasSuffix($0) }) { return true }

        // Token-Limit-Abbruch mitten im Wort (Bindestrich am Ende).
        if trimmed.hasSuffix("-") { return true }

        // Längere Antwort ohne Satzzeichen: Satzzeichen nachziehen reicht – kein zweites MLX.
        return false
    }

    /// Bereitet den finalen Assistenten-Text für TTS vor – ein Durchlauf statt verstreuter Schritte.
    nonisolated static func finalizeAssistantResponse(
        raw: String,
        userMessage: String,
        userBrain: UserBrainProfile
    ) -> String {
        var text = sanitizeForSpeech(raw)
        text = recoverIfEmpty(
            sanitized: text,
            raw: raw,
            userMessage: userMessage,
            userBrain: userBrain
        )
        text = ensureTerminalPunctuation(text)
        return deduplicatedForSpeech(text)
    }

    /// Hängt fehlendes Satzzeichen an, wenn die Antwort inhaltlich fertig wirkt.
    nonisolated static func ensureTerminalPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if endsWithCompleteSentence(trimmed) { return trimmed }

        let lower = trimmed.lowercased()
        let questionHints = ["?", " wer ", " was ", " wie ", " wo ", " wann ", " warum ", " welche", " welcher", " welches", " kannst", " könntest", " hast du", " bist du", " soll ", " oder "]
        if trimmed.contains("?") || questionHints.contains(where: { lower.contains($0) }) {
            return trimmed + "?"
        }
        return trimmed + "."
    }

    /// True, wenn der Text mit einer üblichen Begrüßung beginnt.
    nonisolated static func startsWithGreeting(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        let prefixes = [
            "hallo", "hi", "hey", "servus", "moin", "grüß", "gruess", "guten tag",
            "guten morgen", "guten abend", "gute nacht", "willkommen",
        ]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// Stellt sicher, dass eine Gesprächseröffnung mit Begrüßung beginnt.
    nonisolated static func ensureOpeningGreeting(_ text: String, assistantName: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard !startsWithGreeting(trimmed) else { return trimmed }

        let name = assistantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            return "Hallo! \(trimmed)"
        }
        return "Hallo! \(trimmed)"
    }

    /// Entfernt doppelte oder sehr ähnliche Sätze – typisch nach LLM-Fortsetzungen.
    nonisolated static func deduplicateSentences(_ sentences: [String]) -> [String] {
        var result: [String] = []
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { continue }

            let isDuplicate = result.contains { existing in
                sentencesAreDuplicates(existing, trimmed)
            }
            if !isDuplicate {
                result.append(trimmed)
            }
        }
        return result
    }

    /// Kürzt Eröffnungen auf wenige Sätze – Begrüßung plus höchstens eine Frage.
    nonisolated static func compactForOpening(
        _ text: String,
        maxSentences: Int = 2,
        maxCharacters: Int = 150
    ) -> String {
        var sentences = deduplicateSentences(sentencesForSpeech(text))
        guard !sentences.isEmpty else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        sentences = Array(sentences.prefix(maxSentences))

        // Unvollständigen Restsatz verwerfen, wenn schon ein vollständiger Satz da ist.
        if sentences.count > 1,
           let last = sentences.last,
           !endsWithCompleteSentence(last) {
            sentences.removeLast()
        }

        var result = sentences.joined(separator: " ")
        if result.count > maxCharacters {
            result = limitForSpeech(result, maxCharacters: maxCharacters)
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty, !endsWithCompleteSentence(result) {
            result += "?"
        }
        return result
    }

    /// Fügt eine LLM-Fortsetzung an einen abgebrochenen Satz an.
    nonisolated static func mergeContinuation(partial: String, continuation: String) -> String {
        let head = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        var tail = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return head }
        guard !head.isEmpty else { return tail }

        // Doppelte Wiederholung am Anfang der Fortsetzung entfernen.
        let headWords = head.split(whereSeparator: \.isWhitespace).suffix(4).map { String($0).lowercased() }
        let tailWords = tail.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
        if headWords.count >= 2, tailWords.count >= headWords.count {
            let headSuffix = Array(headWords)
            let tailPrefix = Array(tailWords.prefix(headSuffix.count))
            if headSuffix == tailPrefix {
                let dropCount = headSuffix.count
                tail = tail.split(whereSeparator: \.isWhitespace).dropFirst(dropCount).joined(separator: " ")
            }
        }

        guard !tail.isEmpty else { return head }

        // Fortsetzung wiederholt die ganze bisherige Antwort – verwerfen.
        if textsAreSimilar(head, tail) || head.lowercased() == tail.lowercased() {
            return deduplicatedForSpeech(head)
        }

        var merged = head
        if endsWithCompleteSentence(head) {
            merged = head + " " + tail
        } else {
            merged = head + " " + tail
        }
        return deduplicatedForSpeech(merged)
    }

    /// Teilt Text in vollständige Sätze für sequenzielles Vorlesen – ohne Kürzung.
    nonisolated static func sentencesForSpeech(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        var current = ""

        for character in trimmed {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        return sentences.isEmpty ? [trimmed] : sentences
    }

    /// Kürzt lange Antworten für TTS – nur an Satzende, nie mitten im Satz.
    nonisolated static func limitForSpeech(_ text: String, maxCharacters: Int = 260) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }

        let prefix = String(trimmed.prefix(maxCharacters))
        for terminator in [".", "!", "?"] {
            if let range = prefix.range(of: terminator, options: .backwards) {
                return String(trimmed[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Kein Satzende im Fenster – vollständigen Text behalten statt mitten im Satz abzuschneiden.
        return trimmed
    }

    /// Entfernt stotternde Wort-Wiederholungen (z. B. „leider leider leider …“).
    /// Vergleicht Wörter ohne Satzzeichen, behält aber den Originaltext – Satzzeichen steuern Piper-Pausen und Betonung.
    nonisolated static func collapseWordStutter(in text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3 else { return text }

        func comparisonKey(_ word: String) -> String {
            word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…")).lowercased()
        }

        var result: [String] = []
        var index = 0
        while index < words.count {
            let current = comparisonKey(words[index])
            var runLength = 1
            while !current.isEmpty,
                  index + runLength < words.count,
                  comparisonKey(words[index + runLength]) == current {
                runLength += 1
            }

            // Letztes Wort der Wiederholung behalten – trägt das abschließende Satzzeichen.
            result.append(words[index + runLength - 1])
            index += runLength
        }

        return result.joined(separator: " ")
    }

    /// True, wenn ein Wort zu oft hintereinander vorkommt (Modell-Stottern).
    nonisolated static func hasExcessiveWordStutter(_ text: String, maxRepeats: Int = 3) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?")).lowercased() }
            .filter { !$0.isEmpty }
        guard words.count >= maxRepeats + 1 else { return false }

        var runLength = 1
        for index in 1 ..< words.count {
            if words[index] == words[index - 1] {
                runLength += 1
                if runLength > maxRepeats { return true }
            } else {
                runLength = 1
            }
        }
        return false
    }

    /// True, wenn die neue Antwort fast wortgleich der letzten Assistenten-Antwort ist.
    nonisolated static func isRepeatingLoop(
        candidate: String,
        recentAssistantTexts: [String],
        userTurnCount: Int = Int.max
    ) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return false }
        guard let previous = recentAssistantTexts.last else { return false }

        let normalizedA = trimmed.lowercased()
        let normalizedB = previous.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedA == normalizedB { return true }

        // Erste Nutzer-Runde nach Eröffnung: thematische Ähnlichkeit ist normal.
        if userTurnCount <= 1 { return false }

        // Nur bei nahezu gleichem Inhalt – nicht bei ähnlicher Satzstruktur im selben Thema.
        return contentWordsAreNearlyIdentical(trimmed, previous, threshold: 0.97)
    }

    /// True, wenn der Nutzer sich über Wiederholungen beschwert.
    nonisolated static func isUserFrustratedAboutRepetition(_ userMessage: String) -> Bool {
        let lower = userMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hints = [
            "immer dasselbe", "schon wieder", "wiederholst", "fragst du mich immer",
            "hab ich schon", "habe ich schon", "noch mal", "nochmal", "das hast du schon",
            "immer die gleiche", "immer wieder",
        ]
        return hints.contains { lower.contains($0) }
    }

    /// Kurze Entschuldigung, wenn der Nutzer Wiederholungen moniert.
    nonisolated static func apologyForRepetition(userMessage: String) -> String {
        let lower = userMessage.lowercased()
        if lower.contains("?") {
            return "Stimmt, sorry – ich wiederhole mich da. Was möchtest du als Nächstes klären?"
        }
        return "Stimmt, entschuldige – ich frage nicht noch mal dasselbe. Erzähl einfach weiter."
    }

    /// Entfernt eine Folgefrage, wenn sie der letzten KI-Frage zu ähnlich ist.
    nonisolated static func removingRepeatedFollowUp(
        from candidate: String,
        recentAssistantTexts: [String]
    ) -> String {
        var sentences = deduplicateSentences(sentencesForSpeech(candidate))
        guard sentences.count >= 2 else { return candidate }

        let lastSentence = sentences[sentences.count - 1]
        guard lastSentence.contains("?") else { return candidate }

        // Alle Fragen der letzten Antworten prüfen – nicht nur die letzte: Wurde eine Wiederholung schon
        // entfernt, endet die gespeicherte Antwort ohne Frage, und die Frage käme sonst eine Runde später zurück.
        let previousQuestions = recentAssistantTexts
            .flatMap { sentencesForSpeech($0) }
            .filter { $0.contains("?") }
        if previousQuestions.contains(where: { followUpQuestionsAreSimilar(lastSentence, $0) }) {
            sentences.removeLast()
            let joined = sentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return ensureTerminalPunctuation(joined)
        }
        return candidate
    }

    /// Deutsche Funktionswörter – für Ähnlichkeitsvergleiche ignorieren.
    nonisolated private static let germanStopWords: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "einem", "einen",
        "und", "oder", "aber", "doch", "nicht", "auch", "noch", "schon", "mal", "gern", "gerne",
        "ich", "du", "sie", "er", "es", "wir", "ihr", "mir", "dir", "mich", "dich", "dein", "deine",
        "deinen", "deiner", "mein", "meine", "was", "wie", "wo", "wann", "warum", "wenn", "dass",
        "ist", "sind", "war", "bin", "bist", "hat", "hab", "habe", "hast", "auf", "mit", "für",
        "von", "zu", "im", "am", "an", "als", "sehr", "so", "ja", "nein", "halt", "eben", "denn",
        "nun", "hier", "da", "dann", "dazu", "damit", "nochmal",
    ]

    /// Inhaltswörter ohne Stoppwörter – für robustere Schleifen-Erkennung.
    nonisolated private static func contentWords(in text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?\"'")) }
                .filter { word in
                    word.count >= 3 && !germanStopWords.contains(word)
                }
        )
    }

    /// True, wenn zwei Texte inhaltlich fast identisch sind (ohne Stoppwörter).
    nonisolated private static func contentWordsAreNearlyIdentical(
        _ a: String,
        _ b: String,
        threshold: Double
    ) -> Bool {
        let wordsA = contentWords(in: a)
        let wordsB = contentWords(in: b)
        guard wordsA.count >= 5, wordsB.count >= 5 else { return false }

        let overlap = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)
        return Double(overlap) / Double(minCount) >= threshold
    }

    /// True, wenn zwei Folgefragen inhaltlich dieselbe Richtung haben.
    /// Kurze Rückfragen („Was bringst du heute mit?“) haben zu wenige Inhaltswörter für den Inhaltsvergleich
    /// (mindestens 5) – daher zusätzlich der normalisierte Satzvergleich.
    nonisolated private static func followUpQuestionsAreSimilar(_ a: String, _ b: String) -> Bool {
        sentencesAreDuplicates(a, b) || contentWordsAreNearlyIdentical(a, b, threshold: 0.82)
    }

    /// True bei leeren Bestätigungen ohne Gesprächsführung.
    nonisolated static func isWeakAcknowledgment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard trimmed.count <= 56 else { return false }

        let lower = trimmed
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let weakExact = [
            "okay", "ok", "alles klar", "verstanden", "alles klar verstanden",
            "gut", "na gut", "achso", "mhm", "hm", "jo", "jep", "ja klar",
        ]
        if weakExact.contains(lower) { return true }

        // Nur exakte Floskeln – keine Längen-Heuristik, die gültige Kurzantworten verwirft.
        return false
    }

    /// Engagierte Ersatz-Antwort mit Folgefrage – hält das Gespräch am Laufen.
    nonisolated static func engagedFallback(forUserMessage userText: String, userBrain: UserBrainProfile) -> String {
        let hasMission = !userBrain.resolvedMission.isEmpty
        let lower = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lower.contains("app") || lower.contains("anwendung") || lower.contains("programm") {
            if hasMission {
                return "Ja, genau. Was würdest du mir dazu gern noch erzählen?"
            }
            return "Ja, klar. Wie siehst du das denn?"
        }

        if lower.contains("termin") {
            return "Passt dir das so? Sag mir gern, was dir wichtig wäre."
        }

        if lower.contains("wie spät") || lower.contains("wie viel uhr") || lower.contains("welche uhrzeit") {
            return "Das kann ich gerade nicht genau sagen. Brauchst du es für heute?"
        }

        if MissionQuestionDetector.isRoleOrMissionQuestion(userText), hasMission {
            return "Gute Frage. Ich bin neugierig – wie würdest du das selbst beschreiben?"
        }

        if hasMission {
            if lower.contains("?") {
                return "Gute Frage. Ich würde gern verstehen, wie du das siehst – was denkst du selbst dazu?"
            }
            return "Das klingt interessant. Erzähl mir gern noch ein bisschen mehr darüber."
        }

        if lower.contains("?") {
            return "Gute Frage. Was meinst du damit genau?"
        }
        return "Verstehe. Was bewegt dich dabei am meisten?"
    }

    /// Kurze Ersatz-Antwort, wenn das Modell in eine Schleife gerät.
    nonisolated static func antiLoopFallback(forUserMessage userText: String, hasMission: Bool) -> String {
        var profile = UserBrainProfile()
        if hasMission {
            profile.mission = "aktiv"
        }
        return engagedFallback(forUserMessage: userText, userBrain: profile)
    }

    /// Entfernt Sätze mit Technik-/App-Bezug – die KI soll wie ein Mensch klingen.
    nonisolated private static func removeTechnologySentences(from text: String) -> String {
        let parts = splitIntoSentences(text)
        let filtered = parts.filter { sentence in
            !containsTechnologyReference(sentence)
        }
        let joined = filtered.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? fallbackWithoutTechnology(from: text) : joined
    }

    /// True, wenn der Satz App/KI/Computer erwähnt.
    nonisolated private static func containsTechnologyReference(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let banned = [
            "app", "voicefinder", "anwendung", "software", "computer",
            "programm", "sprachassistent", "künstliche intelligenz", " ki ",
            " als ki", "ich bin ein bot", "ich bin eine ki", "hier in der",
            "in dieser app", "computeranwendung", "technologie", "algorithmus",
        ]
        return banned.contains { lower.contains($0) }
    }

    /// Wenn alle Sätze gefiltert wurden: offensichtliche Tech-Begriffe ersetzen statt leer zu bleiben.
    nonisolated private static func fallbackWithoutTechnology(from text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("in der App", ""),
            ("in dieser App", ""),
            ("hier in der App", ""),
            ("Voicefinder", ""),
            ("Computeranwendung", ""),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func splitIntoSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "?", with: "?|")
            .replacingOccurrences(of: "!", with: "!|")
            .replacingOccurrences(of: ".", with: ".|")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Grober Textvergleich für Schleifen-Erkennung.
    nonisolated private static func textsAreSimilar(_ a: String, _ b: String) -> Bool {
        let normalizedA = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedB = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedA.isEmpty, !normalizedB.isEmpty else { return false }

        if normalizedA == normalizedB { return true }

        let wordsA = Set(normalizedA.split(whereSeparator: { $0.isWhitespace }))
        let wordsB = Set(normalizedB.split(whereSeparator: { $0.isWhitespace }))
        guard wordsA.count >= 5, wordsB.count >= 5 else { return false }

        let overlap = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)
        return Double(overlap) / Double(minCount) >= 0.92
    }

    /// Falls die Bereinigung alles entfernt hat: leichtere Rettung oder Auftrags-Fallback.
    nonisolated static func recoverIfEmpty(
        sanitized: String,
        raw: String,
        userMessage: String,
        userBrain: UserBrainProfile
    ) -> String {
        if !sanitized.isEmpty { return sanitized }

        if let direct = MissionQuestionDetector.directSpokenAnswer(for: userMessage, userBrain: userBrain) {
            return direct
        }

        let fallback = fallbackWithoutTechnology(from: raw)
        if !fallback.isEmpty { return fallback }

        return antiLoopFallback(
            forUserMessage: userMessage,
            userBrain: userBrain
        )
    }

    /// Kompatibilitäts-Overload mit Profil.
    nonisolated static func antiLoopFallback(forUserMessage userText: String, userBrain: UserBrainProfile) -> String {
        engagedFallback(forUserMessage: userText, userBrain: userBrain)
    }

    /// True, wenn die Zeile nur interne Regie/Meta ist und nicht gesprochen werden soll.
    nonisolated private static func isMetaOnlyLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let metaKeywords = [
            "intermezzo",
            "gesprächseröffnung",
            "gespraechseroeffnung",
            "erstes gespräch",
            "erstes gespraech",
            "auftrag:",
            "mein auftrag",
            "profil im gespräch",
            "ki-gehirn",
            "system-prompt",
            "regie:",
            "anweisung:",
            "intern:",
            "meine rolle",
            "ich bin ein arzt und habe",
        ]
        return metaKeywords.contains { lower.contains($0) }
    }
}
