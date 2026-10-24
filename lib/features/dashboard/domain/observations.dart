import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../study_session/domain/study_session.dart';
import 'deep_analysis.dart';

/// Uygulamanın kayıtlarından analiz gözlemleri.
///
/// - Oturum blokları (sonuç girilmiş): saat, gün, ders, kaynak, konu ve
///   oturumun soru başına süresiyle.
/// - Oturuma bağlı olmayan kitap test sonuçları (kitap ekranından optik): saat
///   ve konu var, süre yok. Oturumdan gelen test sonuçları blokla çift
///   sayılmasın diye alınmaz.
/// - Deneme bölümleri: gün ve ders var; saat yok.
List<Observation> buildObservations({
  required List<StudySession> sessions,
  required Map<String, TestResult> results,
  required List<MockExam> exams,
  required List<Book> books,
}) {
  final bookById = {for (final b in books) b.id: b};

  /// Konu: testin bağlı olduğu başlık (ör. "Test 5: Vektörler - 2" → "Vektörler").
  String? topicOf(String? bookId, String? nodeId) {
    final book = bookId == null ? null : bookById[bookId];
    if (book == null || nodeId == null) return null;
    final path = pathTo(book, nodeId);
    if (path.isEmpty) return null;
    final node = path.last;
    final isLeaf = node.children.isEmpty;
    return (isLeaf && path.length >= 2) ? path[path.length - 2].title : node.title;
  }

  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final out = <Observation>[];

  for (final s in sessions) {
    final end = s.endedAt;
    final minutes = end == null ? null : end.difference(s.startedAt).inMinutes;
    final perQuestion = s.secondsPerQuestion;
    for (final i in s.items) {
      if (!i.hasResults || i.solved == 0) continue;
      final book = i.bookId == null ? null : bookById[i.bookId];
      final subject = i.subject ?? (book == null ? null : subjectKey(book.examType, book.subject));
      if (subject == null) continue;
      out.add(Observation(
        at: s.startedAt,
        day: day(s.startedAt),
        subject: subject,
        source: book?.title ?? 'Kitapsız',
        topic: topicOf(i.bookId, i.contentNodeId),
        correct: i.correct ?? 0,
        wrong: i.wrong ?? 0,
        blank: i.blank ?? 0,
        secondsPerQuestion: perQuestion,
        sessionMinutes: minutes,
        sessionKey: s.id,
      ));
    }
  }

  for (final r in results.values) {
    if (r.sessionId != null || !r.hasCounts) continue;
    final book = bookById[r.bookId];
    if (book == null) continue;
    out.add(Observation(
      at: r.solvedAt,
      day: day(r.solvedAt),
      subject: subjectKey(book.examType, book.subject),
      source: book.title,
      topic: topicOf(r.bookId, r.nodeId),
      correct: r.correct ?? 0,
      wrong: r.wrong ?? 0,
      blank: r.blank ?? 0,
      sessionKey: 'test:${r.nodeId}',
    ));
  }

  for (final e in exams) {
    final perQuestion = e.durationMinutes == null || e.questionCount == 0
        ? null
        : e.durationMinutes! * 60 / e.questionCount;
    for (final sec in e.sections) {
      out.add(Observation(
        day: day(e.takenOn),
        subject: sec.subject,
        source: 'Deneme',
        correct: sec.correct,
        wrong: sec.wrong,
        blank: sec.blank,
        secondsPerQuestion: perQuestion,
        sessionKey: 'exam:${e.id}',
      ));
    }
  }
  return out;
}
