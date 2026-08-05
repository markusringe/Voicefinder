//
//  WebSearchSettingsView.swift
//  Voicefinder
//
//  Konfiguration der Internet-Recherche: Wikipedia zuerst, dann Google oder DuckDuckGo.
//

import SwiftUI

/// Einstellungen für die Internet-Recherche.
struct WebSearchSettingsView: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        Form {
            Section {
                Picker("Suchmaschine", selection: $viewModel.webSearchEngine) {
                    ForEach(WebSearchEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .disabled(viewModel.isBusy)

                Text(viewModel.webSearchEngine.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reihenfolge")
            } footer: {
                Text("Zuerst wird immer Wikipedia durchsucht. Danach kommt die gewählte Suchmaschine zum Einsatz.")
            }

            if viewModel.webSearchEngine == .google {
                Section {
                    SecureField("API-Schlüssel", text: $viewModel.googleSearchAPIKey, prompt: Text("AIza…"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(viewModel.isBusy)

                    TextField("Suchmaschinen-ID (cx)", text: $viewModel.googleSearchEngineID, prompt: Text("abc123…"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(viewModel.isBusy)
                } header: {
                    Text("Google Custom Search")
                } footer: {
                    Text(
                        """
                        Google Cloud Console → Custom Search API aktivieren → \
                        Programmable Search Engine anlegen („Gesamtes Web durchsuchen“) → \
                        API-Schlüssel und cx eintragen. Kostenlos ca. 100 Anfragen/Tag. \
                        Ohne Schlüssel wird DuckDuckGo genutzt.
                        """
                    )
                }
            }

            Section("Status") {
                LabeledContent("Stufe 1", value: "Wikipedia")
                LabeledContent("Stufe 2", value: viewModel.webSearchEngine.displayName)
                if viewModel.webSearchEngine == .google {
                    LabeledContent(
                        "Google",
                        value: viewModel.isGoogleSearchConfigured ? "Konfiguriert" : "Nicht konfiguriert"
                    )
                }
            }
        }
        .navigationTitle("Internet-Recherche")
        .onDisappear {
            viewModel.persistGoogleSearchSettings()
        }
    }
}
