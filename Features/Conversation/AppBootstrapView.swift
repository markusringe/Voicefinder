//
//  AppBootstrapView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import SwiftUI
import UIKit

/// Zeigt den Startbildschirm mit Modell-Ladefortschritt, danach die Haupt-UI.
struct AppBootstrapView: View {
    @StateObject private var startupViewModel = StartupViewModel()

    var body: some View {
        Group {
            if startupViewModel.isComplete, let dependencies = startupViewModel.dependencies {
                MainTabView(
                    viewModel: ConversationViewModel(
                        dependencies: dependencies,
                        preloaded: startupViewModel.preloadedFlags
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification
                    )
                ) { _ in
                    AppMemoryCoordinator.handleMemoryWarning()
                    Task {
                        await dependencies.releaseMemoryUnderPressure()
                    }
                }
            } else if let error = startupViewModel.errorMessage {
                bootstrapErrorView(error)
            } else {
                StartupView(viewModel: startupViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: startupViewModel.isComplete)
        .task {
            await startupViewModel.startLoading()
        }
    }

    private func bootstrapErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Start fehlgeschlagen")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    AppBootstrapView()
}
