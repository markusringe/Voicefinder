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
