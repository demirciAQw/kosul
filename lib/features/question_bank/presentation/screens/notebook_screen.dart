import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../domain/question_card.dart';
import '../../domain/question_grouping.dart';
import '../../question_bank_providers.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/question_tile.dart';
import '../../../notes/notes_providers.dart';
import '../../../notes/presentation/notes_view.dart';
import 'question_viewer_screen.dart';
import '../../../notes/presentation/notes_export.dart';
import '../../../notes/domain/notes.dart';
import '../export_sheet.dart';

/// Hata / Boş / GK defteri: arama, açılır menü filtreleri ve ağaç yapılı liste.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> with SingleTickerProviderStateMixin {
  /// Sorular ve Notlar sekmeleri; düğme ve araçlar seçili sekmeye göre değişir.
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  bool get _onNotes => _tabs.index == 1;

  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(questionFilterProvider.notifier).setText(value);
    });
    setState(() {}); // temizle butonunu göster/gizle
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(questionFilterProvider);
    final groupBy = ref.watch(questionGroupByProvider);
    final groups = ref.watch(questionGroupsProvider);
    final gallery = ref.watch(notebookGalleryProvider);
    final cards = ref.watch(filteredQuestionsProvider);
    final due = ref.watch(dueCountProvider).value ?? 0;
    final incomplete = ref.watch(incompleteCountProvider);
    final selection = ref.watch(questionSelectionProvider);

    // Filtre menüsünden "Temizle" ile metin de sıfırlandıysa arama kutusunu boşalt.
    ref.listen(questionFilterProvider, (prev, next) {
      if (next.text == null && prev?.text != null && _search.text.isNotEmpty) _search.clear();
    });

    return PopScope(
      canPop: selection.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(questionSelectionProvider.notifier).clear();
      },
      child: Scaffold(
      appBar: selection.isNotEmpty
          ? AppBar(
              leading: IconButton(
                tooltip: 'Seçimi bırak',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ref.read(questionSelectionProvider.notifier).clear(),
              ),
              title: Text('${selection.length} seçili'),
              actions: [
                IconButton(
                  tooltip: 'Tümünü seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () => ref
                      .read(questionSelectionProvider.notifier)
                      .selectAll([for (final c in ref.read(filteredQuestionsProvider).value ?? const <QuestionCard>[]) c.id]),
                ),
                IconButton(
                  tooltip: 'Seçilenleri dışa aktar',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => _exportQuestions(selected: selection),
                ),
                IconButton(
                  tooltip: 'Seçilenleri sil',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _deleteSelected(selection),
                ),
              ],
            )
          : AppBar(
        title: const Text('Defterim'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.quiz_outlined), text: 'Sorular'),
            Tab(icon: Icon(Icons.sticky_note_2_outlined), text: 'Notlar'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dışa aktar',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _onNotes ? _exportNotes : () => _exportQuestions(),
          ),
          if (!_onNotes)
          IconButton(
            tooltip: 'Filtrele',
            onPressed: () => showQuestionFilterSheet(context),
            icon: Badge.count(
              count: filter.activeCount,
              isLabelVisible: filter.activeCount > 0,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: selection.isNotEmpty
          ? null
          : _onNotes
              ? FloatingActionButton.extended(
                  heroTag: 'notebook-note',
                  onPressed: () => context.push(AppRoutes.newNote, extra: ref.read(noteSubjectFilterProvider)),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Not ekle'),
                )
              : FloatingActionButton.extended(
                  heroTag: 'notebook-add',
                  onPressed: () => context.push(AppRoutes.newQuestion),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Soru ekle'),
                ),
      body: TabBarView(
        controller: _tabs,
        children: [
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Kaynak, konu, neden ya da not ara',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          ref.read(questionFilterProvider.notifier).setText(null);
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Tümü')),
                      ButtonSegment(value: true, label: Text('Güzel Sorular'), icon: Icon(Icons.star_rounded)),
                    ],
                    selected: {filter.starredOnly},
                    onSelectionChanged: (s) =>
                        ref.read(questionFilterProvider.notifier).setStarredOnly(s.first),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.review),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(due > 0 ? 'Tekrar ($due)' : 'Tekrar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.incompleteQuestions),
                    icon: Badge(
                      isLabelVisible: incomplete > 0,
                      smallSize: 8,
                      child: const Icon(Icons.pending_actions_outlined),
                    ),
                    label: Text(incomplete > 0 ? 'Eksikler ($incomplete)' : 'Eksikler'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Galeri'), icon: Icon(Icons.grid_view_rounded)),
                    ButtonSegment(value: false, label: Text('Gruplu'), icon: Icon(Icons.account_tree_outlined)),
                  ],
                  selected: {gallery},
                  onSelectionChanged: (s) => ref.read(notebookGalleryProvider.notifier).set(s.first),
                ),
                const Spacer(),
                if (gallery)
                  Text(
                    '${cards.value?.length ?? 0} soru',
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (!gallery)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<GroupBy>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [for (final g in GroupBy.values) ButtonSegment(value: g, label: Text(g.label))],
                  selected: {groupBy},
                  onSelectionChanged: (s) => ref.read(questionGroupByProvider.notifier).set(s.first),
                ),
              ),
            ),
          Expanded(
            child: gallery
                // Galeri: arama ve filtrelerin sonucu doğrudan sorular; dokununca tam
                // ekran açılır ve sonuçlar arasında kaydırılır.
                ? cards.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Sorular yüklenemedi: $e')),
                    data: (list) => list.isEmpty
                        ? _EmptyState(filtered: !filter.isUnfiltered)
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 3 / 4,
                            ),
                            itemCount: list.length,
                            itemBuilder: (context, i) => QuestionTile(
                              key: ValueKey(list[i].id),
                              card: list[i],
                              onOpen: () => QuestionViewerScreen.open(context, list, i),
                            ),
                          ),
                  )
                : groups.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Sorular yüklenemedi: $e')),
                    data: (list) => list.isEmpty
                        ? _EmptyState(filtered: !filter.isUnfiltered)
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 96),
                            children: [
                              for (final g in list)
                                _GroupTile(group: g, path: g.title, depth: 0, expanded: list.length <= 3),
                            ],
                          ),
                  ),
          ),
        ],
      ),
      const NotesView(),
        ],
      ),
    ),
    );
  }

  /// Sorular: seçili / bu arama / tüm defter kapsamlarıyla dışa aktarma paneli.
  Future<void> _exportQuestions({Set<String>? selected}) async {
    final filtered = ref.read(filteredQuestionsProvider).value ?? const <QuestionCard>[];
    final all = await ref.read(allQuestionsProvider.future);
    if (!mounted) return;
    final filter = ref.read(questionFilterProvider);
    final scopes = <String, List<QuestionCard>>{
      if (selected != null && selected.isNotEmpty) 'Seçili': [for (final c in all) if (selected.contains(c.id)) c],
      if (!filter.isUnfiltered) 'Bu arama ve filtre': filtered,
      'Tüm defter': all,
    };
    await showQuestionExportSheet(context, scopes: scopes);
  }

  /// Notlar: seçili dersin (ya da tüm derslerin) notları ve sayfa fotoğrafları.
  Future<void> _exportNotes() async {
    final notes = ref.read(notesProvider).value ?? const <StudyNote>[];
    final subject = ref.read(noteSubjectFilterProvider);
    final list = [for (final n in notes) if (subject == null || n.subject == subject) n];
    await exportNotes(context, ref, list, title: subject == null ? 'Tüm notlar' : '$subject defteri');
  }

  Future<void> _deleteSelected(Set<String> ids) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${ids.length} soruyu sil?'),
        content: const Text('Sorular, fotoğrafları ve tekrar geçmişleri silinir. Bu geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    final count = await ref.read(deleteQuestionCardProvider).many(ids);
    ref.read(questionSelectionProvider.notifier).clear();
    messenger.showSnackBar(SnackBar(content: Text('$count soru silindi.')));
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.path, required this.depth, this.expanded = false});

  final QuestionGroup group;
  final String path;
  final int depth;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: PageStorageKey<String>(path),
      initiallyExpanded: expanded,
      maintainState: false, // kapalı grubun kartları çizilmez: binlerce soruda bile akıcı
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsetsDirectional.only(start: 16 + depth * 14.0, end: 16),
      title: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: depth == 0 ? theme.textTheme.titleMedium : theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          Text('${group.total}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
      subtitle: group.subtitle == null ? null : Text(group.subtitle!),
      children: [
        for (final child in group.children)
          _GroupTile(group: child, path: '$path/${child.title}', depth: depth + 1),
        if (group.cards.isNotEmpty) _CardGrid(cards: group.cards),
      ],
    );
  }
}

class _CardGrid extends StatefulWidget {
  const _CardGrid({required this.cards});
  final List<QuestionCard> cards;

  @override
  State<_CardGrid> createState() => _CardGridState();
}

class _CardGridState extends State<_CardGrid> {
  static const _page = 30;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final total = widget.cards.length;
    final visible = total < _shown ? total : _shown;
    return Column(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3 / 4,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          children: [
            for (final card in widget.cards.take(visible)) QuestionTile(key: ValueKey(card.id), card: card),
          ],
        ),
        if (visible < total)
          TextButton(
            onPressed: () => setState(() => _shown += _page),
            child: Text('Daha fazla göster (${total - visible})'),
          ),
      ],
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filtered ? Icons.filter_alt_off_outlined : Icons.collections_bookmark_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(filtered ? 'Filtrene uyan soru yok' : 'Defterin henüz boş', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Filtreleri gevşetmeyi dene.'
                  : 'Bir testi bitirince yanlış ve boşlarını buraya ekle. Her soru çözümüyle birlikte saklanır.',
              textAlign: TextAlign.center,
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.read(questionFilterProvider.notifier).reset(),
                child: const Text('Filtreleri temizle'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
