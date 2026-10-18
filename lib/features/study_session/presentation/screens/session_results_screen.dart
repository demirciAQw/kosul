import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';
import '../session_coverage.dart';
import '../session_quick_mark.dart';

/// "Eksiklerini doldur": bitmiş oturumun D/Y/B sonuçları. "Sonra" ile
/// ertelenebilir; rozet, sonuçlar kaydedilene kadar ana ekranda kalır.
///
/// Her blokta iki yol var: sayıları elle yazmak ya da optik formda yanlış ve
/// boşlara dokunmak (sayılar kendiliğinden dolar, sorular deftere düşer).
class SessionResultsScreen extends ConsumerStatefulWidget {
  const SessionResultsScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends ConsumerState<SessionResultsScreen> {
  final _fields = <String, _ResultFields>{};

  /// Optikte "çözmedim" denen testler: otomatik "çözüldü" işaretlenmez.
  final _excluded = <String>{};
  bool _saving = false;

  _ResultFields _fieldsFor(SessionItem item) => _fields.putIfAbsent(item.id, () => _ResultFields(item));

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionByIdProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sonuçları gir'),
        actions: [TextButton(onPressed: () => context.go(AppRoutes.home), child: const Text('Sonra'))],
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Oturum okunamadı: $e')),
        data: (s) => s == null ? const Center(child: Text('Oturum bulunamadı.')) : _body(s),
      ),
    );
  }

  Widget _body(StudySession s) {
    final questionItems = [for (final i in s.items) if (i.hasQuestions) i];
    final fields = [for (final item in questionItems) _fieldsFor(item)];
    final duration = s.elapsedAt(DateTime.now());
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([for (final f in fields) ...f.listenables]),
                builder: (context, _) {
                  final solved = fields.fold<int>(0, (sum, f) => sum + f.solved);
                  return _Summary(
                    duration: duration,
                    solved: solved,
                    secondsPerQuestion: solved == 0 ? null : duration.inSeconds / solved,
                  );
                },
              ),
              const SizedBox(height: 12),
              for (final item in s.items)
                item.hasQuestions
                    ? _ItemCard(
                        item: item,
                        fields: _fieldsFor(item),
                        onMark: () => _mark(s, item),
                        onAddQuestion: () => _addQuestion(s, item),
                      )
                    : _NoQuestionsCard(item: item),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(s),
                child: const Text('Sonuçları kaydet'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double? _currentSecondsPerQuestion(StudySession s) {
    final solved = _fields.values.fold<int>(0, (sum, f) => sum + f.solved);
    return solved > 0 ? s.elapsedAt(DateTime.now()).inSeconds / solved : null;
  }

  /// Optik form: işaretlenen sayılar alanlara yazılır, sorular deftere düşer.
  Future<void> _mark(StudySession s, SessionItem item) async {
    final result = await markSessionItem(context, ref, s, item);
    if (result == null || !mounted) return;
    for (final section in result.sections) {
      section.included ? _excluded.remove(section.key) : _excluded.add(section.key);
    }
    _fieldsFor(item).set(result.correct, result.wrong, result.blank);
  }

  /// Fotoğraflı tam kayıt: kaynak, konu, testteki soru sayısı ve süre otomatik gelir.
  void _addQuestion(StudySession s, SessionItem item) {
    final itemSolved = _fieldsFor(item).solved;
    context.push(
      AppRoutes.newQuestion,
      extra: sessionItemPrefill(
        ref,
        s,
        item,
        avgSecondsPerQuestion: _currentSecondsPerQuestion(s),
        testTotalQuestions: itemSolved > 0 ? itemSolved : null,
      ),
    );
  }

  /// Bu oturumda çalışılan testleri/başlıkları kitap haritasında "çözüldü" yapar.
  /// Daha önce sonucu olanlara dokunmaz; optikte dışarıda bırakılanları atlar;
  /// sayfalarının yalnızca bir kısmı seçilmiş başlıkları işaretlemez.
  Future<void> _markCoverage(StudySession s) => ref.read(testProgressRepositoryProvider).saveIfAbsent(
        sessionCoverage(
          session: s,
          books: ref.read(libraryProvider).value ?? const <Book>[],
          now: ref.read(clockProvider)(),
          excluded: _excluded,
        ),
      );

  Future<void> _save(StudySession s) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(submitSessionResultsProvider).call(s.id, [
        for (final item in s.items)
          if (item.hasQuestions) _fieldsFor(item).toResult(item.id),
      ]);
      await _markCoverage(s);
      messenger.showSnackBar(const SnackBar(content: Text('Sonuçlar kaydedildi.')));
      router.go(AppRoutes.home);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sonuçlar kaydedilemedi: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ResultFields {
  _ResultFields(SessionItem item)
      : correct = TextEditingController(text: item.correct?.toString() ?? ''),
        wrong = TextEditingController(text: item.wrong?.toString() ?? ''),
        blank = TextEditingController(text: item.blank?.toString() ?? '');

  final TextEditingController correct;
  final TextEditingController wrong;
  final TextEditingController blank;

  static int _v(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int get solved => _v(correct) + _v(wrong) + _v(blank);
  List<Listenable> get listenables => [correct, wrong, blank];

  void set(int c, int w, int b) {
    correct.text = '$c';
    wrong.text = '$w';
    blank.text = '$b';
  }

  ItemResult toResult(String itemId) =>
      ItemResult(itemId: itemId, correct: _v(correct), wrong: _v(wrong), blank: _v(blank));

  void dispose() {
    correct.dispose();
    wrong.dispose();
    blank.dispose();
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.duration, required this.solved, required this.secondsPerQuestion});
  final Duration duration;
  final int solved;
  final double? secondsPerQuestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleLarge),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            stat(formatDuration(duration), 'süre'),
            stat('$solved', 'çözülen soru'),
            stat(secondsPerQuestion == null ? '–' : '${secondsPerQuestion!.round()} sn', 'soru başına'),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.fields,
    required this.onMark,
    required this.onAddQuestion,
  });

  final SessionItem item;
  final _ResultFields fields;
  final VoidCallback onMark;
  final VoidCallback onAddQuestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (item.pages.isNotEmpty) 'Sayfa ${item.pageSpec}',
      if (item.estimatedQuestions != null) 'yaklaşık ${item.estimatedQuestions} soru',
    ].join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.label, style: theme.textTheme.titleSmall),
            if (meta.isNotEmpty)
              Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _CountField(label: 'Doğru', controller: fields.correct)),
                const SizedBox(width: 8),
                Expanded(child: _CountField(label: 'Yanlış', controller: fields.wrong)),
                const SizedBox(width: 8),
                Expanded(child: _CountField(label: 'Boş', controller: fields.blank)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onMark,
                    icon: const Icon(Icons.checklist_rounded),
                    label: const Text('Yanlışları işaretle'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onAddQuestion,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Fotoğraflı'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Konu anlatımı, video, tekrar: yalnızca süre sayılır.
class _NoQuestionsCard extends StatelessWidget {
  const _NoQuestionsCard({required this.item});
  final SessionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
        title: Text(item.label),
        subtitle: const Text('Süre kaydedilir; girilecek sonuç yok.'),
      ),
    );
  }
}

class _CountField extends StatelessWidget {
  const _CountField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}
