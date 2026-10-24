import 'dart:math' as math;

import '../../curriculum/domain/curriculum.dart';
import 'question_card.dart';
import 'recurrence.dart';

/// Zorluk kümesi: kartlardaki 1–10 zorluk puanına göre.
enum DifficultyBand {
  any('Hepsi'),
  easy('Kolay'),
  medium('Orta'),
  hard('Zor'),
  mixed('Karma');

  const DifficultyBand(this.label);
  final String label;

  static DifficultyBand of(int difficulty) =>
      difficulty <= 3 ? DifficultyBand.easy : (difficulty <= 6 ? DifficultyBand.medium : DifficultyBand.hard);
}

class PracticeTestOptions {
  const PracticeTestOptions({
    this.count = 20,
    this.subject,
    this.topicKey,
    this.band = DifficultyBand.any,
    this.reason,
    this.coverWeakTopics = false,
    this.photosOnly = true,
  });

  final int count;
  final String? subject;

  /// [topicOfCard] anahtarı (tek konu); null = hepsi.
  final String? topicKey;
  final DifficultyBand band;

  /// Yalnızca bu nedenle yapılan hatalar (ör. dikkatsizlik).
  final MistakeReason? reason;

  /// En az 2 hata olan her konudan en az bir soru.
  final bool coverWeakTopics;

  /// Yalnızca fotoğraflı sorular (PDF'te soru görünsün).
  final bool photosOnly;
}

class PracticeTest {
  const PracticeTest({required this.cards, required this.available, required this.notes});
  final List<QuestionCard> cards;

  /// Süzgeçten geçen toplam soru (seçim bundan yapıldı).
  final int available;

  /// Kullanıcıya açıklama: "Zor soru az olduğu için 3 orta soru eklendi" gibi.
  final List<String> notes;
}

/// Yanlış ve boşlardan test kurar. [seed] aynıysa aynı test çıkar (önizleme
/// ile PDF aynı olsun).
PracticeTest buildPracticeTest(
  List<QuestionCard> cards,
  PracticeTestOptions o, {
  required Map<String, CurriculumNode> curriculum,
  int seed = 0,
}) {
  final rnd = math.Random(seed);
  final notes = <String>[];
  final pool = [
    for (final c in cards)
      if (c.status != QuestionStatus.correct &&
          (o.subject == null || c.subject == o.subject) &&
          (o.reason == null || c.reason == o.reason) &&
          (!o.photosOnly || c.questionImage != null) &&
          (o.topicKey == null || topicOfCard(c, curriculum)?.key == o.topicKey) &&
          (o.band == DifficultyBand.any ||
              o.band == DifficultyBand.mixed ||
              DifficultyBand.of(c.difficulty) == o.band))
        c,
  ]..shuffle(rnd);
  final count = math.min(o.count, pool.length);
  if (pool.length < o.count) notes.add('Süzgeçe uyan ${pool.length} soru var; test ${pool.length} soruluk oldu.');

  final picked = <QuestionCard>[];
  final used = <String>{};
  void take(QuestionCard c) {
    if (picked.length < count && used.add(c.id)) picked.add(c);
  }

  // Zayıf konuların hepsi: her birinden en az bir soru (en çok hata yapılan önce).
  if (o.coverWeakTopics) {
    final byTopic = <String, List<QuestionCard>>{};
    for (final c in pool) {
      final t = topicOfCard(c, curriculum);
      if (t != null) (byTopic[t.key] ??= []).add(c);
    }
    final weak = byTopic.entries.where((e) => e.value.length >= 2).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (weak.length > count) notes.add('${weak.length} zayıf konu var; ilk $count konu alındı.');
    for (final e in weak) {
      take(e.value.first);
    }
    // Kalan yer: zayıf konulardan, hata sayısıyla orantılı sırayla.
    var round = 1;
    while (picked.length < count && weak.any((e) => e.value.length > round)) {
      for (final e in weak) {
        if (e.value.length > round) take(e.value[round]);
      }
      round++;
    }
  }

  if (o.band == DifficultyBand.mixed && picked.length < count) {
    // Dengeli: kolay, orta, zor eşit pay; eksik kalan diğerlerinden.
    final groups = {
      for (final b in const [DifficultyBand.easy, DifficultyBand.medium, DifficultyBand.hard])
        b: [for (final c in pool) if (DifficultyBand.of(c.difficulty) == b && !used.contains(c.id)) c],
    };
    final remaining = count - picked.length;
    final share = remaining ~/ 3;
    var extra = remaining - share * 3;
    for (final b in groups.keys) {
      final want = share + (extra-- > 0 ? 1 : 0);
      final have = groups[b]!;
      if (have.length < want) notes.add('${b.label} soru az (${have.length}); eksik diğer zorluklardan tamamlandı.');
      for (final c in have.take(want)) {
        take(c);
      }
    }
  }

  for (final c in pool) {
    take(c); // kalan yer: rastgele sırayla
  }

  // Karma ve konu modunda kolaydan zora sıralı; diğerlerinde karışık kalır.
  if (o.band == DifficultyBand.mixed || o.coverWeakTopics) {
    picked.sort((a, b) => a.difficulty.compareTo(b.difficulty));
  }
  return PracticeTest(cards: picked, available: pool.length, notes: notes);
}
