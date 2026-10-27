<div align="center">

![Hlas - Dictation. Not typing.](docs/assets/hero.png)

# Hlas

**Dictation. Not typing.**

Hold **Fn** · speak Czech or English · release - text lands at your cursor, in any app.
No subscription. No account. No telemetry. No cloud unless you ask for it.

### [⬇︎ Download Hlas 0.4.2](https://github.com/GedeonDrapak/hlas/releases/download/v0.4.2/Hlas-0.4.2-arm64.dmg) &nbsp;·&nbsp; 2.9 MB &nbsp;·&nbsp; Apple Silicon, macOS 15+

**[Website](https://gedeondrapak.github.io/hlas/)** · [First run](#first-run) · [Build from source](#build) · [Privacy](docs/PRIVACY.md)

</div>

---

Built in Prague as a personal replacement for the $8-15/month dictation apps - because every one of them treats Czech as an afterthought, and none of them should cost more than your music streaming.

## First run

1. Open the DMG, drag **Hlas** onto **Applications** and open it. macOS asks once whether to open an app downloaded from the internet: click **Open**.
2. Grant **Microphone** (to hear you) and **Accessibility** (for the Fn hotkey and the paste). The welcome tour walks you through both.
3. Hold **Fn**, speak, release.

Hlas is signed with the Developer ID certificate of Eden Makers s.r.o. and notarized by Apple. Every line of source is in this repo, and you can [build it yourself](#build) in two minutes.

<details>
<summary>Updating from a build before October 2026?</summary>

Earlier builds were signed with a personal development certificate. The new signature makes macOS treat Hlas as a new app for permissions, so it asks for Microphone and Accessibility once more. If the Fn key does nothing after updating, remove Hlas from **System Settings → Privacy & Security → Accessibility** with the minus button and grant it again, or run:

```bash
tccutil reset Accessibility com.gedeon.hlas
```
</details>

## Stop renting your own voice

| | **Hlas** | Superwhisper | Wispr Flow | Willow |
|---|---|---|---|---|
| Price | **free / ~$3/mo API** | $8.49/mo | $15/mo | $15/mo |
| Local + private | **yes** | yes | no (cloud + screenshots) | partial |
| Czech quality | **Whisper large-v3 class** | good | uncontrollable | weak |
| App size | **~4 MB** | ~1 GB+ | heavy | heavy |
| Idle RAM | **~60 MB** (model auto-unloads) | ~800 MB | heavy | ? |
| Account required | **no** | yes | yes | yes |

## One key. That's the whole UI.

- **Hold Fn** → speak → release: text pastes into the focused app.
- **Quick-tap Fn**: latches hands-free recording; tap again to stop.
- Menu bar Hlas icon → **Settings**, custom **Vocabulary**, searchable **History**.

![Onboarding](docs/assets/screens.png)

## Transcript or Smart text

Choose **Transcript** to insert speech recognition output directly, or **Smart text** to automatically clean up dictation and choose readable paragraphs or lists. No style presets to manage. Smart text uses your OpenAI or Groq key and sends text to that provider, including when audio transcription is Local. Hold Option when pressing Fn to use Transcript for one dictation.

Originals remain available in History. You can reprocess an entry, define exact text replacements, disable new history or choose its expiration. The menu also imports audio files up to 10 minutes long. Dictation pastes automatically at the current caret. If you switch to another application during processing, Hlas keeps the result available for copying.

## Your engine, your call

- **Local (default):** whisper.cpp `large-v3-turbo-q5_0` on Metal. One-time 547 MB download, ~1 GB RAM while loaded, auto-unloads after 3 min idle. Works offline. Audio never leaves your Mac.
- **Groq API:** whisper-large-v3-turbo - ~$0.04/hr of audio (≈ $1-3/mo at heavy use). BYOK.
- **OpenAI API:** gpt-transcribe - ~$0.27/hr, best accuracy + vocabulary support. BYOK.
- **Soniox API:** stt-async-v5 - ~$0.10/hr, vocabulary as context terms. Upload is deleted right after transcription. BYOK.
- **Fish Audio API:** transcribe-1-pro - ~$0.36/hr, automatic language detection, no vocabulary support. BYOK.

![Engine and language selection](docs/assets/engines.png)

## A whole dictation app. Four megabytes.

![Settings and recording pill](docs/assets/settings-pill.png)

- **~60 MB idle RAM** - Whisper loads on demand, unloads after 3 minutes of silence.
- **Keys live in macOS Keychain** - history stays local and is clearable anytime.
- **Bluetooth-safe** - pin the built-in mic so AirPods never wreck dictation quality.
- **Czech-first** - priming prompts for cs/sk/en, Czech-QWERTZ-safe paste.

## Build

Prefer building it yourself? Two minutes:

```bash
# 1. Build whisper.cpp static libs (once)
cd ../hlas
make vendor   # builds whisper.cpp for the app's real macOS 15 deployment target

# 2. Build app (xcodegen: brew install xcodegen)
make install   # builds via Xcode (stable signing), installs to /Applications, launches
make test      # runs fast tests for WAV, filtering, errors, and model integrity
```

Permissions needed on first run: **Microphone** + **Accessibility** (for the Fn hotkey and paste).

Hlas supports Apple Silicon Macs running macOS 15 or later. Intel Macs are intentionally not supported in this release.

## Privacy

- **Local:** audio stays on the Mac and is processed by the downloaded Whisper model.
- **Groq / OpenAI / Soniox / Fish Audio:** audio is sent directly to the provider selected in Settings for transcription.
- API keys are stored in macOS Keychain. History stays local and can be cleared in Settings.

The full policy ships in the app and is available in [Privacy](docs/PRIVACY.md). See [third-party notices](THIRD_PARTY_NOTICES.md) for whisper.cpp, Whisper model, Satoshi, and Konect font licenses.

## Public release

`make install` is for local development. Two ways to cut a public DMG:

```bash
# Public releases: Developer ID (Eden Makers) + Apple notarization.
# One-time setup on the release Mac: the Developer ID Application cert of the
# Eden Makers account (tech@edenmakers.ai) in the login keychain, plus
xcrun notarytool store-credentials EdenNotary --apple-id tech@edenmakers.ai --team-id CLG46PZG7A
make release

# Fallback without those credentials: dev-signed, not notarized. Users then
# have to approve it in Privacy & Security. Do not publish these.
tools/release-unsigned.sh
```

`make release` creates an Apple Silicon DMG, notarizes it, staples the ticket, and checks Gatekeeper. It reads the distribution team off the installed Developer ID certificate, so the Eden Makers team never has to be written down next to the personal Apple Development team in `project.yml`. It intentionally stops if the required certificate or notarization credentials are unavailable. Upload the DMG and its `.sha256` to the GitHub release; the website links to the release asset by version.

## Design

Fusion of the Fakturio design system (Linear/Raycast near-black neutrals, hairline borders, 16px radii) and the Eden Makers system (bio-digital green `hsl(153 100% 45%)`, uppercase tracked labels, never pure black/white).

The app uses a custom two-pulse Hlas mark and bundled Satoshi typography. The same mark scales from the macOS app icon down to the monochrome menu bar template.

## Architecture

```
Fn press ──► CGEventTap (Hotkey.swift, health-checked)
              │
              ▼
     AVCaptureSession ──► 16 kHz mono Float32 (AudioRecorder.swift)
              │                    │
              ▼                    ▼
      Overlay pill (NSPanel)   Transcriber protocol
                                 ├─ LocalWhisper (whisper.cpp, lazy load + idle unload)
                                 ├─ OpenAICompatibleTranscriber (Groq / OpenAI)
                                 ├─ SonioxTranscriber (upload, poll, delete)
                                 └─ FishAudioTranscriber
              │
              ▼
        TextInjector - pasteboard swap + Cmd-V (physical keycode 9,
        Czech-QWERTZ-safe), transient-tagged, changeCount-guarded restore
```

Techniques borrowed from studying Handy, VoiceInk and FluidVoice source:
hybrid tap/hold hotkey (VoiceInk), tap health-check (FluidVoice), clipboard
etiquette + sub-second padding + Czech filler handling (Handy).
