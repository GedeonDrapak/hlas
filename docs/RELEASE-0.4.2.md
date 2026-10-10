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

Since 2026-10-10 the published DMG is signed with the Developer ID certificate of Eden Makers s.r.o. (team CLG46PZG7A) and notarized by Apple, so it opens without a Gatekeeper warning. The app code is unchanged from the original 0.4.2 build. Because the signature changed from the personal development certificate, macOS asks for Microphone and Accessibility once more after updating; if the Fn key does nothing, run `tccutil reset Accessibility com.gedeon.hlas` and grant it again. Quit the existing app before replacing it in Applications.

## Verification

- Swift package regression tests and Xcode Release build.
- Live OpenAI Czech content tests and 10 format-selection fixtures in two runs.
- Local Whisper inference, cancellation and subsequent transcription.
- Native audio import, result layout, capture startup and Accessibility grant preservation.
- Named-pasteboard tests for rich content and restoring without overwriting a newer user copy.
- An isolated WAV benchmark returned identical bytes with roughly 16-20% lower encoding time than the previous implementation; this is not a claim about total dictation latency.

Full Czech recognition benchmarks, every target editor and Bluetooth hot-plug soak testing are not claimed. Groq's editing route is implemented but the live editing evaluation used OpenAI. No replacement recognition engine or realtime streaming is included.
