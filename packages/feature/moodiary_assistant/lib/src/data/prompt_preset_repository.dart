import 'dart:convert';

import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';

/// Ein gespeicherter System-Prompt (Vorlage oder eigene Kreation).
class PromptPreset {
  const PromptPreset({
    required this.id,
    required this.name,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String content;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'updatedAt': updatedAt,
  };

  static PromptPreset? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final content = json['content'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        content is! String) {
      return null;
    }
    final updatedAt = json['updatedAt'];
    return PromptPreset(
      id: id,
      name: name,
      content: content,
      updatedAt: updatedAt is int ? updatedAt : 0,
    );
  }
}

/// CRUD für Prompt-Presets auf KV-Basis (JSON-Liste). Dadurch landen sie
/// automatisch im Einstellungs-Backup (settings.json).
class PromptPresetRepository {
  static const maxContentChars = 20000;

  /// ID des Werks-Presets („Moodiary Assistant", Standardverhalten).
  /// Leere activeId bedeutet: Werks-Preset aktiv.
  static const builtInId = 'built-in';

  /// Legt die Vorlagen genau einmal an (Versionsmarke): Fehlende Vorlagen
  /// werden zu bestehenden eigenen Prompts hinzugefügt, nichts wird
  /// überschrieben. Gelöschte Vorlagen bleiben gelöscht (kein Nachsäen).
  static const int currentSeedVersion = 1;

  static bool _seeding = false;

  Future<void> ensureSeeded() async {
    if (_seeding) return;
    _seeding = true;
    try {
      await _ensureSeededOnce();
    } finally {
      _seeding = false;
    }
  }

  Future<void> _ensureSeededOnce() async {
    if ((MoodiaryKVs.assistantPromptSeedVersion.get() ?? 0) >=
        currentSeedVersion) {
      return;
    }
    final existing = {for (final p in getAll()) p.id};
    final now = DateTime.now().millisecondsSinceEpoch;
    await _saveAll([
      for (final s in _templateSeeds)
        if (!existing.contains(s.id))
          PromptPreset(
            id: s.id,
            name: s.name,
            content: s.content,
            updatedAt: now,
          ),
      ...getAll(),
    ]);
    MoodiaryKVs.assistantPromptSeedVersion.set(currentSeedVersion);
    // Standardprompt für neue Installationen: der Tagebuchassistent.
    final storage = getIt<IKVStorage>();
    if (storage.get<String>(MoodiaryKVs.assistantActivePromptId.name) ==
        null) {
      await setActiveId('tagebuch');
    }
  }

  static const List<({String id, String name, String content})>
  _templateSeeds = [
    (
      id: 'tagebuch',
      name: 'Tagebuch',
      content: '''
Du bist ein einfühlsamer Tagebuch-Begleiter im Stil einer guten Journaling-App: warm, ruhig und neugierig, niemals klinisch oder kitschig.

So arbeitest du:
- Lasse die Nutzerin/den Nutzer frei erzählen. Spiegle das Wichtigste in eigenen Worten zurück, damit sie/er sich verstanden fühlt.
- Stelle pro Nachricht höchstens eine behutsame Nachfrage und warte die Antwort ab — kein Fragefeuer.
- Benenne sanft Muster und Gefühle, die zwischen den Zeilen stehen („Das klingt nach …"), ohne zu diagnostizieren oder Ratschläge aufzudrängen.
- Werde nur praktisch, wenn ausdrücklich darum gebeten wird (z. B. „hilf mir, das zu sortieren").
- Antworte in der Sprache der Nutzerin/des Nutzers, eher kurz als lang: wenige Sätze im Gespräch, ausführlicher nur auf Wunsch.
- Biete am Ende eines Austauschs an, das Besprochene als Tagebucheintrag festzuhalten.
''',
    ),
    (
      id: 'journaling-morgens',
      name: 'Journaling morgens',
      content: '''
Du leitest eine kurze Morgen-Journaling-Routine. Stelle genau drei Fragen, strikt nacheinander:

1. Was ist deine Absicht für heute — wie willst du heute sein oder wirken?
2. Was ist die eine wichtigste Sache heute, und was ist der erste kleine Schritt dazu?
3. Was könnte heute schwierig werden, und wie gehst du gelassen damit um?

Eiserne Regeln:
- Pro Nachricht genau EINE Frage, dann auf die Antwort warten. Niemals mehrere Fragen auf einmal, niemals vorwegnehmen.
- Nach jeder Antwort: ein Satz Resonanz, dann die nächste Frage.
- Nach der dritten Antwort: kurze, ermutigende Zusammenfassung des Tages-Fokus in zwei bis drei Sätzen. Danach ist die Routine beendet — keine weiteren Fragen.
- Antworte in der Sprache der Nutzerin/des Nutzers.
''',
    ),
    (
      id: 'journaling-abends',
      name: 'Journaling abends',
      content: '''
Du leitest eine kurze Abend-Journaling-Routine zum Tagesabschluss. Stelle genau drei Fragen, strikt nacheinander:

1. Was war heute gut — was war dein schönster Moment?
2. Was war schwierig, und was nimmst du daraus mit?
3. Was lässt du heute los, und worauf freust du dich morgen?

Eiserne Regeln:
- Pro Nachricht genau EINE Frage, dann auf die Antwort warten. Niemals mehrere Fragen auf einmal, niemals vorwegnehmen.
- Nach jeder Antwort: ein Satz Resonanz, dann die nächste Frage.
- Nach der dritten Antwort: ein ruhiger Abschluss in zwei bis drei Sätzen (Würdigung + gute Nacht). Danach ist die Routine beendet — keine weiteren Fragen.
- Antworte in der Sprache der Nutzerin/des Nutzers.
''',
    ),
    (
      id: 'dankbarkeit',
      name: 'Dankbarkeit',
      content: '''
Du leitest eine kurze Dankbarkeits-Übung. Stelle genau drei Fragen, strikt nacheinander:

1. Wofür bist du heute dankbar? Auch Kleines zählt — nenne, was dir einfällt.
2. Welcher Mensch hat deinen Tag besser gemacht, und warum?
3. Was an dir selbst schätzt du heute?

Eiserne Regeln:
- Pro Nachricht genau EINE Frage, dann auf die Antwort warten. Niemals mehrere Fragen auf einmal, niemals vorwegnehmen.
- Nach jeder Antwort: ein Satz Resonanz, dann die nächste Frage.
- Nach der dritten Antwort: ein warmer Abschluss in zwei bis drei Sätzen, der die genannten Punkte aufgreift. Danach ist die Übung beendet — keine weiteren Fragen.
- Antworte in der Sprache der Nutzerin/des Nutzers.
''',
    ),
  ];

  List<PromptPreset> getAll() {
    final raw = MoodiaryKVs.assistantPromptPresets.get() ?? '[]';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>)
            ...[?PromptPreset.fromJson(e)],
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveAll(List<PromptPreset> list) async {
    MoodiaryKVs.assistantPromptPresets.set(
      jsonEncode([for (final p in list) p.toJson()]),
    );
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  static int _counter = 0;

  Future<PromptPreset> upsert({String? id, required String name, required String content}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Prompt-Name darf nicht leer sein');
    }
    var cleanContent = content.trim();
    if (cleanContent.length > maxContentChars) {
      cleanContent = cleanContent.substring(0, maxContentChars);
    }
    final list = getAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    final preset = PromptPreset(
      id: id ?? _newId(),
      name: cleanName,
      content: cleanContent,
      updatedAt: now,
    );
    final next = [
      preset,
      for (final p in list)
        if (p.id != preset.id) p,
    ];
    await _saveAll(next);
    return preset;
  }

  Future<void> remove(String id) async {
    await _saveAll([for (final p in getAll()) if (p.id != id) p]);
    if (activeId() == id) await setActiveId('');
  }

  String activeId() => MoodiaryKVs.assistantActivePromptId.get() ?? '';

  Future<void> setActiveId(String id) async {
    MoodiaryKVs.assistantActivePromptId.set(id);
  }

  PromptPreset? active() {
    final id = activeId();
    if (id.isEmpty) return null;
    return getAll().where((p) => p.id == id).firstOrNull;
  }
}
