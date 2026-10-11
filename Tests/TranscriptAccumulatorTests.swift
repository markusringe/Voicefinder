//
//  TranscriptAccumulatorTests.swift
//  VoicefinderTests
//

import Testing
@testable import Voicefinder

struct TranscriptAccumulatorTests {

    @Test
    func laufendeTeilergebnisse_werdenUnveraendertDurchgereicht() {
        var accumulator = TranscriptAccumulator()
        #expect(accumulator.ingest("Wie", segmentCount: 1, at: 0.0) == "Wie")
        #expect(accumulator.ingest("Wie viele", segmentCount: 2, at: 0.2) == "Wie viele")
        #expect(accumulator.ingest("Wie viele Beine?", segmentCount: 4, at: 0.8) == "Wie viele Beine?")
    }

    @Test
    func resetNachPause_behaeltSatzanfang() {
        // Echte Sequenz vom iPhone: nach ~1,6 s Pause beginnt Apple Speech ein neues Transkript.
        var accumulator = TranscriptAccumulator()
        _ = accumulator.ingest("Wie viele Beine?", segmentCount: 4, at: 21.117)
        _ = accumulator.ingest("Wie viele Beine?", segmentCount: 3, at: 22.519)
        #expect(accumulator.ingest("Hat", segmentCount: 1, at: 22.708) == "Wie viele Beine? Hat")
        #expect(accumulator.ingest("Hat eine Spinne?", segmentCount: 4, at: 23.719) == "Wie viele Beine? Hat eine Spinne?")
    }

    @Test
    func korrekturDesErkenners_istKeinReset() {
        // Echte Sequenz: Apple überarbeitet „Franz Beckenbauer Becken“ zu „Franz Beckenbauer“.
        var accumulator = TranscriptAccumulator()
        _ = accumulator.ingest("Franz Becken", segmentCount: 2, at: 55.440)
        _ = accumulator.ingest("Franz Beckenbauer Becken", segmentCount: 2, at: 55.743)
        #expect(accumulator.ingest("Franz Beckenbauer", segmentCount: 1, at: 55.924) == "Franz Beckenbauer")
    }

    @Test
    func schnelleKorrekturDesErstenWorts_istKeinReset() {
        var accumulator = TranscriptAccumulator()
        _ = accumulator.ingest("Was ist die", segmentCount: 3, at: 1.0)
        #expect(accumulator.ingest("Wer ist", segmentCount: 2, at: 1.2) == "Wer ist")
    }

    @Test
    func reset_leertAngesammeltenText() {
        var accumulator = TranscriptAccumulator()
        _ = accumulator.ingest("Wie viele Beine?", segmentCount: 4, at: 1.0)
        _ = accumulator.ingest("Hat", segmentCount: 1, at: 3.0)
        accumulator.reset()
        #expect(accumulator.ingest("Hallo", segmentCount: 1, at: 10.0) == "Hallo")
    }
}
