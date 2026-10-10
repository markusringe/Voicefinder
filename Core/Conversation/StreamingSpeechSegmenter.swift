//
//  StreamingSpeechSegmenter.swift
//  Voicefinder
//
//  Erkennt sprechbare Satzgrenzen im LLM-Stream für frühes TTS.
//

import Foundation

/// Hilfsfunktionen, um aus gestreamtem LLM-Text früh sprechbare Segmente zu extrahieren.
enum StreamingSpeechSegmenter: Sendable {
    /// Mindestlänge eines Satzes, bevor er vorgelesen wird (kürzere werden mit dem Folgesatz gebündelt).
    nonisolated static let minimumEarlySentenceLength = 10

    /// Abkürzungen, deren Punkt kein Satzende ist (ohne Punkt, kleingeschrieben).
    private nonisolated static let abbreviations: Set<String> = [
        "bzw", "ca", "dr", "nr", "usw", "etc", "evtl", "ggf", "inkl", "bspw",
        "st", "str", "prof", "vgl", "zb", "mio", "mrd", "min", "max", "bzgl", "ugs",
    ]

    /// Erster abgeschlossener Satz und der Text danach.
    ///
    /// Ein Satz gilt erst als abgeschlossen, wenn nach dem Satzzeichen bereits Leerraum folgt –
    /// sonst könnte „3.“ oder „z.“ im Stream noch zu einem Datum oder einer Abkürzung gehören.
    nonisolated static func firstCompletedSentence(in text: String) -> (sentence: String, remainder: String)? {
        let characters = Array(text)
        guard characters.count > minimumEarlySentenceLength else { return nil }

        for index in characters.indices.dropLast() {
            let character = characters[index]
            guard character == "." || character == "!" || character == "?" || character == "…" else { continue }
            guard characters[index + 1].isWhitespace else { continue }
            if character == ".", isNonTerminalPeriod(at: index, in: characters) { continue }

            let sentence = String(characters[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sentence.count >= minimumEarlySentenceLength else { continue }

            let remainder = String(characters[(index + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (sentence, remainder)
        }
        return nil
    }

    /// Text, der nach einem bereits gesprochenen Satzanfang noch vorgelesen werden muss.
    ///
    /// `nil`, wenn der finale Text nicht mit dem gesprochenen Satz beginnt (z. B. regelbasierter Fallback).
    nonisolated static func remainder(of finalText: String, afterSpoken spokenSentence: String) -> String? {
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spokenKey = ResponseSanitizer.normalizeForComparison(spokenSentence)
        guard !spokenKey.isEmpty else { return nil }

        if let (sentence, remainder) = firstCompletedSentence(in: trimmed),
           ResponseSanitizer.normalizeForComparison(sentence) == spokenKey {
            return remainder
        }

        // Finaler Text ist genau der gesprochene Satz (ggf. mit nachgezogenem Satzzeichen).
        if ResponseSanitizer.normalizeForComparison(trimmed) == spokenKey {
            return ""
        }

        if trimmed.hasPrefix(spokenSentence) {
            return String(trimmed.dropFirst(spokenSentence.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// True, wenn der Punkt zu einer Zahl („3. Oktober“) oder Abkürzung („z. B.“) gehört.
    private nonisolated static func isNonTerminalPeriod(at index: Int, in characters: [Character]) -> Bool {
        var start = index
        while start > 0, !characters[start - 1].isWhitespace {
            start -= 1
        }
        let token = String(characters[start..<index])
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "(\"„“'"))
        guard !token.isEmpty else { return false }

        if token.allSatisfy(\.isNumber) { return true }
        if token.count == 1, token.first?.isLetter == true { return true }
        // „z.B.“ / „d.h.“ ohne Leerzeichen.
        if token.contains(".") { return true }
        return abbreviations.contains(token)
    }
}
