# MyWhisper — Codebase Analysis

> Machine-readable reference for AI agents. Companion to AGENTS.md (developer rules) and HANDOFF.md (project status).  
> Last updated: 2026-04-23

---

## Quick Facts

| Property | Value |
|----------|-------|
| Language | Swift 6 (strict concurrency) |
| Platform | macOS 26+ |
| Build system | SwiftPM (no Xcode project) |
| Build command | `./script/build_and_run.sh` |
| Output | `dist/MyWhisper.app` |
| Bundle ID | `com.carlosanderssohn.MyWhisper` |
| Architecture | MVVM + Clean Services |
| Third-party deps | None — pure Apple frameworks |
| Tests | Swift Testing tests in `Tests/MyWhisperTests/` |

---

## Directory Structure

```
MyWhisper/
├── Package.swift                        SwiftPM manifest (macOS 26, Swift 6)
├── AGENTS.md                            Developer rules and guidelines
├── HANDOFF.md                           Project status and context (German)
├── CODEBASE.md                          This file — AI agent reference
├── script/
│   └── build_and_run.sh                 Build, sign, launch script
├── Sources/MyWhisper/                   Thin app-entry-point target
│   └── App/
│       ├── AppDelegate.swift            NSApp launch configuration
│       └── MyWhisperApp.swift           SwiftUI entry point, MenuBarExtra
├── Sources/MyWhisperCore/               Library target (shared by app and previews)
│   ├── Models/                          10 value types (enums, structs)
│   ├── Services/                        9 classes (AppModel + 8 service classes)
│   ├── Stores/                          2 JSON persistence files
│   ├── Support/                         4 utility files
│   └── Views/                           3 SwiftUI view components
└── Tests/MyWhisperTests/
    └── MyWhisperTests.swift             15 unit tests
```

---

## Key Files

### Coordinator
| File | Lines | Role |
|------|-------|------|
| `Sources/MyWhisperCore/Services/AppModel.swift` | ~490 | Central `@Observable @MainActor` coordinator. Manages hotkey, permissions, dictation lifecycle, text polish routing, history, UI state. |

### Services
| File | Lines | Role |
|------|-------|------|
| `Sources/MyWhisperCore/Services/DictationService.swift` | 667 | Audio capture pipeline. Creates fresh `AVAudioEngine` + `SpeechAnalyzer` + `SpeechTranscriber` per session. Emits audio level, live transcript, language model status. |
| `Sources/MyWhisperCore/Services/TextPolishCoordinator.swift` | 56 | Routes text through deterministic (`Clean`) or Apple Intelligence (`Minimal`/`Technical`/`Rewrite`/`Custom`) backend. Handles availability checks and fallback. |
| `Sources/MyWhisperCore/Services/TextPolisher.swift` | 44 | Deterministic polisher. Removes language-specific filler words (DE: äh/ähm, EN: uh/um), capitalizes, adds punctuation. |
| `Sources/MyWhisperCore/Services/AppleIntelligenceTextPolisher.swift` | 94 | Apple Intelligence polisher. `SystemLanguageModel` + per-request `LanguageModelSession`. Checks device eligibility and locale support. |
| `Sources/MyWhisperCore/Services/HotkeyService.swift` | 73 | Global hotkey via `NSEvent.addGlobalMonitorForEvents`. Default: `Control + Option + S`. `@MainActor`, key-repeat-safe, `isKeyDown` guard prevents stray releases. |
| `Sources/MyWhisperCore/Services/ClipboardPasteService.swift` | 107 | Snapshots clipboard → sets text → posts `Cmd+V` via `CGEvent` → restores clipboard after 350ms. |
| `Sources/MyWhisperCore/Services/PermissionService.swift` | 80 | TCC permission management: microphone, speech recognition, accessibility. Async request methods. |

### Stores
| File | Role |
|------|------|
| `Sources/MyWhisperCore/Stores/AppSettingsStore.swift` | JSON at `~/Library/Application Support/com.carlosanderssohn.MyWhisper/settings.json` |
| `Sources/MyWhisperCore/Stores/HistoryStore.swift` | JSON at `~/Library/Application Support/com.carlosanderssohn.MyWhisper/history.json` |

### Models
| File | Type | Purpose |
|------|------|---------|
| `AppLanguage.swift` | Enum | German, English US with locale identifiers |
| `AppSettings.swift` | Struct (Codable) | Language, profile selection, separate system/style prompts, dictation vocabulary. Includes migration logic. |
| `DictationState.swift` | Enum | idle / preparing / listening / processing / inserted / error(String) |
| `LanguageModelStatus.swift` | Enum | idle / checking / downloading(Double?) / ready / failed(String) |
| `AppleIntelligenceStatus.swift` | Enum | available / unavailable(5 reasons) |
| `PermissionState.swift` | Enum + Struct | notDetermined / granted / denied + PermissionSnapshot |
| `TextPolishProfile.swift` | Struct | id, name, backend, systemPrompt, prompt. Defaults and merge logic. |
| `TextPolishBackend.swift` | Enum | deterministic / appleIntelligence |
| `TextPolishProfileID.swift` | Enum | clean / minimal / technical / rewrite / custom |
| `TranscriptionRecord.swift` | Struct (Codable) | id, timestamp, language, profileName, rawText, finalText |

### Views
| File | Role |
|------|------|
| `Sources/MyWhisper/App/MyWhisperApp.swift` | App entry, `MenuBarExtra` with language badge, history window (1040×680), settings sheet |
| `Sources/MyWhisperCore/Views/MenuBarContentView.swift` | Popup: language picker, status text, last inserted text, links |
| `Sources/MyWhisperCore/Views/SettingsView.swift` | Language, profile, Apple Intelligence status, permission rows, model retry |
| `Sources/MyWhisperCore/Views/HistoryWindowView.swift` | `NavigationSplitView`: day-grouped sidebar + raw/final text detail |

---

## Core Data Flow

```
1. User holds Control+Option+S
   └─ HotkeyService.onPressed() → AppModel.handleHotkeyPressed()

2. Permission check (microphone, speech, accessibility)
   └─ If missing → request → presentError() → scheduleStateReset()

3. DictationService.startCapture(language:contextualStrings:)
   ├─ Fresh AVAudioEngine + SpeechAnalyzer + SpeechTranscriber created
   ├─ Settings vocabulary passed to AnalysisContext.contextualStrings
   ├─ Audio tap (4096-frame buffer) installed on input node
   ├─ dictationState = .listening
   └─ Async loop: buffers → analyzer → finalized + volatile segments

4. User releases Control+Option+S
   └─ HotkeyService.onReleased() → AppModel.handleHotkeyReleased()

5. DictationService.finishCapture()
   ├─ Engine stopped, tap removed, engine reset
   ├─ Analyzer finalized, all results consumed
   └─ Returns rawText (concatenated finalized segments)

6. TextPolishCoordinator.polish(rawText, language, profile)
   ├─ Clean profile:  DeterministicTextPolisher
   │  └─ Trim → remove fillers → capitalize → add punctuation → finalText
   └─ AI profile:     AppleIntelligenceTextPolisher
      └─ SystemLanguageModel.availability → LanguageModelSession → finalText
      (Falls back to Clean if Apple Intelligence unavailable)

7. ClipboardPasteService.paste(finalText)
   ├─ Snapshot current clipboard
   ├─ Set finalText to NSPasteboard
   ├─ Post CGEvent: Cmd+V keydown+keyup to frontmost app
   └─ Async: restore original clipboard after 350ms

8. TranscriptionRecord(id, timestamp, language, profileName, rawText, finalText)
   └─ history.insert(record, at: 0) → HistoryStore.save() → history.json

9. dictationState = .inserted → scheduleStateReset(after: 1.0s) → .idle
```

---

## Language Model Preparation Flow

```
AppModel.init() or language change
→ schedulePreparationIfPossible(for: language)
→ DictationService.prepare(language:)
  ├─ SpeechTranscriber created for locale
  ├─ AssetInventory.status(forModules:)
  │  ├─ .installed → onLanguageModelStatus(.ready)
  │  └─ .downloading / not installed → AssetInstallationRequest
  │     → onLanguageModelStatus(.downloading(progress)) loop
  │     → await downloadAndInstall()
  └─ On failure → onLanguageModelStatus(.failed(message))

AppModel.selectedLanguageModelStatus updated
→ Menu shows: Ready / Checking / Downloading X% / Failed
→ preparedLanguageIDs tracks cached languages
```

---

## Text Polish Availability & Fallback

```
User selects Minimal/Technical/Rewrite/Custom profile
→ TextPolishCoordinator.availability(for: profile, language:)
  → AppleIntelligenceTextPolisher.availability(for: language)
    ├─ SystemLanguageModel.availability check
    ├─ Locale support check
    └─ Returns .available or .unavailable(reason)

If unavailable:
  ├─ AppModel shows message: "[Profile] switched to Clean because [reason]"
  └─ Resolved profile = .clean

If available:
  └─ Profile saved to settings.json
```

---

## Frameworks & APIs

| Framework | Used For |
|-----------|---------|
| AppKit | NSApplication, NSPasteboard, NSScreen, NSEvent (global key monitors) |
| SwiftUI | Views, @Observable, MenuBarExtra |
| CoreGraphics | CGEvent for keyboard simulation (Cmd+V) |
| AVFoundation | AVAudioEngine, AVAudioInputNode, AVAudioPCMBuffer |
| Speech | SFSpeechRecognizer (permission check only) |
| FoundationModels | SystemLanguageModel, LanguageModelSession |
| OSLog | Debug logging via Logger |
| Testing | @Test macro for unit tests |

**macOS 26 Speech APIs:** `SpeechAnalyzer`, `SpeechTranscriber`, `AnalysisContext`, `AssetInventory`, `AssetInstallationRequest`

---

## Architectural Rules (Summary from AGENTS.md)

1. Views are thin and data-driven — no business logic in views
2. Services own all platform-specific code
3. AppModel coordinates, does not implement
4. Apple Intelligence is optional — deterministic fallback always available
5. One file header comment per file (1-line description)
6. Swift 6 strict concurrency — use `@MainActor` and `Sendable` correctly
7. Persist via JSON only (no CoreData, no CloudKit)

---

## Permissions Required

| Permission | API | Usage |
|------------|-----|-------|
| Microphone | `AVCaptureDevice.requestAccess` | Audio capture for dictation |
| Speech Recognition | `SFSpeechRecognizer.requestAuthorization` | On-device transcription |
| Accessibility | `AXIsProcessTrusted` | Posting `Cmd+V` to frontmost app |

---

## Build & Run

```bash
# Build and launch
./script/build_and_run.sh

# Debug mode (keeps terminal attached)
./script/build_and_run.sh debug

# View logs
./script/build_and_run.sh logs

# Run tests
swift test
```
