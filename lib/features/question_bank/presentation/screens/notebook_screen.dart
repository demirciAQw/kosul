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
import '../../../tools/tools_providers.dart';
import '../../../curriculum/domain/yks.dart';
import '../../../../core/text/turkish_text.dart';

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

  /// Araçlar'dan "Yanlış defteri (PDF)" istendiyse paylaş paneli PDF'le açılır.
  bool _pdfScheduled = false;

  void _handlePdfRequest() {
    if (_pdfScheduled || !ref.read(notebookPdfRequestProvider)) return;
    _pdfScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notebookPdfRequestProvider.notifier).set(false);
      _pdfScheduled = false;
      if (!mounted) return;
      _tabs.index = 0;
      _exportQuestions(pdf: true);
    });
  }

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  /// Yazmayı bıraktıktan bir süre sonra arama veri setine yazılır.
  Timer? _logTimer;
  String? _loggedQuery;
  String? _searchId;
  DateTime? _searchAt;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _debounce?.cancel();
    _logTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(questionFilterProvider.notifier).setText(value);
    });
    _logTimer?.cancel();
    _logTimer = Timer(const Duration(milliseconds: 1500), _logSearch);
    setState(() {}); // temizle butonunu göster/gizle
  }

  /// Aramayı uygula (geçmişten ya da öneriden), klavyeyi kapat, geçmişe ekle.
  void _applyQuery(String q, {String? via}) {
    _search.text = q;
    _search.selection = TextSelection.collapsed(offset: q.length);
    _debounce?.cancel();
    ref.read(questionFilterProvider.notifier).setText(q);
    _searchFocus.unfocus();
    unawaited(ref.read(searchHistoryProvider.notifier).add(q));
    if (via != null) {
      unawaited(ref.read(searchLogProvider).append({
        'type': 'query_from_$via',
        'at': DateTime.now().toIso8601String(),
        'from': _loggedQuery,
        'to': q,
      }));
    }
    _logTimer?.cancel();
    _logTimer = Timer(const Duration(milliseconds: 600), _logSearch);
    setState(() {});
  }

  String _labelOf(QuestionCard c) =>
      [subjectName(c.subject), c.topicText, c.testLabel ?? c.sourceName, if (c.questionNo != null) 'S${c.questionNo}']
          .whereType<String>()
          .join(' · ');

  /// Veri seti: arama metni, akıllı arama durumu, öneri ve ilk 20 sonuç.
  void _logSearch() {
    if (!mounted) return;
    final q = _search.text.trim();
    if (q.isEmpty || q == _loggedQuery) return;
    final smart = ref.read(smartSearchResultProvider).value;
    final cards = ref.read(filteredQuestionsProvider).value ?? const <QuestionCard>[];
    _loggedQuery = q;
    _searchAt = DateTime.now();
    _searchId = 's${_searchAt!.microsecondsSinceEpoch}';
    unawaited(ref.read(searchLogProvider).append({
      'type': 'search',
      'id': _searchId,
      'at': _searchAt!.toIso8601String(),
      'query': q,
      'normalized': normalizeTr(q),
      'smart': ref.read(smartSearchEnabledProvider),
      'suggestion': smart?.suggestion,
      'count': cards.length,
      'results': [
        for (final (i, c) in cards.take(20).indexed)
          {'rank': i + 1, 'id': c.id, 'score': smart?.scores[c.id], 'label': _labelOf(c)},
      ],
    }));
  }

  /// Arama sonuçlarından birine gidildi: hangi aramadan, kaçıncı sonuç.
  void _logOpen(QuestionCard card, int index) {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    if (q != _loggedQuery) _logSearch();
    final smart = ref.read(smartSearchResultProvider).value;
    unawaited(ref.read(searchLogProvider).append({
      'type': 'open',
      'search': _searchId,
      'at': DateTime.now().toIso8601String(),
      'query': q,
      'card': card.id,
      'rank': index + 1,
      'score': smart?.scores[card.id],
      'label': _labelOf(card),
      'msAfterSearch': _searchAt == null ? null : DateTime.now().difference(_searchAt!).inMilliseconds,
    }));
    unawaited(ref.read(searchHistoryProvider.notifier).add(q));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notebookPdfRequestProvider);
    _handlePdfRequest();
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
      CustomScrollView(
        // Üst kısım (arama, filtreler, görünüm) aşağı kaydırınca yukarı çekilir;
        // sorular bütün ekranı kullanır.
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: _onChanged,
                      onSubmitted: (q) {
                        if (q.trim().isNotEmpty) _applyQuery(q.trim());
                      },
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
                                  _loggedQuery = null;
                                  ref.read(questionFilterProvider.notifier).setText(null);
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                  ),
                  _SearchAssist(
                    query: _search.text,
                    focused: _searchFocus.hasFocus,
                    onApply: (q, via) => _applyQuery(q, via: via),
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
              ],
            ),
          ),
          ..._contentSlivers(gallery: gallery, cards: cards, groups: groups, filter: filter),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
      const NotesView(),
        ],
      ),
    ),
    );
  }

  /// Sorular: seçili / bu arama / tüm defter kapsamlarıyla dışa aktarma paneli.
  Future<void> _exportQuestions({Set<String>? selected, bool pdf = false}) async {
    final filtered = ref.read(filteredQuestionsProvider).value ?? const <QuestionCard>[];
    final all = await ref.read(allQuestionsProvider.future);
    if (!mounted) return;
    final filter = ref.read(questionFilterProvider);
    final scopes = <String, List<QuestionCard>>{
      if (selected != null && selected.isNotEmpty) 'Seçili': [for (final c in all) if (selected.contains(c.id)) c],
      if (!filter.isUnfiltered) 'Bu arama ve filtre': filtered,
      'Tüm defter': all,
    };
    await showQuestionExportSheet(context, scopes: scopes, pdf: pdf);
  }

  /// Notlar: seçili dersin (ya da tüm derslerin) notları ve sayfa fotoğrafları.
  Future<void> _exportNotes() async {
    final notes = ref.read(notesProvider).value ?? const <StudyNote>[];
    final subject = ref.read(noteSubjectFilterProvider);
    final list = [for (final n in notes) if (subject == null || n.subject == subject) n];
    await exportNotes(context, ref, list, title: subject == null ? 'Tüm notlar' : '$subject defteri');
  }

  /// Grupların açık/kapalı durumu (yol → açık mı). Yoksa varsayılan kullanılır.
  final _expanded = <String, bool>{};

  List<Widget> _contentSlivers({
    required bool gallery,
    required AsyncValue<List<QuestionCard>> cards,
    required AsyncValue<List<QuestionGroup>> groups,
    required QuestionFilter filter,
  }) {
    Widget fill(Widget child) => SliverFillRemaining(hasScrollBody: false, child: child);
    if (gallery) {
      // Galeri: arama ve filtrelerin sonucu doğrudan sorular; dokununca tam
      // ekran açılır ve sonuçlar arasında kaydırılır.
      return cards.when(
        loading: () => [fill(const Center(child: CircularProgressIndicator()))],
        error: (e, _) => [fill(Center(child: Text('Sorular yüklenemedi: $e')))],
        data: (list) => list.isEmpty
            ? [fill(_EmptyState(filtered: !filter.isUnfiltered))]
            : [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverGrid.builder(
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
                      onOpen: () {
                        _logOpen(list[i], i);
                        QuestionViewerScreen.open(context, list, i);
                      },
                    ),
                  ),
                ),
              ],
      );
    }
    return groups.when(
      loading: () => [fill(const Center(child: CircularProgressIndicator()))],
      error: (e, _) => [fill(Center(child: Text('Sorular yüklenemedi: $e')))],
      data: (list) => list.isEmpty
          ? [fill(_EmptyState(filtered: !filter.isUnfiltered))]
          : [for (final g in list) ..._groupSlivers(g, g.title, 0, defaultOpen: list.length <= 3)],
    );
  }

  /// Grup başlığı + (açıksa) alt gruplar ve kartlar. Izgara tembel: yalnızca
  /// ekrandaki kartlar çizilir.
  List<Widget> _groupSlivers(QuestionGroup g, String path, int depth, {bool defaultOpen = false}) {
    final open = _expanded[path] ?? defaultOpen;
    return [
      SliverToBoxAdapter(
        child: _GroupHeader(
          group: g,
          depth: depth,
          open: open,
          onTap: () => setState(() => _expanded[path] = !open),
        ),
      ),
      if (open) ...[
        for (final child in g.children) ..._groupSlivers(child, '$path/${child.title}', depth + 1),
        if (g.cards.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3 / 4,
              ),
              itemCount: g.cards.length,
              itemBuilder: (context, i) {
                final card = g.cards[i];
                return QuestionTile(
                  key: ValueKey(card.id),
                  card: card,
                  onOpen: () {
                    final all = ref.read(filteredQuestionsProvider).value ?? const <QuestionCard>[];
                    _logOpen(card, all.indexWhere((c) => c.id == card.id));
                    context.push(AppRoutes.question(card.id));
                  },
                );
              },
            ),
          ),
      ],
    ];
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

/// Grup başlığı: dokununca açılır/kapanır. Kartlar başlığın altında ayrı,
/// tembel bir ızgarada çizilir (iç içe kaydırma yok).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.depth, required this.open, required this.onTap});
  final QuestionGroup group;
  final int depth;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16 + depth * 14.0, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: depth == 0 ? theme.textTheme.titleMedium : theme.textTheme.titleSmall,
                  ),
                  if (group.subtitle != null)
                    Text(group.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${group.total}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more_rounded),
            ),
          ],
        ),
      ),
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

/// Arama kutusunun altı: yazım hatasında öneri, odaktayken son aramalar.
class _SearchAssist extends ConsumerWidget {
  const _SearchAssist({required this.query, required this.focused, required this.onApply});
  final String query;
  final bool focused;

  /// Seçilen arama ve nereden geldiği ("history" ya da "suggestion").
  final void Function(String query, String via) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = query.trim();
    final history = ref.watch(searchHistoryProvider).value ?? const <String>[];
    final suggestion = q.isEmpty ? null : ref.watch(smartSearchResultProvider).value?.suggestion;
    final nq = normalizeTr(q);
    final matches = [
      for (final h in history)
        if (h != q && (q.isEmpty || normalizeTr(h).contains(nq))) h,
    ].take(6).toList();
    final showHistory = focused && matches.isNotEmpty;
    if (suggestion == null && !showHistory) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (suggestion != null)
            ActionChip(
              avatar: Icon(Icons.auto_fix_high_rounded, size: 18, color: scheme.primary),
              label: Text('Bunu mu demek istedin: $suggestion'),
              onPressed: () => onApply(suggestion, 'suggestion'),
            ),
          if (showHistory)
            Card(
              margin: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Son aramalar',
                              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        TextButton(
                          onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                          child: const Text('Temizle'),
                        ),
                      ],
                    ),
                  ),
                  for (final h in matches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: 'Geçmişten sil',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => ref.read(searchHistoryProvider.notifier).remove(h),
                      ),
                      onTap: () => onApply(h, 'history'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
