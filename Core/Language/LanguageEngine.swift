//
//  LanguageEngine.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

protocol LanguageEngine: Sendable {
    func reply(
        to text: String,
        context: [ChatTurn]
    ) async throws -> AsyncStream<String>
}
