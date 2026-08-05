//
//  LocalLLMEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Fehler für die MLX-/On-Device-LLM-Integration.
enum LocalLLMEngineError: LocalizedError, Sendable {
    case modelNotActivated
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .modelNotActivated:
            "Das eingebettete Sprachmodell ist noch nicht aktiv."
        case .notImplemented:
            "MLX-LLM-Analyse ist noch nicht implementiert."
        }
    }
}

/// Spricht ausschließlich mit dem fest eingebetteten MLX-Modell (kein Regel-Fallback).
struct LocalLLMEngine: LanguageEngine, Sendable {
    private let mlxService: MLXChatService

    nonisolated init(mlxService: MLXChatService = .shared) {
        self.mlxService = mlxService
    }

    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        guard await mlxService.isReady else {
            throw LocalLLMEngineError.modelNotActivated
        }

        return try await mlxService.streamReply(
            userMessage: text,
            context: context,
            characterPrompt: options.characterPrompt,
            interactionStyle: options.interactionStyle,
            userBrain: options.userBrain,
            isConversationOpening: options.isConversationOpening
        )
    }

    nonisolated func completePartialReply(
        partial: String,
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        await mlxService.generateContinuation(
            partialAnswer: partial,
            userMessage: userMessage,
            context: context,
            characterPrompt: options.characterPrompt,
            interactionStyle: options.interactionStyle,
            userBrain: options.userBrain
        )
    }

    nonisolated func generateEngagedRetry(
        userMessage: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> String {
        await mlxService.generateEngagedRetry(
            userMessage: userMessage,
            context: context,
            characterPrompt: options.characterPrompt,
            interactionStyle: options.interactionStyle,
            userBrain: options.userBrain
        )
    }
}
