import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

class NetPoint {
  const NetPoint(this.date, this.net);
  final DateTime date;
  final double net;
}

/// Denemeler boyunca net çizgisi (eskiden yeniye). Son nokta etiketlenir.
class NetChart extends StatelessWidget {
  const NetChart({super.key, required this.points, this.maxNet, this.height = 170});

  final List<NetPoint> points;

  /// Eksenin üst sınırı için ipucu (ör. 120 soruluk TYT). Verilmezse veriden.
  final double? maxNet;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Net grafiği, ${points.length} deneme, son net ${formatNet(points.last.net)}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _NetChartPainter(
            points: points,
            maxHint: maxNet,
            line: scheme.primary,
            grid: scheme.outlineVariant,
            label: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant) ??
                TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            emphasis: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700) ??
                TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w700),
            surface: scheme.surface,
          ),
        ),
      ),
    );
  }
}

class _NetChartPainter extends CustomPainter {
  _NetChartPainter({
    required this.points,
    required this.maxHint,
    required this.line,
    required this.grid,
    required this.label,
    required this.emphasis,
    required this.surface,
  });

  final List<NetPoint> points;
  final double? maxHint;
  final Color line;
  final Color grid;
  final TextStyle label;
  final TextStyle emphasis;
  final Color surface;

  static const _left = 34.0;
  static const _right = 12.0;
  static const _top = 18.0;
  static const _bottom = 22.0;

  TextPainter _text(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final nets = points.map((p) => p.net);
    final dataMax = nets.reduce(math.max);
    final dataMin = nets.reduce(math.min);
    final lo = math.min(0.0, dataMin);
    var hi = math.max(dataMax, 1.0);
    final hint = maxHint;
    if (hint != null && dataMax > hint * 0.6) hi = math.max(hi, hint);
    hi = (hi * 1.1).ceilToDouble();
    final span = hi - lo == 0 ? 1.0 : hi - lo;

    final chart = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    double yOf(double v) => chart.bottom - (v - lo) / span * chart.height;
    double xOf(int i) =>
        points.length == 1 ? chart.center.dx : chart.left + i * chart.width / (points.length - 1);

    // Izgara: alt, orta, üst.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [lo, (lo + hi) / 2, hi]) {
      final y = yOf(v);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final t = _text(formatNet(v), label);
      t.paint(canvas, Offset(chart.left - t.width - 6, y - t.height / 2));
    }

    // Çizgi.
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(i), yOf(points[i].net));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    // Noktalar.
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(i), yOf(points[i].net));
      canvas.drawCircle(o, 4, Paint()..color = surface);
      canvas.drawCircle(
        o,
        4,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Son netin etiketi.
    final last = Offset(xOf(points.length - 1), yOf(points.last.net));
    final tag = _text(formatNet(points.last.net), emphasis);
    final tagX = math.min(last.dx - tag.width / 2, size.width - tag.width);
    tag.paint(canvas, Offset(math.max(chart.left, tagX), math.max(0.0, last.dy - tag.height - 6)));

    // Tarihler: ilk ve son.
    final first = _text(formatDayMonth(points.first.date), label);
    first.paint(canvas, Offset(chart.left, chart.bottom + 6));
    if (points.length > 1) {
      final end = _text(formatDayMonth(points.last.date), label);
      end.paint(canvas, Offset(chart.right - end.width, chart.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(_NetChartPainter old) =>
      old.points != points || old.line != line || old.maxHint != maxHint || old.grid != grid;
}
