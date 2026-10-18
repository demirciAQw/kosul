import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/app/palette.dart';
import 'package:kocum/app/theme.dart';

/// WCAG kontrast oranı (göreli parlaklık).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('açık ve koyu tema kurulur, ana renk Google mavisi', () {
    expect(AppTheme.light.colorScheme.primary, KocumColors.blue);
    expect(AppTheme.dark.colorScheme.primary, KocumColors.blueDark);
    expect(AppTheme.light.colorScheme.brightness, Brightness.light);
    expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
  });

  test('metin ve anlam renkleri okunur kontrastta (WCAG AA)', () {
    final light = AppTheme.light.colorScheme;
    final dark = AppTheme.dark.colorScheme;
    expect(_contrast(light.onSurface, Colors.white), greaterThan(4.5));
    expect(_contrast(light.onSurfaceVariant, Colors.white), greaterThan(4.5));
    expect(_contrast(dark.onSurface, dark.surface), greaterThan(4.5));
    // Optik balonlarında beyaz rakam: doğru, yanlış, boş.
    for (final c in [KocumColors.correct, KocumColors.wrong, KocumColors.blank]) {
      expect(_contrast(Colors.white, c), greaterThan(3.0), reason: '$c');
    }
  });
}
