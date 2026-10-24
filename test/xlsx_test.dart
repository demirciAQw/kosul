import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/export/xlsx_writer.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/tools/data/workbook_export.dart';

/// ZIP'ten ad → metin (sıkıştırmasız girdiler).
Map<String, String> _unzip(Uint8List z) {
  final b = ByteData.sublistView(z);
  final end = z.length - 22;
  final count = b.getUint16(end + 10, Endian.little);
  var p = b.getUint32(end + 16, Endian.little);
  final out = <String, String>{};
  for (var i = 0; i < count; i++) {
    final size = b.getUint32(p + 24, Endian.little);
    final nameLen = b.getUint16(p + 28, Endian.little);
    final local = b.getUint32(p + 42, Endian.little);
    final name = utf8.decode(z.sublist(p + 46, p + 46 + nameLen));
    final start = local + 30 + b.getUint16(local + 26, Endian.little);
    var data = z.sublist(start, start + size);
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) data = data.sublist(3);
    out[name] = utf8.decode(data);
    p += 46 + nameLen;
  }
  return out;
}

void main() {
  test('sütun adları ve tarih sayısı (Python prototipiyle aynı)', () {
    expect([0, 25, 26, 27, 51, 52, 701, 702].map(columnName), ['A', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
    expect(excelSerial(DateTime(2026, 10, 24, 19, 5)), closeTo(46319.79513888889, 1e-9));
  });

  test('xlsx parçaları, sayfalar, hücre türleri ve kaçış', () {
    final bytes = buildXlsx([
      XlsxSheet('Sorular', const ['Eklenme', 'Konu', 'Soru no', 'Yıldızlı'], [
        [DateTime(2026, 10, 24, 19, 5), 'Türev & Limit <zor> "C"', 7, true],
        [null, 'ğüşıöç İĞÜŞÖÇ', 12.5, false],
      ]),
      const XlsxSheet('Oturumlar/[2026]', ['A'], []),
    ]);
    final files = _unzip(bytes);
    expect(files.keys, containsAll([
      '[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', //
      'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml',
    ]));
    // Sayfa adındaki yasak karakterler temizlenir.
    expect(files['xl/workbook.xml'], contains('name="Oturumlar  2026"'));
    final s1 = files['xl/worksheets/sheet1.xml']!;
    expect(s1, contains('<c r="A1" t="inlineStr" s="1"><is><t>Eklenme</t></is></c>'));
    expect(s1, contains('<c r="A2" s="2"><v>46319.79513888889</v></c>'));
    expect(s1, contains('Türev &amp; Limit &lt;zor&gt; &quot;C&quot;'));
    expect(s1, contains('<c r="C2"><v>7</v></c>'));
    expect(s1, contains('<c r="D2" t="inlineStr"><is><t>evet</t></is></c>'));
    expect(s1, isNot(contains('r="A3"'))); // boş hücre yazılmaz
    expect(s1, contains('<c r="C3"><v>12.5</v></c>'));
    expect(s1, contains('ğüşıöç İĞÜŞÖÇ'));
    expect(s1, contains('<autoFilter ref="A1:D3"/>'));
    expect(s1, contains('state="frozen"'));
    expect(files['xl/styles.xml'], contains('cellStyle name="Normal"'));
  });

  test('soru sayfası: her soru bir satır, ders adı ve şıklar', () {
    final card = QuestionCard(
      id: 'q1',
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: 'Bilgi Sarmal Fizik',
      testLabel: 'Test 5: Vektörler - 2',
      questionNo: 7,
      subject: 'TYT Fizik',
      difficulty: 6,
      createdAt: DateTime(2026, 10, 19, 14, 5),
      correctAnswer: 'C',
      givenAnswer: 'B',
      topicText: 'VEKTÖRLER',
    );
    final sheet = questionsSheet([card], const {});
    expect(sheet.rows.single[1], 'Yanlış');
    expect(sheet.rows.single[3], 'Vektörler');
    expect(sheet.rows.single[7], 7);
    expect((sheet.rows.single[8], sheet.rows.single[9]), ('C', 'B'));
    expect(sheet.headers, hasLength(sheet.rows.single.length));
  });
}
