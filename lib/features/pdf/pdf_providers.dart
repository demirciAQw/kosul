import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/pdf_renderer.dart';
import 'data/pdf_repository.dart';
import 'domain/pdf_models.dart';

final pdfRepositoryProvider = Provider((ref) => PdfRepository(ref.watch(appDatabaseProvider)));
final pdfRendererProvider = Provider((ref) => PdfRenderer(ref.watch(mediaStorageProvider)));

final pdfBooksProvider = StreamProvider<List<PdfBook>>((ref) => ref.watch(pdfRepositoryProvider).watchBooks());

/// Kart → PDF'teki yeri (PDF'ten seçilmiş sorular).
final pdfRefsProvider =
    StreamProvider<Map<String, PdfQuestionRef>>((ref) => ref.watch(pdfRepositoryProvider).watchRefs());

/// Kart → kayıtlı kalem çözümü sayısı.
final cardLayerCountsProvider =
    StreamProvider<Map<String, int>>((ref) => ref.watch(pdfRepositoryProvider).watchCardLayerCounts());

/// Bir kartın kayıtlı çözüm katmanları.
final cardLayersProvider = StreamProvider.family<List<InkLayer>, String>(
    (ref, cardId) => ref.watch(pdfRepositoryProvider).watchLayers('card', cardId));

/// Kitaplıktaki PDF'ler kimliğe göre.
final pdfBookByIdProvider = Provider.family<PdfBook?, String>((ref, id) {
  final books = ref.watch(pdfBooksProvider).value ?? const <PdfBook>[];
  return books.where((b) => b.id == id).firstOrNull;
});
