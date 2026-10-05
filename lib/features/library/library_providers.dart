import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../curriculum/curriculum_providers.dart';
import 'data/library_data.dart';
import 'domain/book_template_usecases.dart';
import 'domain/library.dart';

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
