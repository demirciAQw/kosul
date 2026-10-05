import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../study_session/domain/study_session.dart';
import '../../study_session/presentation/widgets/topic_selection_view.dart';
import '../domain/planning.dart';
import '../planning_providers.dart';

class CreatePlanScreen extends ConsumerStatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  ConsumerState<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends ConsumerState<CreatePlanScreen> {
  final _title = TextEditingController();
  final _tasks = <NewPlanTaskDraft>[];
  late DateTimeRange _range;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: today, end: today.add(const Duration(days: 13)));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final today = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 3),
      initialDateRange: _range,
      helpText: 'Plan tarih aralığı',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _addFromBooks() async {
    final drafts = await Navigator.of(context).push<List<SessionItemDraft>>(
      MaterialPageRoute(builder: (_) => const TopicPickerPage()),
    );
    if (drafts == null || !mounted) return;
    setState(() {
      for (final d in drafts) {
        _tasks.add(NewPlanTaskDraft(
          title: d.label,
          bookId: d.bookId,
          contentNodeId: d.contentNodeId,
          targetQuestions: d.estimatedQuestions,
        ));
      }
    });
  }

  Future<void> _addCustom() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _TextPromptDialog());
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _tasks.add(NewPlanTaskDraft(title: text.trim())));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(createPlanProvider).call(NewPlanDraft(
            title: _title.text,
            startsOn: _range.start,
            endsOn: _range.end,
            tasks: _tasks,
          ));
      messenger.showSnackBar(const SnackBar(content: Text('Plan kaydedildi.')));
      router.pop();
    } on PlanException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Plan kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _range.end.difference(_range.start).inDays + 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni plan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Plan adı', hintText: 'Örn. Ekim sonuna kadar problemler'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_outlined),
            label: Text('${formatDateRange(_range.start, _range.end)} ($days gün)'),
          ),
          const SizedBox(height: 24),
          Text('Görev havuzu', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Görevleri aralık içinde istediğin gün yaparsın; sıra ve gün dayatılmaz.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _tasks.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_tasks[i].title),
              subtitle: _tasks[i].targetQuestions == null ? null : Text('yaklaşık ${_tasks[i].targetQuestions} soru'),
              trailing: IconButton(
                tooltip: 'Kaldır',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _tasks.removeAt(i)),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Kitaptan konu ekle'),
                onPressed: _addFromBooks,
              ),
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Kendi görevini yaz'),
                onPressed: _addCustom,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Planı kaydet'),
          ),
        ),
      ),
    );
  }
}

class TopicPickerPage extends StatelessWidget {
  const TopicPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plana konu ekle')),
      body: TopicSelectionView(
        actionLabel: 'Plana ekle',
        actionIcon: Icons.playlist_add_rounded,
        onSubmit: (drafts) => Navigator.of(context).pop(drafts),
      ),
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog();

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni görev'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Örn. 2 deneme çöz'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Ekle')),
      ],
    );
  }
}
