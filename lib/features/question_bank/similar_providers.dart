import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/turkish_text.dart';
import '../curriculum/curriculum_providers.dart';
import '../curriculum/domain/curriculum.dart';
import '../dashboard/domain/stem_analysis.dart';
import '../ocr/auto_tag_providers.dart';
import '../ocr/domain/auto_tags.dart';
import '../ocr/domain/ocr.dart';
import '../ocr/ocr_providers.dart';
import 'domain/question_card.dart';
import 'domain/similar_questions.dart';
import 'question_bank_providers.dart';

final _numericOption = RegExp(r'^[\d\s.,/√°²³+\-−·]+$');

/// Fotoğrafı okunmuş her sorunun benzerlik özellikleri ve metin vektörleri.
final similarIndexProvider =
    Provider<({Map<String, SimilarProfile> profiles, Map<String, Map<String, double>> vectors})>((ref) {
  final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
  final records = ref.watch(ocrRecordsProvider).value ?? const <String, OcrRecord>{};
  final tags = ref.watch(autoTagsProvider);
  final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
  final profiles = <String, SimilarProfile>{};
  for (final c in cards) {
    final r = records[OcrJob.questionId(c.id)];
    if (r == null || !r.ok || r.imagePath != c.questionImage || r.searchable.trim().isEmpty) continue;
    final main = mainQuestionOf(r);
    final t = tags[c.id];
    // Konu adı üzerinden: MEB düğümü, elle yazılan ve otomatik konu aynı ölçüde kıyaslanır.
    final topicTitle = (c.mebNodeId == null ? null : curriculum[c.mebNodeId]?.title) ??
        ((c.topicText ?? '').trim().isEmpty ? null : c.topicText) ??
        t?.topic;
    final options = r.parsed?.options ?? const <String, String>{};
    final numeric = options.values.where((v) => _numericOption.hasMatch(v.trim())).length;
    profiles[c.id] = SimilarProfile(
      text: '${r.searchable} ${main.prompt}',
      topicKey: topicTitle == null ? null : normalizeTr(topicTitle),
      types: (t?.types ?? const <String>[]).toSet(),
      stemKind: main.prompt.trim().isEmpty ? null : classifyStem(main.prompt, hasStatements: main.hasStatements).name,
      figureKinds: {
        for (final f in r.figures)
          if (f['kind'] != 'annotation') '${f['kind']}',
      },
      numericOptions: options.isEmpty ? null : numeric * 2 >= options.length,
    );
  }
  return (profiles: profiles, vectors: tfidfVectors({for (final e in profiles.entries) e.key: e.value.text}));
});

/// Bir sorunun benzerleri: yanlış/boş ve doğru yapılanlar ayrı.
final similarQuestionsProvider = Provider.family<SimilarResult, String>((ref, id) {
  final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
  final target = cards.where((c) => c.id == id).firstOrNull;
  if (target == null) return const SimilarResult(mistakes: [], correct: []);
  final index = ref.watch(similarIndexProvider);
  return findSimilar(target, cards, index.profiles, index.vectors);
});
