import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/app/theme.dart';
import 'package:kocum/features/mock_exam/presentation/widgets/net_chart.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('çip yazısı her durumda görünür (açık ve koyu tema)', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final style = theme.chipTheme.labelStyle!;
      final color = style.color;
      // Flutter yalnızca rengi duruma göre çözer: renk durum rengi olmalı, boş olmamalı.
      expect(color, isA<WidgetStateColor>(), reason: '${theme.brightness}');
      final resolve = (color! as WidgetStateColor).resolve;
      final scheme = theme.colorScheme;
      final background = theme.chipTheme.backgroundColor!;
      expect(_contrast(resolve(const {}), background), greaterThan(4.5), reason: 'seçisiz ${theme.brightness}');
      expect(_contrast(resolve(const {WidgetState.selected}), scheme.primaryContainer), greaterThan(4.5),
          reason: 'seçili ${theme.brightness}');
      expect(resolve(const {WidgetState.disabled}).a, greaterThan(0));
    }
  });

  test('grafikte dokunulan yer en yakın noktaya eşlenir', () {
    // Genişlik 346: çizim alanı 34..334; 3 nokta 34, 184, 334'te.
    expect(nearestPointIndex(346, 3, 30), 0);
    expect(nearestPointIndex(346, 3, 190), 1);
    expect(nearestPointIndex(346, 3, 340), 2);
    expect(nearestPointIndex(346, 3, 400), 2); // taşma sıkıştırılır
    expect(nearestPointIndex(346, 1, 100), 0);
  });
}
