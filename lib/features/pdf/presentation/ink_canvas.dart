import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../domain/ink.dart';

/// Etkin araç.
enum InkMode { none, pen, highlighter, eraser }

class InkBrush {
  const InkBrush({this.mode = InkMode.none, this.color = 0xFF202124, this.width = 0.0035});
  final InkMode mode;
  final int color;
  final double width; // genişliğe oranla

  InkBrush copyWith({InkMode? mode, int? color, double? width}) =>
      InkBrush(mode: mode ?? this.mode, color: color ?? this.color, width: width ?? this.width);
}

/// Çizgileri boyar. Koordinatlar 0–1; [size] ile piksele çevrilir.
class InkPainter extends CustomPainter {
  InkPainter(this.strokes, {this.opacity = 1});
  final List<InkStroke> strokes;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, size, s, opacity: opacity);
    }
  }

  static void paintStroke(Canvas canvas, Size size, InkStroke s, {double opacity = 1}) {
    if (s.points.isEmpty) return;
    final highlighter = s.tool == InkTool.highlighter;
    final realPressure = s.points.any((p) => p.pressure != 0.5);
    final outline = getStroke(
      [for (final p in s.points) PointVector(p.x * size.width, p.y * size.height, p.pressure)],
      options: StrokeOptions(
        size: s.width * size.width,
        thinning: highlighter ? 0 : 0.55,
        smoothing: 0.5,
        streamline: 0.45,
        simulatePressure: !realPressure && !highlighter,
        isComplete: true,
      ),
    );
    if (outline.isEmpty) return;
    final path = Path()..addPolygon(outline, true);
    final base = Color(s.color);
    final alpha = (highlighter ? 0.35 : 1.0) * opacity;
    canvas.drawPath(path, Paint()..color = base.withValues(alpha: base.a * alpha));
  }

  @override
  bool shouldRepaint(InkPainter old) => old.strokes != strokes || old.opacity != opacity;
}

/// Çizim yüzeyi: kalem çizer, parmak (kaleme izin verilmediyse) üstteki
/// yakınlaştırıcıya bırakılır. Çizgiler alanın boyutuna oranla kaydedilir.
class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.strokes,
    required this.brush,
    required this.onChanged,
    this.fingerDraws = false,
  });

  /// Bu yüzeyin düzenlenebilir çizgileri.
  final List<InkStroke> strokes;
  final InkBrush brush;
  final ValueChanged<List<InkStroke>> onChanged;

  /// Parmakla da çiz (kalemi olmayan cihazlar). Kapalıyken parmak kaydırır.
  final bool fingerDraws;

  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  List<InkPoint>? _current;
  int? _pointer;
  bool _erasing = false;

  Set<PointerDeviceKind> get _devices => {
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        if (widget.fingerDraws) ...[PointerDeviceKind.touch, PointerDeviceKind.mouse],
      };

  InkPoint _at(PointerEvent e, Size size) => InkPoint(
        (e.localPosition.dx / size.width).clamp(0.0, 1.0),
        (e.localPosition.dy / size.height).clamp(0.0, 1.0),
        e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus
            ? (e.pressure > 0 ? e.pressure.clamp(0.05, 1.0) : 0.5)
            : 0.5,
      );

  void _erase(InkPoint p) {
    final next = eraseAt(widget.strokes, p.x, p.y, 0.015);
    if (next.length != widget.strokes.length) widget.onChanged(next);
  }

  void _down(PointerDownEvent e, Size size) {
    if (!_devices.contains(e.kind) || widget.brush.mode == InkMode.none) return;
    if (_pointer != null) {
      // İkinci parmak: yakınlaştırma; yarım çizgi iptal.
      setState(() {
        _current = null;
        _pointer = null;
      });
      return;
    }
    _pointer = e.pointer;
    final p = _at(e, size);
    _erasing = widget.brush.mode == InkMode.eraser || e.kind == PointerDeviceKind.invertedStylus;
    if (_erasing) {
      _erase(p);
    } else {
      setState(() => _current = [p]);
    }
  }

  void _move(PointerMoveEvent e, Size size) {
    if (e.pointer != _pointer) return;
    final p = _at(e, size);
    if (_erasing) {
      _erase(p);
    } else {
      setState(() => _current = [...?_current, p]);
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final pts = _current;
    _pointer = null;
    _current = null;
    if (!_erasing && pts != null && pts.isNotEmpty) {
      widget.onChanged([
        ...widget.strokes,
        InkStroke(
          points: pts,
          color: widget.brush.color,
          width: widget.brush.mode == InkMode.highlighter ? widget.brush.width * 4 : widget.brush.width,
          tool: widget.brush.mode == InkMode.highlighter ? InkTool.highlighter : InkTool.pen,
        ),
      ]);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawing = widget.brush.mode != InkMode.none;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final current = _current;
      final painted = Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: InkPainter(widget.strokes), isComplex: true)),
          if (current != null)
            CustomPaint(
              painter: InkPainter([
                InkStroke(
                  points: current,
                  color: widget.brush.color,
                  width: widget.brush.mode == InkMode.highlighter ? widget.brush.width * 4 : widget.brush.width,
                  tool: widget.brush.mode == InkMode.highlighter ? InkTool.highlighter : InkTool.pen,
                ),
              ]),
            ),
        ],
      );
      if (!drawing) return IgnorePointer(child: painted);
      // Çizen aygıtlar hareket yarışını hemen kazanır: üstteki yakınlaştırıcı
      // onlarla kaydırmaz; diğer aygıtlar (parmak) kaydırmaya devam eder.
      return RawGestureDetector(
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(supportedDevices: _devices),
            (_) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: (e) => _move(e, size),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: painted,
        ),
      );
    });
  }
}
