import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PhotoSource { camera, gallery }

class ImageCompressionException implements Exception {
  const ImageCompressionException();
  @override
  String toString() => 'Fotoğraf sıkıştırılamadı.';
}

/// Kırpma ekranının renkleri; uygulama temasından türetilir.
class CropUiStyle {
  const CropUiStyle({required this.toolbar, required this.onToolbar, required this.accent});

  factory CropUiStyle.fromTheme(ThemeData theme) => CropUiStyle(
        toolbar: theme.colorScheme.surface,
        onToolbar: theme.colorScheme.onSurface,
        accent: theme.colorScheme.primary,
      );

  final Color toolbar;
  final Color onToolbar;
  final Color accent;
}

/// Kayda hazır fotoğraf + yeniden kırpma için saklanan tam çözünürlüklü orijinal.
/// İkisi de önbellekte (geçici) durur; kayıt anında yalnızca [path] kalıcı depoya kopyalanır.
class CapturedPhoto {
  const CapturedPhoto({required this.originalPath, required this.path});

  final String originalPath; // kırpılmamış, sıkıştırılmamış
  final String path; // kırpılmış + WebP

  List<String> get tempFiles => [originalPath, path];
}

/// Fotoğraf hattı: seç → kırp → sıkıştır.
///
/// Sıra önemli: kırpma TAM çözünürlüklü orijinal üzerinde yapılır, sıkıştırma
/// en sonda ve tek sefer uygulanır. Sayfanın tamamından küçük bir soruyu
/// ayıklasan bile metin net kalır; yeniden kırpmada kalite kaybı birikmez.
///
/// Neden WebP ve kısa kenar 1440 px? Soru fotoğrafları metin ağırlıklıdır:
/// 1440 px üs/indis gibi küçük karakterleri net tutar; WebP %80 aynı netlikte
/// JPEG'den belirgin biçimde küçüktür. EXIF yönü piksellere uygulanır, konum
/// vb. meta veri atılır.
class PhotoCaptureService {
  PhotoCaptureService({ImagePicker? picker, ImageCropper? cropper})
      : _picker = picker ?? ImagePicker(),
        _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  static const shortSide = 1440;
  static const quality = 80;

  /// Kırpma çıktısı için üst sınır: 50 MP'lik karede bile kırpma hızlı ve bellek
  /// dostu kalır; 1440 px hedefinin çok üstünde olduğu için netlik kaybettirmez.
  static const _cropMaxSide = 4096;

  /// Kırpma ekranında vazgeçilirse null döner ve hiçbir geçici dosya kalmaz.
  Future<CapturedPhoto?> capture(
    PhotoSource source, {
    required String title,
    required CropUiStyle style,
  }) async {
    final original = await _pickToTemp(source);
    if (original == null) return null;
    try {
      final processed = await _cropAndCompress(original, title: title, style: style);
      if (processed == null) {
        await _deleteQuietly(original);
        return null;
      }
      return CapturedPhoto(originalPath: original, path: processed);
    } catch (_) {
      await _deleteQuietly(original);
      rethrow;
    }
  }

  /// Orijinalden yeniden kırpar. Vazgeçilirse null döner; mevcut [photo] geçerli kalır.
  Future<CapturedPhoto?> recrop(
    CapturedPhoto photo, {
    required String title,
    required CropUiStyle style,
  }) async {
    final processed = await _cropAndCompress(photo.originalPath, title: title, style: style);
    return processed == null ? null : CapturedPhoto(originalPath: photo.originalPath, path: processed);
  }

  Future<String?> _pickToTemp(PhotoSource source) async {
    final picked = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    final temp = await getTemporaryDirectory();
    if (p.isWithin(temp.path, picked.path)) return picked.path;
    // Önbellek dışındaki bir dosya kullanıcıya ait olabilir: üzerinde asla
    // silme işlemi yapmamak için önce kendi önbelleğimize kopyala.
    final copy = p.join(temp.path, 'kocum_src_${_stamp()}${p.extension(picked.path)}');
    await File(picked.path).copy(copy);
    return copy;
  }

  Future<String?> _cropAndCompress(
    String sourcePath, {
    required String title,
    required CropUiStyle style,
  }) async {
    final cropped = await _cropper.cropImage(
      sourcePath: sourcePath,
      maxWidth: _cropMaxSide,
      maxHeight: _cropMaxSide,
      // Ara çıktı yüksek kalitede; asıl sıkıştırma aşağıda tek seferde yapılır.
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: style.toolbar,
          toolbarWidgetColor: style.onToolbar,
          activeControlsWidgetColor: style.accent,
          initAspectRatio: CropAspectRatioPreset.original,
          // Serbest kırpma: sayfadaki tek bir soruyu köşelerinden sürükleyerek ayıkla.
          lockAspectRatio: false,
          hideBottomControls: false, // döndürme ve ölçek kontrolleri görünür
          aspectRatioPresets: const [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio3x2,
          ],
        ),
      ],
    );
    if (cropped == null) return null;

    try {
      final temp = await getTemporaryDirectory();
      final target = p.join(temp.path, 'kocum_${_stamp()}.webp');
      final result = await FlutterImageCompress.compressAndGetFile(
        cropped.path,
        target,
        minWidth: shortSide,
        minHeight: shortSide,
        quality: quality,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (result == null) throw const ImageCompressionException();
      return result.path;
    } finally {
      await _deleteQuietly(cropped.path);
    }
  }

  static String _stamp() => '${DateTime.now().microsecondsSinceEpoch}';

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Önbellek dosyası; silinemezse işletim sistemi zaten temizler.
    }
  }
}
