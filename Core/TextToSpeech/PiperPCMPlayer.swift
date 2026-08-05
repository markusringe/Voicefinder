//
//  PiperPCMPlayer.swift
//  Voicefinder
//
//  Wiedergabe von Piper/Sherpa-ONNX-PCM über AVAudioEngine.
//

@preconcurrency import AVFoundation
import Foundation

/// Spielt mono-Float-PCM (Sherpa-ONNX-Ausgabe) ab – unterstützt schnelles Stoppen.
actor PiperPCMPlayer {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackGeneration: UInt64 = 0
    private var activeBufferContinuation: CheckedContinuation<Void, Error>?
    private var activeBufferGeneration: UInt64 = 0

    /// Spielt Samples mit der angegebenen Abtastrate ab und wartet bis zum Ende.
    func play(samples: [Float], sampleRate: Int) async throws {
        guard !samples.isEmpty else { return }

        playbackGeneration &+= 1
        let generation = playbackGeneration

        try await AudioSessionCoordinator.shared.activatePlayback()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )
        guard let format else {
            throw PiperTextToSpeechEngineError.playbackFailed
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()

        audioEngine = engine
        playerNode = player

        defer {
            if generation == playbackGeneration {
                cleanupPlayback(generation: generation)
                Task { await AudioSessionCoordinator.shared.releaseForHandoff() }
            }
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw PiperTextToSpeechEngineError.playbackFailed
        }

        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { source in
            guard let destination = buffer.floatChannelData?[0], let base = source.baseAddress else { return }
            destination.update(from: base, count: samples.count)
        }

        try await scheduleAndAwait(buffer: buffer, on: player, generation: generation)

        if Task.isCancelled || generation != playbackGeneration {
            throw PiperTextToSpeechEngineError.cancelled
        }
    }

    /// Stoppt die Wiedergabe sofort.
    func stop() {
        playbackGeneration &+= 1
        resumeActiveBuffer(with: PiperTextToSpeechEngineError.cancelled)
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
    }

    // MARK: - Intern

    private func scheduleAndAwait(
        buffer: AVAudioPCMBuffer,
        on player: AVAudioPlayerNode,
        generation: UInt64
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activeBufferContinuation = continuation
            activeBufferGeneration = generation

            player.scheduleBuffer(buffer) { [weak self] in
                Task { await self?.bufferDidFinish(generation: generation) }
            }
        }
    }

    private func bufferDidFinish(generation: UInt64) {
        guard generation == activeBufferGeneration else { return }
        resumeActiveBuffer(with: nil)
    }

    private func resumeActiveBuffer(with error: Error?) {
        guard let continuation = activeBufferContinuation else { return }
        activeBufferContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func cleanupPlayback(generation: UInt64) {
        guard generation == playbackGeneration else { return }
        resumeActiveBuffer(with: PiperTextToSpeechEngineError.cancelled)
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
    }
}
