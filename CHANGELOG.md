# Changelog

## Unreleased

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
