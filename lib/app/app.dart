import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/core_providers.dart';
import '../features/question_bank/question_bank_providers.dart';
import '../features/notes/notes_providers.dart';
import '../features/ocr/ocr_providers.dart';
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
  /// Kamera uygulama öndeyken hazır, arka planda ya da kapanırken kapalı.
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ref.read(fastCameraProvider).warmUp()),
      onHide: () => unawaited(ref.read(fastCameraProvider).close()),
      onDetach: () => unawaited(ref.read(fastCameraProvider).close()),
    );
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

    // Fotoğraflardaki metin: sorular, notlar ya da kayıtlar değişince eksikler
    // arka plan kuyruğuna alınır (yeni soru eklenince kendiliğinden başlar).
    void syncOcr() {
      final cards = ref.read(allQuestionsProvider).value;
      final notes = ref.read(notesProvider).value;
      final records = ref.read(ocrRecordsProvider).value;
      if (cards == null || notes == null || records == null) return;
      unawaited(ref.read(ocrQueueProvider).sync(ocrJobsFor(cards, notes), records).catchError((_) {}));
    }

    ref.listenManual(allQuestionsProvider, (previous, next) => syncOcr());
    ref.listenManual(notesProvider, (previous, next) => syncOcr());
    ref.listenManual(ocrRecordsProvider, (previous, next) => syncOcr(), fireImmediately: true);
    ref.listenManual<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final settings = next.value;
      if (settings != null) ref.read(ocrQueueProvider).enabled = settings.ocrEnabled;
    }, fireImmediately: true);

    // Resim açıklaması (Gemini Nano): ayar açık ve cihaz hazırsa kuyruğa bağlanır;
    // sürüm değiştiği için eski sorular da bir kez yeniden işlenir.
    Future<void> syncGenAi() async {
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return;
      final queue = ref.read(ocrQueueProvider);
      final status = settings.genAiDescriptions ? await ref.read(genAiStatusProvider.future) : 'off';
      final wanted = status == 'available' ? ref.read(genAiDescriberProvider).describe : null;
      if ((wanted == null) != (queue.describe == null)) {
        queue.describe = wanted;
        syncOcr();
      }
    }

    ref.listenManual<AsyncValue<AppSettings>>(settingsProvider, (previous, next) => unawaited(syncGenAi()),
        fireImmediately: true);
    ref.listenManual<AsyncValue<String>>(genAiStatusProvider, (previous, next) => unawaited(syncGenAi()));

    // Hızlı fotoğraf modu: fotoğraf servisi ayarı izler.
    ref.listenManual<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final settings = next.value;
      if (settings == null) return;
      final capture = ref.read(photoCaptureProvider)..fast = settings.fastPhotos;
      // Performans modu: uygulama içi kamera; ayar açıksa öndeyken hazır bekler.
      final camera = ref.read(fastCameraProvider)..keepWarm = settings.fastPhotos && settings.warmCamera;
      capture.camera = settings.fastPhotos ? camera : null;
      unawaited(camera.keepWarm ? camera.warmUp() : camera.close());
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
