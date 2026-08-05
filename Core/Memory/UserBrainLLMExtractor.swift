//
//  UserBrainLLMExtractor.swift
//  Voicefinder
//
//  Extrahiert persönliche Fakten per lokalem LLM für das KI-Gehirn.
//

import Foundation

/// Kandidat für einen neuen Profil-Eintrag.
struct UserBrainFactCandidate: Sendable, Equatable {
    let label: String
    let value: String
}

/// Nutzt das eingebettete MLX-Modell, um interessante Nutzer-Fakten zu erkennen.
enum UserBrainLLMExtractor: Sendable {
    /// Extrahiert neue Fakten – leeres Array bei Fehler oder wenn nichts Neues erkannt wurde.
    nonisolated static func extractFacts(
        from userMessage: String,
        existingProfile: UserBrainProfile
    ) async -> [UserBrainFactCandidate] {
        guard LLMModelProvider.isSupported else { return [] }
        guard await MLXChatService.shared.isReady else { return [] }

        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return [] }

        let knownSummary = existingProfile.profilePromptBlock() ?? "Noch keine Infos bekannt."

        let prompt = """
        Aufgabe: Extrahiere NUR neue persönliche Fakten über den Nutzer aus seiner Nachricht.
        Bekanntes Profil:
        \(knownSummary)

        Regeln:
        - Antworte NUR mit JSON-Array, z. B. [{"label":"Beruf","value":"Lehrer"}]
        - Label kurz auf Deutsch – bevorzugt Standardfelder: Vorname, Nachname, Geschlecht, Beruf, Straße, Wohnort, Alter, Hobbies, Familienstand, Auto, Größe, Haustiere, Lieblingsfarbe
        - Oder andere kurze Labels (Lieblingsessen, Sport, Kind, etc.)
        - Keine Fakten wiederholen, die schon bekannt sind
        - Kein Markdown, kein Text außerhalb des JSON
        - Leeres Array [] wenn nichts Neues

        Nutzer sagt: \(trimmed)
        JSON:
        """

        guard let raw = await MLXChatService.shared.generateCompactReply(prompt: prompt) else {
            return []
        }

        return parseCandidates(from: raw)
    }

    /// Parst LLM-Ausgabe in strukturierte Kandidaten.
    nonisolated private static func parseCandidates(from raw: String) -> [UserBrainFactCandidate] {
        let cleaned = extractJSONArray(from: raw)
        guard let data = cleaned.data(using: .utf8) else { return [] }

        struct PayloadItem: Decodable {
            let label: String
            let value: String
        }

        guard let items = try? JSONDecoder().decode([PayloadItem].self, from: data) else {
            return []
        }

        return items.compactMap { item in
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !value.isEmpty, label.count <= 40, value.count <= 120 else {
                return nil
            }
            return UserBrainFactCandidate(label: label, value: value)
        }
    }

    /// Isoliert das erste JSON-Array aus der Modell-Antwort.
    nonisolated private static func extractJSONArray(from text: String) -> String {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end else {
            return "[]"
        }
        return String(text[start...end])
    }
}
