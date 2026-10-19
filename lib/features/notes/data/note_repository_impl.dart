import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/notes.dart';

class DriftNoteRepository implements NoteRepository {
  DriftNoteRepository(this._db);
  final AppDatabase _db;

  StudyNote _toEntity(StudyNoteRow r, List<String> photos) => StudyNote(
        id: r.id,
        subject: r.subject,
        title: r.title,
        body: r.body,
        isPinned: r.isPinned,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        photos: photos,
      );

  JoinedSelectStatement _joined() {
    final n = _db.studyNotes;
    final p = _db.notePhotos;
    return _db.select(n).join([leftOuterJoin(p, p.noteId.equalsExp(n.id))])
      ..orderBy([OrderingTerm.desc(n.isPinned), OrderingTerm.desc(n.createdAt), OrderingTerm.asc(p.sortOrder)]);
  }

  List<StudyNote> _group(List<TypedResult> rows) {
    final notes = <String, StudyNoteRow>{};
    final photos = <String, List<String>>{};
    for (final row in rows) {
      final note = row.readTable(_db.studyNotes);
      notes[note.id] = note;
      final photo = row.readTableOrNull(_db.notePhotos);
      if (photo != null) (photos[note.id] ??= []).add(photo.path);
    }
    return [for (final n in notes.values) _toEntity(n, photos[n.id] ?? const [])];
  }

  @override
  Stream<List<StudyNote>> watchAll() => _joined().watch().map(_group);

  @override
  Future<StudyNote?> findById(String id) async {
    final q = _joined()..where(_db.studyNotes.id.equals(id));
    return _group(await q.get()).firstOrNull;
  }

  @override
  Future<void> save(StudyNote note) => _db.transaction(() async {
        await _db.into(_db.studyNotes).insertOnConflictUpdate(StudyNotesCompanion.insert(
              id: note.id,
              subject: note.subject,
              title: Value(note.title),
              body: note.body,
              isPinned: Value(note.isPinned),
              createdAt: note.createdAt,
              updatedAt: note.updatedAt,
            ));
        await (_db.delete(_db.notePhotos)..where((p) => p.noteId.equals(note.id))).go();
        if (note.photos.isEmpty) return;
        await _db.batch((b) => b.insertAll(_db.notePhotos, [
              for (var i = 0; i < note.photos.length; i++)
                NotePhotosCompanion.insert(
                  id: '${note.id}-p$i',
                  noteId: note.id,
                  path: note.photos[i],
                  sortOrder: i,
                ),
            ]));
      });

  @override
  Future<void> setPinned(String id, bool pinned) =>
      (_db.update(_db.studyNotes)..where((n) => n.id.equals(id))).write(StudyNotesCompanion(isPinned: Value(pinned)));

  @override
  Future<void> delete(String id) => (_db.delete(_db.studyNotes)..where((n) => n.id.equals(id))).go();
}
