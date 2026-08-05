//
//  CharacterSettingsView.swift
//  Voicefinder
//
//  Unterseite „KI-Eigenschaften“: Identität, Auftrag, Charakter und Antwort-Stil.
//

import SwiftUI

/// KI-Eigenschaften – wer die KI ist, was sie tun soll und wie sie antwortet.
struct CharacterSettingsView: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        Form {
            Section {
                brainFieldRow(
                    label: "Name der KI",
                    value: $viewModel.userBrainProfile.assistantName,
                    placeholder: "z. B. Johanna"
                )
                .onChange(of: viewModel.userBrainProfile.assistantName) { _, _ in
                    viewModel.persistUserBrain()
                }
            } header: {
                Text("Identität der KI")
            } footer: {
                Text("Verbindlich: So stellt sich die KI vor – wie ein Mensch, nicht wie ein technischer Assistent.")
            }

            Section {
                missionFieldRow
            } header: {
                Text("Auftrag")
            } footer: {
                Text("Verbindlich: Die Rolle und das Ziel des Gesprächs. Mit „Gespräch starten“ beginnt die KI aus diesem Auftrag.")
            }

            Section {
                TextEditor(text: $viewModel.characterPrompt)
                    .frame(minHeight: 120)
                    .disabled(viewModel.isBusy)
            } header: {
                Text("Charakter der KI")
            } footer: {
                Text("Verbindlich: Persönlichkeit, Tonfall und Verhaltensregeln der KI – getrennt vom Nutzerprofil im KI-Gehirn.")
            }

            Section {
                Picker("Antwort-Stil", selection: $viewModel.aiInteractionStyle) {
                    ForEach(AIInteractionStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.systemImage)
                            .tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(viewModel.isBusy)

                if let selected = AIInteractionStyle.allCases.first(where: { $0 == viewModel.aiInteractionStyle }) {
                    Label(selected.subtitle, systemImage: selected.systemImage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Antwort-Stil")
            } footer: {
                Text("Der Stil beeinflusst Ton und Art der Antworten ab der nächsten KI-Antwort – z. B. freundlich-normal, forsch-direkt oder lustig-humorvoll.")
            }

            Section {
                Button("Standard-Charakter wiederherstellen") {
                    viewModel.characterPrompt = CharacterProfileStore.restoreDefaultPrompt()
                }
                .disabled(viewModel.isBusy || CharacterProfileStore.usesDefaultPrompt(viewModel.characterPrompt))

                Button("Antwort-Stil auf Normal") {
                    viewModel.aiInteractionStyle = .normal
                }
                .disabled(viewModel.isBusy || viewModel.aiInteractionStyle == .normal)
            } header: {
                Text("Zurücksetzen")
            } footer: {
                Text("Der Standard-Charakter ist für natürlichen Smalltalk mit Qwen optimiert – kurze Sätze, eine Frage pro Antwort.")
            }
        }
        .navigationTitle("KI-Eigenschaften")
        .onDisappear {
            viewModel.persistUserBrain()
        }
    }

    /// Mehrzeiliges Feld für den Gesprächsauftrag.
    private var missionFieldRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auftrag")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(
                "Eintrag",
                text: $viewModel.userBrainProfile.mission,
                prompt: Text("z. B. Du bist eine Freundin, die höflich nachfragt, ob heute ein Treffen passt."),
                axis: .vertical
            )
            .lineLimit(3...6)
            .disabled(viewModel.isBusy)
        }
        .onChange(of: viewModel.userBrainProfile.mission) { _, _ in
            viewModel.persistUserBrain()
        }
    }

    /// Zeile mit fester Bezeichnung und editierbarem Eintrag.
    @ViewBuilder
    private func brainFieldRow(label: String, value: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Eintrag", text: value, prompt: Text(placeholder))
                .disabled(viewModel.isBusy)
        }
    }
}
