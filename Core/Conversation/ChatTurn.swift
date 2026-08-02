//
//  ChatTurn.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

enum SpeakerRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct ChatTurn: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: SpeakerRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: SpeakerRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}
