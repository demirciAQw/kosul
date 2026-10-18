import '../../../core/text/turkish_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../question_bank/domain/question_bank.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/srs.dart';
import 'karne_parser.dart';
import 'mock_exam.dart';

/// Karneden deftere düşecek bir yanlış ya da boş.
class KarneMistake {
  const KarneMistake({
    required this.subject,
    required this.questionNo,
    required this.status,
    required this.kazanim,
    this.correctAnswer,
    this.givenAnswer,
  });

  final String subject; // "TYT Kimya"
  final int questionNo; // kitapçıktaki numara (Fen testinde Kimya 8–14)
  final QuestionStatus status;
  final String kazanim;
  final String? correctAnswer;
  final String? givenAnswer;

  /// Karta not: "Doğru cevap C, senin cevabın B."
  String? get answerNote {
    final dc = correctAnswer;
    if (dc == null) return null;
    final given = givenAnswer;
    return status == QuestionStatus.blank || given == null
        ? 'Doğru cevap $dc, boş bıraktın.'
        : 'Doğru cevap $dc, senin cevabın $given.';
  }
}

/// İçe aktarmanın önizlemesi: kaydetmeden önce kullanıcıya gösterilir.
class KarneImportPlan {
  const KarneImportPlan({
    required this.data,
    required this.kind,
    required this.sections,
    required this.mistakes,
    required this.skipped,
    required this.note,
    this.durationMinutes,
  });

  final KarneData data;
  final MockKind kind;
  final List<MockSectionDraft> sections;
  final List<KarneMistake> mistakes;

  /// Girilmeyen seçmeli bölümler (ör. Din Kültürü'nü seçenin Seçmeli Felsefe'si).
  final List<String> skipped;
  final String note;
  final int? durationMinutes;

  int get wrongCount => mistakes.where((m) => m.status == QuestionStatus.wrong).length;
  int get blankCount => mistakes.where((m) => m.status == QuestionStatus.blank).length;
  double get net => sections.fold(0.0, (a, s) => a + netOf(s.correct, s.wrong));

  MockExamDraft draft({String? title}) => MockExamDraft(
        title: title ?? data.title,
        kind: kind,
        takenOn: data.date ?? DateTime.now(),
        durationMinutes: durationMinutes,
        note: note,
        sections: sections,
      );
}

/// Karne verisini deneme taslağına ve defter kartlarına çevirir.
KarneImportPlan planKarneImport(KarneData d) {
  final examType = d.examType ?? 'TYT';
  final kind = switch (examType) {
    'AYT' => MockKind.ayt,
    'YDT' => MockKind.ydt,
    _ => MockKind.tyt,
  };

  final sections = <MockSectionDraft>[];
  final keys = <String, String>{}; // karnedeki ad → ders anahtarı
  final skipped = <String>[];
  for (final s in d.sections) {
    final questions = d.questions.where((q) => q.subjectRaw == s.rawName);
    // Cevap anahtarı bile basılmamış ve hiç işaretlenmemiş bölüm: girilmemiş seçmeli.
    final notTaken = s.correct == 0 && s.wrong == 0 && questions.every((q) => q.correctAnswer == null);
    if (notTaken) {
      skipped.add(titleCaseTr(s.rawName));
      continue;
    }
    final key = Yks.keyFromReportName(examType, s.rawName) ?? subjectKey(examType, titleCaseTr(s.rawName));
    keys[s.rawName] = key;
    sections.add(MockSectionDraft(
      subject: key,
      questionCount: s.questionCount,
      correct: s.correct,
      wrong: s.wrong,
      blank: s.blank,
    ));
  }

  final mistakes = <KarneMistake>[];
  for (final entry in keys.entries) {
    final qs = [for (final q in d.questions) if (q.subjectRaw == entry.key) q];
    if (qs.isEmpty) continue;
    final count = sections.firstWhere((s) => s.subject == entry.value).questionCount;
    // Numaralar kitapçığa göre değilse (Kimya 1–7 basılmışsa) kitapçık numarasına kaydır.
    final start = Yks.bookletStart(entry.value);
    final shift = start > 1 && qs.every((q) => q.no <= count) ? start - 1 : 0;
    for (final q in qs) {
      if (q.result == KarneResult.correct) continue;
      mistakes.add(KarneMistake(
        subject: entry.value,
        questionNo: q.no + shift,
        status: q.result == KarneResult.wrong ? QuestionStatus.wrong : QuestionStatus.blank,
        kazanim: q.kazanim,
        correctAnswer: q.correctAnswer,
        givenAnswer: q.givenAnswer,
      ));
    }
  }

  final parts = <String>[
    if (d.score != null) '$examType puanı ${d.score!.replaceAll('.', ',')}',
    for (final (i, label) in const ['Sınıf', 'Okul', 'Genel'].indexed)
      if (i < d.ranks.length) '$label sırası ${d.ranks[i].$1}/${d.ranks[i].$2}',
    if (d.osymRank != null) 'ÖSYM tahmini sıralaması ${d.osymRank}',
    if (d.booklet != null) '${d.booklet} kitapçığı',
  ];

  return KarneImportPlan(
    data: d,
    kind: kind,
    sections: sections,
    mistakes: mistakes,
    skipped: skipped,
    note: parts.isEmpty ? 'Karneden içe aktarıldı.' : '${parts.join('. ')}. Karneden içe aktarıldı.',
    // ÖSYM süreleri: soru başına süre tahmini için.
    durationMinutes: switch (kind) {
      MockKind.tyt => 165,
      MockKind.ayt => 180,
      MockKind.ydt => 120,
      MockKind.branch => null,
    },
  );
}

class KarneDuplicateException implements Exception {
  const KarneDuplicateException(this.existing);
  final MockExam existing;
  @override
  String toString() => '${existing.title} (${formatDate(existing.takenOn)}) zaten kayıtlı.';
}

class KarneImportResult {
  const KarneImportResult({required this.exam, required this.cards});
  final MockExam exam;
  final int cards;
}

/// Önizlemesi onaylanan karneyi kaydeder: deneme + (isteğe bağlı) defter kartları.
class ImportKarne {
  ImportKarne({
    required SaveMockExam save,
    required MockExamRepository exams,
    required QuestionCardRepository cards,
    required IdGenerator ids,
    required Clock clock,
  })  : _save = save,
        _exams = exams,
        _cards = cards,
        _ids = ids,
        _clock = clock;

  final SaveMockExam _save;
  final MockExamRepository _exams;
  final QuestionCardRepository _cards;
  final IdGenerator _ids;
  final Clock _clock;

  /// Aynı ad ve tarihli deneme varsa [KarneDuplicateException]; [replace]
  /// ise eskisi (fotoğrafsız kartlarıyla) silinip yenisi yazılır.
  Future<KarneImportResult> call(
    KarneImportPlan plan, {
    String? title,
    bool addMistakes = true,
    bool replace = false,
  }) async {
    final draft = plan.draft(title: title);
    final day = DateTime(draft.takenOn.year, draft.takenOn.month, draft.takenOn.day);
    final all = await _exams.watchAll().first;
    final duplicate = all.where((e) => e.title.trim() == draft.title.trim() && e.takenOn == day).firstOrNull;
    if (duplicate != null) {
      if (!replace) throw KarneDuplicateException(duplicate);
      await _exams.delete(duplicate.id);
    }

    final exam = await _save(draft);
    if (!addMistakes) return KarneImportResult(exam: exam, cards: 0);

    final now = _clock();
    var created = 0;
    for (final m in plan.mistakes) {
      final subject = Yks.byKey(m.subject);
      final testName = subject?.group ?? subjectName(m.subject);
      await _cards.insert(
        QuestionCard(
          id: _ids.next(),
          status: m.status,
          origin: QuestionOrigin.mockExam,
          sourceName: exam.title,
          subject: m.subject,
          difficulty: 5,
          createdAt: now,
          mockExamId: exam.id,
          testLabel: '${exam.title}, $testName testi',
          questionNo: m.questionNo,
          testTotalQuestions: exam.section(m.subject)?.questionCount,
          topicText: m.kazanim,
          correctAnswer: m.correctAnswer,
          givenAnswer: m.status == QuestionStatus.wrong ? m.givenAnswer : null,
          note: m.answerNote,
          avgSecondsPerQuestion: exam.secondsPerQuestion,
        ),
        review: ReviewState.initial(now),
      );
      created++;
    }
    return KarneImportResult(exam: exam, cards: created);
  }
}
