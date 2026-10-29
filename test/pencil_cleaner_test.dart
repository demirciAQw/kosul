import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/ocr/domain/question_text.dart';
import 'package:kocum/features/ocr/domain/reader/pencil_cleaner.dart';

/// Gri kâğıt (200) üstünde koyu basılı blok (40) ve açık kurşun kalem çizgisi (150).
(Uint8List, int, int) _page() {
  const w = 120, h = 60;
  final px = Uint8List(w * h * 4);
  void put(int x, int y, int v) {
    final i = (y * w + x) * 4;
    px[i] = v;
    px[i + 1] = v;
    px[i + 2] = v;
    px[i + 3] = 255;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      put(x, y, 200);
    }
  }
  for (var y = 20; y < 30; y++) {
    for (var x = 10; x < 50; x++) {
      put(x, y, 40); // basılı yazı
    }
  }
  for (var y = 44; y < 46; y++) {
    for (var x = 60; x < 110; x++) {
      put(x, y, 150); // yazıdan uzak kurşun kalem
    }
  }
  return (px, w, h);
}

int _at(Uint8List px, int w, int x, int y) => px[(y * w + x) * 4];

void main() {
  test('yazıdan uzak kalem izi kâğıt rengine döner; basılı yazı değişmez', () {
    final (px, w, h) = _page();
    final out = cleanPencil(px, w, h);
    expect(_at(out, w, 80, 44), greaterThan(180)); // kalem silindi
    expect(_at(out, w, 20, 25), 40); // basılı yazı korundu
    expect(_at(px, w, 80, 44), 150); // girdi değişmedi
  });

  test('boş sayfa olduğu gibi kalır', () {
    final px = Uint8List(40 * 20 * 4)..fillRange(0, 40 * 20 * 4, 200);
    expect(cleanPencil(px, 40, 20), px);
  });

  test('birleştirme: asıl okuma korunur, yalnızca yeni yerler ve anlamlı satırlar eklenir', () {
    const base = [OcrLine('Soru kökü', left: 0, top: 0, width: 100, height: 10, confidence: 0.9)];
    const extra = [
      OcrLine('Soru kok', left: 2, top: 1, width: 90, height: 10, confidence: 0.8), // aynı yer
      OcrLine('noktaları', left: 0, top: 40, width: 80, height: 10, confidence: 0.7), // yeni
      OcrLine('|', left: 0, top: 80, width: 5, height: 10, confidence: 0.6), // çöp
    ];
    expect(mergeOcrLines(base, extra).map((l) => l.text), ['Soru kökü', 'noktaları']);
  });

  test('birleştirme: kalem yüzünden bozuk okunan satır, daha güvenli temiz okumayla değişir', () {
    const base = [
      OcrLine('dışına çeşitli NA gönderme', left: 0, top: 0, width: 200, height: 12, confidence: 0.55),
      OcrLine('Buna göre;', left: 0, top: 30, width: 80, height: 12, confidence: 0.96),
    ];
    const extra = [
      OcrLine('dışına çeşitli salgılar gönderme', left: 1, top: 1, width: 205, height: 12, confidence: 0.96),
      OcrLine('Buna gore', left: 0, top: 30, width: 80, height: 12, confidence: 0.99), // fark küçük: değişmez
    ];
    expect(mergeOcrLines(base, extra).map((l) => l.text), ['dışına çeşitli salgılar gönderme', 'Buna göre;']);
  });
}
