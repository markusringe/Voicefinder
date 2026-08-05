//
//  ResilientLanguageEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Umschließt eine Language Engine mit Regel-Fallback bei leerer Antwort oder Fehler.
struct ResilientLanguageEngine: LanguageEngine, Sendable {
    private let primaryEngine: any LanguageEngine
    private let fallbackEngine: RuleBasedLanguageEngine

    nonisolated init(
        primaryEngine: any LanguageEngine,
        fallbackEngine: RuleBasedLanguageEngine = RuleBasedLanguageEngine()
    ) {
        self.primaryEngine = primaryEngine
        self.fallbackEngine = fallbackEngine
    }

    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                defer { continuation.finish() }

                do {
                    let primaryStream = try await primaryEngine.reply(
                        to: text,
                        context: context,
                        options: options
                    )

                    var combined = ""
                    for await chunk in primaryStream {
                        if Task.isCancelled { break }
                        combined += chunk
                        continuation.yield(chunk)
                    }

                    if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NSLog("[Voicefinder] Leere Primär-Antwort – Regel-Fallback.")
                        await self.yieldFallback(
                            to: text,
                            context: context,
                            options: options,
                            into: continuation
                        )
                    } else {
                        NSLog(
                            "[Voicefinder] Language-Stream fertig (%d Zeichen).",
                            combined.trimmingCharacters(in: .whitespacesAndNewlines).count
                        )
                    }
                } catch {
                    NSLog("[Voicefinder] Primär-Engine-Fehler – Regel-Fallback: \(error.localizedDescription)")
                    await self.yieldFallback(
                        to: text,
                        context: context,
                        options: options,
                        into: continuation
                    )
                }
            }
        }
    }

    nonisolated func completePartialReply(
        partial: String,
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        try await primaryEngine.completePartialReply(
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
        try await primaryEngine.generateEngagedRetry(
            userMessage: userMessage,
            context: context,
            options: options
        )
    }

    /// Streamt die Regel-Engine-Antwort in denselben Ausgabe-Stream.
    private func yieldFallback(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions,
        into continuation: AsyncStream<String>.Continuation
    ) async {
        guard let stream = try? await fallbackEngine.reply(to: text, context: context, options: options) else {
            return
        }
        for await chunk in stream {
            guard !Task.isCancelled else { return }
            continuation.yield(chunk)
        }
    }
}
