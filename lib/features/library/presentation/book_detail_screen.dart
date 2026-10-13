import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/question_bank_providers.dart';
import '../domain/library.dart';
import '../domain/progress.dart';
import '../library_providers.dart';
import 'library_sheet.dart';
import 'widgets/progress_widgets.dart';

/// Kitaptaki yanlış/boş kart sayıları: test düğümü → adet.
final _mistakesByNodeProvider = StreamProvider.family<Map<String, int>, String>((ref, bookId) {
  final filter = QuestionFilter(bookId: bookId, statuses: const {QuestionStatus.wrong, QuestionStatus.blank});
  return ref.watch(questionCardRepositoryProvider).watch(filter).map((cards) {
    final out = <String, int>{};
    for (final c in cards) {
      final id = c.contentNodeId;
      if (id != null) out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  });
});

/// Kitap ayrıntısı: ilerleme, kitap haritası ve ünite ünite test listesi.
/// Testler buradan elle "çözüldü / çözülmedi" yapılabilir.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookByIdProvider(bookId));
    if (book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ref.watch(libraryProvider).isLoading
              ? const CircularProgressIndicator()
              : const Text('Kitap bulunamadı.'),
        ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final results = ref.watch(testResultsProvider).value ?? const <String, TestResult>{};
    final mistakes = ref.watch(_mistakesByNodeProvider(bookId)).value ?? const <String, int>{};
    final p = bookProgress(book, results);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) => switch (action) {
              'rename' => _rename(context, ref, book),
              'share' => exportBookTemplateFlow(ref, ScaffoldMessenger.of(context), book),
              _ => _delete(context, ref, book),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Adını düzenle')),
              PopupMenuItem(value: 'share', child: Text('Şablonu paylaş (JSON)')),
              PopupMenuItem(value: 'delete', child: Text('Kitabı sil')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              ProgressRing(value: p.ratio, size: 96, stroke: 9),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p.doneLeaves} ${p.unitName} bitti', style: theme.textTheme.titleMedium),
                    Text('${p.remainingLeaves} ${p.unitName} duruyor', style: theme.textTheme.bodyMedium),
                    if (p.totalQuestions > 0)
                      Text('${p.doneQuestions} / ${p.totalQuestions} soru', style: theme.textTheme.bodySmall),
                    if (p.answered > 0) ...[
                      const SizedBox(height: 8),
                      ResultBar(correct: p.correct, wrong: p.wrong, blank: p.blank),
                      const SizedBox(height: 4),
                      Text(
                        '${p.correct} D, ${p.wrong} Y, ${p.blank} B'
                        '${p.accuracy == null ? '' : ', başarı %${(p.accuracy! * 100).round()}'}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Kitap haritası', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          BookMap(book: book, results: results),
          const BookMapLegend(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Testler', style: theme.textTheme.titleSmall)),
              Text(
                'Kutucukla çözüldü işaretle',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final root in book.roots)
            _NodeSection(book: book, node: root, results: results, mistakes: mistakes, depth: 0),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Book book) async {
    final value = await showDialog<({String title, String publisher})>(
      context: context,
      builder: (_) => _RenameDialog(title: book.title, publisher: book.publisher ?? ''),
    );
    if (value == null || value.title.trim().isEmpty) return;
    await ref.read(libraryRepositoryProvider).rename(
          book.id,
          title: value.title.trim(),
          publisher: value.publisher.trim().isEmpty ? null : value.publisher.trim(),
        );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kitabı sil?'),
        content: const Text(
          'Kitap, içindekiler ve test ilerlemesi silinir. Bu kitaptan eklediğin sorular '
          'defterinde kalır, yalnızca kitapla bağı kopar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final router = GoRouter.of(context);
    await ref.read(libraryRepositoryProvider).delete(book.id);
    router.go(AppRoutes.books);
  }
}

class _NodeSection extends ConsumerWidget {
  const _NodeSection({
    required this.book,
    required this.node,
    required this.results,
    required this.mistakes,
    required this.depth,
  });

  final Book book;
  final ContentNode node;
  final Map<String, TestResult> results;
  final Map<String, int> mistakes;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (node.children.isEmpty) {
      return _LeafTile(book: book, node: node, result: results[node.id], mistakes: mistakes[node.id] ?? 0);
    }
    final theme = Theme.of(context);
    final prog = nodeProgress(node, results);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('node-${node.id}'),
        tilePadding: EdgeInsets.only(left: depth * 12.0, right: 4),
        childrenPadding: EdgeInsets.only(left: depth * 12.0 + 4),
        title: Text(node.title, style: depth == 0 ? theme.textTheme.titleSmall : theme.textTheme.bodyLarge),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: prog.total == 0 ? 0 : prog.done / prog.total,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text('${prog.done}/${prog.total}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        children: [
          for (final c in node.children)
            _NodeSection(book: book, node: c, results: results, mistakes: mistakes, depth: depth + 1),
        ],
      ),
    );
  }
}

class _LeafTile extends ConsumerWidget {
  const _LeafTile({required this.book, required this.node, required this.result, required this.mistakes});

  final Book book;
  final ContentNode node;
  final TestResult? result;
  final int mistakes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = result;
    final details = [
      if (node.questionCount != null) '${node.questionCount} soru',
      if (r == null)
        'çözülmedi'
      else if (r.hasCounts)
        '${r.correct ?? 0} D, ${r.wrong ?? 0} Y, ${r.blank ?? 0} B'
      else
        'çözüldü',
    ].join(', ');
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 8, right: 0),
      onTap: () => context.push(AppRoutes.bookTest(book.id, node.id)),
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: testColor(context, r), borderRadius: BorderRadius.circular(4)),
      ),
      title: Text(node.title),
      subtitle: Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mistakes > 0)
            Tooltip(
              message: 'Defterdeki yanlış ve boşlar',
              child: Badge(
                label: Text('$mistakes'),
                backgroundColor: theme.colorScheme.error,
              ),
            ),
          Checkbox(
            value: r != null,
            onChanged: (v) => toggleSolved(context, ref, book: book, node: node, current: r, solved: v ?? false),
          ),
        ],
      ),
    );
  }
}

/// Testi elle çözüldü/çözülmedi yapar. "Çözülmedi"de sonuç (sayılar) silinir;
/// "Geri al" ile geri gelir. Defterdeki sorular etkilenmez.
Future<void> toggleSolved(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required ContentNode node,
  required TestResult? current,
  required bool solved,
}) async {
  final repo = ref.read(testProgressRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (solved) {
    await repo.save(TestResult(nodeId: node.id, bookId: book.id, solvedAt: ref.read(clockProvider)()));
    return;
  }
  if (current == null) return;
  await repo.clear(node.id);
  messenger.showSnackBar(SnackBar(
    content: Text('${node.title} çözülmedi olarak işaretlendi.'),
    action: SnackBarAction(label: 'Geri al', onPressed: () => repo.save(current)),
  ));
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.publisher});
  final String title;
  final String publisher;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _publisher = TextEditingController(text: widget.publisher);

  @override
  void dispose() {
    _title.dispose();
    _publisher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kitabı düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Kitap adı')),
            const SizedBox(height: 12),
            TextField(controller: _publisher, decoration: const InputDecoration(labelText: 'Yayınevi')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (title: _title.text, publisher: _publisher.text)),
            child: const Text('Kaydet'),
          ),
        ],
      );
}
