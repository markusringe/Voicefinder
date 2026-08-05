//
//  MLXChatService.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import MLXLLM
import MLXLMCommon

/// Aktiviert das fest im App-Bundle eingebettete MLX-Modell (einmaliger Speicher-Mapping-Schritt).
actor MLXChatService {
    /// Gemeinsame Instanz für Bootstrap und `LocalLLMEngine`.
    static let shared = MLXChatService()

    private var modelContainer: ModelContainer?
    private var isActivating = false
    private(set) var isReady = false
    private(set) var lastActivationError: String?
    /// Pfad zum eingebetteten Modell im Bundle.
    private(set) var embeddedModelPath: String?
    /// Laufende Token-Generierung – wird bei Pipeline-Abbruch gecancelt.
    private var generationTask: Task<Void, Never>?
    /// Verhindert parallele MLX-Inferenz (Hauptantwort + KI-Gehirn).
    private var isGenerating = false

    /// True, solange eine Dialog- oder Hintergrund-Inferenz läuft (für Speicher-Entlastung).
    var isGenerationInProgress: Bool {
        isGenerating
    }

    /// Parameter für Dialog-Antworten – vollständige Sätze (~20–50 Wörter).
    private static let voiceAssistantParameters = GenerateParameters(
        maxTokens: 140,
        temperature: 0.58,
        topP: 0.90,
        repetitionPenalty: 1.10
    )

    /// Gesprächseröffnung – Begrüßung plus eine Frage.
    private static let openingParameters = GenerateParameters(
        maxTokens: 72,
        temperature: 0.5,
        topP: 0.9,
        repetitionPenalty: 1.1
    )

    /// Zweite Runde – Fortsetzung bei abgebrochenem Satz.
    private static let voiceCompletionParameters = GenerateParameters(
        maxTokens: 56,
        temperature: 0.4,
        topP: 0.88,
        repetitionPenalty: 1.12
    )

    /// Qwen3: Thinking-Modus abschalten – sonst englische Reasoning-Texte statt Dialog.
    private static let qwenChatContext: [String: any Sendable] = ["enable_thinking": false]

    private init() {}

    /// Erzeugt eine ChatSession mit Qwen3-kompatiblem Kontext (Thinking aus).
    private static func makeChatSession(
        modelContainer: ModelContainer,
        instructions: String,
        history: [Chat.Message] = [],
        generateParameters: GenerateParameters
    ) -> ChatSession {
        ChatSession(
            modelContainer,
            instructions: instructions,
            history: history,
            generateParameters: generateParameters,
            additionalContext: qwenChatContext
        )
    }

    /// Wartet, bis keine MLX-Generierung mehr läuft.
    private func waitForGenerationIdle() async {
        while isGenerating {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Markiert Beginn/Ende einer MLX-Inferenz (nur eine gleichzeitig).
    private func withGenerationLock<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await waitForGenerationIdle()
        isGenerating = true
        defer { isGenerating = false }
        return try await operation()
    }

    /// Bricht laufende MLX-Generierung ab (z. B. bei Nutzer-Unterbrechung).
    func cancelActiveGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    /// Bricht MLX ab und wartet, bis keine Inferenz mehr läuft (vor Piper-Laden).
    func cancelActiveGenerationAndWait() async {
        cancelActiveGeneration()
        await waitForGenerationIdle()
    }

    /// Mappt das eingebettete Modell aus dem App-Bundle in den Arbeitsspeicher (kein Netzwerk).
    func activateEmbeddedModel(at modelURL: URL) async throws {
        if isReady { return }

        if isActivating {
            let deadline = ContinuousClock.now + .seconds(300)
            while isActivating {
                if ContinuousClock.now > deadline {
                    throw LLMModelProviderError.modelNotActivated
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !isReady {
                throw LLMModelProviderError.modelNotActivated
            }
            return
        }

        isActivating = true
        defer { isActivating = false }

        do {
            try LLMModelProvider.validateModelDirectory(modelURL)
            let configuration = ModelConfiguration(directory: modelURL)
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            isReady = true
            lastActivationError = nil
            embeddedModelPath = modelURL.path
            NSLog(
                "[Voicefinder] Eingebettetes LLM aktiv: %@ (%@)",
                LLMModelProvider.displayName,
                modelURL.path
            )
        } catch {
            isReady = false
            lastActivationError = error.localizedDescription
            throw error
        }
    }

    /// Kompatibilitäts-Alias – leitet auf eingebettetes Modell um.
    func prepareIfNeeded() async throws {
        try await activateEmbeddedModel(at: LLMModelProvider.requiredEmbeddedModelURL())
    }

    /// Erste Mini-Inferenz nach dem Laden – kompiliert Metal-Shader, bevor der Nutzer spricht.
    func warmUpInferenceIfNeeded() async {
        guard isReady, let modelContainer else { return }

        NSLog("[Voicefinder] MLX-Warmup: erste Inferenz …")
        let session = Self.makeChatSession(
            modelContainer: modelContainer,
            instructions: "Antworte kurz auf Deutsch.",
            generateParameters: GenerateParameters(maxTokens: 8, temperature: 0.1)
        )

        do {
            var tokenCount = 0
            for try await _ in session.streamResponse(to: "Hallo") {
                tokenCount += 1
                if tokenCount >= 2 { break }
            }
            NSLog("[Voicefinder] MLX-Warmup abgeschlossen.")
        } catch {
            NSLog("[Voicefinder] MLX-Warmup fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Streamt eine **deutsche** LLM-Antwort tokenweise – UI und TTS sehen Fortschritt sofort.
    func streamReply(
        userMessage: String,
        context: [ChatTurn],
        characterPrompt: String,
        interactionStyle: AIInteractionStyle,
        userBrain: UserBrainPromptContext,
        isConversationOpening: Bool = false
    ) async throws -> AsyncStream<String> {
        guard let modelContainer else {
            throw LocalLLMEngineError.modelNotActivated
        }

        let trimmedPrompt = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalLLMEngineError.notImplemented
        }

        var systemPrompt = CharacterProfileStore.resolvedSystemPrompt(
            customCharacter: characterPrompt,
            style: interactionStyle,
            userBrain: userBrain
        )
        if isConversationOpening {
            systemPrompt += "\n\n" + CharacterProfileStore.openingBrevityDirective
        }

        let generateParameters = isConversationOpening
            ? Self.openingParameters
            : Self.voiceAssistantParameters
        let conversationHistory = Self.conversationHistory(from: context, userMessage: trimmedPrompt)
        let userPrompt = CharacterProfileStore.germanFramedUserMessage(
            trimmedPrompt,
            userFirstName: userBrain.resolvedUserFirstName
        )

        generationTask?.cancel()
        await waitForGenerationIdle()
        isGenerating = true

        let pair = AsyncStream<String>.makeStream()
        // Nur bei Abbruch durch den Consumer canceln – nicht bei normalem finish(), sonst kollidiert das mit der nächsten Runde.
        pair.continuation.onTermination = { @Sendable reason in
            if case .cancelled = reason {
                Task { await MLXChatService.shared.cancelActiveGeneration() }
            }
        }
        generationTask = Task {
            defer {
                isGenerating = false
                pair.continuation.finish()
                generationTask = nil
            }
            await self.streamVoiceResponse(
                modelContainer: modelContainer,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt,
                generateParameters: generateParameters,
                continuation: pair.continuation
            )
        }

        return pair.stream
    }

    /// Führt eine einzelne MLX-Generierung aus und leitet Tokens sofort weiter.
    private func streamVoiceResponse(
        modelContainer: ModelContainer,
        systemPrompt: String,
        conversationHistory: [Chat.Message],
        userPrompt: String,
        generateParameters: GenerateParameters,
        continuation: AsyncStream<String>.Continuation
    ) async {
        NSLog("[Voicefinder] MLX-Generierung startet …")

        let session = Self.makeChatSession(
            modelContainer: modelContainer,
            instructions: systemPrompt,
            history: conversationHistory,
            generateParameters: generateParameters
        )

        var combined = ""
        var lastYieldedLength = 0
        var receivedFirstToken = false

        do {
            for try await chunk in session.streamResponse(to: userPrompt) {
                if Task.isCancelled { break }

                combined += chunk
                let speakable = ResponseSanitizer.stripThinkingBlocks(combined)
                guard speakable.count > lastYieldedLength else { continue }

                let delta = String(speakable.dropFirst(lastYieldedLength))
                lastYieldedLength = speakable.count

                if !receivedFirstToken, !delta.isEmpty {
                    receivedFirstToken = true
                    NSLog("[Voicefinder] MLX erstes Token empfangen.")
                }

                continuation.yield(delta)
            }
        } catch {
            NSLog("[Voicefinder] MLX-Generierung Fehler: \(error.localizedDescription)")
        }

        let trimmed = ResponseSanitizer.sanitizeForSpeech(combined)
        if trimmed.isEmpty {
            NSLog("[Voicefinder] MLX lieferte keinen Text – versuche Korrektur-Prompt.")
            await self.streamCorrectionIfNeeded(
                modelContainer: modelContainer,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userMessage: userPrompt,
                continuation: continuation
            )
        } else {
            NSLog("[Voicefinder] MLX-Antwort fertig (%d Zeichen).", trimmed.count)
        }
    }

    /// Ein Korrekturversuch, falls die erste Generierung leer blieb.
    private func streamCorrectionIfNeeded(
        modelContainer: ModelContainer,
        systemPrompt: String,
        conversationHistory: [Chat.Message],
        userMessage: String,
        continuation: AsyncStream<String>.Continuation
    ) async {
        guard !Task.isCancelled else { return }

        var history = conversationHistory
        history.append(.user(userMessage))

        let session = Self.makeChatSession(
            modelContainer: modelContainer,
            instructions: systemPrompt + "\n\nAntworte JETZT in vollständigen deutschen Sätzen.",
            history: history,
            generateParameters: Self.voiceAssistantParameters
        )

        do {
            for try await chunk in session.streamResponse(to: "Bitte antworte auf Deutsch.") {
                if Task.isCancelled { break }
                continuation.yield(chunk)
            }
        } catch {
            NSLog("[Voicefinder] MLX-Korrektur Fehler: \(error.localizedDescription)")
        }
    }

    /// Kurze, nicht gestreamte Antwort – z. B. für KI-Gehirn-Fakt-Extraktion.
    func generateCompactReply(prompt: String) async -> String? {
        guard isReady, let modelContainer else { return nil }
        guard !AppMemoryCoordinator.isUnderMemoryPressure else { return nil }

        return await withGenerationLock {
            let session = Self.makeChatSession(
                modelContainer: modelContainer,
                instructions: "Du bist ein präziser Daten-Extraktor. Antworte exakt wie gefordert.",
                generateParameters: GenerateParameters(maxTokens: 64, temperature: 0.1, topP: 0.9)
            )

            var combined = ""
            do {
                for try await chunk in session.streamResponse(to: prompt) {
                    if Task.isCancelled { return nil }
                    combined += chunk
                }
            } catch {
                NSLog("[Voicefinder] KI-Gehirn LLM-Extraktion Fehler: \(error.localizedDescription)")
                return nil
            }

            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Zweite LLM-Runde: setzt eine abgebrochene Antwort fort und schließt Sätze ab.
    func generateContinuation(
        partialAnswer: String,
        userMessage: String,
        context: [ChatTurn],
        characterPrompt: String,
        interactionStyle: AIInteractionStyle,
        userBrain: UserBrainPromptContext
    ) async -> String {
        guard isReady, let modelContainer else { return "" }
        guard !AppMemoryCoordinator.isUnderMemoryPressure else { return "" }

        let trimmedPartial = partialAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPartial.isEmpty, !trimmedUser.isEmpty else { return "" }
        guard ResponseSanitizer.needsContinuation(trimmedPartial) else { return "" }

        return await withGenerationLock {
            let systemPrompt = CharacterProfileStore.resolvedSystemPrompt(
                customCharacter: characterPrompt,
                style: interactionStyle,
                userBrain: userBrain
            ) + """

            FORTSETZUNG (verbindlich): Deine vorherige Antwort endete mitten im Satz. \
            Gib NUR die Fortsetzung auf Deutsch – ohne den bisherigen Text zu wiederholen. \
            Schließe alle offenen Sätze natürlich ab. Kein Markdown, kein Meta-Text.
            """

            var history = Self.conversationHistory(from: context, userMessage: trimmedUser)
            history.append(.assistant(trimmedPartial))

            let continuationPrompt = """
            Setze deine Antwort nahtlos fort und beende alle Sätze.
            Nutzerfrage war: \(trimmedUser)
            """

            let session = Self.makeChatSession(
                modelContainer: modelContainer,
                instructions: systemPrompt,
                history: history,
                generateParameters: Self.voiceCompletionParameters
            )

            var combined = ""
            do {
                for try await chunk in session.streamResponse(to: continuationPrompt) {
                    if Task.isCancelled { return "" }
                    combined += chunk
                }
            } catch {
                NSLog("[Voicefinder] MLX-Fortsetzung Fehler: \(error.localizedDescription)")
                return ""
            }

            let sanitized = ResponseSanitizer.sanitizeForSpeech(combined)
            guard ResponseSanitizer.isPredominantlyGerman(sanitized) else {
                NSLog("[Voicefinder] Fortsetzung nicht auf Deutsch – verworfen.")
                return ""
            }
            return sanitized
        }
    }

    /// Nachgenerierung bei zu knapper oder leerer Antwort – mit Bezug zum Nutzer und Folgefrage.
    func generateEngagedRetry(
        userMessage: String,
        context: [ChatTurn],
        characterPrompt: String,
        interactionStyle: AIInteractionStyle,
        userBrain: UserBrainPromptContext
    ) async -> String {
        guard isReady, let modelContainer else { return "" }
        guard !AppMemoryCoordinator.isUnderMemoryPressure else { return "" }

        let trimmedUser = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else { return "" }

        return await withGenerationLock {
            let systemPrompt = CharacterProfileStore.resolvedSystemPrompt(
                customCharacter: characterPrompt,
                style: interactionStyle,
                userBrain: userBrain
            ) + """

            KORREKTUR (verbindlich): Deine letzte Antwort war zu kurz oder wirkte wie eine leere Bestätigung.
            Antworte jetzt auf Deutsch in genau 2 natürlichen Sätzen.
            Gehe konkret auf das Gesagte des Nutzers ein und stelle genau EINE offene Folgefrage.
            Kein „Alles klar“, kein „Verstanden“, kein „Okay“ allein.
            """

            let history = Self.conversationHistory(from: context, userMessage: trimmedUser)
            let retryPrompt = """
            Nutzer sagte: \(trimmedUser)
            Deine neue, engagierte Antwort auf Deutsch:
            """

            let session = Self.makeChatSession(
                modelContainer: modelContainer,
                instructions: systemPrompt,
                history: history,
                generateParameters: GenerateParameters(
                    maxTokens: 100,
                    temperature: 0.45,
                    topP: 0.88,
                    repetitionPenalty: 1.15
                )
            )

            var combined = ""
            do {
                for try await chunk in session.streamResponse(to: retryPrompt) {
                    if Task.isCancelled { return "" }
                    combined += chunk
                }
            } catch {
                NSLog("[Voicefinder] MLX-Nachgenerierung Fehler: \(error.localizedDescription)")
                return ""
            }

            let sanitized = ResponseSanitizer.sanitizeForSpeech(combined)
            guard ResponseSanitizer.isPredominantlyGerman(sanitized) else { return "" }
            guard !ResponseSanitizer.isWeakAcknowledgment(sanitized) else { return "" }
            return sanitized
        }
    }

    // MARK: - Hilfsfunktionen
    private static func conversationHistory(
        from turns: [ChatTurn],
        userMessage: String
    ) -> [Chat.Message] {
        var messages = chatMessages(from: turns)
        if let last = messages.last, last.role == .user, last.content == userMessage {
            messages = Array(messages.dropLast())
        }
        return messages
    }

    /// Wandelt App-Gesprächsrunden in MLX-Chat-Nachrichten um (nur letzte Runden – weniger RAM/TTFT).
    private static func chatMessages(from turns: [ChatTurn]) -> [Chat.Message] {
        turns.suffix(6).map { turn in
            switch turn.role {
            case .user:
                .user(turn.text)
            case .assistant:
                .assistant(turn.text)
            case .system:
                .system(turn.text)
            }
        }
    }
}
