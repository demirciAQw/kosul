import '../../../core/text/turkish_text.dart';
import 'question_card.dart';

/// Akıllı arama: yazım hatalarını tolere eder, en az bir kelimesi benzeyen
/// soruyu listeler, sonuçları alaka sırasına koyar.
///
/// Her sorunun alanları (konu, ders, kaynak, test, neden, not, durum) kelimelere
/// ayrılır ve Türkçe katlanır. Arama kelimesi başına en iyi eşleşme alınır:
/// tam eşleşme > baş eşleşmesi > içinde geçme > yazım hatası (harf eksik,
/// fazla, farklı ya da yer değiştirmiş). Hata payı kelime uzadıkça artar.
class SearchField {
  const SearchField(this.text, this.weight);
  final String text;
  final double weight;
}

class SmartSearchResult {
  const SmartSearchResult({required this.cards, required this.scores, this.suggestion});
  final List<QuestionCard> cards;
  final Map<String, double> scores; // kart → alaka puanı
  /// "Bunu mu demek istedin?" önerisi (düzeltilmiş arama), yoksa null.
  final String? suggestion;
}

/// Alan ağırlıkları: konuda eşleşen, notta eşleşenden önemlidir.
const fieldWeights = (topic: 1.0, subject: 0.9, source: 0.8, test: 0.8, reason: 0.7, note: 0.6, status: 0.5);

List<String> searchTokens(String text) =>
    [for (final t in normalizeTr(text).split(RegExp(r'\s+'))) if (t.length >= 2 || RegExp(r'^\d+$').hasMatch(t)) t];

/// Sınırlı Damerau-Levenshtein (bitişik harf yer değişimi tek hata).
/// [cutoff]'u aşınca erken çıkar ve cutoff + 1 döner.
int editDistance(String a, String b, int cutoff) {
  if ((a.length - b.length).abs() > cutoff) return cutoff + 1;
  var prev2 = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowBest = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final t = prev2[j - 2] + 1;
        if (t < v) v = t;
      }
      cur[j] = v;
      if (v < rowBest) rowBest = v;
    }
    if (rowBest > cutoff) return cutoff + 1;
    prev2 = prev;
    prev = cur;
  }
  return prev[b.length];
}

int _allowed(String q) => q.length <= 3 ? 0 : (q.length <= 5 ? 1 : (q.length <= 8 ? 2 : 3));

/// İki (katlanmış) kelimenin benzerliği, 0–1.
double tokenSimilarity(String q, String t) {
  if (t == q) return 1;
  if (q.length >= 2 && t.startsWith(q)) return 0.9;
  if (q.length >= 3 && t.contains(q)) return 0.75;
  final allowed = _allowed(q);
  if (allowed == 0) return 0;
  final d = editDistance(q, t, allowed);
  if (d <= allowed) return 0.85 - 0.1 * (d - 1);
  if (t.length > q.length) {
    // Yazılmakta olan kelime: başında yazım hatası ("turv" → "ture…").
    final d2 = editDistance(q, t.substring(0, q.length), allowed);
    if (d2 <= allowed) return 0.8 - 0.1 * (d2 - 1);
  }
  return 0;
}

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
    final fields = fieldsOf(c);
    final tokens = <(String, double)>[];
    for (final f in fields) {
      for (final word in f.text.split(RegExp(r'[\s/,;:()·.-]+'))) {
        for (final n in normalizeTr(word).split(' ')) {
          if (n.isEmpty) continue;
          display.putIfAbsent(n, () => word);
          tokens.add((n, f.weight));
        }
      }
    }
    var total = 0.0;
    var matched = 0;
    for (final q in qs) {
      var best = 0.0;
      for (final (t, w) in tokens) {
        final s = sim(q, t) * w;
        if (s > best) best = s;
      }
      total += best;
      if (best >= 0.45) matched++;
    }
    if (matched == 0) continue;
    var score = (total / qs.length) * (0.7 + 0.3 * matched / qs.length);
    final joined = normalizeTr(fields.map((f) => f.text).join(' '));
    if (normQuery.length >= 3 && joined.contains(normQuery)) score += 0.15; // ifade birebir geçiyor
    if (fields.any((f) => normalizeTr(f.text).trim() == normQuery)) score += 0.1; // bir alanın tamamı
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
      final allowed = _allowed(q);
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
