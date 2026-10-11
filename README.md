# Moodiary-Pro

Deutsche Community-Version von [Moodiary](https://github.com/ZhuJHua/moodiary)
(Branch `develop`) – mit OneDrive-Sync und Komfortfunktionen. Alle Änderungen
stehen in [CHANGELOG-Moodiary.md](./CHANGELOG-Moodiary.md) (liegt auch jedem
Release bei).

## Was ist anders als im Original?

- **Deutsch**: komplette Oberfläche, Editor und Einstellungen (Du-Form)
- **OneDrive** als Cloud-Sync neben WebDAV/S3/LAN (Anmeldung per
  Microsoft-Browserfenster; eigene Azure-Client-ID eintragbar)
- **Assistent**: Prompt-Presets mit 4 Vorlagen, KI-Anbieter-Vorlagen
  (CommandCode, Mistral), Modell-Filter (gratis/Reasoning), Sortierung,
  einklappbare Anbieter, Chat umbenennen, Zeilenumbruch, Chat-Bilder in Einträgen
- **Backup**: alle Einstellungen inkl. Chats (ohne Datei-Dopplung)
- **Anzeige**: Wochenbeginn Mo/So, Kalender-Ansicht, AMOLED-Schwarz

## Installieren

Fertige APKs gibt es unter
[Releases](https://github.com/b3n67/Moodiary-Pro/releases).
Hinweis: andere Signatur als die Store-Version – diese vorher
deinstallieren (Tagebücher vorher sichern!).

## Selbst bauen

Flutter 3.47.2, Android SDK + NDK, Rust mit Android-Targets, `cargo-about`,
Node + pnpm. Beispiel (Windows, `arm64-v8a`):

```powershell
cd mobile
flutter build apk --release
```

Eigene OneDrive-Client-ID einbetten:

```powershell
flutter build apk --release --dart-define=ONEDRIVE_CLIENT_ID=<id>
```

Ohne die Define bleibt das Feld in den OneDrive-Einstellungen leer und jede
Nutzerin trägt ihre eigene ID ein.

## Dank

Alle Lorbeeren für die App gehen an
[ZhuJHua](https://github.com/ZhuJHua/moodiary) und die Community dort.
Verbesserungen aus diesem Fork werden als Pull-Requests zurück angeboten.
Es gilt die [LICENSE](./LICENSE) des Originals.
