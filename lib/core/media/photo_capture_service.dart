import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PhotoSource { camera, gallery }

class ImageCompressionException implements Exception {
  const ImageCompressionException();
  @override
  String toString() => 'Fotoğraf sıkıştırılamadı.';
}

/// Kayda hazır fotoğraf + yeniden kırpma için saklanan orijinal.
/// İkisi de önbellekte (geçici) durur; kayıt anında yalnızca [path] kalıcı depoya kopyalanır.
class CapturedPhoto {
  const CapturedPhoto({required this.originalPath, required this.path});

  final String originalPath; // kırpılmamış (en uzun kenar en fazla 4096 px)
  final String path; // kırpılmış + WebP

  List<String> get tempFiles => [originalPath, path];
}

/// Fotoğraf hattının platform tarafı: seç → (uygulama içi kırpma ekranı) → sıkıştır.
///
/// Kırpma artık harici bir Android ekranında (uCrop) değil, uygulamanın kendi
/// Flutter ekranında yapılır: durum çubuğuyla çakışma olmaz, tema tutarlı kalır.
///
/// Neden WebP ve kısa kenar 1440 px? Soru fotoğrafları metin ağırlıklıdır:
/// 1440 px üs/indis gibi küçük karakterleri net tutar; WebP %80 aynı netlikte
/// JPEG'den belirgin biçimde küçüktür. Kırpılan görüntü yeniden kodlandığı için
/// konum vb. meta veri taşınmaz.
class PhotoCaptureService {
  PhotoCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const shortSide = 1440;
  static const quality = 80;

  /// 50 MP'lik karede bile kırpma ekranı hızlı ve bellek dostu kalır;
  /// 1440 px hedefinin çok üstünde olduğu için netlik kaybettirmez.
  static const maxSourceSide = 4096.0;

  /// Seçilen/çekilen fotoğrafı uygulama önbelleğine alır. Vazgeçilirse null.
  Future<String?> pickToTemp(PhotoSource source) async {
    final picked = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxSourceSide,
      maxHeight: maxSourceSide,
      imageQuality: 95,
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

  /// Kırpma ekranının ürettiği görüntüyü (PNG) WebP'ye çevirip önbelleğe yazar.
  Future<String> compressToWebp(Uint8List encoded) async {
    final Uint8List out;
    try {
      out = await FlutterImageCompress.compressWithList(
        encoded,
        minWidth: shortSide,
        minHeight: shortSide,
        quality: quality,
        format: CompressFormat.webp,
        keepExif: false,
      );
    } catch (_) {
      throw const ImageCompressionException();
    }
    if (out.isEmpty) throw const ImageCompressionException();
    final temp = await getTemporaryDirectory();
    final target = p.join(temp.path, 'kocum_${_stamp()}.webp');
    await File(target).writeAsBytes(out, flush: true);
    return target;
  }

  static String _stamp() => '${DateTime.now().microsecondsSinceEpoch}';

  static Future<void> deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Önbellek dosyası; silinemezse işletim sistemi zaten temizler.
    }
  }
}
