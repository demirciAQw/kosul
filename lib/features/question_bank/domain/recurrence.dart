import '../../../core/text/turkish_text.dart';
import '../../curriculum/domain/curriculum.dart';
import 'question_bank.dart';
import 'question_card.dart';

/// Bir sorunun "benzerleri": aynı konudaki yanlış ve boşlar, ve bunlardan
/// aynı nedenle yapılanlar. Tekrar ekranında sık tekrarlanan hatalar öne alınır.
class Recurrence {
  const Recurrence({
    required this.topic,
    required this.sameTopic,
    required this.sameTopicReason,
    this.reason,
  });

  final String topic;

  /// Aynı konudaki yanlış ve boşlar (bu soru dahil).
  final int sameTopic;

  /// Bunlardan bu sorunun nedeniyle aynı olanlar (bu soru dahil; neden yoksa 0).
  final int sameTopicReason;
  final MistakeReason? reason;

  /// Aynı konuda en az 3 hata ya da aynı konu ve aynı nedenle en az 2 hata.
  bool get isRecurring => sameTopic >= 3 || sameTopicReason >= 2;

  /// Sıralama ağırlığı: aynı nedenle tekrar, yalnızca konu tekrarından ağır basar.
  int get score => sameTopicReason * 2 + sameTopic;

  String get message {
    final base = '$topic konusunda $sameTopic hatan var';
    final r = reason;
    if (r == null || sameTopicReason < 2) return '$base.';
    return '$base, $sameTopicReason tanesi "${r.label}".';
  }
}

/// Kartın konu anahtarı ve adı: MEB konusu, yoksa karneden gelen kazanım.
({String key, String label})? topicOfCard(QuestionCard c, Map<String, CurriculumNode> curriculum) {
  final node = c.mebNodeId == null ? null : curriculum[c.mebNodeId];
  if (node != null) return (key: 'meb:${node.id}', label: node.title);
  final t = c.topicText?.trim();
  if (t == null || t.isEmpty) return null;
  return (key: 'txt:${c.subject}:${normalizeTr(t)}', label: titleCaseTr(t));
}

/// Tüm defterden her yanlış/boş kart için benzerlik bilgisi. Konusu belli
/// olmayan kartlar sonuçta yer almaz.
Map<String, Recurrence> recurrenceOf(Iterable<QuestionCard> cards, Map<String, CurriculumNode> curriculum) {
  final mistakes = [for (final c in cards) if (c.status != QuestionStatus.correct) c];
  final topicCount = <String, int>{};
  final pairCount = <String, int>{};
  final topics = <String, ({String key, String label})>{};
  for (final c in mistakes) {
    final t = topicOfCard(c, curriculum);
    if (t == null) continue;
    topics[c.id] = t;
    topicCount[t.key] = (topicCount[t.key] ?? 0) + 1;
    final r = c.reason;
    if (r != null) pairCount['${t.key}|${r.name}'] = (pairCount['${t.key}|${r.name}'] ?? 0) + 1;
  }
  return {
    for (final c in mistakes)
      if (topics[c.id] != null)
        c.id: Recurrence(
          topic: topics[c.id]!.label,
          sameTopic: topicCount[topics[c.id]!.key]!,
          sameTopicReason: c.reason == null ? 0 : pairCount['${topics[c.id]!.key}|${c.reason!.name}']!,
          reason: c.reason,
        ),
  };
}

/// Tekrar kuyruğu: tekrarlayan hatalar önce (ağırlığa göre), diğerleri eski
/// sırasıyla arkadan. Sıralama kararlıdır.
List<DueReview> prioritizeDue(List<DueReview> due, Map<String, Recurrence> rec) {
  final indexed = [for (final (i, d) in due.indexed) (i, d)];
  int weight(DueReview d) {
    final r = rec[d.card.id];
    return r != null && r.isRecurring ? r.score : 0;
  }

  indexed.sort((a, b) {
    final w = weight(b.$2).compareTo(weight(a.$2));
    return w != 0 ? w : a.$1.compareTo(b.$1);
  });
  return [for (final (_, d) in indexed) d];
}
