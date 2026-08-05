//
//  ConversationOrchestrator.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation

/// Zentrale Steuerung der Voice-Pipeline: STT → Language Engine → TTS.
///
/// Hält den Gesprächszustand explizit und leitet partielle sowie finale Transkripte
/// an die nachgelagerten Engines weiter.
actor ConversationOrchestrator {
    private(set) var state: ConversationState = .idle
    private(set) var turns: [ChatTurn] = []
    private(set) var partialText: String = ""

    private let speechToTextEngine: any SpeechToTextEngine
    private let stopFinalizingSpeechEngine: CompositeSpeechToTextEngine?
    private let languageEngine: any LanguageEngine
    private let textToSpeechEngine: any TextToSpeechEngine
    /// Lädt Piper nach der LLM-Antwort vor (sequenziell, nicht parallel zum MLX).
    private let preloadPiperForSpeech: (@Sendable () async -> Void)?
    /// Entlädt Piper vor MLX-Inferenz – vermeidet gleichzeitig LLM + ONNX im RAM.
    private let releasePiperForLLM: (@Sendable () async -> Void)?
    /// Gibt Piper vor MLX frei.
    private let trimMemoryBeforeLLM: (@Sendable () async -> Void)?
    private var piperPreloadTask: Task<Void, Never>?
    /// Verzögerte KI-Gehirn-Anreicherung – blockiert nicht die nächste Antwort.
    private var brainEnrichmentTask: Task<Void, Never>?

    private var partialListeningTask: Task<Void, Never>?
    private var finalListeningTask: Task<Void, Never>?
    private var levelListeningTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var isListening = false
    /// Nutzer hat das Mikrofon stummgeschaltet – keine Transkription und Pipeline.
    private var isMicrophoneMutedByUser = false
    /// Erkennt Sprechpausen, wenn STT keine finalen Segmente liefert (typisch bei Apple Speech).
    private var utteranceEndTask: Task<Void, Never>?
    private var latestPartialUtterance: String = ""
    /// Verhindert doppelte Pipeline-Starts für denselben Satz.
    private var lastSubmittedUtterance: String = ""
    private var lastSubmittedAt: Date = .distantPast
    /// True, sobald während WhisperKit-Aufnahme Sprachenergie erkannt wurde.
    private var speechEnergyDetected = false
    /// STT ist pausiert während LLM/TTS – verhindert Echo-Rückkopplung.
    private var isSTTSuspended = false
    /// Aktueller KI-Charakter (System-Prompt) für die Language Engine.
    private var characterPrompt: String = CharacterProfileStore.load()
    /// Antwort-Stil (Normal, Forsch, Frech, Lustig, Schlau).
    private var interactionStyle: AIInteractionStyle = AppSettingsStore.aiInteractionStyle
    /// Internet-Recherche vor LLM-Antworten (Google primär, DuckDuckGo/Wikipedia als Fallback).
    private var internetEnabled: Bool = AppSettingsStore.internetEnabled
    /// Dauerhaft gespeichertes Nutzerprofil (KI-Gehirn).
    private var userBrain: UserBrainProfile = UserBrainProfile()
    /// Verhindert mehrfache Gesprächseröffnung pro Sitzung.
    private var conversationOpeningDelivered = false
    private var conversationOpeningTask: Task<Void, Never>?
    /// Hintergrund-LLM für Eröffnungsvorbereitung – wird bei Nutzer-Input abgebrochen.
    private var conversationPreparationTask: Task<String?, Never>?
    /// Vorbereiteter Eröffnungstext – wird auf Knopfdruck gesprochen.
    private var preparedConversationOpeningText: String?

    /// Drosselt UI-Callbacks – mehrere schnelle Zustandswechsel werden zu einem MainActor-Update gebündelt.
    private var uiNotifyScheduled = false
    /// Drosselt Mikrofonpegel-Updates an die UI (~20 Hz statt ~100 Hz).
    private var lastLevelDispatchInstant: ContinuousClock.Instant?
    private static let uiNotifyCoalesceInterval: Duration = .milliseconds(32)
    private static let levelDispatchInterval: Duration = .milliseconds(50)

    private var onUpdate: (@MainActor @Sendable (ConversationState, [ChatTurn], String) -> Void)?
    private var onLevelUpdate: (@MainActor @Sendable (Float) -> Void)?
    private var onBrainUpdate: (@MainActor @Sendable (UserBrainProfile) -> Void)?

    init(dependencies: AppDependencies) {
        self.speechToTextEngine = dependencies.speechToTextEngine
        self.stopFinalizingSpeechEngine = dependencies.stopFinalizingSpeechEngine
        self.languageEngine = dependencies.languageEngine
        self.textToSpeechEngine = dependencies.textToSpeechEngine
        self.preloadPiperForSpeech = dependencies.piperPreloadAction
        self.releasePiperForLLM = dependencies.releasePiperForLLMAction
        self.trimMemoryBeforeLLM = dependencies.trimMemoryBeforeLLMAction
    }

    /// Aktualisiert den KI-Charakter für künftige Antworten.
    func setCharacterPrompt(_ prompt: String) {
        characterPrompt = prompt
    }

    /// Aktualisiert den Antwort-Stil für künftige Antworten.
    func setInteractionStyle(_ style: AIInteractionStyle) {
        interactionStyle = style
    }

    /// Schaltet Internet-Recherche für faktische Fragen ein oder aus.
    func setInternetEnabled(_ enabled: Bool) {
        internetEnabled = enabled
    }

    /// Aktualisiert das Nutzerprofil (KI-Gehirn) für künftige Antworten.
    func setUserBrain(_ profile: UserBrainProfile) {
        var synced = profile
        _ = synced.syncStandardFieldsFromEntries()
        userBrain = synced
    }

    /// Bereitet die Eröffnung vor (ohne zu sprechen) – mit oder ohne Auftrag.
    func prepareConversationOpeningText() async -> String? {
        guard turns.isEmpty else { return nil }
        guard !conversationOpeningDelivered else { return nil }

        if let cached = preparedConversationOpeningText,
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }

        conversationPreparationTask?.cancel()
        let task = Task<String?, Never> {
            await self.generateConversationOpeningText()
        }
        conversationPreparationTask = task
        let generated = await task.value
        conversationPreparationTask = nil

        guard !Task.isCancelled, let generated, !generated.isEmpty else { return nil }
        preparedConversationOpeningText = generated
        return generated
    }

    /// Spricht die vorbereitete Eröffnung und startet das Gespräch.
    func startPreparedConversationOpening() async {
        guard !conversationOpeningDelivered else { return }
        guard turns.isEmpty else { return }

        var text = preparedConversationOpeningText
        if text == nil || text?.isEmpty == true {
            text = await generateConversationOpeningText()
        }
        guard let text, !text.isEmpty else { return }

        conversationOpeningTask?.cancel()
        conversationOpeningTask = Task {
            await self.speakConversationOpening(text)
        }
        await conversationOpeningTask?.value
        conversationOpeningTask = nil
    }

    /// Beendet das laufende Gespräch (Pipeline, Mikrofon, Verlauf).
    func endConversation() async {
        conversationOpeningTask?.cancel()
        conversationOpeningTask = nil
        conversationPreparationTask?.cancel()
        conversationPreparationTask = nil
        cancelBackgroundWork()
        cancelStreamConsumers()
        utteranceEndTask?.cancel()
        utteranceEndTask = nil
        await interruptActivePipeline(keepListening: false)

        if isListening {
            await stopListening()
        }

        turns.removeAll()
        partialText = ""
        latestPartialUtterance = ""
        lastSubmittedUtterance = ""
        lastSubmittedAt = .distantPast
        preparedConversationOpeningText = nil
        conversationOpeningDelivered = false
        uiNotifyScheduled = false
        AppMemoryCoordinator.resetDialogRoundCounter()
        setState(.idle)
        notifyObservers()
    }

    /// Entfernt Observer-Callbacks – verhindert verwaiste UI-Updates nach ViewModel-Ende.
    func clearObservers() {
        onUpdate = nil
        onLevelUpdate = nil
        onBrainUpdate = nil
    }

    /// Registriert Callback, wenn das Profil aus dem Gespräch ergänzt wurde.
    func setOnBrainUpdate(_ handler: @escaping @MainActor @Sendable (UserBrainProfile) -> Void) {
        onBrainUpdate = handler
        let current = userBrain
        Task { @MainActor in
            handler(current)
        }
    }

    /// Registriert einen Callback für Zustandsänderungen auf dem MainActor (z. B. ViewModel).
    func setOnUpdate(
        _ handler: @escaping @MainActor @Sendable (ConversationState, [ChatTurn], String) -> Void
    ) {
        onUpdate = handler
        let currentState = state
        let currentTurns = turns
        let currentPartialText = partialText
        Task { @MainActor in
            handler(currentState, currentTurns, currentPartialText)
        }
    }

    /// Registriert einen Callback für Mikrofonpegel (0…1) auf dem MainActor.
    func setOnLevelUpdate(_ handler: @escaping @MainActor @Sendable (Float) -> Void) {
        onLevelUpdate = handler
    }

    /// Startet die Mikrofon-Erfassung und lauscht auf partielle sowie finale Transkripte.
    func startListening() async throws {
        if isListening {
            return
        }

        if isPipelineActive {
            await interruptActivePipeline(keepListening: true)
        }

        setState(.requestingPermissions)

        let granted = await speechToTextEngine.requestAuthorization()
        guard granted else {
            setState(.failed(message: "Mikrofon- oder Spracherkennungsberechtigung wurde verweigert."))
            return
        }

        try await speechToTextEngine.startStreaming()
        isListening = true
        // Kein Barge-in: Mikrofon pausiert während TTS, sonst hört sich die KI selbst zu.
        await AudioSessionCoordinator.shared.setBargeInEnabled(false)
        setState(.listening)

        let partialStream = await speechToTextEngine.partialTextStream
        let finalStream = await speechToTextEngine.finalTextStream
        let levelStream = await speechToTextEngine.audioLevelStream
        startStreamConsumers(
            partialStream: partialStream,
            finalStream: finalStream,
            levelStream: levelStream
        )
    }

    /// Beendet die Mikrofon-Erfassung und startet ggf. die Antwort-Pipeline.
    func stopListening() async {
        guard isListening else { return }

        utteranceEndTask?.cancel()
        utteranceEndTask = nil
        isListening = false
        await AudioSessionCoordinator.shared.setBargeInEnabled(false)

        cancelStreamConsumers()

        if let finalizer = stopFinalizingSpeechEngine {
            NSLog("[Voicefinder] Mikrofon-Stopp: WhisperKit-Finalize-Pfad")
            setState(.transcribing(partialText: "WhisperKit transkribiert …"))
            notifyObservers()

            guard let finalText = await finalizer.stopStreamingAndFinalize()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !finalText.isEmpty else {
                print("[Voicefinder] Kein Transkript nach Aufnahme-Stopp.")
                setState(.failed(message: "Keine Sprache erkannt. Bitte erneut versuchen."))
                notifyObservers()
                return
            }

            print("[Voicefinder] Transkript: \(finalText)")
            NSLog("[Voicefinder] Pipeline-Start mit: %@", finalText)
            partialText = finalText
            notifyObservers()

            pipelineTask?.cancel()
            pipelineTask = Task {
                await self.processUserText(finalText)
            }
            return
        }

        await speechToTextEngine.stopStreaming()

        for _ in 0 ..< 30 {
            if isPipelineActive { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        notifyObservers()

        switch state {
        case .listening:
            setState(.idle)
        case .transcribing where !isPipelineActive:
            setState(.failed(message: "Keine Sprache erkannt. Bitte erneut versuchen."))
        default:
            break
        }
    }

    /// Verarbeitet manuell eingegebenen Text (Fallback bis Live-Mikrofon-STT verfügbar ist).
    func submitUserText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pipelineTask?.cancel()
        pipelineTask = Task {
            await self.handleSubmittedText(trimmed)
        }
    }

    /// Verarbeitet Texteingabe auf dem Orchestrator-Actor (ohne unnötige await-Aufrufe).
    private func handleSubmittedText(_ trimmed: String) async {
        if isPipelineActive {
            await interruptActivePipeline(keepListening: isListening)
        }
        await processUserText(trimmed)
    }

    /// Stoppt laufende Sprachausgabe und setzt den Zustand auf unterbrochen.
    func interruptSpeaking() async {
        await interruptActivePipeline(keepListening: isListening)
        if !isListening {
            setState(.interrupted)
        }
    }

    /// Schaltet das Mikrofon stumm oder wieder frei (STT pausiert, Pipeline bleibt aus).
    func setMicrophoneMuted(_ muted: Bool) async {
        isMicrophoneMutedByUser = muted
        partialText = ""
        latestPartialUtterance = ""
        speechEnergyDetected = false
        utteranceEndTask?.cancel()

        if muted {
            if let pausable = speechToTextEngine as? PausableSpeechToTextEngine, !isSTTSuspended {
                await pausable.pauseStreaming()
            }
        } else if isListening, !isSTTSuspended {
            if let pausable = speechToTextEngine as? PausableSpeechToTextEngine {
                do {
                    try await pausable.resumeStreaming()
                } catch {
                    recoverFromPipelineError(error)
                }
            }
        }

        notifyObservers()
    }

    // MARK: - Stream-Verarbeitung

    private func startStreamConsumers(
        partialStream: AsyncStream<String>,
        finalStream: AsyncStream<String>,
        levelStream: AsyncStream<Float>
    ) {
        cancelStreamConsumers()

        partialListeningTask = Task {
            for await partial in partialStream {
                guard !Task.isCancelled else { break }
                await self.applyPartialTranscript(partial)
            }
        }

        finalListeningTask = Task {
            for await finalText in finalStream {
                guard !Task.isCancelled else { break }
                await self.applyFinalTranscript(finalText)
            }
        }

        levelListeningTask = Task {
            for await level in levelStream {
                guard !Task.isCancelled else { break }
                self.applyAudioLevel(level)
            }
        }
    }

    private func applyAudioLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)

        // Pegel nur gedrosselt an die UI – sonst ~100 MainActor-Tasks pro Sekunde.
        if let onLevelUpdate {
            let now = ContinuousClock.now
            let shouldDispatch: Bool
            if let lastLevelDispatchInstant {
                shouldDispatch = now - lastLevelDispatchInstant >= Self.levelDispatchInterval
            } else {
                shouldDispatch = true
            }
            if shouldDispatch {
                lastLevelDispatchInstant = now
                Task { @MainActor in
                    onLevelUpdate(clamped)
                }
            }
        }

        // WhisperKit-Aufnahme: Partials ändern sich nicht – Sprechpause über Pegel erkennen.
        if stopFinalizingSpeechEngine != nil, isListening, !isPipelineActive, !isSTTSuspended, !isMicrophoneMutedByUser {
            if clamped >= Self.speechEnergyThreshold {
                speechEnergyDetected = true
            }
            if speechEnergyDetected {
                scheduleUtteranceEndDetection(for: latestPartialUtterance, forceReschedule: true)
            }
        }
    }

    /// Stille nach dem letzten Partial, bevor der Satz als fertig gilt (Apple Speech liefert oft keine Finals).
    private static let utteranceSilenceNanoseconds: UInt64 = 850_000_000
    /// Mindest-Pegel, ab dem gesprochene Sprache für WhisperKit-Pausenerkennung zählt.
    private static let speechEnergyThreshold: Float = 0.08
    /// Gleicher Satz wird innerhalb dieses Fensters nicht erneut gestartet.
    private static let utteranceDedupInterval: TimeInterval = 2.0

    private func applyPartialTranscript(_ partial: String) async {
        guard !isSTTSuspended, !isMicrophoneMutedByUser else { return }

        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Live-Partials nur beim Zuhören/Transkribieren – nicht während Denken/Sprechen überschreiben.
        switch state {
        case .listening, .transcribing:
            partialText = trimmed
            setState(.transcribing(partialText: trimmed))
            if stopFinalizingSpeechEngine == nil {
                scheduleUtteranceEndDetection(for: trimmed)
            }
        default:
            break
        }
    }

    /// Startet die Pipeline nach Sprechpause, wenn kein finales STT-Segment kam.
    /// Timer wird nur bei geändertem Text neu gesetzt (identische Partials unterbrechen nicht).
    private func scheduleUtteranceEndDetection(
        for text: String,
        forceReschedule: Bool = false
    ) {
        if !forceReschedule, text == latestPartialUtterance, utteranceEndTask != nil {
            return
        }

        latestPartialUtterance = text
        utteranceEndTask?.cancel()
        utteranceEndTask = Task {
            try? await Task.sleep(nanoseconds: Self.utteranceSilenceNanoseconds)
            guard !Task.isCancelled else { return }
            if self.stopFinalizingSpeechEngine != nil {
                await self.finalizeWhisperKitUtterance()
            } else {
                await self.submitDetectedUtterance(self.latestPartialUtterance)
            }
        }
    }

    /// WhisperKit: Aufnahme nach Sprechpause stoppen, transkribieren und Pipeline starten.
    private func finalizeWhisperKitUtterance() async {
        guard isListening, !isMicrophoneMutedByUser else { return }
        guard !isPipelineActive else { return }
        guard speechEnergyDetected else { return }

        let now = Date()
        if now.timeIntervalSince(lastSubmittedAt) < Self.utteranceDedupInterval {
            return
        }

        lastSubmittedAt = now
        speechEnergyDetected = false
        utteranceEndTask?.cancel()

        NSLog("[Voicefinder] WhisperKit: Sprechpause erkannt – transkribiere Aufnahme.")
        setState(.transcribing(partialText: "WhisperKit transkribiert …"))
        notifyObservers()

        pipelineTask?.cancel()
        pipelineTask = Task {
            await self.processWhisperKitRecording()
        }
    }

    /// Stoppt WhisperKit-Aufnahme, verarbeitet das Transkript und startet danach erneut das Mikrofon.
    private func processWhisperKitRecording() async {
        guard let finalizer = stopFinalizingSpeechEngine else { return }

        let finalText = await finalizer.stopStreamingAndFinalize()?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let finalText, finalText.count >= 2 else {
            NSLog("[Voicefinder] WhisperKit: Kein brauchbares Transkript nach Sprechpause.")
            partialText = ""
            setState(isListening ? .listening : .idle)
            notifyObservers()
            await restartListeningAfterWhisperKit()
            return
        }

        lastSubmittedUtterance = finalText
        NSLog("[Voicefinder] Pipeline-Start (WhisperKit): %@", finalText)
        await processUserText(finalText)
        await restartListeningAfterWhisperKit()
    }

    /// Startet nach WhisperKit-Finalize erneut Live-Aufnahme und Stream-Consumer.
    private func restartListeningAfterWhisperKit() async {
        guard isListening else { return }

        do {
            try await speechToTextEngine.startStreaming()
            let partialStream = await speechToTextEngine.partialTextStream
            let finalStream = await speechToTextEngine.finalTextStream
            let levelStream = await speechToTextEngine.audioLevelStream
            startStreamConsumers(
                partialStream: partialStream,
                finalStream: finalStream,
                levelStream: levelStream
            )
            speechEnergyDetected = false
            setState(.listening)
        } catch {
            isListening = false
            setState(.failed(message: error.localizedDescription))
        }
    }

    /// Verarbeitet erkannten Nutzertext (final oder nach Sprechpause, Apple Speech).
    private func submitDetectedUtterance(_ text: String) async {
        guard !isSTTSuspended, !isMicrophoneMutedByUser else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        guard isListening else { return }
        if isPipelineActive {
            await interruptActivePipeline(keepListening: true)
        }

        if isLikelyEchoOfAssistantSpeech(trimmed) {
            NSLog("[Voicefinder] Echo erkannt – ignoriert: %@", trimmed)
            return
        }

        let now = Date()
        if trimmed == lastSubmittedUtterance,
           now.timeIntervalSince(lastSubmittedAt) < Self.utteranceDedupInterval {
            return
        }

        lastSubmittedUtterance = trimmed
        lastSubmittedAt = now

        NSLog("[Voicefinder] Pipeline-Start: %@", trimmed)
        utteranceEndTask?.cancel()
        pipelineTask?.cancel()
        pipelineTask = Task {
            await self.processUserText(trimmed)
        }
    }

    private func applyFinalTranscript(_ finalText: String) async {
        guard !isSTTSuspended, !isMicrophoneMutedByUser else { return }

        partialText = finalText
        notifyObservers()
        await submitDetectedUtterance(finalText)
    }

    /// Maximale gespeicherte Runden (Nutzer+Assistent) – genug Kontext für MLX, begrenzt RAM.
    private static let maxStoredTurns = 8

    /// Kernpipeline: Nutzertext speichern, Antwort erzeugen und vorlesen.
    private func processUserText(_ text: String) async {
        conversationOpeningTask?.cancel()
        conversationOpeningTask = nil
        conversationPreparationTask?.cancel()
        conversationPreparationTask = nil
        preparedConversationOpeningText = nil

        // Laufende MLX-Generierung stoppen, bevor eine neue Runde startet.
        await MLXChatService.shared.cancelActiveGenerationAndWait()
        cancelBackgroundWork()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !Task.isCancelled else { return }

        brainEnrichmentTask?.cancel()
        await suspendSTTForAssistantOutput()
        await textToSpeechEngine.stop()
        piperPreloadTask?.cancel()
        piperPreloadTask = nil

        turns.append(ChatTurn(role: .user, text: trimmed))
        trimTurnsIfNeeded()
        partialText = trimmed
        setState(.thinking(userText: trimmed))

        userBrain = await UserBrainStore.shared.ingestUserMessage(trimmed)
        notifyBrainObservers()

        NSLog("[Voicefinder] Language-Engine startet für: %@", trimmed)

        // Rollen-/Auftragsfragen direkt aus dem KI-Gehirn – ohne Web/LLM-Latenz.
        if let directAnswer = MissionQuestionDetector.directSpokenAnswer(for: trimmed, userBrain: userBrain) {
            await deliverAssistantResponse(directAnswer, userText: trimmed)
            return
        }

        // Piper nur unter Speicherdruck entladen – sonst bleibt TTS zwischen Runden schneller.
        await releasePiperBeforeLLMIfNeeded()

        do {
            let responseStream = try await languageEngine.reply(
                to: trimmed,
                context: turns,
                options: LanguageReplyOptions(
                    characterPrompt: characterPrompt,
                    interactionStyle: interactionStyle,
                    internetEnabled: internetEnabled && !AppMemoryCoordinator.isUnderMemoryPressure,
                    userBrain: userBrain.promptContext()
                )
            )
            var responseText = ""
            var lastStreamUIUpdate = ContinuousClock.now

            for await chunk in responseStream {
                guard !Task.isCancelled else {
                    NSLog("[Voicefinder] Pipeline abgebrochen während LLM-Stream.")
                    await resumeSTTAfterAssistantOutput()
                    return
                }
                responseText += chunk

                // Rohtext auf Stottern prüfen – Stream früh abbrechen spart Latenz und RAM.
                if ResponseSanitizer.hasExcessiveWordStutter(responseText, maxRepeats: 4) {
                    NSLog("[Voicefinder] Wort-Stottern im Stream erkannt – Generierung abgebrochen.")
                    await MLXChatService.shared.cancelActiveGeneration()
                    break
                }

                // UI nicht bei jedem Token neu zeichnen – reduziert MainActor-Last und Re-Renders.
                let now = ContinuousClock.now
                if now - lastStreamUIUpdate >= .milliseconds(250) {
                    lastStreamUIUpdate = now
                    let preview = ResponseSanitizer.sanitizeForSpeech(responseText)
                    setState(.speaking(responseText: preview))
                }
            }

            NSLog("[Voicefinder] LLM-Stream vollständig empfangen (%d Zeichen).", responseText.count)

            guard !Task.isCancelled else {
                await resumeSTTAfterAssistantOutput()
                return
            }

            var finalResponse = ResponseSanitizer.finalizeAssistantResponse(
                raw: responseText,
                userMessage: trimmed,
                userBrain: userBrain
            )
            finalResponse = polishAssistantResponse(finalResponse, userText: trimmed)

            guard !finalResponse.isEmpty else {
                if !Task.isCancelled {
                    NSLog("[Voicefinder] Leere LLM-Antwort – kein Text für TTS.")
                    setState(.failed(message: "Keine Antwort vom Sprachmodell erhalten. Bitte erneut sprechen."))
                }
                await resumeSTTAfterAssistantOutput()
                return
            }

            await deliverAssistantResponse(finalResponse, userText: trimmed)
        } catch {
            if Task.isCancelled {
                await resumeSTTAfterAssistantOutput()
                return
            }
            if let piperError = error as? PiperTextToSpeechEngineError,
               case .cancelled = piperError {
                if !isListening {
                    partialText = ""
                    setState(.interrupted)
                }
                await resumeSTTAfterAssistantOutput()
                return
            }
            if let piperError = error as? PiperTextToSpeechEngineError,
               case .speakTimedOut = piperError {
                NSLog("[Voicefinder] TTS-Timeout – Gespräch läuft weiter.")
                partialText = ""
                setState(isListening ? .listening : .idle)
                await releasePiperAfterSpeechIfNeeded()
                await resumeSTTAfterAssistantOutput()
                return
            }
            recoverFromPipelineError(error)
        }
    }

    /// Speichert Assistenten-Antwort, spricht sie vor und setzt den Zustand zurück.
    private func deliverAssistantResponse(_ finalResponse: String, userText: String) async {
        let spokenText = ResponseSanitizer.deduplicatedForSpeech(finalResponse)
        if spokenText != finalResponse {
            NSLog("[Voicefinder] Doppelte Formulierung in Antwort entfernt.")
        }

        turns.append(ChatTurn(role: .assistant, text: spokenText))
        trimTurnsIfNeeded()
        notifyObservers()
        setState(.speaking(responseText: spokenText))

        await awaitPiperPreloadIfNeeded()
        NSLog("[Voicefinder] TTS startet (%d Zeichen) …", spokenText.count)
        do {
            try await speakResponseText(spokenText)
            await releasePiperAfterSpeechIfNeeded()
            AppMemoryCoordinator.markResourcesReleased()
            AppMemoryCoordinator.markDialogRoundCompleted()
            NSLog("[Voicefinder] TTS fertig.")
        } catch {
            if !Task.isCancelled {
                recoverFromPipelineError(error)
            }
            await resumeSTTAfterAssistantOutput()
            scheduleBrainEnrichment(from: userText)
            return
        }

        guard !Task.isCancelled else {
            await resumeSTTAfterAssistantOutput()
            return
        }

        partialText = ""
        setState(isListening ? .listening : .idle)
        await resumeSTTAfterAssistantOutput()
        scheduleBrainEnrichment(from: userText)
    }

    /// Erzeugt den Eröffnungstext – Auftrag, KI-Gehirn oder Standort-Kontext.
    private func generateConversationOpeningText() async -> String? {
        if !userBrain.resolvedMission.isEmpty {
            return await generateMissionBasedOpeningText()
        }
        return await generateCasualOpeningText()
    }

    /// Eröffnung aus dem hinterlegten Auftrag.
    private func generateMissionBasedOpeningText() async -> String? {
        let mission = userBrain.resolvedMission
        guard !mission.isEmpty else { return nil }
        guard !Task.isCancelled else { return nil }

        partialText = ""
        setState(.thinking(userText: "Eröffnung vorbereiten …"))
        NSLog("[Voicefinder] Auftrags-Eröffnung wird vorbereitet: %@", mission)

        let openingPrompt = CharacterProfileStore.missionOpeningUserMessage(mission: mission)

        await releasePiperBeforeLLMIfNeeded()

        do {
            let responseStream = try await languageEngine.reply(
                to: openingPrompt,
                context: [],
                options: LanguageReplyOptions(
                    characterPrompt: characterPrompt,
                    interactionStyle: interactionStyle,
                    internetEnabled: false,
                    isConversationOpening: true,
                    userBrain: userBrain.missionRolePromptContext()
                )
            )
            return await finalizeGeneratedOpening(from: responseStream)
        } catch {
            recoverFromPipelineError(error)
            return nil
        }
    }

    /// Lockere Eröffnung ohne Auftrag – nutzt KI-Gehirn und Gerätekontext.
    private func generateCasualOpeningText() async -> String? {
        guard !Task.isCancelled else { return nil }

        partialText = ""
        setState(.thinking(userText: "Eröffnung vorbereiten …"))
        NSLog("[Voicefinder] Gesprächseröffnung ohne Auftrag wird vorbereitet.")

        let openingPrompt = CharacterProfileStore.casualOpeningUserMessage(userBrain: userBrain)

        await releasePiperBeforeLLMIfNeeded()

        do {
            let responseStream = try await languageEngine.reply(
                to: openingPrompt,
                context: [],
                options: LanguageReplyOptions(
                    characterPrompt: characterPrompt,
                    interactionStyle: interactionStyle,
                    internetEnabled: false,
                    isConversationOpening: true,
                    userBrain: userBrain.promptContext()
                )
            )
            return await finalizeGeneratedOpening(from: responseStream)
        } catch {
            recoverFromPipelineError(error)
            return nil
        }
    }

    /// Bereinigt und validiert einen erzeugten Eröffnungstext.
    private func finalizeGeneratedOpening(from responseStream: AsyncStream<String>) async -> String? {
        var responseText = ""

        for await chunk in responseStream {
            guard !Task.isCancelled else { return nil }
            responseText += chunk
        }

        var sanitized = ResponseSanitizer.sanitizeForSpeech(responseText)
        if !ResponseSanitizer.isPredominantlyGerman(sanitized) {
            NSLog("[Voicefinder] Eröffnung nicht auf Deutsch – Ersatz-Eröffnung.")
            sanitized = userBrain.resolvedMission.isEmpty
                ? "Hallo! Wie geht es dir?"
                : "Hallo! Darf ich dich kurz etwas fragen?"
        }
        let recentAssistantTexts = turns
            .suffix(4)
            .filter { $0.role == .assistant }
            .map(\.text)
        if ResponseSanitizer.isRepeatingLoop(
            candidate: sanitized,
            recentAssistantTexts: recentAssistantTexts
        ) {
            NSLog("[Voicefinder] Eröffnungs-Schleife erkannt – Ersatz-Eröffnung.")
            sanitized = userBrain.resolvedMission.isEmpty
                ? "Hallo! Wie geht es dir?"
                : "Hallo! Darf ich dich kurz etwas fragen?"
        }
        guard !sanitized.isEmpty else {
            setState(isListening ? .listening : .idle)
            return nil
        }

        sanitized = ResponseSanitizer.ensureOpeningGreeting(
            sanitized,
            assistantName: userBrain.assistantName
        )
        sanitized = ResponseSanitizer.compactForOpening(
            ResponseSanitizer.deduplicatedForSpeech(sanitized)
        )
        NSLog("[Voicefinder] Eröffnung final (%d Zeichen).", sanitized.count)

        setState(isListening ? .listening : .idle)
        return sanitized
    }

    /// Qualitätsprüfung ohne zweite MLX-Runde – Schleifen-Erkennung und regelbasierte Fallbacks.
    private func polishAssistantResponse(
        _ text: String,
        userText: String
    ) -> String {
        if ResponseSanitizer.isUserFrustratedAboutRepetition(userText) {
            NSLog("[Voicefinder] Nutzer moniert Wiederholungen – Entschuldigung statt gleicher Frage.")
            return ResponseSanitizer.apologyForRepetition(userMessage: userText)
        }

        var polished = ResponseSanitizer.deduplicatedForSpeech(
            ResponseSanitizer.sanitizeForSpeech(text)
        )

        let userTurnCount = turns.filter { $0.role == .user }.count
        let recentAssistantTexts = turns
            .suffix(3)
            .filter { $0.role == .assistant }
            .map(\.text)

        polished = ResponseSanitizer.removingRepeatedFollowUp(
            from: polished,
            recentAssistantTexts: recentAssistantTexts
        )

        if ResponseSanitizer.isRepeatingLoop(
            candidate: polished,
            recentAssistantTexts: recentAssistantTexts,
            userTurnCount: userTurnCount
        ) {
            NSLog("[Voicefinder] Antwort fast identisch zur vorherigen – Formulierung anpassen.")
            // MLX-Text behalten, nur die wiederholte Folgefrage entfernen – kein generischer Fallback.
            let withoutQuestion = ResponseSanitizer.removingRepeatedFollowUp(
                from: polished,
                recentAssistantTexts: recentAssistantTexts
            )
            if withoutQuestion != polished, !withoutQuestion.isEmpty {
                return withoutQuestion
            }
            return "Alles klar, ich habe verstanden. Erzähl gern weiter."
        }

        if ResponseSanitizer.isWeakAcknowledgment(polished) {
            NSLog("[Voicefinder] Antwort nur Floskel – regelbasierter Fallback.")
            return ResponseSanitizer.engagedFallback(forUserMessage: userText, userBrain: userBrain)
        }
        if !ResponseSanitizer.isPredominantlyGerman(polished) {
            NSLog("[Voicefinder] Antwort überwiegend Englisch – regelbasierter Fallback.")
            return ResponseSanitizer.engagedFallback(forUserMessage: userText, userBrain: userBrain)
        }

        return polished
    }

    /// Spricht den vollständigen Text Satz für Satz vor – ohne Kürzung mitten im Satz.
    private func speakResponseText(_ text: String) async throws {
        SpeechDeliveryCoordinator.begin()
        defer { SpeechDeliveryCoordinator.end() }

        let sentences = ResponseSanitizer.deduplicateSentences(
            ResponseSanitizer.sentencesForSpeech(text)
        )
        guard !sentences.isEmpty else { return }

        for sentence in sentences {
            try Task.checkCancellation()
            try await textToSpeechEngine.speak(text: sentence)
        }
    }

    /// Spricht einen bereits erzeugten Eröffnungstext vor.
    private func speakConversationOpening(_ finalResponse: String) async {
        guard !Task.isCancelled else { return }

        conversationOpeningDelivered = true
        await suspendSTTForAssistantOutput()
        await textToSpeechEngine.stop()
        piperPreloadTask?.cancel()
        piperPreloadTask = nil

        turns.append(ChatTurn(role: .assistant, text: finalResponse))
        notifyObservers()
        setState(.speaking(responseText: finalResponse))

        do {
            await preparePiperForSpeechIfAllowed()
            try await speakResponseText(finalResponse)
            await releasePiperAfterSpeechIfNeeded()
            partialText = ""
            setState(isListening ? .listening : .idle)
        } catch {
            if !Task.isCancelled {
                recoverFromPipelineError(error)
            }
        }

        await resumeSTTAfterAssistantOutput()
    }

    /// Vor MLX Piper entladen – auf dem Gerät immer, damit MLX und ONNX nicht gleichzeitig im RAM liegen.
    private func releasePiperBeforeLLMIfNeeded() async {
        guard AppMemoryCoordinator.shouldUnloadPiperBeforeLLM else { return }
        guard let trimMemoryBeforeLLM else { return }
        await trimMemoryBeforeLLM()
    }

    /// Nach TTS Piper nur bei Speicherdruck entladen – sonst bleibt TTS für die nächste Runde schneller.
    private func releasePiperAfterSpeechIfNeeded() async {
        guard AppMemoryCoordinator.shouldUnloadPiperAfterTTS else { return }
        guard let releasePiperForLLM else { return }
        await releasePiperForLLM()
    }

    /// Wartet auf laufendes Piper-Preload oder startet es sequenziell nach LLM (nie parallel).
    private func awaitPiperPreloadIfNeeded() async {
        if let task = piperPreloadTask {
            await task.value
            piperPreloadTask = nil
            return
        }

        guard !AppMemoryCoordinator.shouldReduceMemoryUse else { return }

        // Kurze Pause nach MLX – gibt iOS Zeit, Zwischenpuffer freizugeben, bevor Piper lädt.
        try? await Task.sleep(for: .milliseconds(120))

        piperPreloadTask?.cancel()
        let task = Task {
            await self.preparePiperForSpeechIfAllowed()
        }
        piperPreloadTask = task
        await task.value
        piperPreloadTask = nil
    }

    /// Lädt Piper sequenziell nach LLM.
    private func preparePiperForSpeechIfAllowed() async {
        guard let preloadPiperForSpeech else { return }
        await preloadPiperForSpeech()
    }

    /// Verzögertes KI-Gehirn-LLM – erst nach TTS, nur wenn MLX idle und kein Speicherdruck.
    private func scheduleBrainEnrichment(from message: String) {
        guard !AppMemoryCoordinator.shouldSkipBrainEnrichmentLLM else {
            NSLog("[Voicefinder] KI-Gehirn LLM übersprungen (Speicherdruck).")
            return
        }

        brainEnrichmentTask?.cancel()
        brainEnrichmentTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await enrichAndApplyBrain(from: message)
        }
    }

    /// Bricht Hintergrund-Tasks ab, die nach Dialog-Ende oder Interrupt weiterlaufen würden.
    private func cancelBackgroundWork() {
        brainEnrichmentTask?.cancel()
        brainEnrichmentTask = nil
        piperPreloadTask?.cancel()
        piperPreloadTask = nil
    }

    /// Beendet alle STT-Stream-Consumer – verhindert mehrfach lauschende Tasks nach Neustart.
    private func cancelStreamConsumers() {
        partialListeningTask?.cancel()
        finalListeningTask?.cancel()
        levelListeningTask?.cancel()
        partialListeningTask = nil
        finalListeningTask = nil
        levelListeningTask = nil
    }

    /// Lädt Profil-Anreicherung und wendet sie auf dem Orchestrator an.
    private func enrichAndApplyBrain(from message: String) async {
        guard !AppMemoryCoordinator.shouldSkipBrainEnrichmentLLM else {
            NSLog("[Voicefinder] KI-Gehirn LLM übersprungen (Speicherdruck).")
            return
        }
        let enriched = await UserBrainStore.shared.enrichFromMessage(message)
        userBrain = enriched
        notifyBrainObservers()
    }

    /// Nach behebbaren Pipeline-Fehlern wieder zuhören statt dauerhaft rot zu bleiben.
    private func recoverFromPipelineError(_ error: Error) {
        NSLog("[Voicefinder] Pipeline-Fehler: \(error.localizedDescription)")
        partialText = ""
        if isListening {
            setState(.listening)
        } else {
            setState(.failed(message: error.localizedDescription))
        }
    }

    /// Begrenzt den Verlauf, damit MLX + Piper nicht mit wachsendem Kontext und RAM kollidieren.
    private func trimTurnsIfNeeded() {
        guard turns.count > Self.maxStoredTurns else { return }
        turns = Array(turns.suffix(Self.maxStoredTurns))
    }

    /// Pausiert STT, damit TTS nicht als Nutzereingabe transkribiert wird.
    private func suspendSTTForAssistantOutput() async {
        isSTTSuspended = true
        utteranceEndTask?.cancel()
        latestPartialUtterance = ""
        speechEnergyDetected = false

        if let pausable = speechToTextEngine as? PausableSpeechToTextEngine {
            await pausable.pauseStreaming()
        }
    }

    /// Setzt STT nach KI-Antwort mit leerem Erkennungspuffer fort.
    private func resumeSTTAfterAssistantOutput() async {
        guard isSTTSuspended else { return }
        isSTTSuspended = false
        latestPartialUtterance = ""
        speechEnergyDetected = false
        utteranceEndTask?.cancel()

        guard isListening else { return }
        guard !isMicrophoneMutedByUser else { return }

        if let pausable = speechToTextEngine as? PausableSpeechToTextEngine {
            do {
                try await pausable.resumeStreaming()
            } catch {
                recoverFromPipelineError(error)
            }
        }
    }

    /// Erkennt, ob transkribierter Text vermutlich die eigene TTS-Antwort ist.
    /// True, wenn der Nutzertext wahrscheinlich die eigene TTS-Ausgabe ist (Echo-Rückkopplung).
    private func isLikelyEchoOfAssistantSpeech(_ text: String) -> Bool {
        let recentAssistantTexts = turns
            .suffix(4)
            .filter { $0.role == .assistant }
            .map(\.text)
        guard !recentAssistantTexts.isEmpty else { return false }

        for assistantText in recentAssistantTexts.reversed() {
            if Self.textsAreSimilar(text, assistantText) { return true }
        }
        return false
    }

    /// Grober Textvergleich für Echo-Erkennung (TTS-Rückkopplung).
    private static func textsAreSimilar(_ a: String, _ b: String) -> Bool {
        let normalizedA = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedB = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedA.isEmpty, !normalizedB.isEmpty else { return false }

        if normalizedA == normalizedB { return true }
        if normalizedA.count >= 12, normalizedB.contains(normalizedA) { return true }
        if normalizedB.count >= 12, normalizedA.contains(normalizedB) { return true }

        let wordsA = Set(normalizedA.split(whereSeparator: { $0.isWhitespace }))
        let wordsB = Set(normalizedB.split(whereSeparator: { $0.isWhitespace }))
        guard wordsA.count >= 3, wordsB.count >= 3 else { return false }

        let overlap = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)
        return Double(overlap) / Double(minCount) >= 0.6
    }

    /// Bricht laufende Antwortgenerierung und TTS ab.
    private func interruptActivePipeline(keepListening: Bool) async {
        pipelineTask?.cancel()
        pipelineTask = nil
        cancelBackgroundWork()
        await MLXChatService.shared.cancelActiveGenerationAndWait()
        await textToSpeechEngine.stop()

        if isSTTSuspended {
            await resumeSTTAfterAssistantOutput()
        }

        if keepListening, isListening {
            setState(.listening)
        }
    }

    /// True, solange gedacht oder gesprochen wird.
    private var isPipelineActive: Bool {
        switch state {
        case .thinking, .speaking:
            true
        default:
            false
        }
    }

    private func setState(_ newState: ConversationState) {
        state = newState
        notifyObservers()
    }

    private func notifyObservers() {
        guard onUpdate != nil else { return }
        guard !uiNotifyScheduled else { return }

        uiNotifyScheduled = true
        Task {
            try? await Task.sleep(for: Self.uiNotifyCoalesceInterval)
            uiNotifyScheduled = false
            guard let onUpdate else { return }
            let currentState = state
            let currentTurns = turns
            let currentPartialText = partialText
            await MainActor.run {
                onUpdate(currentState, currentTurns, currentPartialText)
            }
        }
    }

    /// Informiert die UI über Änderungen am Nutzerprofil (KI-Gehirn).
    private func notifyBrainObservers() {
        guard let onBrainUpdate else { return }
        let profile = userBrain
        Task { @MainActor in
            onBrainUpdate(profile)
        }
    }
}
