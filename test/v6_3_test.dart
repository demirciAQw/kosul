import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/media/media_storage.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/library/domain/progress.dart';
import 'package:kocum/features/question_bank/data/question_card_repository_impl.dart';
import 'package:kocum/features/question_bank/domain/question_bank.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/study_session/domain/study_session.dart';
import 'package:kocum/features/study_session/presentation/session_coverage.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'id${_n++}';
}

class _NoMedia implements MediaStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  test('oturum bitince çalışılan bölümün testleri kitap haritasına düşer', () {
    final json = jsonDecode(File('assets/templates/BilgiSarmal_IlkAsama_Fizik.json').readAsStringSync());
    final book = BookTemplateModel.fromJson(json as Map<String, dynamic>).toEntity(ids: _SeqIds(), now: DateTime(2026));
    final konu = book.roots[1].children[1]; // 2. Ünite › Vektörler
    final pages = [for (var p = konu.pageStart!; p <= konu.pageEnd!; p++) p];
    final session = StudySession(
      id: 's',
      status: SessionStatus.awaitingResults,
      startedAt: DateTime(2026, 10, 18, 9),
      endedAt: DateTime(2026, 10, 18, 10),
      items: [SessionItem(id: 'i', label: 'Vektörler', bookId: book.id, contentNodeId: konu.id, pages: pages)],
    );
    final marks = sessionCoverage(session: session, books: [book], now: DateTime(2026, 10, 18, 10));
    expect(marks.map((m) => m.nodeId), leavesUnder(konu).map((l) => l.id));
    expect(marks, hasLength(3));

    // Sayfaların yalnızca biri seçildiyse test işaretlenmez.
    final partial = StudySession(
      id: 's2',
      status: SessionStatus.awaitingResults,
      startedAt: DateTime(2026),
      items: [SessionItem(id: 'j', label: 'x', bookId: book.id, contentNodeId: konu.id, pages: [pages.first])],
    );
    expect(sessionCoverage(session: partial, books: [book], now: DateTime(2026)), isEmpty);
  });

  test('şıklar kaydedilir; doğru soruda senin cevabın doğru şıktır, boşta yoktur', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftQuestionCardRepository(db);
    final save = SaveQuestionCard(repository: repo, media: _NoMedia(), ids: _SeqIds(), clock: () => DateTime(2026));
    QuestionDraft d(QuestionStatus s, String? c, String? g) => QuestionDraft(
          status: s,
          origin: QuestionOrigin.book,
          sourceName: 'K',
          subject: 'TYT Fizik',
          correctAnswer: c,
          givenAnswer: g,
        );
    final wrong = await save(d(QuestionStatus.wrong, 'c', 'B'));
    expect((wrong.correctAnswer, wrong.givenAnswer), ('C', 'B'));
    expect(wrong.answerText, 'Doğru cevap C, senin cevabın B');
    final right = await save(d(QuestionStatus.correct, 'A', 'D'));
    expect(right.givenAnswer, 'A');
    final blank = await save(d(QuestionStatus.blank, 'E', 'A'));
    expect((blank.correctAnswer, blank.givenAnswer), ('E', null));
    expect(blank.answerText, 'Doğru cevap E, boş bıraktın');
    expect((await repo.findById(wrong.id))!.givenAnswer, 'B');
  });
}
