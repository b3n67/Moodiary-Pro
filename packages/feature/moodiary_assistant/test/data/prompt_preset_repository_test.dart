import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/prompt_preset_repository.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

void main() {
  setUp(() {
    getIt.pushNewScope(
      init: (gi) => gi.registerSingleton<IKVStorage>(MemoryKVStorage()),
    );
  });
  tearDown(() => getIt.popScope());

  group('PromptPresetRepository', () {
    test('leer am Anfang, aktiver Prompt ist null', () {
      final repo = PromptPresetRepository();
      expect(repo.getAll(), isEmpty);
      expect(repo.active(), isNull);
    });

    test('anlegen, umbenennen per upsert und löschen', () async {
      final repo = PromptPresetRepository();
      final created = await repo.upsert(name: 'Coach', content: 'Sei streng.');
      expect(created.name, 'Coach');
      expect(repo.getAll().single.id, created.id);

      final updated = await repo.upsert(
        id: created.id,
        name: 'Coach v2',
        content: 'Sei nett.',
      );
      expect(updated.id, created.id);
      expect(repo.getAll().single.name, 'Coach v2');

      await repo.remove(created.id);
      expect(repo.getAll(), isEmpty);
    });

    test('aktiver Prompt folgt der Auswahl', () async {
      final repo = PromptPresetRepository();
      final a = await repo.upsert(name: 'A', content: 'a');
      final b = await repo.upsert(name: 'B', content: 'b');
      await repo.setActiveId(b.id);
      expect(repo.active()?.id, b.id);
      await repo.remove(b.id);
      // Gelöschter aktiver Prompt fällt auf „keiner" zurück.
      expect(repo.active(), isNull);
      expect(repo.getAll().single.id, a.id);
    });

    test('kaputter Cache bricht nicht, sondern ist leer', () {
      MoodiaryKVs.assistantPromptPresets.set('kein-json{');
      expect(PromptPresetRepository().getAll(), isEmpty);
    });

    test('Vorlagen werden beim ersten Öffnen gesät, alles editierbar', () async {
      final repo = PromptPresetRepository();
      expect(repo.getAll(), isEmpty);
      await repo.ensureSeeded();      final names = {for (final p in repo.getAll()) p.id};
      expect(
        names,
        containsAll([
          'tagebuch',
          'journaling-morgens',
          'journaling-abends',
          'dankbarkeit',
        ]),
      );
      for (final p in repo.getAll()) {
        expect(p.content.trim(), isNotEmpty);
      }
      // Vorlage bearbeiten geht wie bei eigenen.
      await repo.upsert(
        id: 'dankbarkeit',
        name: 'Dankbarkeit!',
        content: 'neu',
      );
      expect(
        repo.getAll().where((p) => p.id == 'dankbarkeit').single.name,
        'Dankbarkeit!',
      );
      // Vorlage löschen geht auch; nachgesät wird nicht.
      await repo.remove('dankbarkeit');
      expect(
        repo.getAll().any((p) => p.id == 'dankbarkeit'),
        isFalse,
      );
      await repo.ensureSeeded();
      expect(
        repo.getAll().any((p) => p.id == 'dankbarkeit'),
        isFalse,
      );
      // Aktivieren einer Vorlage funktioniert.
      await repo.setActiveId('tagebuch');
      expect(repo.active()?.name, 'Tagebuch');
      expect(repo.active()?.content, contains('Tagebuch-Begleiter'));
    });

    test('Erstinstallation wählt Tagebuch als Standardprompt', () async {
      final repo = PromptPresetRepository();
      await repo.ensureSeeded();
      expect(repo.activeId(), 'tagebuch');
      expect(repo.active()?.name, 'Tagebuch');
    });

    test('Bestehende eigene Prompts behalten, Vorlagen ergänzt', () async {
      final repo = PromptPresetRepository();
      final mine = await repo.upsert(name: 'Meiner', content: 'x');
      await repo.ensureSeeded();
      final ids = {for (final p in repo.getAll()) p.id};
      expect(ids, contains(mine.id));
      expect(ids, contains('tagebuch'));
      // Zweiter Durchlauf sät nicht nach (gelöschte bleiben gelöscht).
      await repo.remove('tagebuch');
      await repo.ensureSeeded();
      expect(
        repo.getAll().any((p) => p.id == 'tagebuch'),
        isFalse,
      );
      expect(repo.getAll().any((p) => p.id == mine.id), isTrue);
    });
  });

  group('buildStableSystemPrompt', () {
    test('aktiver Prompt landet zwischen Persona und Notizen', () {
      final prompt = buildStableSystemPrompt(
        toolsEnabled: false,
        memoryEnabled: false,
        activePrompt: 'PROMPT-MARK',
      );
      final persona = prompt.indexOf('warm, grounded companion');
      final mark = prompt.indexOf('PROMPT-MARK');
      expect(persona, greaterThanOrEqualTo(0));
      expect(mark, greaterThan(persona));
    });

    test('Prompt und Notizen stehen beide drin, Prompt zuerst', () {
      final prompt = buildStableSystemPrompt(
        toolsEnabled: false,
        memoryEnabled: false,
        userNotes: 'NOTES-MARK',
        activePrompt: 'PROMPT-MARK',
      );
      final mark = prompt.indexOf('PROMPT-MARK');
      final notes = prompt.indexOf('NOTES-MARK');
      expect(mark, greaterThanOrEqualTo(0));
      expect(notes, greaterThan(mark));
    });
  });
}
