//
//  OpenSourceLicensesView.swift
//  Voicefinder
//
//  Übersicht der eingesetzten Open-Source-Modelle und Bibliotheken mit Lizenzen.
//

import SwiftUI

/// Ein Open-Source-Bestandteil mit Projekt- und Lizenzlinks.
private struct OpenSourceComponent: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let licenseName: String
    let projectURL: String
    let licenseURL: String
}

/// Seite mit allen relevanten Open-Source-Komponenten der Voice-Pipeline.
struct OpenSourceLicensesView: View {
    /// Feste Liste der in Voicefinder eingesetzten OSS-Modelle und Frameworks.
    private let components: [OpenSourceComponent] = [
        OpenSourceComponent(
            name: "Qwen3-1.7B",
            role: "Lokales Sprachmodell (MLX, 4-Bit quantisiert)",
            licenseName: "Apache License 2.0",
            projectURL: "https://huggingface.co/Qwen/Qwen3-1.7B",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0"
        ),
        OpenSourceComponent(
            name: "MLX / MLX Swift",
            role: "On-Device-Inferenz auf Apple Silicon",
            licenseName: "MIT License",
            projectURL: "https://github.com/ml-explore/mlx-swift",
            licenseURL: "https://github.com/ml-explore/mlx-swift/blob/main/LICENSE"
        ),
        OpenSourceComponent(
            name: "Whisper / WhisperKit",
            role: "Offline-Spracherkennung (Simulator-Fallback)",
            licenseName: "MIT License",
            projectURL: "https://github.com/argmaxinc/WhisperKit",
            licenseURL: "https://github.com/openai/whisper/blob/main/LICENSE"
        ),
        OpenSourceComponent(
            name: "Piper TTS",
            role: "Deutsche ONNX-Stimmen für Sprachausgabe",
            licenseName: "MIT License",
            projectURL: "https://github.com/rhasspy/piper",
            licenseURL: "https://github.com/rhasspy/piper/blob/master/LICENSE.md"
        ),
        OpenSourceComponent(
            name: "Sherpa-ONNX",
            role: "Offline-TTS-Runtime für Piper-Modelle",
            licenseName: "Apache License 2.0",
            projectURL: "https://github.com/k2-fsa/sherpa-onnx",
            licenseURL: "https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE"
        ),
        OpenSourceComponent(
            name: "eSpeak NG",
            role: "Phonetisierung für Piper (espeak-ng-data im Bundle)",
            licenseName: "GNU GPLv3",
            projectURL: "https://github.com/espeak-ng/espeak-ng",
            licenseURL: "https://github.com/espeak-ng/espeak-ng/blob/master/COPYING"
        ),
    ]

    var body: some View {
        List {
            Section {
                Text(
                    "Voicefinder nutzt ausschließlich lokale Modelle auf dem Gerät. "
                        + "Apple Speech für Live-STT auf dem iPhone ist eine Systemkomponente von Apple."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Modelle & Bibliotheken") {
                ForEach(components) { component in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(component.name)
                            .font(.headline)
                        Text(component.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Lizenz: \(component.licenseName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            if let projectLink = URL(string: component.projectURL) {
                                Link("Projekt", destination: projectLink)
                                    .font(.caption)
                            }
                            if let licenseLink = URL(string: component.licenseURL) {
                                Link("Lizenztext", destination: licenseLink)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Hinweis") {
                Text(
                    "Die genannten Lizenzen gelten für die eingebetteten Modelle und Bibliotheken. "
                        + "Vollständige Lizenztexte findest du in den verlinkten Repositories."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Open Source")
    }
}
