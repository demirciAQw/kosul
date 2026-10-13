import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';

/// Geçmiş oturumlar: sonuçları düzenle, süreyi düzelt, sil.
class SessionHistoryScreen extends ConsumerWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(sessionHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Geçmiş oturumlar')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Oturumlar yüklenemedi: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Henüz bitmiş bir oturum yok.'));
          }
          final children = <Widget>[];
          String? day;
          for (final s in list) {
            final d = formatDate(s.startedAt);
            if (d != day) {
              day = d;
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(d, style: Theme.of(context).textTheme.titleSmall),
              ));
            }
            children.add(_SessionTile(session: s));
          }
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: children);
        },
      ),
    );
  }
}

enum _Action { results, time, delete }

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final StudySession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = session;
    final end = s.endedAt ?? s.startedAt;
    final c = s.items.fold<int>(0, (a, i) => a + (i.correct ?? 0));
    final w = s.items.fold<int>(0, (a, i) => a + (i.wrong ?? 0));
    final b = s.items.fold<int>(0, (a, i) => a + (i.blank ?? 0));
    final pending = s.status == SessionStatus.awaitingResults;
    return ListTile(
      onTap: () => context.push(AppRoutes.sessionResults(s.id)),
      title: Text(s.items.map((i) => i.label).join('; '), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        '${formatClock(s.startedAt)}–${formatClock(end)}, ${formatDuration(end.difference(s.startedAt))}',
        if (c + w + b > 0) '$c D, $w Y, $b B',
        if (pending) 'sonuç bekliyor',
      ].join(', ')),
      leading: Icon(
        pending ? Icons.pending_actions_outlined : Icons.check_circle_outline_rounded,
        color: pending ? theme.colorScheme.tertiary : theme.colorScheme.primary,
      ),
      trailing: PopupMenuButton<_Action>(
        tooltip: 'Oturum seçenekleri',
        onSelected: (a) => switch (a) {
          _Action.results => context.push(AppRoutes.sessionResults(s.id)),
          _Action.time => _editTime(context, ref),
          _Action.delete => _delete(context, ref),
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: _Action.results, child: Text('Sonuçları düzenle')),
          PopupMenuItem(value: _Action.time, child: Text('Süreyi düzelt')),
          PopupMenuItem(value: _Action.delete, child: Text('Oturumu sil')),
        ],
      ),
    );
  }

  Future<void> _editTime(BuildContext context, WidgetRef ref) async {
    final value = await showDialog<({TimeOfDay start, int minutes})>(
      context: context,
      builder: (_) => _TimeDialog(session: session),
    );
    if (value == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final d = session.startedAt;
    final start = DateTime(d.year, d.month, d.day, value.start.hour, value.start.minute);
    try {
      await ref.read(studySessionRepositoryProvider).updateTimes(
            session.id,
            startedAt: start,
            endedAt: start.add(Duration(minutes: value.minutes)),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Süre güncellendi.')));
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Oturumu sil?'),
        content: const Text(
          'Süresi ve sonuçları analizden çıkar. Bu oturumda deftere eklediğin sorular kalır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(studySessionRepositoryProvider).deleteFinished(session.id);
    messenger.showSnackBar(const SnackBar(content: Text('Oturum silindi.')));
  }
}

class _TimeDialog extends StatefulWidget {
  const _TimeDialog({required this.session});
  final StudySession session;

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.session.startedAt);
  late final _minutes = TextEditingController(
    text: '${(widget.session.endedAt ?? widget.session.startedAt).difference(widget.session.startedAt).inMinutes}',
  );

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Süreyi düzelt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sayacı kapatmayı unuttuysan gerçek süreyi gir.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(context: context, initialTime: _start);
                if (picked != null) setState(() => _start = picked);
              },
              icon: const Icon(Icons.schedule_rounded),
              label: Text('Başlangıç ${_start.format(context)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(labelText: 'Süre', suffixText: 'dakika'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(_minutes.text.trim());
              if (m == null || m < 1) return;
              Navigator.pop(context, (start: _start, minutes: m));
            },
            child: const Text('Kaydet'),
          ),
        ],
      );
}
