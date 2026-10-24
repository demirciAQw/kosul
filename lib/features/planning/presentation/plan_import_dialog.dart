import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../library/domain/library.dart';
import '../../library/library_providers.dart';
import '../domain/plan_import.dart';
import '../planning_providers.dart';

/// Yapay zekânın verdiği programı (JSON) yapıştır → önizle → plan olarak kaydet.
Future<void> showPlanImportDialog(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PlanImportSheet(),
    );

class _PlanImportSheet extends ConsumerStatefulWidget {
  const _PlanImportSheet();

  @override
  ConsumerState<_PlanImportSheet> createState() => _PlanImportSheetState();
}

class _PlanImportSheetState extends ConsumerState<_PlanImportSheet> {
  final _text = TextEditingController();
  PlanImport? _preview;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    _text.text = t;
    _check();
  }

  void _check() {
    setState(() {
      _error = null;
      _preview = null;
      try {
        _preview = parsePlanJson(
          _text.text,
          books: ref.read(libraryProvider).value ?? const <Book>[],
          today: ref.read(clockProvider)(),
        );
      } on PlanImportException catch (e) {
        _error = e.message;
      }
    });
  }

  Future<void> _save() async {
    final p = _preview;
    if (p == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final plan = await ref.read(createPlanProvider).call(p.draft);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('"${plan.title}" eklendi: ${plan.tasks.length} görev.')));
    } on Exception catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _preview;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Programı içe aktar', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Yapay zekânın verdiği JSON programını yapıştır. Önce önizleme gösterilir; kaydedince yeni bir plan olur.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            onChanged: (_) => setState(() => _preview = null),
            decoration: InputDecoration(
              hintText: '{ "format": "kocum.plan", … }',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Yapıştır')),
              const Spacer(),
              OutlinedButton(onPressed: _text.text.trim().isEmpty ? null : _check, child: const Text('Önizle')),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.draft.title, style: theme.textTheme.titleMedium),
                    Text(
                      '${formatDate(p.draft.startsOn)} – ${formatDate(p.draft.endsOn)}, ${p.draft.tasks.length} görev'
                      '${p.matchedBooks > 0 ? ', ${p.matchedBooks} görev kitaplığına bağlandı' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    for (final t in p.draft.tasks.take(6))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text('• ${t.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    if (p.draft.tasks.length > 6)
                      Text('ve ${p.draft.tasks.length - 6} görev daha', style: theme.textTheme.bodySmall),
                    for (final w in p.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(w, style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Kaydediliyor…' : 'Plan olarak kaydet'),
            ),
          ],
        ],
      ),
    );
  }
}
