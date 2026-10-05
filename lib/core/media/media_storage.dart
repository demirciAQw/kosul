import 'dart:io';

/// Fotoğrafların kalıcı deposu. Veritabanına yalnızca GÖRELİ yol yazılır;
/// yedekten geri yüklemede ya da cihaz değişiminde mutlak yollar kırılmaz.
abstract interface class MediaStorage {
  /// [sourcePath]'i kalıcı klasöre KOPYALAR, göreli yolunu döndürür.
  /// (Taşımak yerine kopyalar: DB kaydı başarısız olursa kaynak dosya
  /// yeniden deneme için yerinde kalır.)
  Future<String> importFile(String sourcePath, {required String bucket});

  File resolve(String relativePath);

  Future<void> delete(String relativePath);

  /// Uygulama önbelleğindeki geçici dosyayı sessizce siler; asla hata fırlatmaz.
  /// Önbellek dışındaki yollar yok sayılır.
  Future<void> discardTemp(String? absolutePath);
}
