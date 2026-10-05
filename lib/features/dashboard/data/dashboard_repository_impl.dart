import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../question_bank/domain/question_card.dart';
import '../domain/dashboard.dart';

class DriftDashboardRepository implements DashboardRepository {
  DriftDashboardRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<MistakeStat>> watchMistakeStats(MistakeDimension by, {DateTime? since}) {
    final c = _db.questionCards;
    final key = switch (by) {
      MistakeDimension.topic => c.mebNodeId,
      MistakeDimension.reason => c.reason,
      MistakeDimension.subject => c.subject,
    };
    final count = c.id.count();
    final lost = c.avgSecondsPerQuestion.sum();

    Expression<bool> condition =
        c.status.isIn([QuestionStatus.wrong.name, QuestionStatus.blank.name]);
    if (since != null) condition = condition & c.createdAt.isBiggerOrEqualValue(since);

    final query = _db.selectOnly(c)
      ..addColumns([key, count, lost])
      ..where(condition)
      ..groupBy([key])
      ..orderBy([OrderingTerm.desc(count)]);

    return query.watch().map((rows) => [
          for (final row in rows)
            MistakeStat(
              key: row.read(key),
              count: row.read(count) ?? 0,
              lostSeconds: row.read(lost) ?? 0,
            ),
        ]);
  }

  @override
  Stream<List<DailyStudy>> watchDailyStudy({required int days, required DateTime today}) {
    final from = DateTime(today.year, today.month, today.day - (days - 1));
    final query = _db.select(_db.studySessions)
      ..where((s) => s.endedAt.isNotNull() & s.startedAt.isBiggerOrEqualValue(from));

    return query.watch().map((rows) {
      final seconds = <DateTime, int>{};
      for (final r in rows) {
        final end = r.endedAt;
        if (end == null) continue;
        final day = DateTime(r.startedAt.year, r.startedAt.month, r.startedAt.day);
        seconds[day] = (seconds[day] ?? 0) + end.difference(r.startedAt).inSeconds;
      }
      return [
        for (var i = 0; i < days; i++)
          () {
            final day = DateTime(from.year, from.month, from.day + i);
            return DailyStudy(day: day, duration: Duration(seconds: seconds[day] ?? 0));
          }(),
      ];
    });
  }
}
