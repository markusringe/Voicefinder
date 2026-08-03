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
    static let defaultModelName = "openai_whisper-base"

    /// Unterordner im Bundle, in dem Xcode die Modell-Ressourcen ablegt.
    private static let modelsBundleSubdirectory = "Models"

    /// Liefert die URL zum gebündelten Modellordner mit CoreML-Dateien und Tokenizer.
    ///
    /// - Parameter modelName: Name des Modellordners, standardmäßig `openai_whisper-base`.
    /// - Returns: URL zum Modellverzeichnis im App-Bundle.
    /// - Throws: `WhisperKitModelError.modelNotFoundInBundle`, wenn die Ressource fehlt.
    static func bundledModelFolderURL(modelName: String = defaultModelName) throws -> URL {
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
    static func validateBundledModel(at folderURL: URL) throws {
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
