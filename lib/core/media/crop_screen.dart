import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'photo_capture_service.dart' show CropOutput;

/// Sürüklenen parça: köşe, kenar ya da tüm seçim.
enum _Drag { move, left, top, right, bottom, corner }

/// Uygulama içi kırpma ekranı.
///
/// Harici uCrop ekranının yerine geçer: AppBar ve alt çubuk sistem çubuklarının
/// payını kendisi bırakır, butonlar durum çubuğunun altına kaymaz.
/// Seçim normalize (0–1) koordinatlarda tutulur; ekran dönse ya da boyut
/// değişse de seçim bozulmaz. Çıktı, kırpılmış bölgenin PNG baytlarıdır;
/// WebP'ye sıkıştırma çağıran tarafta (PhotoCaptureService) yapılır.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.sourcePath, required this.title, this.maxOutputSide = 2880});

  final String sourcePath;
  final String title;

  /// Çıktının en uzun kenarı (hızlı modda daha küçük).
  final double maxOutputSide;

  /// Ham RGBA çıktı döner (PNG kodlaması yok: ekran anında kapanır, sıkıştırma
  /// arka planda yapılır). Vazgeçilirse null.
  static Future<CropOutput?> open(
    BuildContext context, {
    required String sourcePath,
    required String title,
    double maxOutputSide = 2880,
  }) {
    return Navigator.of(context, rootNavigator: true).push<CropOutput>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(sourcePath: sourcePath, title: title, maxOutputSide: maxOutputSide),
      ),
    );
  }

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  static const _hitRadius = 30.0; // köşe/kenar yakalama mesafesi (px)
  static const _minCropPx = 48.0;
  static const _padding = 20.0;

  ui.Image? _image;
  Object? _error;
  bool _busy = false;

  Rect _crop = const Rect.fromLTRB(0.04, 0.04, 0.96, 0.96);
  Rect _imageRect = Rect.zero; // ekrandaki görüntü alanı (son yerleşimden)

  _Drag? _drag;
  Rect _beforeDrag = Rect.zero;
  Offset _anchor = Offset.zero; // köşe sürüklemede sabit kalan karşı köşe
  Offset _moving = Offset.zero; // köşe sürüklemede hareket eden köşe

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  // ───────────────────────── Koordinat dönüşümleri ─────────────────────────

  static double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  Rect _toScreen(Rect n) => Rect.fromLTRB(
        _imageRect.left + n.left * _imageRect.width,
        _imageRect.top + n.top * _imageRect.height,
        _imageRect.left + n.right * _imageRect.width,
        _imageRect.top + n.bottom * _imageRect.height,
      );

  Offset _toNormalized(Offset screen) => Offset(
        _clamp((screen.dx - _imageRect.left) / _imageRect.width, 0, 1),
        _clamp((screen.dy - _imageRect.top) / _imageRect.height, 0, 1),
      );

  double get _minW => _imageRect.width == 0 ? 0.05 : _minCropPx / _imageRect.width;
  double get _minH => _imageRect.height == 0 ? 0.05 : _minCropPx / _imageRect.height;

  // ───────────────────────── Sürükleme ─────────────────────────

  void _onPanStart(Offset pos) {
    if (_busy || _imageRect.isEmpty) return;
    final c = _toScreen(_crop);
    _beforeDrag = _crop;

    // 1) Köşeler: karşı köşe sabitlenir, seçim ters yöne de çevrilebilir.
    final corners = <(Offset, Offset)>[
      (c.topLeft, c.bottomRight),
      (c.topRight, c.bottomLeft),
      (c.bottomLeft, c.topRight),
      (c.bottomRight, c.topLeft),
    ];
    for (final (corner, opposite) in corners) {
      if ((pos - corner).distance <= _hitRadius) {
        _drag = _Drag.corner;
        _moving = _toNormalized(corner);
        _anchor = _toNormalized(opposite);
        return;
      }
    }

    // 2) Kenarlar.
    final withinV = pos.dy > c.top && pos.dy < c.bottom;
    final withinH = pos.dx > c.left && pos.dx < c.right;
    const edge = _hitRadius * 0.8;
    if (withinV && (pos.dx - c.left).abs() <= edge) {
      _drag = _Drag.left;
    } else if (withinV && (pos.dx - c.right).abs() <= edge) {
      _drag = _Drag.right;
    } else if (withinH && (pos.dy - c.top).abs() <= edge) {
      _drag = _Drag.top;
    } else if (withinH && (pos.dy - c.bottom).abs() <= edge) {
      _drag = _Drag.bottom;
    } else if (c.contains(pos)) {
      _drag = _Drag.move;
    } else if (_imageRect.inflate(_hitRadius).contains(pos)) {
      // 3) Seçimin dışında: dokunulan noktadan yeni bir alan çiz.
      final start = _toNormalized(pos);
      _drag = _Drag.corner;
      _anchor = start;
      _moving = start;
    } else {
      _drag = null;
    }
  }

  void _onPanUpdate(Offset delta) {
    final drag = _drag;
    if (drag == null || _imageRect.isEmpty) return;
    final dx = delta.dx / _imageRect.width;
    final dy = delta.dy / _imageRect.height;
    final r = _crop;
    setState(() {
      switch (drag) {
        case _Drag.move:
          final nx = _clamp(r.left + dx, 0, 1 - r.width);
          final ny = _clamp(r.top + dy, 0, 1 - r.height);
          _crop = Rect.fromLTWH(nx, ny, r.width, r.height);
        case _Drag.left:
          _crop = Rect.fromLTRB(_clamp(r.left + dx, 0, r.right - _minW), r.top, r.right, r.bottom);
        case _Drag.right:
          _crop = Rect.fromLTRB(r.left, r.top, _clamp(r.right + dx, r.left + _minW, 1), r.bottom);
        case _Drag.top:
          _crop = Rect.fromLTRB(r.left, _clamp(r.top + dy, 0, r.bottom - _minH), r.right, r.bottom);
        case _Drag.bottom:
          _crop = Rect.fromLTRB(r.left, r.top, r.right, _clamp(r.bottom + dy, r.top + _minH, 1));
        case _Drag.corner:
          _moving = Offset(_clamp(_moving.dx + dx, 0, 1), _clamp(_moving.dy + dy, 0, 1));
          _crop = Rect.fromPoints(_anchor, _moving);
      }
    });
  }

  void _onPanEnd() {
    if (_drag == null) return;
    _drag = null;
    // Parmak kaydı ya da çok küçük alan: önceki seçime dön.
    if (_crop.width < _minW || _crop.height < _minH) {
      setState(() => _crop = _beforeDrag);
    }
  }

  // ───────────────────────── İşlemler ─────────────────────────

  /// Görüntüyü 90° saat yönünde çevirir; seçim de onunla birlikte döner.
  Future<void> _rotate() async {
    final src = _image;
    if (src == null || _busy) return;
    setState(() => _busy = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(src.height.toDouble(), 0);
      canvas.rotate(math.pi / 2);
      canvas.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.high);
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(src.height, src.width);
      picture.dispose();
      if (!mounted) {
        rotated.dispose();
        return;
      }
      final r = _crop;
      setState(() {
        _image = rotated;
        // (x, y) → (1 − y, x)
        _crop = Rect.fromLTRB(1 - r.bottom, r.left, 1 - r.top, r.right);
        _busy = false;
      });
      src.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Döndürülemedi: $e');
    }
  }

  Future<void> _finish() async {
    final image = _image;
    if (image == null || _busy) return;
    setState(() => _busy = true);
    try {
      final src = Rect.fromLTRB(
        _crop.left * image.width,
        _crop.top * image.height,
        _crop.right * image.width,
        _crop.bottom * image.height,
      );
      final longest = math.max(src.width, src.height);
      final maxSide = widget.maxOutputSide;
      final scale = longest > maxSide ? maxSide / longest : 1.0;
      final w = math.max(1, (src.width * scale).round());
      final h = math.max(1, (src.height * scale).round());

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(w, h);
      picture.dispose();
      // Ham pikseller: GPU'dan okumak hızlıdır; PNG kodlaması (saniyeler) yok.
      final data = await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
      cropped.dispose();
      if (!mounted) return;
      if (data == null) throw StateError('görüntü üretilemedi');
      Navigator.of(context).pop(CropOutput(data.buffer.asUint8List(), w, h));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Kırpılamadı: $e');
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // ───────────────────────── Görünüm ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final accent = Theme.of(context).colorScheme.primaryContainer;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Vazgeç',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Fotoğraf açılamadı: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : image == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final availW = constraints.maxWidth - 2 * _padding;
                          final availH = constraints.maxHeight - 2 * _padding;
                          final scale = math.min(availW / image.width, availH / image.height);
                          final w = image.width * scale;
                          final h = image.height * scale;
                          _imageRect = Rect.fromLTWH(
                            (constraints.maxWidth - w) / 2,
                            (constraints.maxHeight - h) / 2,
                            w,
                            h,
                          );
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) => _onPanStart(d.localPosition),
                            onPanUpdate: (d) => _onPanUpdate(d.delta),
                            onPanEnd: (_) => _onPanEnd(),
                            onPanCancel: _onPanEnd,
                            child: Stack(
                              children: [
                                Positioned.fromRect(
                                  rect: _imageRect,
                                  child: RawImage(
                                    image: image,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _CropPainter(
                                      crop: _toScreen(_crop),
                                      bounds: _imageRect,
                                      accent: accent,
                                    ),
                                  ),
                                ),
                                if (_busy)
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black38,
                                      child: Center(child: CircularProgressIndicator()),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Köşeleri ya da kenarları sürükle. Seçimin dışından sürükleyerek yeni alan çizebilirsin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Sağa döndür',
                              color: Colors.white,
                              onPressed: _busy ? null : _rotate,
                              icon: const Icon(Icons.rotate_right_rounded),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                              onPressed: _busy ? null : () => setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1)),
                              child: const Text('Tümünü seç'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                              onPressed: _busy ? null : _finish,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Kırp'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.crop, required this.bounds, required this.accent});

  final Rect crop;
  final Rect bounds;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addRect(crop);
    canvas.drawPath(outside, Paint()..color = const Color(0xB0000000));

    final grid = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }

    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final handle = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(sx * len, 0), handle);
      canvas.drawLine(o, o + Offset(0, sy * len), handle);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);

    // Kenar ortası tutamaçları: kenardan da sürüklenebildiğini gösterir.
    const half = 10.0;
    final mid = crop.center;
    canvas.drawLine(Offset(mid.dx - half, crop.top), Offset(mid.dx + half, crop.top), handle);
    canvas.drawLine(Offset(mid.dx - half, crop.bottom), Offset(mid.dx + half, crop.bottom), handle);
    canvas.drawLine(Offset(crop.left, mid.dy - half), Offset(crop.left, mid.dy + half), handle);
    canvas.drawLine(Offset(crop.right, mid.dy - half), Offset(crop.right, mid.dy + half), handle);
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.bounds != bounds || oldDelegate.accent != accent;
}
