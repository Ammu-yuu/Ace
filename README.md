# Ace — a macOS desktop pet with a voice and a brain

Ace is a Shimeji-style floating desktop character for macOS. It sits on top of
your other windows, talks with you (voice in / voice out), and acts as a small
"second brain" (spelling help, conversation, reminders).

Built **incrementally** — see the step plan below. This repo is currently at
**Step A (project setup)**.

## Requirements
- macOS 13+
- Swift toolchain (comes with Xcode or the Command Line Tools) — verify with `swift --version`

## Run (dev)
```bash
swift run
```
A small floating "Ace" pet appears near the bottom-right of your screen, stays
on top of other windows, and can be dragged anywhere. No Dock icon (it runs as
an accessory app). Quit from the terminal with `Ctrl-C`.

## Build a real .app bundle
```bash
./scripts/build_app.sh
open build/Ace.app
```
The bundle is needed (not just `swift run`) once voice is enabled, because macOS
grants microphone / speech-recognition permission to a signed bundle identity.

## Project layout
```
Package.swift            SwiftPM manifest
Sources/AcePet/
  main.swift             app entry point (accessory app, no Dock icon)
  App/                   UI — floating window + pet view          (the "/app")
  Brain/                 brain adapter interface + stub           (the "/brain")
  Voice/                 speech-to-text / text-to-speech protocols(the "/voice")
  Reminders/             reminder scheduler protocol              (the "/reminders")
assets/                  drop-in sprites (placeholder for now)    (the "/assets")
scripts/
  build_app.sh           packages Sources → build/Ace.app
  Info.plist             bundle metadata + mic/speech usage strings
```

## Design choices
- **Native SwiftUI/AppKit** (not Electron) because it's macOS-only and gives us
  free, on-device voice: Apple `Speech` for STT and `AVSpeechSynthesizer` for
  TTS — **no API keys, nothing sent to the cloud** for voice.
- **Pluggable brain.** The UI never talks to a model directly; it talks to a
  `BrainAdapter`. Today that's a `StubBrain` that echoes. In Step D we swap in a
  real backend (Claude API, a local model, or OpenClaw) without touching the UI.
- **No copyrighted art.** The pet is drawn in code. See `assets/README.md` to add
  your own licensed/original sprites.

## Secrets
Keys live in environment variables / `.env` (gitignored). See `.env.example`.
Voice needs no keys; only the optional real brain backend (Step D) might.

## Incremental build plan
- [x] **Step A** — Project setup, run/build instructions ← *you are here*
- [ ] **Step B** — Floating window + idle sprite animation (placeholder frames)
- [ ] **Step C** — Speech-to-text + speech bubble + mock brain
- [ ] **Step D** — Real brain adapter (Claude API / OpenClaw) or documented hook
- [ ] **Step E** — Text-to-speech
- [ ] **Step F** — Conversation history + spelling-assist mode
- [ ] **Step G** — Reminders (local notifications; "in X min" / "at HH:MM")
- [ ] **Step H** — Pet states: idle / listening / thinking / speaking
