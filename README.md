<div align="center">

![GhostlyAssistant](docs/images/banner.png)

**English** · [Русский](README.ru.md)

**A vendor-agnostic AI assistant for calls on macOS.** It listens to the call, transcribes speech on-device with Whisper,
notices when someone asks a question and streams the language model's answer into a floating chat that stays out of screen sharing.

</div>

---

## What it is

GhostlyAssistant lives in the macOS menu bar. During a call it:

- **listens to system audio** — what the other people say in Zoom, Meet, Teams and the like;
- **transcribes speech on your Mac** with Whisper (WhisperKit), offline;
- **notices when a question is asked**, takes a screenshot and sends the language model the question, the recent conversation and the image;
- **streams the answer** into a floating chat, in the language the question was asked in;
- **knows your material** — you can attach a knowledge base (PDF, Word, plain text, Markdown, images).

The window carries the macOS "exclude from screen capture" flag, so standard screen-sharing apps don't show it.
This is a public system feature; where it doesn't apply, settings explain how to keep the chat out of the stream
(share a single window or a different display).

## Model providers

GhostlyAssistant is vendor-agnostic: answers come from the language model you choose.

| Provider | Status |
|---|---|
| Anthropic Claude | ✅ supported |
| OpenAI | 🚧 in progress |
| Google Gemini | 🚧 in progress |
| Local models — Ollama, LM Studio, vLLM | 🚧 in progress (OpenAI-compatible API) |

## Screenshots

| Chat during a call — dark theme | Settings — light theme |
|---|---|
| ![Chat](docs/images/chat-en.png) | ![Settings](docs/images/settings-en.png) |

## Features

- **Light and dark themes** — minimal, no glass; or follow the system.
- **Live chat** with "Recognizing → Thinking → Answering" stages, and answer latency.
- **Answer a skipped line** — if the assistant decided a line wasn't a question, answer it with a click or `⌥⌘A`.
- **Ask your own question** — typed or spoken into the microphone (the 🎤 button, transcribed by the same Whisper).
- **Knowledge base** — a small one goes into the context whole, a large one is searched with tools (BM25 + opening PDF pages).
- **Model choice** — for Claude the list comes from the Models API for your key.
- **Whisper model choice** — a catalog of 9 variants with download, cancel, switch and delete.
- **Recognition languages** — set separately for the other people on the call and for your own voice.
- **Model parameters** — thinking, effort and maximum answer length; each one is labelled where it affects answer speed.
- **Answer style** — brief / balanced / detailed, plus your own instructions for the prompt.
- **English and Russian interface**, switchable on the fly; text size; launch at login.
- **Hotkeys** — `⌥⌘H` hides/shows the chat, `⌥⌘A` answers the last skipped line.

## How it's built

Logic that can be covered by automated tests lives in the `AssistantCore` Swift package (Swift Testing, 137 tests):
cutting audio into utterances, Claude response types and streaming parser, request building, the assistant pipeline,
the knowledge base and search. The `App/` target holds only what is tied to the OS: audio and screen capture
(ScreenCaptureKit), Whisper, the floating window (AppKit), the interface (SwiftUI) and settings.

Answers go through the Claude Messages API over plain HTTP with SSE parsing — there is no official Swift SDK.

## Requirements

| | Minimum |
|---|---|
| Mac | **Apple Silicon (M1 or newer).** Intel Macs are not supported: the app is built for arm64 only, and Whisper runs on the Neural Engine. |
| macOS | **26 or later.** |
| Disk space | ~7 MB for the app plus the speech model: **~630 MB** for the default one, from 77 MB to 3.1 GB depending on the model you pick. |
| Internet | Needed for answers (the model provider's API) and to download the speech model once. Speech recognition itself works offline. |
| Model provider | Your own **Claude API key**. |
| Permissions | **Screen & System Audio Recording** (call audio and the screenshot) and **Microphone** (only for asking by voice). |

**Which Whisper model fits your Mac** — according to [argmax's support table](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/main/config.json):

| Model | Size | M1 | M2 / M3 / M4 and newer |
|---|---|---|---|
| Large v3 Turbo, compressed — **default** | 627 MB | ✅ | ✅ |
| Large v3, compressed | 948 MB | ✅ | ✅ |
| Large v3 Turbo | 1.6 GB | — | ✅ |
| Large v3 | 3.1 GB | ✅ | ✅ |
| Small | 486 MB | ✅ | ✅ |
| Base | 147 MB | ✅ | ✅ |
| Tiny | 77 MB | ✅ | ✅ |
| Small, compressed · Medium | 217 MB · 1.5 GB | not in argmax's table — may work, untested | |

The default model is the one argmax recommends for multilingual accuracy, and it runs on every supported Mac.

## Install

See [Requirements](#requirements) first.

1. Download `GhostlyAssistant-<version>.dmg` from [Releases](../../releases) and drag the app into Applications.
2. The build is signed with a developer certificate but not notarized, so on first launch macOS says it can't verify
   the developer. Open **System Settings → Privacy & Security** and click **Open Anyway** — or remove the quarantine
   flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/GhostlyAssistant.app
   ```

Then continue with [First launch](#first-launch).

Updates install from inside the app. It checks at launch and once a day; when a new version is out, a window shows
what changed with **Install**, **Remind Me Later** and **Skip This Version**. Check by hand from the menu bar icon →
**Check for Updates…** or in settings → **Updates**. Versions up to 1.3.0 can't update themselves — install the next
release from the DMG once.

## Build from source

You need macOS 26+, Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project GhostlyAssistant.xcodeproj -scheme GhostlyAssistant -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/GhostlyAssistant.app
```

The app is signed with an Apple Development certificate — set your own team in `project.yml`
(`DEVELOPMENT_TEAM`), otherwise the screen recording permission is lost after every rebuild.

Installer DMG (needs `pip install dmgbuild`): `scripts/make-dmg.sh` → `build/release/GhostlyAssistant-<version>.dmg`.

Core tests:

```bash
swift test --package-path Packages/AssistantCore
```

### Publishing a release

Updates come through [Sparkle](https://sparkle-project.org). The app reads
`https://github.com/viacheslav-rashchevskyi/GhostlyAssistant/releases/latest/download/appcast.xml`, and every update
is signed with an EdDSA key whose public half is `SUPublicEDKey` in `App/Info.plist`. The private half lives in the
login Keychain of the Mac that publishes; keep a backup
(`build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x <file>`, restore with `-f <file>`) — without
it, installed apps won't accept new updates.

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `App/Info.plist`. Sparkle compares `CFBundleVersion`,
   so it must grow with every release.
2. Build the Release app (command above) and the DMG: `scripts/make-dmg.sh`.
3. Create the GitHub release `v<version>` with the notes as usual, under a `## What's changed` heading.
4. `scripts/publish-update.sh` takes that section from the release, signs the DMG, writes the appcast and uploads
   both files to the release. Pass a notes file to use it instead of the release body, and `--no-upload` to only
   write `build/updates/appcast.xml`.

To try an update locally, serve a test appcast and point an older build at it:
`GHOSTLY_UPDATE_FEED=http://localhost:8765/appcast.xml`.

## First launch

On first launch a setup guide walks you through everything; the chat appears when it's done.

![Setup guide](docs/images/onboarding.png)

1. **Welcome** — interface language and theme; the speech model (~600 MB) starts downloading in the background.
2. **Claude API key** — checked right away and stored only in the macOS Keychain. You can skip it and add it later.
3. **Screen & System Audio Recording** — the guide opens the right System Settings pane and restarts the app for you.
4. **Languages** — of the other people on the call and of your own voice.
5. **Speech model** — waits for the download; you can pick another model.
6. **How to use** — hotkeys, the microphone, an optional knowledge base and a test question.

To run it again: menu bar icon → **Setup guide…**

## Debugging

```bash
# transcribe an audio file and print the text with timings
GhostlyAssistant --transcribe path/to/audio.aiff

# run one question through the whole pipeline (key and knowledge base come from settings)
GhostlyAssistant --ask "Question text"
```

## Stack

Swift 6 · SwiftUI + AppKit · ScreenCaptureKit · WhisperKit · PDFKit · Claude Messages API · XcodeGen

---

<div align="center">
<sub>A personal macOS project. Speech recognition and answers run on WhisperKit and the Claude API.</sub>
</div>
