//
//  AudioLevelNormalizer.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import AVFoundation
import Foundation

/// Hilfsfunktionen zur Normalisierung von Mikrofonpegeln für die UI (0…1).
enum AudioLevelNormalizer {
    /// Leerer Pegel-Stream für Engines ohne Live-Mikrofon-Tap.
    static func emptyStream() -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }

    /// RMS aus einem Float32-Audiopuffer → 0…1.
    nonisolated static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0 ..< frameCount {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = sqrtf(sum / Float(frameCount))
        // Empirischer Verstärkungsfaktor für sichtbare UI-Reaktion bei normaler Sprechlautstärke.
        return min(1, rms * 12)
    }

    /// dBFS (-60…0) → 0…1 (für `AVAudioRecorder`-Metering).
    nonisolated static func normalizedDecibels(_ decibels: Float) -> Float {
        let clamped = max(-60, min(0, decibels))
        return (clamped + 60) / 60
    }
}
