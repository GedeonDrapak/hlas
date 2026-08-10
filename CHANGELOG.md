# Changelog

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
