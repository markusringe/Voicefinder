//
//  LocalRuleLanguageEngineTests.swift
//  VoicefinderTests
//
//  Created by Markus Ringe on 03.08.26.
//

import Testing
@testable import Voicefinder

struct RuleBasedLanguageEngineTests {

    @Test
    func hallo_liefertBegruessungUndIntent() async throws {
        let engine = RuleBasedLanguageEngine()
        let analysis = try await engine.analyze(text: "Hallo", context: [])

        #expect(analysis.intent == .greeting)
        #expect(analysis.response.contains("Hallo"))
    }

    @Test
    func uhrzeit_liefertDatumUndIntent() async throws {
        let engine = RuleBasedLanguageEngine()
        let analysis = try await engine.analyze(text: "Wie spät ist es?", context: [])

        #expect(analysis.intent == .timeQuery)
        #expect(analysis.response.contains("Es ist"))
    }

    @Test
    func reply_streamtAntwort() async throws {
        let engine = RuleBasedLanguageEngine()
        let stream = try await engine.reply(to: "Hallo", context: [])

        var response = ""
        for await chunk in stream {
            response += chunk
        }

        #expect(response.contains("Hallo"))
    }
}
