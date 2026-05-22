# Transcriber

A macOS menu bar app that turns speech into text locally and pastes it directly into whatever you're typing in.

Press the hotkey once to start recording, speak, then press it again to stop.

---

## What it does

1. Records your microphone via a global hotkey
2. Strips silence with Voice Activity Detection
3. Transcribes on-device using Parakeet TDT (via FluidAudio)
4. Optionally refines the transcript with a local LLM (Ollama + qwen3:8b)
5. Pastes the result into the active text field

Nothing leaves your Mac.

---

## Requirements

- macOS 14.6 (Sonoma) or later
- Microphone permission
- Accessibility permission — required for the global hotkey and the paste
- [Ollama](https://ollama.com) with `qwen3:8b` — only if you want Quick or Deep refinement

---

## Setup

### 1. Pull the model (refinement only)

```sh
brew install ollama
ollama pull qwen3:8b
```

Skip this if you plan to run with refinement set to **Off**.

### 2. Build and run

Open `Transcriber.xcodeproj` in Xcode, select your Mac as the destination, and press `⌘R`.

On first launch:
- Grant **Microphone** access when prompted.
- Grant **Accessibility** access in **System Settings → Privacy & Security → Accessibility**, then click **Retry** in the menu.

---

## Usage

| Action | Default |
|--------|---------|
| Start / stop recording | `⌃⌥T` |
| Change shortcut | Click **Shortcut:** in the menu |
| Copy last transcript | **Copy Last Transcript** in the menu |

Press the hotkey to start, speak, then press it again to stop. VAD trims silence from the captured audio before it reaches the transcription model. The transcript is pasted into the active field.

---

## Refinement modes

| Mode | What it does |
|------|-------------|
| **Off** | Raw ASR output pasted immediately, no Ollama required |
| **Quick** | Fixes punctuation, capitalisation, homophones, and run-on sentences |
| **Deep** | Same as Quick with extended chain-of-thought reasoning (`think: true`), handles self-corrections and ambiguous phrasing more reliably |

Both Quick and Deep resolve spoken corrections automatically. If you say *"I'm 32 years old, sorry, 28"* the output is *"I'm 28 years old."*

The Ollama model is kept loaded in memory between recordings so refinement adds minimal latency after the first use.

---

## How it works

```
Microphone
    │
    ▼
AVAudioEngine          captures raw audio to a temp WAV file
    │
    ▼
VAD (FluidAudio)       detects speech segments, strips silence,
                       joins segments with short spacers
    │
    ▼
Peak normalisation     scales audio to 90% peak (vDSP) before ASR
    │
    ▼
Parakeet TDT ASR       on-device transcription, no network call
    │
    ▼
Ollama / qwen3:8b      optional local LLM refinement
    │
    ▼
CGEvent paste          injects ⌘V into the active application
```

**Parallel model loading** — VAD and ASR models load concurrently at startup via `async let`, keeping cold-start time to a minimum.

**Job cancellation** — each transcription run is tagged with a UUID. If recording starts again before the previous job finishes, the stale result is silently discarded.

**No Dock icon** — the app runs as a pure menu bar agent (`LSUIElement = true`).

---

## Tech

- Swift · SwiftUI (`@Observable`, `MenuBarExtra`, `async/await`)
- [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.14.5 — Parakeet TDT ASR and VAD
- Ollama REST API — local LLM inference at `localhost:11434`
- CoreGraphics event tap — system-wide hotkey interception
- ServiceManagement — launch at login
- Accelerate / vDSP — audio peak normalisation

---

## License

MIT