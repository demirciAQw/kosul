import '../../../core/text/turkish_text.dart';

/// Kartlarda ve filtrelerde "Ders" anahtarı: "TYT Matematik".
String subjectKey(String examType, String subject) => '$examType $subject';

class CurriculumNode {
  const CurriculumNode({
    required this.id,
    required this.examType,
    required this.subject,
    required this.title,
    required this.depth,
    required this.sortOrder,
    this.parentId,
    this.aliases = const [],
  });

  final String id;
  final String? parentId;
  final String examType;
  final String subject;
  final String title;
  final List<String> aliases;
  final int depth;
  final int sortOrder;

  String get subjectLabel => subjectKey(examType, subject);
}

abstract interface class CurriculumRepository {
  Stream<List<CurriculumNode>> watchAll();
  Future<List<CurriculumNode>> all();
}

/// Ağacı derinlik-öncelikli sıraya dizer (açılır menüde hiyerarşik görünüm için).
List<CurriculumNode> depthFirst(Iterable<CurriculumNode> nodes) {
  final ids = {for (final n in nodes) n.id};
  final byParent = <String?, List<CurriculumNode>>{};
  for (final n in nodes) {
    (byParent[ids.contains(n.parentId) ? n.parentId : null] ??= []).add(n);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  final out = <CurriculumNode>[];
  void walk(String? parent) {
    for (final n in byParent[parent] ?? const <CurriculumNode>[]) {
      out.add(n);
      walk(n.id);
    }
  }

  walk(null);
  return out;
}

class TopicMatch {
  const TopicMatch(this.nodeId, this.score);
  final String nodeId;
  final double score; // 0..1
}

/// Kitaplardaki serbest konu adlarını MEB ağacına normalize eder.
///
/// "YAŞ PROBLEMLERİ", "Yaş Problemleri – Kavrama", "Yas problemleri"
/// → tyt.mat.problemler.yas. Başlık + takma adlar üzerinden karakter-ikili
/// Dice benzerliği; ebeveyni eşleşmiş düğümün çocuklarına küçük bir bonus.
class TopicMatcher {
  TopicMatcher(Iterable<CurriculumNode> nodes)
      : _entries = [
          for (final n in nodes)
            for (final name in [n.title, ...n.aliases])
              (node: n, norm: normalizeTr(name), grams: bigramsOf(normalizeTr(name))),
        ];

  /// Bu skorun üstü otomatik kabul; [suggestThreshold] ile arası "onay bekliyor".
  static const autoAcceptThreshold = 0.75;
  static const suggestThreshold = 0.55;

  final List<({CurriculumNode node, String norm, Set<String> grams})> _entries;

  TopicMatch? match(String title, {String? parentMebId}) {
    final norm = normalizeTr(title);
    if (norm.isEmpty) return null;
    final grams = bigramsOf(norm);
    CurriculumNode? best;
    var bestScore = 0.0;
    for (final e in _entries) {
      var score = e.norm == norm ? 1.0 : diceCoefficient(grams, e.grams);
      if (parentMebId != null) {
        if (e.node.parentId == parentMebId) score += 0.10;
        if (e.node.id == parentMebId) score += 0.05;
      }
      if (score > bestScore) {
        bestScore = score;
        best = e.node;
      }
    }
    if (best == null || bestScore < suggestThreshold) return null;
    return TopicMatch(best.id, bestScore > 1 ? 1 : bestScore);
  }
}

/// [rootId] ve altındaki tüm düğümlerin kimlikleri (üst konu seçilince alt konuları da kapsar).
Set<String> descendantIds(Iterable<CurriculumNode> nodes, String rootId) {
  final children = <String, List<String>>{};
  for (final n in nodes) {
    final parent = n.parentId;
    if (parent != null) (children[parent] ??= []).add(n.id);
  }
  final result = <String>{rootId};
  final stack = [rootId];
  while (stack.isNotEmpty) {
    for (final child in children[stack.removeLast()] ?? const <String>[]) {
      if (result.add(child)) stack.add(child);
    }
  }
  return result;
}
