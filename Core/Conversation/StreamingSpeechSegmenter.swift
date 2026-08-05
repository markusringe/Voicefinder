//
//  StreamingSpeechSegmenter.swift
//  Voicefinder
//
//  Erkennt sprechbare Satzgrenzen im LLM-Stream für frühes TTS.
//

import Foundation

/// Hilfsfunktionen, um aus gestreamtem LLM-Text früh sprechbare Segmente zu extrahieren.
enum StreamingSpeechSegmenter: Sendable {
    /// Mindestlänge eines Satzes, bevor er vorgelesen wird.
    private nonisolated static let minimumEarlySentenceLength = 10

    /// Bereich des ersten abgeschlossenen Satzes (inkl. Satzzeichen), falls vorhanden.
    nonisolated static func firstSentenceRange(in text: String) -> Range<String.Index>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumEarlySentenceLength else { return nil }

        let terminators = [". ", "! ", "? ", ".\n", "!\n", "?\n", ".", "!", "?"]
        var earliest: Range<String.Index>?

        for term in terminators {
            guard let range = trimmed.range(of: term) else { continue }
            let end = range.upperBound
            let length = trimmed.distance(from: trimmed.startIndex, to: end)
            guard length >= minimumEarlySentenceLength else { continue }

            if let current = earliest {
                if end < current.upperBound {
                    earliest = trimmed.startIndex..<end
                }
            } else {
                earliest = trimmed.startIndex..<end
            }
        }

        return earliest
    }

    /// Text nach dem bereits gesprochenen Satzanfang – für Rest-Vorlesen.
    nonisolated static func remainder(afterSpokenEnd end: String.Index, in fullText: String) -> String {
        guard end <= fullText.endIndex else { return "" }
        return String(fullText[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
