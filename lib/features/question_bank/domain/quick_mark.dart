import '../../../core/utils/id_generator.dart';
import 'question_bank.dart';
import 'question_card.dart';
import 'srs.dart';

/// Hızlı işaretlemenin bağlamı: ders, konu, kaynak ve süre testten gelir;
/// kullanıcı yalnızca soru numarasına dokunur.
class QuickMarkContext {
  const QuickMarkContext({
    required this.origin,
    required this.subject,
    required this.sourceName,
    this.bookId,
    this.contentNodeId,
    this.mebNodeId,
    this.sessionId,
    this.sessionItemId,
    this.mockExamId,
    this.testLabel,
    this.avgSecondsPerQuestion,
  });

  final QuestionOrigin origin;
  final String subject;
  final String sourceName;
  final String? bookId;
  final String? contentNodeId;
  final String? mebNodeId;
  final String? sessionId;
  final String? sessionItemId;
  final String? mockExamId;
  final String? testLabel;
  final double? avgSecondsPerQuestion;
}

class QuickMarkSummary {
  const QuickMarkSummary({
    required this.created,
    required this.updated,
    required this.removed,
    required this.kept,
  });

  final int created;
  final int updated;
  final int removed;

  /// İşareti kaldırıldığı hâlde fotoğraf/çözüm eklendiği için silinmeyen kartlar.
  final int kept;

  String get message {
    final parts = [
      if (created > 0) '$created yeni soru deftere eklendi',
      if (updated > 0) '$updated soru güncellendi',
      if (removed > 0) '$removed soru defterden çıkarıldı',
      if (kept > 0) '$kept soru fotoğraflı olduğu için defterde bırakıldı',
    ];
    return parts.isEmpty ? 'Değişiklik yok.' : '${parts.join(', ')}.';
  }
}

/// Optik formdaki işaretleri defterle eşitler.
///
/// - Yeni işaretlenen numara → fotoğrafsız "hızlı" kart (Eksikler'de bekler).
/// - Durumu değişen numara (yanlış ↔ boş) → kart güncellenir.
/// - İşareti kaldırılan numara → kart çıplaksa silinir, emek verilmişse kalır.
class QuickMarkQuestions {
  QuickMarkQuestions({
    required QuestionCardRepository repository,
    required IdGenerator ids,
    required Clock clock,
  })  : _repository = repository,
        _ids = ids,
        _clock = clock;

  final QuestionCardRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  Future<List<QuestionCard>> _linked(QuickMarkContext ctx) {
    if (ctx.sessionItemId != null) return _repository.findLinked(sessionItemId: ctx.sessionItemId);
    if (ctx.mockExamId != null) {
      return _repository.findLinked(mockExamId: ctx.mockExamId, subject: ctx.subject);
    }
    return Future.value(const <QuestionCard>[]);
  }

  /// Formu önceki işaretlerle açmak için.
  Future<Map<int, QuestionStatus>> existingMarks(QuickMarkContext ctx) async => {
        for (final c in await _linked(ctx))
          if (c.questionNo != null && c.status != QuestionStatus.correct) c.questionNo!: c.status,
      };

  Future<QuickMarkSummary> call(
    QuickMarkContext ctx, {
    required int total,
    required Map<int, QuestionStatus> marks,
  }) async {
    final byNo = <int, QuestionCard>{
      for (final c in await _linked(ctx))
        if (c.questionNo != null) c.questionNo!: c,
    };
    final now = _clock();
    var created = 0, updated = 0, removed = 0, kept = 0;

    for (final entry in marks.entries) {
      if (entry.value == QuestionStatus.correct || entry.key < 1 || entry.key > total) continue;
      final existing = byNo[entry.key];
      if (existing == null) {
        await _repository.insert(
          QuestionCard(
            id: _ids.next(),
            status: entry.value,
            origin: ctx.origin,
            sourceName: ctx.sourceName,
            subject: ctx.subject,
            difficulty: 5,
            createdAt: now,
            bookId: ctx.bookId,
            contentNodeId: ctx.contentNodeId,
            mebNodeId: ctx.mebNodeId,
            sessionId: ctx.sessionId,
            sessionItemId: ctx.sessionItemId,
            mockExamId: ctx.mockExamId,
            testLabel: ctx.testLabel,
            testTotalQuestions: total,
            avgSecondsPerQuestion: ctx.avgSecondsPerQuestion,
            questionNo: entry.key,
          ),
          review: ReviewState.initial(now),
        );
        created++;
      } else if (existing.status != entry.value) {
        await _repository.update(existing.copyWith(status: entry.value), ensureReview: ReviewState.initial(now));
        updated++;
      }
    }

    for (final entry in byNo.entries) {
      final mark = marks[entry.key];
      if (mark != null && mark != QuestionStatus.correct && entry.key <= total) continue;
      final card = entry.value;
      if (card.status == QuestionStatus.correct) continue; // GK olarak eklenmiş doğru soru: dokunma
      if (card.isBare) {
        await _repository.delete(card.id);
        removed++;
      } else {
        kept++;
      }
    }
    return QuickMarkSummary(created: created, updated: updated, removed: removed, kept: kept);
  }
}
