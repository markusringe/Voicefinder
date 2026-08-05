//
//  PiperModelProvider.swift
//  Voicefinder
//
//  Bundle-Pfade und Validierung für Piper-ONNX-Modelle (Sherpa-ONNX).
//

import Foundation

/// Pfade zu den Ressourcen einer Piper-Stimme im App-Bundle.
struct PiperVoiceResourcePaths: Sendable {
    /// Absoluter Pfad zur `.onnx`-Datei.
    let model: String
    /// Absoluter Pfad zu `tokens.txt`.
    let tokens: String
    /// Absoluter Pfad zum gemeinsamen `espeak-ng-data`-Verzeichnis.
    let espeakDataDir: String
}

/// Konfiguration für **ausschließlich fest eingebettete** Piper-Modelle (kein Runtime-Download).
enum PiperModelProvider {
    /// Bundle-Unterordner: `Resources/Models/piper-de/`.
    nonisolated private static let bundledModelsSubdirectory = "Models/piper-de"

    /// Gemeinsames espeak-ng-data-Verzeichnis (von allen Stimmen genutzt).
    nonisolated private static let espeakDirectoryName = "espeak-ng-data"

    /// Fest im App-Bundle erwartete Stimmen – entspricht `PiperVoice.allCases`.
    nonisolated static let embeddedVoices: [PiperVoice] = PiperVoice.allCases

    /// True, wenn alle eingebetteten Stimmen und espeak-ng-data im Bundle liegen.
    nonisolated static var isBundled: Bool {
        isFullyBundled
    }

    /// True, wenn jede erwartete Stimme vollständig im Bundle vorhanden ist.
    nonisolated static var isFullyBundled: Bool {
        guard bundledRootURL() != nil else { return false }
        return missingEmbeddedVoices().isEmpty && hasEspeakData
    }

    /// True, wenn Sherpa-ONNX auf dieser Plattform nutzbar ist.
    nonisolated static var isSupported: Bool {
        #if targetEnvironment(simulator) && arch(x86_64)
        false
        #else
        true
        #endif
    }

    /// Piper-Warmup beim Start, wenn das volle Stimmen-Bundle vorhanden ist.
    nonisolated static var requiresWarmup: Bool {
        isSupported && isFullyBundled
    }

    /// Liefert alle eingebetteten Stimmen, die tatsächlich im Bundle liegen.
    nonisolated static func availableVoices() -> [PiperVoice] {
        guard bundledRootURL() != nil else { return [] }
        return embeddedVoices.filter { isVoicePresent($0) }
    }

    /// Namen fehlender Stimmen (Entwickler-/Build-Diagnose).
    nonisolated static func missingEmbeddedVoices() -> [String] {
        guard bundledRootURL() != nil else {
            return embeddedVoices.map(\.displayName)
        }

        var missing: [String] = []
        if !hasEspeakData {
            missing.append("espeak-ng-data")
        }
        for voice in embeddedVoices where !isVoicePresent(voice) {
            missing.append(voice.displayName)
        }
        return missing
    }

    /// Prüft, ob eine konkrete Stimme vollständig im Bundle liegt.
    nonisolated static func isVoicePresent(_ voice: PiperVoice, in root: URL? = nil) -> Bool {
        let base = (root ?? bundledRootURL())?.appendingPathComponent("voices/\(voice.bundleSubdirectory)", isDirectory: true)
        guard let base else { return false }

        let onnx = base.appendingPathComponent(voice.onnxFileName)
        let tokens = base.appendingPathComponent("tokens.txt")
        let fm = FileManager.default
        return fm.fileExists(atPath: onnx.path) && fm.fileExists(atPath: tokens.path)
    }

    /// Liefert Pfade für Sherpa-ONNX-Konfiguration – wirft bei fehlender Stimme.
    nonisolated static func paths(for voice: PiperVoice) throws -> PiperVoiceResourcePaths {
        guard isFullyBundled, let root = bundledRootURL() else {
            throw PiperModelProviderError.notBundled
        }

        guard isVoicePresent(voice, in: root) else {
            throw PiperModelProviderError.voiceNotFound(voice.displayName)
        }

        let voiceDir = root.appendingPathComponent("voices/\(voice.bundleSubdirectory)", isDirectory: true)
        let espeakDir = root.appendingPathComponent(espeakDirectoryName, isDirectory: true)

        return PiperVoiceResourcePaths(
            model: voiceDir.appendingPathComponent(voice.onnxFileName).path,
            tokens: voiceDir.appendingPathComponent("tokens.txt").path,
            espeakDataDir: espeakDir.path
        )
    }

    /// Wählt die gespeicherte Stimme oder die Standard-Stimme aus dem eingebetteten Set.
    nonisolated static func resolvedVoice() -> PiperVoice {
        let stored = AppSettingsStore.piperVoice
        if isVoicePresent(stored) {
            return stored
        }
        return .thorstenMedium
    }

    // MARK: - Intern

    nonisolated private static var hasEspeakData: Bool {
        guard let root = bundledRootURL() else { return false }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent(espeakDirectoryName, isDirectory: true).path
        )
    }

    nonisolated private static func bundledRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }

        let candidates = [
            resourceURL.appendingPathComponent(bundledModelsSubdirectory, isDirectory: true),
            resourceURL.appendingPathComponent("piper-de", isDirectory: true)
        ]

        return candidates.first { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }
}

/// Fehler beim Zugriff auf Piper-Modellressourcen.
enum PiperModelProviderError: LocalizedError, Sendable {
    case notBundled
    case voiceNotFound(String)
    case espeakDataMissing
    case synthesisFailed

    var errorDescription: String? {
        switch self {
        case .notBundled:
            """
            Piper-Stimmen fehlen im App-Bundle. \
            Alle Modelle müssen fest unter Resources/Models/piper-de eingebunden sein.
            """
        case let .voiceNotFound(name):
            "Piper-Stimme „\(name)“ ist nicht im Bundle vorhanden."
        case .espeakDataMissing:
            "Gemeinsames espeak-ng-data-Verzeichnis fehlt im Piper-Bundle."
        case .synthesisFailed:
            "Piper konnte keinen Ton erzeugen."
        }
    }
}
