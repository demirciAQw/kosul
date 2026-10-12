import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/di/core_providers.dart';
import 'core/media/local_media_storage.dart';
import 'core/notifications/session_chronometer.dart';
import 'features/curriculum/data/curriculum_data.dart';

/// Kompozisyon kökü: asenkron altyapı burada kurulur ve DI'a verilir.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15 uygulamaları kenardan kenara çizer. Bunu her sürümde aynı
  // yapıyoruz; üst ve alt boşlukları AppBar, SafeArea ve NavigationBar bırakır.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  final database = AppDatabase();
  final media = await LocalMediaStorage.open();
  final chronometer = SessionChronometer();
  await Future.wait<void>([
    CurriculumSeeder(database).run(),
    chronometer.init(),
  ]);

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      mediaStorageProvider.overrideWithValue(media),
      sessionChronometerProvider.overrideWithValue(chronometer),
    ],
    child: const KocumApp(),
  ));
}
