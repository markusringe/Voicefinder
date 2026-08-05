//
//  EchoLanguageEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Einfache Platzhalter-Implementierung der LanguageEngine für Entwicklung und Tests.
///
/// Gibt den Nutzertext als Echo zurück, bis eine echte lokale Reply-Engine angebunden ist.
struct EchoLanguageEngine: LanguageEngine, Sendable {
    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        _ = options
        let response = "Du hast gesagt: \(text)"

        return AsyncStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
}
