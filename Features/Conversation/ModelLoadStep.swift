//
//  ModelLoadStep.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Identifikator für einen Ladeschritt beim App-Start.
enum ModelLoadStepID: String, Sendable, CaseIterable {
    case liveSpeech
    case whisperKit
    case piperTTS
    case languageModel
}

/// Zustand eines einzelnen Modell-Ladeschritts.
enum ModelLoadStepStatus: Equatable, Sendable {
    case pending
    case loading
    case completed
    case failed(String)
    case skipped

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .skipped:
            true
        case .pending, .loading:
            false
        }
    }
}

/// Ein Modell-Eintrag auf dem Startbildschirm inkl. Fortschritt.
struct ModelLoadStep: Identifiable, Sendable {
    let id: ModelLoadStepID
    let title: String
    let subtitle: String
    let systemImage: String
    var status: ModelLoadStepStatus
    /// Fortschritt 0…1 für den Balken unter dem Eintrag.
    var progress: Double

    init(
        id: ModelLoadStepID,
        title: String,
        subtitle: String,
        systemImage: String,
        status: ModelLoadStepStatus = .pending,
        progress: Double = 0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.status = status
        self.progress = progress
    }
}

/// Ergebnis des Start-Ladevorgangs für das Conversation-ViewModel.
struct PreloadedModelFlags: Sendable {
    var whisperReady: Bool
    var piperReady: Bool
    var llmReady: Bool
    var llmDisplayName: String
}
