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

1. **Input-device list refresh.** `InputDevicePicker` enumerates `onAppear` only - refresh when
   the Menu opens, and listen for device hot-plug (CoreAudio property listener) so unplugging
   mid-session behaves.
2. **History window.** Settings shows last 5; add a full searchable list (menu item), copy on
   click, clear-all.
3. **Overlay on active screen.** `OverlayPanel.position()` uses `NSScreen.main`; should follow
   the screen with keyboard focus (multi-display).
4. **Hallucination blocklist extension.** Collect real false positives from debug.log; consider
   whisper's `no_speech_prob` as an additional signal.
5. **Priming prompts for more languages** (`LocalWhisper.run`) - de/es/fr/pl at least, mirroring
   the cs pattern.
6. **App icon.** None yet (default). Design: Eden green waveform glyph on near-black rounded
   square; respect the no-pure-black rule.
7. **Satoshi font bundling** - DS currently uses system font as stand-in. OTFs live in the Eden
    vault (`Design System/fonts/`); bundle Light/Regular/Medium/Bold + register via CTFont.
8. **Local model options.** Offer `large-v3-q5_0` (1.1 GB, better Czech, ~2.5x slower) as a
    "max accuracy" alternative in Settings; reuse ModelDownloader with a model registry.
9. **LLM cleanup pass (bigger).** Optional post-processing: filler removal, homophone fixes
    (hezky/hezký), number formatting. Provider: Groq (cheap) or Apple Intelligence. Steal the
    prompt from Handy (`settings.rs:726` in cjpais/Handy) - includes prompt-injection defense.
    Must honor "keep original language" for Czech.
10. **ElevenLabs Scribe engine** - best published Czech WER; same multipart pattern as existing
    API engines, different response shape.

## Risky areas - touch with care

- `Hotkey.swift` + signing setup: the permission stack is finally stable; changes here can
  reintroduce the TCC dance. Test with `tools/fakefn.swift` after ANY change.
- `TextInjector.swift`: the transient-type tagging and changeCount guard are load-bearing
  (clipboard managers, user copies mid-transcription).
- `AudioRecorder` keep-warm vs. device switching: warm engine restarts when the preferred device
  changes - preserve that when refactoring.

## Environment facts

- Owner's machine: M1 Pro, 16 GB RAM, macOS 26.5, Xcode 26.6. RAM discipline matters.
- whisper.cpp checkout: `~/Dev/whisper.cpp` (d9b7613b, Nov 2025), static libs in `build-hlas/`.
- The owner's OpenAI key is stored in macOS Keychain; do not log or print settings values.
