import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/llm_preset_repository.dart';
import 'package:moodiary_assistant/src/data/model_resolver.dart';
import 'package:moodiary_assistant/src/presentation/model_picker_sheet.dart';
import 'package:moodiary_models/moodiary_models.dart';

LlmModelPreset _model({
  required String id,
  num? inputCost,
  num? outputCost,
  bool reasoning = false,
}) => LlmModelPreset(
  id: id,
  name: id,
  protocol: AssistantProviderType.openaiCompletions,
  baseUrl: 'https://api.example',
  inputCost: inputCost,
  outputCost: outputCost,
  reasoning: reasoning,
);

ModelOption _option(LlmModelPreset? preset) =>
    ModelOption(id: 'm', label: 'm', preset: preset, levels: const []);

void main() {
  group('withBundled', () {
    test('leere Liste bekommt Mistral und CommandCode', () {
      final list = LlmPresetRepository.withBundled(const []);
      final ids = {for (final p in list) p.id};
      expect(ids, containsAll(['mistral', 'commandcode']));
    });

    test('keine Duplikate bei vorhandenem Katalog-Eintrag', () {
      const existing = LlmProviderPreset(
        id: 'mistral',
        name: 'Mistral (Katalog)',
        models: [],
      );
      final list = LlmPresetRepository.withBundled([existing]);
      expect(
        list.where((p) => p.id == 'mistral'),
        hasLength(1),
      );
      expect(list.firstWhere((p) => p.id == 'mistral').name, 'Mistral (Katalog)');
    });

    test('Mistral-Vorlage ist OpenAI-kompatibel mit Modellen', () {
      final list = LlmPresetRepository.withBundled(const []);
      final mistral = list.firstWhere((p) => p.id == 'mistral');
      expect(mistral.models, isNotEmpty);
      for (final m in mistral.models) {
        expect(m.baseUrl, 'https://api.mistral.ai/v1');
        expect(m.protocol, AssistantProviderType.openaiCompletions);
      }
    });

    test('CommandCode-Vorlage zeigt auf die Provider-Basis-URL', () {
      final list = LlmPresetRepository.withBundled(const []);
      final preset = list.firstWhere((p) => p.id == 'commandcode');
      expect(preset.docUrl, contains('commandcode.ai'));
      for (final m in preset.models) {
        expect(m.baseUrl, 'https://api.commandcode.ai/provider/v1');
      }
      final free = [
        for (final m in preset.models)
          if ((m.inputCost ?? -1) == 0 && (m.outputCost ?? -1) == 0) m.id,
      ];
      expect(
        free,
        containsAll([
          'poolside/laguna-s-2.1-free',
          'inclusionai/ling-3.1-flash:free',
          'stealth/glyph-cluster:free',
        ]),
      );
    });
  });

  group('Modellfilter', () {
    test('frei nur bei bekanntem Nulltarif', () {
      expect(
        modelIsFree(_option(_model(id: 'a', inputCost: 0, outputCost: 0))),
        isTrue,
      );
      expect(
        modelIsFree(_option(_model(id: 'a', inputCost: 0, outputCost: 5))),
        isFalse,
      );
      expect(
        modelIsFree(_option(_model(id: 'a'))),
        isFalse,
        reason: 'unbekannte Preise zählen nicht als gratis',
      );
      expect(modelIsFree(_option(null)), isFalse);
    });

    test('reasoning nur mit Flag', () {
      expect(
        modelSupportsReasoning(_option(_model(id: 'a', reasoning: true))),
        isTrue,
      );
      expect(
        modelSupportsReasoning(_option(_model(id: 'a'))),
        isFalse,
      );
      expect(modelSupportsReasoning(_option(null)), isFalse);
    });
  });

  group('Modellsortierung', () {
    ModelOption _opt(String label, {num? cost}) => ModelOption(
      id: label,
      label: label,
      preset: cost == null
          ? null
          : _model(id: label, inputCost: cost, outputCost: cost),
      levels: const [],
    );

    test('Name sortiert alphabetisch', () {
      final list = [_opt('Claude'), _opt('aaron'), _opt('Berta')];
      list.sort((a, b) => compareModelOptions(a, b, ModelSort.name));
      expect([for (final o in list) o.label], ['aaron', 'Berta', 'Claude']);
    });

    test('Preis sortiert aufsteigend, unbekannt zuletzt', () {
      final list = [_opt('teuer', cost: 5), _opt('ratlos'), _opt('billig', cost: 1)];
      list.sort((a, b) => compareModelOptions(a, b, ModelSort.price));
      expect([for (final o in list) o.label], ['billig', 'teuer', 'ratlos']);
    });

    test('Standard vergleicht alles gleich', () {
      final a = _opt('x');
      final b = _opt('y');
      expect(compareModelOptions(a, b, ModelSort.standard), 0);
    });
  });
}
