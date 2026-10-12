//
//  PiperPCMPlayer.swift
//  Voicefinder
//
//  Wiedergabe von Piper/Sherpa-ONNX-PCM über AVAudioEngine.
//

@preconcurrency import AVFoundation
import Foundation

/// Spielt mono-Float-PCM (Sherpa-ONNX-Ausgabe) ab – Engine wird wiederverwendet (Speicher).
actor PiperPCMPlayer {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var activeFormat: AVAudioFormat?
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

        let (engine, player) = try ensurePlaybackEngine(format: format)

        defer {
            if generation == playbackGeneration {
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

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        try await scheduleAndAwait(buffer: buffer, on: player, generation: generation)

        if Task.isCancelled || generation != playbackGeneration {
            throw PiperTextToSpeechEngineError.cancelled
        }
    }

    /// Stoppt die Wiedergabe sofort und gibt die Audio-Engine frei.
    func stop() {
        playbackGeneration &+= 1
        resumeActiveBuffer(with: PiperTextToSpeechEngineError.cancelled)
        teardownEngine()
    }

    // MARK: - Intern

    /// Stellt eine wiederverwendete Engine bereit – vermeidet pro Satz eine neue AVAudioEngine.
    private func ensurePlaybackEngine(format: AVAudioFormat) throws -> (AVAudioEngine, AVAudioPlayerNode) {
        if let audioEngine,
           let playerNode,
           let activeFormat,
           activeFormat.sampleRate == format.sampleRate,
           activeFormat.channelCount == format.channelCount {
            return (audioEngine, playerNode)
        }

        teardownEngine()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()

        audioEngine = engine
        playerNode = player
        activeFormat = format
        return (engine, player)
    }

    private func teardownEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        if let playerNode, let audioEngine {
            audioEngine.detach(playerNode)
        }
        playerNode = nil
        audioEngine = nil
        activeFormat = nil
    }

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
}
