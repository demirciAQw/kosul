import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/dashboard/domain/ai_report.dart';
import 'package:kocum/features/question_bank/domain/question_bank.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/recurrence.dart';
import 'package:kocum/features/question_bank/domain/srs.dart';

QuestionCard _c(
  String id, {
  String topic = 'TÜREV',
  MistakeReason? reason,
  QuestionStatus status = QuestionStatus.wrong,
  DateTime? at,
  String subject = 'AYT Matematik',
  String? photo,
}) =>
    QuestionCard(
      id: id,
      status: status,
      origin: QuestionOrigin.book,
      sourceName: 'Kitap',
      subject: subject,
      difficulty: 5,
      createdAt: at ?? DateTime(2026, 10, 20),
      topicText: topic,
      reason: reason,
      questionImage: photo,
    );

void main() {
  group('Benzer hatalar', () {
    final cards = [
      _c('a', reason: MistakeReason.carelessness),
      _c('b', reason: MistakeReason.carelessness),
      _c('c', reason: MistakeReason.knowledgeGap),
      _c('d', topic: 'LİMİT'),
      _c('e', topic: 'LİMİT', status: QuestionStatus.correct),
    ];
    final rec = recurrenceOf(cards, const {});

    test('aynı konu ve aynı neden sayılır; doğrular sayılmaz', () {
      expect(rec['a']!.sameTopic, 3);
      expect(rec['a']!.sameTopicReason, 2);
      expect(rec['a']!.isRecurring, isTrue);
      expect(rec['c']!.sameTopicReason, 1);
      expect(rec['d']!.sameTopic, 1);
      expect(rec['d']!.isRecurring, isFalse);
      expect(rec.containsKey('e'), isFalse);
      expect(rec['a']!.message, contains('Türev konusunda 3 hatan var, 2 tanesi'));
    });

    test('tekrar kuyruğu: tekrarlayanlar öne, gerisi eski sırasıyla', () {
      final state = ReviewState.initial(DateTime(2026, 10, 20));
      final due = [for (final id in ['d', 'c', 'a', 'b']) DueReview(cards.firstWhere((x) => x.id == id), state)];
      final order = prioritizeDue(due, rec).map((x) => x.card.id).toList();
      // a ve b: aynı konu + aynı neden (ağırlık 2*2+3=7); c: yalnızca konu (1*2+3=5); d: tekrarlamıyor.
      expect(order, ['a', 'b', 'c', 'd']);
    });
  });

  group('Yapay zekâ raporu', () {
    final now = DateTime(2026, 10, 24);
    final cards = [
      _c('a', reason: MistakeReason.carelessness, at: DateTime(2026, 10, 22), photo: 'questions/a.webp'),
      _c('b', reason: MistakeReason.carelessness, at: DateTime(2026, 10, 21)),
      _c('c', status: QuestionStatus.blank, at: DateTime(2026, 10, 1), subject: 'TYT Fizik', topic: 'KALDIRMA KUVVETİ'),
    ];

    test('yönerge, özet, tekrarlayan hatalar ve soru tablosu', () {
      final r = buildAiReport(cards: cards, curriculum: const {}, exams: const [], books: const [], now: now);
      expect(r.markdown, contains('## Senden istediğim'));
      expect(r.markdown, contains('yanlış 2, boş 1'));
      expect(r.markdown, contains('## En çok net kaybettiren konular'));
      expect(r.markdown, contains('| # | Tarih | Ders'));
      expect(r.questionCount, 3);
      expect(r.photos, isEmpty);
    });

    test('kapsam: son 7 gün ve tek ders; fotoğraflar adlarıyla', () {
      final r = buildAiReport(
        cards: cards,
        curriculum: const {},
        exams: const [],
        books: const [],
        now: now,
        options: const AiReportOptions(days: 7, subject: 'AYT Matematik', photos: true),
      );
      expect(r.questionCount, 2);
      expect(r.markdown, isNot(contains('Kaldırma')));
      expect(r.photos.single.zipName, startsWith('fotograflar/01_AYT_Matematik'));
      expect(r.markdown, contains('fotograflar/01_AYT_Matematik'));
    });
  });
}
