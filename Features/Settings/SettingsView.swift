//
//  SettingsView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import SwiftUI

/// Unterseite: App-Einstellungen (Internet, Modell-Hinweise).
struct SettingsView: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Internet-Recherche", isOn: $viewModel.internetEnabled)

                NavigationLink {
                    WebSearchSettingsView(viewModel: viewModel)
                } label: {
                    Label("Suchquellen", systemImage: "globe")
                }
            } header: {
                Text("Wissen")
            } footer: {
                Text("Standardmäßig antwortet die KI aus KI-Gehirn und lokalem Modell. Internet-Recherche nur bei explizitem Bedarf (z. B. Wetter, Nachrichten) – leere Treffer werden ignoriert.")
            }

            Section("On-Device-Modelle") {
                LabeledContent("Sprachmodell", value: viewModel.llmModelName.isEmpty ? "—" : viewModel.llmModelName)
                LabeledContent("Whisper", value: viewModel.isWhisperReady ? "Bereit" : "—")
                LabeledContent("Piper TTS", value: viewModel.piperStatusLabel)
            }

            Section("Sprachausgabe") {
                NavigationLink {
                    VoiceSettingsView(viewModel: viewModel)
                } label: {
                    Label("Stimme & Geschwindigkeit", systemImage: "waveform.circle")
                }
            }

            Section("KI") {
                NavigationLink {
                    CharacterSettingsView(viewModel: viewModel)
                } label: {
                    Label("KI-Eigenschaften", systemImage: "person.text.rectangle")
                }

                NavigationLink {
                    AIBrainSettingsView(viewModel: viewModel)
                } label: {
                    Label("KI-Gehirn", systemImage: "brain.head.profile")
                }

                LabeledContent("Antwort-Stil", value: viewModel.aiInteractionStyle.displayName)
                LabeledContent(
                    "Profil",
                    value: viewModel.userBrainProfile.hasAnyData
                        ? "\(viewModel.userBrainProfile.filledStandardFieldCount)+\(viewModel.userBrainProfile.filledEntryCount) Punkte"
                        : "Leer"
                )
            }

            Section("Rechtliches") {
                NavigationLink {
                    OpenSourceLicensesView()
                } label: {
                    Label("Open Source & Lizenzen", systemImage: "doc.text")
                }
            }

            Section("Datenschutz") {
                Text("Spracheingabe, LLM und TTS laufen auf dem Gerät. Internet wird nur selten und optional für gezielte Recherche genutzt – nicht für Cloud-KI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Einstellungen")
    }
}
