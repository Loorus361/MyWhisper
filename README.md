<!-- Introduces MyWhisper, its requirements, local data, and development workflow. -->
# MyWhisper

A native macOS menu bar app for push-to-talk dictation in German and US English. Hold **Control + Option + S**, dictate, then release to insert text into the focused app.

Despite the name, this implementation uses Apple's speech APIs, not OpenAI Whisper. No OpenAI API key is required.

## Status and requirements

Early personal project, with no packaged GitHub release yet.

- macOS 26 or later.
- Swift 6.3 or later and a compatible macOS SDK, as required by `Package.swift`.
- Microphone, Speech Recognition and Accessibility permissions.
- Supported Apple speech models; initial preparation may download language assets.
- Apple Intelligence is optional. Its rewrite profiles require a supported, enabled and ready on-device model and supported language.

## Features

- Push-to-talk through a global keyboard shortcut.
- German and US English dictation.
- Deterministic **Clean** text processing.
- **Minimal**, **Technical**, **Rewrite** and **Custom** profiles using Apple Intelligence, with a Clean fallback when unavailable.
- Editable vocabulary and profile prompts.
- Local history with separate raw and processed text.
- Clipboard-based insertion and restoration of the previous clipboard.

## Build and test

```sh
swift build
swift test
```

These commands compile the app and run unit tests. They do not establish microphone recognition quality, permission behavior, or insertion reliability in every target application.

To build, sign and launch an app bundle:

```sh
./script/build_and_run.sh
```

The script stops any running MyWhisper process, replaces the generated bundle in `dist/`, signs it and launches it. It uses `MYWHISPER_CODESIGN_IDENTITY` if supplied, otherwise the first detected Apple Development identity, otherwise ad-hoc signing. Changes in signing may affect macOS permission recognition. `--verify` also launches the app; it is not a headless test.

## Local data and limitations

Settings and transcription history are JSON files under `~/Library/Application Support/com.carlosanderssohn.MyWhisper/`. History includes raw and final dictated text. Treat these files as private. The app uses Apple's on-device speech and Foundation Models integrations; model asset preparation may need a network connection.

Insertion temporarily places the transcript on the system clipboard and sends a paste command to the focused app. Verify the destination before dictating sensitive text. No guarantee is made for every application's paste handling.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md) and [CODEBASE.md](CODEBASE.md). Historical handoff notes may lag behind the source.

[MIT License](LICENSE).
