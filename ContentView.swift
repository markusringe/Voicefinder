//
//  ContentView.swift
//  Voicefinder
//
//  Created by Markus Ringe on 02.08.26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.blue)

                Text("Voicefinder")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Lokaler Sprachassistent in Vorbereitung")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Label("STT wird vorbereitet", systemImage: "mic.fill")
                    Label("Lokale Antwortlogik folgt", systemImage: "brain")
                    Label("TTS-Ausgabe folgt", systemImage: "speaker.wave.2.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer()
            }
            .padding()
            .navigationTitle("Start")
        }
    }
}

#Preview {
    ContentView()
}
