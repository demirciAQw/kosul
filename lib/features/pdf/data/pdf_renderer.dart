import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../../core/media/media_storage.dart';
import '../domain/pdf_models.dart';

/// PDF'i çizer: sayfanın tamamını ya da seçilen soru bölgesini istenen
/// genişlikte. Belgeler açık tutulur; son çizilenler bellekte önbelleklenir.
class PdfRenderer {
  PdfRenderer(this._media);
  final MediaStorage _media;

  final _docs = <String, Future<PdfDocument>>{};
  final _cache = LinkedHashMap<String, ui.Image>();
  static const _cacheSize = 24;

  Future<PdfDocument> _open(PdfBook book) =>
      _docs.putIfAbsent(book.id, () => PdfDocument.openFile(_media.resolve(book.filePath).path));

  /// Sayfanın boyutu (PDF noktası).
  Future<({double width, double height})> pageSize(PdfBook book, int page) async {
    final p = (await _open(book)).pages[page];
    return (width: p.width, height: p.height);
  }

  /// Sayfa ya da bölge ([x0]..[y1] sayfaya oranla) [targetWidth] piksel genişlikte.
  Future<ui.Image?> render(
    PdfBook book,
    int page, {
    required double targetWidth,
    double x0 = 0,
    double y0 = 0,
    double x1 = 1,
    double y1 = 1,
  }) async {
    final key = '${book.id}:$page:${x0.toStringAsFixed(4)},${y0.toStringAsFixed(4)},'
        '${x1.toStringAsFixed(4)},${y1.toStringAsFixed(4)}@${targetWidth.round()}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // en yeni
      return hit;
    }
    final doc = await _open(book);
    if (page < 0 || page >= doc.pages.length) return null;
    final p = doc.pages[page];
    final fullW = targetWidth / (x1 - x0);
    final scale = fullW / p.width;
    final fullH = p.height * scale;
    final img = await p.render(
      x: (x0 * fullW).floor(),
      y: (y0 * fullH).floor(),
      width: ((x1 - x0) * fullW).ceil(),
      height: ((y1 - y0) * fullH).ceil(),
      fullWidth: fullW,
      fullHeight: fullH,
      backgroundColor: 0xFFFFFFFF,
    );
    if (img == null) return null;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(img.pixels, img.width, img.height, ui.PixelFormat.bgra8888, done.complete);
    final out = await done.future;
    img.dispose();
    _cache[key] = out;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return out;
  }

  /// PDF'i medya klasörüne kopyalar ve sayfa sayısını okur.
  Future<({String filePath, int pageCount})> import(String sourcePath) async {
    final rel = await _media.importFile(sourcePath, bucket: 'pdf');
    final doc = await PdfDocument.openFile(_media.resolve(rel).path);
    final count = doc.pages.length;
    await doc.dispose();
    return (filePath: rel, pageCount: count);
  }
}
