import '../../../core/export/xlsx_writer.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../dashboard/domain/deep_analysis.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../notes/domain/notes.dart';
import '../../planning/domain/planning.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/recurrence.dart';
import '../../study_session/domain/study_session.dart';

double? _pct(int correct, int total) => total == 0 ? null : (correct * 1000 / total).round() / 10;

/// Soru sayfası (Defter'den seçili sorular için de kullanılır).
XlsxSheet questionsSheet(List<QuestionCard> cards, Map<String, CurriculumNode> curriculum) => XlsxSheet(
      'Sorular',
      const [
        'Eklenme', 'Durum', 'Ders', 'Konu', 'Kaynak türü', 'Kaynak', 'Test', 'Soru no', 'Doğru cevap', //
        'Senin cevabın', 'Neden', 'Neden notu', 'Zorluk (1-10)', 'Yıldızlı', 'Soru başına sn',
        'Fotoğraf', 'Çözüm', 'Not', 'Kimlik',
      ],
      [
        for (final c in cards)
          [
            c.createdAt,
            c.status.label,
            subjectName(c.subject),
            topicOfCard(c, curriculum)?.label,
            c.origin.label,
            c.sourceName,
            c.testLabel,
            c.questionNo,
            c.correctAnswer,
            c.givenAnswer,
            c.reason?.label,
            c.reasonNote,
            c.difficulty,
            c.isStarred,
            c.avgSecondsPerQuestion?.round(),
            c.questionImage != null,
            c.hasSolution,
            c.note,
            c.id,
          ],
      ],
    );

/// Tüm veri, LibreOffice Calc'ta açılacak sayfalar hâlinde.
List<XlsxSheet> dataWorkbook({
  required List<QuestionCard> cards,
  required Map<String, CurriculumNode> curriculum,
  required List<Book> books,
  required List<BookProgress> progress,
  required Map<String, TestResult> results,
  required List<StudySession> sessions,
  required List<MockExam> exams,
  required List<StudyPlan> plans,
  required List<StudyNote> notes,
  List<Finding> findings = const [],
}) {
  final bookById = {for (final b in books) b.id: b};
  final sortedSessions = [...sessions]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  return [
    questionsSheet(cards, curriculum),
    XlsxSheet(
      'Oturumlar',
      const ['Başlangıç', 'Bitiş', 'Süre (dk)', 'Gün', 'Saat', 'Blok', 'Ders', 'Kaynak', 'Konu', 'Sayfalar', //
        'Doğru', 'Yanlış', 'Boş', 'Toplam', 'Doğruluk %', 'Net', 'Oturum'],
      [
        for (final s in sortedSessions)
          for (final i in s.items)
            () {
              final book = i.bookId == null ? null : bookById[i.bookId];
              final total = i.solved;
              return <Object?>[
                s.startedAt,
                s.endedAt,
                s.endedAt?.difference(s.startedAt).inMinutes,
                _weekday(s.startedAt),
                s.startedAt.hour,
                i.label,
                i.subject == null ? null : subjectName(i.subject!),
                book?.title ?? (i.activity?.label ?? 'Kitapsız'),
                book == null || i.contentNodeId == null ? null : nodeLabel(book, i.contentNodeId!),
                i.pageSpec.isEmpty ? null : i.pageSpec,
                i.correct,
                i.wrong,
                i.blank,
                i.hasResults ? total : null,
                i.hasResults ? _pct(i.correct ?? 0, total) : null,
                i.hasResults ? netOf(i.correct ?? 0, i.wrong ?? 0) : null,
                s.id,
              ];
            }(),
      ],
    ),
    XlsxSheet(
      'Kitap testleri',
      const ['Kitap', 'Ders', 'Ünite', 'Konu', 'Test', 'Sayfa', 'Çözüldü', 'Çözülme', 'Doğru', 'Yanlış', 'Boş', //
        'Doğruluk %'],
      [
        for (final b in books)
          for (final leaf in progressLeaves(b))
            () {
              final path = pathTo(b, leaf.id);
              final r = results[leaf.id];
              final total = (r?.correct ?? 0) + (r?.wrong ?? 0) + (r?.blank ?? 0);
              return <Object?>[
                b.title,
                subjectName(subjectKey(b.examType, b.subject)),
                path.isNotEmpty ? path.first.title : null,
                path.length >= 3 ? path[path.length - 2].title : null,
                leaf.title,
                leaf.pageStart == null
                    ? null
                    : (leaf.pageEnd == null || leaf.pageEnd == leaf.pageStart
                        ? '${leaf.pageStart}'
                        : '${leaf.pageStart}-${leaf.pageEnd}'),
                r != null,
                r?.solvedAt,
                r?.correct,
                r?.wrong,
                r?.blank,
                r != null && r.hasCounts ? _pct(r.correct ?? 0, total) : null,
              ];
            }(),
      ],
    ),
    XlsxSheet(
      'Kitaplar',
      const ['Kitap', 'Yayınevi', 'Sınav', 'Ders', 'Test', 'Biten', 'Kalan', 'İlerleme %', 'Doğru', 'Yanlış', 'Boş', //
        'Son çalışma'],
      [
        for (final p in progress)
          [
            p.book.title,
            p.book.publisher,
            p.book.examType,
            p.book.subject,
            p.totalLeaves,
            p.doneLeaves,
            p.totalLeaves - p.doneLeaves,
            _pct(p.doneLeaves, p.totalLeaves),
            p.correct,
            p.wrong,
            p.blank,
            p.lastSolvedAt,
          ],
      ],
    ),
    XlsxSheet(
      'Denemeler',
      const ['Tarih', 'Deneme', 'Tür', 'Ders', 'Soru', 'Doğru', 'Yanlış', 'Boş', 'Net', 'Deneme neti', 'Süre (dk)'],
      [
        for (final e in [...exams]..sort((a, b) => a.takenOn.compareTo(b.takenOn)))
          for (final s in e.sections)
            [
              e.takenOn,
              e.title,
              e.kind.label,
              subjectName(s.subject),
              s.questionCount,
              s.correct,
              s.wrong,
              s.blank,
              s.net,
              e.net,
              e.durationMinutes,
            ],
      ],
    ),
    XlsxSheet(
      'Bulgular',
      const ['Etken', 'Daha iyi', 'Daha kötü', 'İyi doğruluk %', 'Kötü doğruluk %', 'Fark (puan)', 'Soru', 'Gün', //
        'Karşılaştırma', 'Cümle'],
      [
        for (final f in findings)
          [
            f.factor.title,
            f.better,
            f.worse,
            (f.betterRate * 1000).round() / 10,
            (f.worseRate * 1000).round() / 10,
            (f.gap * 1000).round() / 10,
            f.questions,
            f.days,
            f.controlledFor,
            f.sentence,
          ],
      ],
    ),
    XlsxSheet(
      'Notlar',
      const ['Tarih', 'Ders', 'Başlık', 'Metin', 'Sayfa fotoğrafı', 'Sabit'],
      [
        for (final n in notes) [n.createdAt, n.subject, n.title, n.body, n.photos.length, n.isPinned],
      ],
    ),
    XlsxSheet(
      'Planlar',
      const ['Plan', 'Başlangıç', 'Bitiş', 'Görev', 'Kitap', 'Hedef soru', 'Bitti'],
      [
        for (final p in plans)
          for (final t in p.tasks)
            [
              p.title,
              p.startsOn,
              p.endsOn,
              t.title,
              t.bookId == null ? null : bookById[t.bookId]?.title,
              t.targetQuestions,
              t.isDone,
            ],
      ],
    ),
  ];
}

String _weekday(DateTime d) => const ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'][d.weekday - 1];

/// Dosya adı için gün damgası.
String workbookFileName(DateTime now) =>
    'Kocum_Veriler_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.xlsx';
