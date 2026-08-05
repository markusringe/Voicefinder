//
//  ConversationView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 03.08.26.
//

import SwiftUI

/// Hauptansicht für die Sprachkonversation.
struct ConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel

    @State private var showTextInput = false

    var body: some View {
        chatScroll
            .safeAreaInset(edge: .bottom) {
                bottomPanel
            }
            .navigationTitle("Gespräch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    statusChip
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        CharacterSettingsView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "person.text.rectangle")
                    }
                    .accessibilityLabel("KI-Eigenschaften")

                    NavigationLink {
                        AIBrainSettingsView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "brain.head.profile")
                    }
                    .accessibilityLabel("KI-Gehirn")

                    if viewModel.isGeneratingResponse {
                        Button {
                            viewModel.interruptSpeaking()
                        } label: {
                            Image(systemName: "speaker.slash.fill")
                        }
                        .accessibilityLabel("Antwort stoppen")
                    }

                    if !viewModel.turns.isEmpty || viewModel.isMicrophoneActive {
                        Button(role: .destructive) {
                            viewModel.endConversation()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .accessibilityLabel("Gespräch beenden")
                    }
                }
            }
    }

    // MARK: - Chat

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if AppDependencies.usesSimulatorSpeechFallback {
                        simulatorHint
                    }

                    if viewModel.turns.isEmpty {
                        conversationStartCard
                    }

                    ForEach(viewModel.turns) { turn in
                        ChatBubble(
                            turn: turn,
                            assistantDisplayName: viewModel.userBrainProfile.assistantName
                        )
                        .id(turn.id)
                    }

                    if !viewModel.partialText.isEmpty, viewModel.isListening {
                        partialBubble
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.turns.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.partialText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    // MARK: - Untere Leiste

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MicrophoneLevelView(
                    level: viewModel.isMicrophoneMuted ? 0 : viewModel.microphoneLevel,
                    isActive: viewModel.isMicrophoneActive && !viewModel.isMicrophoneMuted
                )

                Button {
                    viewModel.toggleMicrophoneMute()
                } label: {
                    Image(systemName: viewModel.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.isMicrophoneMuted ? .orange : .secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(viewModel.isMicrophoneMuted ? "Mikrofon einschalten" : "Mikrofon stummschalten")
                .disabled(viewModel.isBusy || !viewModel.isMicrophoneActive)
            }
            .frame(height: 56)

            if showTextInput {
                HStack(spacing: 8) {
                    TextField("Nachricht …", text: $viewModel.draftText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isBusy)

                    Button("Senden") {
                        viewModel.submitDraftText()
                    }
                    .disabled(
                        viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isBusy
                    )
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTextInput = true
                    }
                } label: {
                    Label("Tastatur", systemImage: "keyboard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(viewModel.isBusy)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Hilfs-Views

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusLabel)
    }

    /// Startkarte – KI eröffnet auf Knopfdruck (mit Auftrag, KI-Gehirn oder Standort).
    private var conversationStartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.conversationStartHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.isPreparingConversationOpening {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Eröffnung wird vorbereitet …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let preview = viewModel.preparedConversationOpening, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                viewModel.startConversation()
            } label: {
                Label("Gespräch starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy || viewModel.isPreparingConversationOpening)

            Text("Oder sprich einfach los – das Mikrofon hört schon zu.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var partialBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(viewModel.partialText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var simulatorHint: some View {
        Text(simulatorHintText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var simulatorHintText: String {
        if AppDependencies.usesWhisperKitRecordingFallback {
            return "Simulator: Transkription nach Sprechpause. Auf dem iPhone läuft Live-STT."
        }
        return "Intel-Simulator: Für beste Qualität echtes iPhone nutzen."
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = viewModel.turns.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var statusLabel: String {
        if viewModel.isMicrophoneMuted, viewModel.isMicrophoneActive {
            return "Stummgeschaltet"
        }
        switch viewModel.state {
        case .idle: return "Bereit"
        case .requestingPermissions: return "Berechtigung …"
        case .listening: return "Zuhören"
        case .transcribing: return "Erkennen …"
        case .thinking: return "Denkt …"
        case .speaking: return "Spricht …"
        case .interrupted: return "Pause"
        case .failed: return "Fehler"
        }
    }

    private var statusColor: Color {
        if viewModel.isMicrophoneMuted, viewModel.isMicrophoneActive {
            return .orange
        }
        switch viewModel.state {
        case .failed: return .red
        case .interrupted: return .orange
        case .speaking, .thinking: return .blue
        case .listening, .transcribing: return .green
        default: return .secondary
        }
    }
}

// MARK: - Mikrofon (kompakt)

private struct MicrophoneLevelView: View {
    let level: Float
    let isActive: Bool

    private let barCount = 8

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "mic.fill" : "mic.slash")
                .font(.body)
                .foregroundStyle(isActive && level > 0.08 ? .green : .secondary)
                .frame(width: 24)

            HStack(spacing: 3) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .frame(width: 4, height: barHeight(for: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Mikrofon")
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index + 1) / Float(barCount)
        guard level >= threshold * 0.85 else { return 4 }
        return 4 + CGFloat(level) * 24
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / Float(barCount)
        return level >= threshold * 0.85 ? .green : Color(.systemGray4)
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let turn: ChatTurn
    let assistantDisplayName: String

    var body: some View {
        HStack {
            if turn.role == .assistant { Spacer(minLength: 48) }

            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
                Text(roleLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(turn.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            if turn.role == .user { Spacer(minLength: 48) }
        }
    }

    private var roleLabel: String {
        switch turn.role {
        case .user:
            return "Du"
        case .assistant:
            let name = assistantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Gesprächspartner" : name
        case .system:
            return "System"
        }
    }

    private var bubbleColor: Color {
        switch turn.role {
        case .user:
            return Color.accentColor.opacity(0.14)
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color.orange.opacity(0.12)
        }
    }
}
