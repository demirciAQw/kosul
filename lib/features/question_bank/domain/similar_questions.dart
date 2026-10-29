import 'dart:math' as math;

import '../../../core/text/turkish_text.dart';
import 'question_card.dart';
import 'smart_search.dart';

/// Benzer soru arama (yerelde, model yok). Bir sorunun benzerleri, yanlış/boş
/// ve doğru yapılanlar ayrı ayrı bulunur: "Bu hatanın benzerini doğru yapmış
/// mıyım?" sorusunun cevabı.
///
/// Puan: aynı ders şart; aynı konu, ortak soru türleri, aynı kök türü, ortak
/// şekil türü, aynı şık biçimi, benzer uzunluk ve metin benzerliği (TF-IDF:
/// ayırt edici kelimeler ağır, kalıp kelimeler hafif).

/// Bir sorunun benzerlik için özellikleri (okunan metin ve etiketlerden).
class SimilarProfile {
  const SimilarProfile({
    required this.text,
    this.topicKey,
    this.types = const {},
    this.stemKind,
    this.figureKinds = const {},
    this.numericOptions,
  });

  /// Okunan soru metni (kök, öncüller, şıklar).
  final String text;

  /// Konu anahtarı (MEB düğümü, elle yazılan ya da otomatik konu; katlanmış).
  final String? topicKey;
  final Set<String> types; // paragraf, grafik yorumlama, öncüllü …
  final String? stemKind; // negative, premise … (StemKind.name)
  final Set<String> figureKinds; // chart, table, diagram, photo
  /// Şıklar sayısal mı (5 / 5,1 / √3); şık yoksa null.
  final bool? numericOptions;
}

class SimilarMatch {
  const SimilarMatch({required this.card, required this.score, required this.reasons});
  final QuestionCard card;
  final double score;
  final List<String> reasons;
}

class SimilarResult {
  const SimilarResult({required this.mistakes, required this.correct});
  final List<SimilarMatch> mistakes; // yanlış ya da boş yapılan benzerler
  final List<SimilarMatch> correct; // doğru yapılan benzerler
}

/// Soru kalıbı kelimeleri: her soruda geçer, benzerliği şişirmesin.
const _stop = {
  'asagidakilerden', 'hangisi', 'hangisidir', 'hangileri', 'buna', 'gore', 'verilen', 'verilenlerden',
  'yukaridaki', 'asagidaki', 'olan', 'olarak', 'icin', 'ile', 'olur', 'olabilir', 'dir', 'dur', 'tir',
  'bir', 'veya', 'yalniz', 've', 'bu', 'su', 'ise', 'gibi', 'kadar', 'daha', 'cok', 'sekilde', 'soru',
};

/// Benzerlik kelimeleri: katlanmış, en az 3 harf, sayı ve kalıp kelimeler atılır.
List<String> similarityTokens(String text) => [
      for (final t in searchTokens(text))
        if (t.length >= 3 && !RegExp(r'^\d+$').hasMatch(t) && !_stop.contains(t)) t,
    ];

/// TF-IDF vektörleri (her soru için kelime → ağırlık, birim uzunlukta).
Map<String, Map<String, double>> tfidfVectors(Map<String, String> texts) {
  final tokens = {for (final e in texts.entries) e.key: similarityTokens(e.value)};
  final df = <String, int>{};
  for (final ts in tokens.values) {
    for (final t in ts.toSet()) {
      df[t] = (df[t] ?? 0) + 1;
    }
  }
  final n = tokens.length;
  final out = <String, Map<String, double>>{};
  for (final e in tokens.entries) {
    final tf = <String, double>{};
    for (final t in e.value) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final v = {for (final t in tf.entries) t.key: t.value * (math.log((n + 1) / ((df[t.key] ?? 0) + 1)) + 1)};
    final norm = math.sqrt(v.values.fold<double>(0, (s, x) => s + x * x));
    out[e.key] = norm == 0 ? const {} : {for (final x in v.entries) x.key: x.value / norm};
  }
  return out;
}

double cosine(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final (small, large) = a.length <= b.length ? (a, b) : (b, a);
  var s = 0.0;
  for (final e in small.entries) {
    final o = large[e.key];
    if (o != null) s += e.value * o;
  }
  return s;
}

/// Bir sorunun benzerlerini bulur. [vectors]: [tfidfVectors] çıktısı.
SimilarResult findSimilar(
  QuestionCard target,
  List<QuestionCard> cards,
  Map<String, SimilarProfile> profiles,
  Map<String, Map<String, double>> vectors, {
  int limit = 5,
  double minScore = 2.5,
}) {
  final p = profiles[target.id];
  if (p == null) return const SimilarResult(mistakes: [], correct: []);
  final subject = normalizeTr(target.subject);
  final matches = <SimilarMatch>[];
  for (final c in cards) {
    if (c.id == target.id || normalizeTr(c.subject) != subject) continue;
    final q = profiles[c.id];
    if (q == null) continue;
    var score = 0.0;
    final reasons = <String>[];
    if (p.topicKey != null && q.topicKey != null) {
      if (p.topicKey == q.topicKey) {
        score += 3;
        reasons.add('aynı konu');
      } else {
        score -= 1;
      }
    }
    if (p.types.isNotEmpty && q.types.isNotEmpty) {
      final common = p.types.intersection(q.types);
      score += 2 * common.length / p.types.union(q.types).length;
      if (common.isNotEmpty) reasons.add('ortak tür: ${common.join(', ')}');
    }
    if (p.stemKind != null && p.stemKind == q.stemKind) {
      score += p.stemKind == 'positive' ? 0.3 : 1;
      if (p.stemKind != 'positive') reasons.add('aynı kök türü');
    }
    if (p.figureKinds.intersection(q.figureKinds).isNotEmpty) {
      score += 0.5;
      reasons.add('benzer şekil');
    }
    if (p.numericOptions != null && p.numericOptions == q.numericOptions) score += 0.3;
    final la = p.text.length, lb = q.text.length;
    if (la > 0 && lb > 0 && math.min<int>(la, lb) / math.max<int>(la, lb) >= 0.6) score += 0.3;
    final text = cosine(vectors[target.id] ?? const {}, vectors[c.id] ?? const {});
    score += 4 * text;
    if (text >= 0.2) reasons.add('metin benzerliği %${(text * 100).round()}');
    if (score >= minScore) matches.add(SimilarMatch(card: c, score: score, reasons: reasons));
  }
  matches.sort((a, b) => b.score.compareTo(a.score));
  return SimilarResult(
    mistakes: [for (final m in matches) if (m.card.status != QuestionStatus.correct) m].take(limit).toList(),
    correct: [for (final m in matches) if (m.card.status == QuestionStatus.correct) m].take(limit).toList(),
  );
}
