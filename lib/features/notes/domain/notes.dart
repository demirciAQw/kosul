import '../../../core/media/media_storage.dart';
import '../../../core/utils/id_generator.dart';

/// Bir derse ait not: yazı, sayfa fotoğrafları ya da ikisi birden. Tarih ve
/// saat yazıldığı anda kendiliğinden alınır, istenirse değiştirilebilir.
class StudyNote {
  const StudyNote({
    required this.id,
    required this.subject,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.isPinned = false,
    this.photos = const [],
  });

  final String id;
  final String subject; // "TYT Matematik"
  final String? title;
  final String body;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sayfa fotoğrafları (medya köküne göre göreli yollar), sırayla.
  final List<String> photos;

  bool get wasEdited => updatedAt.difference(createdAt).inMinutes >= 1;
  bool get hasPhotos => photos.isNotEmpty;

  /// Başlık yoksa ilk satır; o da yoksa fotoğraf sayısı.
  String get heading {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final first = body.trim().split('\n').first.trim();
    if (first.isEmpty) return hasPhotos ? '${photos.length} sayfalık defter notu' : '';
    return first.length > 60 ? '${first.substring(0, 60)}…' : first;
  }
}

/// Editördeki bir fotoğraf: ya kayıtlı (göreli yol) ya da yeni çekilmiş (geçici yol).
class NotePhotoDraft {
  const NotePhotoDraft.stored(String this.stored) : temp = null;
  const NotePhotoDraft.fresh(String this.temp) : stored = null;

  final String? stored;
  final String? temp;
}

class NoteException implements Exception {
  const NoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class NoteRepository {
  /// Sabitlenenler başta, sonra en yeni.
  Stream<List<StudyNote>> watchAll();
  Future<StudyNote?> findById(String id);

  /// Notu ve fotoğraf listesini (sırasıyla) atomik olarak yazar.
  Future<void> save(StudyNote note);
  Future<void> setPinned(String id, bool pinned);
  Future<void> delete(String id);
}

/// Yeni not ya da düzenleme. Ders zorunlu; yazı ya da en az bir fotoğraf olmalı.
/// Yeni fotoğraflar kalıcı depoya alınır; çıkarılan eski fotoğraflar kayıttan
/// sonra silinir. Hata olursa yeni kopyalanan dosyalar geri alınır.
class SaveNote {
  SaveNote(this._repository, this._ids, this._clock, this._media);

  final NoteRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;
  final MediaStorage _media;

  Future<StudyNote> call({
    StudyNote? existing,
    required String? subject,
    required String body,
    String? title,
    DateTime? at,
    List<NotePhotoDraft> photos = const [],
  }) async {
    final s = subject?.trim();
    if (s == null || s.isEmpty) throw const NoteException('Notun dersini seç.');
    final b = body.trim();
    if (b.isEmpty && photos.isEmpty) throw const NoteException('Bir şeyler yaz ya da sayfa fotoğrafı ekle.');
    final t = title?.trim();
    final now = _clock();

    final imported = <String>[];
    final finalPhotos = <String>[];
    final StudyNote note;
    try {
      for (final p in photos) {
        final stored = p.stored;
        if (stored != null) {
          finalPhotos.add(stored);
        } else {
          final rel = await _media.importFile(p.temp!, bucket: 'notes');
          imported.add(rel);
          finalPhotos.add(rel);
        }
      }
      note = StudyNote(
        id: existing?.id ?? _ids.next(),
        subject: s,
        title: (t == null || t.isEmpty) ? null : t,
        body: b,
        isPinned: existing?.isPinned ?? false,
        // Tarih ve saat kendiliğinden alınır; kullanıcı isterse [at] ile değiştirir.
        createdAt: at ?? existing?.createdAt ?? now,
        updatedAt: now,
        photos: finalPhotos,
      );
      await _repository.save(note);
    } catch (_) {
      for (final rel in imported) {
        await _media.delete(rel);
      }
      rethrow;
    }
    for (final old in existing?.photos ?? const <String>[]) {
      if (!finalPhotos.contains(old)) await _media.delete(old);
    }
    for (final p in photos) {
      await _media.discardTemp(p.temp);
    }
    return note;
  }
}

/// Notu ve sayfa fotoğraflarını siler.
class DeleteNote {
  DeleteNote(this._repository, this._media);
  final NoteRepository _repository;
  final MediaStorage _media;

  Future<void> call(StudyNote note) async {
    await _repository.delete(note.id);
    for (final p in note.photos) {
      await _media.delete(p);
    }
  }
}
