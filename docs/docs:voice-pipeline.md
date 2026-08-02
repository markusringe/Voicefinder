# Voice Pipeline

The app captures microphone audio with AVAudioEngine.
STT produces partial and final transcripts.
The orchestrator forwards final user text to the language engine.
The language engine emits short reply chunks.
The TTS engine speaks chunks and must support interruption.