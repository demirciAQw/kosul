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
  MockExams,
  MockExamSections,
  TestResults,
  StudyNotes,
  AppMeta,
])
class AppDatabase extends _$AppDatabase {
  /// Testlerde: `AppDatabase(NativeDatabase.memory())`
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'kocum'));

  /// v2: fotoğrafsız/çözümsüz kartlar, soru numarası, kitapsız oturum, denemeler.
  /// v3: testlerin kesin soru sayısı, planların tamamlanma tarihi.
  /// v4: test ilerlemesi (çözüldü/çözülmedi), "Diğer" nedeni için açıklama.
  /// v5: kartlarda serbest konu/kazanım adı (karneden içe aktarma).
  /// v6: eski sürümlerden kalan yetim tekrar kayıtlarını temizler.
  /// v7: ders notları (study_notes).
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Aynı anda yalnızca BİR koşan oturum olabilir: kısmi benzersiz indeks.
          await customStatement(
            'CREATE UNIQUE INDEX ux_single_running_session '
            "ON study_sessions(status) WHERE status = 'running'",
          );
          await _createV2Indexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(sessionItems, sessionItems.subject);
            await m.addColumn(sessionItems, sessionItems.activity);
            await m.createTable(mockExams);
            await m.createTable(mockExamSections);
            // Tablo yeniden kurulur: soru fotoğrafı isteğe bağlı olur, "çözüm
            // zorunlu" CHECK kuralı kalkar, yeni sütunlar eklenir. Drift eski
            // indeksleri kendisi yeniden oluşturur. (Bu aşamada foreign_keys
            // kapalıdır; tekrar durumları silinmez.)
            await m.alterTable(TableMigration(questionCards, newColumns: [
              questionCards.questionNo,
              questionCards.testLabel,
              questionCards.sessionItemId,
              questionCards.mockExamId,
              questionCards.reasonNote,
              questionCards.topicText,
            ]));
            await _createV2Indexes();
          }
          if (from < 3) {
            await m.addColumn(contentNodes, contentNodes.questionCount);
            await m.addColumn(studyPlans, studyPlans.completedAt);
          }
          if (from < 4) {
            await m.createTable(testResults);
            // v2 geçişindeki alterTable güncel tanımı kurduğu için sütun zaten
            // var olabilir; yalnızca eksikse ekle.
            final cols = await customSelect('PRAGMA table_info(question_cards)').get();
            if (!cols.any((c) => c.read<String>('name') == 'reason_note')) {
              await m.addColumn(questionCards, questionCards.reasonNote);
            }
            await _createV2Indexes();
          }
          if (from < 7) {
            await m.createTable(studyNotes);
          }
          if (from < 6) {
            await customStatement(
              'DELETE FROM review_states WHERE card_id NOT IN (SELECT id FROM question_cards)',
            );
          }
          if (from < 5) {
            final cols = await customSelect('PRAGMA table_info(question_cards)').get();
            if (!cols.any((c) => c.read<String>('name') == 'topic_text')) {
              await m.addColumn(questionCards, questionCards.topicText);
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createV2Indexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS ix_cards_session_item ON question_cards(session_item_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS ix_cards_mock_exam ON question_cards(mock_exam_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS ix_cards_session ON question_cards(session_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS ix_mock_sections_exam ON mock_exam_sections(exam_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS ix_cards_content_node ON question_cards(content_node_id)');
  }
}
