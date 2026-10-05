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
  Future<void> delete(String cardId) =>
      (_db.delete(_db.questionCards)..where((c) => c.id.equals(cardId))).go();

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
  Stream<int> watchDueCount(DateTime now) {
    final r = _db.reviewStates;
    final count = r.cardId.count();
    final q = _db.selectOnly(r)
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
        c.solutionText,
        c.note,
        c.reason?.label,
      ].whereType<String>().join(' '));

  static QuestionCardsCompanion _toCompanion(QuestionCard c) => QuestionCardsCompanion.insert(
        id: c.id,
        status: c.status.name,
        origin: c.origin.name,
        questionImage: c.questionImage,
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
      );
}
