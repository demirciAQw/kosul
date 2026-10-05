import '../../../core/media/media_storage.dart';
import '../../../core/utils/id_generator.dart';
import 'question_card.dart';
import 'srs.dart';

abstract interface class QuestionCardRepository {
  Future<void> insert(QuestionCard card, {ReviewState? review});
  Future<QuestionCard?> findById(String id);
  Stream<QuestionCard?> watchById(String id);
  Future<void> setStarred(String cardId, bool starred);
  Future<void> delete(String cardId);
  Stream<List<QuestionCard>> watch(QuestionFilter filter);

  /// "Yanlışlarımı Göster": günü gelmiş kartlar, en gecikmişten başlayarak.
  Stream<int> watchDueCount(DateTime now);
  Future<List<DueReview>> dueNow(DateTime now, {int limit = 50});
  Future<ReviewState?> reviewStateOf(String cardId);
  Future<void> applyReview(String cardId, ReviewState next);
}

/// Günü gelmiş kart + zamanlama durumu (butonlarda sonraki aralığı göstermek için).
class DueReview {
  const DueReview(this.card, this.state);
  final QuestionCard card;
  final ReviewState state;
}

/// Doğrula → fotoğrafları kalıcı depoya al → kartı + SM-2 durumunu yaz.
/// Herhangi bir adım başarısız olursa kalıcı depoya kopyalanan dosyalar
/// geri alınır; geçici dosyalar yeniden deneme için yerinde kalır.
class SaveQuestionCard {
  SaveQuestionCard({
    required QuestionCardRepository repository,
    required MediaStorage media,
    required IdGenerator ids,
    required Clock clock,
  })  : _repository = repository,
        _media = media,
        _ids = ids,
        _clock = clock;

  final QuestionCardRepository _repository;
  final MediaStorage _media;
  final IdGenerator _ids;
  final Clock _clock;

  Future<QuestionCard> call(QuestionDraft draft) async {
    final issues = draft.validate();
    if (issues.isNotEmpty) throw QuestionDraftInvalid(issues);

    final stored = <String>[];
    final QuestionCard card;
    try {
      final question = await _media.importFile(draft.questionImagePath!, bucket: 'questions');
      stored.add(question);
      String? solution;
      if (draft.solutionImagePath != null) {
        solution = await _media.importFile(draft.solutionImagePath!, bucket: 'solutions');
        stored.add(solution);
      }
      final now = _clock();
      final text = draft.solutionText?.trim();
      final note = draft.note?.trim();
      card = QuestionCard(
        id: _ids.next(),
        status: draft.status,
        origin: draft.origin,
        questionImage: question,
        solutionImage: solution,
        solutionText: (text == null || text.isEmpty) ? null : text,
        sourceName: draft.sourceName.trim(),
        bookId: draft.bookId,
        contentNodeId: draft.contentNodeId,
        sessionId: draft.sessionId,
        mebNodeId: draft.mebNodeId,
        subject: draft.subject!.trim(),
        testTotalQuestions: draft.testTotalQuestions,
        reason: draft.reason,
        avgSecondsPerQuestion: draft.avgSecondsPerQuestion,
        difficulty: draft.difficulty,
        isStarred: draft.isStarred,
        note: (note == null || note.isEmpty) ? null : note,
        createdAt: now,
      );
      // Doğru çözülmüş GK soruları tekrar kuyruğuna girmez.
      await _repository.insert(
        card,
        review: card.status == QuestionStatus.correct ? null : ReviewState.initial(now),
      );
    } catch (_) {
      for (final path in stored) {
        await _media.delete(path);
      }
      rethrow;
    }
    await _media.discardTemp(draft.questionImagePath);
    await _media.discardTemp(draft.solutionImagePath);
    return card;
  }
}

/// Kartı ve fotoğraflarını siler (SM-2 durumu veritabanında zincirleme silinir).
class DeleteQuestionCard {
  DeleteQuestionCard({required QuestionCardRepository repository, required MediaStorage media})
      : _repository = repository,
        _media = media;

  final QuestionCardRepository _repository;
  final MediaStorage _media;

  Future<void> call(String id) async {
    final card = await _repository.findById(id);
    if (card == null) return;
    await _repository.delete(id);
    await _media.delete(card.questionImage);
    final solution = card.solutionImage;
    if (solution != null) await _media.delete(solution);
  }
}

/// Tekrar sırasında verilen notu SM-2 ile zamanlamaya çevirir.
class GradeReview {
  GradeReview({required QuestionCardRepository repository, required Clock clock})
      : _repository = repository,
        _clock = clock;

  final QuestionCardRepository _repository;
  final Clock _clock;

  Future<ReviewState> call(String cardId, RecallGrade grade) async {
    final now = _clock();
    final current = await _repository.reviewStateOf(cardId) ?? ReviewState.initial(now);
    final next = Sm2Scheduler.review(current, grade, now);
    await _repository.applyReview(cardId, next);
    return next;
  }
}
