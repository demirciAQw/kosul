import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';
import '../session_quick_mark.dart';
import '../widgets/elapsed_clock.dart';

/// Süren oturum. Bilinçli olarak "duraklat" YOK: sayaç yalnızca BİTİR ile
/// kapanır. Yanlışlıkla başlatılan oturum için İPTAL vardır (süre kaydedilmez).
/// Geri tuşu oturumu etkilemez; ana ekranda kart olarak durur.
class ActiveSessionScreen extends ConsumerWidget {
  const ActiveSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(runningSessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Çalışma oturumu')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Oturum okunamadı: $e')),
        data: (s) => s == null ? const _NoActiveSession() : _RunningView(session: s),
      ),
    );
  }
}

class _RunningView extends ConsumerStatefulWidget {
  const _RunningView({required this.session});
  final StudySession session;

  @override
  ConsumerState<_RunningView> createState() => _RunningViewState();
}

class _RunningViewState extends ConsumerState<_RunningView> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.session;
    final estimate = s.items.fold<int>(0, (sum, i) => sum + (i.estimatedQuestions ?? 0));

    return Column(
      children: [
        const SizedBox(height: 32),
        ElapsedClock(
          startedAt: s.startedAt,
          style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w300, color: scheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          '${formatClock(s.startedAt)} itibarıyla, ${s.items.length} bölüm'
          '${estimate > 0 ? ', yaklaşık $estimate soru' : ''}',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          'Uygulamayı kapatsan da süre işlemeye devam eder.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: s.items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = s.items[i];
              final meta = [
                if (item.activity != null) item.activity!.label,
                if (item.pages.isNotEmpty) 'Sayfa ${item.pageSpec}',
                if (item.hasResults) '${item.correct ?? 0} D, ${item.wrong ?? 0} Y, ${item.blank ?? 0} B',
              ].join(', ');
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(item.label),
                  subtitle: meta.isEmpty ? null : Text(meta),
                  trailing: item.hasQuestions
                      ? IconButton(
                          tooltip: 'Yanlışları işaretle',
                          onPressed: _busy ? null : () => markSessionItem(context, ref, s, item),
                          icon: const Icon(Icons.checklist_rounded),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        if (s.hasQuestionWork)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              'Test biterken yanlışlarını işaretleyebilirsin; ders ve konu otomatik gelir.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('İptal et'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                    onPressed: _busy ? null : _finish,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Bitir'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cancel() async {
    final s = widget.session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oturumu iptal et?'),
        content: Text(
          'Oturum hiç başlamamış sayılır; ${formatDuration(DateTime.now().difference(s.startedAt))} '
          'süre kaydedilmez. Bu oturumda fotoğrafsız işaretlediğin sorular da silinir.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('İptal et')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(cancelStudySessionProvider).call(s.id);
      messenger.showSnackBar(const SnackBar(content: Text('Oturum iptal edildi.')));
      router.go(AppRoutes.home);
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final s = widget.session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oturumu bitir?'),
        content: Text(
          'Süre ${formatDuration(DateTime.now().difference(s.startedAt))} olarak kaydedilecek.'
          '${s.hasQuestionWork ? ' Doğru, yanlış ve boş sayılarını şimdi ya da daha sonra girebilirsin.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Çalışmaya devam et')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bitir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Oturum biter bitmez akış null yayınlar ve bu widget ağaçtan kalkabilir;
    // bu yüzden router ve messenger await'ten ÖNCE alınır.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final submit = ref.read(submitSessionResultsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(finishStudySessionProvider).call(s.id);
      if (s.hasQuestionWork) {
        unawaited(router.pushReplacement(AppRoutes.sessionResults(s.id)));
      } else {
        // Konu anlatımı, video, tekrar: girilecek sonuç yok, oturum doğrudan tamamlanır.
        await submit.call(s.id, const []);
        messenger.showSnackBar(const SnackBar(content: Text('Oturum kaydedildi.')));
        router.go(AppRoutes.home);
      }
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _NoActiveSession extends StatelessWidget {
  const _NoActiveSession();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Şu an süren bir oturum yok.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.pushReplacement(AppRoutes.newSession),
            child: const Text('Yeni oturum başlat'),
          ),
        ],
      ),
    );
  }
}
