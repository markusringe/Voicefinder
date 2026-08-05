//
//  ConversationViewModel.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Combine
import Foundation

/// UI-gebundenes ViewModel für den Conversation-Orchestrator.
@MainActor
final class ConversationViewModel: ObservableObject {
    @Published private(set) var state: ConversationState = .idle
    @Published private(set) var turns: [ChatTurn] = []
    @Published private(set) var partialText: String = ""
    @Published var draftText: String = ""

    /// Vom Nutzer definierter KI-Charakter (System-Prompt), persistent in UserDefaults.
    @Published var characterPrompt: String = CharacterProfileStore.load() {
        didSet {
            CharacterProfileStore.save(characterPrompt)
            Task {
                await orchestrator.setCharacterPrompt(characterPrompt)
            }
        }
    }

    /// Gewählter KI-Antwort-Stil (Normal, Forsch, Frech, Lustig, Schlau).
    @Published var aiInteractionStyle: AIInteractionStyle = AppSettingsStore.aiInteractionStyle {
        didSet {
            AppSettingsStore.aiInteractionStyle = aiInteractionStyle
            Task {
                await orchestrator.setInteractionStyle(aiInteractionStyle)
            }
        }
    }

    /// Internet-Recherche für faktische Fragen (Wikipedia, dann Google oder DuckDuckGo).
    @Published var internetEnabled: Bool = AppSettingsStore.internetEnabled {
        didSet {
            AppSettingsStore.internetEnabled = internetEnabled
            Task {
                await orchestrator.setInternetEnabled(internetEnabled)
            }
        }
    }

    /// Gewählte Suchmaschine nach Wikipedia.
    @Published var webSearchEngine: WebSearchEngine = AppSettingsStore.webSearchEngine {
        didSet {
            AppSettingsStore.webSearchEngine = webSearchEngine
        }
    }

    /// Google Custom Search API-Schlüssel.
    @Published var googleSearchAPIKey: String = AppSettingsStore.googleSearchAPIKey

    /// Google Programmable Search Engine ID (cx).
    @Published var googleSearchEngineID: String = AppSettingsStore.googleSearchEngineID

    /// True, wenn Google als primäre Suchquelle konfiguriert ist.
    var isGoogleSearchConfigured: Bool {
        !googleSearchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !googleSearchEngineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Gewählte Piper-Stimme für die Sprachausgabe.
    @Published var piperVoice: PiperVoice = AppSettingsStore.piperVoice {
        didSet {
            AppSettingsStore.piperVoice = piperVoice
            Task {
                await dependencies.applyVoiceSettings(voice: piperVoice, speed: Float(piperSpeed))
            }
        }
    }

    /// Sprechgeschwindigkeit der Piper-Stimme (0.5 … 2.0).
    @Published var piperSpeed: Double = Double(AppSettingsStore.piperSpeed) {
        didSet {
            let clamped = min(max(piperSpeed, 0.5), 2.0)
            if clamped != piperSpeed {
                piperSpeed = clamped
                return
            }
            AppSettingsStore.piperSpeed = Float(clamped)
            Task {
                await dependencies.applyVoiceSettings(voice: piperVoice, speed: Float(clamped))
            }
        }
    }

    /// Fest eingebettete Piper-Stimmen (immer alle vier – ONNX liegt im App-Bundle).
    @Published private(set) var availablePiperVoices: [PiperVoice] = PiperModelProvider.embeddedVoices

    /// True, wenn Piper geladen und einsatzbereit ist.
    @Published private(set) var isPiperReady = false

    /// True während einer Stimmen-Vorschau.
    @Published private(set) var isPiperPreviewPlaying = false

    /// Normalisierter Mikrofonpegel 0…1 für die Pegelanzeige.
    @Published private(set) var microphoneLevel: Float = 0
    /// True, sobald das Dauer-Mikrofon aktiv ist.
    @Published private(set) var isMicrophoneActive = false
    /// True, wenn der Nutzer das Mikrofon stummgeschaltet hat.
    @Published var isMicrophoneMuted = false

    /// Modelle wurden auf dem Startbildschirm bereits geladen.
    @Published private(set) var isWhisperReady = false
    @Published private(set) var isLLMReady = false
    @Published private(set) var llmModelName = ""

    /// Dauerhaft gespeichertes Nutzerprofil (KI-Gehirn).
    @Published var userBrainProfile: UserBrainProfile = UserBrainProfile()

    /// Einmaliger Dialog: Standort für Wohnort im KI-Gehirn.
    @Published var showLocationSetupAlert = false

    /// Vorbereitete Eröffnung (noch nicht gesprochen).
    @Published private(set) var preparedConversationOpening: String?
    @Published private(set) var isPreparingConversationOpening = false

    private let dependencies: AppDependencies
    private let orchestrator: ConversationOrchestrator
    /// Hält Init-/Setup-Task, damit er bei ViewModel-Ende abgebrochen werden kann.
    private var setupTask: Task<Void, Never>?

    init(
        dependencies: AppDependencies,
        preloaded: PreloadedModelFlags? = nil
    ) {
        self.dependencies = dependencies
        self.orchestrator = ConversationOrchestrator(dependencies: dependencies)

        if let preloaded {
            isWhisperReady = preloaded.whisperReady
            isPiperReady = preloaded.piperReady
            isLLMReady = preloaded.llmReady
            availablePiperVoices = PiperModelProvider.embeddedVoices
            llmModelName = preloaded.llmDisplayName
        }

        setupTask = Task { @MainActor in
            userBrainProfile = await UserBrainStore.shared.currentProfile()
            await orchestrator.setUserBrain(userBrainProfile)
            await orchestrator.setCharacterPrompt(characterPrompt)
            await orchestrator.setInteractionStyle(aiInteractionStyle)
            await orchestrator.setInternetEnabled(internetEnabled)
            await dependencies.applyVoiceSettings(voice: piperVoice, speed: Float(piperSpeed))
            await orchestrator.setOnUpdate { [weak self] state, turns, partialText in
                guard let self else { return }
                self.state = state
                self.turns = turns
                self.partialText = partialText
            }
            await orchestrator.setOnLevelUpdate { [weak self] level in
                self?.microphoneLevel = level
            }
            await orchestrator.setOnBrainUpdate { [weak self] profile in
                self?.userBrainProfile = profile
            }

            prepareLocationSetupIfNeeded()

            if preloaded != nil {
                await startContinuousListening()
            } else {
                await loadModelsForPreviewOrTests()
            }
        }
    }

    deinit {
        setupTask?.cancel()
        let orchestrator = orchestrator
        Task {
            await orchestrator.clearObservers()
            await orchestrator.endConversation()
        }
    }

    /// True, wenn gerade auf Spracheingabe gewartet oder transkribiert wird.
    var isListening: Bool {
        switch state {
        case .listening, .transcribing:
            true
        default:
            false
        }
    }

    /// True, wenn die Pipeline gerade arbeitet und nicht unterbrochen werden sollte.
    var isBusy: Bool {
        switch state {
        case .requestingPermissions, .thinking, .speaking:
            true
        default:
            false
        }
    }

    /// Sendet manuell eingegebenen Text in die Pipeline.
    func submitDraftText() {
        let text = draftText
        draftText = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await orchestrator.submitUserText(trimmed)
        }
    }

    /// Anzeige-Status für Piper in den Einstellungen.
    var piperStatusLabel: String {
        guard PiperModelProvider.isFullyBundled else { return "Nicht verfügbar" }
        if isPiperReady { return "Bereit" }
        #if targetEnvironment(simulator)
        return "Lädt …"
        #else
        return "Bereit"
        #endif
    }

    /// True, wenn die KI gerade antwortet oder nachdenkt.
    var isGeneratingResponse: Bool {
        switch state {
        case .thinking, .speaking:
            true
        default:
            false
        }
    }

    /// True, wenn das Gespräch noch nicht begonnen hat und die Eröffnung startbar ist.
    var canStartConversation: Bool {
        turns.isEmpty && !isPreparingConversationOpening
    }

    /// Kurzer Hinweis, worauf die KI bei der Eröffnung aufbauen kann.
    var conversationStartHint: String {
        if userBrainProfile.hasMission {
            return "Die KI beginnt aus deinem Auftrag – du kannst jederzeit normal weiterreden."
        }
        if userBrainProfile.hasUserProfileData {
            return "Die KI nutzt bekannte Infos aus dem KI-Gehirn für eine persönliche Eröffnung."
        }
        if !userBrainProfile.value(for: .city).isEmpty {
            return "Die KI kann deinen Wohnort und die aktuelle Uhrzeit einbeziehen."
        }
        return "Die KI begrüßt dich freundlich – Uhrzeit und Ort fließen mit ein, wenn bekannt."
    }

    /// Bricht laufende Sprachausgabe ab.
    func interruptSpeaking() {
        Task {
            await orchestrator.interruptSpeaking()
        }
    }

    /// Schaltet das Mikrofon stumm oder wieder frei.
    func toggleMicrophoneMute() {
        isMicrophoneMuted.toggle()
        Task {
            await orchestrator.setMicrophoneMuted(isMicrophoneMuted)
        }
    }

    /// Bereitet optional die Eröffnung im Hintergrund vor.
    func prepareConversationOpeningIfNeeded() {
        guard turns.isEmpty else { return }

        Task {
            isPreparingConversationOpening = true
            defer { isPreparingConversationOpening = false }
            preparedConversationOpening = await orchestrator.prepareConversationOpeningText()
        }
    }

    /// Startet das Gespräch per Knopfdruck – mit Auftrag, KI-Gehirn oder Standort-Kontext.
    func startConversation() {
        Task {
            if preparedConversationOpening == nil {
                isPreparingConversationOpening = true
                preparedConversationOpening = await orchestrator.prepareConversationOpeningText()
                isPreparingConversationOpening = false
            }
            await orchestrator.startPreparedConversationOpening()
            preparedConversationOpening = nil
        }
    }

    /// Beendet das Gespräch vollständig (Pipeline, Mikrofon, Verlauf).
    func endConversation() {
        Task {
            await orchestrator.endConversation()
            preparedConversationOpening = nil

            do {
                try await orchestrator.startListening()
                isMicrophoneActive = true
            } catch {
                isMicrophoneActive = false
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Speichert manuelle Änderungen am KI-Gehirn-Profil.
    func persistUserBrain() {
        Task {
            let saved = await UserBrainStore.shared.save(userBrainProfile)
            userBrainProfile = saved
            await orchestrator.setUserBrain(saved)
        }
    }

    /// Löscht nur Nutzer-Infos im KI-Gehirn – Name und Auftrag der KI bleiben unter KI-Eigenschaften.
    func clearUserBrainProfile() {
        Task {
            userBrainProfile = await UserBrainStore.shared.clearUserProfileOnly()
            await orchestrator.setUserBrain(userBrainProfile)
        }
    }

    /// Legt einen leeren, bearbeitbaren Profil-Punkt an.
    func addUserBrainEntry() {
        userBrainProfile.addEmptyEntry()
        persistUserBrain()
    }

    /// Entfernt einen dynamischen Profil-Punkt.
    func removeUserBrainEntry(id: UUID) {
        userBrainProfile.removeEntry(id: id)
        persistUserBrain()
    }

    /// Speichert Google-Such-Einstellungen (API-Schlüssel und cx).
    func persistGoogleSearchSettings() {
        AppSettingsStore.googleSearchAPIKey = googleSearchAPIKey
        AppSettingsStore.googleSearchEngineID = googleSearchEngineID
        AppSettingsStore.webSearchEngine = webSearchEngine
    }

    /// Standort erlauben und Stadt im KI-Gehirn speichern.
    func requestAndSaveLocation() async {
        do {
            let city = try await UserLocationService.shared.requestCityName()
            userBrainProfile.setValue(city, for: .city)
            persistUserBrain()
            AppSettingsStore.locationSetupCompleted = true
            showLocationSetupAlert = false
            NSLog("[Voicefinder] Wohnort im KI-Gehirn gespeichert: %@", city)
        } catch {
            NSLog("[Voicefinder] Standort fehlgeschlagen: %@", error.localizedDescription)
            AppSettingsStore.locationSetupCompleted = true
            showLocationSetupAlert = false
        }
    }

    /// Standort-Abfrage überspringen (Nutzer kann Wohnort manuell eintragen).
    func skipLocationSetup() {
        AppSettingsStore.locationSetupCompleted = true
        showLocationSetupAlert = false
    }

    /// Spielt einen kurzen Beispieltext mit der aktuellen Piper-Stimme ab.
    func previewPiperVoice() {
        guard PiperModelProvider.isFullyBundled else { return }

        Task {
            isPiperPreviewPlaying = true
            defer { isPiperPreviewPlaying = false }

            let sample = "Hallo, so klingt meine Stimme – ganz normal und menschlich."
            do {
                #if !targetEnvironment(simulator)
                await dependencies.trimMemoryBeforeVoiceOutput()
                #endif
                await dependencies.applyVoiceSettings(voice: piperVoice, speed: Float(piperSpeed))
                try await dependencies.textToSpeechEngine.speak(text: sample)
                #if !targetEnvironment(simulator)
                await dependencies.trimMemoryBeforeVoiceOutput()
                #endif
            } catch {
                NSLog("[Voicefinder] Piper-Vorschau fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Intern

    /// Zeigt einmalig den Standort-Dialog, wenn der Wohnort noch fehlt.
    private func prepareLocationSetupIfNeeded() {
        guard !AppSettingsStore.locationSetupCompleted else { return }
        guard userBrainProfile.value(for: .city).isEmpty else {
            AppSettingsStore.locationSetupCompleted = true
            return
        }
        showLocationSetupAlert = true
    }

    /// Startet das Mikrofon nach erfolgreichem Modell-Laden.
    private func startContinuousListening() async {
        guard isWhisperReady else { return }

        if LLMModelProvider.isSupported, !isLLMReady {
            state = .failed(message: "Lokales Sprachmodell konnte nicht geladen werden.")
            isMicrophoneActive = false
            return
        }

        do {
            try await orchestrator.startListening()
            isMicrophoneActive = true
            // Eröffnung erst beim Knopf „Gespräch starten“ – kein Hintergrund-LLM beim Zuhören.
        } catch {
            state = .failed(message: error.localizedDescription)
            isMicrophoneActive = false
        }
    }

    /// Fallback-Laden für SwiftUI-Previews und Tests ohne Startbildschirm.
    private func loadModelsForPreviewOrTests() async {
        if WhisperKitModelProvider.requiresWhisperWarmup {
            await dependencies.warmUpOfflineSpeechModels()
        }
        isWhisperReady = true

        await dependencies.warmUpPiperModels()
        isPiperReady = await dependencies.isPiperEngineReady
        if !PiperModelProvider.isFullyBundled {
            let missing = PiperModelProvider.missingEmbeddedVoices()
            NSLog("[Voicefinder] Piper-Bundle unvollständig – fehlend: %@", missing.joined(separator: ", "))
        }

        if LLMModelProvider.isSupported {
            isLLMReady = await MLXChatService.shared.isReady
            llmModelName = LLMModelProvider.displayName
        }

        await startContinuousListening()
    }
}
