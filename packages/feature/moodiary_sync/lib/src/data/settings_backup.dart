library;

import 'package:drift/drift.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';

/// Ablagepfad für Chat-Bilder im Backup-Zip (Rückkopie nach `image/`).
const kChatMediaPrefix = 'chat_media';

/// Dateiname der Einstellungsbeilage im Backup-Zip (steht bewusst nicht im
/// Manifest: Das Manifest steuert nur Tagebuch-Daten, alte Backups ohne die
/// Datei bleiben importierbar).
const kSettingsBackupPath = 'settings.json';

/// Normale KV-Keys, die ein Gerät identifizieren und nie aus einem Backup
/// wiederhergestellt werden dürfen (sonst duplizieren sich Geräte-IDs und
/// die Synchronisierung verwechselt Geräte / Pfade zeigen ins Leere).
const _excludedKv = {
  'syncDeviceId',
  'uuid',
  'supportPath',
  'cachePath',
  'local',
  'lastSyncTime',
  'syncManifestStat',
  'syncPendingLocal',
  'startTime',
  'firstStart',
  // Schlüssel-Sync-Status ist Geräte-Betriebszustand, kein Roaming-Setup.
  'syncKeyfileCache',
  'syncKeyfilePendingBackends',
  'syncKeyConflictBackends',
  'syncForceMediaReuploadBackends',
};

/// Secure-Keys, die nie ins Backup gehören. `password` wird ausschließlich
/// über AppLockPin verwaltet – direktes Zurückschreiben würde im Klartext
/// landen (siehe Kommentar in MoodiarySecureKVs).
const _excludedSecure = {'password'};

/// Präfix der Provider-API-Keys im Secure-Storage (`llm_key_<id>`).
const _llmKeyPrefix = 'llm_key_';

/// Sammelt alle wiederherstellbaren Einstellungen ein: sämtliche
/// [MoodiaryKVs] (außer Geräte-Identität), sämtliche [MoodiarySecureKVs]
/// (außer AppLock-PIN, inkl. Sync-Zugangsdaten und Provider-API-Keys) sowie
/// die Assistenten-Tabellen `llm_providers`, `memories` und die kompletten
/// Chat-Verläufe (`chat_sessions`, `chat_messages`, `assistant_tool_calls`
/// inkl. referenzierter Chat-Bilder).
final class SettingsBackup {
  SettingsBackup._();

  static Future<Map<String, Object?>> collect() async {
    final kv = <String, Object?>{};
    for (final e in MoodiaryKVs.values) {
      if (_excludedKv.contains(e.name)) continue;
      final Object? v = e.get();
      if (v == null) continue;
      kv[e.name] = v;
    }

    final db = getIt<MoodiaryDatabase>();
    final secureStorage = getIt<ISecureKVStorage>();

    final secure = <String, String>{};
    for (final e in MoodiarySecureKVs.values) {
      if (_excludedSecure.contains(e.name)) continue;
      final v = await e.get();
      if (v != null) secure[e.name] = v;
    }

    final providerRows =
        await (db.select(
          db.llmProviders,
        )..orderBy([(p) => OrderingTerm.asc(p.sortOrder)])).get();
    final llmKeys = <String, String>{};
    for (final r in providerRows) {
      final key = await secureStorage.get('$_llmKeyPrefix${r.id}');
      if (key != null) llmKeys[r.id] = key;
    }

    final memoryRows =
        await (db.select(
          db.memories,
        )..orderBy([(m) => OrderingTerm.desc(m.updatedAt)])).get();

    final sessionRows =
        await (db.select(
          db.chatSessions,
        )..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])).get();
    final messageRows =
        await (db.select(
          db.chatMessages,
        )..orderBy([(m) => OrderingTerm.asc(m.createdAt)])).get();
    final toolCallRows = await db.select(db.assistantToolCalls).get();
    final chatImages = <String>{
      for (final r in messageRows)
        if (r.imageName != null && r.imageName!.isNotEmpty) r.imageName!,
    };

    return {
      'version': 1,
      'kv': kv,
      'secure': secure,
      'llmKeys': llmKeys,
      'llmProviders': [
        for (final r in providerRows)
          {
            'id': r.id,
            'name': r.name,
            'type': r.type,
            'baseUrl': r.baseUrl,
            'defaultModel': r.defaultModel,
            'createdAt': r.createdAt,
            'sortOrder': r.sortOrder,
            'presetId': r.presetId,
            'modelsJson': r.modelsJson,
            'toolCall': r.toolCall,
            'reasoning': r.reasoning,
            'attachment': r.attachment,
          },
      ],
      'memories': [
        for (final r in memoryRows)
          {
            'id': r.id,
            'category': r.category,
            'content': r.content,
            'createdAt': r.createdAt,
            'updatedAt': r.updatedAt,
            'source': r.source,
          },
      ],
      'chatSessions': [
        for (final r in sessionRows)
          {
            'id': r.id,
            'title': r.title,
            'providerId': r.providerId,
            'model': r.model,
            'createdAt': r.createdAt,
            'updatedAt': r.updatedAt,
            'reasoningEffort': r.reasoningEffort,
            'compactedSummary': r.compactedSummary,
            'compactedUpToMessageId': r.compactedUpToMessageId,
            'compactedAt': r.compactedAt,
            'compactedInputTokensAtTrigger':
                r.compactedInputTokensAtTrigger,
          },
      ],
      'chatMessages': [
        for (final r in messageRows)
          {
            'id': r.id,
            'sessionId': r.sessionId,
            'role': r.role,
            'content': r.content,
            'createdAt': r.createdAt,
            'reasoning': r.reasoning,
            'thinkingMillis': r.thinkingMillis,
            'imageName': r.imageName,
            'inputTokens': r.inputTokens,
            'outputTokens': r.outputTokens,
            'model': r.model,
            'providerId': r.providerId,
          },
      ],
      'chatToolCalls': [
        for (final r in toolCallRows)
          {
            'messageId': r.messageId,
            'seq': r.seq,
            'callId': r.callId,
            'name': r.name,
            'argsJson': r.argsJson,
            'result': r.result,
            'done': r.done,
          },
      ],
      'chatImages': chatImages.toList(),
    };
  }

  /// Schreibt einen [collect]-Schnappschuss zurück. Fehlende Abschnitte
  /// werden übersprungen, unbekannte Keys ignoriert. Kaputte Einzelwerte
  /// werden übersprungen statt den Restore abzubrechen; Geräte-Identität
  /// wird auch aus fremden Snapshots nie übernommen.
  static Future<void> restore(Map<String, Object?> snapshot) async {
    final kv = snapshot['kv'];
    if (kv is Map) {
      for (final e in MoodiaryKVs.values) {
        if (_excludedKv.contains(e.name)) continue;
        if (!kv.containsKey(e.name)) continue;
        _restoreOne(e, kv[e.name]);
      }
    }

    final secureStorage = getIt<ISecureKVStorage>();
    final secure = snapshot['secure'];
    if (secure is Map) {
      for (final e in MoodiarySecureKVs.values) {
        if (_excludedSecure.contains(e.name)) continue;
        final v = secure[e.name];
        if (v is String) await e.set(v);
      }
    }
    final llmKeys = snapshot['llmKeys'];
    if (llmKeys is Map) {
      for (final entry in llmKeys.entries) {
        final id = entry.key;
        final key = entry.value;
        if (id is String && id.isNotEmpty && key is String) {
          await secureStorage.set('$_llmKeyPrefix$id', key);
        }
      }
    }

    final db = getIt<MoodiaryDatabase>();
    // Eine kaputte Zeile überspringt nur sich selbst, nicht den Batch.
    String? reqStr(Map m, String key) {
      final v = m[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    int reqInt(Map m, String key, [int fallback = 0]) {
      final v = m[key];
      return v is int ? v : fallback;
    }

    // Abschnitte aus fremden Snapshots können alles sein – nur Listen
    // sind gültig, alles andere wird wie ein fehlender Abschnitt behandelt.
    List<Map> sectionMaps(Object? section) {
      if (section is! List) return const [];
      return section.whereType<Map>().toList();
    }

    final providers = snapshot['llmProviders'];
    if (providers is List) {
      await db.batch((b) {
        b.insertAll(
          db.llmProviders,
          [
            for (final p in providers.whereType<Map>())
              if (reqStr(p, 'id') case final String id)
                LlmProvidersCompanion(
                  id: Value(id),
                  name: Value(p['name'] as String? ?? ''),
                  type: Value(p['type'] as String? ?? ''),
                  baseUrl: Value(p['baseUrl'] as String? ?? ''),
                  defaultModel: Value(p['defaultModel'] as String? ?? ''),
                  createdAt: Value(reqInt(p, 'createdAt')),
                  sortOrder: Value(reqInt(p, 'sortOrder')),
                  presetId: Value(p['presetId'] as String? ?? ''),
                  modelsJson: Value(p['modelsJson'] as String? ?? '[]'),
                  toolCall: Value(reqInt(p, 'toolCall')),
                  reasoning: Value(reqInt(p, 'reasoning')),
                  attachment: Value(reqInt(p, 'attachment')),
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    }
    final memories = snapshot['memories'];
    if (memories is List) {
      await db.batch((b) {
        b.insertAll(
          db.memories,
          [
            for (final m in memories.whereType<Map>())
              if (reqStr(m, 'id') case final String id)
                MemoriesCompanion(
                  id: Value(id),
                  category: Value(m['category'] as String? ?? ''),
                  content: Value(m['content'] as String? ?? ''),
                  createdAt: Value(reqInt(m, 'createdAt')),
                  updatedAt: Value(reqInt(m, 'updatedAt')),
                  source: Value(m['source'] as String?),
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    }

    // Chats in Fremdschlüssel-Reihenfolge: Sessions → Nachrichten → Tool-Calls.
    // Zeilen mit hängendem Fremdschlüssel werden übersprungen: Der Batch
    // läuft in einer Transaktion, eine kaputte Zeile bräche sonst den
    // ganzen Abschnitt ab (obwohl der Restore Einzelwerte überspringen soll).
    final sessionMaps = sectionMaps(snapshot['chatSessions']);
    final sessionIds = <String>{
      for (final s in sessionMaps)
        if (reqStr(s, 'id') case final String id) id,
    };
    if (sessionMaps.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(
          db.chatSessions,
          [
            for (final s in sessionMaps)
              if (reqStr(s, 'id') case final String id)
                ChatSessionsCompanion(
                  id: Value(id),
                  title: Value(s['title'] as String? ?? ''),
                  providerId: Value(s['providerId'] as String? ?? ''),
                  model: Value(s['model'] as String? ?? ''),
                  createdAt: Value(reqInt(s, 'createdAt')),
                  updatedAt: Value(reqInt(s, 'updatedAt')),
                  reasoningEffort: Value(s['reasoningEffort'] as String? ?? ''),
                  compactedSummary: Value(s['compactedSummary'] as String?),
                  compactedUpToMessageId: Value(
                    s['compactedUpToMessageId'] as String?,
                  ),
                  compactedAt: Value(s['compactedAt'] as int?),
                  compactedInputTokensAtTrigger: Value(
                    s['compactedInputTokensAtTrigger'] as int?,
                  ),
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    }
    final messageMaps = [
      for (final m in sectionMaps(snapshot['chatMessages']))
        if (reqStr(m, 'id') != null &&
            sessionIds.contains(reqStr(m, 'sessionId')))
          m,
    ];
    final messageIds = <String>{
      for (final m in messageMaps) reqStr(m, 'id') as String,
    };
    if (messageMaps.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(
          db.chatMessages,
          [
            for (final m in messageMaps)
              ChatMessagesCompanion(
                id: Value(reqStr(m, 'id') as String),
                sessionId: Value(reqStr(m, 'sessionId') as String),
                  role: Value(m['role'] as String? ?? ''),
                  content: Value(m['content'] as String? ?? ''),
                  createdAt: Value(reqInt(m, 'createdAt')),
                  reasoning: Value(m['reasoning'] as String?),
                  thinkingMillis: Value(m['thinkingMillis'] as int?),
                  imageName: Value(m['imageName'] as String?),
                  inputTokens: Value(m['inputTokens'] as int?),
                  outputTokens: Value(m['outputTokens'] as int?),
                  model: Value(m['model'] as String?),
                  providerId: Value(m['providerId'] as String?),
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    }
    final toolCallMaps = sectionMaps(snapshot['chatToolCalls']);
    if (toolCallMaps.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(
          db.assistantToolCalls,
          [
            for (final c in toolCallMaps)
              if (reqStr(c, 'messageId') case final String messageId
                  when messageIds.contains(messageId))
                AssistantToolCallsCompanion(
                  messageId: Value(messageId),
                  seq: Value(reqInt(c, 'seq')),
                  callId: Value(c['callId'] as String? ?? ''),
                  name: Value(c['name'] as String? ?? ''),
                  argsJson: Value(c['argsJson'] as String? ?? ''),
                  result: Value(c['result'] as String? ?? ''),
                  done: Value(reqInt(c, 'done')),
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    }
  }

  static void _restoreOne(MoodiaryKVs e, Object? v) {
    // Falsche Typen aus fremden/handeditierten Snapshots überspringen,
    // statt den ganzen Restore zu sprengen.
    try {
      if (v == null) return;
      if (v is bool) {
        (e as MoodiaryKVs<bool>).set(v);
      } else if (v is int) {
        (e as MoodiaryKVs<int>).set(v);
      } else if (v is String) {
        (e as MoodiaryKVs<String>).set(v);
      } else if (v is List) {
        (e as MoodiaryKVs<List<String>>).set(v.whereType<String>().toList());
      }
    } catch (_) {
      // Kaputter Einzelwert: liegen lassen, mit dem Rest fortfahren.
    }
  }
}
