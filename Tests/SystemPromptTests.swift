//
//  SystemPromptTests.swift
//  VoicefinderTests
//

import Foundation
import Testing
@testable import Voicefinder

struct SystemPromptTests {
    private static func date(month: Int, day: Int = 11, hour: Int = 9, minute: Int = 45) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private static func brain(mission: String = "") -> UserBrainProfile {
        var profile = UserBrainProfile()
        profile.assistantName = "Joe"
        profile.firstName = "Markus"
        profile.city = "Hamburg"
        profile.mission = mission
        return profile
    }

    @Test
    func jahreszeit_folgtDemKalender() {
        #expect(DeviceContextProvider.season(for: Self.date(month: 1)) == "Winter")
        #expect(DeviceContextProvider.season(for: Self.date(month: 4)) == "Frühling")
        #expect(DeviceContextProvider.season(for: Self.date(month: 7)) == "Sommer")
        #expect(DeviceContextProvider.season(for: Self.date(month: 10)) == "Herbst")
        #expect(DeviceContextProvider.season(for: Self.date(month: 12)) == "Winter")
    }

    @Test
    func prompt_enthaeltKontextNameUndJahreszeit() {
        let prompt = CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: "",
            style: .frech,
            userBrain: Self.brain().promptContext(),
            at: Self.date(month: 10)
        )
        #expect(prompt.contains("Joe"))
        #expect(prompt.contains("Markus"))
        #expect(prompt.contains("Hamburg"))
        #expect(prompt.contains("Herbst"))
        #expect(prompt.contains("11. Oktober 2026"))
    }

    @Test
    func prompt_istKompaktUndOhneBefehlston() {
        let prompt = CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: "",
            style: .frech,
            userBrain: Self.brain(mission: "Du willst die Leute nett unterhalten.").promptContext(),
            at: Self.date(month: 10)
        )
        print("[SystemPromptTests] \(prompt.count) Zeichen:\n\(prompt)")
        #expect(prompt.count < 1_200)
        #expect(!prompt.contains("verbindlich"))
        #expect(!prompt.contains("NIEMALS"))
        #expect(!prompt.contains("["))
    }

    @Test
    func datumUndUhrzeit_stehenAmEnde() {
        // Stabile Teile vorn – der Prompt-Cache bleibt gültig, wenn sich nur die Minute ändert.
        let early = CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: "", style: .normal, userBrain: Self.brain().promptContext(), at: Self.date(month: 10, minute: 45)
        )
        let later = CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: "", style: .normal, userBrain: Self.brain().promptContext(), at: Self.date(month: 10, minute: 46)
        )
        let common = zip(early, later).prefix { $0 == $1 }.count
        #expect(early.count - common < 40)
    }

    @Test
    func alterStandardCharakter_giltWeiterAlsStandard() {
        #expect(CharacterProfileStore.usesDefaultPrompt(CharacterProfileStore.legacyDefaultPrompts[0]))
        #expect(
            CharacterProfileStore.effectiveCharacterPrompt(CharacterProfileStore.legacyDefaultPrompts[0])
                == CharacterProfileStore.defaultPrompt
        )
    }

    @Test
    func nutzernachricht_wirdNichtGerahmt() {
        #expect(CharacterProfileStore.germanFramedUserMessage("  Wie spät ist es?  ", userFirstName: "Markus") == "Wie spät ist es?")
    }
}
