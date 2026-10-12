import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/library.dart';
import '../domain/study_session.dart';

enum CheckState { none, partial, all }

/// Seçim ağacının görünüm modeli: kökler kitaplardır, altında içindekiler.
/// Birden fazla kitaptan aynı oturuma konu seçilebilir (karma tekrar).
class SelectableNode {
  SelectableNode._({
    required this.id,
    required this.title,
    required this.book,
    required this.pages,
    required this.children,
    this.contentNodeId,
    this.mebNodeId,
  });

  factory SelectableNode.fromBook(Book book) {
    final children = [for (final r in book.roots) SelectableNode._fromContent(r, book)];
    return SelectableNode._(
      id: 'book:${book.id}',
      title: book.title,
      book: book,
      children: children,
      pages: children.isEmpty
          ? [for (var p = 1; p <= book.pageCount; p++) p]
          : _union(children),
    );
  }

  factory SelectableNode._fromContent(ContentNode n, Book book) {
    final children = [for (final c in n.children) SelectableNode._fromContent(c, book)];
    return SelectableNode._(
      id: n.id,
      title: n.title,
      book: book,
      contentNodeId: n.id,
      mebNodeId: n.mebNodeId,
      children: children,
      pages: n.hasPages
          ? [for (var p = n.pageStart!; p <= n.pageEnd!; p++) p]
          : _union(children),
    );
  }

  /// Bu sayıdan uzun yapraklarda sayfa çipleri gösterilmez (yalnızca tümü seçilir).
  static const maxPickablePages = 80;

  final String id;
  final String title;
  final Book book;
  final String? contentNodeId; // kitap kökünde null
  final String? mebNodeId;
  final List<int> pages;
  final List<SelectableNode> children;

  bool get isLeaf => children.isEmpty;
  bool get isPagePickable => isLeaf && pages.isNotEmpty && pages.length <= maxPickablePages;
  bool get isExpandable => !isLeaf || isPagePickable;
  int? get estimatedQuestions => pages.isEmpty ? null : book.estimateQuestions(pages.length);

  Iterable<SelectableNode> get leaves sync* {
    if (isLeaf) {
      yield this;
    } else {
      for (final c in children) {
        yield* c.leaves;
      }
    }
  }

  static List<int> _union(List<SelectableNode> nodes) =>
      {for (final c in nodes) ...c.pages}.toList()..sort();
}

/// Değişmez seçim durumu. Anahtar: yaprak kimliği; değer: seçili sayfalar.
/// Sayfa çipi olmayan yapraklarda değer boş kümedir (varlığı = tamamı seçili).
class TreeSelection {
  const TreeSelection._(this._picked);
  static const empty = TreeSelection._(<String, Set<int>>{});

  final Map<String, Set<int>> _picked;

  bool get isEmpty => _picked.isEmpty;
  Set<int> pagesOf(String leafId) => _picked[leafId] ?? const {};

  /// Bir düğüme tıklamak tüm alt ağacını seçer/bırakır.
  TreeSelection setNode(SelectableNode node, {required bool selected}) {
    final next = {..._picked};
    for (final leaf in node.leaves) {
      if (selected) {
        next[leaf.id] = leaf.isPagePickable ? leaf.pages.toSet() : <int>{};
      } else {
        next.remove(leaf.id);
      }
    }
    return TreeSelection._(next);
  }

  TreeSelection togglePage(SelectableNode leaf, int page) {
    final pages = {...pagesOf(leaf.id)};
    if (!pages.remove(page)) pages.add(page);
    final next = {..._picked};
    if (pages.isEmpty) {
      next.remove(leaf.id);
    } else {
      next[leaf.id] = pages;
    }
    return TreeSelection._(next);
  }

  /// Tek geçişte (post-order) tüm düğümlerin üç durumlu onay değerleri.
  Map<String, CheckState> computeStates(List<SelectableNode> roots) {
    final states = <String, CheckState>{};
    CheckState visit(SelectableNode n) {
      final CheckState state;
      if (n.isLeaf) {
        final picked = _picked[n.id];
        state = picked == null
            ? CheckState.none
            : (!n.isPagePickable || picked.length == n.pages.length)
                ? CheckState.all
                : CheckState.partial;
      } else {
        var all = true, none = true;
        for (final c in n.children) {
          final cs = visit(c);
          all = all && cs == CheckState.all;
          none = none && cs == CheckState.none;
        }
        state = all ? CheckState.all : (none ? CheckState.none : CheckState.partial);
      }
      states[n.id] = state;
      return state;
    }

    for (final r in roots) {
      visit(r);
    }
    return states;
  }

  /// "Ne işaretlediysen onu raporlarsın": tamamı seçili en üst düğümler tek
  /// blok olur; böylece bir üniteyi seçen 30 alt konu için sonuç girmez.
  List<SessionItemDraft> toDrafts(List<SelectableNode> roots, Map<String, CheckState> states) {
    final drafts = <SessionItemDraft>[];
    void walk(SelectableNode n, List<String> path) {
      final state = states[n.id] ?? CheckState.none;
      if (state == CheckState.none) return;
      final label = [...path, n.title];
      if (state == CheckState.all || n.isLeaf) {
        final pages = state == CheckState.all ? n.pages : (pagesOf(n.id).toList()..sort());
        drafts.add(SessionItemDraft(
          label: label.join(' › '),
          bookId: n.book.id,
          contentNodeId: n.contentNodeId,
          mebNodeId: n.mebNodeId,
          pages: pages,
          estimatedQuestions: pages.isEmpty ? null : n.book.estimateQuestions(pages.length),
          subject: subjectKey(n.book.examType, n.book.subject),
        ));
        return;
      }
      for (final c in n.children) {
        walk(c, label);
      }
    }

    for (final r in roots) {
      walk(r, const []);
    }
    return drafts;
  }
}
