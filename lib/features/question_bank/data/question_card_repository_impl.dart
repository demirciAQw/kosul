import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/text/turkish_text.dart';
import '../../../core/utils/enum_x.dart';
import '../domain/question_bank.dart';
import '../domain/question_card.dart';
import '../domain/srs.dart';

class DriftQuestionCardRepository implements QuestionCardRepository {
  DriftQuestionCardRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> insert(QuestionCard card, {ReviewState? review}) => _db.transaction(() async {
        await _db.into(_db.questionCards).insert(_toCompanion(card));
        if (review != null) await applyReview(card.id, review);
      });

  @override
  Future<void> update(QuestionCard card, {ReviewState? ensureReview, bool dropReview = false}) =>
      _db.transaction(() async {
        await (_db.update(_db.questionCards)..where((c) => c.id.equals(card.id))).write(_toCompanion(card));
        if (dropReview) {
          await (_db.delete(_db.reviewStates)..where((r) => r.cardId.equals(card.id))).go();
        } else if (ensureReview != null && await reviewStateOf(card.id) == null) {
          await applyReview(card.id, ensureReview);
        }
      });

  @override
  Future<QuestionCard?> findById(String id) async {
    final row = await (_db.select(_db.questionCards)..where((c) => c.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Stream<QuestionCard?> watchById(String id) =>
      (_db.select(_db.questionCards)..where((c) => c.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toEntity(row));

  @override
  Future<void> setStarred(String cardId, bool starred) =>
      (_db.update(_db.questionCards)..where((c) => c.id.equals(cardId)))
          .write(QuestionCardsCompanion(isStarred: Value(starred)));

  @override
  Future<void> delete(String cardId) => _db.transaction(() async {
        // Tekrar kaydı açıkça silinir; yabancı anahtar zincirine güvenmiyoruz
        // (eski sürümden yükseltmede bağ kopmuş olabilir).
        await (_db.delete(_db.reviewStates)..where((r) => r.cardId.equals(cardId))).go();
        await (_db.delete(_db.questionCards)..where((c) => c.id.equals(cardId))).go();
      });

  @override
  Stream<List<QuestionCard>> watch(QuestionFilter f) {
    final q = _db.select(_db.questionCards)
      ..where((t) {
        Expression<bool> e = t.difficulty.isBetweenValues(f.minDifficulty, f.maxDifficulty);
        if (f.subject != null) e = e & t.subject.equals(f.subject!);
        if (f.bookId != null) e = e & t.bookId.equals(f.bookId!);
        if (f.mebNodeIds.isNotEmpty) e = e & t.mebNodeId.isIn(f.mebNodeIds);
        if (f.reasons.isNotEmpty) e = e & t.reason.isIn(f.reasons.map((r) => r.name));
        if (f.statuses.isNotEmpty) e = e & t.status.isIn(f.statuses.map((s) => s.name));
        if (f.starredOnly) e = e & t.isStarred.equals(true);
        final text = normalizeTr(f.text ?? '');
        // Türkçe katlanmış sütunda arama: "işçi" ile "ISCI" aynı sonucu verir.
        if (text.isNotEmpty) e = e & t.searchText.like('%$text%');
        return e;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<List<QuestionCard>> watchIncomplete() {
    final q = _db.select(_db.questionCards)
      ..where((t) =>
          t.questionImage.isNull() |
          (t.solutionImage.isNull() & t.solutionText.isNull()) |
          (t.status.equals(QuestionStatus.correct.name).not() & t.reason.isNull()) |
          t.mebNodeId.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<QuestionCard>> findLinked({
    String? sessionItemId,
    String? mockExamId,
    String? subject,
    String? contentNodeId,
  }) async {
    if (sessionItemId == null && mockExamId == null && contentNodeId == null) return const [];
    final q = _db.select(_db.questionCards)
      ..where((t) {
        final node = contentNodeId;
        if (node != null) return t.contentNodeId.equals(node);
        if (sessionItemId != null) return t.sessionItemId.equals(sessionItemId);
        Expression<bool> e = t.mockExamId.equals(mockExamId!);
        final s = subject;
        if (s != null) e = e & t.subject.equals(s);
        return e;
      });
    return (await q.get()).map(_toEntity).toList();
  }

  @override
  Stream<List<QuestionCard>> watchForNode(String contentNodeId) {
    final q = _db.select(_db.questionCards)
      ..where((t) => t.contentNodeId.equals(contentNodeId))
      ..orderBy([(t) => OrderingTerm.asc(t.questionNo), (t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<List<QuestionCard>> watchMockExamMistakes() {
    final q = _db.select(_db.questionCards)
      ..where((t) =>
          t.mockExamId.isNotNull() &
          t.status.isIn([QuestionStatus.wrong.name, QuestionStatus.blank.name]));
    return q.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<int> watchDueCount(DateTime now) {
    final r = _db.reviewStates;
    final c = _db.questionCards;
    final count = r.cardId.count();
    // Yalnızca hâlâ var olan kartlar sayılır: kart silinmiş ama tekrar kaydı
    // kalmışsa (eski veri) sayaca girmez.
    final q = _db.selectOnly(r)
      ..join([innerJoin(c, c.id.equalsExp(r.cardId))])
      ..addColumns([count])
      ..where(r.dueAt.isSmallerOrEqualValue(now));
    return q.map((row) => row.read(count) ?? 0).watchSingle();
  }

  @override
  Future<List<DueReview>> dueNow(DateTime now, {int limit = 50}) async {
    final c = _db.questionCards;
    final r = _db.reviewStates;
    final q = _db.select(c).join([innerJoin(r, r.cardId.equalsExp(c.id))])
      ..where(r.dueAt.isSmallerOrEqualValue(now))
      ..orderBy([OrderingTerm.asc(r.dueAt)])
      ..limit(limit);
    final rows = await q.get();
    return [
      for (final row in rows) DueReview(_toEntity(row.readTable(c)), _toState(row.readTable(r))),
    ];
  }

  @override
  Future<ReviewState?> reviewStateOf(String cardId) async {
    final row = await (_db.select(_db.reviewStates)..where((s) => s.cardId.equals(cardId)))
        .getSingleOrNull();
    return row == null ? null : _toState(row);
  }

  @override
  Future<void> applyReview(String cardId, ReviewState s) =>
      _db.into(_db.reviewStates).insertOnConflictUpdate(ReviewStatesCompanion.insert(
            cardId: cardId,
            easeFactor: s.easeFactor,
            intervalDays: s.intervalDays,
            repetitions: s.repetitions,
            dueAt: s.dueAt,
            lastReviewedAt: Value(s.lastReviewedAt),
          ));

  static ReviewState _toState(ReviewStateRow r) => ReviewState(
        easeFactor: r.easeFactor,
        intervalDays: r.intervalDays,
        repetitions: r.repetitions,
        dueAt: r.dueAt,
        lastReviewedAt: r.lastReviewedAt,
      );

  static String _searchText(QuestionCard c) => normalizeTr([
        c.sourceName,
        c.subject,
        c.testLabel,
        c.solutionText,
        c.note,
        c.reason?.label,
        c.reasonNote,
        c.topicText,
      ].whereType<String>().join(' '));

  static QuestionCardsCompanion _toCompanion(QuestionCard c) => QuestionCardsCompanion.insert(
        id: c.id,
        status: c.status.name,
        origin: c.origin.name,
        questionImage: Value(c.questionImage),
        solutionImage: Value(c.solutionImage),
        solutionText: Value(c.solutionText),
        sourceName: c.sourceName,
        bookId: Value(c.bookId),
        contentNodeId: Value(c.contentNodeId),
        sessionId: Value(c.sessionId),
        mebNodeId: Value(c.mebNodeId),
        subject: c.subject,
        testTotalQuestions: Value(c.testTotalQuestions),
        reason: Value(c.reason?.name),
        avgSecondsPerQuestion: Value(c.avgSecondsPerQuestion),
        difficulty: c.difficulty,
        isStarred: Value(c.isStarred),
        note: Value(c.note),
        searchText: _searchText(c),
        createdAt: c.createdAt,
        questionNo: Value(c.questionNo),
        testLabel: Value(c.testLabel),
        sessionItemId: Value(c.sessionItemId),
        mockExamId: Value(c.mockExamId),
        reasonNote: Value(c.reasonNote),
        topicText: Value(c.topicText),
      );

  static QuestionCard _toEntity(QuestionCardRow r) => QuestionCard(
        id: r.id,
        status: QuestionStatus.values.byNameOr(r.status, QuestionStatus.wrong),
        origin: QuestionOrigin.values.byNameOr(r.origin, QuestionOrigin.independent),
        questionImage: r.questionImage,
        solutionImage: r.solutionImage,
        solutionText: r.solutionText,
        sourceName: r.sourceName,
        bookId: r.bookId,
        contentNodeId: r.contentNodeId,
        sessionId: r.sessionId,
        mebNodeId: r.mebNodeId,
        subject: r.subject,
        testTotalQuestions: r.testTotalQuestions,
        reason: MistakeReason.values.byNameOrNull(r.reason),
        avgSecondsPerQuestion: r.avgSecondsPerQuestion,
        difficulty: r.difficulty,
        isStarred: r.isStarred,
        note: r.note,
        createdAt: r.createdAt,
        questionNo: r.questionNo,
        testLabel: r.testLabel,
        sessionItemId: r.sessionItemId,
        mockExamId: r.mockExamId,
        reasonNote: r.reasonNote,
        topicText: r.topicText,
      );
}
