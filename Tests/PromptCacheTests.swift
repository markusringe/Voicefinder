//
//  PromptCacheTests.swift
//  VoicefinderTests
//
//  Läuft nur auf echter Hardware mit eingebettetem Modell (MLX braucht Metal).
//

import Foundation
import MLXLMCommon
import Testing
@testable import Voicefinder

@MainActor
struct PromptCacheTests {
    private static let systemPrompt = """
    Du bist ein freundlicher deutscher Sprachassistent. Antworte kurz in ein bis zwei Sätzen.
    Heute ist Samstag, der 10. Oktober 2026. Es ist Herbst.
    """
    private static let greedy = GenerateParameters(maxTokens: 40, temperature: 0)

    private func container() async throws -> ModelContainer {
        try await MLXChatService.shared.activateEmbeddedModel(at: LLMModelProvider.requiredEmbeddedModelURL())
        return try #require(await MLXChatService.shared.modelContainerForTesting)
    }

    private func generate(
        _ container: ModelContainer,
        store: PromptCacheStore,
        messages: [Chat.Message]
    ) async throws -> String {
        let box = TextBox()
        try await MLXChatService.generateWithPromptCache(
            modelContainer: container,
            store: store,
            messages: messages,
            generateParameters: Self.greedy,
            retainCache: true
        ) { box.append($0) }
        return box.text
    }

    private func reference(_ container: ModelContainer, history: [Chat.Message], prompt: String) async throws -> String {
        let session = ChatSession(
            container,
            instructions: Self.systemPrompt,
            history: history,
            generateParameters: Self.greedy,
            additionalContext: ["enable_thinking": false]
        )
        var text = ""
        for try await chunk in session.streamResponse(to: prompt) {
            text += chunk
        }
        return text
    }

    @Test
    func ohneCache_entsprichtChatSession() async throws {
        let container = try await container()
        let expected = try await reference(container, history: [], prompt: "Welche Jahreszeit haben wir?")
        let actual = try await generate(
            container,
            store: PromptCacheStore(),
            messages: [.system(Self.systemPrompt), .user("Welche Jahreszeit haben wir?")]
        )
        print("[PromptCacheTests] Referenz: \(expected)\n[PromptCacheTests] Ohne Cache: \(actual)")
        #expect(actual == expected)
    }

    @Test
    func mitCache_entsprichtChatSession() async throws {
        let container = try await container()
        let expected = try await reference(container, history: [], prompt: "Welche Jahreszeit haben wir?")

        let store = PromptCacheStore()
        _ = try await generate(container, store: store, messages: [.system(Self.systemPrompt), .user("Hallo")])
        let primedTokens = store.tokens.count
        let actual = try await generate(
            container,
            store: store,
            messages: [.system(Self.systemPrompt), .user("Welche Jahreszeit haben wir?")]
        )
        print("[PromptCacheTests] Referenz: \(expected)\n[PromptCacheTests] Mit Cache (\(primedTokens) Tokens vorab): \(actual)")
        #expect(primedTokens > 0)
        #expect(actual == expected)
    }

    private static func realSystemPrompt(minute: Int) -> String {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 10
        components.hour = 20; components.minute = minute
        let date = Calendar(identifier: .gregorian).date(from: components)!
        return CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: "",
            style: .normal,
            userBrain: UserBrainProfile().promptContext(),
            at: date
        )
    }

    private func referenceLong(
        _ container: ModelContainer,
        system: String,
        history: [Chat.Message],
        prompt: String
    ) async throws -> String {
        let session = ChatSession(
            container,
            instructions: system,
            history: history,
            generateParameters: Self.greedy,
            additionalContext: ["enable_thinking": false]
        )
        var text = ""
        for try await chunk in session.streamResponse(to: prompt) {
            text += chunk
        }
        return text
    }

    @Test
    func langerPrompt_folgerundeMitVerlauf_entsprichtChatSession() async throws {
        let container = try await container()
        let system = Self.realSystemPrompt(minute: 20)
        let history: [Chat.Message] = [
            .user("Hallo"),
            .assistant("Hallo! Schön, dass du da bist. Wie geht es dir heute?"),
        ]
        let expected = try await referenceLong(container, system: system, history: history, prompt: "Welche Jahreszeit haben wir denn?")

        let store = PromptCacheStore()
        _ = try await generate(container, store: store, messages: [.system(system), .user("Hallo")])
        let actual = try await generate(
            container,
            store: store,
            messages: [.system(system)] + history + [.user("Welche Jahreszeit haben wir denn?")]
        )
        print("[PromptCacheTests] Lang Referenz: \(expected)\n[PromptCacheTests] Lang mit Cache: \(actual)")
        #expect(actual == expected)
    }

    @Test
    func langerPrompt_geaenderteUhrzeit_entsprichtChatSession() async throws {
        let container = try await container()
        let store = PromptCacheStore()
        _ = try await generate(
            container,
            store: store,
            messages: [.system(Self.realSystemPrompt(minute: 20)), .user("Hallo")]
        )

        let system = Self.realSystemPrompt(minute: 21)
        let expected = try await referenceLong(container, system: system, history: [], prompt: "Wie spät ist es?")
        let actual = try await generate(
            container,
            store: store,
            messages: [.system(system), .user("Wie spät ist es?")]
        )
        print("[PromptCacheTests] Uhrzeit Referenz: \(expected)\n[PromptCacheTests] Uhrzeit mit Cache: \(actual)")
        #expect(actual == expected)
    }
}

private final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    var text: String { lock.withLock { buffer } }
    func append(_ chunk: String) { lock.withLock { buffer += chunk } }
}
