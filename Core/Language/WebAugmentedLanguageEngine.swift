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

            if let augmented = await fetchAugmentedMessageIfUseful(original: text) {
                userMessage = augmented
            }
            // Leere oder nutzlose Web-Treffer: still ignorieren – lokales LLM antwortet allein.
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
            let webContext = try await webSearch.fetchContext(for: original)
            let compact = String(webContext.prefix(120))
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

    /// Formuliert die Nutzerfrage mit Recherche-Ergebnissen für das kleine LLM.
    nonisolated private static func augmentUserMessage(original: String, webContext: String) -> String {
        """
        [Internet-Recherche – nutze diese Fakten nur wenn sie zur Frage passen]
        \(webContext)

        [Nutzerfrage]
        \(original)

        [Aufgabe]
        Beantworte die Nutzerfrage auf Deutsch in vollständigen Sätzen für Sprachausgabe. \
        Nutze die Recherche nur bei passenden Fakten. Sonst antworte aus dem Gespräch und deinem Wissen.
        """
    }
}
