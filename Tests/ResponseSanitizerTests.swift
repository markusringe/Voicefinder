//
//  ResponseSanitizerTests.swift
//  VoicefinderTests
//

import Testing
@testable import Voicefinder

struct ResponseSanitizerTests {

    @Test
    func kurzeWiederholteRueckfrage_wirdEntfernt() {
        // Echte Sequenz aus dem Sprachtest vom 11.10.: dieselbe Rückfrage hinter jeder Antwort.
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: "Ah, wir sind im Herbst. Was bringst du heute mit?",
            recentAssistantTexts: ["Ah, heute ist Samstag. Was bringst du heute mit?"]
        )
        #expect(cleaned == "Ah, wir sind im Herbst.")
    }

    @Test
    func rueckfrageAusAeltererAntwort_wirdAuchErkannt() {
        // Die letzte Antwort hat ihre Rückfrage schon verloren – die vorletzte hatte sie noch.
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: "Die Hauptstadt von Australien ist Canberra. Was bringst du heute mit?",
            recentAssistantTexts: [
                "Ah, heute ist Samstag. Was bringst du heute mit?",
                "Ah, wir sind im Herbst.",
            ]
        )
        #expect(cleaned == "Die Hauptstadt von Australien ist Canberra.")
    }

    @Test
    func andereRueckfrage_bleibtStehen() {
        let candidate = "Wir sind im Herbst. Magst du den Herbst?"
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: candidate,
            recentAssistantTexts: ["Ah, heute ist Samstag. Was bringst du heute mit?"]
        )
        #expect(cleaned == candidate)
    }

    @Test
    func antwortNurAusRueckfrage_bleibtStehen() {
        // Ohne Rückfrage bliebe nichts übrig – dann lieber die Wiederholung als Stille.
        let candidate = "Was bringst du heute mit?"
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: candidate,
            recentAssistantTexts: ["Ah, heute ist Samstag. Was bringst du heute mit?"]
        )
        #expect(cleaned == candidate)
    }
}
