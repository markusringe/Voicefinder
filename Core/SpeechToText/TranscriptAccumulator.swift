//
//  TranscriptAccumulator.swift
//  Voicefinder
//
//  Führt Apple-Speech-Teilergebnisse über Transkript-Resets hinweg zusammen.
//

import Foundation

/// Apple Speech (on-device) beginnt nach einer Sprechpause mitten im Satz ein neues Transkript –
/// `bestTranscription` enthält dann nur noch die Wörter nach der Pause. Dieser Typ erkennt solche
/// Resets und hängt den bisherigen Text davor, damit der Satzanfang nicht verloren geht.
nonisolated struct TranscriptAccumulator: Sendable {
    /// Mindestzeit ohne Textänderung, bevor ein abweichender Neuanfang als Reset gilt.
    /// Kürzere Sprünge sind normale Korrekturen des Erkenners während des Sprechens.
    static let minimumPauseForReset: TimeInterval = 0.8

    /// Bereits abgeschlossene Teile vor dem letzten Reset.
    private var committedPrefix = ""
    private var lastText = ""
    private var lastSegmentCount = 0
    private var lastChangeTime: TimeInterval = 0

    init() {}

    /// Nimmt ein Roh-Teilergebnis auf und liefert den vollständigen Äußerungstext.
    mutating func ingest(_ text: String, segmentCount: Int, at time: TimeInterval) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isReset(to: trimmed, segmentCount: segmentCount, at: time) {
            committedPrefix = combined(committedPrefix, lastText)
        }

        if trimmed != lastText {
            lastChangeTime = time
        }
        lastText = trimmed
        lastSegmentCount = segmentCount

        return combined(committedPrefix, trimmed)
    }

    /// Neue Äußerung – vorherigen Text verwerfen.
    mutating func reset() {
        committedPrefix = ""
        lastText = ""
        lastSegmentCount = 0
        lastChangeTime = 0
    }

    private func isReset(to text: String, segmentCount: Int, at time: TimeInterval) -> Bool {
        guard !lastText.isEmpty, !text.isEmpty else { return false }
        guard segmentCount < lastSegmentCount else { return false }
        guard time - lastChangeTime >= Self.minimumPauseForReset else { return false }
        return Self.firstWord(of: text) != Self.firstWord(of: lastText)
    }

    private static func firstWord(of text: String) -> String {
        let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }

    private func combined(_ prefix: String, _ text: String) -> String {
        if prefix.isEmpty { return text }
        if text.isEmpty { return prefix }
        return prefix + " " + text
    }
}
