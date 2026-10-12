//
//  WebAugmentedLanguageEngine.swift
//  Voicefinder
//
//  Reichert Nutzerfragen optional mit Web-Kontext an – selten und fehlertolerant.
//

import Foundation

/// Reichert Nutzerfragen nur bei Bedarf mit Web-Kontext an, bevor das lokale LLM antwortet.
struct WebAugmentedLanguageEngine: LanguageEngine, Sendable {
    private let inner: any LanguageEngine
    private let webSearch: any WebSearchProviding

    nonisolated init(
        inner: any LanguageEngine,
        webSearch: any WebSearchProviding
    ) {
        self.inner = inner
        self.webSearch = webSearch
    }

    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        var userMessage = text

        if options.internetEnabled,
           !AppMemoryCoordinator.isUnderMemoryPressure,
           WebSearchHeuristic.shouldFetchWebContext(for: text) {
            guard !Task.isCancelled else {
                return try await inner.reply(to: userMessage, context: context, options: options)
            }

            var replyContext = context
            if let augmented = await fetchAugmentedMessageIfUseful(original: text) {
                userMessage = augmented
                // Letzter Nutzer-Turn trägt sonst die Originalfrage, und `userMessage` käme als zweite
                // Nutzernachricht hinten dran – die Frage stünde doppelt im Prompt.
                if let last = replyContext.last, last.role == .user, last.text == text {
                    replyContext[replyContext.count - 1] = ChatTurn(role: .user, text: augmented)
                }
            }
            // Leere oder nutzlose Web-Treffer: still ignorieren – lokales LLM antwortet allein.
            return try await inner.reply(to: userMessage, context: replyContext, options: options)
        }

        return try await inner.reply(to: userMessage, context: context, options: options)
    }

    nonisolated func completePartialReply(
        partial: String,
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        try await inner.completePartialReply(
            partial: partial,
            userMessage: userMessage,
            context: context,
            options: options
        )
    }

    nonisolated func generateEngagedRetry(
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        try await inner.generateEngagedRetry(
            userMessage: userMessage,
            context: context,
            options: options
        )
    }

    /// Lädt Web-Kontext; nil wenn leer, fehlgeschlagen oder irrelevant.
    nonisolated private func fetchAugmentedMessageIfUseful(original: String) async -> String? {
        do {
            let webContext = try await fetchContextWithTimeout(for: original)
            let compact = String(webContext.prefix(Self.contextCharacterBudget))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard WebSearchHeuristic.isUsefulWebContext(compact) else {
                NSLog("[Voicefinder] Web-Recherche: Treffer leer oder irrelevant – ignoriert.")
                return nil
            }

            NSLog("[Voicefinder] Web-Kontext für LLM geladen (%d Zeichen)", compact.count)
            #if DEBUG
            NSLog("[Voicefinder] Web-Kontext (Debug): %@", compact)
            #endif
            return Self.augmentUserMessage(original: original, webContext: compact)
        } catch {
            NSLog("[Voicefinder] Web-Recherche ohne nutzbaren Treffer – lokales LLM übernimmt.")
            return nil
        }
    }

    /// Zeichenbudget für den Web-Kontext im Prompt.
    nonisolated private static let contextCharacterBudget = 500

    /// Harte Obergrenze für die Recherche – im Sprachdialog zählt jede Sekunde Wartezeit.
    nonisolated private static let searchTimeout: Duration = .milliseconds(2500)

    nonisolated private func fetchContextWithTimeout(for query: String) async throws -> String {
        let webSearch = webSearch
        let timeout = Self.searchTimeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await webSearch.fetchContext(for: query) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WebSearchError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw WebSearchError.emptyResults }
            return first
        }
    }

    /// Frage mit Nachschlage-Text für das kleine LLM – als normaler Satz, nicht in Klammerblöcken,
    /// die das Modell zitieren würde.
    nonisolated private static func augmentUserMessage(original: String, webContext: String) -> String {
        """
        \(original)

        (Zum Nachschlagen: \(webContext) – Antworte knapp und konkret damit, wenn es die Frage beantwortet, \
        und nenne Zahlen, Jahre und Namen genau so, wie sie dort stehen.)
        """
    }
}
