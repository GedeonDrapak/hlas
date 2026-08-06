# Agent guide — Hlas

Ultra-minimal macOS menu-bar dictation app (Superwhisper/Wispr Flow replacement).
Czech-first. Swift + AppKit/SwiftUI, whisper.cpp statically linked, BYOK cloud engines.
Owner: Gedeon Drapák. Built Aug 2026 with Claude; this file is for any agent continuing work.

## Read first

1. `README.md` — product overview, engine comparison, architecture diagram.
2. `docs/HANDOFF.md` — current state, verified-working list, prioritized backlog.
3. `docs/TRANSCRIPT.md` — full session log: every decision, bug, and fix with reasoning.

## Build & run

```bash
make install   # xcodegen → xcodebuild (Release) → /Applications/Hlas.app → launch
```

- Requires: Xcode 26+, `brew install xcodegen`, whisper.cpp static libs in `Vendor/lib`.
- If `Vendor/lib` is empty (fresh clone), build them first:
  ```bash
  cd ../whisper.cpp
  cmake -B build-hlas -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build build-hlas -j
  cd ../hlas && find ../whisper.cpp/build-hlas -name "*.a" -exec cp {} Vendor/lib/ \;
  cp ../whisper.cpp/include/whisper.h ../whisper.cpp/ggml/include/*.h Sources/CWhisper/include/
  ```
- `project.yml` is the source of truth; `Hlas.xcodeproj` is generated (gitignored). Never edit the xcodeproj.

## Signing — DO NOT CHANGE

- Signed with **Apple Development, team 74N9VPV9D6, automatic signing via Xcode**. This gives a
  stable designated requirement → **Accessibility/Microphone TCC grants survive rebuilds**.
- NEVER switch to ad-hoc (`--sign -`): every rebuild changes CDHash → macOS silently ignores the
  Accessibility grant → the Fn hotkey dies and the user must re-toggle permissions.
- NEVER `codesign` the bundle manually with the dev cert outside Xcode: without an embedded
  provisioning profile, macOS 26 Gatekeeper **moves the app to Trash** on launch.

## Testing & QA (no unit tests yet — this is the loop)

- **Debug log:** `~/Library/Application Support/Hlas/debug.log` — tap status, presses, sample
  counts, transcripts, drops. First place to look, always.
- **Synthetic dictation:** `swift tools/fakefn.swift` posts an Fn down+up (1.5 s hold). Full
  pipeline fires without touching the keyboard. Check debug.log afterwards.
- **Visual QA:** `HLAS_STEP=N /Applications/Hlas.app/Contents/MacOS/Hlas` opens onboarding at
  step N (0–3). Loop: build → launch with env → `screencapture -x shot.png` → read the image →
  check contrast/layout — for EVERY step, on EVERY gradient. This caught real bugs twice.
- **RAM check:** `ps -o rss= -p $(pgrep -x Hlas)` — idle must stay ≤ ~50 MB; the whisper model
  (~800 MB) must appear only during transcription and unload after `modelKeepAliveSeconds`.

## Architecture (one file ≈ one concern)

| File | Concern |
|---|---|
| `App.swift` | AppDelegate: status item, hidden Edit menu, dictation loop (hybrid tap/hold), permission retry |
| `Hotkey.swift` | CGEventTap on Fn (keycode 63, flagsChanged), health-check timer re-enables dead taps |
| `AudioRecorder.swift` | AVAudioEngine → 16 kHz mono Float32; keep-warm 12 s; per-device selection via AudioUnit |
| `AudioDevices.swift` | CoreAudio HAL input enumeration + `InputDevicePicker` UI |
| `Transcriber.swift` | Engine protocol + WAV encoder |
| `LocalWhisper.swift` | whisper.cpp: lazy load, beam-5, priming prompts (cs/sk/en), idle unload, model downloader |
| `APITranscribers.swift` | Groq (whisper-large-v3-turbo) + OpenAI (gpt-transcribe), shared multipart client |
| `TextInjector.swift` | Pasteboard swap + Cmd-V (physical keycode 9), transient-tagged, changeCount-guarded restore |
| `Hallucinations.swift` | Drops whisper's silence hallucinations ("Titulky vytvořil…") |
| `OverlayPanel.swift` | Non-activating NSPanel pill: waveform, source badge, frosted glass |
| `Onboarding.swift` | 4-step split layout (gradient left / content right), live permission polling |
| `SettingsWindow.swift` | Engine, language chips, mic picker, vocabulary, history |
| `Languages.swift` | 60+ whisper languages, favorite chips with hover-✕, search popover |
| `Settings.swift` | UserDefaults-backed observable settings |
| `History.swift` | Last 50 transcripts, local JSON |
| `DesignTokens.swift` | The design system — read before any UI work |
| `VisualEffect.swift` | NSVisualEffectView wrapper (frosted glass) |
| `Log.swift` | File logger (unified log is unreliable for bare SwiftPM-style apps) |
| `Sources/CWhisper/` | C shim exposing whisper.h to Swift |

## Design system (Fakturio × Eden Makers fusion) — binding rules

- **Never pure black (#000) or pure white (#FFF).** Floors: `#0C0D0F`/`#0F0F0F`; ceilings: ~93 % white.
- Accent: Eden bio-digital green `hsl(153 100% 45%)` (`DS.brand`) — recording, checkmarks, CTAs.
- Hairline borders `white 6–12 %`, radius 16 (cards) / 8 (inputs), uppercase tracked labels for
  section headers (`DS.label` + `.tracking(3-4)`).
- Frosted glass everywhere: `VisualEffectBlur` + dark tint 0.45–0.5 (windows), 0.35 (pill).
- Any text over gradient photos needs the scrim pattern from `Onboarding.leftPanel` (uniform
  0.38 + heavier bottom). Contrast on EVERY gradient, not just the dark one.

## Known gotchas (each cost real debugging time)

1. **Cmd-V inside our own windows** needs the hidden Edit menu in `setupMainMenu()` — LSUIElement
   apps have no menu bar, and paste key-equivalents route through `NSApp.mainMenu`. Don't remove.
2. **`scaledToFill` images in ZStack** blow up layout — always use the `Color.overlay(Image…)`
   containment pattern (see `Onboarding.leftPanel`).
3. **whisper on silence hallucinates** Czech/English subtitle credits — peak guard (0.01) +
   `Hallucinations.filter`. Extend the blocklist rather than raising the peak threshold (quiet
   speakers get dropped otherwise).
4. **Sub-second audio** breaks whisper.cpp → padded to ≥1.2 s; leading 0.25 s silence prevents
   first-word clipping ("Ahoj"→"Hoj").
5. **Event taps die silently** under load / permission changes — the 5 s health-check timer in
   `Hotkey.swift` re-enables; the 3 s retry loop in `App.swift` handles grant-after-launch.
6. **`log show` doesn't reliably surface NSLog** from this app — use `Log.write` → debug.log.
7. Shell cwd resets between agent tool calls — use absolute paths in build commands.

## Conventions

- Comments: only for constraints code can't express (see existing files for density).
- Commits: imperative summary, `Co-Authored-By` footer for AI work.
- No new dependencies without strong reason — the 2.4 MB binary is a feature.
- User-facing copy: English in-app; Gedeon communicates in Czech.
