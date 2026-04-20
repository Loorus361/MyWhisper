<!-- Handoff summary for AI agents continuing the current MyWhisper migration work. -->
# MyWhisper Handoff

## Projektkontext

MyWhisper ist eine native macOS-Menubar-App fuer lokale Push-to-Talk-Diktate.
Die App ist jetzt bewusst auf `macOS 26` ausgerichtet.

Aktuelle Produktform:

- globaler Hotkey: `Control + Option + S`
- lokale Transkription mit Apples Speech-Stack
- Sprachen: Deutsch und Englisch (US)
- final-only Einfuegen in andere Apps via Clipboard + `Cmd+V`
- Overlay mit Status, Live-Zustand und Pegelanzeige
- lokale History mit `rawText` und `finalText`
- Settings fuer Sprache und Berechtigungen

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

## Aktueller funktionaler Stand

### Funktioniert

- App startet und baut sauber
- Sprachmodell-Preparation funktioniert
- Listening startet beim ersten Shortcut
- Pegel schlaegt aus
- Loslassen finalisiert den Text
- finaler Text wird in andere Apps eingefuegt
- mehrere Shortcut-Durchlaeufe hintereinander sind stabil

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

## Offene Baustellen

### Hochprioritaer

- keine akute hochprioritaere Runtime-Blockade mehr bekannt

### Mittel

- Overlay/UI-Qualitaet weiter verbessern, wenn wieder Fokus auf Design gelegt wird
- Live-Transkriptionsdarstellung eleganter machen
- Pegelmeter komplett neu denken, nicht nur kosmetisch anpassen

### Spaeter moeglich

- weitere Optimierung der Text-Polish-Logik
- breitere Settings-/History-Verbesserungen
- Launch-at-login oder weitere Produktfeatures

## Empfehlungen fuer den naechsten Agenten

Wenn du die Arbeit fortsetzt:

1. Lies zuerst `AGENTS.md`.
2. Lies danach `AppModel.swift` und `DictationService.swift`.
3. Behandle den aktuellen SpeechAnalyzer-Pfad als die neue einzige lokale Backend-Implementierung.
4. Fasse den Overlay-Stand nicht als final auf.
5. Regressionsrisiko aktuell vor allem bei:
   - `AVAudioEngine`-Session-Lifecycle
   - Live-Preview-UI
   - Paste-Finalisierung nach Hotkey-Release

## Noch nicht commitet

Zum Zeitpunkt dieser Uebergabe gibt es lokale Aenderungen im Working Tree, inklusive neuer Dateien:

- `Sources/MyWhisper/Models/LanguageModelStatus.swift`
- `Sources/MyWhisper/Views/LiveTranscriptFlowView.swift`
- mehrere geaenderte Service-, View-, Test- und Build-Dateien

Vor weiterem Umbau zuerst `git status` pruefen und keine fremden Aenderungen verwerfen.
