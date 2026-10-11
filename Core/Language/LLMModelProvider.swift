//
//  LLMModelProvider.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import MLXLMCommon

/// Fest eingebettetes MLX-Sprachmodell im App-Bundle – kein Runtime-Download.
///
/// Xcode kopiert `Resources/Models/qwen3-1.7B-4bit` via **Copy Bundle Resources**
/// mit in die `.app`. Das ist Teil der App wie Assets oder Whisper-Modelle.
///
/// Bewusst 1,7B statt 4B: ~1 GB RAM statt ~3 GB – stabil auf iPhone mit 8 GB.
enum LLMModelProvider {
    /// Produktiv-Modell – fest im Repository und im App-Bundle verankert.
    nonisolated static let defaultModelFolderName = "qwen3-1.7B-4bit"

    /// Aktiver Modellordner. Debug-Builds können per Launch-Argument
    /// `-voicefinder.debug.llmModel <Ordnername>` ein anderes Modell aus `Resources/Models` testen.
    nonisolated static var embeddedModelFolderName: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "voicefinder.debug.llmModel"),
           !override.isEmpty {
            return override
        }
        #endif
        return defaultModelFolderName
    }

    /// Hugging-Face-ID – nur für das Entwickler-Setup-Skript.
    nonisolated static let huggingFaceModelID = "mlx-community/Qwen3-1.7B-4bit"

    nonisolated static var displayName: String {
        embeddedModelFolderName == defaultModelFolderName
            ? "Qwen3-1.7B (eingebettet)"
            : "\(embeddedModelFolderName) (Debug-Test)"
    }

    nonisolated private static let modelsBundleSubdirectory = "Models"

    /// Marker für ein vollständiges MLX-Modellverzeichnis im Bundle.
    nonisolated private static let modelMarkers = [
        "config.json",
        "model.safetensors",
        "tokenizer.json"
    ]

    /// MLX auf Apple Silicon (nicht Intel-x86-Simulator).
    nonisolated static var isSupported: Bool {
        #if targetEnvironment(simulator) && arch(x86_64)
        false
        #else
        true
        #endif
    }

    /// True, wenn das eingebettete Modell im gebauten App-Bundle liegt.
    nonisolated static var isEmbeddedInAppBundle: Bool {
        embeddedModelDirectoryURL() != nil
    }

    /// URL des eingebetteten Modells – wirft, wenn das Bundle unvollständig ist.
    nonisolated static func requiredEmbeddedModelURL() throws -> URL {
        guard isSupported else {
            throw LLMModelProviderError.unsupportedPlatform
        }
        guard let url = embeddedModelDirectoryURL() else {
            throw LLMModelProviderError.modelNotEmbedded
        }
        try validateModelDirectory(url)
        return url
    }

    /// Sucht den Modellordner in typischen Xcode-Bundle-Layouts.
    nonisolated static func embeddedModelDirectoryURL() -> URL? {
        let name = embeddedModelFolderName

        if let url = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: modelsBundleSubdirectory
        ), isValidModelDirectory(url) {
            return url
        }

        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           isValidModelDirectory(url) {
            return url
        }

        guard let resourceURL = Bundle.main.resourceURL else { return nil }

        let candidates = [
            resourceURL.appendingPathComponent("\(modelsBundleSubdirectory)/\(name)", isDirectory: true),
            resourceURL.appendingPathComponent(name, isDirectory: true)
        ]
        return candidates.first { isValidModelDirectory($0) }
    }

    nonisolated static func validateModelDirectory(_ url: URL) throws {
        guard isValidModelDirectory(url) else {
            let missing = modelMarkers.filter {
                !FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
            }
            throw LLMModelProviderError.modelNotFound(path: url.path, missing: missing)
        }
    }

    nonisolated static func isValidModelDirectory(_ url: URL) -> Bool {
        modelMarkers.allSatisfy {
            FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
        }
    }

    nonisolated static func embeddedModelConfiguration() throws -> ModelConfiguration {
        ModelConfiguration(directory: try requiredEmbeddedModelURL())
    }
}

/// Fehler beim eingebetteten MLX-Modell.
enum LLMModelProviderError: LocalizedError, Sendable {
    case unsupportedPlatform
    case modelNotEmbedded
    case modelNotActivated
    case modelNotFound(path: String, missing: [String])

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "Das eingebettete Sprachmodell läuft nicht auf Intel-x86-Simulatoren."
        case .modelNotEmbedded:
            """
            Das Sprachmodell fehlt im App-Bundle. \
            Ordner `Resources/Models/qwen3-1.7B-4bit` muss unter \
            „Copy Bundle Resources“ eingetragen sein, dann Clean Build. \
            Einmalig: Scripts/setup-llm-bundle.sh
            """
        case .modelNotActivated:
            "Das eingebettete Sprachmodell wurde noch nicht initialisiert."
        case let .modelNotFound(path, missing):
            "Eingebettetes Modell unvollständig unter „\(path)“. Fehlend: \(missing.joined(separator: ", "))."
        }
    }
}
