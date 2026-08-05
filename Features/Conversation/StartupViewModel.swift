//
//  StartupViewModel.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import Combine
import Foundation

/// Steuert das sequenzielle Laden aller On-Device-Modelle beim App-Start.
@MainActor
final class StartupViewModel: ObservableObject {
    @Published private(set) var steps: [ModelLoadStep] = []
    @Published private(set) var overallProgress: Double = 0
    @Published private(set) var isComplete = false
    @Published private(set) var errorMessage: String?

    /// DI-Container – nach erfolgreichem Start an die Haupt-UI übergeben.
    private(set) var dependencies: AppDependencies?
    private(set) var preloadedFlags = PreloadedModelFlags(
        whisperReady: false,
        piperReady: false,
        llmReady: false,
        llmDisplayName: ""
    )

    private var progressAnimationTasks: [ModelLoadStepID: Task<Void, Never>] = [:]

    /// Startet alle Ladeschritte nacheinander und aktualisiert Fortschrittsbalken.
    func startLoading() async {
        guard dependencies == nil, !isComplete else { return }

        let deps = AppDependencies.live()
        dependencies = deps
        steps = Self.buildSteps()
        errorMessage = nil
        overallProgress = 0

        var whisperReady = !WhisperKitModelProvider.requiresStartupWarmup
        var piperReady = false
        var llmReady = !LLMModelProvider.isSupported

        for (index, step) in steps.enumerated() {
            if case .skipped = step.status {
                overallProgress = Double(index + 1) / Double(steps.count)
                continue
            }

            setStepStatus(step.id, .loading)
            startProgressAnimation(for: step.id)

            do {
                switch step.id {
                case .liveSpeech:
                    try await Task.sleep(for: .milliseconds(350))

                case .whisperKit:
                    try await deps.warmUpOfflineSpeechModelsThrowing()
                    whisperReady = true

                case .piperTTS:
                    #if targetEnvironment(simulator)
                    do {
                        try await deps.warmUpPiperModelsIfNeeded()
                        piperReady = true
                    } catch {
                        piperReady = false
                        NSLog(
                            "[Voicefinder] Piper-Warmup fehlgeschlagen: %@",
                            error.localizedDescription
                        )
                    }
                    #else
                    // Auf Gerät: ONNX wird bei Bedarf geladen – eingebettete Stimmen gelten als verfügbar.
                    piperReady = PiperModelProvider.isFullyBundled
                    if piperReady {
                        NSLog("[Voicefinder] Piper eingebettet – lädt bei der ersten Sprachausgabe.")
                    }
                    #endif

                case .languageModel:
                    try await EmbeddedLLMBootstrap.activateEmbeddedModel()
                    llmReady = true
                }
            } catch {
                stopProgressAnimation(for: step.id)
                setStepStatus(step.id, .failed(error.localizedDescription))
                errorMessage = error.localizedDescription
                return
            }

            stopProgressAnimation(for: step.id)
            setStepProgress(step.id, 1)
            setStepStatus(step.id, .completed)
            overallProgress = Double(index + 1) / Double(steps.count)
        }

        preloadedFlags = PreloadedModelFlags(
            whisperReady: whisperReady,
            piperReady: piperReady,
            llmReady: llmReady,
            llmDisplayName: LLMModelProvider.isSupported ? LLMModelProvider.displayName : ""
        )
        isComplete = true
    }

    // MARK: - Schritt-Liste

    private static func buildSteps() -> [ModelLoadStep] {
        var result: [ModelLoadStep] = []

        let liveSubtitle: String
        if AppDependencies.usesWhisperKitRecordingFallback {
            liveSubtitle = "WhisperKit Live-Aufnahme (Simulator)"
        } else if AppDependencies.usesSimulatorSpeechFallback {
            liveSubtitle = "Apple Speech (Simulator)"
        } else {
            liveSubtitle = "Apple Speech – On-Device"
        }

        result.append(
            ModelLoadStep(
                id: .liveSpeech,
                title: "Spracherkennung",
                subtitle: liveSubtitle,
                systemImage: "mic.fill"
            )
        )

        if LLMModelProvider.isSupported {
            result.append(
                ModelLoadStep(
                    id: .languageModel,
                    title: "Sprachmodell",
                    subtitle: LLMModelProvider.displayName,
                    systemImage: "brain"
                )
            )
        }

        if WhisperKitModelProvider.requiresStartupWarmup {
            result.append(
                ModelLoadStep(
                    id: .whisperKit,
                    title: "WhisperKit",
                    subtitle: WhisperKitModelProvider.activeModelName,
                    systemImage: "waveform"
                )
            )
        }

        if PiperModelProvider.requiresWarmup {
            result.append(
                ModelLoadStep(
                    id: .piperTTS,
                    title: "Piper TTS",
                    subtitle: "4 deutsche Stimmen – ONNX",
                    systemImage: "speaker.wave.2.fill"
                )
            )
        } else if !PiperModelProvider.isFullyBundled, PiperModelProvider.isSupported {
            result.append(
                ModelLoadStep(
                    id: .piperTTS,
                    title: "Piper TTS",
                    subtitle: "Eingebettete Stimmen unvollständig",
                    systemImage: "speaker.slash.fill",
                    status: .skipped,
                    progress: 0
                )
            )
        }

        return result
    }

    // MARK: - UI-Hilfen

    private func setStepStatus(_ id: ModelLoadStepID, _ status: ModelLoadStepStatus) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].status = status
    }

    private func setStepProgress(_ id: ModelLoadStepID, _ progress: Double) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].progress = min(max(progress, 0), 1)
    }

    private func startProgressAnimation(for id: ModelLoadStepID) {
        progressAnimationTasks[id]?.cancel()
        progressAnimationTasks[id] = Task {
            var value = 0.04
            while !Task.isCancelled, value < 0.9 {
                setStepProgress(id, value)
                try? await Task.sleep(for: .milliseconds(180))
                value += 0.04
            }
        }
    }

    private func stopProgressAnimation(for id: ModelLoadStepID) {
        progressAnimationTasks[id]?.cancel()
        progressAnimationTasks[id] = nil
    }
}
