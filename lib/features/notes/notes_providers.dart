import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/note_repository_impl.dart';
import 'domain/notes.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) => DriftNoteRepository(ref.watch(appDatabaseProvider)));

final saveNoteProvider = Provider(
    (ref) => SaveNote(ref.watch(noteRepositoryProvider), ref.watch(idGeneratorProvider), ref.watch(clockProvider)));

final notesProvider = StreamProvider<List<StudyNote>>((ref) => ref.watch(noteRepositoryProvider).watchAll());

/// Notlar sekmesinde seçili ders (null = tüm dersler).
class NoteSubjectFilter extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? subject) => state = subject;
}

final noteSubjectFilterProvider = NotifierProvider<NoteSubjectFilter, String?>(NoteSubjectFilter.new);
