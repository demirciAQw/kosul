import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/planning.dart';

class DriftPlanRepository implements PlanRepository {
  DriftPlanRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<StudyPlan>> watchPlans() {
    final plans = _db.studyPlans;
    final tasks = _db.planTasks;
    // Tek LEFT JOIN: plan ya da görev değişince akış yeniden yayınlanır.
    final query = _db.select(plans).join([leftOuterJoin(tasks, tasks.planId.equalsExp(plans.id))])
      ..orderBy([
        OrderingTerm.desc(plans.startsOn),
        OrderingTerm.asc(plans.id),
        OrderingTerm.asc(tasks.sortOrder),
      ]);

    return query.watch().map((rows) {
      final planRows = <String, StudyPlanRow>{};
      final taskRows = <String, List<PlanTaskRow>>{};
      for (final row in rows) {
        final plan = row.readTable(plans);
        planRows[plan.id] = plan;
        final task = row.readTableOrNull(tasks);
        if (task != null) (taskRows[plan.id] ??= []).add(task);
      }
      return [
        for (final p in planRows.values)
          StudyPlan(
            id: p.id,
            title: p.title,
            startsOn: p.startsOn,
            endsOn: p.endsOn,
            createdAt: p.createdAt,
            completedAt: p.completedAt,
            tasks: [
              for (final t in taskRows[p.id] ?? const <PlanTaskRow>[])
                PlanTask(
                  id: t.id,
                  planId: t.planId,
                  title: t.title,
                  bookId: t.bookId,
                  contentNodeId: t.contentNodeId,
                  targetQuestions: t.targetQuestions,
                  isDone: t.isDone,
                ),
            ],
          ),
      ];
    });
  }

  PlanTasksCompanion _task(String planId, PlanTask t, int sortOrder) => PlanTasksCompanion.insert(
        id: t.id,
        planId: planId,
        title: t.title,
        sortOrder: sortOrder,
        bookId: Value(t.bookId),
        contentNodeId: Value(t.contentNodeId),
        targetQuestions: Value(t.targetQuestions),
        isDone: Value(t.isDone),
      );

  @override
  Future<void> create(StudyPlan plan) => _db.transaction(() async {
        await _db.into(_db.studyPlans).insert(StudyPlansCompanion.insert(
              id: plan.id,
              title: plan.title,
              startsOn: plan.startsOn,
              endsOn: plan.endsOn,
              createdAt: plan.createdAt,
              completedAt: Value(plan.completedAt),
            ));
        if (plan.tasks.isEmpty) return;
        await _db.batch((b) => b.insertAll(_db.planTasks, [
              for (var i = 0; i < plan.tasks.length; i++) _task(plan.id, plan.tasks[i], i),
            ]));
      });

  @override
  Future<void> addTasks(String planId, List<PlanTask> tasks) => _db.transaction(() async {
        final maxOrder = _db.planTasks.sortOrder.max();
        final row = await (_db.selectOnly(_db.planTasks)
              ..addColumns([maxOrder])
              ..where(_db.planTasks.planId.equals(planId)))
            .getSingle();
        final start = (row.read(maxOrder) ?? -1) + 1;
        await _db.batch((b) => b.insertAll(_db.planTasks, [
              for (var i = 0; i < tasks.length; i++) _task(planId, tasks[i], start + i),
            ]));
      });

  @override
  Future<void> setTaskDone(String taskId, bool done) =>
      (_db.update(_db.planTasks)..where((t) => t.id.equals(taskId)))
          .write(PlanTasksCompanion(isDone: Value(done)));

  @override
  Future<void> deleteTask(String taskId) =>
      (_db.delete(_db.planTasks)..where((t) => t.id.equals(taskId))).go();

  @override
  Future<void> setCompleted(String planId, DateTime? completedAt) =>
      (_db.update(_db.studyPlans)..where((p) => p.id.equals(planId)))
          .write(StudyPlansCompanion(completedAt: Value(completedAt)));

  @override
  Future<void> delete(String planId) =>
      (_db.delete(_db.studyPlans)..where((p) => p.id.equals(planId))).go();
}
