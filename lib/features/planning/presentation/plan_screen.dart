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
import 'create_plan_screen.dart';

/// İstediğin kadar plan: süren, tamamlanan ve süresi dolan olarak ayrılır.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Planlarım')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan-add',
        onPressed: () => context.push(AppRoutes.newPlan),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni plan'),
      ),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Planlar yüklenemedi: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyPlans();
          final active = [for (final p in list) if (!p.isCompleted && !p.isExpired(now)) p];
          final done = [for (final p in list) if (p.isCompleted) p];
          final expired = [for (final p in list) if (!p.isCompleted && p.isExpired(now)) p];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Süren planın yok. Yeni bir plan oluşturabilirsin.'),
                ),
              for (final p in active) _PlanCard(plan: p, now: now, initiallyExpanded: active.length == 1),
              if (expired.isNotEmpty) ...[
                const _SectionTitle('Süresi dolanlar'),
                for (final p in expired) _PlanCard(plan: p, now: now),
              ],
              if (done.isNotEmpty) ...[
                _SectionTitle('Tamamlananlar (${done.length})'),
                for (final p in done) _PlanCard(plan: p, now: now),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
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
              'Haftalık, aylık ya da yıllık plan oluştur; görevleri ekle. '
              'Hangi gün ne yapacağına sen karar verirsin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.newPlan),
              icon: const Icon(Icons.add_rounded),
              label: const Text('İlk planını oluştur'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlanAction { addTask, toggleComplete, delete }

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.now, this.initiallyExpanded = false});

  final StudyPlan plan;
  final DateTime now;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pace = plan.paceHint(now);
    final summary = [
      if (plan.tasks.isEmpty) 'Henüz görev yok' else '${plan.doneCount}/${plan.tasks.length} görev',
      if (pace != null) 'günde yaklaşık ${pace.toStringAsFixed(1).replaceAll('.', ',')} görev',
    ].join(', ');

    return Card(
      clipBehavior: Clip.antiAlias,
      color: plan.isCompleted ? scheme.surfaceContainerHighest : null,
      child: ExpansionTile(
        key: PageStorageKey<String>(plan.id),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: plan.isCompleted ? Icon(Icons.task_alt_rounded, color: scheme.primary) : null,
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
        trailing: PopupMenuButton<_PlanAction>(
          tooltip: 'Plan seçenekleri',
          onSelected: (a) => switch (a) {
            _PlanAction.addTask => _addTasks(context, ref),
            _PlanAction.toggleComplete => _toggleComplete(context, ref),
            _PlanAction.delete => _confirmDelete(context, ref),
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: _PlanAction.addTask, child: Text('Görev ekle')),
            PopupMenuItem(
              value: _PlanAction.toggleComplete,
              child: Text(plan.isCompleted ? 'Tamamlanmadı olarak işaretle' : 'Tamamladım olarak işaretle'),
            ),
            const PopupMenuItem(value: _PlanAction.delete, child: Text('Planı sil')),
          ],
        ),
        children: [
          for (final task in plan.tasks)
            Dismissible(
              key: ValueKey('task-${task.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: scheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
              ),
              confirmDismiss: (_) => _confirm(
                context,
                title: 'Görevi sil?',
                message: '"${task.title}" plandan çıkarılır.',
                action: 'Sil',
              ),
              onDismissed: (_) => ref.read(planRepositoryProvider).deleteTask(task.id),
              child: CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: task.isDone,
                onChanged: (v) => ref.read(planRepositoryProvider).setTaskDone(task.id, v ?? false),
                title: Text(
                  task.title,
                  style: task.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                subtitle: task.targetQuestions == null ? null : Text('${task.targetQuestions} soru'),
                secondary: task.isDone || plan.isCompleted
                    ? null
                    : IconButton(
                        tooltip: 'Çalışmaya başla',
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        onPressed: () => _startTask(context, ref, task),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Görev ekle'),
                  onPressed: () => _addTasks(context, ref),
                ),
                if (!plan.isCompleted)
                  ActionChip(
                    avatar: const Icon(Icons.task_alt_rounded, size: 18),
                    label: Text(plan.allTasksDone ? 'Tüm görevler bitti: planı tamamla' : 'Tamamladım'),
                    onPressed: () => _toggleComplete(context, ref),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Tamamlanmadı'),
                    onPressed: () => _toggleComplete(context, ref),
                  ),
                ActionChip(
                  avatar: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                  label: const Text('Sil'),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ),
          if (plan.tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Bir görevi silmek için sola kaydır.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addTasks(BuildContext context, WidgetRef ref) async {
    final add = ref.read(addPlanTasksProvider);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Kitaptan konu ekle'),
              onTap: () => Navigator.pop(sheet, 'book'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Kendi görevini yaz'),
              onTap: () => Navigator.pop(sheet, 'text'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    List<NewPlanTaskDraft>? drafts;
    if (choice == 'book') {
      drafts = await pickPlanTasksFromBooks(context);
    } else {
      final text = await showDialog<String>(context: context, builder: (_) => const TaskTextDialog());
      if (text != null && text.trim().isNotEmpty) drafts = [NewPlanTaskDraft(title: text.trim())];
    }
    if (drafts == null || drafts.isEmpty) return;
    await add.call(plan.id, drafts);
    messenger.showSnackBar(SnackBar(content: Text('${drafts.length} görev eklendi.')));
  }

  Future<void> _toggleComplete(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(planRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (plan.isCompleted) {
      await repository.setCompleted(plan.id, null);
      return;
    }
    await repository.setCompleted(plan.id, ref.read(clockProvider)());
    messenger.showSnackBar(SnackBar(
      content: Text('${plan.title} tamamlandı olarak işaretlendi.'),
      action: SnackBarAction(label: 'Geri al', onPressed: () => repository.setCompleted(plan.id, null)),
    ));
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
      estimatedQuestions: node?.questionCount ??
          (pages.isEmpty ? task.targetQuestions : book?.estimateQuestions(pages.length)),
      subject: book == null ? null : subjectKey(book.examType, book.subject),
    );
    await launchSession(context, ref, [draft]);
  }

  /// Silinen plan, görevleri ve işaretleriyle birlikte "Geri al" ile geri gelir.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(planRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      context,
      title: 'Planı sil?',
      message: 'Plan ve görevleri silinir. Geçmiş çalışma süreleri etkilenmez.',
      action: 'Sil',
    );
    if (ok != true) return;
    final snapshot = plan;
    await repository.delete(plan.id);
    messenger.showSnackBar(SnackBar(
      content: Text('${snapshot.title} silindi.'),
      action: SnackBarAction(label: 'Geri al', onPressed: () => repository.create(snapshot)),
    ));
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) =>
    showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
        ],
      ),
    );
