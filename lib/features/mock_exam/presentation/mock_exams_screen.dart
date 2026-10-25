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
  /// Grafikte seçilen deneme; null = ortalama görünümü.
  String? _selectedId;

  void _select(List<MockExam> chronological, int? i) =>
      setState(() => _selectedId = i == null ? null : chronological[i].id);

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
    final index = chronological.indexWhere((e) => e.id == _selectedId);
    final selected = index < 0 ? null : chronological[index];
    final nets = [for (final e in exams) e.net];
    return [
      _Headline(
        nets: nets,
        selectedNet: selected?.net,
        selectedLabel: selected == null ? null : '${selected.title}, ${formatDate(selected.takenOn)}',
        onClear: () => setState(() => _selectedId = null),
      ),
      if (selected != null) _SelectedExam(exam: selected),
      const SizedBox(height: 12),
      NetChart(
        points: [for (final e in chronological) NetPoint(e.takenOn, e.net)],
        maxNet: exams.first.questionCount.toDouble(),
        selected: index < 0 ? null : index,
        average: nets.reduce((a, b) => a + b) / nets.length,
        onSelect: (i) => _select(chronological, i),
      ),
      if (selected == null && exams.length > 1) const _ChartHint(),
      const _Title('Derslere göre net'),
      _SubjectTable(stats: subjectNetStats(exams), selected: selected),
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
    final index = chronological.indexWhere((e) => e.id == _selectedId);
    final picked = index < 0 ? null : chronological[index];
    final subjectNets = [for (final e in withSubject) e.section(selected)!.net];
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
      _Headline(
        nets: subjectNets,
        selectedNet: picked?.section(selected)?.net,
        selectedLabel: picked == null ? null : '${picked.title}, ${formatDate(picked.takenOn)}',
        onClear: () => setState(() => _selectedId = null),
      ),
      if (picked != null) _SelectedExam(exam: picked),
      const SizedBox(height: 12),
      NetChart(
        points: [for (final e in chronological) NetPoint(e.takenOn, e.section(selected)!.net)],
        maxNet: withSubject.first.section(selected)!.questionCount.toDouble(),
        selected: index < 0 ? null : index,
        average: subjectNets.reduce((a, b) => a + b) / subjectNets.length,
        onSelect: (i) => _select(chronological, i),
      ),
      if (picked == null && withSubject.length > 1) const _ChartHint(),
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

/// Açılışta ortalama net; grafikte bir deneme seçilince o denemenin neti ve
/// ortalamaya göre farkı.
class _Headline extends StatelessWidget {
  const _Headline({required this.nets, this.selectedNet, this.selectedLabel, this.onClear}); // nets: en yeniden eskiye
  final List<double> nets;
  final double? selectedNet;
  final String? selectedLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (nets.isEmpty) return const SizedBox.shrink();
    final average = nets.reduce((a, b) => a + b) / nets.length;
    final best = nets.reduce((a, b) => a > b ? a : b);
    final picked = selectedNet;
    final shown = picked ?? average;
    // Seçimde: bu deneme ortalamaya göre; seçim yokken: son deneme ortalamaya göre.
    final compared = picked ?? nets.first;
    final diff = compared - average;
    final diffText = '${diff >= 0 ? '+' : '−'}${formatNet(diff.abs())} net';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatNet(shown), style: theme.textTheme.displaySmall?.copyWith(color: scheme.primary)),
            Text(
              picked == null ? 'ortalama net, ${nets.length} deneme' : 'bu denemenin neti',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nets.length > 1)
                Text(
                  picked == null ? 'Son: ${formatNet(nets.first)} ($diffText)' : diffText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: diff >= 0 ? KocumColors.good : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                picked == null
                    ? (nets.length > 1 ? 'ortalamaya göre; en iyi ${formatNet(best)}' : 'İkinci denemeden sonra gidişat görünür.')
                    : 'ortalamaya göre; en iyi ${formatNet(best)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (picked != null && selectedLabel != null)
                Text(selectedLabel!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (picked != null)
          IconButton(tooltip: 'Ortalamaya dön', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
      ],
    );
  }
}

/// Seçilen denemenin kısa özeti: doğru, yanlış, boş, süre ve ayrıntıya geçiş.
class _SelectedExam extends StatelessWidget {
  const _SelectedExam({required this.exam});
  final MockExam exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [
                  '${exam.correct} doğru',
                  '${exam.wrong} yanlış',
                  '${exam.blank} boş',
                  if (exam.durationMinutes != null) '${exam.durationMinutes} dk',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: () => context.push(AppRoutes.mockExam(exam.id)), child: const Text('Ayrıntı')),
          ],
        ),
      ),
    );
  }
}

class _ChartHint extends StatelessWidget {
  const _ChartHint();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Bir noktaya dokun: o denemenin sonuçları gelir. Kesikli çizgi ortalama.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

class _SubjectTable extends StatelessWidget {
  const _SubjectTable({required this.stats, this.selected});
  final List<SubjectNetStat> stats;

  /// Seçili deneme varsa "bu deneme / ortalama" karşılaştırması.
  final MockExam? selected;

  /// Ok yönü: seçimde bu deneme − ortalama (küçük farklar düz), yoksa son − önceki.
  double? _change(SubjectNetStat s) {
    final net = selected?.section(s.subject)?.net;
    if (net == null) return s.change;
    final d = net - s.average;
    return d.abs() < 0.01 ? 0 : d;
  }

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
            cell(selected == null ? 'son' : 'bu deneme', style: muted),
            cell('ortalama', style: muted),
            const SizedBox(width: 28),
          ],
        ),
        const Divider(height: 12),
        for (final s in stats)
          if (selected == null || selected!.section(s.subject) != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(s.name, style: theme.textTheme.bodyLarge)),
                cell(formatNet(selected?.section(s.subject)?.net ?? s.last), style: theme.textTheme.titleSmall),
                cell(formatNet(s.average), style: theme.textTheme.bodyMedium),
                SizedBox(
                  width: 28,
                  child: Icon(
                    switch (_change(s)) {
                      final c? when c > 0 => Icons.arrow_upward_rounded,
                      final c? when c < 0 => Icons.arrow_downward_rounded,
                      _ => Icons.remove_rounded,
                    },
                    size: 18,
                    color: switch (_change(s)) {
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
            selected == null
                ? 'Ok, son denemeyi bir öncekiyle karşılaştırır.'
                : 'Ok, bu denemeyi ortalamayla karşılaştırır.',
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
