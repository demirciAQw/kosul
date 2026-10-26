import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Şekil bulucu için küçültülmüş görüntü (RGBA) ve asıl boyutlar.
class SampledImage {
  const SampledImage(this.rgba, this.width, this.height, this.fullWidth, this.fullHeight);
  final Uint8List rgba;
  final int width, height; // küçültülmüş
  final int fullWidth, fullHeight; // asıl (OCR koordinatları bunlara göre)
}

abstract interface class PageImageTools {
  /// Görüntüyü en uzun kenarı [maxSide] olacak şekilde çözer.
  Future<SampledImage?> sample(String path, {int maxSide = 640});

  /// [degrees] kadar döndürülmüş geçici JPEG; olmazsa null. Çağıran siler.
  Future<String?> rotate(String path, int degrees);

  /// Normalize [box] (sol, üst, sağ, alt) bölgesinin geçici PNG'si; olmazsa null. Çağıran siler.
  Future<String?> crop(String path, List<double> box);
}

/// Telefonda: çözme JPEG/WebP çözücüsünün kendi küçültmesiyle (hızlı, az bellek),
/// döndürme sıkıştırma eklentisiyle (yeni bağımlılık yok).
class FlutterPageImageTools implements PageImageTools {
  @override
  Future<SampledImage?> sample(String path, {int maxSide = 640}) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final fw = descriptor.width, fh = descriptor.height;
      final scale = maxSide / math.max(fw, fh);
      final codec = await descriptor.instantiateCodec(
        targetWidth: scale < 1 ? (fw * scale).round() : fw,
        targetHeight: scale < 1 ? (fh * scale).round() : fh,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = data == null
          ? null
          : SampledImage(data.buffer.asUint8List(), frame.image.width, frame.image.height, fw, fh);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return out;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> crop(String path, List<double> box) async {
    try {
      final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final src = ui.Rect.fromLTRB(box[0] * img.width, box[1] * img.height, box[2] * img.width, box[3] * img.height)
          .inflate(8)
          .intersect(ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()));
      final scale = math.min(1.0, 1024 / math.max(src.width, src.height));
      final w = math.max(1, (src.width * scale).round()), h = math.max(1, (src.height * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(img, src, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
      final picture = recorder.endRecording();
      final out = await picture.toImage(w, h);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      out.dispose();
      img.dispose();
      codec.dispose();
      if (png == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ocr_sekil_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> rotate(String path, int degrees) async {
    try {
      final dir = await getTemporaryDirectory();
      final target = '${dir.path}/ocr_dondur_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final out = await FlutterImageCompress.compressAndGetFile(
        path,
        target,
        rotate: degrees,
        quality: 92,
        minWidth: 1440,
        minHeight: 1440,
        format: CompressFormat.jpeg,
      );
      return out?.path;
    } catch (_) {
      return null;
    }
  }
}
