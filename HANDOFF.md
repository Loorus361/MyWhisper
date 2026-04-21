<!-- Handoff summary for AI agents continuing the current MyWhisper migration work. -->
# MyWhisper Handoff

## Projektkontext

MyWhisper ist eine native macOS-Menubar-App fuer lokale Push-to-Talk-Diktate.
Die App ist jetzt bewusst auf `macOS 26` ausgerichtet.

Aktuelle Produktform:

- globaler Hotkey: `Control + Option + S`
- lokale Transkription mit Apples Speech-Stack
- Sprachen: Deutsch und Englisch (US)
- Text-Polish-Profile: `Clean`, `Minimal`, `Technical`, `Rewrite`, `Custom`
- Apple-Intelligence-Rewrite fuer `Minimal`, `Technical`, `Rewrite` und `Custom`
- final-only Einfuegen in andere Apps via Clipboard + `Cmd+V`
- Overlay mit Status, Live-Zustand und Pegelanzeige
- lokale History mit `rawText` und `finalText`
- Settings fuer Sprache, Berechtigungen, editierbares Diktat-Vokabular und sichtbare Text-Polish-Prompts

## Was in diesem Thread umgesetzt wurde

### 1. Speech-Migration auf macOS 26

Die App wurde von der alten `SFSpeechRecognizer`-Dictation-Implementierung auf den neuen lokalen Apple-Pfad umgestellt:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- `AnalysisContext`

Wichtige Punkte:

- `Package.swift` wurde auf `macOS 26` angehoben.
- `script/build_and_run.sh` nutzt jetzt ebenfalls `26.0` als Mindestversion.
- `DictationService` wurde komplett auf den neuen Speech-Pfad umgebaut.
- Asset-Preparation fuer die aktuell gewaehlte Sprache ist integriert.
- Es gibt keinen Legacy-Fallback mehr.

### 2. AppModel und UI-Status

`AppModel` verwaltet jetzt:

- `liveTranscriptPreview`
- `selectedLanguageModelStatus`
- vorbereitete Sprach-IDs statt frueherer Warm-up-Semantik

UI-Aenderungen:

- Settings zeigen den Sprachmodell-Status inklusive Retry bei Fehlern.
- Menubar-Status reflektiert Preparation/Download.
- Overlay kann Live-Preview anzeigen.

### 3. Audio-/Capture-Stabilisierung

Der groesste Runtime-Blocker war ein `AVAudioEngine`-Startfehler:

- `com.apple.coreaudio.avfaudio error -10868`

Ursache:

- der Capture-Graph war zu langlebig
- CoreAudio/Input-Device-Reconfiguration fuehrte zu einem ungueltigen Engine-Zustand

Loesung:

- pro Dictation-Session wird jetzt eine frische `AVAudioEngine` erstellt
- beim Stop/Cancel werden `stop`, `removeTap`, `reset` sauber ausgefuehrt
- dadurch startet Listening jetzt stabil bereits beim ersten Shortcut

### 4. Live-Transkription

Die Transcriber-Konfiguration wurde auf progressive Live-Ergebnisse angepasst:

- `reportingOptions: [.volatileResults, .fastResults]`

Das war noetig, weil nur `volatileResults` allein in der Praxis nicht die gewuenschte Live-Preview geliefert hat.

### 5. Text-Polish-Stack mit Apple Intelligence

Die App hat jetzt einen expliziten Text-Polish-Pfad statt nur eines simplen Cleanup-Schritts:

- `Clean` nutzt weiter lokalen deterministischen Cleanup
- `Minimal`, `Technical`, `Rewrite` und `Custom` nutzen `FoundationModels`
- die AI-Prompts sind in den Settings sichtbar und editierbar
- `Clean` zeigt seinen Regeltext read-only

Technische Struktur:

- `TextPolishCoordinator` entscheidet ueber Profilrouting und Fallback
- `DeterministicTextPolisher` implementiert `Clean`
- `AppleIntelligenceTextPolisher` kapselt `SystemLanguageModel` und `LanguageModelSession`
- `AppSettings` persistiert Profilauswahl und Prompt-Texte
- `Minimal` ist fuer sehr nahe Diktat-Bereinigung gedacht; `Technical` schuetzt Coding-/Git-/CLI-Begriffe; `Rewrite` darf staerker glaetten; `Custom` ist frei editierbar und hat einen professionellen Default

Wichtige Laufzeitregel:

- AI-Profile sind nicht garantiert verfuegbar
- Apple-Intelligence-Prompts pinnen die Ausgabe explizit auf die ausgewaehlte App-Sprache, damit deutsches Diktat nicht ins Englische kippt
- `Technical` soll technische Begriffe wie Commit, Branch, Pull Request, Dateinamen, Befehle und Code-Identifier nicht eindeutschen
- Diktattext wird im AI-Prompt als reiner Inhalt markiert; Apple Intelligence darf darin enthaltene Aufgaben nicht ausfuehren
- bei nicht verfuegbarem Apple-Intelligence-Zustand faellt die Auswahl auf `Clean` zurueck
- beim eigentlichen AI-Generierungsfehler bricht der aktuelle Dictation-Durchlauf weiterhin mit Fehleranzeige ab statt still auf `Clean` zu wechseln

## Aktueller funktionaler Stand

### Funktioniert

- App startet und baut sauber
- Sprachmodell-Preparation funktioniert
- Listening startet beim ersten Shortcut
- Pegel schlaegt aus
- Loslassen finalisiert den Text
- finaler Text wird in andere Apps eingefuegt
- mehrere Shortcut-Durchlaeufe hintereinander sind stabil
- Text-Polish-Profile werden persisted und bei alten Settings migriert
- `Minimal`, `Technical`, `Rewrite` und `Custom` koennen in den Settings direkt ueber ihre Prompts angepasst werden
- das editierbare Diktat-Vokabular wird persisted und als `AnalysisContext.contextualStrings` an Apple Speech uebergeben

### Funktioniert, aber ist gestalterisch noch nicht gut

- Overlay wurde modernisiert, ist aber noch nicht auf dem gewuenschten Apple-/Liquid-Glass-Niveau
- Live-Text wirkt noch nicht wirklich "fluessig"
- Pegelmeter wurde vom Nutzer explizit als unbefriedigend bewertet

Wichtig:

- Der Nutzer moechte den UI-Feinschliff vorerst nicht weiter vertiefen.
- Funktion geht momentan vor perfekter Optik.

## Nutzerfeedback aus dem aktuellen Stand

Der Nutzer hat den letzten Overlay-Stand so eingeordnet:

- Richtung stimmt grundsaetzlich
- Live-Text laeuft noch nicht schoen fluessig
- Pegelanzeige ist gestalterisch nicht akzeptabel
- vorerst Fokus lieber auf andere Themen statt Overlay-Polish

## Wichtige Dateien

Zentrale Dateien fuer den aktuellen Stand:

- `Package.swift`
- `script/build_and_run.sh`
- `AGENTS.md`
- `Sources/MyWhisper/Services/AppModel.swift`
- `Sources/MyWhisper/Services/TextPolishCoordinator.swift`
- `Sources/MyWhisper/Services/AppleIntelligenceTextPolisher.swift`
- `Sources/MyWhisper/Models/TextPolishProfile.swift`
- `Sources/MyWhisper/Services/DictationService.swift`
- `Sources/MyWhisper/Services/OverlayWindowController.swift`
- `Sources/MyWhisper/Views/OverlayView.swift`
- `Sources/MyWhisper/Views/AudioLevelMeterView.swift`
- `Sources/MyWhisper/Views/LiveTranscriptFlowView.swift`
- `Sources/MyWhisper/Views/SettingsView.swift`
- `Sources/MyWhisper/Models/LanguageModelStatus.swift`
- `Tests/MyWhisperTests/MyWhisperTests.swift`

## Verifikation

Dieser Stand wurde bereits erfolgreich verifiziert mit:

- `swift build`
- `swift test`
- `./script/build_and_run.sh --verify`

Fuer den neuen Text-Polish-Stack wurde lokal verifiziert:

- `swift build`
- `swift test`

Noch offen:

- reale manuelle Rewrite-Verifikation mit aktivem Apple Intelligence auf diesem Mac

## Code-Qualitaets-Refactoring (2026-04-21)

Ein vollstaendiger Code-Audit wurde durchgefuehrt und alle relevanten Befunde behoben.
Alle Aenderungen sind in `main` gemergt und gepusht.

### Umgesetzte Verbesserungen

- **HistoryStore**: `save()` wirft jetzt und wird in `AppModel` separat vom Paste-Flow abgefangen — ein Speicherfehler zeigt keinen Fehler mehr, wenn der Text bereits erfolgreich eingefuegt wurde
- **AppSettingsStore**: Fehler beim Laden und Speichern werden via OSLog protokolliert statt lautlos verworfen
- **TextPolishProfile**: Force-Unwrap durch `preconditionFailure` mit erklaerenden Meldungen ersetzt
- **PersistencePaths**: Force-Unwrap auf `FileManager.urls` durch `guard/preconditionFailure` ersetzt
- **AppConstants**: Magic Numbers (350ms Clipboard-Delay, 4096 Audio-Buffer) als benannte Konstanten extrahiert
- **DictationService**: Audio-Hardware-Validierung aus `startCapture()` in `makeAudioSetup(for:)` ausgelagert; `@unchecked Sendable`-Begründung kommentiert

### Bewusst zurueckgestellte Punkte

- **Testabdeckung**: 15 Tests fuer ~8000 LOC ist wenig. Wichtige Pfade ohne Tests: `AppModel`, `HistoryStore`/`AppSettingsStore`, `ClipboardPasteService`, Fehler-Handling in `DictationService`. Zurueckgestellt, weil plattformspezifisches Mocking (AVAudioEngine, Speech-APIs) ein eigenes Projekt ist.
- **L1** (duplizierte Permission-Checks in `ensureReadyForDictation` vs. `schedulePreparationIfPossible`): Die beiden Funktionen tun strukturell Verschiedenes — Extraktion wuerde Verwirrung erzeugen statt Klarheit.
- **L3** (`hotkeyDisplay` String von der echten Hotkey-Definition entkoppelt): Nur kosmetisch, kein Risiko.

## Offene Baustellen

### Hochprioritaer

- keine akute hochprioritaere Runtime-Blockade mehr bekannt

### Mittel

- Overlay/UI-Qualitaet weiter verbessern, wenn wieder Fokus auf Design gelegt wird
- Live-Transkriptionsdarstellung eleganter machen
- Pegelmeter komplett neu denken, nicht nur kosmetisch anpassen

### Spaeter moeglich

- Testabdeckung ausbauen (siehe oben)
- weitere Optimierung der Text-Polish-Prompts anhand echter Diktatbeispiele
- echte Runtime-Verifikation des Apple-Intelligence-Pfads auf einer Maschine mit aktivem Apple Intelligence
- breitere Settings-/History-Verbesserungen
- Launch-at-login oder weitere Produktfeatures

## Empfehlungen fuer den naechsten Agenten

Wenn du die Arbeit fortsetzt:

1. Lies zuerst `AGENTS.md` und `CODEBASE.md`.
2. Lies danach `AppModel.swift` und `DictationService.swift`.
3. Behandle den aktuellen SpeechAnalyzer-Pfad als die neue einzige lokale Backend-Implementierung.
4. Lies danach auch den Text-Polish-Pfad in `TextPolishCoordinator.swift` und `AppleIntelligenceTextPolisher.swift`.
5. Fasse den Overlay-Stand nicht als final auf.
6. Regressionsrisiko aktuell vor allem bei:
   - `AVAudioEngine`-Session-Lifecycle
   - Apple-Intelligence-Availability und Prompt-Verhalten
   - Live-Preview-UI
   - Paste-Finalisierung nach Hotkey-Release

## Git-Stand

Working Tree ist sauber. Alle Aenderungen sind commitet und auf `origin/main` gepusht.
