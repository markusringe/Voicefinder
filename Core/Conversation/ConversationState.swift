//
//  ConversationState.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

enum ConversationState: Equatable, Sendable {
    case idle
    case requestingPermissions
    case listening
    case transcribing(partialText: String)
    case thinking(userText: String)
    case speaking(responseText: String)
    case interrupted
    case failed(message: String)
}
