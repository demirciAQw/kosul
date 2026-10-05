import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/question_bank/question_bank_providers.dart';

/// Alt gezinme çubuğu: Bugün, Plan, Defter, Analiz.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueCountProvider).value ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer_rounded),
            label: 'Bugün',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: due,
              isLabelVisible: due > 0,
              child: const Icon(Icons.collections_bookmark_outlined),
            ),
            selectedIcon: Badge.count(
              count: due,
              isLabelVisible: due > 0,
              child: const Icon(Icons.collections_bookmark_rounded),
            ),
            label: 'Defter',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Analiz',
          ),
        ],
      ),
    );
  }
}
