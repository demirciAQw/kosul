import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../domain/study_session.dart';
import '../study_session_providers.dart';

/// Hazır bir bölüm listesiyle oturumu başlatır ve süren oturum ekranını açar.
Future<void> launchSession(BuildContext context, WidgetRef ref, List<SessionItemDraft> drafts) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    await ref.read(sessionChronometerProvider).requestPermission();
    await ref.read(startStudySessionProvider).call(drafts);
    await router.push(AppRoutes.activeSession);
  } on StudySessionException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.message),
      action: e is SessionAlreadyRunningException
          ? SnackBarAction(label: 'Oturuma dön', onPressed: () => router.push(AppRoutes.activeSession))
          : null,
    ));
  }
}
