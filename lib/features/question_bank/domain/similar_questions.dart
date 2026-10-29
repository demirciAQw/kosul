import 'dart:math' as math;

import '../../../core/text/turkish_text.dart';
import 'question_card.dart';

/// Benzer soru arama ve eşleme (yerelde, model yok).
///
/// Sorunun parçaları **ayrı ayrı** karşılaştırılır: paragraf / verilen metin,
/// soru cümlesi (kök), şıklar ve öncüller. Karşılaştırma **terimlere** odaklanır:
/// bağlaçlar, soru kalıpları ("aşağıdakilerden hangisi", "bu parçada asıl
/// anlatılmak istenen") ve Roma rakamları atılır; kelimelerin ilk 5 harfi
/// alınır (Türkçe ekleri atmanın basit, etkili yolu: entalpi, entalpisi,
/// entalpinin → "ental"). Ağırlıklar TF-IDF: senin sorularında nadir geçen
/// terim daha ayırt edicidir.
///
/// Prototipte (gerçek soru metinleriyle) aynı konulu çiftler %26–45, farklı
/// konulular en çok %10 benzerlik aldı; eşleme eşiği bu yüzden %25.

class SimilarProfile {
  const SimilarProfile({
    this.text = '',
    this.passage = '',
    this.prompt = '',
    this.options = '',
    this.given = '',
    this.topicKey,
    this.types = const {},
    this.stemKind,
    this.figureKinds = const {},
    this.numericOptions,
  });

  /// Parçalara ayrılamamış metin (eski kayıtlar): paragraf sayılır.
  final String text;
  final String passage; // paragraf, verilen bilgi
  final String prompt; // soru cümlesi (kök)
  final String options; // A–E şıkları
  final String given; // öncüller ve maddeler

  final String? topicKey; // konu adı (katlanmış)
  final Set<String> types;
  final String? stemKind; // StemKind.name
  final Set<String> figureKinds;
  final bool? numericOptions;

  String get passageText => passage.isNotEmpty ? passage : text;
}

/// Parçalar ve ağırlıkları (ikisinde de olan parçalar üzerinden ortalanır).
enum SimilarPart {
  passage('paragraf', 0.40),
  prompt('kök', 0.25),
  options('şıklar', 0.20),
  given('verilen bilgi', 0.15);

  const SimilarPart(this.label, this.weight);
  final String label;
  final double weight;

  String of(SimilarProfile p) => switch (this) {
        SimilarPart.passage => p.passageText,
        SimilarPart.prompt => p.prompt,
        SimilarPart.options => p.options,
        SimilarPart.given => p.given,
      };
}

/// Bağlaçlar, edatlar, soru kalıpları (katlanmış tam kelime).
const _stopWords = {
  'asagidakilerden', 'asagidaki', 'hangisi', 'hangisidir', 'hangileri', 'hangisine', 'hangisinde', 'buna',
  'gore', 'verilen', 'verilenlerden', 'yukaridaki', 'olan', 'olarak', 'icin', 'ile', 'olur', 'olabilir',
  'dir', 'dur', 'tir', 'bir', 'veya', 'yalniz', 'bu', 'su', 'ise', 'gibi', 'kadar', 'daha', 'cok',
  'sekilde', 'soru', 've', 'ama', 'fakat', 'ancak', 'cunku', 'eger', 'hem', 'yani', 'nasil', 'neden',
  'nicin', 'kac', 'nedir', 'midir', 'bunlardan', 'bunun', 'bunu', 'onun', 'ona', 'her', 'hic', 'tum',
  'butun', 'bazi', 'baska', 'diger', 'ayni', 'iliskin', 'uzere', 'arasinda', 'icinde', 'uzerinde',
  'sonra', 'once',
};

/// Soru kalıbı kökleri (ilk 5 harf): "bu parçada asıl anlatılmak istenen",
/// "hangisi yanlıştır / doğrudur / değildir / söylenemez / beklenmez".
const _stopStems = {
  'parca', 'asil', 'anlat', 'isten', 'vurgu', 'soyle', 'getir', 'birin', 'yola', 'cikil', 'cikar', 'bilgi',
  'ilgil', 'sahip', 'ozell', 'durum', 'sonuc', 'ifade', 'cumle', 'bekle', 'gorus', 'dile', 'hangi', 'yanli',
  'dogru', 'degil', 'yapil', 'ulasi', 'olama',
};

const _roman = {'i', 'ii', 'iii', 'iv', 'v', 'vi'};

/// Terimler: katlanmış, en az 3 harf, sayı / Roma rakamı / kalıp değil; ilk 5 harf.
List<String> termTokens(String text) {
  final out = <String>[];
  for (final t in normalizeTr(text).split(' ')) {
    if (t.length < 3 || _roman.contains(t) || _stopWords.contains(t) || RegExp(r'^\d+$').hasMatch(t)) continue;
    final stem = t.length > 5 ? t.substring(0, 5) : t;
    if (_stopStems.contains(stem)) continue;
    out.add(stem);
  }
  return out;
}

/// TF-IDF vektörleri (birim uzunlukta).
Map<String, Map<String, double>> tfidfVectors(Map<String, List<String>> docs) {
  final df = <String, int>{};
  for (final ts in docs.values) {
    for (final t in ts.toSet()) {
      df[t] = (df[t] ?? 0) + 1;
    }
  }
  final n = docs.length;
  final out = <String, Map<String, double>>{};
  for (final e in docs.entries) {
    if (e.value.isEmpty) continue;
    final tf = <String, double>{};
    for (final t in e.value) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final v = {for (final x in tf.entries) x.key: x.value * (math.log((n + 1) / ((df[x.key] ?? 0) + 1)) + 1)};
    final norm = math.sqrt(v.values.fold<double>(0, (s, x) => s + x * x));
    if (norm > 0) out[e.key] = {for (final x in v.entries) x.key: x.value / norm};
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

/// Benzerlik dizini: parça başına vektörler ve aday bulmak için ters dizin
/// (terim → o terimi en ayırt edici terimleri arasında taşıyan sorular).
class SimilarIndex {
  SimilarIndex._(this.parts, this._postings, this._keyTerms);

  final Map<SimilarPart, Map<String, Map<String, double>>> parts;
  final Map<String, List<String>> _postings;
  final Map<String, List<String>> _keyTerms;

  static const keyTermCount = 8;

  factory SimilarIndex.build(Map<String, SimilarProfile> profiles) {
    final parts = {
      for (final part in SimilarPart.values)
        part: tfidfVectors({for (final e in profiles.entries) e.key: termTokens(part.of(e.value))}),
    };
    // Tüm parçaların birleşik vektöründen en ağır terimler: aday üretimi için.
    final keyTerms = <String, List<String>>{};
    final postings = <String, List<String>>{};
    for (final id in profiles.keys) {
      final weight = <String, double>{};
      for (final part in SimilarPart.values) {
        for (final e in (parts[part]![id] ?? const <String, double>{}).entries) {
          weight[e.key] = (weight[e.key] ?? 0) + e.value * part.weight;
        }
      }
      final top = (weight.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(keyTermCount)
          .map((e) => e.key)
          .toList();
      keyTerms[id] = top;
      for (final t in top) {
        (postings[t] ??= []).add(id);
      }
    }
    return SimilarIndex._(parts, postings, keyTerms);
  }

  /// En az bir ayırt edici terimi paylaşan adaylar (kendisi hariç).
  Set<String> candidates(String id) => {
        for (final t in _keyTerms[id] ?? const <String>[]) ...?_postings[t],
      }..remove(id);

  /// Parça parça metin benzerliği ve ağırlıklı toplam (ikisinde de olan parçalar).
  ({double total, Map<SimilarPart, double> parts}) textSimilarity(String a, String b) {
    var sum = 0.0, den = 0.0;
    final byPart = <SimilarPart, double>{};
    for (final part in SimilarPart.values) {
      final va = parts[part]![a], vb = parts[part]![b];
      if (va == null || vb == null) continue;
      final c = cosine(va, vb);
      byPart[part] = c;
      sum += part.weight * c;
      den += part.weight;
    }
    return (total: den == 0 ? 0.0 : sum / den, parts: byPart);
  }
}

class SimilarMatch {
  const SimilarMatch({required this.card, required this.score, required this.text, required this.reasons});
  final QuestionCard card;
  final double score; // genel puan (konu, tür, metin…)
  final double text; // metin benzerliği 0–1
  final List<String> reasons;
}

class SimilarResult {
  const SimilarResult({required this.mistakes, required this.correct});
  final List<SimilarMatch> mistakes;
  final List<SimilarMatch> correct;
}

/// Eşleme eşiği (metin benzerliği): prototipte aynı konulu çiftler ≥ 0,26,
/// farklı konulular ≤ 0,10.
const matchThreshold = 0.25;

SimilarMatch? _compare(QuestionCard t, SimilarProfile p, QuestionCard c, SimilarProfile q, SimilarIndex index) {
  if (normalizeTr(t.subject) != normalizeTr(c.subject)) return null;
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
    reasons.add('benzer şekil/grafik');
  }
  if (p.numericOptions != null && p.numericOptions == q.numericOptions) score += 0.3;
  final sim = index.textSimilarity(t.id, c.id);
  score += 6 * sim.total;
  for (final e in sim.parts.entries) {
    if (e.value >= 0.2) reasons.add('${e.key.label} %${(e.value * 100).round()}');
  }
  return SimilarMatch(card: c, score: score, text: sim.total, reasons: reasons);
}

/// Bir sorunun benzerleri: yanlış/boş ve doğru yapılanlar ayrı.
SimilarResult findSimilar(
  QuestionCard target,
  List<QuestionCard> cards,
  Map<String, SimilarProfile> profiles,
  SimilarIndex index, {
  int limit = 5,
  double minScore = 2.5,
}) {
  final p = profiles[target.id];
  if (p == null) return const SimilarResult(mistakes: [], correct: []);
  final byId = {for (final c in cards) c.id: c};
  // Aday: ayırt edici terim paylaşanlar + aynı konudakiler (metni farklı olsa da).
  final ids = {
    ...index.candidates(target.id),
    if (p.topicKey != null)
      for (final e in profiles.entries)
        if (e.value.topicKey == p.topicKey) e.key,
  }..remove(target.id);
  final matches = <SimilarMatch>[];
  for (final id in ids) {
    final c = byId[id], q = profiles[id];
    if (c == null || q == null) continue;
    final m = _compare(target, p, c, q, index);
    if (m != null && m.score >= minScore) matches.add(m);
  }
  matches.sort((a, b) => b.score.compareTo(a.score));
  return SimilarResult(
    mistakes: [for (final m in matches) if (m.card.status != QuestionStatus.correct) m].take(limit).toList(),
    correct: [for (final m in matches) if (m.card.status == QuestionStatus.correct) m].take(limit).toList(),
  );
}

/// Eşleme: metin benzerliği eşiğin üstünde olan sorular aynı gruba (aynı ders,
/// konusu çelişmeyen). Kart → grup numarası; tek kalanlar haritada yok.
Map<String, int> similarGroups(List<QuestionCard> cards, Map<String, SimilarProfile> profiles, SimilarIndex index,
    {double threshold = matchThreshold}) {
  final byId = {for (final c in cards) c.id: c};
  final parent = <String, String>{};
  String find(String x) {
    var r = x;
    while (parent[r] != null && parent[r] != r) {
      r = parent[r]!;
    }
    parent[x] = r;
    return r;
  }

  for (final id in profiles.keys) {
    final a = byId[id];
    if (a == null) continue;
    for (final other in index.candidates(id)) {
      if (other.compareTo(id) <= 0) continue; // her çift bir kez
      final b = byId[other];
      if (b == null || normalizeTr(a.subject) != normalizeTr(b.subject)) continue;
      final ta = profiles[id]!.topicKey, tb = profiles[other]!.topicKey;
      if (ta != null && tb != null && ta != tb) continue;
      if (index.textSimilarity(id, other).total < threshold) continue;
      parent[find(id)] = find(other);
    }
  }
  final roots = <String, List<String>>{};
  for (final id in parent.keys) {
    (roots[find(id)] ??= []).add(id);
  }
  final out = <String, int>{};
  var n = 0;
  for (final members in roots.values) {
    if (members.length < 2) continue;
    n++;
    for (final m in members) {
      out[m] = n;
    }
  }
  return out;
}
