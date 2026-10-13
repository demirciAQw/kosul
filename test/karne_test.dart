import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/curriculum/domain/yks.dart';
import 'package:kocum/features/mock_exam/domain/karne_import.dart';
import 'package:kocum/features/mock_exam/domain/karne_parser.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';

/// Gerçek karnelerden (kişisel bilgileri maskelenmiş) kelime + konum verisi.
List<List<PdfWord>> _fixture(String name) {
  final json = jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final page in json['pages'] as List)
      [
        for (final w in page as List)
          PdfWord(w[0] as String, (w[1] as num).toDouble(), (w[2] as num).toDouble()),
      ],
  ];
}

/// Sayfa 2'deki soru soru sonuçlar, sayfa 1'deki özetle birebir tutmalı.
void _expectConsistent(KarneData d) {
  for (final s in d.sections) {
    final qs = d.questions.where((q) => q.subjectRaw == s.rawName).toList();
    expect(qs.length, s.questionCount, reason: s.rawName);
    expect(qs.where((q) => q.result == KarneResult.correct).length, s.correct, reason: s.rawName);
    expect(qs.where((q) => q.result == KarneResult.wrong).length, s.wrong, reason: s.rawName);
    expect(qs.where((q) => q.result == KarneResult.blank).length, s.blank, reason: s.rawName);
  }
}

void main() {
  group('Karne ayrıştırma', () {
    test('VİP - Maarif 11. sınıf karnesi', () {
      final d = parseKarne(_fixture('karne_vip_maarif.json'));
      expect(d.title, 'VİP - MAARİF 11.SINIF - 1');
      expect(d.date, DateTime(2026, 10, 6));
      expect(d.booklet, 'B');
      expect(d.examType, 'TYT');
      expect(d.score, '445.180');
      expect(d.ranks, [(3, 11), (31, 69), (190, 558)]);
      expect(d.osymRank, 87722);
      expect(d.sections.map((s) => s.rawName), [
        'TÜRKÇE', 'TARİH', 'COĞRAFYA', 'FELSEFE', 'DİN KÜLTÜRÜ', 'MATEMATİK', 'FİZİK', 'KİMYA', 'BİYOLOJİ', //
      ]);
      expect(d.questions, hasLength(120));
      _expectConsistent(d);

      // 3. sütun, 2. sütundaki KİMYA tablosunun 14. sorusuyla başlar.
      final kimya14 = d.questions.firstWhere((q) => q.subjectRaw == 'KİMYA' && q.no == 14);
      expect(kimya14.result, KarneResult.correct);
      final mat6 = d.questions.firstWhere((q) => q.subjectRaw == 'MATEMATİK' && q.no == 6);
      expect(mat6.kazanim, 'ÖZDEŞLİKLER');
      expect((mat6.correctAnswer, mat6.givenAnswer, mat6.result), ('B', 'C', KarneResult.wrong));
    });

    test('Mikroorjinal TYT karnesi: girilmemiş seçmeli felsefe atlanır', () {
      final d = parseKarne(_fixture('karne_mikroorjinal.json'));
      expect(d.title, 'MİKROORJİNAL - MAARİF TG TYT - 1');
      expect(d.date, DateTime(2026, 10, 13));
      expect(d.questions, hasLength(125));
      _expectConsistent(d);

      final plan = planKarneImport(d);
      expect(plan.kind.label, 'TYT');
      expect(plan.skipped, ['Seçmeli Felsefe']);
      expect(plan.sections, hasLength(9));
      expect(plan.wrongCount, 22);
      expect(plan.blankCount, 11);
      expect(plan.net, closeTo(81.5, 0.001));

      // Kitapçık numarası korunur: Fen testinde Kimya 8. soru.
      final kimya = plan.mistakes.firstWhere((m) => m.subject == 'TYT Kimya');
      expect(kimya.questionNo, 8);
      expect(kimya.kazanim, startsWith('ATOM ORBİTALLERİ'));
      expect(kimya.answerNote, 'Doğru cevap C, senin cevabın A.');
      expect(plan.mistakes.where((m) => m.status == QuestionStatus.blank).every((m) => m.answerNote!.contains('boş')), isTrue);
    });

    test('birleştirilmiş karne açık bir mesajla reddedilir', () {
      expect(
        () => parseKarne([
          [const PdfWord('DERS', 300, 240), const PdfWord('ANALİZİ', 340, 240)],
        ]),
        throwsA(isA<KarneFormatException>()),
      );
    });
  });

  group('Kitapçık numaraları', () {
    test('aynı testi paylaşan dersler', () {
      expect(Yks.bookletStart('TYT Matematik'), 1);
      expect(Yks.bookletStart('TYT Coğrafya'), 6);
      expect(Yks.bookletStart('TYT Din Kültürü'), 16);
      expect(Yks.bookletStart('TYT Seçmeli Felsefe'), 21);
      expect(Yks.bookletStart('TYT Kimya'), 8);
      expect(Yks.bookletStart('TYT Biyoloji'), 15);
      expect(Yks.bookletStart('AYT Kimya'), 15);
      expect(Yks.bookletStart('AYT Felsefe Grubu'), 23);
    });

    test('karnedeki ders adları', () {
      expect(Yks.keyFromReportName('TYT', 'DİN KÜLTÜRÜ'), 'TYT Din Kültürü');
      expect(Yks.keyFromReportName('TYT', 'MATEMATIK'), 'TYT Matematik'); // noktasız I
      expect(Yks.keyFromReportName('TYT', 'SEÇMELİ FELSEFE'), 'TYT Seçmeli Felsefe');
      expect(Yks.keyFromReportName('AYT', 'TÜRK DİLİ VE EDEBİYATI'), 'AYT Edebiyat');
      expect(Yks.keyFromReportName('AYT', 'TARİH-1'), 'AYT Tarih-1');
      expect(Yks.keyFromReportName('TYT', 'ASTROLOJİ'), isNull);
    });
  });
}
