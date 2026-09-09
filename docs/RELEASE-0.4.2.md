# Hlas 0.4.2

## Changes

- Two output modes: Transcript and automatic Smart text. Smart text chooses formatting from meaning, preserving prose for messages and narratives while structuring real lists and procedures. No style picker.
- Automatic paste works with editors that do not expose an Accessibility input element. The previous clipboard is restored, including rich formats. Switching applications during processing keeps the result available for recovery.
- Serial microphone lifecycle outside the main thread, adaptive cooldown, throttled waveform updates and session snapshots.
- Cooperative cancellation of local Whisper inference, local model prefetch during speech and memory-pressure unloading.
- Original/edited history, reprocessing, exact text replacements, optional history retention and background persistence.
- Audio file import and recording limits of 10 minutes; fewer WAV encoding allocations.

## Privacy and compatibility

Apple Silicon, macOS 15 or later. Existing settings, keys and history are preserved. Smart text uses the configured OpenAI or Groq key and sends transcript text to that provider, including when speech recognition is Local. Transcript mode skips the editing request. No screenshots or surrounding editor text are sent.

This release uses the same Apple Development signing identity as prior releases. It is not notarized. First-time installations may require approval in System Settings > Privacy & Security. Quit the existing app before replacing it in Applications.

## Verification

- Swift package regression tests and Xcode Release build.
- Live OpenAI Czech content tests and 10 format-selection fixtures in two runs.
- Local Whisper inference, cancellation and subsequent transcription.
- Native audio import, result layout, capture startup and Accessibility grant preservation.
- Named-pasteboard tests for rich content and restoring without overwriting a newer user copy.
- An isolated WAV benchmark returned identical bytes with roughly 16-20% lower encoding time than the previous implementation; this is not a claim about total dictation latency.

Full Czech recognition benchmarks, every target editor and Bluetooth hot-plug soak testing are not claimed. Groq's editing route is implemented but the live editing evaluation used OpenAI. No replacement recognition engine or realtime streaming is included.
