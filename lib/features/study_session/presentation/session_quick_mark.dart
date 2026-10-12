import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/library.dart';
import '../../library/library_providers.dart';
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

String _sourceOf(SessionItem item, Book? book) =>
    book?.title ?? (item.isBookless ? item.label : item.label.split(' › ').first);

/// "Testin şu sorusu": oturum bloğunun optik formunu açar. Ders, konu, kaynak
/// ve süre bloktan gelir; kullanıcı yalnızca numaralara dokunur. Sonuç (D/Y/B)
/// bloğa yazılır ve geri döndürülür.
Future<OpticFormResult?> markSessionItem(
  BuildContext context,
  WidgetRef ref,
  StudySession session,
  SessionItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final book = _bookOf(ref, item);
  final subject = _subjectOf(item, book);
  if (subject == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Bu bölümün dersi bilinmiyor; soruyu Defter\'den ekle.')));
    return null;
  }
  final where = [
    if (book != null) book.title,
    if (item.pages.isNotEmpty) 'sayfa ${item.pageSpec}',
  ];
  final result = await openQuickMark(
    context,
    ref,
    markContext: QuickMarkContext(
      origin: item.isBookless ? QuestionOrigin.independent : QuestionOrigin.book,
      subject: subject,
      sourceName: _sourceOf(item, book),
      bookId: item.bookId,
      contentNodeId: item.contentNodeId,
      mebNodeId: item.mebNodeId,
      sessionId: session.id,
      sessionItemId: item.id,
      testLabel: item.testLabel,
      avgSecondsPerQuestion: session.secondsPerQuestion,
    ),
    title: item.testLabel,
    subtitle: where.isEmpty ? null : where.join(', '),
    initialTotal: item.solved > 0 ? item.solved : (item.estimatedQuestions ?? 20),
  );
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

/// Fotoğraflı tam kayıt için ekleme ekranının ön dolgusu.
QuestionPrefill sessionItemPrefill(
  WidgetRef ref,
  StudySession session,
  SessionItem item, {
  double? avgSecondsPerQuestion,
  int? testTotalQuestions,
}) {
  final book = _bookOf(ref, item);
  return QuestionPrefill(
    origin: item.isBookless ? QuestionOrigin.independent : QuestionOrigin.book,
    sessionId: session.id,
    sessionItemId: item.id,
    bookId: item.bookId,
    contentNodeId: item.contentNodeId,
    mebNodeId: item.mebNodeId,
    sourceName: _sourceOf(item, book),
    subject: _subjectOf(item, book),
    testLabel: item.testLabel,
    testTotalQuestions: testTotalQuestions ?? (item.solved > 0 ? item.solved : item.estimatedQuestions),
    avgSecondsPerQuestion: avgSecondsPerQuestion ?? session.secondsPerQuestion,
  );
}
