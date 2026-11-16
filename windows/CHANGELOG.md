# Changelog

## Unreleased

- "Check for updates" reads `https://hlas.dev/download/latest.json` instead of the GitHub releases API, and the privacy link opens hlas.dev.

## 0.6.0 - 2026-11-15

- Hlas Cloud on Windows: a fourth engine that dictates through the Hlas Cloud subscription (EUR 35 a year) with a licence key instead of an API key. Smart text goes through Hlas Cloud too when it is the engine.
- New Settings page "Hlas Cloud": licence key, live subscription status, "Get Hlas Cloud" and "Manage subscription" (Stripe customer portal).
- `hlas://activate?key=...` links from the page shown after payment store the licence in Credential Manager and switch to Hlas Cloud, also when Hlas is already running. The installer registers the `hlas:` protocol and the uninstaller removes it with the stored licence.
- Free 7-day Hlas Cloud trial without a card (30 minutes a day): "Try free for 7 days" on the Hlas Cloud page. One trial per install.
- Hlas Cloud requests carry a random install id (`%LOCALAPPDATA%\Hlas\install-id`); one licence works on up to 5 computers.
- The status pill no longer draws a border.
- Clear messages for an unknown licence, an ended trial or subscription, too many computers and the daily fair-use limit.

## 0.5.0 - 2026-11-04

- Hlas for Windows moved into the Hlas repository (`windows/`) and now ships in the same GitHub release as Hlas for macOS, with the same version number. The installer is `Hlas-windows-x64-setup.exe`.
- "Check for updates" reads releases of GedeonDrapak/hlas and only offers a release that has the Windows installer attached.

## 0.2.0 - 2026-10-09

Rebuilt around a platform-independent, unit-tested core (`src/core`) and a
Win32 layer (`src/win`). Feature parity with Hlas for macOS 0.4.2.

### Fixed (broken in 0.1.0)

- **Half of every dictation was lost on 48 kHz microphones.** The recording was
  resampled as a single FFT chunk without flushing the resampler's delay, so
  Whisper received 5 s of silence followed by only the first half of a 10 s
  recording. Most Windows microphones run at 48 kHz.
- **Groq and OpenAI never worked.** `keyring` was built without its
  `windows-native` backend and silently stored API keys in an in-memory mock.
- **The CI-built exe could only run on AVX-512 processors.** whisper.cpp was
  compiled for the GitHub runner's CPU (`GGML_NATIVE`), so it would crash with
  an illegal instruction on most laptops. Builds now target a portable AVX2
  baseline, and older CPUs get a message pointing to Groq instead of a crash.
- **Local transcription aborted at random.** whisper-rs 0.16's safe abort
  callback reads its closure back as the wrong type, so whisper.cpp polled
  garbage and stopped the encoder ("failed to encode"). Hlas now passes its
  cancel flag through the raw callback.
- Recordings between 0.1 and 1 second failed inside whisper.cpp. Audio is now
  prepared like macOS: 0.25 s lead-in (no clipped first word), 1.2 s minimum,
  silent recordings skipped.
- Right Ctrl shortcuts (Ctrl+C with the right hand) started a dictation. A key
  pressed together with the push-to-talk key now cancels silently.
- Launching Hlas twice installed two keyboard hooks and pasted every dictation
  twice. A second launch now opens Settings in the running copy.
- The clipboard restore kept only plain text (images and rich text were lost)
  and ran 60 ms after the paste, before many apps had read it.
- The status pill leaked a GDI brush on every repaint, used the system font,
  ignored display scaling and always sat on the primary monitor.
- The local model stayed in RAM (about 1 GB) for the life of the process.
- The settings window showed API keys in clear text and opened a new copy on
  every click.
- Hlas's own synthetic Ctrl+V was seen by its own keyboard hook.

### Added

- Dark look after the macOS design: near-black surfaces, Eden green, Satoshi,
  Settings with a sidebar, switches, segmented controls and dark dropdowns.
- Hold to talk, or quick-tap to keep listening hands-free; tap again to stop.
  Esc cancels at any point.
- Smart text (same prompt and validation as macOS), exact replacements,
  hallucination filter for subtitle credits, Czech/Slovak/English priming
  prompts, vocabulary.
- History window: search, copy, copy original, reformat with Smart text,
  retention, clear.
- "Your text" window whenever a paste is not possible: you switched apps, the
  target runs as administrator, possible background audio, Smart text failed,
  or an audio file was imported.
- Transcribe audio files (wav, mp3, m4a/aac, flac, ogg; up to 10 minutes).
- Model download verified by size and SHA-256 before it replaces anything;
  idle unload after 3 minutes (configurable); prefetch while you speak; the
  0.1.0 model is moved out of the roaming profile.
- Warm microphone for 10 s after a dictation, microphone choice, rebuild after
  device changes, 10-minute limit, live level meter in the pill.
- Dictations are kept out of Windows clipboard history and cloud clipboard.
- Welcome tour in four steps, with a microphone test, the Windows privacy
  switch check, model download and a try-it box.
- Tray: language, output and engine switching, last result, history, audio
  import, welcome tour, start at sign-in, manual update check, log folder.
- Data moved to `%LOCALAPPDATA%\Hlas` (config migrated automatically); the
  program installs to `%LOCALAPPDATA%\Programs\Hlas`.
- Command line: `--transcribe`, `--download-model`, `--version`.
- CI: core tests on Linux and Windows, shared-rule drift check against the
  macOS sources, real Czech transcription on Windows, screenshots of every
  window, a hotkey-to-Notepad end-to-end run, an experimental Vulkan build and
  optional Azure Artifact Signing.

## 0.1.0 - 2026-08-15

First cut, built in CI but never run on Windows hardware.
