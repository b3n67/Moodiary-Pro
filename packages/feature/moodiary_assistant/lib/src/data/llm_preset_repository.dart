import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';

@lazySingleton
class LlmPresetRepository {
  LlmPresetRepository(this._http);

  final IHttpClient _http;

  static const String _apiUrl = 'https://models.dev/api.json';

  static const Duration _timeout = Duration(seconds: 15);

  int get cachedAt => MoodiaryKVs.llmPresetCacheAt.get() ?? 0;

  Future<List<LlmProviderPreset>> load() async {
    final cached = cachedPresets();
    if (cached.isNotEmpty) return cached;
    return refresh();
  }
  List<LlmProviderPreset> cachedPresets() {
    final cached = MoodiaryKVs.llmPresetCache.get() ?? '';
    if (cached.isEmpty) return _withBundled(const []);
    try {
      return _withBundled(_decodeCache(cached));
    } catch (_) {
      return _withBundled(const []);
    }
  }

  Future<List<LlmProviderPreset>>? _inFlight;

  Future<List<LlmProviderPreset>> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _refresh().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<List<LlmProviderPreset>> _refresh() async {
    final body = await _fetchBody();
    final normalized = await compute(_normalize, body);
    MoodiaryKVs.llmPresetCache.set(normalized);
    MoodiaryKVs.llmPresetCacheAt.set(DateTime.now().millisecondsSinceEpoch);
    return _withBundled(_decodeCache(normalized));
  }

  Future<String> _fetchBody() async {
    final res = await _http.get<String>(
      _apiUrl,
      timeout: _timeout,
      silent: true,
      plainText: true,
    );
    final data = res.data;
    if (data == null || data.isEmpty) {
      throw StateError('empty response from $_apiUrl');
    }
    return data;
  }

  List<LlmProviderPreset> _decodeCache(String s) {
    final list = jsonDecode(s);
    if (list is! List) throw const FormatException('invalid preset cache');
    return [
      for (final item in list)
        if (item is Map)
          LlmProviderPreset.fromJson(item.cast<String, dynamic>()),
    ];
  }

  /// Gebündelte Anbieter-Vorlagen, falls der Katalog sie nicht enthält
  /// (offline, veraltet). Duplikate per id ausgeschlossen.
  static List<LlmProviderPreset> withBundled(List<LlmProviderPreset> list) =>
      _withBundled(list);

  static const String _mistralBase = 'https://api.mistral.ai/v1';
  static const String _commandCodeBase =
      'https://api.commandcode.ai/provider/v1';

  static final List<LlmProviderPreset> _bundled = [
    LlmProviderPreset(
      id: 'mistral',
      name: 'Mistral',
      docUrl: 'https://docs.mistral.ai',
      env: const ['MISTRAL_API_KEY'],
      logoUrl: 'https://models.dev/logos/mistral.svg',
      models: [
        for (final m in [
          ('mistral-large-latest', 'Mistral Large'),
          ('mistral-small-latest', 'Mistral Small'),
          ('open-mistral-nemo', 'Open Mistral Nemo'),
          ('codestral-latest', 'Codestral'),
        ])
          LlmModelPreset(
            id: m.$1,
            name: m.$2,
            protocol: AssistantProviderType.openaiCompletions,
            baseUrl: _mistralBase,
            toolCall: true,
          ),
      ],
    ),
    LlmProviderPreset(
      id: 'commandcode',
      name: 'CommandCode',
      docUrl: 'https://commandcode.ai/docs/provider',
      env: const ['COMMANDCODE_API_KEY'],
      logoUrl: 'https://models.dev/logos/commandcode.svg',
      models: [
        // Modell-IDs aus https://commandcode.ai/docs/reference/cli/models.
        // Claude nur über /messages (Anthropic-Protokoll), Rest über
        // /chat/completions. toolCall nur wo belegt (+1-Markierung).
        for (final m in [
          ('claude-sonnet-4-6', 'Claude Sonnet 4.6', 'anthropic', true),
          ('claude-sonnet-5', 'Claude Sonnet 5', 'anthropic', true),
          ('claude-opus-4-8', 'Claude Opus 4.8', 'anthropic', true),
          ('deepseek/deepseek-v4-flash', 'DeepSeek V4 Flash', 'openai', true),
          (
            'deepseek/deepseek-v4.1-flash',
            'DeepSeek V4.1 Flash',
            'openai',
            true
          ),
          ('gpt-5.5', 'GPT-5.5', 'openai', true),
          ('google/gemini-3.8-flash', 'Gemini 3.8 Flash', 'openai', true),
          ('moonshotai/Kimi-K2.7-Code', 'Kimi K2.7 Code', 'openai', true),
          ('z-ai/glm-5.3-flash', 'GLM-5.3 Flash', 'openai', true),
          ('MiniMaxAI/MiniMax-M3', 'MiniMax M3', 'openai', true),
          ('Qwen/Qwen3.8-Max', 'Qwen 3.8 Max', 'openai', false),
          ('xiaomi/mimo-v2.5-pro', 'MiMo V2.5 Pro', 'openai', false),
          ('poolside/laguna-s-2.1-free', 'Laguna S 2.1 (gratis)', 'openai', false),
          (
            'inclusionai/ling-3.1-flash:free',
            'Ling 3.1 Flash (gratis)',
            'openai',
            false
          ),
          (
            'stealth/glyph-cluster:free',
            'Glyph Cluster (gratis)',
            'openai',
            false
          ),
        ])
          LlmModelPreset(
            id: m.$1,
            name: m.$2,
            protocol: m.$3 == 'anthropic'
                ? AssistantProviderType.anthropicMessages
                : AssistantProviderType.openaiCompletions,
            baseUrl: _commandCodeBase,
            toolCall: m.$4,
            inputCost: m.$4 ? null : 0,
            outputCost: m.$4 ? null : 0,
          ),
      ],
    ),
  ];
}

List<LlmProviderPreset> _withBundled(List<LlmProviderPreset> list) {
  final ids = {for (final p in list) p.id};
  if (ids.contains('mistral') && ids.contains('commandcode')) return list;
  return [
    ...list,
    for (final b in LlmPresetRepository._bundled)
      if (!ids.contains(b.id)) b,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

String _normalize(String body) {
  return jsonEncode(
    parseModelsDevCatalog(body).map((e) => e.toJson()).toList(),
  );
}

List<LlmProviderPreset> parseModelsDevCatalog(String body) {
  final root = jsonDecode(body);
  if (root is! Map) {
    throw const FormatException('invalid models.dev api.json root');
  }
  final result = <LlmProviderPreset>[];
  root.forEach((id, value) {
    if (id is String && value is Map) {
      final preset = LlmProviderPreset.fromModelsDev(
        id,
        value.cast<String, dynamic>(),
      );
      if (preset != null) result.add(preset);
    }
  });
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
