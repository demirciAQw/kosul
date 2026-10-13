import '../../../core/text/turkish_text.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../question_bank/domain/question_card.dart';

/// "Şu dersten genelde şu tip soruları kaçırıyorsun": etiketlere (konu, neden,
/// durum) dayalı, yapay zekâ kullanmayan ders bazlı örüntüler.
class SubjectPattern {
  const SubjectPattern({required this.subject, required this.mistakes, required this.insights});

  final String subject; // "TYT Matematik"
  final int mistakes; // yanlış + boş
  final List<String> insights;
}

/// Her neden için kısa, uygulanabilir bir öneri.
String reasonAdvice(MistakeReason reason) => switch (reason) {
      MistakeReason.knowledgeGap => 'konu tekrarı iyi gelir',
      MistakeReason.misconception => 'kavramı örnekle baştan çalış',
      MistakeReason.calculation => 'işlemi kâğıda yazarak ilerle, sonucu kontrol et',
      MistakeReason.misreading => 'soru kökünü işaretleyerek oku',
      MistakeReason.carelessness => 'işaretlemeden önce şıkları bir kez daha kontrol et',
      MistakeReason.timePressure => 'süre tutarak çözmeyi dene',
      MistakeReason.wrongMethod => 'çözümleri karşılaştırıp kısa yolu not al',
      MistakeReason.guessed => 'emin olmadığın konuyu tekrar et',
      MistakeReason.other => '',
    };

String _percent(int part, int whole) => '%${(part * 100 / whole).round()}';

CurriculumNode _rootOf(CurriculumNode node, Map<String, CurriculumNode> curriculum) {
  var current = node;
  for (var i = 0; i < 10; i++) {
    final parent = current.parentId == null ? null : curriculum[current.parentId];
    if (parent == null) break;
    current = parent;
  }
  return current;
}

K? _maxKey<K>(Map<K, int> counts) {
  K? best;
  var bestCount = 0;
  counts.forEach((k, v) {
    if (v > bestCount) {
      best = k;
      bestCount = v;
    }
  });
  return best;
}

/// Yanlış ve boş kartlardan ders bazlı örüntüler; en çok hata yapılan ders başta.
/// [minMistakes] altındaki dersler için yorum üretilmez (az veriyle yanıltmamak için).
List<SubjectPattern> findSubjectPatterns(
  Iterable<QuestionCard> cards,
  Map<String, CurriculumNode> curriculum, {
  int minMistakes = 3,
}) {
  final bySubject = <String, List<QuestionCard>>{};
  for (final c in cards) {
    if (c.status == QuestionStatus.correct) continue;
    (bySubject[c.subject] ??= []).add(c);
  }

  final out = <SubjectPattern>[];
  for (final entry in bySubject.entries) {
    final list = entry.value;
    final n = list.length;
    if (n < minMistakes) continue;

    final rootCount = <String, int>{};
    final leafCount = <String, int>{};
    final reasonCount = <MistakeReason, int>{};
    final comboCount = <String, int>{}; // "kök|neden"
    final blankByRoot = <String, int>{};
    final titles = <String, String>{}; // kök anahtarı → görünen ad
    var untagged = 0, reasoned = 0, blanks = 0;

    for (final c in list) {
      final node = c.mebNodeId == null ? null : curriculum[c.mebNodeId];
      final root = node == null ? null : _rootOf(node, curriculum);
      // MEB konusu yoksa karneden gelen kazanım adı konu yerine geçer.
      final text = c.topicText?.trim();
      final String? rootKey = root?.id ?? ((text != null && text.isNotEmpty) ? 'txt:${normalizeTr(text)}' : null);
      if (rootKey == null) {
        untagged++;
      } else {
        titles[rootKey] = root?.title ?? titleCaseTr(text!);
        rootCount[rootKey] = (rootCount[rootKey] ?? 0) + 1;
        if (root != null && node!.id != root.id) leafCount[node.id] = (leafCount[node.id] ?? 0) + 1;
      }
      final reason = c.reason;
      if (reason != null) {
        reasoned++;
        reasonCount[reason] = (reasonCount[reason] ?? 0) + 1;
        if (rootKey != null) {
          final key = '$rootKey|${reason.name}';
          comboCount[key] = (comboCount[key] ?? 0) + 1;
        }
      }
      if (c.status == QuestionStatus.blank) {
        blanks++;
        if (rootKey != null) blankByRoot[rootKey] = (blankByRoot[rootKey] ?? 0) + 1;
      }
    }

    final insights = <String>[];

    // 1) Konu yoğunlaşması (+ en çok hangi alt konu).
    final topRootId = _maxKey(rootCount);
    if (topRootId != null && rootCount[topRootId]! >= 2) {
      final count = rootCount[topRootId]!;
      final rootTitle = titles[topRootId]!;
      final leaves = {
        for (final e in leafCount.entries)
          if (curriculum[e.key] != null && _rootOf(curriculum[e.key]!, curriculum).id == topRootId) e.key: e.value,
      };
      final topLeaf = _maxKey(leaves);
      final leafNote = topLeaf != null && leaves[topLeaf]! >= 2 && leaves[topLeaf]! * 2 >= count
          ? ' En çok da ${curriculum[topLeaf]!.title}.'
          : '';
      insights.add('Yanlış ve boşlarının ${_percent(count, n)} kadarı $rootTitle konusunda ($count soru).$leafNote');
    }

    // 2) Konu × neden: "bu konuda genelde şu sebepten kaçırıyorsun".
    final topCombo = _maxKey(comboCount);
    if (topCombo != null && comboCount[topCombo]! >= 2) {
      final cut = topCombo.lastIndexOf('|');
      final comboTitle = titles[topCombo.substring(0, cut)]!;
      final reason = MistakeReason.values.byName(topCombo.substring(cut + 1));
      final advice = reasonAdvice(reason);
      insights.add('$comboTitle sorularında en sık neden ${lowerTr(reason.label)} '
          '(${comboCount[topCombo]} soru)${advice.isEmpty ? '.' : ': $advice.'}');
    }

    // 3) Dersin genel nedeni (konu × neden ile aynı değilse).
    final topReason = _maxKey(reasonCount);
    if (topReason != null && reasoned >= 3) {
      final sameAsCombo = topCombo != null && topCombo.endsWith('|${topReason.name}');
      if (!sameAsCombo) {
        final advice = reasonAdvice(topReason);
        insights.add('Bu dersteki en sık neden ${lowerTr(topReason.label)} '
            '(${_percent(reasonCount[topReason]!, reasoned)})${advice.isEmpty ? '.' : ': $advice.'}');
      }
    }

    // 4) Boş bırakma örüntüsü.
    final topBlankRoot = _maxKey(blankByRoot);
    if (blanks >= 3 && topBlankRoot != null && blankByRoot[topBlankRoot]! * 2 >= blanks) {
      insights.add('Boş bıraktıklarının çoğu ${titles[topBlankRoot]!} konusundan '
          '(${blankByRoot[topBlankRoot]}/$blanks).');
    }

    // 5) Veri eksikliği uyarısı.
    if (untagged >= 2 && untagged * 2 >= n) {
      insights.add('$untagged sorunun konusu girilmemiş; konu ekledikçe örüntü netleşir.');
    } else if (reasoned * 2 < n) {
      insights.add('Soruların çoğuna neden seçilmemiş; Eksikler\'den tek dokunuşla ekleyebilirsin.');
    }

    if (insights.isNotEmpty) {
      out.add(SubjectPattern(subject: entry.key, mistakes: n, insights: insights));
    }
  }
  out.sort((a, b) => b.mistakes.compareTo(a.mistakes));
  return out;
}
