import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/media/bmp_encoder.dart';
import 'package:kocum/core/media/photo_capture_service.dart';
import 'package:kocum/features/settings/domain/settings.dart';

void main() {
  test('BMP: başlık, 4 bayt satır dolgusu, aşağıdan yukarı BGR', () {
    // 5×3, her piksel (x, y, 7, 255)
    const w = 5, h = 3;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        rgba[i] = x;
        rgba[i + 1] = y;
        rgba[i + 2] = 7;
        rgba[i + 3] = 255;
      }
    }
    final bmp = rgbaToBmp(rgba, w, h);
    final d = ByteData.sublistView(bmp);
    const row = 16; // 5 × 3 = 15 → 16
    expect(String.fromCharCodes(bmp.sublist(0, 2)), 'BM');
    expect(d.getUint32(2, Endian.little), 54 + row * h);
    expect(d.getUint32(10, Endian.little), 54);
    expect(d.getInt32(18, Endian.little), w);
    expect(d.getInt32(22, Endian.little), h);
    expect(d.getUint16(28, Endian.little), 24);
    // İlk BMP satırı görüntünün EN ALT satırıdır (y = 2); piksel BGR.
    expect(bmp.sublist(54, 57), [7, 2, 0]); // (x=0, y=2)
    expect(bmp.sublist(54 + 4 * 3, 54 + 5 * 3), [7, 2, 4]); // (x=4, y=2)
    expect(bmp.sublist(54 + 2 * row, 54 + 2 * row + 3), [7, 0, 0]); // son satır = y 0
  });

  test('hızlı mod daha küçük kaynak ve çıktı kullanır', () {
    final s = PhotoCaptureService();
    expect((s.sourceSide, s.outputSide, s.targetShortSide, s.webpQuality), (4096.0, 2880.0, 1440, 80));
    s.fast = true;
    expect(s.sourceSide, lessThan(4096));
    expect(s.outputSide, lessThan(2880));
    expect(s.targetShortSide, lessThan(1440));
  });

  test('hızlı fotoğraf ayarı kaydedilip okunur', () {
    final back = AppSettings.fromJson(const AppSettings(fastPhotos: true).toJson());
    expect(back.fastPhotos, isTrue);
    expect(AppSettings.fromJson(const {}).fastPhotos, isFalse);
  });

  test('hazır fotoğraf: bekleme sözü varsayılan olarak tamam', () async {
    final p = CapturedPhoto(originalPath: 'a', path: 'b');
    await expectLater(p.ready, completes);
  });
}
