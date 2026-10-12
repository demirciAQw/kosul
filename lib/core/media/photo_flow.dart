import 'package:flutter/material.dart';

import 'crop_screen.dart';
import 'photo_capture_service.dart';

/// "Kamerayla çek / Galeriden seç" sayfası. Vazgeçilirse null.
Future<PhotoSource?> askPhotoSource(BuildContext context) => showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamerayla çek'),
              onTap: () => Navigator.pop(sheet, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(sheet, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );

/// Çek/seç → uygulama içi kırpma → WebP. Herhangi bir adımda vazgeçilirse
/// null döner ve geçici dosya bırakmaz.
Future<CapturedPhoto?> capturePhoto(
  BuildContext context,
  PhotoCaptureService service,
  PhotoSource source, {
  required String title,
}) async {
  final original = await service.pickToTemp(source);
  if (original == null) return null;
  if (!context.mounted) {
    await PhotoCaptureService.deleteQuietly(original);
    return null;
  }
  final png = await CropScreen.open(context, sourcePath: original, title: title);
  if (png == null) {
    await PhotoCaptureService.deleteQuietly(original);
    return null;
  }
  try {
    final path = await service.compressToWebp(png);
    return CapturedPhoto(originalPath: original, path: path);
  } catch (_) {
    await PhotoCaptureService.deleteQuietly(original);
    rethrow;
  }
}

/// Her zaman orijinalden yeniden kırpar; vazgeçilirse null (mevcut fotoğraf geçerli kalır).
Future<CapturedPhoto?> recropPhoto(
  BuildContext context,
  PhotoCaptureService service,
  CapturedPhoto photo, {
  required String title,
}) async {
  final png = await CropScreen.open(context, sourcePath: photo.originalPath, title: title);
  if (png == null) return null;
  final path = await service.compressToWebp(png);
  return CapturedPhoto(originalPath: photo.originalPath, path: path);
}
