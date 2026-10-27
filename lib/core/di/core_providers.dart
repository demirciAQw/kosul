import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../media/media_storage.dart';
import '../media/photo_capture_service.dart';
import '../notifications/session_chronometer.dart';
import '../utils/id_generator.dart';
import '../media/fast_camera.dart';

// Asenkron başlatılan altyapı main() içinde override edilir.
final appDatabaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('appDatabaseProvider main() içinde override edilmeli'));
final mediaStorageProvider = Provider<MediaStorage>(
    (ref) => throw UnimplementedError('mediaStorageProvider main() içinde override edilmeli'));
final sessionChronometerProvider = Provider<SessionChronometer>(
    (ref) => throw UnimplementedError('sessionChronometerProvider main() içinde override edilmeli'));

final idGeneratorProvider = Provider<IdGenerator>((ref) => const UuidV7Generator());
final clockProvider = Provider<Clock>((ref) => DateTime.now);
final photoCaptureProvider = Provider<PhotoCaptureService>((ref) => PhotoCaptureService());

/// Uygulama içi kamera (performans modunda hazır tutulur).
final fastCameraProvider = Provider<FastCamera>((ref) {
  final camera = FastCamera();
  ref.onDispose(camera.close);
  return camera;
});
