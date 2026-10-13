import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/library/domain/library.dart';
import 'package:kocum/features/library/domain/progress.dart' as progress;
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/quick_mark.dart';
import 'package:kocum/features/question_bank/presentation/screens/optic_form_screen.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'id${_n++}';
}

Book _paragraf() => BookTemplateModel.fromJson(
      jsonDecode(File('assets/templates/345_Sifir_Risk_Paragraf.json').readAsStringSync()) as Map<String, dynamic>,
    ).toEntity(ids: _SeqIds(), now: DateTime(2026, 10, 13));

void main() {
  group('Kitap ilerlemesi', () {
    final book = _paragraf();
    final kesfetIlkTest = book.roots.first.children.first;

    test('ilk üç bölüm 9 test × 20 soru', () {
      for (final unit in book.roots.take(3)) {
        expect(unit.children, hasLength(9));
        expect(unit.children.every((t) => t.questionCount == 20), isTrue);
      }
    });

    test('yapraklar ve yüzde', () {
      final leaves = progress.progressLeaves(book);
      expect(leaves, hasLength(9 * 3 + 11 + 15 + 22 + 10));
      final results = {
        kesfetIlkTest.id: progress.TestResult(
          nodeId: kesfetIlkTest.id,
          bookId: book.id,
          solvedAt: DateTime(2026, 10, 13),
          correct: 16,
          wrong: 3,
          blank: 1,
          total: 20,
        ),
      };
      final p = progress.bookProgress(book, results);
      expect(p.doneLeaves, 1);
      expect(p.remainingLeaves, leaves.length - 1);
      expect(p.correct, 16);
      expect(p.accuracy, 0.8);
      expect(p.unitName, 'test');
    });

    test('yol, etiket ve konu: test bilinince konu da bilinir', () {
      expect(progress.nodeLabel(book, kesfetIlkTest.id), '01 Keşfet: Farklı Soru Türleri ile Tanış › Test 1');
      expect(progress.effectiveMeb(book, kesfetIlkTest.id), 'tyt.tur.paragraf');
    });

    test('bölüm seçilince optik test test bölünür', () {
      final unit = book.roots.first;
      expect(progress.testsUnder(unit), hasLength(9));
      expect(progress.testsUnder(unit).first.questionCount, 20);
    });
  });

  test('çok bölümlü optik: 6. testin 5. sorusu 105 değil', () {
    final r = OpticFormResult([
      for (var t = 1; t <= 9; t++)
        OpticSectionResult(
          key: 'test$t',
          included: t <= 6,
          total: 20,
          marks: t == 6 ? const {5: QuestionStatus.wrong} : const {},
        ),
    ]);
    expect(r.sections[5].marks.keys.single, 5);
    expect(r.total, 6 * 20); // çözülmeyen 3 test sayılmaz
    expect(r.wrong, 1);
    expect(r.correct, 119);
  });

  test('"Diğer" nedeni kullanıcının cümlesiyle gösterilir', () {
    final card = QuestionCard(
      id: 'c',
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: 'K',
      subject: 'TYT Türkçe',
      difficulty: 5,
      createdAt: DateTime(2026, 10, 13),
      reason: MistakeReason.other,
      reasonNote: 'Şekli yanlış çizdim',
    );
    expect(card.reasonText, 'Şekli yanlış çizdim');
    expect(
      QuestionDraft.fromCard(card).copyWith(reasonNote: () => null).reasonNote,
      isNull,
    );
  });

  test('optik özetleri toplanır', () {
    const a = QuickMarkSummary(created: 2, updated: 0, removed: 1, kept: 0);
    const b = QuickMarkSummary(created: 1, updated: 1, removed: 0, kept: 1);
    final s = a + b;
    expect(s.created, 3);
    expect(s.message, contains('3 yeni soru'));
  });
}
