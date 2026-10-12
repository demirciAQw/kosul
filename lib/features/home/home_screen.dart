import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/utils/formatters.dart';
import '../library/presentation/library_sheet.dart';
import '../question_bank/question_bank_providers.dart';
import '../study_session/domain/study_session.dart';
import '../study_session/presentation/widgets/elapsed_clock.dart';
import '../study_session/study_session_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final running = ref.watch(runningSessionProvider).value;
    final pending = ref.watch(pendingSessionsProvider).value ?? const <StudySession>[];
    final due = ref.watch(dueCountProvider).value ?? 0;
    final incomplete = ref.watch(incompleteCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Koçum'),
        actions: [
          IconButton(
            tooltip: 'Eksiklerini doldur',
            onPressed: pending.isEmpty ? null : () => _openPending(context, pending),
            icon: Badge.count(
              count: pending.length,
              isLabelVisible: pending.isNotEmpty,
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Kitaplarım',
            onPressed: () => showLibrarySheet(context),
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (running != null) _RunningCard(session: running) else const _StartCard(),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: ListTile(
                leading: Icon(Icons.pending_actions_outlined, color: theme.colorScheme.onTertiaryContainer),
                title: const Text('Eksiklerini doldur'),
                subtitle: Text('${pending.length} oturumun doğru/yanlış sayıları bekliyor'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openPending(context, pending),
              ),
            ),
          ],
          if (incomplete > 0) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.pending_actions_outlined, color: theme.colorScheme.primary),
                title: const Text('Eksikler'),
                subtitle: Text('$incomplete sorunun fotoğrafı, çözümü ya da nedeni eksik'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.incompleteQuestions),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.replay_rounded, color: theme.colorScheme.primary),
              title: const Text('Yanlışlarımı göster'),
              subtitle: Text(due > 0 ? '$due soru tekrar bekliyor' : 'Bugün tekrar edecek soru yok'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.review),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.add_a_photo_outlined),
            title: const Text('Soru ekle'),
            subtitle: const Text('Kitap dışı, deneme ya da Telegram sorusu'),
            onTap: () => context.push(AppRoutes.newQuestion),
          ),
          ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: const Text('Deneme ekle'),
            subtitle: const Text('Netlerini ders ders gir, yanlışları optikten işaretle'),
            onTap: () => context.push(AppRoutes.newMockExam),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('JSON şablonu içe aktar'),
            subtitle: const Text('Kitabın ünite, konu ve sayfaları tek dokunuşla gelsin'),
            onTap: () => importBookTemplateFlow(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Örnek kitabı ekle'),
            subtitle: const Text('345 TYT Matematik: uygulamayı denemek için'),
            onTap: () => importSampleBookFlow(context, ref),
          ),
        ],
      ),
    );
  }

  void _openPending(BuildContext context, List<StudySession> pending) {
    if (pending.length == 1) {
      context.push(AppRoutes.sessionResults(pending.first.id));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Sonuç bekleyen oturumlar')),
            for (final s in pending)
              ListTile(
                title: Text(formatShortDate(s.startedAt)),
                subtitle: Text('${formatDuration(s.elapsedAt(DateTime.now()))} süre, ${s.items.length} bölüm'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push(AppRoutes.sessionResults(s.id));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bugün ne çalışıyorsun?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Kitaptan konu ve sayfa seç ya da kitapsız çalış; tek dokunuşla sayacı başlat.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.newSession),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Yeni oturum'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.session});
  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(AppRoutes.activeSession),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Oturum sürüyor',
                        style: theme.textTheme.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
                    ElapsedClock(
                      startedAt: session.startedAt,
                      style: theme.textTheme.displaySmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    Text('${session.items.length} bölüm',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
