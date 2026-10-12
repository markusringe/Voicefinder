//
//  StreamingSpeechSegmenterTests.swift
//  VoicefinderTests
//

import Testing
@testable import Voicefinder

struct StreamingSpeechSegmenterTests {

    @Test
    func ersterSatz_wirdErkannt_sobaldTextFolgt() {
        let result = StreamingSpeechSegmenter.firstCompletedSentence(in: "Das ist eine gute Frage. Ich")
        #expect(result?.sentence == "Das ist eine gute Frage.")
        #expect(result?.remainder == "Ich")
    }

    @Test
    func satzzeichenAmStreamEnde_giltNochNichtAlsSatzende() {
        #expect(StreamingSpeechSegmenter.firstCompletedSentence(in: "Das ist eine gute Frage.") == nil)
    }

    @Test
    func kurzerSatz_wirdMitFolgesatzGebuendelt() {
        let result = StreamingSpeechSegmenter.firstCompletedSentence(in: "Klar! Das mache ich gern. Und")
        #expect(result?.sentence == "Klar! Das mache ich gern.")
    }

    @Test
    func datumUndAbkuerzungen_beendenKeinenSatz() {
        let date = StreamingSpeechSegmenter.firstCompletedSentence(in: "Am 3. Oktober ist Feiertag. Weil")
        #expect(date?.sentence == "Am 3. Oktober ist Feiertag.")

        let abbreviation = StreamingSpeechSegmenter.firstCompletedSentence(in: "Nimm z. B. einen Apfel mit. Dann")
        #expect(abbreviation?.sentence == "Nimm z. B. einen Apfel mit.")

        let compact = StreamingSpeechSegmenter.firstCompletedSentence(in: "Das ist bzw. war so. Oder")
        #expect(compact?.sentence == "Das ist bzw. war so.")
    }

    @Test
    func rest_nachGesprochenemSatz() {
        let remainder = StreamingSpeechSegmenter.remainder(
            of: "Das ist eine gute Frage. Ich erkläre es dir kurz.",
            afterSpoken: "Das ist eine gute Frage."
        )
        #expect(remainder == "Ich erkläre es dir kurz.")
    }

    @Test
    func rest_istLeer_wennNurDerSatzGesprochenWurde() {
        let remainder = StreamingSpeechSegmenter.remainder(
            of: "Das ist eine gute Frage.",
            afterSpoken: "Das ist eine gute Frage."
        )
        #expect(remainder == "")
    }

    @Test
    func rest_istNil_wennFinalerTextAbweicht() {
        let remainder = StreamingSpeechSegmenter.remainder(
            of: "Stimmt, entschuldige – erzähl einfach weiter.",
            afterSpoken: "Das ist eine gute Frage."
        )
        #expect(remainder == nil)
    }

    @Test
    func sanitizer_behaeltSatzzeichen_fuerSatzgrenzen() {
        let sanitized = ResponseSanitizer.sanitizeForSpeech("Das ist eine gute Frage. Ich erkläre es dir, okay?")
        #expect(sanitized == "Das ist eine gute Frage. Ich erkläre es dir, okay?")
    }

    @Test
    func stotterKorrektur_behaeltSatzzeichen() {
        let collapsed = ResponseSanitizer.collapseWordStutter(in: "Leider, leider, leider geht das nicht. Schade!")
        #expect(collapsed == "leider geht das nicht. Schade!")
    }
}
