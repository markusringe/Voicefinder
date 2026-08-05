//
//  RuleBasedLanguageEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Offline-Regelanalyse: Schlüsselwort-Matching ohne Modell – sofort einsatzbereit.
struct RuleBasedLanguageAnalyzer: LanguageAnalyzing, Sendable {
    nonisolated init() {}

    nonisolated func analyze(text: String, context: [ChatTurn]) async throws -> LanguageAnalysis {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty {
            return LanguageAnalysis(
                intent: .empty,
                response: "Ich habe nichts verstanden. Bitte versuche es noch einmal.",
                suggestedAction: .none
            )
        }

        if matches(normalized, any: ["hallo", "hi", "hey", "guten tag", "servus", "moin"]) {
            return LanguageAnalysis(
                intent: .greeting,
                response: "Hallo! Wie kann ich dir helfen?",
                suggestedAction: SuggestedAction(kind: .none, label: "Weiter zuhören")
            )
        }

        if matches(normalized, any: ["hilfe", "help", "was kannst du", "was machst du"]) {
            return LanguageAnalysis(
                intent: .help,
                response: """
                Ich bin Voicefinder, dein lokaler Sprachassistent. \
                Du kannst sprechen, Text eingeben oder das Sample testen. \
                Ich antworte auf Deutsch und laufe weitgehend auf dem Gerät.
                """,
                suggestedAction: SuggestedAction(kind: .showHelp, label: "Hilfe anzeigen")
            )
        }

        if matches(normalized, any: ["uhrzeit", "wie spät", "wie spaet", "datum", "welcher tag"]) {
            return LanguageAnalysis(
                intent: .timeQuery,
                response: "Es ist \(Self.formattedDateTime()).",
                suggestedAction: .none
            )
        }

        if matches(normalized, any: ["danke", "vielen dank", "super", "perfekt"]) {
            return LanguageAnalysis(
                intent: .thanks,
                response: "Gern geschehen! Melde dich, wenn du noch etwas brauchst.",
                suggestedAction: .none
            )
        }

        if matches(normalized, any: ["tschüss", "tschuess", "bye", "ciao", "auf wiedersehen"]) {
            return LanguageAnalysis(
                intent: .farewell,
                response: "Tschüss! Bis zum nächsten Mal.",
                suggestedAction: .none
            )
        }

        if let previousAssistant = context.last(where: { $0.role == .assistant })?.text,
           matches(normalized, any: ["nochmal", "wiederhole", "was hast du gesagt"]) {
            return LanguageAnalysis(
                intent: .repeatLast,
                response: "Zuletzt habe ich gesagt: \(previousAssistant)",
                suggestedAction: SuggestedAction(kind: .repeatLastResponse, label: "Antwort wiederholen")
            )
        }

        return LanguageAnalysis(
            intent: .unknown,
            response: "Du meintest „\(text)“. Darauf habe ich noch keine spezielle Antwort, aber ich habe dich verstanden.",
            suggestedAction: SuggestedAction(kind: .none, label: "Allgemeine Antwort")
        )
    }

    /// Prüft, ob einer der Schlüsselbegriffe im normalisierten Text vorkommt.
    nonisolated private func matches(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    /// Datums-/Uhrzeit-String für Antworten – statisch, damit kein MainActor nötig ist.
    nonisolated private static func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

/// Regelbasierte `LanguageEngine` – streamt die lokale Antwort aus der Analyse.
struct RuleBasedLanguageEngine: LanguageEngine, Sendable {
    private let analyzer: RuleBasedLanguageAnalyzer

    /// Standard: eingebauter Regelanalysator ohne externe Abhängigkeiten.
    nonisolated init() {
        self.analyzer = RuleBasedLanguageAnalyzer()
    }

    nonisolated init(analyzer: RuleBasedLanguageAnalyzer) {
        self.analyzer = analyzer
    }

    /// Vollständige Analyse inkl. Intent und Aktionsvorschlag (für Orchestrator/UI später).
    nonisolated func analyze(text: String, context: [ChatTurn]) async throws -> LanguageAnalysis {
        try await analyzer.analyze(text: text, context: context)
    }

    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        _ = options
        let analysis = try await analyzer.analyze(text: text, context: context)
        let chunks = Self.chunk(analysis.response)

        return AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    /// Teilt die Antwort in kurze Streaming-Häppchen für TTS und UI.
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
}
