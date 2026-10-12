import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/library.dart';
import '../../library/library_providers.dart';
import '../../study_session/domain/study_session.dart';
import '../../study_session/presentation/session_launcher.dart';
import '../domain/planning.dart';
import '../planning_providers.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Planım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newPlan),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni plan'),
      ),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Planlar yüklenemedi: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyPlans();
          final active = [for (final p in list) if (!p.isExpired(now)) p];
          final past = [for (final p in list) if (p.isExpired(now)) p];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (final p in active) _PlanCard(plan: p, now: now, initiallyExpanded: active.length == 1),
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                  child: Text('Biten planlar', style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final p in past) _PlanCard(plan: p, now: now),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Henüz planın yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Bir tarih aralığı seç, konuları ekle. Hangi gün ne yapacağına sen karar verirsin.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.now, this.initiallyExpanded = false});

  final StudyPlan plan;
  final DateTime now;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pace = plan.paceHint(now);
    final summary = [
      '${plan.doneCount}/${plan.tasks.length} görev',
      if (pace != null) 'günde yaklaşık ${pace.toStringAsFixed(1).replaceAll('.', ',')} görev',
    ].join(', ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>(plan.id),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(plan.title, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${formatDateRange(plan.startsOn, plan.endsOn)}, ${plan.statusText(now)}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: plan.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 6),
              Text(summary, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (_) => _confirmDelete(context, ref),
          itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('Planı sil'))],
        ),
        children: [
          for (final task in plan.tasks)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: task.isDone,
              onChanged: (v) => ref.read(planRepositoryProvider).setTaskDone(task.id, v ?? false),
              title: Text(
                task.title,
                style: task.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
              ),
              subtitle: task.targetQuestions == null ? null : Text('yaklaşık ${task.targetQuestions} soru'),
              secondary: task.isDone
                  ? null
                  : IconButton(
                      tooltip: 'Çalışmaya başla',
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      onPressed: () => _startTask(context, ref, task),
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _startTask(BuildContext context, WidgetRef ref, PlanTask task) async {
    final books = ref.read(libraryProvider).value ?? const <Book>[];
    final book = books.where((b) => b.id == task.bookId).firstOrNull;
    final node = book?.allNodes.where((n) => n.id == task.contentNodeId).firstOrNull;
    final pages = node != null && node.hasPages
        ? [for (var p = node.pageStart!; p <= node.pageEnd!; p++) p]
        : <int>[];
    final draft = SessionItemDraft(
      label: task.title,
      bookId: book?.id,
      contentNodeId: node?.id,
      mebNodeId: node?.mebNodeId,
      pages: pages,
      estimatedQuestions: pages.isEmpty ? task.targetQuestions : book?.estimateQuestions(pages.length),
      subject: book == null ? null : subjectKey(book.examType, book.subject),
    );
    await launchSession(context, ref, [draft]);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Planı sil?'),
        content: const Text('Plan ve görevleri silinir. Geçmiş çalışma süreleri etkilenmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await ref.read(planRepositoryProvider).delete(plan.id);
  }
}
