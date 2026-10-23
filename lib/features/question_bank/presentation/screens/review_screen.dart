import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../domain/question_bank.dart';
import '../../domain/question_card.dart';
import '../../domain/srs.dart';
import '../../question_bank_providers.dart';
import '../widgets/media_image.dart';
import '../../../../app/palette.dart';
import '../../domain/recurrence.dart';

/// "Yanlışlarımı Göster": günü gelen kartlar SM-2'ye göre çözümleriyle getirilir.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueReviewsProvider);
    // Benzerlik için tüm defter: aynı konuda sık tekrarlanan hatalar öne alınır.
    final all = ref.watch(allQuestionsProvider);
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Yanlışlarım')),
      body: due.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Kartlar yüklenemedi: $e')),
        data: (list) {
          if (list.isEmpty) return const _NothingDue();
          if (all.isLoading && !all.hasValue) return const Center(child: CircularProgressIndicator());
          final rec = recurrenceOf(all.value ?? const <QuestionCard>[], {for (final n in curriculum) n.id: n});
          return _ReviewSession(initial: prioritizeDue(list, rec), recurrence: rec);
        },
      ),
    );
  }
}

class _NothingDue extends StatelessWidget {
  const _NothingDue();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Bugün tekrar edecek soru yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Yeni yanlışlar ertesi gün, tekrar ettiklerin ise zamanı gelince buraya düşer.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewSession extends ConsumerStatefulWidget {
  const _ReviewSession({required this.initial, this.recurrence = const {}});
  final List<DueReview> initial;

  /// Kart → benzer hata bilgisi (aynı konu, aynı neden).
  final Map<String, Recurrence> recurrence;

  @override
  ConsumerState<_ReviewSession> createState() => _ReviewSessionState();
}

class _ReviewSessionState extends ConsumerState<_ReviewSession> {
  late final List<DueReview> _queue = [...widget.initial];
  final _relearn = <String>{};
  int _index = 0;
  int _graded = 0;
  bool _showSolution = false;
  bool _busy = false;

  DueReview? get _current => _index < _queue.length ? _queue[_index] : null;

  Future<void> _grade(RecallGrade grade) async {
    final item = _current;
    if (item == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Aynı oturumda ikinci kez gösterilen kart zamanlamayı bir kez daha etkilemez.
      ReviewState? before;
      var counted = false, requeued = false;
      if (!_relearn.contains(item.card.id)) {
        before = await ref.read(questionCardRepositoryProvider).reviewStateOf(item.card.id);
        await ref.read(gradeReviewProvider).call(item.card.id, grade);
        _graded++;
        counted = true;
        if (grade == RecallGrade.again) {
          _relearn.add(item.card.id);
          _queue.add(item); // oturum sonunda bir kez daha göster
          requeued = true;
        }
      }
      if (mounted) {
        final at = _index;
        setState(() {
          _index++;
          _showSolution = false;
        });
        // Yanlışlıkla basılan not geri alınabilir: zamanlama ve kuyruk eski hâline döner.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('"${grade.label}" kaydedildi.'),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => _undoGrade(item, at, before: before, counted: counted, requeued: requeued),
          ),
        ));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoGrade(
    DueReview item,
    int at, {
    required ReviewState? before,
    required bool counted,
    required bool requeued,
  }) async {
    if (!mounted) return;
    if (counted && before != null) {
      await ref.read(questionCardRepositoryProvider).applyReview(item.card.id, before);
    }
    if (!mounted) return;
    setState(() {
      if (requeued) {
        final last = _queue.lastIndexWhere((q) => q.card.id == item.card.id);
        if (last > at) _queue.removeAt(last);
        _relearn.remove(item.card.id);
      }
      if (counted) _graded--;
      _index = at;
      _showSolution = false;
    });
  }

  /// Tekrar sırasında soruyu siler; liste ve sayaçlar hemen güncellenir.
  Future<void> _deleteCurrent() async {
    final item = _current;
    if (item == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Soruyu sil?'),
        content: const Text('Soru, fotoğrafları ve tekrar geçmişi silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(deleteQuestionCardProvider).call(item.card.id);
      if (!mounted) return;
      setState(() {
        _queue.removeWhere((q) => q.card.id == item.card.id);
        _showSolution = false;
        _busy = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Soru silindi.')));
    } on Exception catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  static String _interval(int days) => days <= 1 ? 'yarın' : '$days gün';

  @override
  Widget build(BuildContext context) {
    final item = _current;
    if (item == null) return _Finished(graded: _graded);

    final theme = Theme.of(context);
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final topic = curriculum.where((n) => n.id == item.card.mebNodeId).firstOrNull;
    final card = item.card;
    final isRelearn = _relearn.contains(card.id);
    final now = ref.read(clockProvider)();

    return Column(
      children: [
        LinearProgressIndicator(value: _index / _queue.length),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Soruyu sil',
                onPressed: _busy ? null : _deleteCurrent,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              Expanded(
                child: Text(
                  [if (topic != null) topic.title, card.sourceName].join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('${_index + 1} / ${_queue.length}', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        if (widget.recurrence[card.id]?.isRecurring ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _RecurrenceBanner(widget.recurrence[card.id]!),
          ),
        if (card.reason != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Neden yanlış yapmıştın: ${card.reasonText}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Soru')),
              ButtonSegment(value: true, label: Text('Çözüm')),
            ],
            selected: {_showSolution},
            onSelectionChanged: (s) => setState(() => _showSolution = s.first),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _showSolution ? _Solution(card: card) : _Question(card: card),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: !_showSolution
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => setState(() => _showSolution = true),
                      child: const Text('Çözümü göster'),
                    ),
                  )
                : isRelearn
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _grade(RecallGrade.good),
                          child: const Text('Tamam, anladım'),
                        ),
                      )
                    : Row(
                        children: [
                          for (final grade in RecallGrade.values) ...[
                            Expanded(
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 56),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  backgroundColor:
                                      grade == RecallGrade.again ? theme.colorScheme.errorContainer : null,
                                ),
                                onPressed: _busy ? null : () => _grade(grade),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(grade.label),
                                    Text(
                                      grade == RecallGrade.again
                                          ? 'şimdi'
                                          : _interval(Sm2Scheduler.review(item.state, grade, now).intervalDays),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (grade != RecallGrade.values.last) const SizedBox(width: 6),
                          ],
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.card});
  final QuestionCard card;

  @override
  Widget build(BuildContext context) {
    final path = card.questionImage;
    if (path == null) {
      // Fotoğrafsız hızlı kart: soruyu kitaptan açıp çözmek için yerini göster.
      final theme = Theme.of(context);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kitabı aç ve soruyu yeniden çöz', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(card.sourceName, style: theme.textTheme.bodyLarge),
              if (card.testLabel != null) Text(card.testLabel!, style: theme.textTheme.bodyMedium),
              if (card.questionNo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${card.questionNo}. soru', style: theme.textTheme.headlineMedium),
                ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => openImageZoom(context, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: MediaImage(path, fit: BoxFit.fitWidth, cacheWidth: 1440),
      ),
    );
  }
}

class _Solution extends StatelessWidget {
  const _Solution({required this.card});
  final QuestionCard card;

  @override
  Widget build(BuildContext context) {
    final image = card.solutionImage;
    final text = card.solutionText;
    final answer = card.answerText;
    if (image == null && text == null && answer != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(answer, style: Theme.of(context).textTheme.titleMedium),
      );
    }
    if (image == null && text == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Bu soruya henüz çözüm eklenmemiş. Defterde soruya dokunup ekleyebilirsin.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          GestureDetector(
            onTap: () => openImageZoom(context, image),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MediaImage(image, fit: BoxFit.fitWidth, cacheWidth: 1440),
            ),
          ),
        if (text != null)
          Padding(
            padding: EdgeInsets.only(top: image == null ? 0 : 12),
            child: SelectableText(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
      ],
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.graded});
  final int graded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Bugünlük bu kadar', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('$graded soruyu tekrar ettin.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.notebook),
              child: const Text('Defterime dön'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tekrarlayan hata" şeridi: bu konuda sık yanlış yapıyorsun, önce bu geliyor.
class _RecurrenceBanner extends StatelessWidget {
  const _RecurrenceBanner(this.recurrence);
  final Recurrence recurrence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = dark ? KocumColors.redDark : KocumColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat_rounded, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Tekrarlayan hata. ', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                TextSpan(text: recurrence.message),
              ]),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
