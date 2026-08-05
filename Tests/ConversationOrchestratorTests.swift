//
//  ConversationOrchestratorTests.swift
//  VoicefinderTests
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import Testing
@testable import Voicefinder

// MARK: - Test-Doubles

/// STT-Mock ohne echtes Mikrofon; liefert steuerbare Transkript-Streams.
actor MockSpeechToTextEngine: SpeechToTextEngine {
    private(set) var partialTextStream: AsyncStream<String>
    private(set) var finalTextStream: AsyncStream<String>
    private(set) var audioLevelStream: AsyncStream<Float>

    private var partialContinuation: AsyncStream<String>.Continuation
    private var finalContinuation: AsyncStream<String>.Continuation
    private var levelContinuation: AsyncStream<Float>.Continuation

    private(set) var didRequestAuthorization = false
    private(set) var didStartStreaming = false

    init() {
        let partialPair = AsyncStream<String>.makeStream()
        partialTextStream = partialPair.stream
        partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        finalTextStream = finalPair.stream
        finalContinuation = finalPair.continuation

        let levelPair = AsyncStream<Float>.makeStream()
        audioLevelStream = levelPair.stream
        levelContinuation = levelPair.continuation
    }

    func requestAuthorization() async -> Bool {
        didRequestAuthorization = true
        return true
    }

    func startStreaming() async throws {
        didStartStreaming = true
        resetStreams()
    }

    func stopStreaming() async {
        partialContinuation.finish()
        finalContinuation.finish()
        levelContinuation.finish()
    }

    func emitPartial(_ text: String) {
        partialContinuation.yield(text)
    }

    func emitLevel(_ level: Float) {
        levelContinuation.yield(level)
    }

    func emitFinal(_ text: String) {
        finalContinuation.yield(text)
    }

    private func resetStreams() {
        let partialPair = AsyncStream<String>.makeStream()
        partialTextStream = partialPair.stream
        partialContinuation = partialPair.continuation

        let finalPair = AsyncStream<String>.makeStream()
        finalTextStream = finalPair.stream
        finalContinuation = finalPair.continuation

        let levelPair = AsyncStream<Float>.makeStream()
        audioLevelStream = levelPair.stream
        levelContinuation = levelPair.continuation
    }
}

/// LLM-Mock mit fester Antwort.
struct MockLanguageEngine: LanguageEngine, Sendable {
    let response: String

    nonisolated func reply(
        to text: String,
        context: [ChatTurn],
        options: LanguageReplyOptions
    ) async throws -> AsyncStream<String> {
        _ = text
        _ = context
        _ = options
        return AsyncStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
}

/// TTS-Mock protokolliert gesprochene Texte und simuliert Ausgabe-Laufzeit.
actor MockTextToSpeechEngine: TextToSpeechEngine {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0
    private let speakDelayNanoseconds: UInt64
    private var speakTask: Task<Void, Error>?

    init(speakDelayNanoseconds: UInt64 = 200_000_000) {
        self.speakDelayNanoseconds = speakDelayNanoseconds
    }

    func speak(text: String) async throws {
        speakTask?.cancel()
        spokenTexts.append(text)
        let delay = speakDelayNanoseconds
        let task = Task<Void, Error> {
            try await Task.sleep(nanoseconds: delay)
        }
        speakTask = task
        defer { speakTask = nil }
        try await task.value
    }

    func speak(stream: AsyncStream<String>) async throws {
        var combined = ""
        for await chunk in stream {
            combined += chunk
        }
        try await speak(text: combined)
    }

    func stop() async {
        stopCount += 1
        speakTask?.cancel()
        speakTask = nil
    }
}

// MARK: - Tests

struct ConversationOrchestratorTests {

    @Test
    func submitUserText_durchlaeuftPipeline() async throws {
        let tts = MockTextToSpeechEngine()
        let orchestrator = ConversationOrchestrator(
            dependencies: AppDependencies(
                speechToTextEngine: MockSpeechToTextEngine(),
                languageEngine: MockLanguageEngine(response: "Testantwort"),
                textToSpeechEngine: tts
            )
        )

        await orchestrator.submitUserText("Hallo")
        try await Task.sleep(nanoseconds: 400_000_000)

        let state = await orchestrator.state
        let turns = await orchestrator.turns
        let spoken = await tts.spokenTexts

        #expect(state == .idle)
        #expect(turns.count == 2)
        #expect(turns.first?.role == .user)
        #expect(turns.first?.text == "Hallo")
        #expect(turns.last?.role == .assistant)
        #expect(turns.last?.text == "Testantwort")
        #expect(spoken == ["Testantwort"])
    }

    @Test
    func interruptSpeaking_stopptTTS() async throws {
        let tts = MockTextToSpeechEngine(speakDelayNanoseconds: 5_000_000_000)
        let orchestrator = ConversationOrchestrator(
            dependencies: AppDependencies(
                speechToTextEngine: MockSpeechToTextEngine(),
                languageEngine: MockLanguageEngine(response: "Lange Antwort"),
                textToSpeechEngine: tts
            )
        )

        await orchestrator.submitUserText("Start")
        try await Task.sleep(nanoseconds: 300_000_000)

        await orchestrator.interruptSpeaking()
        try await Task.sleep(nanoseconds: 100_000_000)

        let stopCount = await tts.stopCount
        #expect(stopCount >= 1)
    }

    @Test
    func partialTranscript_waehrendSprechen_unterbrichtTTS_nicht() async throws {
        let speech = MockSpeechToTextEngine()
        let tts = MockTextToSpeechEngine(speakDelayNanoseconds: 3_000_000_000)
        let orchestrator = ConversationOrchestrator(
            dependencies: AppDependencies(
                speechToTextEngine: speech,
                languageEngine: MockLanguageEngine(response: "Antwort"),
                textToSpeechEngine: tts
            )
        )

        try await orchestrator.startListening()

        Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await speech.emitFinal("Hallo")
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        // Während TTS ist STT pausiert – Partials sollen TTS nicht abbrechen (kein Echo-Barge-in).
        await speech.emitPartial("Unterbrechung")
        try await Task.sleep(nanoseconds: 200_000_000)

        let stopCount = await tts.stopCount
        #expect(stopCount == 0)

        await orchestrator.stopListening()
    }

    @Test
    func kurzesPartial_unterbrichtNichtTTS() async throws {
        let speech = MockSpeechToTextEngine()
        let tts = MockTextToSpeechEngine(speakDelayNanoseconds: 3_000_000_000)
        let orchestrator = ConversationOrchestrator(
            dependencies: AppDependencies(
                speechToTextEngine: speech,
                languageEngine: MockLanguageEngine(response: "Antwort"),
                textToSpeechEngine: tts
            )
        )

        try await orchestrator.startListening()

        Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await speech.emitFinal("Hallo")
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        await speech.emitPartial("Hi")
        try await Task.sleep(nanoseconds: 200_000_000)

        let stopCount = await tts.stopCount
        #expect(stopCount == 0)

        await orchestrator.stopListening()
    }
}
