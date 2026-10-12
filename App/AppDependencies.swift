//
//  AppDependencies.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Zentrale Dependency-Injection für alle Pipeline-Engines der App.
struct AppDependencies {
    let speechToTextEngine: any SpeechToTextEngine
    let languageEngine: any LanguageEngine
    let textToSpeechEngine: any TextToSpeechEngine

    /// Simulator mit WhisperKit-Aufnahme: konkrete Composite-Referenz für `stopStreamingAndFinalize()`.
    let stopFinalizingSpeechEngine: CompositeSpeechToTextEngine?

    /// True im iOS-Simulator – UI-Hinweise und ggf. anderer STT-Pfad.
    static let usesSimulatorSpeechFallback: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// True, wenn der Simulator WhisperKit für Mikrofon nutzt (nicht auf Intel-x86).
    static let usesWhisperKitRecordingFallback: Bool = {
        #if targetEnvironment(simulator)
        WhisperKitModelProvider.isWhisperKitSupported
        #else
        false
        #endif
    }()

    /// Gemeinsame Composite-Instanz für Hintergrund-Vorbereitung (WhisperKit-Preload).
    private let compositeSpeechEngine: CompositeSpeechToTextEngine?

    /// Piper-Engine für Hintergrund-Warmup und Stimmen-Einstellungen.
    private let piperTextToSpeechEngine: PiperTextToSpeechEngine?

    /// Composite-TTS für Stimmen-Einstellungen (Stimme/Geschwindigkeit durchreichen).
    private let compositeTextToSpeechEngine: CompositeTextToSpeechEngine?

    /// Lädt Piper sequenziell nach der LLM-Antwort (nicht parallel zum MLX-Stream).
    let piperPreloadAction: (@Sendable () async -> Void)?

    /// Gibt Piper-ONNX frei, bevor MLX inferiert (Spitzen-RAM vermeiden).
    let releasePiperForLLMAction: (@Sendable () async -> Void)?

    /// Entlastet RAM vor MLX (Piper freigeben) – nur bei Speicherdruck oder periodischem Flush.
    let trimMemoryBeforeLLMAction: (@Sendable () async -> Void)?

    /// Vereinfachter Init für Tests ohne Warmup-Engines.
    init(
        speechToTextEngine: any SpeechToTextEngine,
        languageEngine: any LanguageEngine,
        textToSpeechEngine: any TextToSpeechEngine,
        stopFinalizingSpeechEngine: CompositeSpeechToTextEngine? = nil
    ) {
        self.speechToTextEngine = speechToTextEngine
        self.languageEngine = languageEngine
        self.textToSpeechEngine = textToSpeechEngine
        self.stopFinalizingSpeechEngine = stopFinalizingSpeechEngine
        self.compositeSpeechEngine = nil
        self.piperTextToSpeechEngine = nil
        self.compositeTextToSpeechEngine = nil
        self.piperPreloadAction = nil
        self.releasePiperForLLMAction = nil
        self.trimMemoryBeforeLLMAction = nil
    }

    /// Vollständiger Init für die Live-App inkl. Warmup-Referenzen.
    private init(
        speechToTextEngine: any SpeechToTextEngine,
        languageEngine: any LanguageEngine,
        textToSpeechEngine: any TextToSpeechEngine,
        stopFinalizingSpeechEngine: CompositeSpeechToTextEngine?,
        compositeSpeechEngine: CompositeSpeechToTextEngine,
        piperTextToSpeechEngine: PiperTextToSpeechEngine,
        compositeTextToSpeechEngine: CompositeTextToSpeechEngine
    ) {
        self.speechToTextEngine = speechToTextEngine
        self.languageEngine = languageEngine
        self.textToSpeechEngine = textToSpeechEngine
        self.stopFinalizingSpeechEngine = stopFinalizingSpeechEngine
        self.compositeSpeechEngine = compositeSpeechEngine
        self.piperTextToSpeechEngine = piperTextToSpeechEngine
        self.compositeTextToSpeechEngine = compositeTextToSpeechEngine

        if PiperModelProvider.requiresWarmup {
            self.piperPreloadAction = {
                try? await piperTextToSpeechEngine.prepareIfNeeded()
            }
            self.releasePiperForLLMAction = {
                await compositeTextToSpeechEngine.releaseHeavyResourcesAfterSpeak()
            }
            self.trimMemoryBeforeLLMAction = {
                await MLXChatService.shared.cancelActiveGenerationAndWait()
                await compositeTextToSpeechEngine.releaseHeavyResourcesAfterSpeak()
            }
        } else {
            self.piperPreloadAction = nil
            self.releasePiperForLLMAction = nil
            self.trimMemoryBeforeLLMAction = nil
        }
    }

    /// Standard-Konfiguration für die lokale Voice-Pipeline.
    @MainActor
    static func live() -> AppDependencies {
        #if targetEnvironment(simulator)
        let whisperEngine = WhisperKitTranscriber()
        #endif

        let liveEngine: any SpeechToTextEngine
        let fileEngine: any FileTranscribing
        let whisperFileEngine: WhisperKitTranscriber?

        #if targetEnvironment(simulator)
        if WhisperKitModelProvider.isWhisperKitSupported {
            liveEngine = WhisperKitRecordingTranscriber(whisperFileEngine: whisperEngine)
            fileEngine = whisperEngine
            whisperFileEngine = whisperEngine
        } else {
            liveEngine = AppleSpeechTranscriber()
            fileEngine = AppleSpeechFileTranscriber()
            whisperFileEngine = nil
        }
        #else
        // Gerät: nur Apple Speech – WhisperKit (~400 MB) nie parallel zum MLX laden.
        liveEngine = AppleSpeechTranscriber()
        fileEngine = AppleSpeechFileTranscriber()
        whisperFileEngine = nil
        #endif

        let composite = CompositeSpeechToTextEngine(
            liveEngine: liveEngine,
            fileEngine: fileEngine,
            whisperFileEngine: whisperFileEngine
        )

        let piperTTS = PiperTextToSpeechEngine()
        let compositeTTS = CompositeTextToSpeechEngine(piper: piperTTS)

        return AppDependencies(
            speechToTextEngine: composite,
            languageEngine: Self.makeLanguageEngine(),
            textToSpeechEngine: compositeTTS,
            stopFinalizingSpeechEngine: Self.usesWhisperKitRecordingFallback ? composite : nil,
            compositeSpeechEngine: composite,
            piperTextToSpeechEngine: piperTTS,
            compositeTextToSpeechEngine: compositeTTS
        )
    }

    /// Initialisiert kritische eingebettete Ressourcen – sequenziell über `StartupViewModel`.
    func bootstrapEmbeddedResources() async throws {
        try await warmUpOfflineSpeechModelsThrowing()
        if LLMModelProvider.isSupported {
            try await EmbeddedLLMBootstrap.activateEmbeddedModel()
        }
    }

    /// Lädt WhisperKit-Modelle – wirft bei Fehlern (Startbildschirm).
    func warmUpOfflineSpeechModelsThrowing() async throws {
        guard WhisperKitModelProvider.requiresStartupWarmup,
              let compositeSpeechEngine else { return }
        try await compositeSpeechEngine.prepareOfflineModelsIfNeeded()
    }

    /// Lädt WhisperKit-Modelle im Hintergrund vor, wenn auf dieser Plattform nötig.
    func warmUpOfflineSpeechModels() async {
        try? await warmUpOfflineSpeechModelsThrowing()
    }

    /// Lädt Piper im Hintergrund vor (Simulator-Startbildschirm).
    func warmUpPiperModels() async {
        do {
            try await warmUpPiperModelsIfNeeded()
        } catch {
            NSLog("[Voicefinder] Piper-Warmup fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Entlastet Speicher nach iOS-Warnung – laufende Nutzer-Antwort (MLX/TTS) nicht hart abbrechen.
    func releaseMemoryUnderPressure() async {
        let mlxBusy = await MLXChatService.shared.isGenerationInProgress
        if mlxBusy {
            NSLog("[Voicefinder] Speicherwarnung – MLX-Antwort läuft weiter, kein harter Abbruch.")
        } else {
            await MLXChatService.shared.cancelActiveGenerationAndWait()
        }

        await MLXChatService.shared.dropPromptCache()

        if SpeechDeliveryCoordinator.isActive {
            NSLog("[Voicefinder] Speicherwarnung während TTS – Piper bleibt geladen bis Ende der Wiedergabe.")
        } else {
            await compositeTextToSpeechEngine?.releaseHeavyResourcesAfterSpeak()
        }
        // Speicherflag bleibt aktiv – Vorsichtsphase läuft über AppMemoryCoordinator weiter.
    }

    /// Vor Sprachausgabe schwere Ressourcen freigeben (Gerät: MLX pausieren, Piper laden).
    func trimMemoryBeforeVoiceOutput() async {
        await MLXChatService.shared.cancelActiveGenerationAndWait()
        await compositeTextToSpeechEngine?.releaseHeavyResourcesAfterSpeak()
    }

    /// Wirft bei fehlgeschlagenem Piper-Warmup.
    func warmUpPiperModelsIfNeeded() async throws {
        guard PiperModelProvider.requiresWarmup,
              let piperTextToSpeechEngine else { return }
        try await piperTextToSpeechEngine.prepareIfNeeded()
    }

    /// Wendet Stimmen-Einstellungen auf die Composite-TTS-Engine an.
    func applyVoiceSettings(voice: PiperVoice, speed: Float) async {
        await compositeTextToSpeechEngine?.applyVoiceSettings(voice: voice, speed: speed)
    }

    /// True, wenn Piper nach Warmup bereit ist.
    var isPiperEngineReady: Bool {
        get async {
            guard let piperTextToSpeechEngine else { return false }
            return await piperTextToSpeechEngine.isReady
        }
    }

    /// Wählt die Language Engine: eingebettetes MLX-LLM oder Regel-Engine (Intel-Simulator).
    @MainActor
    private static func makeLanguageEngine() -> any LanguageEngine {
        if LLMModelProvider.isSupported {
            return WebAugmentedLanguageEngine(
                inner: ResilientLanguageEngine(primaryEngine: LocalLLMEngine()),
                webSearch: CompositeWebSearchService()
            )
        }
        return RuleBasedLanguageEngine()
    }
}
