import '../../../core/text/fuzzy_search.dart';
import '../../../core/text/turkish_text.dart';
import 'question_card.dart';

// Ortak parçalar core/text/ altında; eski içe aktarmalar bozulmasın diye buradan da verilir.
export '../../../core/text/fuzzy_search.dart';

/// Akıllı arama: yazım hatalarını tolere eder, en az bir kelimesi benzeyen
/// soruyu listeler, sonuçları alaka sırasına koyar.
///
/// Her sorunun alanları (konu, ders, kaynak, test, neden, not, durum) kelimelere
/// ayrılır ve Türkçe katlanır. Arama kelimesi başına en iyi eşleşme alınır:
/// tam eşleşme > baş eşleşmesi > içinde geçme > yazım hatası (harf eksik,
/// fazla, farklı ya da yer değiştirmiş). Hata payı kelime uzadıkça artar.
class SmartSearchResult {
  const SmartSearchResult({required this.cards, required this.scores, this.suggestion});
  final List<QuestionCard> cards;
  final Map<String, double> scores; // kart → alaka puanı
  /// "Bunu mu demek istedin?" önerisi (düzeltilmiş arama), yoksa null.
  final String? suggestion;
}

/// Alan ağırlıkları: konuda eşleşen, notta eşleşenden önemlidir.
const fieldWeights = (
  topic: 1.0,
  subject: 0.9,
  source: 0.8,
  test: 0.8,
  reason: 0.7,
  note: 0.6,
  status: 0.5,
  // Fotoğraftan okunan metin: içerik araması için; etiketlerin önüne geçmesin.
  ocr: 0.5,
);

/// [fieldsOf] her kart için aranacak alanları verir. Sonuç: en az bir arama
/// kelimesi benzeyen kartlar, alaka puanına göre (eşitse en yeni önce).
SmartSearchResult smartSearch(
  List<QuestionCard> cards,
  String query,
  List<SearchField> Function(QuestionCard) fieldsOf,
) {
  final qs = searchTokens(query);
  if (qs.isEmpty) return SmartSearchResult(cards: cards, scores: const {});
  final normQuery = normalizeTr(query).trim();
  final simCache = <String, double>{};
  double sim(String q, String t) => simCache.putIfAbsent('$q|$t', () => tokenSimilarity(q, t));

  // Öneri için sözlük: katlanmış kelime → ilk görülen yazılışı ("turev" → "Türev").
  final display = <String, String>{};
  final scored = <(QuestionCard, double)>[];
  for (final c in cards) {
    final score = relevanceScore(
      fieldsOf(c),
      qs,
      normQuery,
      sim: sim,
      onWord: (n, word) => display.putIfAbsent(n, () => word),
    );
    if (score == null) continue;
    scored.add((c, score));
  }
  scored.sort((a, b) {
    final s = b.$2.compareTo(a.$2);
    return s != 0 ? s : b.$1.createdAt.compareTo(a.$1.createdAt);
  });

  // Öneri: sözlükte karşılığı olmayan kelimeyi en yakın kelimeyle değiştir.
  String? suggestion;
  final vocab = display.keys.toList();
  final corrected = <String>[];
  var changed = false;
  for (final q in qs) {
    if (vocab.any((t) => t == q || t.startsWith(q))) {
      corrected.add(display[q] ?? q);
      continue;
    }
    String? bestWord;
    var bestSim = 0.0;
    for (final t in vocab) {
      final allowed = typoAllowance(q);
      if (allowed == 0) break;
      final d = editDistance(q, t, allowed);
      if (d > allowed) continue;
      final s = 0.85 - 0.1 * (d - 1);
      if (s > bestSim) {
        bestSim = s;
        bestWord = t;
      }
    }
    if (bestWord != null && bestSim >= 0.65) {
      corrected.add(display[bestWord]!);
      changed = true;
    } else {
      corrected.add(q);
    }
  }
  if (changed) suggestion = corrected.join(' ');

  return SmartSearchResult(
    cards: [for (final (c, _) in scored) c],
    scores: {for (final (c, s) in scored) c.id: s},
    suggestion: suggestion,
  );
}
