import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/question_bank_providers.dart';
import '../domain/mock_exam.dart';
import '../mock_exam_providers.dart';
import 'karne_import_screen.dart';
import 'widgets/net_chart.dart';
import 'widgets/topic_loss_list.dart';
import '../../../app/palette.dart';

/// Deneme analizi: net seyri, ders bazlı netler, konu bazlı net kaybı ve tüm denemeler.
class MockExamsScreen extends ConsumerStatefulWidget {
  const MockExamsScreen({super.key});

  @override
  ConsumerState<MockExamsScreen> createState() => _MockExamsScreenState();
}

class _MockExamsScreenState extends ConsumerState<MockExamsScreen> {
  /// Branş denemelerinde grafiği çizilecek ders.
  String? _branchSubject;

  @override
  Widget build(BuildContext context) {
    final exams = ref.watch(mockExamsProvider);
    final kind = ref.watch(mockKindFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Denemeler'),
        actions: [
          IconButton(
            tooltip: 'Karneden içe aktar (PDF)',
            onPressed: () => importKarneFlow(context, ref),
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'mock-add',
        onPressed: () => context.push(AppRoutes.newMockExam),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Deneme ekle'),
      ),
      body: exams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Denemeler yüklenemedi: $e')),
        data: (all) {
          if (all.isEmpty) return const _EmptyExams();
          final ofKind = [for (final e in all) if (e.kind == kind) e];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              SegmentedButton<MockKind>(
                segments: [
                  for (final k in MockKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {kind},
                onSelectionChanged: (s) => ref.read(mockKindFilterProvider.notifier).set(s.first),
              ),
              const SizedBox(height: 16),
              if (ofKind.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Henüz ${kind.label} denemesi eklemedin.',
                    textAlign: TextAlign.center,
                  ),
                )
              else if (kind == MockKind.branch)
                ..._branchBody(context, ofKind)
              else
                ..._examBody(context, ofKind),
            ],
          );
        },
      ),
    );
  }

  /// TYT / AYT / YDT: toplam net seyri + ders tablosu + konu kaybı + liste.
  List<Widget> _examBody(BuildContext context, List<MockExam> exams) {
    final chronological = exams.reversed.toList();
    return [
      _Headline(nets: [for (final e in exams) e.net]),
      const SizedBox(height: 12),
      NetChart(
        points: [for (final e in chronological) NetPoint(e.takenOn, e.net)],
        maxNet: exams.first.questionCount.toDouble(),
      ),
      const _Title('Derslere göre net'),
      _SubjectTable(stats: subjectNetStats(exams)),
      const _Title('En çok net kaybettiren konular'),
      _TopicLossFor(examIds: {for (final e in exams) e.id}),
      const _Title('Tüm denemeler'),
      for (final e in exams) _ExamTile(exam: e),
    ];
  }

  /// Branş: ders seç, o dersin net seyrini gör.
  List<Widget> _branchBody(BuildContext context, List<MockExam> exams) {
    final subjects = <String>[];
    for (final e in exams) {
      for (final s in e.sections) {
        if (!subjects.contains(s.subject)) subjects.add(s.subject);
      }
    }
    final selected = subjects.contains(_branchSubject) ? _branchSubject! : subjects.first;
    final withSubject = [for (final e in exams) if (e.section(selected) != null) e];
    final chronological = withSubject.reversed.toList();
    return [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final s in subjects)
            ChoiceChip(
              label: Text(s),
              selected: s == selected,
              onSelected: (_) => setState(() => _branchSubject = s),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _Headline(nets: [for (final e in withSubject) e.section(selected)!.net]),
      const SizedBox(height: 12),
      NetChart(
        points: [for (final e in chronological) NetPoint(e.takenOn, e.section(selected)!.net)],
        maxNet: withSubject.first.section(selected)!.questionCount.toDouble(),
      ),
      const _Title('En çok net kaybettiren konular'),
      _TopicLossFor(examIds: {for (final e in withSubject) e.id}, subject: selected),
      const _Title('Tüm branş denemeleri'),
      for (final e in exams) _ExamTile(exam: e),
    ];
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Son net ve önceki denemelerin ortalamasına göre fark.
class _Headline extends StatelessWidget {
  const _Headline({required this.nets}); // en yeniden eskiye
  final List<double> nets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (nets.isEmpty) return const SizedBox.shrink();
    final last = nets.first;
    final previous = nets.skip(1).take(5).toList();
    final avg = previous.isEmpty ? null : previous.reduce((a, b) => a + b) / previous.length;
    final diff = avg == null ? null : last - avg;
    final best = nets.reduce((a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatNet(last), style: theme.textTheme.displaySmall?.copyWith(color: scheme.primary)),
            Text('son deneme neti', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (diff != null)
                Text(
                  '${diff >= 0 ? '+' : '−'}${formatNet(diff.abs())} net',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: diff >= 0 ? KocumColors.good : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                diff == null
                    ? 'İkinci denemeden sonra gidişat görünür.'
                    : 'önceki ${previous.length} denemenin ortalamasına göre; en iyi ${formatNet(best)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectTable extends StatelessWidget {
  const _SubjectTable({required this.stats});
  final List<SubjectNetStat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget cell(String text, {TextStyle? style}) =>
        SizedBox(width: 60, child: Text(text, textAlign: TextAlign.right, style: style));

    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox.shrink()),
            cell('son', style: muted),
            cell('ortalama', style: muted),
            const SizedBox(width: 28),
          ],
        ),
        const Divider(height: 12),
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(s.name, style: theme.textTheme.bodyLarge)),
                cell(formatNet(s.last), style: theme.textTheme.titleSmall),
                cell(formatNet(s.average), style: theme.textTheme.bodyMedium),
                SizedBox(
                  width: 28,
                  child: Icon(
                    switch (s.change) {
                      final c? when c > 0 => Icons.arrow_upward_rounded,
                      final c? when c < 0 => Icons.arrow_downward_rounded,
                      _ => Icons.remove_rounded,
                    },
                    size: 18,
                    color: switch (s.change) {
                      final c? when c > 0 => KocumColors.good,
                      final c? when c < 0 => scheme.error,
                      _ => scheme.onSurfaceVariant,
                    },
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Ok, son denemeyi bir öncekiyle karşılaştırır.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Seçili denemelerin (isteğe bağlı olarak tek dersinin) konu bazlı net kaybı.
class _TopicLossFor extends ConsumerWidget {
  const _TopicLossFor({required this.examIds, this.subject});
  final Set<String> examIds;
  final String? subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(mockExamMistakesProvider).value ?? const <QuestionCard>[];
    final curriculum = {
      for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n,
    };
    final relevant = cards.where(
      (c) => examIds.contains(c.mockExamId) && (subject == null || c.subject == subject),
    );
    return TopicLossList(losses: topicNetLoss(relevant, curriculum));
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam});
  final MockExam exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: () => context.push(AppRoutes.mockExam(exam.id)),
        title: Text(exam.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${formatDate(exam.takenOn)}, ${exam.correct} D, ${exam.wrong} Y, ${exam.blank} B',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatNet(exam.net), style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
            Text('net', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _ImportButton extends ConsumerWidget {
  const _ImportButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.tonalIcon(
        onPressed: () => importKarneFlow(context, ref),
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Okul karnesinden içe aktar (PDF)'),
      );
}

class _EmptyExams extends StatelessWidget {
  const _EmptyExams();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Henüz deneme eklemedin', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Deneme sonuçlarını ders ders gir; netlerin, gidişatın ve hangi konunun kaç net '
              'kaybettirdiği burada görünür.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const _ImportButton(),
          ],
        ),
      ),
    );
  }
}
