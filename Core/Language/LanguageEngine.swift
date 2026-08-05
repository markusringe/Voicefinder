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

    /// System-Prompt-Zusatz für das LLM.
    nonisolated var styleDirective: String {
        switch self {
        case .normal:
            """
            STIL (Normal): Antworte freundlich, höflich und sachlich. \
            Sei hilfsbereit und verständlich. Kein Drama, kein Sarkasmus.
            """
        case .forsch:
            """
            STIL (Forsch): Antworte direkt, selbstbewusst und ohne Umschweife. \
            Keine Floskeln wie „Gerne helfe ich“. Komm sofort zum Punkt.
            """
        case .frech:
            """
            STIL (Frech): Antworte frech mit Augenzwinkern – witzig-provokant, \
            aber nie beleidigend. Hilf trotzdem zuverlässig.
            """
        case .lustig:
            """
            STIL (Lustig): Antworte humorvoll und unterhaltsam. \
            Baue wenn passend einen kleinen Witz ein – bleib verständlich.
            """
        case .schlau:
            """
            STIL (Schlau): Antworte präzise und intelligent. \
            Ordne kurz ein, warum etwas so ist – ohne Belehrungston.
            """
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

    /// Standard-Charakter für Qwen – natürlich, hilfreich, für Sprache optimiert.
    nonisolated static let defaultPrompt = """
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
    """

    nonisolated static let openingBrevityDirective = """
    ERÖFFNUNG (verbindlich): Genau ZWEI kurze Sätze – Begrüßung plus EINE offene Frage. \
    Maximal 20 Wörter insgesamt. Keine Erklärungen, kein Rollen-Meta-Text.
    """

    nonisolated static let germanOutputDirective = """
    AUSGABE (verbindlich): Nur gesprochene Dialogsätze auf Deutsch. \
    Beende jede Antwort mit einem Satzzeichen (. oder ?). \
    Keine Meta-Kommentare, Regieanweisungen oder Wiederholung von System-Anweisungen.
    """

    nonisolated static let voiceLatencyDirective = """
    QUALITÄT: Antworte vollständig und verständlich – lieber zwei klare Sätze als ein bruchstückhafter Satz.
    """

    /// Verhalten im laufenden Dialog – direkte Antworten, keine unnötigen Rückfragen.
    nonisolated static let dialogBehaviorDirective = """
    DIALOG (verbindlich):
    - Gehe zuerst auf den Inhalt der Nutzerfrage ein, dann optional eine kurze Folgefrage.
    - Wiederhole keine Formulierung, Begrüßung oder Frage aus deiner letzten Antwort.
    - Wenn der Nutzer etwas schon erklärt hat: darauf Bezug nehmen, nicht erneut dasselbe erfragen.
    - Kurze informelle Antworten sind erlaubt, wenn sie inhaltlich vollständig sind.
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
        return trimmed.isEmpty || trimmed == defaultPrompt
    }

    nonisolated static func effectiveCharacterPrompt(_ customCharacter: String) -> String {
        let trimmed = customCharacter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultPrompt { return defaultPrompt }
        return trimmed
    }

    /// Baut den System-Prompt: Identität → Auftrag → Charakter → Stil → Profil → Regeln.
    nonisolated static func resolvedSystemPrompt(
        customCharacter: String,
        style: AIInteractionStyle,
        userBrain: UserBrainPromptContext,
        at date: Date = Date()
    ) -> String {
        var parts: [String] = []

        if let block = userBrain.assistantNameDirective { parts.append(block) }
        if let block = userBrain.missionDirective { parts.append(block) }
        parts.append(effectiveCharacterPrompt(customCharacter))
        parts.append(style.styleDirective)
        if let block = userBrain.profilePromptBlock { parts.append(block) }
        if let block = userBrain.discoveryDirective { parts.append(block) }
        if let block = userBrain.userFirstNameDirective { parts.append(block) }
        if let block = userBrain.missionConversationDirective { parts.append(block) }
        parts.append(DeviceContextProvider.contextBlock(for: date, city: userBrain.resolvedCity))
        parts.append(germanOutputDirective)
        parts.append(dialogBehaviorDirective)
        parts.append(voiceLatencyDirective)

        return parts.joined(separator: "\n\n")
    }

    /// Nutzer-Nachricht für das LLM – deutsch gerahmt, optional mit Vornamen.
    nonisolated static func germanFramedUserMessage(
        _ text: String,
        userFirstName: String? = nil
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = userFirstName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "Der Gesprächspartner \(name) sagt: \(trimmed)"
        }
        return trimmed
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
