import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../curriculum/curriculum_providers.dart';
import 'data/library_data.dart';
import 'data/test_progress_repository_impl.dart';
import 'domain/book_template_usecases.dart';
import 'domain/library.dart';
import 'domain/progress.dart';

final libraryRepositoryProvider =
    Provider<LibraryRepository>((ref) => DriftLibraryRepository(ref.watch(appDatabaseProvider)));

final bookTemplateCodecProvider = Provider<BookTemplateCodec>((ref) => JsonBookTemplateCodec(
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
    ));

final templateFileGatewayProvider = Provider((ref) => const TemplateFileGateway());

final importBookTemplateProvider = Provider((ref) => ImportBookTemplate(
      codec: ref.watch(bookTemplateCodecProvider),
      curriculum: ref.watch(curriculumRepositoryProvider),
      library: ref.watch(libraryRepositoryProvider),
    ));

final exportBookTemplateProvider = Provider((ref) => ExportBookTemplate(
      codec: ref.watch(bookTemplateCodecProvider),
      library: ref.watch(libraryRepositoryProvider),
    ));

final libraryProvider =
    StreamProvider<List<Book>>((ref) => ref.watch(libraryRepositoryProvider).watchLibrary());

// ───────────────────────── Kitap ilerlemesi ─────────────────────────

final testProgressRepositoryProvider =
    Provider<TestProgressRepository>((ref) => DriftTestProgressRepository(ref.watch(appDatabaseProvider)));

/// Düğüm kimliği → test sonucu (tüm kitaplar).
final testResultsProvider =
    StreamProvider<Map<String, TestResult>>((ref) => ref.watch(testProgressRepositoryProvider).watchAll());

/// Kitaplar sekmesi: her kitabın ne kadarı bitti, ne kadarı duruyor.
final bookProgressProvider = Provider<AsyncValue<List<BookProgress>>>((ref) {
  final books = ref.watch(libraryProvider);
  final results = ref.watch(testResultsProvider).value ?? const <String, TestResult>{};
  return books.whenData((list) => [for (final b in list) bookProgress(b, results)]);
});

final bookByIdProvider = Provider.family<Book?, String>((ref, id) {
  final books = ref.watch(libraryProvider).value ?? const <Book>[];
  return books.where((b) => b.id == id).firstOrNull;
});
