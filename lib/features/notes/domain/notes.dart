import '../../../core/utils/id_generator.dart';

/// Bir derse ait serbest not. Tarih ve saat yazıldığı anda kendiliğinden alınır.
class StudyNote {
  const StudyNote({
    required this.id,
    required this.subject,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.isPinned = false,
  });

  final String id;
  final String subject; // "TYT Matematik"
  final String? title;
  final String body;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get wasEdited => updatedAt.difference(createdAt).inMinutes >= 1;

  /// Başlık yoksa ilk satır.
  String get heading {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final first = body.trim().split('\n').first.trim();
    return first.length > 60 ? '${first.substring(0, 60)}…' : first;
  }
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
  Future<void> save(StudyNote note);
  Future<void> setPinned(String id, bool pinned);
  Future<void> delete(String id);
}

/// Yeni not ya da düzenleme. Ders zorunlu; metin boş olamaz.
/// Not tarihi verilmezse yeni notta "şimdi", düzenlemede eski tarih kalır.
class SaveNote {
  SaveNote(this._repository, this._ids, this._clock);

  final NoteRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  Future<StudyNote> call({
    StudyNote? existing,
    required String? subject,
    required String body,
    String? title,
    DateTime? at,
  }) async {
    final s = subject?.trim();
    if (s == null || s.isEmpty) throw const NoteException('Notun dersini seç.');
    final b = body.trim();
    if (b.isEmpty) throw const NoteException('Not boş olamaz.');
    final t = title?.trim();
    final now = _clock();
    final note = StudyNote(
      id: existing?.id ?? _ids.next(),
      subject: s,
      title: (t == null || t.isEmpty) ? null : t,
      body: b,
      isPinned: existing?.isPinned ?? false,
      createdAt: at ?? existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _repository.save(note);
    return note;
  }
}
