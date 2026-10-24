import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/dashboard/domain/ai_report.dart';
import 'package:kocum/features/question_bank/domain/practice_test.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/presentation/question_pdf.dart';
import 'package:kocum/features/study_session/domain/study_session.dart';
import 'package:kocum/features/tools/data/full_export.dart';
import 'package:kocum/features/tools/domain/export_log.dart';

QuestionCard _c(String id, {int diff = 5, String topic = 'TÜREV', MistakeReason? reason, DateTime? at}) => QuestionCard(
      id: id,
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: 'Kitap',
      subject: 'AYT Matematik',
      difficulty: diff,
      createdAt: at ?? DateTime(2026, 10, 20),
      topicText: topic,
      reason: reason,
      questionImage: 'questions/$id.webp',
    );

void main() {
  group('Yanlışlardan test', () {
    final cards = [
      for (var i = 0; i < 6; i++) _c('e$i', diff: 2),
      for (var i = 0; i < 6; i++) _c('m$i', diff: 5, topic: 'LİMİT'),
      for (var i = 0; i < 2; i++) _c('h$i', diff: 9, topic: 'İNTEGRAL', reason: MistakeReason.carelessness),
    ];

    test('karma: kolay, orta, zor dengeli; zor az ise tamamlanır ve not düşülür', () {
      final t = buildPracticeTest(cards, const PracticeTestOptions(count: 9, band: DifficultyBand.mixed), curriculum: const {});
      expect(t.cards, hasLength(9));
      expect(t.cards.where((c) => c.difficulty == 9), hasLength(2));
      expect(t.notes.join(), contains('Zor soru az'));
      // kolaydan zora sıralı
      expect(t.cards.first.difficulty, 2);
      expect(t.cards.last.difficulty, 9);
    });

    test('yalnızca dikkat hataları', () {
      final t = buildPracticeTest(cards, const PracticeTestOptions(count: 10, reason: MistakeReason.carelessness),
          curriculum: const {});
      expect(t.cards.map((c) => c.id).toSet(), {'h0', 'h1'});
      expect(t.notes.join(), contains('2 soru var'));
    });

    test('çok yanlış yapılan konuların hepsi kapsanır', () {
      final t = buildPracticeTest(cards, const PracticeTestOptions(count: 3, coverWeakTopics: true), curriculum: const {});
      final topics = t.cards.map((c) => c.topicText).toSet();
      expect(topics, {'TÜREV', 'LİMİT', 'İNTEGRAL'});
    });

    test('aynı tohumla aynı test', () {
      const o = PracticeTestOptions(count: 5);
      final a = buildPracticeTest(cards, o, curriculum: const {}, seed: 7).cards.map((c) => c.id).toList();
      final b = buildPracticeTest(cards, o, curriculum: const {}, seed: 7).cards.map((c) => c.id).toList();
      expect(a, b);
    });
  });

  test('Claude paketleri: son paketten bu yana ve etiket', () {
    final log = [
      ClaudeBatch(number: 1, at: DateTime(2026, 10, 10), full: false, questions: 5, sessions: 2),
      ClaudeBatch(number: 2, at: DateTime(2026, 10, 20), from: DateTime(2026, 10, 10), full: false, questions: 3, sessions: 1),
    ];
    expect(nextSince(log), DateTime(2026, 10, 20));
    expect(batchOf(DateTime(2026, 10, 15), log)?.label, 'Paket #2');
    expect(batchOf(DateTime(2026, 10, 5), log)?.label, 'Paket #1');
    expect(batchOf(DateTime(2026, 10, 22), log), isNull); // henüz gönderilmedi
    final back = ClaudeBatch.fromJson(log[1].toJson())!;
    expect((back.number, back.from), (2, DateTime(2026, 10, 10)));
  });

  test('PDF ızgarası: 4 kutu, taşma yok; görsel oranı korunur', () {
    const client = Size(539, 786); // A4, 28 nokta kenar boşluğu
    final cells = gridCells(client);
    expect(cells, hasLength(4));
    for (final c in cells) {
      expect(c.right, lessThanOrEqualTo(client.width + 0.01));
      expect(c.bottom, lessThanOrEqualTo(client.height + 0.01));
    }
    expect(cells[1].left, greaterThan(cells[0].right));
    final fit = fitInto(const Rect.fromLTWH(0, 0, 200, 100), 400, 400);
    expect((fit.width, fit.height), (100.0, 100.0));
    expect(fit.left, 50);
  });

  test('rapor: yeni veriler, oturumlar ve hedef bölümü', () {
    final now = DateTime(2026, 10, 24, 12);
    final session = StudySession(
      id: 's',
      status: SessionStatus.completed,
      startedAt: DateTime(2026, 10, 23, 19),
      endedAt: DateTime(2026, 10, 23, 20, 10),
      items: [const SessionItem(id: 'i', label: 'Türev testi', subject: 'AYT Matematik', correct: 8, wrong: 2, blank: 0)],
    );
    final r = buildAiReport(
      cards: [_c('old', at: DateTime(2026, 10, 1)), _c('new', at: DateTime(2026, 10, 23))],
      curriculum: const {},
      exams: const [],
      books: const [],
      now: now,
      options: AiReportOptions(days: null, since: DateTime(2026, 10, 20), label: 'Paket #3'),
      sessions: [session],
      deadline: DateTime(2026, 12, 31),
    );
    expect(r.markdown, contains('Paket #3'));
    expect(r.questionCount, 1);
    expect(r.markdown, contains('| 2026-10-23 | 19:00 | 70 | Türev testi'));
    expect(r.markdown, contains('## Hedef: tüm kitapları 2026-12-31'));
  });

  test('yedek JSON sayıları ve biçimi', () {
    final data = fullDataJson(
      now: DateTime(2026, 10, 24),
      cards: [_c('a')],
      books: const [],
      results: const {},
      sessions: const [],
      exams: const [],
      plans: const [],
      notes: const [],
    );
    expect(data['format'], 'kocum.backup');
    expect((data['counts'] as Map)['questions'], 1);
    expect((data['questions'] as List).single['id'], 'a');
  });
}
