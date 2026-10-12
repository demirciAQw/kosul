import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../study_session/domain/study_session.dart';
import '../../study_session/presentation/widgets/topic_selection_view.dart';
import '../domain/planning.dart';
import '../planning_providers.dart';

/// Yeni plan: tür (haftalık, aylık, yıllık, özel), ad, tarih aralığı, görevler.
/// Görev eklemek zorunlu değil; plan kartından sonra da eklenebilir.
/// Vazgeç ile ya da geri tuşuyla (onay sorularak) hiçbir şey kaydetmeden çıkılır.
class CreatePlanScreen extends ConsumerStatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  ConsumerState<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends ConsumerState<CreatePlanScreen> {
  final _title = TextEditingController();
  final _tasks = <NewPlanTaskDraft>[];
  PlanKind _kind = PlanKind.weekly;
  late DateTimeRange _range;
  bool _saving = false;

  bool get _dirty => _title.text.trim().isNotEmpty || _tasks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _applyKind(PlanKind.weekly);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _applyKind(PlanKind kind) {
    final r = kind.rangeFrom(ref.read(clockProvider)());
    _kind = kind;
    _range = DateTimeRange(start: r.start, end: r.end);
  }

  /// Ad boş bırakılırsa: "Haftalık plan (12 Eki – 18 Eki)" ya da "3. Plan".
  String _suggestedTitle() {
    final count = (ref.read(plansProvider).value?.length ?? 0) + 1;
    return _kind == PlanKind.custom
        ? '$count. Plan'
        : '${_kind.label} plan (${formatDateRange(_range.start, _range.end)})';
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
    if (picked != null) {
      setState(() {
        _range = picked;
        _kind = PlanKind.custom;
      });
    }
  }

  Future<void> _addFromBooks() async {
    final drafts = await pickPlanTasksFromBooks(context);
    if (drafts == null || !mounted) return;
    setState(() => _tasks.addAll(drafts));
  }

  Future<void> _addCustom() async {
    final text = await showDialog<String>(context: context, builder: (_) => const TaskTextDialog());
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _tasks.add(NewPlanTaskDraft(title: text.trim())));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Plan oluşturmaktan vazgeç?'),
        content: const Text('Yazdığın ad ve eklediğin görevler kaydedilmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Devam et')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Vazgeç')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancel() async {
    final router = GoRouter.of(context);
    if (await _confirmDiscard()) router.pop();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final title = _title.text.trim();
    try {
      final plan = await ref.read(createPlanProvider).call(NewPlanDraft(
            title: title.isEmpty ? _suggestedTitle() : title,
            startsOn: _range.start,
            endsOn: _range.end,
            tasks: _tasks,
          ));
      messenger.showSnackBar(SnackBar(content: Text('${plan.title} oluşturuldu.')));
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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (await _confirmDiscard()) router.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yeni plan'),
          leading: IconButton(tooltip: 'Vazgeç', icon: const Icon(Icons.close_rounded), onPressed: _cancel),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PlanKind>(
                showSelectedIcon: false,
                segments: [for (final k in PlanKind.values) ButtonSegment(value: k, label: Text(k.label))],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _applyKind(s.first)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Plan adı',
                hintText: _suggestedTitle(),
                helperText: 'Boş bırakırsan bu ad verilir.',
              ),
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
              'Görevleri aralık içinde istediğin gün yaparsın; sıra ve gün dayatılmaz. '
              'Görevsiz oluşturup sonra da ekleyebilirsin.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _tasks.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_tasks[i].title),
                subtitle: _tasks[i].targetQuestions == null ? null : Text('${_tasks[i].targetQuestions} soru'),
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
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _cancel,
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Planı oluştur'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kitap ağacından görev seçtirir (oluşturmada ve var olan plana eklemede).
Future<List<NewPlanTaskDraft>?> pickPlanTasksFromBooks(BuildContext context) async {
  final drafts = await Navigator.of(context).push<List<SessionItemDraft>>(
    MaterialPageRoute(builder: (_) => const TopicPickerPage()),
  );
  if (drafts == null) return null;
  return [
    for (final d in drafts)
      NewPlanTaskDraft(
        title: d.label,
        bookId: d.bookId,
        contentNodeId: d.contentNodeId,
        targetQuestions: d.estimatedQuestions,
      ),
  ];
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

class TaskTextDialog extends StatefulWidget {
  const TaskTextDialog({super.key});

  @override
  State<TaskTextDialog> createState() => _TaskTextDialogState();
}

class _TaskTextDialogState extends State<TaskTextDialog> {
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
