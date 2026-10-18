import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/notes.dart';

class DriftNoteRepository implements NoteRepository {
  DriftNoteRepository(this._db);
  final AppDatabase _db;

  StudyNote _toEntity(StudyNoteRow r) => StudyNote(
        id: r.id,
        subject: r.subject,
        title: r.title,
        body: r.body,
        isPinned: r.isPinned,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  @override
  Stream<List<StudyNote>> watchAll() {
    final q = _db.select(_db.studyNotes)
      ..orderBy([(n) => OrderingTerm.desc(n.isPinned), (n) => OrderingTerm.desc(n.createdAt)]);
    return q.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<StudyNote?> findById(String id) async {
    final row = await (_db.select(_db.studyNotes)..where((n) => n.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> save(StudyNote note) => _db.into(_db.studyNotes).insertOnConflictUpdate(StudyNotesCompanion.insert(
        id: note.id,
        subject: note.subject,
        title: Value(note.title),
        body: note.body,
        isPinned: Value(note.isPinned),
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      ));

  @override
  Future<void> setPinned(String id, bool pinned) =>
      (_db.update(_db.studyNotes)..where((n) => n.id.equals(id))).write(StudyNotesCompanion(isPinned: Value(pinned)));

  @override
  Future<void> delete(String id) => (_db.delete(_db.studyNotes)..where((n) => n.id.equals(id))).go();
}
