import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/media/media_storage.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/notes/data/note_repository_impl.dart';
import 'package:kocum/features/notes/domain/notes.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'n${_n++}';
}

/// Dosyaları gerçekten kopyalamayan medya: içe alınan yolu "notes/<ad>" yapar.
class _FakeMedia implements MediaStorage {
  final deleted = <String>[];

  @override
  Future<String> importFile(String sourcePath, {required String bucket}) async =>
      '$bucket/${sourcePath.split('/').last}';

  @override
  Future<void> delete(String relativePath) async => deleted.add(relativePath);

  @override
  Future<void> discardTemp(String? absolutePath) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('not tarih ve saatle derse kaydedilir, düzenlenince oluşturma zamanı korunur', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftNoteRepository(db);
    var now = DateTime(2026, 10, 18, 14, 5);
    final save = SaveNote(repo, _SeqIds(), () => now, _FakeMedia());

    final note = await save(subject: 'TYT Matematik', body: '  Zincir kuralı: içerinin türevi  ');
    expect(note.createdAt, DateTime(2026, 10, 18, 14, 5));
    expect(note.body, 'Zincir kuralı: içerinin türevi');
    expect(note.heading, 'Zincir kuralı: içerinin türevi');

    now = DateTime(2026, 10, 18, 15, 0);
    final edited = await save(existing: note, subject: 'TYT Matematik', body: 'Güncel', title: 'Türev');
    expect(edited.createdAt, note.createdAt);
    expect(edited.updatedAt, now);
    expect(edited.wasEdited, isTrue);

    final all = await repo.watchAll().first;
    expect(all.single.title, 'Türev');
    expect(all.single.subject, 'TYT Matematik');
  });

  test('tarih ve saat elle değiştirilebilir, düzenlemede seçilen tarih kalır', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftNoteRepository(db);
    final save = SaveNote(repo, _SeqIds(), () => DateTime(2026, 10, 18, 14, 5), _FakeMedia());

    final picked = DateTime(2026, 10, 12, 21, 30);
    final note = await save(subject: 'TYT Fizik', body: 'Dün akşamki ders notu', at: picked);
    expect(note.createdAt, picked);

    final edited = await save(existing: note, subject: 'TYT Fizik', body: 'Düzeltildi');
    expect(edited.createdAt, picked, reason: 'tarih verilmezse eski tarih korunur');
    expect((await repo.findById(note.id))!.createdAt, picked);
  });

  test('ders ve metin zorunlu', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final save = SaveNote(DriftNoteRepository(db), _SeqIds(), () => DateTime(2026, 10, 18), _FakeMedia());
    expect(() => save(subject: null, body: 'x'), throwsA(isA<NoteException>()));
    expect(() => save(subject: 'TYT Fizik', body: '   '), throwsA(isA<NoteException>()));
  });

  test('fotoğraflı not: sayfalar sırayla kaydedilir, çıkarılan fotoğraf silinir', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftNoteRepository(db);
    final media = _FakeMedia();
    final save = SaveNote(repo, _SeqIds(), () => DateTime(2026, 10, 19, 20), media);

    // Yazısız, yalnızca fotoğraflı not da olur.
    final note = await save(
      subject: 'AYT Kimya',
      body: '',
      photos: const [NotePhotoDraft.fresh('/tmp/s1.webp'), NotePhotoDraft.fresh('/tmp/s2.webp')],
    );
    expect(note.photos, ['notes/s1.webp', 'notes/s2.webp']);
    expect(note.heading, '2 sayfalık defter notu');
    expect((await repo.findById(note.id))!.photos, ['notes/s1.webp', 'notes/s2.webp']);

    // Düzenleme: ilk sayfa çıkarıldı, yeni sayfa eklendi.
    final edited = await save(
      existing: note,
      subject: 'AYT Kimya',
      body: 'Denge sabiti',
      photos: const [NotePhotoDraft.stored('notes/s2.webp'), NotePhotoDraft.fresh('/tmp/s3.webp')],
    );
    expect(edited.photos, ['notes/s2.webp', 'notes/s3.webp']);
    expect(media.deleted, ['notes/s1.webp']);

    await DeleteNote(repo, media)(edited);
    expect(await repo.findById(note.id), isNull);
    expect(media.deleted, containsAll(['notes/s2.webp', 'notes/s3.webp']));
  });

  test('yazı da fotoğraf da yoksa kaydedilmez', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final save = SaveNote(DriftNoteRepository(db), _SeqIds(), () => DateTime(2026), _FakeMedia());
    expect(() => save(subject: 'TYT Fizik', body: ''), throwsA(isA<NoteException>()));
  });
}
