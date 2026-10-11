import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/assistant_tools.dart';

void main() {
  group('buildTurnContext attachedImages', () {
    test('ohne Bilder kein Bild-Hinweis', () {
      final ctx = buildTurnContext(nowLocal: DateTime(2026, 1, 1));
      expect(ctx.contains('Images attached'), isFalse);
    });

    test('mit Bildern stehen die Dateinamen drin', () {
      final ctx = buildTurnContext(
        nowLocal: DateTime(2026, 1, 1),
        attachedImages: const ['image-abc.jpg'],
      );
      expect(ctx, contains('image-abc.jpg'));
    });
  });

  group('createDiary/updateDiary Schema', () {
    Object? imagesParam(Map<String, dynamic> schema) {
      final props = schema['properties'] as Map;
      final items = props['items'] as Map;
      final itemSchema = (items['items'] ?? items) as Map;
      final itemProps = itemSchema['properties'] as Map;
      return itemProps['images'];
    }

    test('createDiary kennt images-Array', () {
      final spec = AssistantToolRegistry.byId(AssistantTool.createDiary.id)!;
      final param = imagesParam(spec.jsonSchema);
      expect(param, isNotNull);
      expect((param as Map)['type'], 'array');
    });

    test('updateDiary kennt images-Array', () {
      final spec = AssistantToolRegistry.byId(AssistantTool.updateDiary.id)!;
      final param = imagesParam(spec.jsonSchema);
      expect(param, isNotNull);
      expect((param as Map)['type'], 'array');
    });
  });

  group('resolveImageNames', () {
    test('filtert Müll, behält existierende, deckelt', () async {
      final names = await AssistantToolRegistry.resolveImageNames(
        [' a.jpg ', '', '  ', 'a.jpg', 42, null, 'b.jpg'],
        exists: (name) async => name == 'a.jpg',
      );
      expect(names, ['a.jpg']);
    });

    test('eckige Klammern gelten als unsicher', () async {
      final names = await AssistantToolRegistry.resolveImageNames(
        ['x].jpg', 'y[.jpg', 'ok.jpg'],
        exists: (name) async => true,
      );
      expect(names, ['ok.jpg']);
    });

    test('keine Liste → leer', () async {
      expect(
        await AssistantToolRegistry.resolveImageNames(
          'a.jpg',
          exists: (name) async => true,
        ),
        isEmpty,
      );
      expect(
        await AssistantToolRegistry.resolveImageNames(
          null,
          exists: (name) async => true,
        ),
        isEmpty,
      );
    });

    test('maximal 10 Namen', () async {
      final many = [for (var i = 0; i < 30; i++) 'img-$i.jpg'];
      final names = await AssistantToolRegistry.resolveImageNames(
        many,
        exists: (name) async => true,
      );
      expect(names, hasLength(10));
    });
  });
}
