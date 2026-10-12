//
//  LanguageEngine.swift
//  Voicefinder
//
//  Protokolle, Stile und Charakter-Persistenz für die Language-Pipeline.
//

import Foundation

// MARK: - KI-Antwort-Stile

/// Beeinflusst Ton und Verhalten der KI – wählbar unter „KI-Eigenschaften“.
enum AIInteractionStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case normal
    case forsch
    case frech
    case lustig
    case schlau

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .normal: "Normal"
        case .forsch: "Forsch"
        case .frech: "Frech"
        case .lustig: "Lustig"
        case .schlau: "Schlau"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .normal:
            "Freundlich, klar und ausgewogen – der Alltags-Assistent."
        case .forsch:
            "Direkt und energisch – kommt schnell auf den Punkt."
        case .frech:
            "Frech mit Augenzwinkern – provokant, aber nicht gemein."
        case .lustig:
            "Humorvoll und locker – Antworten sollen unterhalten."
        case .schlau:
            "Klug und präzise – kurze Erklärungen mit Mehrwert."
        }
    }

    /// Ton-Vorgabe für den System-Prompt – eine Zeile, damit kleine Modelle ihr folgen statt sie zu zitieren.
    nonisolated var styleDirective: String {
        switch self {
        case .normal: "Dein Ton: freundlich, klar und ausgewogen."
        case .forsch: "Dein Ton: direkt und selbstbewusst, ohne Umschweife."
        case .frech: "Dein Ton: frech mit Augenzwinkern, aber nie beleidigend – du hilfst trotzdem zuverlässig."
        case .lustig: "Dein Ton: humorvoll und locker, gern mit einem kleinen Witz."
        case .schlau: "Dein Ton: klug und präzise, gern mit einer kurzen Einordnung."
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .normal: "person.crop.circle"
        case .forsch: "bolt.fill"
        case .frech: "face.smiling.inverse"
        case .lustig: "theatermasks.fill"
        case .schlau: "lightbulb.fill"
        }
    }
}

// MARK: - Antwort-Optionen

/// Steuerung für Antwortgenerierung (Charakter, Stil, Web, KI-Gehirn).
struct LanguageReplyOptions: Sendable, Equatable {
    var characterPrompt: String
    var interactionStyle: AIInteractionStyle
    var internetEnabled: Bool
    var isConversationOpening: Bool
    var userBrain: UserBrainPromptContext

    nonisolated init(
        characterPrompt: String = "",
        interactionStyle: AIInteractionStyle = .normal,
        internetEnabled: Bool = false,
        isConversationOpening: Bool = false,
        userBrain: UserBrainPromptContext = UserBrainPromptContext()
    ) {
        self.characterPrompt = characterPrompt
        self.interactionStyle = interactionStyle
        self.internetEnabled = internetEnabled
        self.isConversationOpening = isConversationOpening
        self.userBrain = userBrain
    }
}

// MARK: - Charakter-Persistenz

/// Persistiert den KI-Charakter (System-Prompt) und baut LLM-Prompts.
enum CharacterProfileStore {
    nonisolated static let userDefaultsKey = "voicefinder.characterPrompt"

    /// Standard-Charakter – kurz und in natürlicher Sprache; Regeln stehen in `answerRules`.
    nonisolated static let defaultPrompt = """
    Du bist ein freundlicher, aufmerksamer Gesprächspartner. \
    Ihr unterhaltet euch mündlich auf Deutsch und duzt euch.
    """

    /// Frühere Standard-Charaktere – gespeichert gelten sie weiter als Standard, nicht als eigener Charakter.
    nonisolated static let legacyDefaultPrompts = [
        """
        Du bist ein freundlicher, menschlich klingender Gesprächspartner in einer Voice-App.
        Sprich natürlich, wie in einem echten Gespräch – warm, konkret und auf den Nutzer bezogen.

        Regeln:
        - Antworte auf Deutsch in idiomatischer Umgangssprache.
        - Pro Antwort: ein bis drei vollständige Sätze (etwa 20–50 Wörter).
        - Beantworte die Frage oder das Anliegen direkt – nicht ausweichen, wenn der Kontext klar ist.
        - Stelle höchstens EINE Folgefrage; keine redundanten Rückfragen zu bereits Gesagtem.
        - Beende jeden Satz mit . oder ? – keine halben Sätze oder abgebrochenen Fragmente.
        - Kein Markdown, keine Listen, keine Meta-Kommentare – nur gesprochener Dialog.
        - Vermeide leere Floskeln wie „Alles klar“, „Verstanden“ oder „Okay“ allein.
        - Bei echter Unsicherheit: kurz und präzise nachfragen statt generisch zu antworten.
        """,
    ]

    /// Antwortregeln – einmal, knapp, ohne Befehlston.
    nonisolated static let answerRules = """
    So antwortest du:
    - Ein bis zwei kurze, vollständige Sätze, so wie man spricht. Keine Listen, kein Markdown, keine Emojis.
    - Beantworte zuerst, was gefragt wurde. Stell höchstens eine Rückfrage, und nur wenn sie wirklich passt.
    - Wiederhole weder die Frage noch Sätze aus deinen letzten Antworten.
    - Wenn du etwas nicht sicher weißt, sag das ehrlich, statt zu raten.
    """

    nonisolated static let openingBrevityDirective = """
    Beginne jetzt das Gespräch: eine kurze Begrüßung und eine offene Frage, zusammen höchstens 20 Wörter.
    """

    nonisolated static func load() -> String {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultPrompt : stored
    }

    nonisolated static func save(_ prompt: String) {
        UserDefaults.standard.set(prompt, forKey: userDefaultsKey)
    }

    @discardableResult
    nonisolated static func restoreDefaultPrompt() -> String {
        save(defaultPrompt)
        return defaultPrompt
    }

    nonisolated static func usesDefaultPrompt(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == defaultPrompt || legacyDefaultPrompts.contains(trimmed)
    }

    nonisolated static func effectiveCharacterPrompt(_ customCharacter: String) -> String {
        if usesDefaultPrompt(customCharacter) { return defaultPrompt }
        return customCharacter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Baut den System-Prompt: Charakter → Ton → Regeln → Name/Rolle → Profil → Datum.
    ///
    /// Bewusst kurz (~200–300 Tokens statt ~1.100): kleine Modelle folgen wenigen klaren Sätzen besser,
    /// als sie lange „verbindlich“-Blöcke befolgen – sie kopierten diese teils in ihre Antworten.
    /// Stabile Teile stehen vorn, Datum und Uhrzeit am Ende (Prompt-Cache bleibt bis dahin gültig).
    nonisolated static func resolvedSystemPrompt(
        customCharacter: String,
        style: AIInteractionStyle,
        userBrain: UserBrainPromptContext,
        at date: Date = Date()
    ) -> String {
        var parts: [String] = [
            effectiveCharacterPrompt(customCharacter),
            style.styleDirective,
            answerRules,
        ]

        let personal = [
            userBrain.assistantNameDirective,
            userBrain.missionDirective,
            userBrain.missionConversationDirective,
            userBrain.profilePromptBlock,
            userBrain.discoveryDirective,
        ].compactMap { $0 }
        if !personal.isEmpty {
            parts.append(personal.joined(separator: "\n"))
        }

        parts.append(DeviceContextProvider.contextBlock(for: date))
        return parts.joined(separator: "\n\n")
    }

    /// Nutzer-Nachricht für das LLM – unverändert. Eine Rahmung wie „Der Gesprächspartner X sagt:“
    /// hat das Modell wörtlich in seine Antworten übernommen; der Name steht im System-Prompt.
    nonisolated static func germanFramedUserMessage(
        _ text: String,
        userFirstName: String? = nil
    ) -> String {
        _ = userFirstName
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Interner Prompt für Auftrags-Eröffnung.
    nonisolated static func missionOpeningUserMessage(mission: String) -> String {
        let trimmed = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Sprich den Gesprächspartner jetzt an – nur diesen einen Einstieg, sehr kurz.
        Genau ZWEI Sätze: (1) kurze Begrüßung, (2) EINE offene Frage passend zu deinem Auftrag.
        Maximal 20 Wörter insgesamt. Keine Erklärungen.
        Dein Auftrag/Rolle: \(trimmed)
        """
    }

    /// Interner Prompt für lockere Eröffnung ohne Auftrag.
    nonisolated static func casualOpeningUserMessage(userBrain: UserBrainProfile) -> String {
        var hints: [String] = []
        let city = userBrain.value(for: .city).trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty { hints.append("Wohnort bekannt: \(city)") }
        let name = userBrain.value(for: .firstName).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { hints.append("Vorname bekannt: \(name)") }

        let context = hints.isEmpty ? "" : "\nBekannt: \(hints.joined(separator: ", "))."
        return """
        Sprich den Gesprächspartner freundlich an – nur diesen einen Einstieg, sehr kurz.
        Genau ZWEI Sätze: (1) Begrüßung, (2) EINE offene, einladende Frage.\(context)
        """
    }
}

// MARK: - Protokoll

protocol LanguageEngine: Sendable {
    func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String>

    func completePartialReply(
        partial: String,
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String

    func generateEngagedRetry(
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String
}

extension LanguageEngine {
    nonisolated func reply(
        to text: String,
        context: [ChatTurn]
    ) async throws -> AsyncStream<String> {
        try await reply(to: text, context: context, options: LanguageReplyOptions())
    }

    /// Standard: keine Fortsetzung – nur MLX-Engine liefert echte Ergänzungen.
    nonisolated func completePartialReply(
        partial: String,
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        _ = userMessage
        _ = context
        _ = options
        return partial
    }

    /// Standard: keine Nachgenerierung (nur MLX-Engine überschreibt).
    nonisolated func generateEngagedRetry(
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        _ = userMessage
        _ = context
        _ = options
        return ""
    }
}
