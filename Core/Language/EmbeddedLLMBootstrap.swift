//
//  EmbeddedLLMBootstrap.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Startet eingebettete On-Device-Modelle einmalig beim App-Start.
///
/// Die Gewichte liegen fest im App-Bundle (`Copy Bundle Resources`) – es gibt keinen
/// Runtime-Download und kein nachträgliches „Modell laden“ in der UI.
enum EmbeddedLLMBootstrap {
    /// Initialisiert das fest eingebettete Sprachmodell in den Arbeitsspeicher.
    /// MLX muss die Bundle-Dateien einmal mappen – das ist kein Netzwerk-Download.
    static func activateEmbeddedModel() async throws {
        guard LLMModelProvider.isSupported else { return }

        let modelURL = try LLMModelProvider.requiredEmbeddedModelURL()
        try await MLXChatService.shared.activateEmbeddedModel(at: modelURL)

        // Warmup nur im Simulator – auf dem Gerät spart das ~100 MB KV-Cache neben Piper.
        #if targetEnvironment(simulator)
        await MLXChatService.shared.warmUpInferenceIfNeeded()
        #endif
    }
}
