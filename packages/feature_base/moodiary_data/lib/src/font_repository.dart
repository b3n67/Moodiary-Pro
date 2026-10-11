import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_theme/moodiary_theme.dart';

import 'db/database.dart';

@lazySingleton
class FontRepository {
  FontRepository(this._db);

  final MoodiaryDatabase _db;

  static Font _toFont(FontRow r) => Font(
    fontFileName: r.fontFileName,
    fontWghtAxisMap: (jsonDecode(r.wghtAxisJson) as Map)
        .cast<String, dynamic>(),
  );

  Future<List<Font>> getAllFonts() async {
    final rows = await _db.select(_db.fonts).get();
    return [for (final r in rows) _toFont(r)];
  }

  /// Mitgeliefert unter `assets/fonts/`: Asset-Dateiname → kanonischer
  /// Dateiname aus dem Name-Table (volle Namen, vgl. Ausgabe von
  /// `FontManager.getFontName`). Kanonisch, weil der Rest der App
  /// Dateinamen aus dem Name-Table ableitet (`addFont`, `scanDiskFonts`).
  static const bundledFonts = {
    'Arimo.ttf': 'Arimo Regular.ttf',
    'Tinos.ttf': 'Tinos Regular.ttf',
    'Lato.ttf': 'Lato Regular.ttf',
    'Nunito.ttf': 'Nunito ExtraLight.ttf',
    'OpenSans.ttf': 'Open Sans Regular.ttf',
  };

  static const int _bundledSeedVersion = 1;

  Future<void>? _seeding;

  /// Kopiert fehlende mitgelieferte Schriften aus den Assets in den
  /// Schriften-Ordner und trägt sie in die Datenbank ein (Upsert).
  /// Versionsmarke wie bei den Prompt-Presets; läuft auch nach Restore
  /// oder Dateiverlust heilend nach (Datei- und DB-Bestand entscheiden,
  /// die Marke wird nur bei vollem Erfolg gesetzt).
  /// Gleichzeitige Aufrufe teilen sich einen Lauf (kein doppeltes Schreiben).
  Future<void> ensureSeeded() async {
    final pending = _seeding;
    if (pending != null) return pending;
    try {
      await (_seeding = _seed());
    } finally {
      _seeding = null;
    }
  }

  Future<void> _seed() async {
    if ((MoodiaryKVs.bundledFontSeedVersion.get() ?? 0) >=
        _bundledSeedVersion) {
      final rows = await getAllFonts();
      final files = {for (final f in rows) f.fontFileName};
      if (bundledFonts.values.every(
        (n) =>
            files.contains(n) &&
            File(AppFiles.getRealPath('font', n)).existsSync(),
      )) {
        return;
      }
    }
    var ok = true;
    for (final entry in bundledFonts.entries) {
      try {
        final path = AppFiles.getRealPath('font', entry.value);
        if (!File(path).existsSync()) {
          final data = await rootBundle.load('assets/fonts/${entry.key}');
          await File(path).writeAsBytes(data.buffer.asUint8List());
        }
        await insertFont(
          Font(
            fontFileName: entry.value,
            fontWghtAxisMap: await FontManager.getFontWghtAxis(
              filePath: path,
            ),
          ),
        );
      } catch (_) {
        // Eine kaputte/missing Asset-Schrift blockiert nicht den Rest;
        // die Marke wird dann nicht gesetzt und der Lauf wiederholt sich.
        ok = false;
      }
    }
    if (ok) MoodiaryKVs.bundledFontSeedVersion.set(_bundledSeedVersion);
  }

  Future<List<Font>> scanDiskFonts() async {
    final scanned = await FontManager.scanFontFiles();
    return [
      for (final f in scanned)
        Font(fontFileName: f.fileName, fontWghtAxisMap: f.wghtAxis),
    ];
  }

  Future<Font?> getFontByFontFamily(String fontFamily) async {
    final row = await (_db.select(
      _db.fonts,
    )..where((f) => f.fontFamily.equals(fontFamily))).getSingleOrNull();
    return row == null ? null : _toFont(row);
  }

  Future<void> insertFont(Font font) async {
    await _db
        .into(_db.fonts)
        .insertOnConflictUpdate(
          FontsCompanion.insert(
            fontFamily: font.fontFamily,
            fontFileName: font.fontFileName,
            wghtAxisJson: Value(jsonEncode(font.fontWghtAxisMap)),
          ),
        );
  }

  Future<void> deleteFontByFamily(String fontFamily) async {
    await (_db.delete(
      _db.fonts,
    )..where((f) => f.fontFamily.equals(fontFamily))).go();
  }

  Future<Font?> getActiveFont() async {
    final family = MoodiaryKVs.customFont.get();
    if (family == null || family.isEmpty) return null;
    return getFontByFontFamily(family);
  }
}

extension FontThemeDescriptor on Font {
  ActiveFontDescriptor get themeDescriptor =>
      (family: fontFamily, fileName: fontFileName, wghtAxis: fontWghtAxisMap);
}
