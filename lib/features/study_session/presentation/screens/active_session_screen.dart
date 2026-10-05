import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';
import '../widgets/elapsed_clock.dart';

/// Süren oturum. Bilinçli olarak "duraklat" ya da "iptal" YOK: sayaç yalnızca
/// BİTİR ile kapanır. Geri tuşu oturumu etkilemez; ana ekranda kart olarak durur.
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
  bool _finishing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.session;
    final estimate = s.items.fold<int>(0, (sum, i) => sum + (i.estimatedQuestions ?? 0));

    return Column(
      children: [
        const SizedBox(height: 40),
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
        const SizedBox(height: 28),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: s.items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = s.items[i];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(item.label),
                  subtitle: item.pages.isEmpty ? null : Text('Sayfa ${item.pageSpec}'),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                onPressed: _finishing ? null : _finish,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Bitir'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _finish() async {
    final s = widget.session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oturumu bitir?'),
        content: Text(
          'Süre ${formatDuration(DateTime.now().difference(s.startedAt))} olarak kaydedilecek. '
          'Doğru, yanlış ve boş sayılarını şimdi ya da daha sonra girebilirsin.',
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
    setState(() => _finishing = true);
    try {
      await ref.read(finishStudySessionProvider).call(s.id);
      unawaited(router.pushReplacement(AppRoutes.sessionResults(s.id)));
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _finishing = false);
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
