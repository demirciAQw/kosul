import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../../question_bank/domain/question_card.dart';
import '../../../question_bank/presentation/question_prefill.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';

/// "Eksiklerini doldur": bitmiş oturumun D/Y/B sonuçları. "Sonra" ile
/// ertelenebilir; rozet, sonuçlar kaydedilene kadar ana ekranda kalır.
class SessionResultsScreen extends ConsumerStatefulWidget {
  const SessionResultsScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends ConsumerState<SessionResultsScreen> {
  final _fields = <String, _ResultFields>{};
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
    final fields = [for (final item in s.items) _fieldsFor(item)];
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
                _ItemCard(item: item, fields: _fieldsFor(item), onAddQuestion: () => _addQuestion(s, item)),
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

  /// Hata ekleme ekranını oturum bağlamıyla önceden doldurur: kaynak, MEB
  /// konusu, testteki soru sayısı ve soru başına ortalama süre otomatik gelir.
  void _addQuestion(StudySession s, SessionItem item) {
    final books = ref.read(libraryProvider).value ?? const <Book>[];
    final book = books.where((b) => b.id == item.bookId).firstOrNull;
    final totalSolved = _fields.values.fold<int>(0, (sum, f) => sum + f.solved);
    final itemSolved = _fieldsFor(item).solved;
    context.push(
      AppRoutes.newQuestion,
      extra: QuestionPrefill(
        origin: QuestionOrigin.book,
        sessionId: s.id,
        bookId: item.bookId,
        contentNodeId: item.contentNodeId,
        mebNodeId: item.mebNodeId,
        sourceName: book?.title ?? item.label.split(' › ').first,
        subject: book == null ? null : subjectKey(book.examType, book.subject),
        testTotalQuestions: itemSolved > 0 ? itemSolved : item.estimatedQuestions,
        avgSecondsPerQuestion:
            totalSolved > 0 ? s.elapsedAt(DateTime.now()).inSeconds / totalSolved : null,
      ),
    );
  }

  Future<void> _save(StudySession s) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(submitSessionResultsProvider)
          .call(s.id, [for (final item in s.items) _fieldsFor(item).toResult(item.id)]);
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
  const _ItemCard({required this.item, required this.fields, required this.onAddQuestion});
  final SessionItem item;
  final _ResultFields fields;
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onAddQuestion,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Yanlış ya da boş soru ekle'),
              ),
            ),
          ],
        ),
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
