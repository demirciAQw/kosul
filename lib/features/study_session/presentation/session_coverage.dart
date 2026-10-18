import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../domain/study_session.dart';

/// Oturumda çalışılan testler/başlıklar: kitap haritasında "çözüldü" olacaklar.
///
/// Oturum bitirilir bitirilmez çağrılır (sonuç girilmesini beklemez). Kitapsız
/// bloklar ve konu anlatımı gibi soru içermeyen bloklar atlanır. Sayfalarının
/// yalnızca bir kısmı seçilmiş başlıklar işaretlenmez; [excluded] (optikte
/// "çözmedim" denenler) atlanır. Var olan sonuçlara dokunmak çağıranın işi
/// değildir: kayıt `saveIfAbsent` ile yapılır.
List<TestResult> sessionCoverage({
  required StudySession session,
  required List<Book> books,
  required DateTime now,
  Set<String> excluded = const {},
}) {
  final out = <TestResult>[];
  for (final item in session.items) {
    if (!item.hasQuestions || item.bookId == null) continue;
    final book = books.where((b) => b.id == item.bookId).firstOrNull;
    if (book == null) continue;
    final node = findNode(book, item.contentNodeId);
    final pages = item.pages.toSet();
    for (final leaf in node == null ? progressLeaves(book) : leavesUnder(node)) {
      if (excluded.contains(leaf.id)) continue;
      final covered = !leaf.hasPages ||
          pages.isEmpty ||
          [for (var p = leaf.pageStart!; p <= leaf.pageEnd!; p++) p].every(pages.contains);
      if (covered) out.add(TestResult(nodeId: leaf.id, bookId: book.id, solvedAt: now, sessionId: session.id));
    }
  }
  return out;
}
