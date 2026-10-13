import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../domain/progress.dart';
import '../library_providers.dart';
import 'library_sheet.dart';
import 'widgets/progress_widgets.dart';

/// Kitaplar sekmesi: her kitabın ne kadarı bitti, ne kadarı duruyor.
class BooksScreen extends ConsumerWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(bookProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kitaplarım')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'books-add',
        onPressed: () => showLibrarySheet(context),
        icon: const Icon(Icons.library_add_outlined),
        label: const Text('Kitap ekle'),
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Kitaplar yüklenemedi: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyBooks();
          final done = list.fold<int>(0, (a, p) => a + p.doneLeaves);
          final total = list.fold<int>(0, (a, p) => a + p.totalLeaves);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _Overview(done: done, total: total, books: list.length),
              const SizedBox(height: 12),
              for (final p in list) _BookCard(progress: p),
            ],
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.done, required this.total, required this.books});
  final int done;
  final int total;
  final int books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ProgressRing(value: total == 0 ? 0 : done / total, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$books kitap', style: theme.textTheme.titleMedium),
                  Text('$done / $total test ya da başlık bitti', style: theme.textTheme.bodyMedium),
                  Text('${total - done} tane duruyor', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.progress});
  final BookProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = progress;
    final b = p.book;
    final now = ref.watch(clockProvider)();
    final last = p.lastSolvedAt;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.book(b.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ProgressRing(value: p.ratio),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      [b.examType, b.subject, if (b.publisher != null) b.publisher!].join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p.doneLeaves}/${p.totalLeaves} ${p.unitName} bitti, ${p.remainingLeaves} duruyor',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (p.answered > 0) ...[
                      const SizedBox(height: 6),
                      ResultBar(correct: p.correct, wrong: p.wrong, blank: p.blank, height: 6),
                      const SizedBox(height: 4),
                      Text(
                        '${p.correct} D, ${p.wrong} Y, ${p.blank} B'
                        '${p.accuracy == null ? '' : ', başarı %${(p.accuracy! * 100).round()}'}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    if (last != null)
                      Text(
                        'Son çalışma: ${formatRelativeDay(last, now)}',
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBooks extends StatelessWidget {
  const _EmptyBooks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Henüz kitap yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Hazır kitaplardan ekle ya da JSON şablonu içe aktar. Çözdüğün testler burada '
              'kitap kitap görünür.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showLibrarySheet(context),
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Kitap ekle'),
            ),
          ],
        ),
      ),
    );
  }
}
