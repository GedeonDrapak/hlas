# Hlas

Ultra-minimal macOS dictation. Hold **Fn**, speak (Czech or English), release - text appears at your cursor. No subscription, no account, no telemetry.

Built as a personal replacement for Superwhisper / Wispr Flow / Willow ($15/mo each).

## Why

| | Hlas | Superwhisper | Wispr Flow | Willow |
|---|---|---|---|---|
| Price | free / ~$3/mo API | $8.49/mo | $15/mo | $15/mo |
| Local + private | yes | yes | no (cloud + screenshots) | partial |
| Czech quality | whisper large-v3 class | good | uncontrollable | weak |
| App size | ~4 MB | ~1 GB+ | heavy | heavy |
| Idle RAM | ~60 MB (model auto-unloads) | ~800 MB | heavy | ? |

## Usage

- **Hold Fn** → speak → release: text pastes into the focused app.
- **Quick-tap Fn**: latches hands-free recording; tap again to stop.
- Menu bar icon → **Settings**: engine, language, vocabulary, history.

## Engines

- **Local (default):** whisper.cpp `large-v3-turbo-q5_0` (547 MB one-time download, ~1 GB while loaded, auto-unloads after 3 min idle). Runs on Metal.
- **Groq API:** whisper-large-v3-turbo - ~$0.04/hr of audio (≈ $1–3/mo at heavy use). BYOK.
- **OpenAI API:** gpt-transcribe - ~$0.27/hr. BYOK.

## Build

```bash
# 1. Build whisper.cpp static libs (once)
cd ../hlas
make vendor   # builds whisper.cpp for the app's real macOS 15 deployment target

# 2. Build app (xcodegen: brew install xcodegen)
make install   # builds via Xcode (stable signing), installs to /Applications, launches
```

Permissions needed on first run: **Microphone** + **Accessibility** (for the Fn hotkey and paste).

## Design

Fusion of the Fakturio design system (Linear/Raycast near-black neutrals, hairline borders, 16px radii) and the Eden Makers system (bio-digital green `hsl(153 100% 45%)`, uppercase tracked labels, never pure black/white).

## Architecture

```
Fn press ──► CGEventTap (Hotkey.swift, health-checked)
              │
              ▼
        AVAudioEngine ──► 16 kHz mono Float32 (AudioRecorder.swift)
              │                    │
              ▼                    ▼
      Overlay pill (NSPanel)   Transcriber protocol
                                 ├─ LocalWhisper (whisper.cpp, lazy load + idle unload)
                                 └─ OpenAICompatibleTranscriber (Groq / OpenAI)
              │
              ▼
        TextInjector - pasteboard swap + Cmd-V (physical keycode 9,
        Czech-QWERTZ-safe), transient-tagged, changeCount-guarded restore
```

Techniques borrowed from studying Handy, VoiceInk and FluidVoice source:
hybrid tap/hold hotkey (VoiceInk), tap health-check (FluidVoice), clipboard
etiquette + sub-second padding + Czech filler handling (Handy).
