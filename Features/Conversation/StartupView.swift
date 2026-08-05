//
//  StartupView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import SwiftUI

/// Startbildschirm: lädt nacheinander alle On-Device-Modelle mit Fortschrittsanzeige.
struct StartupView: View {
    @ObservedObject var viewModel: StartupViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                overallProgressSection
                stepList
                Spacer(minLength: 0)
                footerHint
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
    }

    // MARK: - Kopfbereich

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating, isActive: !viewModel.isComplete)

            Text("Voicefinder")
                .font(.largeTitle.bold())

            Text("Lokale KI wird vorbereitet …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Gesamtfortschritt über alle Schritte.
    private var overallProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gesamtfortschritt")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(viewModel.overallProgress * 100)) %")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: viewModel.overallProgress)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Liste aller Modell-Schritte mit individuellem Fortschrittsbalken.
    private var stepList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.steps) { step in
                ModelLoadStepRow(step: step)
            }
        }
    }

    private var footerHint: some View {
        Text("Alle Modelle laufen vollständig auf dem Gerät – ohne Cloud.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Zeile pro Modell

/// Einzelner Eintrag mit Icon, Text und Fortschrittsbalken.
private struct ModelLoadStepRow: View {
    let step: ModelLoadStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: step.systemImage)
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                    Text(step.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                statusTrailing
            }

            if showsProgressBar {
                ProgressView(value: step.progress)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(statusColor.opacity(isLoadingStep ? 0.35 : 0), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: step.status)
        .animation(.easeInOut(duration: 0.2), value: step.progress)
    }

    private var isLoadingStep: Bool {
        if case .loading = step.status { return true }
        return false
    }

    @ViewBuilder
    private var statusTrailing: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)

        case .loading:
            ProgressView()
                .controlSize(.small)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .failed(_):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var showsProgressBar: Bool {
        switch step.status {
        case .loading, .completed:
            true
        case .pending, .failed(_), .skipped:
            false
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .pending:
            .secondary
        case .loading:
            .accentColor
        case .completed:
            .green
        case .failed(_):
            .orange
        case .skipped:
            .secondary
        }
    }
}

#Preview {
    StartupView(viewModel: StartupViewModel())
}
