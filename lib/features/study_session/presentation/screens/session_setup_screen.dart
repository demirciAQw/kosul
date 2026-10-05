import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';
import '../widgets/topic_selection_view.dart';

/// Kitap › Ünite › Konu › Sayfa ağacından çoklu seçim + tek BAŞLA.
class SessionSetupScreen extends ConsumerStatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ne çalışacaksın?')),
      body: TopicSelectionView(
        actionLabel: 'BAŞLA',
        actionIcon: Icons.play_arrow_rounded,
        busy: _starting,
        onSubmit: _start,
      ),
    );
  }

  Future<void> _start(List<SessionItemDraft> drafts) async {
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(sessionChronometerProvider).requestPermission();
      await ref.read(startStudySessionProvider).call(drafts);
      // Kurulum sayfasının yerine geçer: geri tuşu ana ekrana döner.
      unawaited(router.pushReplacement(AppRoutes.activeSession));
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        action: e is SessionAlreadyRunningException
            ? SnackBarAction(
                label: 'Oturuma dön',
                onPressed: () => router.pushReplacement(AppRoutes.activeSession),
              )
            : null,
      ));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}
