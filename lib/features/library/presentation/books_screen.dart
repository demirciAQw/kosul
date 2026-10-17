import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../domain/library.dart';
import '../domain/progress.dart';
import '../library_providers.dart';
import 'library_sheet.dart';
import 'widgets/progress_widgets.dart';

/// Kitaplar sekmesi: her kitabın ne kadarı bitti, ne kadarı duruyor.
/// Kitap kategorisi: sınav türüne ve yayıncıya göre üç sekme.
enum BookShelf {
  tyt('TYT'),
  ayt('AYT'),
  meb('MEB');

  const BookShelf(this.label);
  final String label;

  /// MEB ders kitapları ayrı rafta; diğerleri sınav türüne göre.
  static BookShelf of(Book book) {
    if ((book.publisher ?? '').trim().toUpperCase() == 'MEB') return BookShelf.meb;
    return book.examType == 'TYT' ? BookShelf.tyt : BookShelf.ayt;
  }
}

/// Kitaplar sekmesi: TYT, AYT ve MEB kitapları ayrı sekmelerde; her kitabın ne
/// kadarı bitti, ne kadarı duruyor.
class BooksScreen extends ConsumerWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(bookProgressProvider);
    final all = progress.value ?? const <BookProgress>[];
    int count(BookShelf s) => all.where((p) => BookShelf.of(p.book) == s).length;

    return DefaultTabController(
      length: BookShelf.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kitaplarım'),
          bottom: TabBar(
            tabs: [
              for (final s in BookShelf.values)
                Tab(text: count(s) == 0 ? s.label : '${s.label} (${count(s)})'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'books-add',
          onPressed: () => showLibrarySheet(context),
          icon: const Icon(Icons.library_add_outlined),
          label: const Text('Kitap ekle'),
        ),
        body: progress.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Kitaplar yüklenemedi: $e')),
          data: (list) => TabBarView(
            children: [
              for (final shelf in BookShelf.values)
                _ShelfView(shelf: shelf, items: [for (final p in list) if (BookShelf.of(p.book) == shelf) p]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfView extends StatelessWidget {
  const _ShelfView({required this.shelf, required this.items});
  final BookShelf shelf;
  final List<BookProgress> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyBooks(shelf: shelf);
    final done = items.fold<int>(0, (a, p) => a + p.doneLeaves);
    final total = items.fold<int>(0, (a, p) => a + p.totalLeaves);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _Overview(done: done, total: total, books: items.length),
        const SizedBox(height: 12),
        for (final p in items) _BookCard(progress: p),
      ],
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
  const _EmptyBooks({required this.shelf});
  final BookShelf shelf;

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
            Text('${shelf.label} rafında kitap yok', style: theme.textTheme.titleMedium),
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
