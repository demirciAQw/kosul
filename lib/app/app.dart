import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/core_providers.dart';
import '../features/question_bank/question_bank_providers.dart';
import '../features/settings/domain/settings.dart';
import '../features/settings/settings_providers.dart';
import '../features/study_session/domain/study_session.dart';
import '../features/study_session/study_session_providers.dart';
import 'router.dart';
import 'theme.dart';

class KocumApp extends ConsumerStatefulWidget {
  const KocumApp({super.key});

  @override
  ConsumerState<KocumApp> createState() => _KocumAppState();
}

class _KocumAppState extends ConsumerState<KocumApp> {
  @override
  void initState() {
    super.initState();
    // Bildirim, veritabanındaki gerçeğin yansımasıdır (tek doğruluk kaynağı).
    // Telefon yeniden başlayıp bildirim kaybolsa bile uygulama açılınca geri gelir.
    ref.listenManual<AsyncValue<StudySession?>>(
      runningSessionProvider,
      (previous, next) {
        if (!next.hasValue) return;
        final chronometer = ref.read(sessionChronometerProvider);
        final session = next.value;
        if (session == null) {
          chronometer.hide();
        } else if (previous?.value?.id != session.id) {
          chronometer.show(startedAt: session.startedAt, itemCount: session.items.length);
        }
      },
      fireImmediately: true,
    );

    // Hatırlatıcılar: uygulama açılınca ve bekleyen tekrar sayısı değişince
    // yeniden kurulur; bildirim metni güncel sayıyı söyler.
    void refreshReminders() {
      final s = ref.read(settingsProvider).value;
      if (s == null || !(s.reviewReminder || s.studyReminder)) return;
      unawaited(applyReminders(
        ref.read(reminderServiceProvider),
        s,
        due: ref.read(dueCountProvider).value ?? 0,
      ).catchError((_) {}));
    }

    ref.listenManual<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      if (previous?.hasValue != true && next.hasValue) refreshReminders();
    }, fireImmediately: true);
    ref.listenManual<AsyncValue<int>>(dueCountProvider, (previous, next) {
      if (next.hasValue && previous?.value != next.value) refreshReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Koçum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(settingsProvider).value?.themeMode ?? ThemeMode.system,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
