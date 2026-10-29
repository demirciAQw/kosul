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

/// Okuma kaydından asıl sorunun parçaları: paragraf/verilen metin (şekil
/// açıklamalarıyla), soru cümlesi, şıklar, öncüller ve maddeler.
({String passage, String prompt, String options, String given}) questionPartsOf(OcrRecord r) {
  final figures = [
    for (final f in r.figures)
      if (f['description'] is String) '${f['description']}',
  ].join(' ');
  final questions = r.structure?['questions'];
  final primary = r.structure?['primary'];
  if (questions is List && primary is int && primary >= 0 && primary < questions.length && questions[primary] is Map) {
    final q = questions[primary] as Map;
    String joined(Object? v) => v is List ? v.map((e) => '$e').join(' ') : '';
    final statements = q['statements'] is List
        ? [
            for (final st in q['statements'] as List)
              if (st is Map) '${st['text']}',
          ]
        : const <String>[];
    final options = q['options'] is Map ? (q['options'] as Map).values.map((v) => '$v').join(' ') : '';
    return (
      passage: '${joined(q['stem'])} $figures'.trim(),
      prompt: '${q['prompt'] ?? ''}',
      options: options,
      given: [...statements, joined(q['bullets'])].join(' ').trim(),
    );
  }
  return (
    passage: '${r.parsed?.stem ?? r.fullText} $figures'.trim(),
    prompt: '',
    options: r.parsed?.options.values.join(' ') ?? '',
    given: '',
  );
}

/// Fotoğrafı okunmuş her sorunun benzerlik özellikleri ve dizini.
final similarIndexProvider = Provider<({Map<String, SimilarProfile> profiles, SimilarIndex index})>((ref) {
  final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
  final records = ref.watch(ocrRecordsProvider).value ?? const <String, OcrRecord>{};
  final tags = ref.watch(autoTagsProvider);
  final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
  final profiles = <String, SimilarProfile>{};
  for (final c in cards) {
    final r = records[OcrJob.questionId(c.id)];
    if (r == null || !r.ok || r.imagePath != c.questionImage || r.searchable.trim().isEmpty) continue;
    final main = mainQuestionOf(r);
    final parts = questionPartsOf(r);
    final t = tags[c.id];
    // Konu adı üzerinden: MEB düğümü, elle yazılan ve otomatik konu aynı ölçüde kıyaslanır.
    final topicTitle = (c.mebNodeId == null ? null : curriculum[c.mebNodeId]?.title) ??
        ((c.topicText ?? '').trim().isEmpty ? null : c.topicText) ??
        t?.topic;
    final options = r.parsed?.options ?? const <String, String>{};
    final numeric = options.values.where((v) => _numericOption.hasMatch(v.trim())).length;
    profiles[c.id] = SimilarProfile(
      text: r.searchable,
      passage: parts.passage,
      prompt: parts.prompt.isEmpty ? main.prompt : parts.prompt,
      options: parts.options,
      given: parts.given,
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
  return (profiles: profiles, index: SimilarIndex.build(profiles));
});

/// Bir sorunun benzerleri: yanlış/boş ve doğru yapılanlar ayrı.
final similarQuestionsProvider = Provider.family<SimilarResult, String>((ref, id) {
  final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
  final target = cards.where((c) => c.id == id).firstOrNull;
  if (target == null) return const SimilarResult(mistakes: [], correct: []);
  final data = ref.watch(similarIndexProvider);
  return findSimilar(target, cards, data.profiles, data.index);
});

/// Eşleme: benzerliği yüksek sorular aynı grupta (kart → grup no).
final similarGroupsProvider = Provider<Map<String, int>>((ref) {
  final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
  final data = ref.watch(similarIndexProvider);
  return similarGroups(cards, data.profiles, data.index);
});
