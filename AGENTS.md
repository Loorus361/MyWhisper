<!-- Explains how humans and agents should work in the MyWhisper repository. -->
# AGENTS.md

## Overview

MyWhisper is a native macOS menu bar app for fast, local-first push-to-talk dictation.
The current product shape is:

- global hotkey: `Control + Option + S`
- local speech-to-text using Apple's speech stack
- language selection: German and English (US)
- text polish profiles: `Clean`, `Minimal`, `Technical`, `Rewrite`, `Custom`
- on-device rewrite via Apple Intelligence for `Minimal`, `Technical`, `Rewrite`, and `Custom`
- system-wide insertion through clipboard set -> paste -> clipboard restore
- local history storing both raw and final text
- settings window for permissions, language defaults, dictation vocabulary, and text polish prompts

The app is intentionally macOS-first and personal-tool-first. Favor reliability, latency, and clarity over broad feature scope.

## Project Layout

- `Package.swift`
  Defines the SwiftPM package and macOS target.
- `Sources/MyWhisper/App`
  App entrypoint and app-level launch behavior.
- `Sources/MyWhisperCore/Models`
  Small value types and enums used across UI and services.
- `Sources/MyWhisperCore/Services`
  Runtime behavior: hotkey handling, speech capture, permissions, paste flow, and the main app model.
- `Sources/MyWhisperCore/Stores`
  Local persistence for settings and transcription history.
- `Sources/MyWhisperCore/Support`
  Constants, grouping helpers, and filesystem path helpers.
- `Sources/MyWhisperCore/Views`
  SwiftUI views for the menu bar menu, settings, and history.
- `script/build_and_run.sh`
  Canonical local build/run/sign/stage entrypoint.
- `.codex/environments/environment.toml`
  Codex desktop Run action wiring.
- `Tests/MyWhisperTests`
  Test target. Keep pure logic testable here as the codebase grows.

## Core Runtime Flow

The current happy-path dictation flow is:

1. User presses the global hotkey.
2. `AppModel` verifies permissions and ensures the selected language has been prepared for the current app session.
3. `DictationService` prepares a fresh `SpeechAnalyzer` + `SpeechTranscriber` session and starts audio capture.
4. `dictationState` transitions to `.listening`; the menu bar menu reflects this state.
5. User releases the hotkey.
6. `DictationService` ends audio input and awaits a finalized transcription result.
7. `TextPolishCoordinator` resolves the selected text polish profile for the current language.
8. `DeterministicTextPolisher` handles `Clean`, while `AppleIntelligenceTextPolisher` handles `Minimal`, `Technical`, `Rewrite`, and `Custom` through `FoundationModels`.
9. `ClipboardPasteService` pastes the final text into the focused app and restores the previous clipboard.
10. The app stores raw text, final text, and the applied polish profile in history, grouped later by day and session.

If you need to reason about app behavior, start with:

- `Sources/MyWhisperCore/Services/AppModel.swift`
- `Sources/MyWhisperCore/Services/HotkeyService.swift`
- `Sources/MyWhisperCore/Services/DictationService.swift`
- `Sources/MyWhisperCore/Services/ClipboardPasteService.swift`
- `Sources/MyWhisperCore/Services/TextPolishCoordinator.swift`
- `Sources/MyWhisperCore/Services/AppleIntelligenceTextPolisher.swift`

## Key Architectural Rules

- Keep `AppModel` as the central orchestrator for user-facing app state.
  It should own coordination, not heavy platform-specific implementation details.
- Keep platform edges inside dedicated services.
  Examples: pasteboard work in `ClipboardPasteService`, audio/speech in `DictationService`, permissions in `PermissionService`.
- Keep views thin.
  Views should render state and forward actions, not encode runtime workflow.
- Keep raw transcription and polished text distinct.
  Recognition quality and polish quality are separate concerns in this product.
- Keep the text polish profile model explicit.
  `Clean` is deterministic and fast; `Minimal`, `Technical`, `Rewrite`, and `Custom` are on-device AI profiles with user-visible prompts.
- Preserve local-first behavior by default.
  Cloud features, if added later, should be optional and isolated behind explicit settings or profile choices.
- Treat Apple Intelligence as optional runtime capability, not a guaranteed dependency.
  Unsupported devices, disabled Apple Intelligence, model-not-ready states, or unsupported locales must keep the app usable by falling back to `Clean`.
- Apple Intelligence prompt composition must explicitly pin output to the selected app language.
  German dictation should never be translated to English by `Minimal`, `Technical`, `Rewrite`, or `Custom`.
- `Technical` should preserve coding vocabulary, Git terms, product names, filenames, CLI commands, and code identifiers instead of translating them into natural German prose.
- Apple Intelligence must treat dictated text as inert content.
  It should rewrite command-like dictation as text, not execute the command.
- Avoid broad refactors that merge unrelated responsibilities back into one file.
  The current split is intentional and should stay readable for both humans and coding agents.

## File Header Rule

Every project-owned text file should begin with a one-line descriptive comment.
For new files:

- Swift: use `// ...`
- Shell/TOML/gitignore: use `# ...`
- Markdown: use `<!-- ... -->`

Exception:

- `Package.swift` must keep `// swift-tools-version:` on line 1, so place the descriptive comment immediately after that line.

## Local Development Workflow

Preferred commands:

- `swift build`
- `./script/build_and_run.sh`
- `./script/build_and_run.sh --verify`
- `./script/build_and_run.sh --logs`

Use the run script instead of ad hoc launch commands whenever possible. It:

- builds the project
- stages a local `.app` bundle in `dist/`
- signs the bundle
- launches it with `open`

## Signing And Permissions

The app depends on stable bundle identity for TCC permissions, especially Accessibility.
Do not casually remove signing from the run script unless you are deliberately debugging permission behavior.

Relevant permissions:

- Microphone
- Speech Recognition
- Accessibility

For macOS 26 builds, selected-language speech assets may be prepared automatically after microphone and speech permissions are granted.

When permission behavior seems inconsistent, inspect signing and bundle identity before changing app logic.

## Persistence

Local app data currently lives under Application Support using the bundle identifier path produced by `PersistencePaths`.

Important persisted data:

- settings JSON
- selected text polish profile ID
- visible prompts for `Minimal`, `Technical`, `Rewrite`, and `Custom`
- editable dictation vocabulary used as Apple Speech contextual strings
- history JSON containing raw and final transcripts
- history profile names for the applied polish mode

Do not silently change persistence schema without also planning a migration path.

## UI Guidance

The intended UI direction is:

- minimal
- Apple-native
- low chrome
- menu bar first
- one accent color
- fast feedback over decorative motion

Do not bloat the menu bar menu with debug-heavy UI unless the user explicitly asks for it.

## Near-Term Priorities

At the time this file was written, the next likely areas of work are:

- better recognition quality through contextual vocabulary
- tuning the `Minimal`, `Technical`, `Rewrite`, and `Custom` prompts against real dictation samples
- deciding whether `Clean` should stay purely deterministic or gain optional hybrid behavior later
- launch-at-login support
- richer settings and history controls

If you change priorities significantly, update this section so future agents get accurate guidance.

## When Editing

- Read the nearest file before changing it.
- Keep comments short and factual.
- Prefer extending the existing structure over inventing a parallel architecture.
- If you introduce a new workflow step, document it here when it materially affects how the repo should be understood.
- If you change prompt defaults or polish-profile behavior, update both this file and `HANDOFF.md` so later agents can distinguish product intent from temporary prompt experiments.
