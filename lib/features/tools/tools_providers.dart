import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../anlik/anlik_providers.dart';
import '../anlik/domain/anlik_esitleme.dart';
import '../library/library_providers.dart';
import '../mock_exam/mock_exam_providers.dart';
import '../notes/notes_providers.dart';
import '../ocr/ocr_providers.dart';
import '../planning/planning_providers.dart';
import '../question_bank/question_bank_providers.dart';
import '../study_session/study_session_providers.dart';
import 'data/export_log_repository.dart';
import 'data/full_export.dart';
import 'domain/export_log.dart';

final exportLogRepositoryProvider = Provider((ref) => ExportLogRepository(ref.watch(appDatabaseProvider)));

/// Claude paket geçmişi (Araçlar ekranı yeniler).
final claudeExportLogProvider =
    FutureProvider.autoDispose<List<ClaudeBatch>>((ref) => ref.watch(exportLogRepositoryProvider).load());

/// Araçlar'dan "Yanlış defteri PDF" istendi: Defter açılınca paylaş paneli PDF'le açılır.
class NotebookPdfRequest extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final notebookPdfRequestProvider = NotifierProvider<NotebookPdfRequest, bool>(NotebookPdfRequest.new);

/// Tüm veri yedeği (kocum.backup JSON'u, fotoğrafsız). Araçlar'daki "tüm veri"
/// dışa aktarması ve bilgisayarla eşitleme aynı veriyi kullanır.
final fullDataCollectorProvider = Provider<Future<Map<String, dynamic>> Function()>((ref) => () async {
      final ocr = await ref.read(ocrRecordsProvider.future);
      final anlik = ref.read(anlikDeposuProvider);
      return fullDataJson(
        now: ref.read(clockProvider)(),
        cards: await ref.read(allQuestionsProvider.future),
        books: await ref.read(libraryProvider.future),
        results: await ref.read(testResultsProvider.future),
        sessions: await ref.read(studySessionRepositoryProvider).watchHistory(limit: 100000).first,
        exams: await ref.read(mockExamsProvider.future),
        plans: await ref.read(plansProvider.future),
        notes: await ref.read(notesProvider.future),
        ocr: [for (final r in ocr.values) r.toDatasetJson()],
        anlik: {
          'anliklar': [for (final a in await anlik.anliklar()) anlikJson(a)],
          'etiketler': [for (final e in await anlik.etiketler()) etiketJson(e)],
          'baglar': [for (final b in await anlik.baglar()) bagJson(b)],
        },
      );
    });
