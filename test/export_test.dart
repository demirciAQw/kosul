import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/export/zip_writer.dart';
import 'package:kocum/features/notes/domain/notes.dart';
import 'package:kocum/features/notes/presentation/notes_export.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/question_export.dart';

/// ZIP'i merkezi dizinden okur: (ad, içerik) listesi.
List<(String, List<int>)> _readZip(Uint8List z) {
  final b = ByteData.sublistView(z);
  final end = z.length - 22;
  expect(b.getUint32(end, Endian.little), 0x06054b50);
  final count = b.getUint16(end + 10, Endian.little);
  var p = b.getUint32(end + 16, Endian.little);
  final out = <(String, List<int>)>[];
  for (var i = 0; i < count; i++) {
    expect(b.getUint32(p, Endian.little), 0x02014b50);
    final size = b.getUint32(p + 24, Endian.little);
    final nameLen = b.getUint16(p + 28, Endian.little);
    final local = b.getUint32(p + 42, Endian.little);
    final name = utf8.decode(z.sublist(p + 46, p + 46 + nameLen));
    expect(b.getUint32(local, Endian.little), 0x04034b50);
    final localNameLen = b.getUint16(local + 26, Endian.little);
    final dataStart = local + 30 + localNameLen;
    final data = z.sublist(dataStart, dataStart + size);
    expect(crc32(data), b.getUint32(p + 16, Endian.little), reason: name);
    out.add((name, data));
    p += 46 + nameLen;
  }
  return out;
}

QuestionCard _card(String id, {String? photo, String? solution, QuestionStatus status = QuestionStatus.wrong}) =>
    QuestionCard(
      id: id,
      status: status,
      origin: QuestionOrigin.book,
      sourceName: 'Bilgi Sarmal Fizik',
      testLabel: 'Test 5: Vektörler - 2',
      questionNo: 7,
      subject: 'TYT Fizik',
      difficulty: 6,
      createdAt: DateTime(2026, 10, 19, 14, 5),
      questionImage: photo,
      solutionImage: solution,
      correctAnswer: 'C',
      givenAnswer: 'B',
      note: 'vektör; yön',
    );

void main() {
  test('CRC-32 standart değer', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });

  test('ZIP yazılır ve geri okunur; Türkçe adlar ve aynı adlar', () {
    final zip = ZipWriter(time: DateTime(2026, 10, 22, 14, 30));
    zip.addText('etiketler.csv', 'a;b', bom: true);
    final a = zip.add('TYT Fizik/Türev_S7.webp', List<int>.generate(300, (i) => i % 256));
    final b = zip.add('TYT Fizik/Türev_S7.webp', [1, 2, 3]);
    expect(a, 'TYT Fizik/Türev_S7.webp');
    expect(b, 'TYT Fizik/Türev_S7 (2).webp');
    final entries = _readZip(zip.finish());
    expect(entries.map((e) => e.$1), ['etiketler.csv', 'TYT Fizik/Türev_S7.webp', 'TYT Fizik/Türev_S7 (2).webp']);
    expect(entries[0].$2.take(3), [0xEF, 0xBB, 0xBF]);
    expect(entries[2].$2, [1, 2, 3]);
  });

  test('dosya adları güvenli', () {
    expect(safeFileName('TYT Fizik: Vektörler / 2?'), 'TYT_Fizik_Vektörler_2');
    expect(safeFileName('   '), 'adsiz');
  });

  test('soru paketi: etiketli adlar, klasör, çözüm dosyası ve tablo', () {
    final cards = [
      _card('a', photo: 'questions/a.webp', solution: 'questions/a_s.jpg'),
      _card('b', status: QuestionStatus.blank),
    ];
    final plan = planQuestionExport(cards, const QuestionExportOptions(), topicOf: (_) => 'Vektörler');
    expect(plan.media.map((m) => m.zipName), [
      'TYT_Fizik/TYT_Fizik_Vektörler_Test_5_Vektörler_-_2_S7_Yanlış.webp',
      'TYT_Fizik/TYT_Fizik_Vektörler_Test_5_Vektörler_-_2_S7_Yanlış_cozum.jpg',
    ]);
    final lines = plan.table!.split('\r\n');
    expect(lines, hasLength(3));
    expect(lines.first, startsWith('Sıra;Soru dosyası'));
    expect(lines[1], contains(';C;B;'));
    expect(lines[1], endsWith('"vektör; yön"')); // ayraç içeren alan tırnaklı
    expect(plan.json, isNull);

    final seq = planQuestionExport(
      cards,
      const QuestionExportOptions(naming: ExportNaming.sequence, folderBySubject: false, solutionPhotos: false, table: false, fullData: true),
      topicOf: (_) => null,
    );
    expect(seq.media.single.zipName, '001_TYT_Fizik.webp');
    expect(seq.table, isNull);
    expect(jsonDecode(seq.json!)['cards'], hasLength(2));
  });

  test('not metni: derslere göre, tarihli, fotoğraf bağlantılı', () {
    final n = StudyNote(
      id: 'n1',
      subject: 'AYT Kimya',
      title: 'Denge',
      body: 'Le Chatelier',
      createdAt: DateTime(2026, 10, 19, 20, 5),
      updatedAt: DateTime(2026, 10, 19, 20, 5),
      photos: const ['notes/x.jpg'],
    );
    final md = notesMarkdown([n], {'n1': ['AYT_Kimya/2026-10-19_2005_Denge_s1.jpg']}, title: 'Tüm notlar');
    expect(md, contains('## AYT Kimya'));
    expect(md, contains('### Denge'));
    expect(md, contains('_2026-10-19 20:05_'));
    expect(md, contains('![](AYT_Kimya/2026-10-19_2005_Denge_s1.jpg)'));
  });
}
