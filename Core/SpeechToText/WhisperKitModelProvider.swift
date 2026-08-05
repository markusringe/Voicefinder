//
//  WhisperKitModelProvider.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Fehler beim Zugriff auf lokal gebündelte WhisperKit-Modell-Ressourcen.
enum WhisperKitModelError: LocalizedError, Sendable {
    /// Das erwartete Modellverzeichnis fehlt im App-Bundle.
    case modelNotFoundInBundle(modelName: String)

    var errorDescription: String? {
        switch self {
        case let .modelNotFoundInBundle(modelName):
            return """
            WhisperKit-Modell „\(modelName)“ wurde im App-Bundle nicht gefunden. \
            Prüfe, ob „Resources/Models/\(modelName)“ als Copy-Bundle-Resource eingebunden ist.
            """
        }
    }
}

/// Löst Pfade zu offline gebündelten WhisperKit-Modellen im App-Bundle auf.
///
/// Die CoreML-Dateien liegen unter `Resources/Models/<modellname>/` und werden beim Build
/// in das App-Bundle kopiert. WhisperKit lädt sie über `modelFolder` ohne Hugging-Face-Download.
enum WhisperKitModelProvider {
    /// Standardmodellvariante, passend zum Ordner `openai_whisper-base`.
    nonisolated static let defaultModelName = "openai_whisper-base"

    /// Anzeigename für Startbildschirm und Einstellungen.
    nonisolated static var activeModelName: String {
        defaultModelName
    }

    /// True auf Gerät und arm64-Simulator – auf Intel-x86 nicht nutzbar.
    nonisolated static var isWhisperKitSupported: Bool {
        #if targetEnvironment(simulator) && arch(x86_64)
        false
        #else
        true
        #endif
    }

    /// True, wenn WhisperKit irgendwann geladen werden kann.
    nonisolated static var requiresWhisperWarmup: Bool {
        isWhisperKitSupported
    }

    /// True, wenn WhisperKit beim App-Start vorgeladen werden soll.
    /// Auf dem Gerät lazy (kein paralleles Laden neben MLX); im Simulator Pflicht für Live-Aufnahme.
    nonisolated static var requiresStartupWarmup: Bool {
        #if targetEnvironment(simulator)
        isWhisperKitSupported
        #else
        false
        #endif
    }

    /// Unterordner im Bundle, in dem Xcode die Modell-Ressourcen ablegt.
    nonisolated private static let modelsBundleSubdirectory = "Models"

    /// Liefert die URL zum gebündelten Modellordner mit CoreML-Dateien und Tokenizer.
    ///
    /// - Parameter modelName: Name des Modellordners, standardmäßig `openai_whisper-base`.
    /// - Returns: URL zum Modellverzeichnis im App-Bundle.
    /// - Throws: `WhisperKitModelError.modelNotFoundInBundle`, wenn die Ressource fehlt.
    nonisolated static func bundledModelFolderURL(modelName: String = defaultModelName) throws -> URL {
        guard let url = Bundle.main.url(
            forResource: modelName,
            withExtension: nil,
            subdirectory: modelsBundleSubdirectory
        ) else {
            throw WhisperKitModelError.modelNotFoundInBundle(modelName: modelName)
        }
        return url
    }

    /// Prüft, ob die wichtigsten Modell-Komponenten im Bundle vorhanden sind.
    ///
    /// Wird vor der WhisperKit-Initialisierung genutzt, um früh aussagekräftige Fehler zu liefern.
    nonisolated static func validateBundledModel(at folderURL: URL) throws {
        let requiredRelativePaths = [
            "config.json",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin",
            "tokenizer.json"
        ]

        let missingPaths = requiredRelativePaths.filter { relativePath in
            let fileURL = folderURL.appendingPathComponent(relativePath)
            return !FileManager.default.fileExists(atPath: fileURL.path)
        }

        guard missingPaths.isEmpty else {
            throw WhisperKitModelError.modelNotFoundInBundle(
                modelName: "\(folderURL.lastPathComponent) (fehlend: \(missingPaths.joined(separator: ", ")))"
            )
        }
    }
}
