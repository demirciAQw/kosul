import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/library.dart';
import '../../domain/progress.dart';
import '../../../../app/palette.dart';

/// Testin sonucuna göre renk: yeşil (iyi), amber (orta), kırmızı (zayıf);
/// sayısız "çözüldü" ana renk; çözülmemiş soluk.
Color testColor(BuildContext context, TestResult? r) {
  final scheme = Theme.of(context).colorScheme;
  if (r == null) return scheme.surfaceContainerHighest;
  final answered = (r.correct ?? 0) + (r.wrong ?? 0) + (r.blank ?? 0);
  if (!r.hasCounts || answered == 0) return scheme.primary;
  final ratio = (r.correct ?? 0) / answered;
  if (ratio >= 0.8) return KocumColors.good;
  if (ratio >= 0.5) return KocumColors.fair;
  return KocumColors.weak;
}

/// Ortası yüzde yazan ilerleme halkası.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 64, this.stroke = 7, this.label});

  final double value; // 0–1
  final double size;
  final double stroke;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = label ?? '%${(value * 100).round()}';
    return Semantics(
      label: 'İlerleme $text',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value.clamp(0.0, 1.0).toDouble(),
            stroke: stroke,
            track: scheme.surfaceContainerHighest,
            color: scheme.primary,
          ),
          child: Center(
            child: Text(
              text,
              style: (size >= 80 ? theme.textTheme.titleLarge : theme.textTheme.labelLarge)
                  ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.stroke, required this.track, required this.color});

  final double value;
  final double stroke;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Kitap haritası: her test (yaprak başlık) bir kare; satırlar üniteler.
/// Bir bakışta neyin bittiği, neyin zayıf kaldığı görünür.
class BookMap extends StatelessWidget {
  const BookMap({super.key, required this.book, required this.results, this.cell = 14});

  final Book book;
  final Map<String, TestResult> results;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final root in book.roots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  root.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final leaf in leavesUnder(root))
                      Tooltip(
                        message: leaf.title,
                        child: Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            color: testColor(context, results[leaf.id]),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Renklerin anlamı (kitap haritasının altında).
class BookMapLegend extends StatelessWidget {
  const BookMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 4),
            Text(t, style: theme.textTheme.labelSmall),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(KocumColors.good, '%80+'),
        item(KocumColors.fair, '%50–80'),
        item(KocumColors.weak, '%50 altı'),
        item(scheme.primary, 'çözüldü'),
        item(scheme.surfaceContainerHighest, 'çözülmedi'),
      ],
    );
  }
}

/// D/Y/B oranlarını gösteren ince yatay şerit.
class ResultBar extends StatelessWidget {
  const ResultBar({super.key, required this.correct, required this.wrong, required this.blank, this.height = 8});

  final int correct;
  final int wrong;
  final int blank;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = correct + wrong + blank;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (correct > 0) Expanded(flex: correct, child: ColoredBox(color: KocumColors.good)),
            if (wrong > 0) Expanded(flex: wrong, child: ColoredBox(color: KocumColors.weak)),
            if (blank > 0) Expanded(flex: blank, child: ColoredBox(color: KocumColors.fair)),
          ],
        ),
      ),
    );
  }
}
