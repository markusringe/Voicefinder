//
//  MLXChatService.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Foundation
import MLX
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
    /// KV-Cache des letzten Dialog-Prompts – die nächste Runde prefillt nur den abweichenden Rest.
    private let promptCacheStore = PromptCacheStore()

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

    /// Obergrenze für den MLX-Puffer-Cache – ohne Limit wächst er über Runden und löst iOS-Speicherwarnungen aus,
    /// besonders wenn Piper für frühes Sprechen parallel geladen bleibt.
    private static let gpuCacheLimitBytes = 128 * 1024 * 1024

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

    /// Nur für Gerätetests: geladenes Modell.
    var modelContainerForTesting: ModelContainer? {
        modelContainer
    }

    /// Gibt den Prompt-Cache frei (z. B. bei iOS-Speicherwarnung). Wartet auf eine laufende Generierung.
    func dropPromptCache() async {
        guard let modelContainer else { return }
        let store = promptCacheStore
        await modelContainer.perform { _ in
            store.reset()
        }
        NSLog("[Voicefinder] MLX-Prompt-Cache freigegeben.")
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
            Memory.cacheLimit = Self.gpuCacheLimitBytes
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

        let messages: [Chat.Message] = [.system(systemPrompt)] + conversationHistory + [.user(userPrompt)]
        let accumulator = StreamAccumulator(continuation: continuation)

        do {
            try await Self.generateWithPromptCache(
                modelContainer: modelContainer,
                store: promptCacheStore,
                messages: messages,
                generateParameters: generateParameters,
                retainCache: AppMemoryCoordinator.allowsPromptCacheRetention
                    && !AppSettingsStore.isPromptCacheDisabledForDebugging
            ) { chunk in
                accumulator.append(chunk)
            }
        } catch {
            NSLog("[Voicefinder] MLX-Generierung Fehler: \(error.localizedDescription)")
        }
        let combined = accumulator.combined

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

    // MARK: - Prompt-Cache

    /// Generiert mit wiederverwendetem KV-Cache: Gemeinsamer Token-Präfix mit dem letzten Prompt
    /// (System-Prompt, älterer Verlauf) wird nicht erneut prefillt.
    ///
    /// Läuft komplett in `modelContainer.perform` – der Container serialisiert den Zugriff,
    /// daher wird `store` nie parallel benutzt.
    nonisolated static func generateWithPromptCache(
        modelContainer: ModelContainer,
        store: PromptCacheStore,
        messages: [Chat.Message],
        generateParameters: GenerateParameters,
        retainCache: Bool,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        try await modelContainer.perform(nonSendable: messages) { context, messages in
            let userInput = UserInput(chat: messages, additionalContext: qwenChatContext)
            let fullInput = try await context.processor.prepare(input: userInput)
            let promptTokens = fullInput.text.tokens.asArray(Int.self)
            guard !promptTokens.isEmpty else { return }

            let prefillStart = CFAbsoluteTimeGetCurrent()
            let (cache, reusedCount) = reusablePromptCache(
                store: store,
                promptTokens: promptTokens,
                model: context.model,
                parameters: generateParameters
            )
            // Bis zum Ende unklarer Zustand – bei Fehler/Abbruch nicht wiederverwenden.
            store.reset()

            let suffix = Array(promptTokens[reusedCount...])
            let iterator = try TokenIterator(
                input: LMInput(tokens: MLXArray(suffix)),
                model: context.model,
                cache: cache,
                parameters: generateParameters
            )
            NSLog(
                "[Voicefinder] MLX-Prefill: %d Prompt-Tokens, %d aus Cache, %d neu (%.2f s)",
                promptTokens.count,
                reusedCount,
                suffix.count,
                CFAbsoluteTimeGetCurrent() - prefillStart
            )

            let (stream, task) = generateTask(
                promptTokenCount: suffix.count,
                modelConfiguration: context.configuration,
                tokenizer: context.tokenizer,
                iterator: iterator
            )
            for await item in stream {
                if Task.isCancelled { break }
                if case .chunk(let text) = item {
                    onChunk(text)
                }
            }
            // Generierung muss stehen, bevor der Cache zurückgetrimmt wird.
            task.cancel()
            await task.value

            // Prefill ist nach `TokenIterator.init` abgeschlossen – Zurücktrimmen ist auch nach Abbruch gültig.
            guard retainCache else { return }
            // Nur den Prompt behalten – generierte Tokens weichen vom bereinigten Verlaufstext ab.
            let keptCount = min(cache.first?.offset ?? 0, promptTokens.count)
            for layer in cache {
                layer.trim(layer.offset - keptCount)
            }
            store.cache = cache
            store.tokens = Array(promptTokens.prefix(keptCount))
        }
    }

    /// Liefert einen auf den gemeinsamen Präfix getrimmten Cache oder einen neuen.
    nonisolated private static func reusablePromptCache(
        store: PromptCacheStore,
        promptTokens: [Int],
        model: any LanguageModel,
        parameters: GenerateParameters
    ) -> (cache: [KVCache], reusedCount: Int) {
        guard let existing = store.cache, !existing.isEmpty, canTrimPromptCache(existing) else {
            return (model.newCache(parameters: parameters), 0)
        }

        // Mindestens ein Token muss neu verarbeitet werden, sonst gibt es keine Logits.
        let reusable = min(commonPrefixLength(store.tokens, promptTokens), promptTokens.count - 1)
        guard reusable > 0 else {
            return (model.newCache(parameters: parameters), 0)
        }

        // `trimPromptCache` trimmt nur die erste Schicht – daher jede Schicht einzeln.
        for layer in existing {
            layer.trim(layer.offset - reusable)
        }
        return (existing, reusable)
    }

    nonisolated static func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
        var length = 0
        let limit = min(a.count, b.count)
        while length < limit, a[length] == b[length] {
            length += 1
        }
        return length
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

/// KV-Cache plus zugehörige Prompt-Tokens. Nur innerhalb von `ModelContainer.perform` benutzen –
/// der Container serialisiert alle Zugriffe.
nonisolated final class PromptCacheStore: @unchecked Sendable {
    var cache: [KVCache]?
    var tokens: [Int] = []

    func reset() {
        cache = nil
        tokens = []
    }
}

/// Sammelt gestreamte MLX-Chunks und gibt nur sprechbaren Text (ohne Thinking-Blöcke) weiter.
nonisolated private final class StreamAccumulator: @unchecked Sendable {
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var buffer = ""
    private var lastYieldedLength = 0
    private var receivedFirstToken = false

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    var combined: String {
        lock.withLock { buffer }
    }

    func append(_ chunk: String) {
        let delta: String? = lock.withLock {
            buffer += chunk
            let speakable = ResponseSanitizer.stripThinkingBlocks(buffer)
            guard speakable.count > lastYieldedLength else { return nil }
            let delta = String(speakable.dropFirst(lastYieldedLength))
            lastYieldedLength = speakable.count
            return delta
        }
        guard let delta, !delta.isEmpty else { return }

        if !receivedFirstToken {
            receivedFirstToken = true
            NSLog("[Voicefinder] MLX erstes Token empfangen.")
        }
        continuation.yield(delta)
    }
}
