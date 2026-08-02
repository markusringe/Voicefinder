//
//  SpeechToTextEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

protocol SpeechToTextEngine: Sendable {
    var partialTextStream: AsyncStream<String> { get }
    var finalTextStream: AsyncStream<String> { get }

    func requestAuthorization() async -> Bool
    func startStreaming() async throws
    func stopStreaming() async
}
