import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/enum_x.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/study_session.dart';

class DriftStudySessionRepository implements StudySessionRepository {
  DriftStudySessionRepository(this._db, this._ids);

  final AppDatabase _db;
  final IdGenerator _ids;

  static final _running = SessionStatus.running.name;

  @override
  Stream<StudySession?> watchRunning() {
    // Bloklarla birleşik: oturum sürerken optikten girilen sayılar da yansır.
    final s = _db.studySessions;
    final i = _db.sessionItems;
    final q = _db.select(s).join([leftOuterJoin(i, i.sessionId.equalsExp(s.id))])
      ..where(s.status.equals(_running));
    return q.watch().asyncMap((rows) async => rows.isEmpty ? null : await _hydrate(rows.first.readTable(s)));
  }

  @override
  Stream<List<StudySession>> watchAwaitingResults() {
    final q = _db.select(_db.studySessions)
      ..where((s) => s.status.equals(SessionStatus.awaitingResults.name))
      ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]);
    return q.watch().asyncMap((rows) => Future.wait(rows.map(_hydrate)));
  }

  @override
  Stream<StudySession?> watchById(String id) {
    // Bloklarla birleşik sorgu: optik formdan gelen sayılar ekrana anında yansır.
    final s = _db.studySessions;
    final i = _db.sessionItems;
    final q = _db.select(s).join([leftOuterJoin(i, i.sessionId.equalsExp(s.id))])..where(s.id.equals(id));
    return q.watch().asyncMap((rows) async => rows.isEmpty ? null : await _hydrate(rows.first.readTable(s)));
  }

  @override
  Future<StudySession> start(List<SessionItemDraft> items, DateTime at) async {
    final id = _ids.next();
    await _db.transaction(() async {
      final running = await (_db.select(_db.studySessions)
            ..where((s) => s.status.equals(_running))
            ..limit(1))
          .getSingleOrNull();
      if (running != null) throw const SessionAlreadyRunningException();

      await _db.into(_db.studySessions).insert(
          StudySessionsCompanion.insert(id: id, status: _running, startedAt: at));
      await _db.batch((b) => b.insertAll(_db.sessionItems, [
            for (var i = 0; i < items.length; i++)
              SessionItemsCompanion.insert(
                id: _ids.next(),
                sessionId: id,
                label: items[i].label,
                pages: items[i].pages,
                sortOrder: i,
                bookId: Value(items[i].bookId),
                contentNodeId: Value(items[i].contentNodeId),
                mebNodeId: Value(items[i].mebNodeId),
                estimatedQuestions: Value(items[i].estimatedQuestions),
                subject: Value(items[i].subject),
                activity: Value(items[i].activity?.name),
              ),
          ]));
    });
    final row = await (_db.select(_db.studySessions)..where((s) => s.id.equals(id))).getSingle();
    return _hydrate(row);
  }

  @override
  Future<void> finish(String sessionId, DateTime at) async {
    final changed = await (_db.update(_db.studySessions)
          ..where((s) => s.id.equals(sessionId) & s.status.equals(_running)))
        .write(StudySessionsCompanion(
      endedAt: Value(at),
      status: Value(SessionStatus.awaitingResults.name),
    ));
    if (changed == 0) throw const SessionNotRunningException();
  }

  @override
  Future<void> cancel(String sessionId) => _db.transaction(() async {
        final row = await (_db.select(_db.studySessions)
              ..where((s) => s.id.equals(sessionId) & s.status.equals(_running)))
            .getSingleOrNull();
        if (row == null) throw const SessionNotRunningException();

        // Bu oturumda fotoğrafsız/çözümsüz işaretlenen hızlı kartlar: iz bırakma.
        // (Tekrar durumları yabancı anahtarla zincirleme silinir.)
        final c = _db.questionCards;
        await (_db.delete(c)
              ..where((t) =>
                  t.sessionId.equals(sessionId) &
                  t.questionImage.isNull() &
                  t.solutionImage.isNull() &
                  t.solutionText.isNull()))
            .go();
        // Bloklar zincirleme silinir; fotoğraflı kartların bağı kopar ama kendileri kalır.
        await (_db.delete(_db.studySessions)..where((s) => s.id.equals(sessionId))).go();
      });

  @override
  Future<void> saveResults(String sessionId, List<ItemResult> results) =>
      _db.transaction(() async {
        for (final r in results) {
          await _writeItem(r, sessionId: sessionId);
        }
        await (_db.update(_db.studySessions)
              ..where((s) => s.id.equals(sessionId) & s.status.equals(_running).not()))
            .write(StudySessionsCompanion(status: Value(SessionStatus.completed.name)));

        // Oturum sürerken işaretlenen kartların soru başına süresi o an bilinmiyordu.
        final session =
            await (_db.select(_db.studySessions)..where((s) => s.id.equals(sessionId))).getSingleOrNull();
        final end = session?.endedAt;
        if (session == null || end == null) return;
        final items = await (_db.select(_db.sessionItems)..where((i) => i.sessionId.equals(sessionId))).get();
        final solved = items.fold<int>(0, (sum, i) => sum + (i.correct ?? 0) + (i.wrong ?? 0) + (i.blank ?? 0));
        if (solved == 0) return;
        final perQuestion = end.difference(session.startedAt).inSeconds / solved;
        await (_db.update(_db.questionCards)
              ..where((t) => t.sessionId.equals(sessionId) & t.avgSecondsPerQuestion.isNull()))
            .write(QuestionCardsCompanion(avgSecondsPerQuestion: Value(perQuestion)));
      });

  @override
  Future<void> saveItemResult(ItemResult result) => _writeItem(result);

  Future<void> _writeItem(ItemResult r, {String? sessionId}) =>
      (_db.update(_db.sessionItems)
            ..where((i) {
              final byId = i.id.equals(r.itemId);
              return sessionId == null ? byId : byId & i.sessionId.equals(sessionId);
            }))
          .write(SessionItemsCompanion(
        correct: Value(r.correct),
        wrong: Value(r.wrong),
        blank: Value(r.blank),
      ));

  Future<StudySession> _hydrate(StudySessionRow row) async {
    final items = await (_db.select(_db.sessionItems)
          ..where((i) => i.sessionId.equals(row.id))
          ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
        .get();
    return StudySession(
      id: row.id,
      status: SessionStatus.values.byNameOr(row.status, SessionStatus.completed),
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      items: [
        for (final i in items)
          SessionItem(
            id: i.id,
            label: i.label,
            bookId: i.bookId,
            contentNodeId: i.contentNodeId,
            mebNodeId: i.mebNodeId,
            pages: i.pages,
            estimatedQuestions: i.estimatedQuestions,
            correct: i.correct,
            wrong: i.wrong,
            blank: i.blank,
            subject: i.subject,
            activity: StudyActivity.values.byNameOrNull(i.activity),
          ),
      ],
    );
  }
}
