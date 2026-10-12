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

    // MARK: - Wiederholte Aussagesätze am Ende

    private static let echoedTail = "Aber hey, du sprichst immer noch so laut wie ein Toter im Park."

    @Test
    func wiederholterAussagesatzAmEnde_wirdEntfernt() {
        // Echte Sequenz vom 12.10.: Ab Runde 2 hängt das Modell denselben Satz an jede Antwort.
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: "Ah, heute ist Montag. \(Self.echoedTail)",
            recentAssistantTexts: [
                "Ah, dann ist es also so. \(Self.echoedTail) Was willst du heute?",
            ]
        )
        #expect(cleaned == "Ah, heute ist Montag.")
    }

    @Test
    func wiederholterAussagesatzMitRueckfrage_beideWerdenEntfernt() {
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: "Ah, es ist der Herbst. \(Self.echoedTail) Was willst du heute?",
            recentAssistantTexts: [
                "Ah, dann ist es also so. \(Self.echoedTail) Was willst du heute?",
            ]
        )
        #expect(cleaned == "Ah, es ist der Herbst.")
    }

    @Test
    func neuerAussagesatz_bleibtStehen() {
        let candidate = "Ah, es ist der Herbst. Der Herbst ist meine liebste Jahreszeit."
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: candidate,
            recentAssistantTexts: ["Ah, dann ist es also so. \(Self.echoedTail) Was willst du heute?"]
        )
        #expect(cleaned == candidate)
    }

    @Test
    func kurzerHoeflichkeitssatz_wirdNichtAlsWiederholungGewertet() {
        let candidate = "Heute ist Montag. Gern geschehen."
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: candidate,
            recentAssistantTexts: ["Nichts zu danken. Gern geschehen."]
        )
        #expect(cleaned == candidate)
    }

    @Test
    func antwortNurAusWiederholtemSatz_bleibtStehen() {
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: Self.echoedTail,
            recentAssistantTexts: ["Ah, dann ist es also so. \(Self.echoedTail)"]
        )
        #expect(cleaned == Self.echoedTail)
    }

    @Test
    func gleicheFaktenfrageZweimal_behaeltDieAntwort() {
        let cleaned = ResponseSanitizer.removingRepeatedFollowUp(
            from: "Heute ist Montag.",
            recentAssistantTexts: ["Heute ist Montag."]
        )
        #expect(cleaned == "Heute ist Montag.")
    }
}
