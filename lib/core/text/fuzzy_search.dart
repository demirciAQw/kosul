/// Yazım hatasına dayanıklı arama parçaları (soru defteri ve Anlık ortak kullanır).
///
/// Metin kelimelere ayrılır ve Türkçe katlanır (normalizeTr). Arama kelimesi
/// başına en iyi eşleşme alınır: tam > baş eşleşmesi > içinde geçme > yazım
/// hatası (harf eksik, fazla, farklı ya da yer değiştirmiş). Hata payı kelime
/// uzadıkça artar. Alanların ağırlığı vardır (ör. etiket 1.0, metin 0.7).
library;

import 'turkish_text.dart';

class SearchField {
  const SearchField(this.text, this.weight);
  final String text;
  final double weight;
}

List<String> searchTokens(String text) => [
  for (final t in normalizeTr(text).split(RegExp(r'\s+')))
    if (t.length >= 2 || RegExp(r'^\d+$').hasMatch(t)) t,
];

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

/// Kelime uzunluğuna göre izin verilen yazım hatası sayısı.
int typoAllowance(String q) => q.length <= 3 ? 0 : (q.length <= 5 ? 1 : (q.length <= 8 ? 2 : 3));

/// İki (katlanmış) kelimenin benzerliği, 0–1.
double tokenSimilarity(String q, String t) {
  if (t == q) return 1;
  if (q.length >= 2 && t.startsWith(q)) return 0.9;
  if (q.length >= 3 && t.contains(q)) return 0.75;
  final allowed = typoAllowance(q);
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

/// Alanların aranan kelimelere göre alaka puanı. Hiçbir kelime benzemezse null.
///
/// [qs]: `searchTokens(sorgu)`; [normQuery]: `normalizeTr(sorgu)`.
/// [sim]: önbellekli `tokenSimilarity` verilebilir. [onWord]: her kelime
/// (katlanmış, yazıldığı gibi) için çağrılır ("bunu mu demek istedin?" sözlüğü).
double? relevanceScore(
  List<SearchField> fields,
  List<String> qs,
  String normQuery, {
  double Function(String q, String t) sim = tokenSimilarity,
  void Function(String norm, String word)? onWord,
}) {
  if (qs.isEmpty) return null;
  final tokens = <(String, double)>[];
  for (final f in fields) {
    for (final word in f.text.split(RegExp(r'[\s/,;:()·.-]+'))) {
      for (final n in normalizeTr(word).split(' ')) {
        if (n.isEmpty) continue;
        onWord?.call(n, word);
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
  if (matched == 0) return null;
  var score = (total / qs.length) * (0.7 + 0.3 * matched / qs.length);
  final joined = normalizeTr(fields.map((f) => f.text).join(' '));
  if (normQuery.length >= 3 && joined.contains(normQuery)) score += 0.15; // ifade birebir geçiyor
  if (fields.any((f) => normalizeTr(f.text).trim() == normQuery)) score += 0.1; // bir alanın tamamı
  return score;
}
