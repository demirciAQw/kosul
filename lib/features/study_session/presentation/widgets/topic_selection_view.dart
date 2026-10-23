import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../../library/presentation/library_sheet.dart';
import '../../domain/study_session.dart';
import '../tree_selection.dart';
import '../../../library/domain/progress.dart';

typedef _Row = ({SelectableNode node, int depth, bool isPageStrip});

/// Kitap › Ünite › Konu › Sayfa ağacından çoklu seçim.
/// Hem oturum başlatmada ("BAŞLA") hem plana görev eklemede kullanılır.
class TopicSelectionView extends ConsumerStatefulWidget {
  const TopicSelectionView({
    super.key,
    required this.actionLabel,
    required this.actionIcon,
    required this.onSubmit,
    this.busy = false,
  });

  final String actionLabel;
  final IconData actionIcon;
  final ValueChanged<List<SessionItemDraft>> onSubmit;
  final bool busy;

  @override
  ConsumerState<TopicSelectionView> createState() => _TopicSelectionViewState();
}

class _TopicSelectionViewState extends ConsumerState<TopicSelectionView> {
  TreeSelection _selection = TreeSelection.empty;
  final _expanded = <String>{};

  List<Book>? _booksCache;
  List<SelectableNode> _roots = const [];

  /// Kitap akışı yeni liste yayınlamadıkça ağacı yeniden kurma.
  List<SelectableNode> _rootsFor(List<Book> books) {
    if (!identical(books, _booksCache)) {
      _booksCache = books;
      _roots = [for (final b in books) SelectableNode.fromBook(b)];
    }
    return _roots;
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    return library.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Kitaplar yüklenemedi: $e')),
      data: (books) => books.isEmpty ? const _EmptyLibrary() : _buildTree(_rootsFor(books)),
    );
  }

  Widget _buildTree(List<SelectableNode> roots) {
    // Kitap haritasındaki çözüldü bilgisi: çözülmüş kısımlar mavi tikle görünür.
    final results = ref.watch(testResultsProvider).value ?? const <String, TestResult>{};
    final states = _selection.computeStates(roots);
    final rows = _visibleRows(roots);
    final drafts = _selection.isEmpty ? const <SessionItemDraft>[] : _selection.toDrafts(roots, states);
    final estimate = drafts.fold<int>(0, (sum, d) => sum + (d.estimatedQuestions ?? 0));

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final node = row.node;
              if (row.isPageStrip) {
                return _PageStrip(
                  node: node,
                  depth: row.depth,
                  picked: _selection.pagesOf(node.id),
                  onToggle: (page) => setState(() => _selection = _selection.togglePage(node, page)),
                );
              }
              final state = states[node.id] ?? CheckState.none;
              final solved = _solvedOf(node, results);
              return _NodeTile(
                node: node,
                depth: row.depth,
                state: state,
                solved: solved.done,
                solvable: solved.total,
                expanded: _expanded.contains(node.id),
                onToggleExpand: () => setState(() {
                  if (!_expanded.remove(node.id)) _expanded.add(node.id);
                }),
                onCheck: () => setState(() {
                  _selection = _selection.setNode(node, selected: state != CheckState.all);
                }),
              );
            },
          ),
        ),
        _ActionBar(
          count: drafts.length,
          estimate: estimate,
          busy: widget.busy,
          label: widget.actionLabel,
          icon: widget.actionIcon,
          onPressed: drafts.isEmpty ? null : () => widget.onSubmit(drafts),
        ),
      ],
    );
  }

  /// Düz liste + ListView.builder: binlerce düğümde bile yalnızca görünen satırlar çizilir.
  List<_Row> _visibleRows(List<SelectableNode> roots) {
    final rows = <_Row>[];
    void add(SelectableNode n, int depth) {
      rows.add((node: n, depth: depth, isPageStrip: false));
      if (!_expanded.contains(n.id)) return;
      if (n.isPagePickable) {
        rows.add((node: n, depth: depth + 1, isPageStrip: true));
      } else {
        for (final c in n.children) {
          add(c, depth + 1);
        }
      }
    }

    for (final r in roots) {
      add(r, 0);
    }
    return rows;
  }
}

/// Düğümün altındaki testlerden kaçı kitap haritasında çözüldü.
({int done, int total}) _solvedOf(SelectableNode n, Map<String, TestResult> results) {
  final List<ContentNode> leaves;
  if (n.contentNodeId == null) {
    leaves = progressLeaves(n.book);
  } else {
    final c = findNode(n.book, n.contentNodeId);
    if (c == null) return (done: 0, total: 0);
    leaves = leavesUnder(c);
  }
  return (done: leaves.where((l) => results.containsKey(l.id)).length, total: leaves.length);
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.depth,
    required this.state,
    required this.expanded,
    required this.onToggleExpand,
    required this.onCheck,
    this.solved = 0,
    this.solvable = 0,
  });

  final SelectableNode node;
  final int depth;
  final CheckState state;

  /// Altındaki testlerden çözülenler / toplam. Seçimi etkilemez, yalnızca gösterir.
  final int solved;
  final int solvable;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = node.estimatedQuestions;
    final scheme = theme.colorScheme;
    final allSolved = solvable > 0 && solved == solvable;
    final subtitle = [
      if (node.pages.isNotEmpty) 's. ${formatPages(node.pages)}',
      if (estimate != null) node.exactQuestions != null ? '$estimate soru' : 'yaklaşık $estimate soru',
    ].join(', ');

    return InkWell(
      onTap: node.isExpandable ? onToggleExpand : onCheck,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 8.0 + depth * 20, end: 12),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              value: switch (state) {
                CheckState.all => true,
                CheckState.none => false,
                CheckState.partial => null,
              },
              onChanged: (_) => onCheck(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (depth == 0 ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)
                          ?.copyWith(color: allSolved ? scheme.primary : null),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
            if (allSolved)
              Tooltip(
                message: solvable == 1 ? 'Çözüldü' : 'Hepsi çözüldü',
                child: Icon(Icons.check_circle_rounded, color: scheme.primary, size: 22),
              )
            else if (solved > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$solved/$solvable',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (node.isExpandable)
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bir yaprağın sayfaları: tek tek seçilebilen çipler (ör. yalnızca 3. ve 5. test).
class _PageStrip extends StatelessWidget {
  const _PageStrip({required this.node, required this.depth, required this.picked, required this.onToggle});

  final SelectableNode node;
  final int depth;
  final Set<int> picked;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 16.0 + depth * 20, end: 16, bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final page in node.pages)
            FilterChip(
              label: Text('$page'),
              selected: picked.contains(page),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onToggle(page),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.estimate,
    required this.busy,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final int count;
  final int estimate;
  final bool busy;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count == 0
                      ? 'Konu ya da sayfa seç'
                      : '$count bölüm seçildi${estimate > 0 ? ', yaklaşık $estimate soru' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon),
                label: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends ConsumerWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Henüz kitap eklemedin', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Bir arkadaşının paylaştığı JSON şablonunu içe aktar; ünite, konu ve sayfalar tek dokunuşla gelsin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => importBookTemplateFlow(context, ref),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('JSON şablonu içe aktar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => showLibrarySheet(context),
              child: const Text('Hazır kitaplardan seç'),
            ),
          ],
        ),
      ),
    );
  }
}
