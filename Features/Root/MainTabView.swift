//
//  MainTabView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import SwiftUI

/// Hauptnavigation mit Unterseiten: Gespräch, KI-Charakter, Einstellungen.
struct MainTabView: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        TabView {
            NavigationStack {
                ConversationView(viewModel: viewModel)
            }
            .tabItem {
                Label("Gespräch", systemImage: "waveform.circle.fill")
            }

            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Einstellungen", systemImage: "gearshape.fill")
            }
        }
        .alert("Standort für lokale Infos", isPresented: $viewModel.showLocationSetupAlert) {
            Button("Standort erlauben") {
                Task { await viewModel.requestAndSaveLocation() }
            }
            Button("Später", role: .cancel) {
                viewModel.skipLocationSetup()
            }
        } message: {
            Text(
                "Damit ich Wetter und Ortsinfos nennen kann, speichere ich deinen Wohnort einmalig im KI-Gehirn. Du kannst ihn später unter Einstellungen → KI-Gehirn ändern."
            )
        }
    }
}
