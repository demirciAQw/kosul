import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/enum_x.dart';
import '../domain/mock_exam.dart';

class DriftMockExamRepository implements MockExamRepository {
  DriftMockExamRepository(this._db);
  final AppDatabase _db;

  JoinedSelectStatement _joined() {
    final e = _db.mockExams;
    final s = _db.mockExamSections;
    return _db.select(e).join([leftOuterJoin(s, s.examId.equalsExp(e.id))])
      ..orderBy([
        OrderingTerm.desc(e.takenOn),
        OrderingTerm.desc(e.createdAt),
        OrderingTerm.asc(s.sortOrder),
      ]);
  }

  List<MockExam> _group(List<TypedResult> rows) {
    final exams = <String, MockExamRow>{};
    final sections = <String, List<MockExamSectionRow>>{};
    for (final row in rows) {
      final exam = row.readTable(_db.mockExams);
      exams[exam.id] = exam;
      final section = row.readTableOrNull(_db.mockExamSections);
      if (section != null) (sections[exam.id] ??= []).add(section);
    }
    return [for (final e in exams.values) _toEntity(e, sections[e.id] ?? const [])];
  }

  @override
  Stream<List<MockExam>> watchAll() => _joined().watch().map(_group);

  @override
  Stream<MockExam?> watchById(String id) {
    final q = _joined()..where(_db.mockExams.id.equals(id));
    return q.watch().map((rows) => _group(rows).firstOrNull);
  }

  @override
  Future<MockExam?> findById(String id) async {
    final q = _joined()..where(_db.mockExams.id.equals(id));
    return _group(await q.get()).firstOrNull;
  }

  @override
  Future<void> save(MockExam exam) => _db.transaction(() async {
        await _db.into(_db.mockExams).insertOnConflictUpdate(MockExamsCompanion.insert(
              id: exam.id,
              title: exam.title,
              kind: exam.kind.name,
              takenOn: exam.takenOn,
              createdAt: exam.createdAt,
              durationMinutes: Value(exam.durationMinutes),
              note: Value(exam.note),
            ));
        await (_db.delete(_db.mockExamSections)..where((s) => s.examId.equals(exam.id))).go();
        await _db.batch((b) => b.insertAll(_db.mockExamSections, [
              for (var i = 0; i < exam.sections.length; i++)
                MockExamSectionsCompanion.insert(
                  id: exam.sections[i].id,
                  examId: exam.id,
                  subject: exam.sections[i].subject,
                  questionCount: exam.sections[i].questionCount,
                  correct: exam.sections[i].correct,
                  wrong: exam.sections[i].wrong,
                  blank: exam.sections[i].blank,
                  sortOrder: i,
                ),
            ]));
      });

  @override
  Future<void> updateSection(String sectionId, {required int correct, required int wrong, required int blank}) =>
      (_db.update(_db.mockExamSections)..where((s) => s.id.equals(sectionId))).write(MockExamSectionsCompanion(
        correct: Value(correct),
        wrong: Value(wrong),
        blank: Value(blank),
      ));

  @override
  Future<void> delete(String id) => _db.transaction(() async {
        // Optikten gelmiş, üzerinde emek olmayan kartlar denemeyle birlikte gider.
        await (_db.delete(_db.questionCards)
              ..where((t) =>
                  t.mockExamId.equals(id) &
                  t.questionImage.isNull() &
                  t.solutionImage.isNull() &
                  t.solutionText.isNull() &
                  t.note.isNull()))
            .go();
        await (_db.delete(_db.mockExams)..where((e) => e.id.equals(id))).go();
      });

  static MockExam _toEntity(MockExamRow e, List<MockExamSectionRow> sections) => MockExam(
        id: e.id,
        title: e.title,
        kind: MockKind.values.byNameOr(e.kind, MockKind.tyt),
        takenOn: e.takenOn,
        createdAt: e.createdAt,
        durationMinutes: e.durationMinutes,
        note: e.note,
        sections: [
          for (final s in sections)
            MockSection(
              id: s.id,
              subject: s.subject,
              questionCount: s.questionCount,
              correct: s.correct,
              wrong: s.wrong,
              blank: s.blank,
            ),
        ],
      );
}
