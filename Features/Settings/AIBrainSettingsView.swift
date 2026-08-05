//
//  AIBrainSettingsView.swift
//  Voicefinder
//
//  Unterseite „KI-Gehirn“: dauerhaftes Nutzerprofil – wer der Nutzer ist.
//

import SwiftUI

/// Zeigt und bearbeitet das dauerhafte Nutzerprofil der KI (nur nutzerbezogene Daten).
struct AIBrainSettingsView: View {
    @ObservedObject var viewModel: ConversationViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(UserBrainField.allCases) { field in
                    brainFieldRow(
                        label: field.displayName,
                        value: binding(for: field),
                        placeholder: field.placeholder
                    )
                    .onChange(of: viewModel.userBrainProfile.value(for: field)) { _, _ in
                        viewModel.persistUserBrain()
                    }
                }
            } header: {
                Text("Profilfelder")
            } footer: {
                Text("Jedes Feld hat eine feste Bezeichnung und einen Eintrag (Wert). Leere Felder füllt die KI nebenbei aus dem Gespräch.")
            }

            Section {
                if viewModel.userBrainProfile.entries.isEmpty {
                    Text("Noch keine zusätzlichen Punkte – die KI legt sie an, wenn du Interessantes erzählst.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($viewModel.userBrainProfile.entries) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bezeichnung")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Bezeichnung", text: $entry.label, prompt: Text("z. B. Beruf"))
                                .disabled(viewModel.isBusy)

                            Text("Eintrag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Eintrag", text: $entry.value, prompt: Text("Wert"))
                                .disabled(viewModel.isBusy)

                            if entry.discoveredByAI {
                                Label("Von der KI entdeckt", systemImage: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.removeUserBrainEntry(id: entry.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    viewModel.addUserBrainEntry()
                } label: {
                    Label("Punkt hinzufügen", systemImage: "plus.circle")
                }
                .disabled(viewModel.isBusy)
            } header: {
                Text("Weitere Infos")
            } footer: {
                Text("Eigene Bezeichnung und Eintrag – von dir oder von der KI angelegt.")
            }

            Section("Fortschritt") {
                LabeledContent(
                    "Profilfelder",
                    value: "\(viewModel.userBrainProfile.filledStandardFieldCount) von \(UserBrainField.allCases.count)"
                )
                LabeledContent(
                    "Weitere Punkte",
                    value: "\(viewModel.userBrainProfile.filledEntryCount)"
                )
                if viewModel.userBrainProfile.hasUserProfileData {
                    Text("Zuletzt aktualisiert: \(viewModel.userBrainProfile.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Profil speichern") {
                    viewModel.persistUserBrain()
                }
                .disabled(viewModel.isBusy)

                Button("Alles löschen", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(viewModel.isBusy || !viewModel.userBrainProfile.hasUserProfileData)
            }
        }
        .navigationTitle("KI-Gehirn")
        .onDisappear {
            viewModel.persistUserBrain()
        }
        .confirmationDialog(
            "KI-Gehirn wirklich löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) {
                viewModel.clearUserBrainProfile()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle gespeicherten Nutzer-Infos und Einträge werden unwiderruflich entfernt. Name und Auftrag der KI bleiben unter KI-Eigenschaften erhalten.")
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

    /// Zwei-Wege-Binding auf ein Standardfeld.
    private func binding(for field: UserBrainField) -> Binding<String> {
        Binding(
            get: { viewModel.userBrainProfile.value(for: field) },
            set: { newValue in
                viewModel.userBrainProfile.setValue(newValue, for: field)
            }
        )
    }
}
