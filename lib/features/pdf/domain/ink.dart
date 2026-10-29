import 'dart:convert';

/// Kalem noktası: sayfaya (ya da soru bölgesine) oranla 0–1; baskı 0–1.
/// Oranla saklandığı için büyütme, küçültme ve ekran boyutu çizgiyi kaydırmaz.
class InkPoint {
  const InkPoint(this.x, this.y, [this.pressure = 0.5]);
  final double x;
  final double y;
  final double pressure;
}

enum InkTool { pen, highlighter }

class InkStroke {
  const InkStroke({required this.points, required this.color, required this.width, this.tool = InkTool.pen});
  final List<InkPoint> points;
  final int color; // ARGB
  final double width; // genişliğe oranla (ör. 0.004)
  final InkTool tool;

  ({double x0, double y0, double x1, double y1}) get bounds {
    var x0 = 1.0, y0 = 1.0, x1 = 0.0, y1 = 0.0;
    for (final p in points) {
      if (p.x < x0) x0 = p.x;
      if (p.y < y0) y0 = p.y;
      if (p.x > x1) x1 = p.x;
      if (p.y > y1) y1 = p.y;
    }
    return (x0: x0, y0: y0, x1: x1, y1: y1);
  }

  static double _r(double v, int digits) {
    final f = digits == 4 ? 10000 : 100;
    return (v * f).roundToDouble() / f;
  }

  /// Kısa JSON: {"c": renk, "w": kalınlık, "t": araç, "p": [x, y, baskı, …]}.
  Map<String, Object> toJson() => {
        'c': color,
        'w': _r(width * 100, 4) / 100,
        't': tool.name,
        'p': [
          for (final p in points) ...[_r(p.x, 4), _r(p.y, 4), _r(p.pressure, 2)],
        ],
      };

  static InkStroke? fromJson(Object? j) {
    if (j is! Map) return null;
    final raw = j['p'];
    final c = j['c'];
    final w = j['w'];
    if (raw is! List || c is! int || w is! num) return null;
    final pts = <InkPoint>[];
    for (var i = 0; i + 2 < raw.length; i += 3) {
      final x = raw[i], y = raw[i + 1], p = raw[i + 2];
      if (x is num && y is num && p is num) pts.add(InkPoint(x.toDouble(), y.toDouble(), p.toDouble()));
    }
    if (pts.isEmpty) return null;
    return InkStroke(
      points: pts,
      color: c,
      width: w.toDouble(),
      tool: j['t'] == 'highlighter' ? InkTool.highlighter : InkTool.pen,
    );
  }
}

String encodeStrokes(List<InkStroke> strokes) => jsonEncode([for (final s in strokes) s.toJson()]);

/// Bozuk ya da eski kayıtlara dayanıklı: okunamayan çizgi atlanır.
List<InkStroke> decodeStrokes(String json) {
  try {
    final list = jsonDecode(json);
    if (list is! List) return const [];
    return [for (final j in list) InkStroke.fromJson(j)].whereType<InkStroke>().toList();
  } catch (_) {
    return const [];
  }
}

/// Silgi: (x, y) noktasına [radius] kadar yakın noktası olan çizgiler silinir.
List<InkStroke> eraseAt(List<InkStroke> strokes, double x, double y, double radius) {
  final r2 = radius * radius;
  return [
    for (final s in strokes)
      if (!s.points.any((p) => (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) <= r2)) s,
  ];
}

/// Sayfadaki çizgilerden soru bölgesine düşenler (noktalarının en az %60'ı
/// içinde), bölgeye oranlanmış olarak. Soruyu seçerken ilk çözüm soruyla gelir.
List<InkStroke> strokesInRect(List<InkStroke> strokes, double x0, double y0, double x1, double y1) {
  final w = x1 - x0, h = y1 - y0;
  if (w <= 0 || h <= 0) return const [];
  bool inside(InkPoint p) => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;
  return [
    for (final s in strokes)
      if (s.points.where(inside).length >= 0.6 * s.points.length)
        InkStroke(
          color: s.color,
          width: s.width / w,
          tool: s.tool,
          points: [for (final p in s.points) InkPoint((p.x - x0) / w, (p.y - y0) / h, p.pressure)],
        ),
  ];
}
