import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Books,
  ContentNodes,
  CurriculumNodes,
  StudyPlans,
  PlanTasks,
  StudySessions,
  SessionItems,
  QuestionCards,
  ReviewStates,
  AppMeta,
])
class AppDatabase extends _$AppDatabase {
  /// Testlerde: `AppDatabase(NativeDatabase.memory())`
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'kocum'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Aynı anda yalnızca BİR koşan oturum olabilir: kısmi benzersiz indeks.
          await customStatement(
            'CREATE UNIQUE INDEX ux_single_running_session '
            "ON study_sessions(status) WHERE status = 'running'",
          );
        },
        onUpgrade: (m, from, to) async {
          // v2+: `dart run drift_dev make-migrations` ile adım adım, test edilmiş geçişler.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
