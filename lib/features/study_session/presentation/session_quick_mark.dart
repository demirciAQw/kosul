import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../library/library_providers.dart';
import '../../library/presentation/test_mark_flow.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/quick_mark.dart';
import '../../question_bank/presentation/question_prefill.dart';
import '../../question_bank/presentation/quick_mark_flow.dart';
import '../../question_bank/presentation/screens/optic_form_screen.dart';
import '../domain/study_session.dart';
import '../study_session_providers.dart';

Book? _bookOf(WidgetRef ref, SessionItem item) {
  final books = ref.read(libraryProvider).value ?? const <Book>[];
  return books.where((b) => b.id == item.bookId).firstOrNull;
}

String? _subjectOf(SessionItem item, Book? book) =>
    item.subject ?? (book == null ? null : subjectKey(book.examType, book.subject));

/// Oturum bloğunun optiği. Kitaptan seçilmiş ve testleri bilinen bloklarda form
/// test test bölünür ("6. test, 5. soru"); çözülen testler kitap haritasına
/// işlenir. Kitapsız bloklarda tek bölümdür. Toplam D/Y/B bloğa yazılır.
Future<OpticFormResult?> markSessionItem(
  BuildContext context,
  WidgetRef ref,
  StudySession session,
  SessionItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final book = _bookOf(ref, item);
  final OpticFormResult? result;

  if (book != null) {
    result = await markBookScope(
      context,
      ref,
      book: book,
      node: findNode(book, item.contentNodeId),
      sessionId: session.id,
      sessionItemId: item.id,
      avgSecondsPerQuestion: session.secondsPerQuestion,
      fallbackTotal: item.solved > 0 ? item.solved : item.estimatedQuestions,
    );
  } else {
    final subject = _subjectOf(item, book);
    if (subject == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Bu bölümün dersi bilinmiyor; soruyu Defter\'den ekle.')));
      return null;
    }
    result = await openQuickMark(
      context,
      ref,
      parts: [
        QuickMarkPart(
          key: item.id,
          title: item.testLabel,
          total: item.solved > 0 ? item.solved : (item.estimatedQuestions ?? 20),
          markContext: QuickMarkContext(
            origin: QuestionOrigin.independent,
            subject: subject,
            sourceName: item.label,
            mebNodeId: item.mebNodeId,
            sessionId: session.id,
            sessionItemId: item.id,
            testLabel: item.testLabel,
            avgSecondsPerQuestion: session.secondsPerQuestion,
          ),
        ),
      ],
      title: item.testLabel,
    );
  }
  if (result == null) return null;

  try {
    await ref.read(studySessionRepositoryProvider).saveItemResult(ItemResult(
          itemId: item.id,
          correct: result.correct,
          wrong: result.wrong,
          blank: result.blank,
        ));
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Sayılar kaydedilemedi: $e')));
  }
  return result;
}

/// Fotoğraflı tam kayıt için ekleme ekranının ön dolgusu. Blok tek bir test ya
/// da yaprak başlıksa test de dolu gelir; kullanıcıdan yalnızca soru no istenir.
QuestionPrefill sessionItemPrefill(
  WidgetRef ref,
  StudySession session,
  SessionItem item, {
  double? avgSecondsPerQuestion,
  int? testTotalQuestions,
}) {
  final book = _bookOf(ref, item);
  final node = book == null ? null : findNode(book, item.contentNodeId);
  final isTest = node != null && node.children.isEmpty;
  return QuestionPrefill(
    origin: item.isBookless ? QuestionOrigin.independent : QuestionOrigin.book,
    sessionId: session.id,
    sessionItemId: item.id,
    bookId: item.bookId,
    contentNodeId: isTest ? node!.id : null,
    mebNodeId: node == null ? item.mebNodeId : effectiveMeb(book!, node.id),
    sourceName: book?.title ?? item.label,
    subject: _subjectOf(item, book),
    testLabel: isTest ? nodeLabel(book!, node!.id) : item.testLabel,
    testTotalQuestions: isTest ? (node!.questionCount ?? testTotalQuestions) : testTotalQuestions,
    avgSecondsPerQuestion: avgSecondsPerQuestion ?? session.secondsPerQuestion,
  );
}
