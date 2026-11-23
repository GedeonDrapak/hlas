# Changelog

## Unreleased

- New hotkey choice: Fn + Control. Hold both to dictate, release either to stop. Pick it in Settings or the welcome tour.

## 0.6.1 - 2026-11-16

- Updates come from hlas.dev instead of GitHub (`https://hlas.dev/download/appcast.xml`), so they keep working when GitHub is unreachable.

## 0.6.0 - 2026-11-15

- Hlas Cloud: unlimited dictation and Smart text for EUR 35 a year with a licence key instead of an API key. Settings > Engine > Hlas Cloud shows the licence status, "Get Hlas Cloud" and "Manage subscription". The page after payment opens Hlas through `hlas://activate` and fills in the key.
- Free 7-day Hlas Cloud trial without a card (30 minutes a day), one per install: "Try free for 7 days" in Settings.
- One Hlas Cloud licence works on up to 5 computers. Hlas Cloud requests carry a random install id for that.
- The status pill drops its hairline border and the "Transcript" label while recording. A dotted orb replaces the dot: green while listening, grey while transcribing (thinking-orbs by Jakub Antalik, MIT).

## 0.5.0 - 2026-11-04

- Hlas for macOS and Hlas for Windows now live in one repository and ship in one GitHub release with one version number.
- Automatic updates through Sparkle. Hlas asks once before it starts checking, and Settings and the menu bar have "Check for Updates".
- Remove filler sounds (ehm, eee, hmm, um) locally, in both output modes. On by default, toggle in Settings > Clean-up.
- Spoken line breaks: say "nový řádek" or "nový odstavec" (new line, new paragraph) as a separate phrase. On by default.
- Labs in Settings, for experiments that are off by default. First one: spoken symbols ("zavináč" to @, "podtržítko" to _, "gmail tečka com" to gmail.com).
- Vocabulary words can carry how the engine mishears them. Click a word, add "sídens, sí dens", and Hlas writes Seedance.
- Ctrl+Option+V pastes your last dictation again, also from the menu bar.
- Fix lost dictations: when Whisper's Czech priming prompt turns real speech into a subtitle credit ("Titulky vytvořil..."), Hlas now transcribes the same audio again without any prompt instead of discarding it.
- Free the local model before quitting, so ggml no longer aborts at exit.
- Welcome tour: new "Your text" step explains Transcript vs Smart text and the clean-up switches; steps slide in from the side, backgrounds crossfade, the current-step highlight glides, permission cards animate when granted.
- Shorter menu bar menu: daily actions on top, the tour, updates, diagnostics and legal under Help. "Make smart text" moved into the last-dictation window.
- Fix "Transcribe Audio File" opening its file dialog behind other apps, so the click seemed to do nothing.
- Settings: the engine is now a menu. Five segments needed more than the window's width and pushed the whole page past both edges.
- Credits: "Made by Gedeon Drapák and Edenmakers" with links in Help, About and at the bottom of Settings.
- The recording waveform is drawn every display frame (up to 120 Hz on ProMotion) and scrolls smoothly between level updates.

## 0.4.4 - 2026-10-27

- Add Soniox (stt-async-v5, ~$0.10 per hour) and Fish Audio (transcribe-1-pro, ~$0.36 per hour) as bring-your-own-key transcription engines in Settings and the welcome tour. Soniox gets your vocabulary as context terms; the upload and job are deleted right after transcription.
- Explain an exhausted cloud balance (HTTP 402) instead of a generic error.

## 0.4.3 - 2026-10-27

- Add a hotkey picker in Settings and the welcome tour: Fn / Globe, Right Option, Right Command, Right Control or F13-F19, for keyboards without Fn.
- Cancel dictation when a right-side modifier hotkey is used in a shortcut such as Right Cmd+C.
- Stop F-key hotkeys from leaking autorepeat key presses into the focused app.
- Detect a stale Accessibility entry from an older build in the welcome tour and offer a one-click reset (`tccutil reset Accessibility`) instead of a card that never turns green.

## 0.4.2 - 2026-09-09

- Let Smart text choose structure from intent instead of forcing lists by action count.
- Keep messages, explanations and stories in prose; reserve bullets for real enumerations and numbering for procedures.
- Add live Czech format-selection fixtures covering prose, quoted requests, shopping lists, task assignments and instructions.

## 0.4.1 - 2026-09-09

- Restore automatic paste for editors that expose no Accessibility focused element. Guard only changes of application; Cmd-V uses the actual caret.
- Preserve and restore every clipboard format without rejecting images or payloads over 1 MB.
- Add regression tests for unavailable AX fields, large rich clipboards, and a newer user copy during restoration.

## 0.4.0 - 2026-09-09

- Add Transcript / automatic Smart text, original recovery, and reprocessing from history.
- Serialize microphone lifecycle off the UI thread, throttle metering and adapt microphone cooldown.
- Cancel local inference cooperatively and ignore obsolete sessions; prefetch the local model during speech.
- Fix model idle-unload races and release it under memory pressure.
- Preserve raw transcripts, add exact replacements, optional history and retention; persist history off the main thread.
- Check the original focused input before paste and preserve rich clipboard content through a copy fallback.
- Import audio files and bound recordings to 10 minutes.
- Reduce WAV allocations and add session-level timing metadata and offline/live regression tests.

## 0.3.1 - 2026-08-09

- Keep the recording pill on the Space you are actually on. `.stationary` conflicted with `.canJoinAllSpaces` and could pin the pill to the Space where it was first created; the collection behavior is now re-asserted on every show.
- Stop clipping the pill's drop shadow. The panel was 260x44 around a 40pt capsule, so the shadow survived left and right but was sheared off top and bottom.
- Replace the personal-use Konect demo with the purchased commercial cut. Digits and punctuation are now safe in display text.
- Ship the first public DMG, signed with a stable developer certificate so Accessibility and Microphone grants survive updates.

## 0.3.0 - 2026-08-06

- Add Apple Silicon-only distribution configuration with Hardened Runtime and microphone entitlement.
- Add a notarized DMG release command with signing and Gatekeeper validation.
- Verify local Whisper model downloads by HTTP response, exact size, and SHA-256 before atomically installing them.
- Keep a working local model when a replacement download is invalid or cancelled.
- Turn cloud transcription failures into actionable messages for API keys, rate limits, connectivity, timeouts, and provider outages.
- Add bundled privacy policy, third-party notices, and access to them from Settings and the menu bar.
- Add fast regression tests for WAV encoding, hallucination filtering, cloud errors, and model integrity.
- Add privacy-safe diagnostics export, microphone startup timing, VoiceOver state announcements, Reduce Motion support, and keyboard-accessible controls.

## 0.2.0 - 2026-08-06

- Store API keys in macOS Keychain with automatic migration.
- Prevent stale transcription results and preserve the final audio buffer.
- Add Esc cancellation, searchable History and Launch at Login settings.
- Keep transcript contents out of diagnostics and secure local files.
- Add custom Hlas app and menu bar icons with bundled Satoshi typography.
- Follow the active window across displays and refresh microphone devices live.
- Make Bluetooth audio capture reliable with AVCaptureSession and default to the built-in mic.
- Rebuild the warm capture session immediately after microphone or system audio changes.
