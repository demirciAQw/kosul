import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/export_log_repository.dart';
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
