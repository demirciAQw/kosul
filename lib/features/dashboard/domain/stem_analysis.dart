import 'dart:math' as math;

import '../../../core/text/turkish_text.dart';
import '../../question_bank/domain/question_card.dart';

/// Soru kökü analizi: fotoğraftan okunan soru cümlelerinin türü (olumsuz,
/// öncüllü, "en …", hesap, olumlu) ve tekrar eden kalıpları; hangi kök
/// türünde açık ara bir eğilim olduğu.
///
/// Önemli: defterdeki soruların çoğu yanlış ya da boştur; doğru yapılanların
/// fotoğrafı genellikle yoktur. Bu yüzden "olumsuz köklerde daha çok yanlış"
/// diyebilmek için payda yoktur. Dürüst karşılaştırmalar: yanlışların içinde
/// dikkatsizlik ve boş bırakma oranları; fotoğraflı doğru sorular yeterliyse
/// gerçek hata oranı.

enum StemKind {
  negative('Olumsuz kök', 'değildir, yanlıştır, söylenemez…'),
  premise('Öncüllü', 'I, II, III / hangileri'),
  superlative('"En …" kökü', 'en az, en çok, en uygun…'),
  quantity('Hesap', 'kaçtır, kaç farklı…'),
  positive('Olumlu kök', 'hangisidir, nedir…');

  const StemKind(this.label, this.hint);
  final String label;
  final String hint;
}

// Katlanmış metinde (ı→i, ş→s, ğ→g …) aranır.
final _negative = RegExp(
    r'\b(degil\w*|yanlis\w*|yok\w*|\w+(maz|mez)|\w+(mamis|memis)\w*)\b');
final _premise = RegExp(r'\bhangileri\w*\b');
final _superlative =
    RegExp(r'\ben (az|cok|fazla|buyuk|kucuk|kisa|uzun|yuksek|dusuk|son|once|iyi|uygun|dogru|belirgin|onemli)\b');
final _quantity = RegExp(r'\bkac\w*\b');

/// Soru cümlesinin türü (öncelik: olumsuz > öncüllü > en … > hesap > olumlu).
StemKind classifyStem(String prompt, {bool hasStatements = false}) {
  final t = normalizeTr(prompt);
  if (_negative.hasMatch(t)) return StemKind.negative;
  if (hasStatements || _premise.hasMatch(t)) return StemKind.premise;
  if (_superlative.hasMatch(t)) return StemKind.superlative;
  if (_quantity.hasMatch(t)) return StemKind.quantity;
  return StemKind.positive;
}

/// Kalıp için kelimeler: soru cümlesinin son 4 anlamlı kelimesi (sayı ve tek
/// harfler atılır), katlanmış. Kalıbı belirleyen sondur ("…hangisine değinilmemiştir").
List<String> stemTemplate(String prompt) {
  final words = [
    for (final w in normalizeTr(prompt).split(RegExp(r'[^a-z0-9]+')))
      if (w.length >= 2 && !RegExp(r'^\d+$').hasMatch(w)) w,
  ];
  return words.length <= 4 ? words : words.sublist(words.length - 4);
}

double _jaccard(List<String> a, List<String> b) {
  final sa = a.toSet(), sb = b.toSet();
  if (sa.isEmpty && sb.isEmpty) return 1;
  return sa.intersection(sb).length / sa.union(sb).length;
}

/// Analize giren bir soru.
class StemSample {
  const StemSample({
    required this.prompt,
    required this.status,
    this.reason,
    this.hasStatements = false,
    this.subject,
  });
  final String prompt;
  final QuestionStatus status;
  final MistakeReason? reason;
  final bool hasStatements;
  final String? subject;

  bool get isMistake => status != QuestionStatus.correct;
}

class StemTrend {
  const StemTrend({required this.text, required this.z, required this.kind});
  final String text;
  final double z;
  final StemKind kind;
}

class StemTemplateGroup {
  const StemTemplateGroup({
    required this.example,
    required this.count,
    required this.wrong,
    required this.blank,
    required this.careless,
  });
  final String example; // görünen kalıp ("…aşağıdakilerden hangisi söylenemez?")
  final int count;
  final int wrong;
  final int blank;
  final int careless;
}

class StemReport {
  const StemReport({
    required this.analyzed,
    required this.mistakes,
    required this.counts,
    required this.trends,
    required this.templates,
    required this.verdict,
  });
  final int analyzed; // okunmuş soru cümlesi olan sorular
  final int mistakes;
  final Map<StemKind, int> counts; // yanlış ve boşlarda
  final List<StemTrend> trends; // açık ara eğilimler (güçlüden zayıfa)
  final List<StemTemplateGroup> templates;
  final String verdict;

  bool get hasClearTrend => trends.isNotEmpty;
}

/// İki oran farkının z değeri (iki örneklem oran testi).
double twoProportionZ(int a, int n1, int b, int n2) {
  if (n1 == 0 || n2 == 0) return 0;
  final p1 = a / n1, p2 = b / n2, p = (a + b) / (n1 + n2);
  final se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2));
  return se == 0 ? 0 : (p1 - p2) / se;
}

const minGroup = 8; // her grupta en az bu kadar soru
const minDiff = 0.15; // en az 15 puan fark
const minZ = 2.0; // istatistiksel anlamlılık

String _pct(double v) => '%${(v * 100).round()}';

StemReport analyzeStems(List<StemSample> samples) {
  final usable = [for (final s in samples) if (s.prompt.trim().isNotEmpty) s];
  final kinds = {for (final s in usable) s: classifyStem(s.prompt, hasStatements: s.hasStatements)};
  final mistakes = [for (final s in usable) if (s.isMistake) s];
  final counts = <StemKind, int>{for (final k in StemKind.values) k: 0};
  for (final s in mistakes) {
    counts[kinds[s]!] = counts[kinds[s]!]! + 1;
  }

  final trends = <StemTrend>[];
  void compare(StemKind k, String what, Iterable<StemSample> pool, bool Function(StemSample) hit) {
    final inK = [for (final s in pool) if (kinds[s] == k) s];
    final rest = [for (final s in pool) if (kinds[s] != k) s];
    if (inK.length < minGroup || rest.length < minGroup) return;
    final a = inK.where(hit).length, b = rest.where(hit).length;
    final p1 = a / inK.length, p2 = b / rest.length;
    final z = twoProportionZ(a, inK.length, b, rest.length);
    // Yalnızca yüksek olan yön: "ötekilerde düşük" aynı bulgunun aynasıdır.
    if (p1 - p2 < minDiff || z < minZ) return;
    trends.add(StemTrend(
      kind: k,
      z: z,
      text: '${k.label} sorularda $what belirgin yüksek: '
          '${_pct(p1)} ($a/${inK.length}), ötekilerde ${_pct(p2)} ($b/${rest.length}).',
    ));
  }

  final withReason = [for (final s in mistakes) if (s.reason != null) s];
  final correct = [for (final s in usable) if (!s.isMistake) s];
  for (final k in StemKind.values) {
    compare(k, 'dikkatsizlik payı', withReason, (s) => s.reason == MistakeReason.carelessness);
    compare(k, 'boş bırakma payı', mistakes, (s) => s.status == QuestionStatus.blank);
    // Gerçek hata oranı ancak fotoğraflı doğru sorular yeterliyse.
    if (correct.length >= minGroup) compare(k, 'hata oranı', usable, (s) => s.isMistake);
  }
  trends.sort((a, b) => b.z.abs().compareTo(a.z.abs()));

  // Basit kelime benzerliğiyle tekrar eden kalıplar (yanlış ve boşlarda).
  final groups = <({List<String> key, List<StemSample> items})>[];
  for (final s in mistakes) {
    final t = stemTemplate(s.prompt);
    if (t.length < 2) continue;
    final g = groups.where((g) => _jaccard(g.key, t) >= 0.6).firstOrNull;
    if (g != null) {
      g.items.add(s);
    } else {
      groups.add((key: t, items: [s]));
    }
  }
  final templates = [
    for (final g in groups)
      if (g.items.length >= 3)
        StemTemplateGroup(
          example: () {
            final words = g.items.first.prompt.trim().split(RegExp(r'\s+'));
            return words.length <= 7 ? words.join(' ') : '…${words.sublist(words.length - 7).join(' ')}';
          }(),
          count: g.items.length,
          wrong: g.items.where((s) => s.status == QuestionStatus.wrong).length,
          blank: g.items.where((s) => s.status == QuestionStatus.blank).length,
          careless: g.items.where((s) => s.reason == MistakeReason.carelessness).length,
        ),
  ]..sort((a, b) => b.count.compareTo(a.count));

  final String verdict;
  if (mistakes.length < 2 * minGroup) {
    verdict = 'Henüz yeterli veri yok: soru cümlesi okunmuş ${mistakes.length} yanlış/boş soru var, '
        'karşılaştırma için en az ${2 * minGroup} gerekiyor.';
  } else if (trends.isNotEmpty) {
    verdict = 'Açık ara bir eğilim var. ${trends.first.text}';
  } else {
    verdict = 'Açık ara bir eğilim yok: kök türleri arasındaki farklar ya küçük ya da '
        'tesadüfle açıklanabilecek düzeyde.';
  }
  return StemReport(
    analyzed: usable.length,
    mistakes: mistakes.length,
    counts: counts,
    trends: trends,
    templates: templates.take(5).toList(),
    verdict: verdict,
  );
}
