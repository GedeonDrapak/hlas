# Session transcript — Hlas v0.1 build log (2026-08-06)

Reconstructed detailed log of the full build session (Gedeon ↔ Claude). Not a verbatim dump —
but every request, decision, bug, and fix is here in order, with reasoning. Written for the next
agent (Codex) to absorb full context before touching code.

---

## 1. Kickoff — the brief

Gedeon: annoyed at paying $15/mo subscriptions for Superwhisper / Wispr Flow / Willow. Wants an
**ultra-minimalist, fast, smart, low-RAM background dictation app** with excellent **Czech**,
local models or BYOK APIs, sleek design = fusion of his **Fakturio** app design system and the
**Eden Makers** design system (both in his vault). Provided a list of OSS apps to research
(VoiceInk, Handy, OpenWhispr, FluidVoice, Dictara, Buzz…).

## 2. Research phase (3 parallel agents)

**Commercial apps (Superwhisper / Wispr Flow / Willow):**
- Wispr Flow's UX is the benchmark: hold Fn, minimal bottom pill with waveform, zero config.
  Cloud-only + screenshot uploads = privacy backlash (2.7/5 Trustpilot).
- Superwhisper: local models (its killer feature) but bloated mode-zoo, heavy RAM, complex setup.
- Willow: fast (200 ms claim) but weak non-English.
- The 90 % feature set: one hotkey, pill overlay, paste-anywhere, invisible cleanup, custom
  vocabulary, explicit language pick, speed, privacy-by-default, simple history.
- Bloat to skip: mode zoo, per-mode LLM pickers, screen capture context, meeting notetakers.
- **Market gap: nobody has Wispr UX + local privacy + good Czech. That's Hlas.**

**OSS repo analysis (Handy / VoiceInk / FluidVoice, cloned + read):**
- Handy (Rust/Tauri): pasteboard-promise paste with read receipts; idle-unload watcher for model
  RAM; Silero VAD; sub-second padding; Czech filler list; excellent LLM cleanup prompt.
- VoiceInk (Swift): whisper.cpp actor pattern; **hybrid hotkey** (hold=PTT, tap=toggle, decided
  by press duration); AUHAL recorder that never touches default device; Czech ⌘-QWERTZ paste fix
  (physical keycode 9); sessionID-verified clipboard restore; prewarm on wake.
- FluidVoice (Swift SPM): CGEventTap **health-check timer** (macOS silently kills taps);
  FluidAudio/Parakeet CoreML integration; vocabulary boosting; elaborate typing fallbacks.
- Distilled "steal this" list drove the implementation below.

**STT engines for Czech (key numbers):**
- Local sweet spot: whisper.cpp `large-v3-turbo-q5_0` — 547 MB disk, ~1 GB loaded, ~9x realtime
  claim (measured ~6.7x on M1 Pro), small Czech penalty vs full large-v3.
- Parakeet TDT v3 via FluidAudio: Czech 11 % WER FLEURS, ~66 MB ANE RAM, ~155x realtime on M1 —
  future upgrade, bigger integration.
- **Apple SpeechAnalyzer (macOS 26): NO Czech** — ruled out.
- APIs: Groq large-v3 $0.111/hr (best price/quality), ElevenLabs Scribe ≤5 % Czech WER claimed
  (best quality), OpenAI. All far under $15/mo subscriptions at 1 h/day.

## 3. Design synthesis

Both source systems use Satoshi. Fakturio dark = Linear/Raycast near-black neutrals (#0C0D0F,
hairlines white 8 %, radius 16). Eden adds bio-digital green hsl(153 100% 45%), uppercase tracked
labels, "never pure black/white" hard rule. → `DesignTokens.swift`.

## 4. Build v0.1 (name: "Hlas" = Czech for "voice")

SwiftPM skeleton first, then Xcode-managed. Components: CGEventTap Fn hotkey, AVAudioEngine
16 kHz recorder, Transcriber protocol (Local/Groq/OpenAI), pasteboard+Cmd-V injector, NSPanel
pill overlay, settings window, history, model downloader. whisper.cpp built as static libs
(`-DGGML_METAL_EMBED_LIBRARY=ON` — no bundle resources needed), vendored to `Vendor/lib`,
exposed via `Sources/CWhisper` C target. App bundle 2.4 MB, idle 38 MB RAM.

Smoke tests before shipping: C harness against vendored libs — jfk.wav transcribed correctly;
timing: load 0.76 s, 11 s audio in 1.65 s warm.

## 5. The permission saga (read this before touching signing!)

Chronology of pain, all on macOS 26:
1. Ad-hoc signed app: works, but **every rebuild → new CDHash → TCC silently ignores the old
   Accessibility grant** (checkbox still shows enabled!). Symptom: tap creation fails,
   `AXTrusted=false`, Fn dead.
2. Manual `codesign` with Apple Development cert (no provisioning): **Gatekeeper moved the app
   to Trash on launch** (RBSRequestErrorDomain error 5 → app vanished into ~/.Trash).
3. Fix: `xcodegen` project + `xcodebuild -allowProvisioningUpdates` automatic signing (team
   74N9VPV9D6) → provisioned dev signing → stable identity → **grants survive rebuilds**
   (verified three times: `event tap STARTED (attempt 0)` right after reinstall).
4. Debugging tools born here: file logger (`debug.log`) because `log show` didn't surface NSLog;
   `tools/fakefn.swift` synthetic Fn press; grant-watcher loops polling debug.log.
5. Stale grants fixed by `tccutil reset Accessibility com.gedeon.hlas` + fresh grant, NOT by
   toggling (toggling an entry pointing at a stale csreq often does nothing).

## 6. First real dictation + accuracy round

User's first test: said "Ahoj Ahoj Ahoj, zkouším jestli tohle funguje v češtině hezky" → got
"Hoj hoj hoj, zkouším jestli sezon co funguje v češtině hezký". Three diagnosed causes → fixes:
- **First-word clipping** (Ahoj→Hoj): mic spin-up + whisper dropping t=0 speech → 0.25 s leading
  silence pad + engine keep-warm 12 s after each dictation.
- **Word errors** (tohle→sezon co): greedy decoding on quantized turbo → beam search (size 5,
  benchmarked ~free on Metal) + Czech priming prompt (VoiceInk technique) for diacritics.
- **hezky→hezký**: homophone, model ceiling → future LLM cleanup pass.
- Silence guard added (peak < 0.01 → drop) after synthetic presses produced hallucinations
  ("Konec.", "Titulky vytvořil Jirka Kováč" — whisper's Czech YouTube-subtitle hallucinations)
  → `Hallucinations.swift` blocklist.
Post-fix test: "Ahoj, ahoj, ten se zkúška mého nového nástroje" — first word intact, remaining
errors = quantized-turbo ceiling → recommended Groq/OpenAI for A/B.

## 7. gpt-transcribe (user brought OpenAI's July 2026 announcement)

Decision: **gpt-transcribe yes** (same /audio/transcriptions endpoint, $0.0045/min ≈ $8/mo,
beats gpt-4o-transcribe, keyword/context support → vocabulary works properly) — swapped in as
the OpenAI engine. **gpt-live-transcribe no** ($0.017/min ≈ $30/mo at 1 h/day — double the
subscriptions being escaped; needs Realtime WebSocket stack; only cosmetic gain in push-to-talk).
Also compared Groq vs OpenAI for the user (Groq = open whisper on LPUs, cheap/fast/known Czech;
gpt-transcribe = newer, likely better Czech, pricier; verdict: A/B with own voice).
User configured his OpenAI key; gpt-transcribe is the active engine at handoff.

## 8. Design pass — blur + onboarding

- Frosted glass everywhere (NSVisualEffectView wrapper): pill (hudWindow + 0.35 tint), windows
  (underWindowBackground + 0.45–0.5 tint). User wanted "Raycast/Eloquent" feel + more
  transparency — delivered.
- Onboarding v1 (single column) → v2 **split layout** per user's reference screenshots:
  Unsplash gradient panel left (3 photos downloaded, ~520 KB, bundled — offline-safe) with HLAS
  brand + numbered step chips (active = white card), content right. 4 steps: Welcome →
  Permissions (live 1 s polling, green checkmarks, Continue gated) → Engine & language → Try it
  (test field, last transcript, launch-at-login).
- **Bug found by user (screenshot): gradient overflowed the whole window** — `scaledToFill` in
  ZStack blew the layout. Fix: `Color.overlay(Image…)` containment pattern + decoded-image cache.
- **Bug found by user #2: contrast** — the "blue" Unsplash photo was actually light pastel;
  white text/chips unreadable. Fix: uniform 0.38 scrim + heavier bottom gradient, dark chip
  backing, swapped photo for a genuinely dark one. Lesson institutionalized: **visual QA of
  every step on every gradient** via `HLAS_STEP=N` env hook + screencapture loop (added then).

## 9. Language manager

User: wants add/remove favorite languages with search (es, zh, sk…). Built `Languages.swift`:
60+ whisper languages with native names, favorite chips (click = set active), "+" popover with
search + toggle, hover-✕ on chips (user requested after seeing chips), Auto-detect permanent,
active-language fallback when removing the active chip. Wired into Settings + onboarding.

## 10. Paste-inside-own-app bug

User: transcription showed in history but never landed in the onboarding Try-It field. Root
cause: **LSUIElement apps have no main menu, and Cmd-V routes through menu key-equivalents** —
so synthetic Cmd-V did nothing inside Hlas's own windows (worked everywhere else). Fix: hidden
programmatic main menu with standard Edit items (`setupMainMenu`). Bonus: manual Cmd-C/V/A now
work in all Hlas fields (API key entry!).

## 11. Audio input routing

User asked what happens with headphones/external mics. Answer: system default input. Built both
requested features: **MICROPHONE picker in Settings** (System default / Built-in always —
recommended with Bluetooth headphones to avoid HFP quality drop / specific device via CoreAudio
HAL enumeration, graceful fallback when unplugged, warm-engine restart on device change) and
**source badge in the pill** (icon by transport type + device name, shown only when NOT the
built-in mic).

## 12. Handoff (this commit)

AGENTS.md + docs/HANDOFF.md + this transcript + `tools/fakefn.swift`. Backlog for Codex in
HANDOFF.md — headline items: Keychain for API keys, Esc-to-cancel, device hot-plug refresh,
history window, multi-display overlay, app icon, Satoshi bundling, LLM cleanup pass, ElevenLabs
Scribe engine, Parakeet/FluidAudio local engine.

## Key measured numbers (M1 Pro, 16 GB)

- App bundle 2.4 MB; idle RAM ~38–46 MB.
- Model load 0.76 s (warm disk); 11 s audio → 1.65 s greedy / ~1.5 s beam-3 / ~1.1 s beam-5-dedup.
- Whisper model RAM ~800 MB, only while loaded; auto-unload default 180 s.
- Dictation UX: 4.5 s Czech clip → text in ~1.4 s (local turbo).

## Owner preferences observed (keep respecting these)

- Czech communication; terse, no fluff (caveman mode active in the original session).
- Design opinions are strong and specific — reference screenshots are briefs, contrast matters,
  "sexy minimal" = Raycast/Linear/Eloquent lineage + Eden green.
- Wants agents to visually verify UI work themselves (screenshot loop), not ask him to check.
- Values: no subscriptions, privacy-by-default, tiny footprint, Czech quality above all.
