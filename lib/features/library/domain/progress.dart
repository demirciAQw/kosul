import 'library.dart';

/// Bir testin (ya da kitap ağacındaki yaprak başlığın) çözüldü kaydı.
/// Kayıt yoksa test çözülmemiştir. Sayılar optikten gelir; elle "çözüldü"
/// işaretlemede boş kalır.
class TestResult {
  const TestResult({
    required this.nodeId,
    required this.bookId,
    required this.solvedAt,
    this.correct,
    this.wrong,
    this.blank,
    this.total,
    this.sessionId,
  });

  final String nodeId;
  final String bookId;
  final DateTime solvedAt;
  final int? correct;
  final int? wrong;
  final int? blank;
  final int? total;
  final String? sessionId;

  bool get hasCounts => correct != null || wrong != null || blank != null;
}

abstract interface class TestProgressRepository {
  /// Tüm kitapların sonuçları: düğüm kimliği → sonuç.
  Stream<Map<String, TestResult>> watchAll();

  /// Varsa üzerine yazar.
  Future<void> save(TestResult result);

  /// Yalnızca henüz sonucu olmayanları yazar (oturumdan otomatik işaretleme).
  Future<void> saveIfAbsent(List<TestResult> results);

  /// "Çözülmedi" yapar.
  Future<void> clear(String nodeId);
}

// ───────────────────────── Ağaç yardımcıları ─────────────────────────

/// Bir düğümün altındaki yapraklar; kendisi yapraksa yalnızca kendisi.
List<ContentNode> leavesUnder(ContentNode node) {
  if (node.children.isEmpty) return [node];
  return [for (final c in node.children) ...leavesUnder(c)];
}

/// Kitabın ilerleme birimleri: tüm yaprak başlıklar (testler ya da alt başlıklar).
List<ContentNode> progressLeaves(Book book) => [for (final r in book.roots) ...leavesUnder(r)];

/// Optik formda ayrı bölüm olacak testler: soru sayısı bilinen yapraklar.
/// Düğümün altındaki yaprakların HEPSİ test değilse boş döner (bölünmez).
List<ContentNode> testsUnder(ContentNode node) {
  final leaves = leavesUnder(node);
  if (leaves.any((l) => l.questionCount == null)) return const [];
  return leaves;
}

ContentNode? findNode(Book book, String? id) {
  if (id == null) return null;
  for (final n in book.allNodes) {
    if (n.id == id) return n;
  }
  return null;
}

/// Kökten düğüme kadar olan zincir (düğüm dahil).
List<ContentNode> pathTo(Book book, String nodeId) {
  List<ContentNode>? walk(List<ContentNode> nodes, List<ContentNode> trail) {
    for (final n in nodes) {
      final next = [...trail, n];
      if (n.id == nodeId) return next;
      final found = walk(n.children, next);
      if (found != null) return found;
    }
    return null;
  }

  return walk(book.roots, const []) ?? const [];
}

/// "01 Keşfet › Test 6" (kitap adı olmadan).
String nodeLabel(Book book, String nodeId) => pathTo(book, nodeId).map((n) => n.title).join(' › ');

/// Düğümün kendi MEB konusu, yoksa en yakın atasınınki. Test bilinince konu da bilinir.
String? effectiveMeb(Book book, String nodeId) {
  for (final n in pathTo(book, nodeId).reversed) {
    if (n.mebNodeId != null) return n.mebNodeId;
  }
  return null;
}

// ───────────────────────── Kitap ilerlemesi ─────────────────────────

class BookProgress {
  const BookProgress({
    required this.book,
    required this.totalLeaves,
    required this.doneLeaves,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.totalQuestions,
    required this.doneQuestions,
    this.lastSolvedAt,
  });

  final Book book;
  final int totalLeaves;
  final int doneLeaves;
  final int correct;
  final int wrong;
  final int blank;

  /// Soru sayısı bilinen testlerin toplamı ve bunların çözülenleri.
  final int totalQuestions;
  final int doneQuestions;
  final DateTime? lastSolvedAt;

  double get ratio => totalLeaves == 0 ? 0 : doneLeaves / totalLeaves;
  int get remainingLeaves => totalLeaves - doneLeaves;
  int get answered => correct + wrong + blank;
  double? get accuracy => answered == 0 ? null : correct / answered;

  /// Kitapta test yapısı varsa "test", yoksa "başlık".
  String get unitName => book.allNodes.any((n) => n.questionCount != null) ? 'test' : 'başlık';
}

BookProgress bookProgress(Book book, Map<String, TestResult> results) {
  final leaves = progressLeaves(book);
  var done = 0, c = 0, w = 0, b = 0, totalQ = 0, doneQ = 0;
  DateTime? last;
  for (final leaf in leaves) {
    final q = leaf.questionCount;
    if (q != null) totalQ += q;
    final r = results[leaf.id];
    if (r == null) continue;
    done++;
    if (q != null) doneQ += q;
    c += r.correct ?? 0;
    w += r.wrong ?? 0;
    b += r.blank ?? 0;
    if (last == null || r.solvedAt.isAfter(last)) last = r.solvedAt;
  }
  return BookProgress(
    book: book,
    totalLeaves: leaves.length,
    doneLeaves: done,
    correct: c,
    wrong: w,
    blank: b,
    totalQuestions: totalQ,
    doneQuestions: doneQ,
    lastSolvedAt: last,
  );
}

/// Bir ünite/konu düğümünün ilerlemesi (kitap ekranındaki başlık satırları için).
({int done, int total}) nodeProgress(ContentNode node, Map<String, TestResult> results) {
  final leaves = leavesUnder(node);
  return (done: leaves.where((l) => results.containsKey(l.id)).length, total: leaves.length);
}
