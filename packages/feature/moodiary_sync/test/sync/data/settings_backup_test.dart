import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/src/data/impl/local_archive.dart';
import 'package:moodiary_sync/src/data/settings_backup.dart';
import 'package:path/path.dart' as p;

import '../sync_test_harness.dart';

/// Minimaler ArchiveSink, der direkt in ein Verzeichnis schreibt.
final class _DirSink implements ArchiveSink {
  _DirSink(this.root);

  final String root;

  @override
  Future<void> addBytes(String zipPath, Uint8List data) async {
    final file = File(p.join(root, zipPath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<void> addLocalFile(String zipPath, String filePath) async {
    final file = File(p.join(root, zipPath));
    await file.parent.create(recursive: true);
    await File(filePath).copy(file.path);
  }

  @override
  Future<void> finish() async {}
}

void main() {
  late MoodiaryDatabase db;

  setUp(() async {
    await setUpSyncEnv();
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    getIt.registerSingleton<MoodiaryDatabase>(db);
  });

  tearDown(() async {
    await db.close();
    await tearDownSyncEnv();
  });

  test('KV round-trip behält Typen und lässt Geräte-Identität aus', () async {
    MoodiaryKVs.weekStart.set(DateTime.sunday);
    MoodiaryKVs.themeMode.set(2);
    MoodiaryKVs.language.set('de');
    MoodiaryKVs.syncPollInterval.set(60);
    MoodiaryKVs.autoSync.set(true);
    MoodiaryKVs.syncDeviceId.set('dieses-geraet');

    final snapshot = await SettingsBackup.collect();
    final kv = snapshot['kv'] as Map;

    expect(kv['weekStart'], DateTime.sunday);
    expect(kv['themeMode'], 2);
    expect(kv['language'], 'de');
    expect(kv['syncPollInterval'], 60);
    expect(kv['autoSync'], true);
    expect(kv.containsKey('syncDeviceId'), isFalse);
    expect(kv.containsKey('uuid'), isFalse);

    // Alles verstellen, dann zurückschreiben.
    MoodiaryKVs.weekStart.set(DateTime.monday);
    MoodiaryKVs.themeMode.set(0);
    MoodiaryKVs.language.set('zh');
    MoodiaryKVs.syncPollInterval.set(30);
    MoodiaryKVs.autoSync.set(false);
    MoodiaryKVs.syncDeviceId.set('anderes-geraet');

    await SettingsBackup.restore(snapshot);

    expect(MoodiaryKVs.weekStart.get(), DateTime.sunday);
    expect(MoodiaryKVs.themeMode.get(), 2);
    expect(MoodiaryKVs.language.get(), 'de');
    expect(MoodiaryKVs.syncPollInterval.get(), 60);
    expect(MoodiaryKVs.autoSync.get(), true);
    // Geräte-Identität wurde nicht angerührt.
    expect(MoodiaryKVs.syncDeviceId.get(), 'anderes-geraet');
  });

  test('Secure-Keys und Provider landen im Snapshot', () async {
    await getIt<ISecureKVStorage>().set('llm_key_p1', 'sk-test');
    await db
        .into(db.llmProviders)
        .insert(
          LlmProvidersCompanion.insert(
            id: 'p1',
            name: 'Test',
            type: 'openai',
            baseUrl: 'https://api.example',
            defaultModel: 'm',
            createdAt: 1,
            sortOrder: 0,
          ),
        );

    final snapshot = await SettingsBackup.collect();
    expect((snapshot['secure'] as Map)['llm_key_p1'], isNull);
    expect((snapshot['llmKeys'] as Map)['p1'], 'sk-test');
    final providers = snapshot['llmProviders'] as List;
    expect(providers.single['name'], 'Test');

    // Löschen und zurückschreiben.
    await getIt<ISecureKVStorage>().remove('llm_key_p1');
    await (db.delete(db.llmProviders)).go();
    await SettingsBackup.restore(snapshot);
    expect(
      await getIt<ISecureKVStorage>().get('llm_key_p1'),
      'sk-test',
    );
    expect(
      await (db.select(db.llmProviders)
            ..where((p) => p.id.equals('p1')))
          .getSingleOrNull(),
      isNotNull,
    );
  });

  test('AppLock-PIN wird weder exportiert noch importiert', () async {
    await getIt<ISecureKVStorage>().set('password', 'geheim');
    final snapshot = await SettingsBackup.collect();
    expect((snapshot['secure'] as Map).containsKey('password'), isFalse);

    await SettingsBackup.restore({
      'secure': {'password': 'fremd'},
    });
    expect(await getIt<ISecureKVStorage>().get('password'), 'geheim');
  });

  test('komplette Chat-Verläufe landen im Snapshot und zurück', () async {
    await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: 's1',
            title: const Value('Titel'),
            providerId: 'p1',
            model: 'm',
            createdAt: 1,
            updatedAt: 2,
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            id: 'msg1',
            sessionId: 's1',
            role: 'user',
            content: 'Hallo',
            createdAt: 3,
            imageName: const Value('pic.jpg'),
          ),
        );
    await db.into(db.assistantToolCalls).insert(
          AssistantToolCallsCompanion.insert(
            messageId: 'msg1',
            seq: 0,
            callId: 'c1',
            name: 'search',
          ),
        );

    final snapshot = await SettingsBackup.collect();
    expect((snapshot['chatSessions'] as List).single['title'], 'Titel');
    expect((snapshot['chatMessages'] as List).single['content'], 'Hallo');
    expect((snapshot['chatToolCalls'] as List).single['name'], 'search');
    expect(snapshot['chatImages'], ['pic.jpg']);

    await (db.delete(db.assistantToolCalls)).go();
    await (db.delete(db.chatMessages)).go();
    await (db.delete(db.chatSessions)).go();
    await SettingsBackup.restore(snapshot);

    final session = await (db.select(
      db.chatSessions,
    )..where((s) => s.id.equals('s1'))).getSingle();
    expect(session.title, 'Titel');
    final message = await (db.select(
      db.chatMessages,
    )..where((m) => m.id.equals('msg1'))).getSingle();
    expect(message.content, 'Hallo');
    expect(message.imageName, 'pic.jpg');
    final call = await (db.select(
      db.assistantToolCalls,
    )..where((c) => c.messageId.equals('msg1'))).getSingle();
    expect(call.name, 'search');
  });

  test('Export→Import stellt Chats, Bilder und KVs wieder her', () async {
    MoodiaryKVs.weekStart.set(DateTime.sunday);
    await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: 's9',
            title: const Value('Chat'),
            providerId: 'p1',
            model: 'm',
            createdAt: 1,
            updatedAt: 2,
          ),
        );
    await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            id: 'msg9',
            sessionId: 's9',
            role: 'user',
            content: 'Hi',
            createdAt: 3,
            imageName: const Value('chat.jpg'),
          ),
        );
    final mediaDir = await Directory.systemTemp.createTemp('media-src-');
    try {
      await Directory(p.join(mediaDir.path, 'image')).create();
      await File(
        p.join(mediaDir.path, 'image', 'chat.jpg'),
      ).writeAsBytes([1, 2, 3]);

      final dir = await Directory.systemTemp.createTemp('archive-');
      try {
        await LocalArchive.writeArchive(
          sink: _DirSink(dir.path),
          diaries: const [],
          categories: const [],
          tombstones: const [],
          mediaBaseDir: mediaDir.path,
          includeSettings: true,
        );
        expect(
          File(p.join(dir.path, 'settings.json')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(dir.path, 'chat_media', 'chat.jpg')).existsSync(),
          isTrue,
        );

        // Alles löschen und zurückholen.
        await (db.delete(db.chatMessages)).go();
        await (db.delete(db.chatSessions)).go();
        MoodiaryKVs.weekStart.set(DateTime.monday);
        final mediaFiles = FakeMediaFiles();
        await LocalArchive.importDirectory(
          dir.path,
          diaryStore: FakeDiaryStore(),
          categoryStore: FakeCategoryStore(),
          placeStore: FakePlaceStore(),
          mediaInfoStore: FakeMediaInfoStore(),
          tombstoneStore: FakeTombstoneStore(),
          mediaFiles: mediaFiles,
        );

        expect(MoodiaryKVs.weekStart.get(), DateTime.sunday);
        final session = await (db.select(
          db.chatSessions,
        )..where((s) => s.id.equals('s9'))).getSingle();
        expect(session.title, 'Chat');
        final message = await (db.select(
          db.chatMessages,
        )..where((m) => m.id.equals('msg9'))).getSingle();
        expect(message.imageName, 'chat.jpg');
        expect(mediaFiles.files['image/chat.jpg'], [1, 2, 3]);
      } finally {
        await Directory(dir.path).delete(recursive: true);
      }
    } finally {
      await mediaDir.delete(recursive: true);
    }
  });

  test('Chat-Bild mit Tagebuch-Referenz wird nicht doppelt abgelegt', () async {
    final mediaDir = await Directory.systemTemp.createTemp('media-dedup-');
    try {
      await Directory(p.join(mediaDir.path, 'image')).create();
      await File(
        p.join(mediaDir.path, 'image', 'dup.jpg'),
      ).writeAsBytes([9]);
      await db.into(db.chatSessions).insert(
            ChatSessionsCompanion.insert(
              id: 's-dup',
              title: const Value('t'),
              providerId: 'p',
              model: 'm',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await db.into(db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              id: 'm-dup',
              sessionId: 's-dup',
              role: 'user',
              content: 'x',
              createdAt: 1,
              imageName: const Value('dup.jpg'),
            ),
          );
      final dir = await Directory.systemTemp.createTemp('archive-dedup-');
      try {
        await LocalArchive.writeArchive(
          sink: _DirSink(dir.path),
          diaries: [
            buildDiary(id: 'd1', images: const ['dup.jpg']),
          ],
          categories: const [],
          tombstones: const [],
          mediaBaseDir: mediaDir.path,
          includeSettings: true,
        );
        expect(
          File(p.join(dir.path, 'media', 'image', 'dup.jpg')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(dir.path, 'chat_media', 'dup.jpg')).existsSync(),
          isFalse,
        );
      } finally {
        await Directory(dir.path).delete(recursive: true);
      }
    } finally {
      await mediaDir.delete(recursive: true);
    }
  });

  test('kaputter Snapshot bricht Restore nicht ab', () async {
    MoodiaryKVs.themeMode.set(0);
    await db.into(db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: 'keep',
            title: const Value('bleibt'),
            providerId: 'p',
            model: 'm',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await SettingsBackup.restore({
      'kv': {'themeMode': 'kein-int', 'language': 'de'},
      'chatSessions': [
        {'id': 'neu', 'title': 'Neu'},
        {'no-id': true},
        'kein-objekt',
      ],
      'chatMessages': [
        {'id': '', 'content': 'leere-id-wird-übersprungen'},
      ],
    });
    // Falscher Typ liegen gelassen, Rest übernommen.
    expect(MoodiaryKVs.themeMode.get(), 0);
    expect(MoodiaryKVs.language.get(), 'de');
    expect(
      await (db.select(
        db.chatSessions,
      )..where((s) => s.id.equals('neu'))).getSingleOrNull(),
      isNotNull,
    );
    expect(
      await (db.select(
        db.chatSessions,
      )..where((s) => s.id.equals('keep'))).getSingleOrNull(),
      isNotNull,
    );
  });

  test('Nachrichten mit hängender sessionId brechen Restore nicht ab', () async {
    await SettingsBackup.restore({
      'chatSessions': [
        {'id': 's-ok', 'title': 'Ok'},
      ],
      'chatMessages': [
        {'id': 'm-ok', 'sessionId': 's-ok', 'content': 'drin'},
        {'id': 'm-dangling', 'sessionId': 'gibts-nicht', 'content': 'raus'},
        {'id': 'm-empty', 'content': 'raus'},
      ],
      'chatToolCalls': [
        {'messageId': 'm-ok', 'seq': 0, 'callId': 'c-ok', 'name': 'n-ok'},
        {'messageId': 'm-dangling', 'seq': 0, 'callId': 'c-raus', 'name': 'x'},
      ],
    });
    expect(
      await (db.select(
        db.chatMessages,
      )..where((m) => m.id.equals('m-ok'))).getSingleOrNull(),
      isNotNull,
    );
    expect(
      await (db.select(
        db.chatMessages,
      )..where((m) => m.id.equals('m-dangling'))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (db.select(
        db.assistantToolCalls,
      )..where((c) => c.callId.equals('c-ok'))).getSingleOrNull(),
      isNotNull,
    );
    expect(
      await (db.select(
        db.assistantToolCalls,
      )..where((c) => c.callId.equals('c-raus'))).getSingleOrNull(),
      isNull,
    );
  });

  test('fremder Abschnittstyp bricht Restore nicht ab', () async {
    await SettingsBackup.restore({
      'chatSessions': 'keine-liste',
      'chatMessages': {'id': 'x'},
      'chatToolCalls': 42,
    });
  });
}
