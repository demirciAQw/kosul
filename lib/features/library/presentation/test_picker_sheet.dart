import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/turkish_text.dart';
import '../domain/library.dart';
import '../domain/progress.dart';
import '../library_providers.dart';

/// Kitaptan test (yaprak başlık) seçtirir; ünitelere göre gruplu, aranabilir.
/// Çözülen testler işaretli görünür. Vazgeçilirse null.
Future<ContentNode?> pickBookTest(BuildContext context, Book book) => showModalBottomSheet<ContentNode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _TestPicker(book: book),
    );

class _TestPicker extends ConsumerStatefulWidget {
  const _TestPicker({required this.book});
  final Book book;

  @override
  ConsumerState<_TestPicker> createState() => _TestPickerState();
}

class _TestPickerState extends ConsumerState<_TestPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = ref.watch(testResultsProvider).value ?? const <String, TestResult>{};
    final q = normalizeTr(_query);
    final rows = <Widget>[];
    for (final root in widget.book.roots) {
      final leaves = [
        for (final l in leavesUnder(root))
          if (q.isEmpty || normalizeTr(nodeLabel(widget.book, l.id)).contains(q)) l,
      ];
      if (leaves.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(root.title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ));
      for (final leaf in leaves) {
        final done = results[leaf.id];
        final path = pathTo(widget.book, leaf.id);
        final middle = path.length > 2 ? path.sublist(1, path.length - 1).map((n) => n.title).join(' › ') : null;
        rows.add(ListTile(
          dense: true,
          leading: Icon(
            done == null ? Icons.radio_button_unchecked_rounded : Icons.check_circle_rounded,
            color: done == null ? theme.colorScheme.outline : theme.colorScheme.primary,
          ),
          title: Text(leaf.title),
          subtitle: Text([
            if (middle != null) middle,
            if (leaf.questionCount != null) '${leaf.questionCount} soru',
            if (leaf.hasPages) 's. ${leaf.pageStart}–${leaf.pageEnd}',
          ].join(', ')),
          onTap: () => Navigator.pop(context, leaf),
        ));
      }
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Test ara (ör. "odaklanma 3")',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Flexible(
            child: rows.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Eşleşen test yok.'))
                : ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: rows),
          ),
        ],
      ),
    );
  }
}
