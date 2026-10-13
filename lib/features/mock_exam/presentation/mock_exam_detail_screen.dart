import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/quick_mark.dart';
import '../../question_bank/presentation/question_prefill.dart';
import '../../question_bank/presentation/quick_mark_flow.dart';
import '../../question_bank/presentation/widgets/question_tile.dart' show statusColor;
import '../../question_bank/question_bank_providers.dart';
import '../domain/mock_exam.dart';
import '../mock_exam_providers.dart';
import 'widgets/topic_loss_list.dart';

class MockExamDetailScreen extends ConsumerWidget {
  const MockExamDetailScreen({super.key, required this.examId});
  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(mockExamByIdProvider(examId));
    return exam.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('Deneme okunamadı: $e'))),
      data: (e) => e == null
          ? Scaffold(appBar: AppBar(), body: const Center(child: Text('Deneme bulunamadı.')))
          : _Content(exam: e),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.exam});
  final MockExam exam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = ref.watch(mockExamMistakesProvider).value ?? const <QuestionCard>[];
    final mine = [for (final c in cards) if (c.mockExamId == exam.id) c];
    final curriculum = {
      for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n,
    };

    // Aynı testte sorulan dersleri (Sosyal, Fen…) grup başlığıyla topla.
    final children = <Widget>[];
    String? lastGroup;
    for (final s in exam.sections) {
      final group = s.group;
      if (group != null && group != lastGroup) {
        final members = exam.sections.where((x) => x.group == group);
        final groupNet = members.fold<double>(0, (sum, x) => sum + x.net);
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text('$group, ${formatNet(groupNet)} net', style: theme.textTheme.labelLarge),
        ));
      } else if (group == null && lastGroup != null) {
        children.add(const SizedBox(height: 12));
      }
      lastGroup = group;
      children.add(_SectionCard(
        exam: exam,
        section: s,
        marked: mine.where((c) => c.subject == s.subject).length,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(exam.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            onPressed: () => context.push(AppRoutes.editMockExam(exam.id)),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _confirmDelete(context, ref),
            itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('Denemeyi sil'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            [
              formatDate(exam.takenOn),
              exam.kind.label,
              if (exam.durationMinutes != null) '${exam.durationMinutes} dk',
            ].join(', '),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatNet(exam.net), style: theme.textTheme.displayMedium?.copyWith(color: scheme.primary)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('net', style: theme.textTheme.titleMedium),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Dyb(correct: exam.correct, wrong: exam.wrong, blank: exam.blank),
              ),
            ],
          ),
          if (exam.note != null) ...[
            const SizedBox(height: 8),
            Text(exam.note!),
          ],
          const SizedBox(height: 8),
          Text(
            'Bir dersin yanlışlarını optik formda işaretlersen sorular deftere düşer; '
            'konularını girdikçe aşağıda net kaybı görünür.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          ...children,
          Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 8),
            child: Text('Bu denemede net kaybettiren konular', style: theme.textTheme.titleMedium),
          ),
          TopicLossList(losses: topicNetLoss(mine, curriculum)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Denemeyi sil?'),
        content: const Text(
          'Deneme ve netleri silinir. Optikle işaretlenip hiç doldurulmamış sorular da silinir; '
          'fotoğraf ya da çözüm eklediğin sorular defterinde kalır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final router = GoRouter.of(context);
    await ref.read(mockExamRepositoryProvider).delete(exam.id);
    router.canPop() ? router.pop() : router.go(AppRoutes.mockExams);
  }
}

class _SectionCard extends ConsumerWidget {
  const _SectionCard({required this.exam, required this.section, required this.marked});
  final MockExam exam;
  final MockSection section;
  final int marked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unentered = section.questionCount - section.correct - section.wrong - section.blank;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(section.name, style: theme.textTheme.titleMedium)),
                Text('${formatNet(section.net)} net', style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary)),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _Dyb(correct: section.correct, wrong: section.wrong, blank: section.blank),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '/ ${section.questionCount}${unentered > 0 ? ', $unentered girilmemiş' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    marked == 0 ? 'Yanlışlar deftere işlenmedi' : '$marked soru defterde',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: 'Fotoğraflı soru ekle',
                  onPressed: () => context.push(
                    AppRoutes.newQuestion,
                    extra: QuestionPrefill(
                      origin: QuestionOrigin.mockExam,
                      mockExamId: exam.id,
                      sourceName: exam.title,
                      subject: section.subject,
                      testLabel: '${exam.title}, ${section.name}',
                      testTotalQuestions: section.questionCount,
                      avgSecondsPerQuestion: exam.secondsPerQuestion,
                    ),
                  ),
                  icon: const Icon(Icons.add_a_photo_outlined),
                ),
                TextButton.icon(
                  onPressed: () => _mark(context, ref),
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('Yanlışları işaretle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mark(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(mockExamRepositoryProvider);
    final warn = marked == 0 && (section.wrong > 0 || section.blank > 0)
        ? 'Kaydedince sayılar işaretlerine göre güncellenir (şu an ${section.wrong} Y, ${section.blank} B).'
        : exam.title;
    final result = await openQuickMark(
      context,
      ref,
      parts: [
        QuickMarkPart(
          key: section.id,
          title: section.name,
          total: section.questionCount,
          markContext: QuickMarkContext(
            origin: QuestionOrigin.mockExam,
            subject: section.subject,
            sourceName: exam.title,
            mockExamId: exam.id,
            testLabel: '${exam.title}, ${section.name}',
            avgSecondsPerQuestion: exam.secondsPerQuestion,
          ),
        ),
      ],
      title: section.subject,
      subtitle: warn,
      totalEditable: false,
      showNet: true,
    );
    if (result == null) return;
    await repository.updateSection(section.id, correct: result.correct, wrong: result.wrong, blank: result.blank);
  }
}

/// "28 D, 6 Y, 6 B" — renkli ama metinle de okunur.
class _Dyb extends StatelessWidget {
  const _Dyb({required this.correct, required this.wrong, required this.blank});
  final int correct;
  final int wrong;
  final int blank;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    TextSpan part(String v, QuestionStatus s) =>
        TextSpan(text: v, style: style?.copyWith(color: statusColor(s), fontWeight: FontWeight.w700));
    return Text.rich(TextSpan(
      style: style,
      children: [
        part('$correct D', QuestionStatus.correct),
        const TextSpan(text: ', '),
        part('$wrong Y', QuestionStatus.wrong),
        const TextSpan(text: ', '),
        part('$blank B', QuestionStatus.blank),
      ],
    ));
  }
}
