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
    final q = _db.select(_db.studySessions)
      ..where((s) => s.status.equals(_running))
      ..limit(1);
    return q.watchSingleOrNull().asyncMap((row) async => row == null ? null : await _hydrate(row));
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
    final q = _db.select(_db.studySessions)..where((s) => s.id.equals(id));
    return q.watchSingleOrNull().asyncMap((row) async => row == null ? null : await _hydrate(row));
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
  Future<void> saveResults(String sessionId, List<ItemResult> results) =>
      _db.transaction(() async {
        for (final r in results) {
          await (_db.update(_db.sessionItems)
                ..where((i) => i.id.equals(r.itemId) & i.sessionId.equals(sessionId)))
              .write(SessionItemsCompanion(
            correct: Value(r.correct),
            wrong: Value(r.wrong),
            blank: Value(r.blank),
          ));
        }
        await (_db.update(_db.studySessions)
              ..where((s) => s.id.equals(sessionId) & s.status.equals(_running).not()))
            .write(StudySessionsCompanion(status: Value(SessionStatus.completed.name)));
      });

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
          ),
      ],
    );
  }
}
