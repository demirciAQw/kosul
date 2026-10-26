import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/ocr/domain/question_text.dart';
import 'package:kocum/features/ocr/domain/reader/figure_detector.dart';
import 'package:kocum/features/ocr/domain/reader/page_reader.dart';

/// Fikstürler: örnek fotoğraflardan (Python prototipiyle aynı veriler).
({List<OcrLine> lines, double w, double h}) _load(String name) {
  final j = jsonDecode(File('test/fixtures/ocr/$name.json').readAsStringSync()) as Map<String, dynamic>;
  double d(Object? v) => (v as num?)?.toDouble() ?? 0;
  return (
    w: d(j['w']),
    h: d(j['h']),
    lines: [
      for (final l in j['lines'] as List)
        OcrLine(
          l['text'] as String,
          left: d(l['x']),
          top: d(l['y']),
          width: d(l['w']),
          height: d(l['h']),
          confidence: l['c'] == null ? 1 : d(l['c']),
          angle: d(l['angle']),
          words: [
            for (final w in (l['words'] as List?) ?? const [])
              OcrWord(w['t'] as String,
                  left: d(w['x']), top: d(w['y']), width: d(w['w']), height: d(w['h']), confidence: d(w['c'])),
          ],
        ),
    ],
  );
}

void main() {
  group('Sayfa okuyucu (yeni nesil sorular)', () {
    for (final name in ['fx_trig', 'fx_trig_skew']) {
      test('$name: iki soru, kesik olan ayrılır, kesirli şıklar konuma göre', () {
        final p = _load(name);
        final r = readPage(p.lines, p.w, p.h);
        expect(r.questions, hasLength(2));
        final cut = r.questions[0], main = r.questions[1];
        expect(cut.partial, isTrue);
        expect(cut.options, {'A': '5', 'B': '5,1', 'C': '5,2', 'D': '5,3', 'E': '5,4'});
        expect(cut.labels, containsAll(['12°', '30°', '17 m']));
        expect(main.number, 2);
        expect(main.partial, isFalse);
        expect(main.options, {
          'A': '4 / sin²α',
          'B': '4 / cos²α',
          'C': '4·sin²α',
          'D': '4·cos²α',
          'E': '4·tan²α',
        });
        expect(main.labels, containsAll(['E', 'α', 'D']));
        expect(main.prompt, 'hangisidir?');
        expect(r.primary, 1); // kesik olmayan, şıkları tam soru
        if (name == 'fx_trig_skew') expect(r.skew, closeTo(3, 0.01));
      });
    }

    test('kimya: madde imli bilgiler, bozuk okunmuş öncüller, soru cümlesi', () {
      final p = _load('kimya_tesseract'); // Tesseract çıktısı: ML Kit'ten daha bozuk
      final r = readPage(p.lines, p.w, p.h);
      expect(r.questions, hasLength(1));
      final q = r.questions.single;
      expect(q.number, 4);
      expect(q.bullets, hasLength(3));
      expect([for (final s in q.statements) s.label], ['I', 'II', 'III']);
      expect(q.statements[1].text, 'Maddenin fiziksel hâline bağlıdır.');
      expect(q.prompt, contains('hangileri yapılabilir?'));
      expect(q.options.keys, ['A', 'B', 'C', 'D', 'E']);
    });

    test('matematik düzeltmeleri ve Roma rakamları', () {
      expect(mathNormalize('3V5 ve 2V13'), '3√5 ve 2√13');
      expect(mathNormalize('tan(42*) ≈ 0,9'), 'tan(42°) ≈ 0,9');
      expect(mathNormalize('4·sin?α'), '4·sin²α');
      expect(mathNormalize('V3 ≈ 1,7'), '√3 ≈ 1,7');
      expect(mathNormalize('KAV2 sabit'), 'KAV2 sabit'); // harf sonrası V dokunulmaz
      expect([for (final x in ['Il', 'Ili', '11', '1', '|', 'IV', 'lll']) romanLabel(x)],
          ['II', 'III', 'II', 'I', 'I', 'IV', 'III']);
    });

    test('sayfa yönü satır açılarından', () {
      List<OcrLine> at(double a) => [for (var i = 0; i < 5; i++) OcrLine('uzun bir satır metni', angle: a)];
      expect(dominantRotation(at(0)), 0);
      expect(dominantRotation(at(89)), 90);
      expect(dominantRotation(at(-90)), 270);
      expect(dominantRotation(at(181)), 180);
      expect(dominantRotation([...at(0), ...at(90)]), 0); // belirsiz
    });
  });

  group('Şekil bulucu', () {
    /// Python prototipindekiyle aynı yapay sayfa.
    (Uint8List, List<TextBox>) synth() {
      const w = 400, h = 300;
      final px = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        px[i * 4] = 245;
        px[i * 4 + 1] = 245;
        px[i * 4 + 2] = 245;
        px[i * 4 + 3] = 255;
      }
      void put(int x, int y, int r, int g, int b) {
        if (x < 0 || y < 0 || x >= w || y >= h) return;
        final i = (y * w + x) * 4;
        px[i] = r;
        px[i + 1] = g;
        px[i + 2] = b;
      }

      void line(int x0, int y0, int x1, int y1) {
        final n = math.max((x1 - x0).abs(), (y1 - y0).abs()) * 2;
        for (var k = 0; k <= n; k++) {
          final t = k / n;
          final x = (x0 + (x1 - x0) * t + 0.5).floor(), y = (y0 + (y1 - y0) * t + 0.5).floor();
          for (final dx in [0, 1]) {
            for (final dy in [0, 1]) {
              put(x + dx, y + dy, 30, 30, 30);
            }
          }
        }
      }

      line(60, 240, 160, 60);
      line(160, 60, 260, 240);
      line(60, 240, 260, 240);
      var s = 12345;
      for (var y = 40; y < 140; y++) {
        for (var x = 290; x < 390; x++) {
          final ch = <int>[];
          for (var k = 0; k < 3; k++) {
            s = (s * 1103515245 + 12345) & 0x7fffffff;
            ch.add(90 + s % 110);
          }
          put(x, y, ch[0], ch[1], ch[2]);
        }
      }
      for (var y = 12; y < 22; y += 3) {
        for (var x = 40; x < 240; x++) {
          put(x, y, 40, 40, 40);
        }
      }
      return (
        px,
        const [
          TextBox('Bu bir metin satırıdır', 40, 10, 200, 12),
          TextBox('A', 50, 245, 10, 12),
          TextBox('B', 262, 245, 10, 12),
          TextBox('C', 155, 44, 10, 12),
        ],
      );
    }

    test('fotoğraf ve şekil ayrı etiketlenir; metin satırı şekil sayılmaz', () {
      final (px, boxes) = synth();
      final regions = detectFigures(px, 400, 300, boxes);
      expect([for (final r in regions) r.kind], ['photo', 'diagram']);
      final photo = regions[0].box, diagram = regions[1].box;
      for (final (got, want) in [
        (photo, [0.715, 0.12, 0.985, 0.48]),
        (diagram, [0.14, 0.18667, 0.665, 0.82]),
      ]) {
        for (var k = 0; k < 4; k++) {
          // Python ile toplama sırası farkı eşikteki bir pikseli kaydırabilir: 4 px pay.
          expect(got[k], closeTo(want[k], 0.01));
        }
      }
    });

    test('boş sayfada bölge yok', () {
      final px = Uint8List(400 * 300 * 4)..fillRange(0, 400 * 300 * 4, 245);
      expect(detectFigures(px, 400, 300, const []), isEmpty);
    });
  });
}
