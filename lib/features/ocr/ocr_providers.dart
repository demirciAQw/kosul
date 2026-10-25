import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../notes/domain/notes.dart';
import '../question_bank/data/search_store.dart';
import '../question_bank/domain/question_card.dart';
import 'data/mlkit_ocr_engine.dart';
import 'data/ocr_queue.dart';
import 'data/ocr_repository_impl.dart';
import 'domain/ocr.dart';

final ocrRepositoryProvider = Provider<OcrRepository>((ref) => DriftOcrRepository(ref.watch(appDatabaseProvider)));

/// Tüm okuma kayıtları (kimlik → kayıt).
final ocrRecordsProvider = StreamProvider<Map<String, OcrRecord>>((ref) => ref.watch(ocrRepositoryProvider).watchAll());

/// Okuma sonuçları veri seti (JSONL).
final ocrLogProvider = Provider<SearchLog>((ref) => SearchLog(name: 'ocr_kayitlari.jsonl'));

final ocrEngineProvider = Provider<OcrEngine>((ref) => MlKitOcrEngine());

final ocrQueueProvider = Provider<OcrQueue>((ref) {
  final media = ref.watch(mediaStorageProvider);
  return OcrQueue(
    engine: ref.watch(ocrEngineProvider),
    repository: ref.watch(ocrRepositoryProvider),
    resolve: (rel) => media.resolve(rel).path,
    // Veri seti: her sonuç telefonda kocum_veri/ocr_kayitlari.jsonl dosyasına.
    onRecord: (r) => unawaited(ref.read(ocrLogProvider).append(r.toDatasetJson())),
  );
});

/// Okunması istenen fotoğraflar: soru (en yeni önce), not sayfaları, çözümler.
List<OcrJob> ocrJobsFor(List<QuestionCard> cards, List<StudyNote> notes) => [
      for (final c in cards)
        if (c.questionImage != null)
          OcrJob(id: OcrJob.questionId(c.id), ownerType: 'question', ownerId: c.id, imagePath: c.questionImage!),
      for (final n in notes)
        for (final (i, p) in n.photos.indexed)
          OcrJob(id: OcrJob.noteId(n.id, i), ownerType: 'note', ownerId: n.id, imagePath: p),
      for (final c in cards)
        if (c.solutionImage != null)
          OcrJob(id: OcrJob.solutionId(c.id), ownerType: 'solution', ownerId: c.id, imagePath: c.solutionImage!),
    ];

/// Kart → fotoğraftan okunan soru metni (yalnızca başarılı okumalar).
Map<String, String> ocrQuestionTexts(Map<String, OcrRecord> records) => {
      for (final r in records.values)
        if (r.ownerType == 'question' && r.ok && r.searchable.isNotEmpty) r.ownerId: r.searchable,
    };
