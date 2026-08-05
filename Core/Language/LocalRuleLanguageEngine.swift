//
//  LocalRuleLanguageEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Einfache lokale Antwortlogik auf Basis fester Regeln – vollständig offline.
///
/// Ersetzt den Echo-Stub durch sinnvolle Kurzantworten auf Deutsch, bis ein
/// on-device LLM (z. B. Core ML / llama.cpp) angebunden wird.
struct LocalRuleLanguageEngine: LanguageEngine, Sendable {
    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        _ = options
        let response = Self.makeResponse(for: text, context: context)
        let chunks = Self.chunk(response)

        return AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    /// Erzeugt eine passende Antwort anhand von Schlüsselwörtern und Kontext.
    nonisolated private static func makeResponse(for text: String, context: [ChatTurn]) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty {
            return "Ich habe nichts verstanden. Bitte versuche es noch einmal."
        }

        if matches(normalized, any: ["hallo", "hi", "hey", "guten tag", "servus", "moin"]) {
            return "Hallo! Wie kann ich dir helfen?"
        }

        if matches(normalized, any: ["hilfe", "help", "was kannst du", "was machst du"]) {
            return """
            Ich bin Voicefinder, dein lokaler Sprachassistent. \
            Du kannst sprechen, Text eingeben oder das Sample testen. \
            Ich antworte auf Deutsch und laufe weitgehend auf dem Gerät.
            """
        }

        if matches(normalized, any: ["uhrzeit", "wie spät", "wie spaet", "datum", "welcher tag"]) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            return "Es ist \(formatter.string(from: Date()))."
        }

        if matches(normalized, any: ["danke", "vielen dank", "super", "perfekt"]) {
            return "Gern geschehen! Melde dich, wenn du noch etwas brauchst."
        }

        if matches(normalized, any: ["tschüss", "tschuess", "bye", "ciao", "auf wiedersehen"]) {
            return "Tschüss! Bis zum nächsten Mal."
        }

        if let previousAssistant = context.last(where: { $0.role == .assistant })?.text,
           matches(normalized, any: ["nochmal", "wiederhole", "was hast du gesagt"]) {
            return "Zuletzt habe ich gesagt: \(previousAssistant)"
        }

        return "Du meintest „\(text)“. Darauf habe ich noch keine spezielle Antwort, aber ich habe dich verstanden."
    }

    /// Teilt die Antwort in kurze Streaming-Häppchen für die UI.
    nonisolated private static func chunk(_ text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return [text] }

        var chunks: [String] = []
        var current = ""

        for word in words {
            if current.isEmpty {
                current = String(word)
            } else {
                current += " \(word)"
            }

            if current.count >= 24 {
                chunks.append(current + " ")
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.isEmpty ? [text] : chunks
    }

    nonisolated private static func matches(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
