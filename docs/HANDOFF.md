# Current update: 0.4.2 (2026-09-09)

Transcript / Smart text is the only output switch. Smart text automatically selects paragraphs or lists, preserves facts and language, and uses OpenAI gpt-4.1-mini or Groq openai/gpt-oss-120b with existing keys. It is optional and never silently enabled for existing installations. No style picker. Format is chosen from intent; never force bullets based on a number of verbs or actions. Messages and stories remain prose, actual lists and procedures get appropriate structure.

DictationCoordinator owns immutable session configuration, cancellation and delivery. AudioRecorder serializes session lifecycle separately from capture. LocalWhisper supports C abort callbacks, recording-time prefetch, pressure unload and generation-checked idle unload. Microphone cooldown is adaptive (8/30 seconds), maximum recording/import is 10 minutes.

History preserves originals and supports retention; existing history format migrates on read. Persistence is serialized off main. Retention defaults to no expiration. Automatic paste checks only that the foreground application has not changed. Do not require AX focused-element identity: Electron editors can report no element while Cmd-V works. Preserve all clipboard formats and restore with a changeCount guard; do not block normal dictation for images or size thresholds.

Validation and measured limitations: see `RELEASE-0.4.2.md`.

## Previous handoff (historical, superseded where conflicting)

# Hlas - handoff / current state (2026-08-06)

App is **installed, fully working, and in daily use** at `/Applications/Hlas.app`.
Git history is clean and chronological - `git log --oneline` tells the build story.

## Verified working (tested end-to-end on the owner's M1 Pro, 16 GB, macOS 26.5)

- Fn hold-to-talk + quick-tap hands-free latch; pill overlay with live waveform.
- Local engine: whisper.cpp `large-v3-turbo-q5_0` (Metal, beam-5). Measured: model load 0.76 s,
  11 s audio → ~1.7 s, ~800 MB only while loaded, hidden idle app ~60 MB. Model at
  `~/Library/Application Support/Hlas/models/ggml-large-v3-turbo-q5_0.bin`.
- Cloud engines: Groq `whisper-large-v3-turbo`; OpenAI `gpt-transcribe` (owner's key configured,
  active engine at handoff). Vocabulary → `prompt` field on both.
- Czech output with correct diacritics; priming prompts for cs/sk/en; first-word clipping fixed;
  silence + hallucination guards active.
- Paste works in every app including Hlas's own windows (hidden Edit menu fix).
- Onboarding (4 steps, split layout, live permission polling), settings, language favorites with
  hover-✕, input-device picker with pill source badge, launch-at-login toggle.
- Permissions survive rebuilds (team-signed via Xcode). `make install` is the whole loop.
- API keys live in macOS Keychain with automatic migration from legacy UserDefaults.
- Esc cancels recording, overlapping transcription results are rejected by session ID, and
  audio accumulation runs on a dedicated queue so the final buffer is not lost.
- Debug logs never contain transcript text, rotate at 1 MB, and private files use mode `0600`.
- Launch at Login is available in onboarding and Settings. History can be cleared from Settings.
- Version 0.3.0 is Apple Silicon-only and adds release hardening, privacy and license documents,
  actionable cloud errors, verified model downloads and a fast regression test suite.
- Audio capture uses AVCaptureSession because AVAudioEngine input taps can stop delivering
  buffers with Bluetooth devices on macOS 26. The built-in microphone is the default.
- Microphone preference and CoreAudio device changes invalidate the warm capture session so the
  next dictation cannot reuse a stale route.
- `make test` runs 9 Swift Testing cases for WAV encoding, hallucination filtering, cloud error
  mapping and model integrity. `make release` creates and notarizes the public arm64 DMG once a
  Developer ID Application certificate and `HlasNotary` Keychain profile are installed.
- Settings and the menu bar can export privacy-safe diagnostics containing no transcripts or API
  keys. Audio startup time is logged for route-change debugging. VoiceOver receives recording state
  announcements, and custom transitions respect Reduce Motion.

## Engine economics (research-verified Aug 2026)

| Engine | Czech quality | Cost @1 h/day | Notes |
|---|---|---|---|
| Local turbo-q5 | good | free | default; quality ceiling of quantized turbo |
| Groq large-v3 | very good | ~$3.30/mo | fastest API (~200x realtime) |
| OpenAI gpt-transcribe | likely best | ~$8/mo | July 2026 model; keyword/context support |
| ElevenLabs Scribe | best published Czech WER (≤5 %) | ~$6.60/mo | NOT integrated - candidate |
| gpt-live-transcribe | - | ~$30/mo | deliberately skipped (cost + Realtime WS complexity) |

Apple SpeechAnalyzer: **no Czech** - ruled out. Parakeet TDT v3 via FluidAudio: Czech 11 % WER,
~66 MB on ANE, ~155x realtime on M1 - the designated future local engine (bigger integration).

## Backlog - mini polish (good Codex tasks, roughly prioritized)

1. **Hallucination blocklist extension.** Collect real false positives from debug.log; consider
   whisper's `no_speech_prob` as an additional signal.
2. **Priming prompts for more languages** (`LocalWhisper.run`) - de/es/fr/pl at least, mirroring
   the cs pattern.
3. **Local model options.** Offer `large-v3-q5_0` (1.1 GB, better Czech, ~2.5x slower) as a
    "max accuracy" alternative in Settings; reuse ModelDownloader with a model registry.
4. **LLM cleanup pass (bigger).** Optional post-processing: filler removal, homophone fixes
    (hezky/hezký), number formatting. Provider: Groq (cheap) or Apple Intelligence. Steal the
    prompt from Handy (`settings.rs:726` in cjpais/Handy) - includes prompt-injection defense.
    Must honor "keep original language" for Czech.
5. **ElevenLabs Scribe engine** - best published Czech WER; same multipart pattern as existing
    API engines, different response shape.
6. **Accessibility QA.** Run Accessibility Inspector and a complete keyboard/VoiceOver walkthrough
   on the final notarized build.
7. **Distribution credentials.** Install a Developer ID Application certificate, store the
   `HlasNotary` credentials, run `make release`, and test the notarized DMG on a clean M-series Mac.
8. ~~**Konect font license.**~~ DONE (Aug 2026). The full commercial cut `Konect-Regular.otf`
   (Ragam Kata Studio) replaced the personal-use demo. 239 glyphs — digits and punctuation are
   now safe. Still missing caron/ring diacritics (ČĎĚŇŘŤŮ + lowercase), so never point
   `DS.display` at Czech or user-supplied text; Satoshi covers those.

## Risky areas - touch with care

- `Hotkey.swift` + signing setup: the permission stack is finally stable; changes here can
  reintroduce the TCC dance. Test with `tools/fakefn.swift` after ANY change.
- `TextInjector.swift`: the transient-type tagging and changeCount guard are load-bearing
  (clipboard managers, user copies mid-transcription).
- `AudioRecorder` keep-warm vs. device switching: the AVCaptureSession restarts when the preferred
  device changes - preserve that when refactoring.

## Environment facts

- Owner's machine: M1 Pro, 16 GB RAM, macOS 26.5, Xcode 26.6. RAM discipline matters.
- whisper.cpp checkout: `~/Dev/whisper.cpp` (d9b7613b, Nov 2025), static libs in `build-hlas/`.
- The owner's OpenAI key is stored in macOS Keychain; do not log or print settings values.
