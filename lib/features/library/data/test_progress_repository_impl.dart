import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/progress.dart';

class DriftTestProgressRepository implements TestProgressRepository {
  DriftTestProgressRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<Map<String, TestResult>> watchAll() => _db.select(_db.testResults).watch().map((rows) => {
        for (final r in rows)
          r.contentNodeId: TestResult(
            nodeId: r.contentNodeId,
            bookId: r.bookId,
            solvedAt: r.solvedAt,
            correct: r.correct,
            wrong: r.wrong,
            blank: r.blank,
            total: r.total,
            sessionId: r.sessionId,
          ),
      });

  TestResultsCompanion _row(TestResult r) => TestResultsCompanion.insert(
        contentNodeId: r.nodeId,
        bookId: r.bookId,
        solvedAt: r.solvedAt,
        correct: Value(r.correct),
        wrong: Value(r.wrong),
        blank: Value(r.blank),
        total: Value(r.total),
        sessionId: Value(r.sessionId),
      );

  @override
  Future<void> save(TestResult result) => _db.into(_db.testResults).insertOnConflictUpdate(_row(result));

  @override
  Future<void> saveIfAbsent(List<TestResult> results) async {
    if (results.isEmpty) return;
    await _db.batch((b) => b.insertAll(
          _db.testResults,
          [for (final r in results) _row(r)],
          mode: InsertMode.insertOrIgnore,
        ));
  }

  @override
  Future<void> clear(String nodeId) =>
      (_db.delete(_db.testResults)..where((t) => t.contentNodeId.equals(nodeId))).go();
}
