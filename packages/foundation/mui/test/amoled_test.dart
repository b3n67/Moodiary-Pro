import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mui/mui.dart';

void main() {
  const black = Color(0xFF000000);

  test('amoled dunkel zieht alle Flächen auf Schwarz', () {
    final cs = buildMuiTheme(
      brightness: Brightness.dark,
      amoled: true,
    ).colorScheme;
    expect(cs.surface, black);
    expect(cs.surfaceContainerLowest, black);
    expect(cs.surfaceContainerLow, black);
    expect(cs.surfaceContainer, black);
    expect(cs.surfaceContainerHigh, black);
    expect(cs.surfaceContainerHighest, black);
    // Text und Akzent bleiben lesbar/farbig.
    expect(cs.onSurface, isNot(black));
    expect(cs.primary, isNot(black));
  });

  test('ohne amoled und im Hellen ändert sich nichts', () {
    final dark = buildMuiTheme(brightness: Brightness.dark).colorScheme;
    expect(dark.surfaceContainer, isNot(black));
    final lightAmoled = buildMuiTheme(
      brightness: Brightness.light,
      amoled: true,
    ).colorScheme;
    expect(lightAmoled.surface, isNot(black));
  });
}
