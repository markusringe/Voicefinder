//
//  MissionQuestionDetector.swift
//  Voicefinder
//
//  Erkennt Fragen an die KI-Rolle – ohne Wikipedia/LLM beantwortbar.
//

import Foundation

/// Entscheidet, ob eine Nutzerfrage die interne Rolle/Auftrag betrifft (kein Web nötig).
enum MissionQuestionDetector: Sendable {
    /// Typische Formulierungen zu Rolle, Auftrag oder Identität der KI.
    nonisolated private static let roleQuestionHints = [
        "dein auftrag", "deine rolle", "dein job", "deine aufgabe",
        "was ist dein", "was sollst du", "was machst du hier", "warum rufst",
        "wieso rufst", "weshalb rufst", "wer bist du", "wie heißt du",
        "was willst du", "was brauchst du", "worum geht", "was ist los",
        "why are you calling", "who are you", "what is your role",
    ]

    /// True, wenn die Frage die KI-Rolle betrifft – Web-Recherche wäre kontraproduktiv.
    nonisolated static func isRoleOrMissionQuestion(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 4 else { return false }
        return roleQuestionHints.contains { lower.contains($0) }
    }

    /// Kurze gesprochene Antwort aus dem KI-Gehirn – ohne Meta-Regie.
    nonisolated static func directSpokenAnswer(
        for userText: String,
        userBrain: UserBrainProfile
    ) -> String? {
        guard isRoleOrMissionQuestion(userText) else { return nil }

        let lower = userText.lowercased()
        let mission = userBrain.resolvedMission.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantName = userBrain.assistantName.trimmingCharacters(in: .whitespacesAndNewlines)

        if lower.contains("wie heißt") || lower.contains("wer bist du") {
            if !assistantName.isEmpty {
                return "Ich bin \(assistantName)."
            }
            if !mission.isEmpty {
                return spokenMissionLine(mission)
            }
            return "Ich bin’s – wir telefonieren gerade."
        }

        guard !mission.isEmpty else {
            return "Gute Frage – ich bin noch nicht ganz sicher, worum’s genau geht."
        }

        return spokenMissionLine(mission)
    }

    /// Formuliert den Auftrag als natürlichen Dialogsatz (ohne „Mein Auftrag ist …“).
    nonisolated private static func spokenMissionLine(_ mission: String) -> String {
        let trimmed = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Da bin ich gerade etwas unsicher." }

        // Bereits dialogisch formuliert – unverändert übernehmen.
        if trimmed.hasSuffix("?") || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") {
            return trimmed
        }
        return trimmed + "."
    }
}
