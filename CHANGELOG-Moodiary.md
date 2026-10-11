# Moodiary – Changelog (deutsche Community-Builds)

Basis: ZhuJHua/moodiary (Branch `develop`), erweitert um Deutsch,
OneDrive-Sync und Komfortfunktionen. Installiert wird per APK (gleiche
Signatur, Update ohne Deinstallation möglich).

## Unveröffentlicht
- Mitgelieferte Schriften (OFL): **Arimo** (≈ Arial), **Tinos**
  (≈ Times New Roman), **Lato**, **Nunito**, **Open Sans** — beim ersten
  Start automatisch in der Schriften-Verwaltung (und im PDF-Export);
  Arial/Times selbst sind proprietär und liegen nicht bei

## Aktuell: Moodiary-25-20261011 (2.8.1+100)

**Neu in dieser Version:**
- Review-Härtung: Backup-Restore bricht bei kaputten Einträgen nicht mehr ab,
  Geräte-Identität wird nie aus fremden Backups übernommen
- OneDrive: korrekte Netzwerk-Fehlerklassen, Timeouts überall, kein
  Client-Leak, Loopback nimmt nur `/callback` an, Custom-Client-ID bleibt erhalten
- Prompt-Seeds mit Versionsmarke, Upsert-Validierung, Bildnamen-Sanitizing
- Kalender überschreibt Sortierung nicht mehr; Export-Karten mit Akzent+AMOLED
- Totholz entfernt (Device-Code-Flow, verwaiste Texte)

**Neu in dieser Version:**
- Prompt-Schalter statt „Aktiv"-Text in den Assistant-Einstellungen
- Modell-Filter auch im Standardmodell-Fenster (Kostenlos + Reasoning)
- **Sortierung** in beiden Modell-Fenstern (Standard / Name / Preis)
- **Anbieter ein-/ausklappen** im Chat-Modellfenster
- **Kalender-Ansicht** als dritte Ansicht im Tagebuch (oben rechts umschalten)
- KI-Anbieter-Vorlagen: **CommandCode** (16 Modelle aus der offiziellen Doku,
  inkl. 3 Gratis-Modelle) und **Mistral** (4 Modelle)

## Aktuell: Moodiary-18-20261009 (2.8.1+98)

**Neu in dieser Version:**
- KI-Anbieter-Vorlagen: **CommandCode** (16 Modelle aus der offiziellen
  Doku, inkl. 3 Gratis-Modelle) und **Mistral** (4 Modelle) – ohne Katalog-Download
- Modell-Filter im Picker: **Kostenlos (0 $)** und **Reasoning einstellbar**,
  kombinierbar mit Suche (auch im Standardmodell-Fenster)
- **Sortierung**: Standard / Name / Preis (unbekannte Preise zuletzt)
- **Anbieter ein-/ausklappen** im Chat-Modellfenster

**Weiterhin enthalten (aus Vorversionen):**
- Deutsche Oberfläche (App, Editor, Einstellungen), Du-Form
- OneDrive-Sync: Anmeldung per Microsoft-Browserfenster (Client-ID fest
  eingebaut, keine Azure-Arbeit pro Nutzer), Token-Refresh, DNS-Retry mit
  deutscher Fehlermeldung
- Wochenbeginn Montag/Sonntag (Einstellungen → Anzeige; Kalender + Heatmap)
- Backup enthält **alle Einstellungen**: KI-Assistenten, Provider + API-Keys,
  Memory, komplette Chat-Verläufe inkl. Bilder (ohne Datei-Dopplung)
- Prompt-Presets: 4 Vorlagen (Tagebuch, Journaling morgens/abends,
  Dankbarkeit), frei editier-/löschbar, Umschalter im Chat-Kopf
  („Preset ∨ · Modell ∨"), Tagebuch als Standard
- Chat umbenennen (⋮-Menü + Long-Press in der Liste), Zeilenumbruch im
  Chat-Eingabefeld (Senden über Pfeil-Button)
- Chat-Bilder lassen sich per KI in Tagebucheinträge übernehmen (+ Medien)
- AMOLED-Schwarz im Design-Dialog (echtes Schwarz im Dunkelmodus)

## Moodiary-16-20261009 (2.8.1+97)

- Prompt-Vorlagen-Nachlieferung per Versionsmarke (auch für bestehende Nutzer)
- AMOLED-Schwarz, Tagebuch als Standardprompt

## Moodiary-14-20261008 (2.8.1+97)

- Prompt-Presets mit Umschalter, Chat-Backup, Chat umbenennen,
  DNS-Härtung, Chat-Bilder-Tools

## moodiary-2.8.1-96-20261008-2015 (intern +95)

- Browser-Loopback-Login ohne Code-Abtippen, fest eingebaute Client-ID,
  Wochenbeginn, Einstellungs-Backup, Token-Refresh-Fix

## moodiary-2.8.1-95 (Erst-Build)

- Deutsche Übersetzungen, OneDrive-Sync (Device-Code-Flow), eigene Signatur
  (Hinweis: Erstinstallation erfordert Deinstallation der Store-Version)

---

*Hinweis: Frühe Builds (bis v13) waren iterative Aufbau-Stände für Deutsch
und OneDrive; die Zuordnung oben fasst sie sinngemäß zusammen. Ab v14 ist
jede Version einzeln nachvollziehbar. Dateiname-Schema: `Moodiary-<Build>-<Datum>.apk`.*
