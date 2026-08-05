//
//  VoiceSettingsView.swift
//  Voicefinder
//
//  Unterseite: Piper-Stimme und Sprechgeschwindigkeit.
//

import SwiftUI

/// Einstellungen für die deutsche Piper-Sprachausgabe.
struct VoiceSettingsView: View {
    @ObservedObject var viewModel: ConversationViewModel

    /// True, wenn alle vier ONNX-Stimmen im App-Bundle liegen.
    private var isBundleComplete: Bool {
        PiperModelProvider.isFullyBundled
    }

    var body: some View {
        Form {
            Section {
                if !isBundleComplete {
                    Label("Piper-Bundle unvollständig", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Fehlend: \(PiperModelProvider.missingEmbeddedVoices().joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker("Stimme", selection: $viewModel.piperVoice) {
                    ForEach(PiperModelProvider.embeddedVoices) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(!isBundleComplete)

                if let selected = PiperModelProvider.embeddedVoices.first(where: { $0 == viewModel.piperVoice }) {
                    Text(selected.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Deutsche Stimme")
            } footer: {
                Text("Vier Piper-Stimmen sind fest in der App eingebettet – vollständig offline, ohne Download.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Geschwindigkeit")
                        Spacer()
                        Text(String(format: "%.1f×", viewModel.piperSpeed))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $viewModel.piperSpeed, in: 0.5 ... 2.0, step: 0.1) {
                        Text("Sprechgeschwindigkeit")
                    }
                    .disabled(!isBundleComplete)

                    HStack {
                        Text("Langsam")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Normal")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Schnell")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Tempo")
            } footer: {
                Text("1,0× ist die Standardgeschwindigkeit des Modells. Höhere Werte sprechen schneller.")
            }

            Section {
                Button {
                    viewModel.previewPiperVoice()
                } label: {
                    Label("Stimme anhören", systemImage: "play.circle.fill")
                }
                .disabled(
                    !isBundleComplete
                        || viewModel.isPiperPreviewPlaying
                        || viewModel.isBusy
                )

                if viewModel.isPiperPreviewPlaying {
                    ProgressView("Spielt Vorschau …")
                }
            } header: {
                Text("Vorschau")
            }

            Section("Status") {
                LabeledContent("Engine", value: viewModel.piperStatusLabel)
                LabeledContent(
                    "Stimmen im Bundle",
                    value: isBundleComplete ? "4 / 4 eingebettet" : "\(PiperModelProvider.availableVoices().count) / 4"
                )
                LabeledContent(
                    "Ausgabe",
                    value: isBundleComplete ? "Piper (ONNX)" : "Bundle unvollständig"
                )
            }
        }
        .navigationTitle("Stimme")
    }
}
