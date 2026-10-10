//
//  TextToSpeechEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

protocol TextToSpeechEngine: Sendable {
    func speak(text: String) async throws
    func speak(stream: AsyncStream<String>) async throws
    func stop() async
}

/// TTS-Engine, die Text vorab synthetisieren kann, während noch etwas anderes abgespielt wird.
protocol PrefetchingTextToSpeechEngine: TextToSpeechEngine {
    /// Startet die Synthese im Hintergrund; ein folgendes `speak(text:)` mit gleichem Text spielt sofort ab.
    func prefetch(text: String) async
}
