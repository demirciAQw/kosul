import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/turkish_text.dart';
import '../curriculum/curriculum_providers.dart';
import '../curriculum/domain/curriculum.dart';
import '../question_bank/domain/question_card.dart';
import '../question_bank/question_bank_providers.dart';
import 'domain/auto_tags.dart';
import 'domain/ocr.dart';
import 'ocr_providers.dart';

/// Konu sözlüğü (assets/meb/konu_sozlugu.json).
final topicLexiconProvider = FutureProvider<TopicLexicon>((ref) async =>
    TopicLexicon.fromJson(jsonDecode(await rootBundle.loadString('assets/meb/konu_sozlugu.json')) as Map<String, dynamic>));

/// Kart → otomatik etiketler (fotoğrafı okunmuş sorular).
final autoTagsProvider = Provider<Map<String, AutoTags>>((ref) {
  final lexicon = ref.watch(topicLexiconProvider).value;
  final cards = ref.watch(allQuestionsProvider).value;
  final records = ref.watch(ocrRecordsProvider).value;
  if (lexicon == null || cards == null || records == null) return const {};
  final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
  return autoTagsFor(lexicon, cards, records, curriculum);
});

Map<String, AutoTags> autoTagsFor(
  TopicLexicon lexicon,
  List<QuestionCard> cards,
  Map<String, OcrRecord> records,
  List<CurriculumNode> curriculum,
) {
  final out = <String, AutoTags>{};
  for (final c in cards) {
    final r = records[OcrJob.questionId(c.id)];
    if (r == null || !r.ok || r.imagePath != c.questionImage) continue;
    final titles = {
      for (final n in curriculum)
        if (normalizeTr(n.subjectLabel).contains(normalizeTr(c.subject)) ||
            normalizeTr(c.subject).contains(normalizeTr(n.subjectLabel)))
          foldForTags(n.title): n.id,
    };
    final tags = autoTag(lexicon: lexicon, subject: c.subject, record: r, curriculumTitles: titles);
    if (!tags.isEmpty) out[c.id] = tags;
  }
  return out;
}

/// Gruplama için konusu olmayan kartların konusu: elle yazılan, yoksa otomatik.
Map<String, String> fallbackTopicsFor(List<QuestionCard> cards, Map<String, AutoTags> tags) => {
      for (final c in cards)
        if (c.mebNodeId == null)
          if (c.topicText != null && c.topicText!.trim().isNotEmpty)
            c.id: titleCaseTr(c.topicText!.trim())
          else if (tags[c.id]?.topic != null)
            c.id: '${tags[c.id]!.topic} (otomatik)',
    };
