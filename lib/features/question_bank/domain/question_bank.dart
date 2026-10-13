import '../../../core/media/media_storage.dart';
import '../../../core/utils/id_generator.dart';
import 'question_card.dart';
import 'srs.dart';

abstract interface class QuestionCardRepository {
  Future<void> insert(QuestionCard card, {ReviewState? review});

  /// Kartı olduğu gibi yazar. [ensureReview]: tekrar durumu yoksa bununla
  /// oluşturulur. [dropReview]: tekrar kuyruğundan çıkarır (doğru çözülen kart).
  Future<void> update(QuestionCard card, {ReviewState? ensureReview, bool dropReview = false});
  Future<QuestionCard?> findById(String id);
  Stream<QuestionCard?> watchById(String id);
  Future<void> setStarred(String cardId, bool starred);
  Future<void> delete(String cardId);
  Stream<List<QuestionCard>> watch(QuestionFilter filter);

  /// Fotoğrafı, çözümü, nedeni ya da konusu eksik kartlar (en yeniden başlayarak).
  /// Konusu eksik olanları süzmek çağıran tarafın işidir (müfredatı o bilir).
  Stream<List<QuestionCard>> watchIncomplete();

  /// Optik formun önceki işaretlerini bulmak için: bir oturum bloğunun ya da
  /// bir denemenin (isteğe bağlı olarak tek dersinin) kartları.
  Future<List<QuestionCard>> findLinked({
    String? sessionItemId,
    String? mockExamId,
    String? subject,
    String? contentNodeId,
  });

  /// Bir kitap testine (ya da yaprak başlığa) bağlı kartlar: test ekranı için.
  Stream<List<QuestionCard>> watchForNode(String contentNodeId);


  /// Denemelerden gelen yanlış ve boşlar (konu bazlı net kaybı için).
  Stream<List<QuestionCard>> watchMockExamMistakes();

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

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Doğrula → fotoğrafları (varsa) kalıcı depoya al → kartı + SM-2 durumunu yaz.
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
      String? question;
      if (draft.questionImagePath != null) {
        question = await _media.importFile(draft.questionImagePath!, bucket: 'questions');
        stored.add(question);
      }
      String? solution;
      if (draft.solutionImagePath != null) {
        solution = await _media.importFile(draft.solutionImagePath!, bucket: 'solutions');
        stored.add(solution);
      }
      final now = _clock();
      card = QuestionCard(
        id: _ids.next(),
        status: draft.status,
        origin: draft.origin,
        questionImage: question,
        solutionImage: solution,
        solutionText: _clean(draft.solutionText),
        sourceName: _clean(draft.sourceName) ?? unknownSourceName,
        bookId: draft.bookId,
        contentNodeId: draft.contentNodeId,
        sessionId: draft.sessionId,
        mebNodeId: draft.mebNodeId,
        subject: draft.subject!.trim(),
        testTotalQuestions: draft.testTotalQuestions,
        reason: draft.status == QuestionStatus.correct ? null : draft.reason,
        reasonNote: draft.status != QuestionStatus.correct && draft.reason == MistakeReason.other
            ? _clean(draft.reasonNote)
            : null,
        topicText: _clean(draft.topicText),
        avgSecondsPerQuestion: draft.avgSecondsPerQuestion,
        difficulty: draft.difficulty,
        isStarred: draft.isStarred,
        note: _clean(draft.note),
        createdAt: now,
        questionNo: draft.questionNo,
        testLabel: _clean(draft.testLabel),
        sessionItemId: draft.sessionItemId,
        mockExamId: draft.mockExamId,
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

/// Var olan kartı günceller (Eksikler'i tamamlama, düzenleme).
/// [QuestionDraft.questionImagePath] doluysa YENİ fotoğraftır: eskisinin yerine
/// geçer ve eski dosya kayıt başarılı olduktan sonra silinir.
class UpdateQuestionCard {
  UpdateQuestionCard({
    required QuestionCardRepository repository,
    required MediaStorage media,
    required Clock clock,
  })  : _repository = repository,
        _media = media,
        _clock = clock;

  final QuestionCardRepository _repository;
  final MediaStorage _media;
  final Clock _clock;

  Future<QuestionCard> call(
    QuestionCard original,
    QuestionDraft draft, {
    bool clearQuestionImage = false,
    bool clearSolutionImage = false,
  }) async {
    final issues = draft.validate();
    if (issues.isNotEmpty) throw QuestionDraftInvalid(issues);

    final stored = <String>[];
    final replaced = <String>[];
    final QuestionCard card;
    try {
      var question = original.questionImage;
      if (draft.questionImagePath != null) {
        final next = await _media.importFile(draft.questionImagePath!, bucket: 'questions');
        stored.add(next);
        if (question != null) replaced.add(question);
        question = next;
      } else if (clearQuestionImage && question != null) {
        replaced.add(question);
        question = null;
      }

      var solution = original.solutionImage;
      if (draft.solutionImagePath != null) {
        final next = await _media.importFile(draft.solutionImagePath!, bucket: 'solutions');
        stored.add(next);
        if (solution != null) replaced.add(solution);
        solution = next;
      } else if (clearSolutionImage && solution != null) {
        replaced.add(solution);
        solution = null;
      }

      card = QuestionCard(
        id: original.id,
        status: draft.status,
        origin: draft.origin,
        questionImage: question,
        solutionImage: solution,
        solutionText: _clean(draft.solutionText),
        sourceName: _clean(draft.sourceName) ?? unknownSourceName,
        bookId: draft.bookId,
        contentNodeId: draft.contentNodeId,
        sessionId: draft.sessionId,
        mebNodeId: draft.mebNodeId,
        subject: draft.subject!.trim(),
        testTotalQuestions: draft.testTotalQuestions,
        reason: draft.status == QuestionStatus.correct ? null : draft.reason,
        reasonNote: draft.status != QuestionStatus.correct && draft.reason == MistakeReason.other
            ? _clean(draft.reasonNote)
            : null,
        topicText: _clean(draft.topicText),
        avgSecondsPerQuestion: draft.avgSecondsPerQuestion,
        difficulty: draft.difficulty,
        isStarred: draft.isStarred,
        note: _clean(draft.note),
        createdAt: original.createdAt,
        questionNo: draft.questionNo,
        testLabel: _clean(draft.testLabel),
        sessionItemId: draft.sessionItemId,
        mockExamId: draft.mockExamId,
      );
      final correct = card.status == QuestionStatus.correct;
      await _repository.update(
        card,
        ensureReview: correct ? null : ReviewState.initial(_clock()),
        dropReview: correct,
      );
    } catch (_) {
      for (final path in stored) {
        await _media.delete(path);
      }
      rethrow;
    }
    for (final path in replaced) {
      await _media.delete(path);
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
    final question = card.questionImage;
    if (question != null) await _media.delete(question);
    final solution = card.solutionImage;
    if (solution != null) await _media.delete(solution);
  }

  /// Çoklu silme (Defter'de seçim modu); silinen kart sayısını döner.
  Future<int> many(Iterable<String> ids) async {
    var count = 0;
    for (final id in ids) {
      await call(id);
      count++;
    }
    return count;
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
