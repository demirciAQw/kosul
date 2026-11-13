// Bilgisayardaki `koc sunucu` ile konuşan HTTP istemcisi (dart:io, ek paket yok).
//
// Her yöntem bir uç noktaya karşılık gelir: /merhaba, /esle/basla, /esle,
// /esitle, /eslemeyi-kaldir. Gövde JSON'dur; büyük gövde (yedek) gzip ile
// sıkıştırılır. Hatalar KocHatasi olarak kısa bir Türkçe açıklamayla gelir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sunucunun kendini tanıttığı bilgi (`GET /merhaba`).
class KocSunucuBilgisi {
  const KocSunucuBilgisi({required this.adres, required this.port, required this.sunucuId, required this.ad});
  final String adres;
  final int port;
  final String sunucuId;
  final String ad;
}

class KocHatasi implements Exception {
  const KocHatasi(this.mesaj, {this.durum, this.cevapGelmedi = false});
  final String mesaj;

  /// İstek gitti ama cevap gelmedi (zaman aşımı). Aynı istek yeniden denenebilir.
  final bool cevapGelmedi;

  /// HTTP durum kodu (bağlantı kurulamadıysa null).
  final int? durum;

  /// Sunucu bu telefonu tanımıyor (eşleme bilgisayar tarafında kaldırılmış).
  bool get eslesmeYok => durum == 401;

  @override
  String toString() => mesaj;
}

class KocIstemcisi {
  KocIstemcisi({this.zamanAsimi = const Duration(seconds: 20), this.esitlemeSuresi = const Duration(minutes: 2)});
  final Duration zamanAsimi;

  /// Eşitleme isteğinin cevabı için beklenecek en uzun süre (yedek büyük olabilir).
  final Duration esitlemeSuresi;

  Uri _uri(String adres, int port, String yol) => Uri(scheme: 'http', host: adres, port: port, path: yol);

  Future<Map<String, dynamic>> _istek(
    String adres,
    int port,
    String yol, {
    Map<String, Object?>? govde,
    List<int>? gzipliGovde,
    String? anahtar,
    Duration? sure,
  }) async {
    final client = HttpClient()..connectionTimeout = sure ?? const Duration(seconds: 4);
    try {
      final post = govde != null || gzipliGovde != null;
      final req = await (post ? client.postUrl(_uri(adres, port, yol)) : client.getUrl(_uri(adres, port, yol))).timeout(
        sure ?? zamanAsimi,
      );
      if (anahtar != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $anahtar');
      if (post) {
        final bytes = gzipliGovde ?? utf8.encode(jsonEncode(govde));
        req.headers.contentType = ContentType.json;
        if (gzipliGovde != null) req.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(sure ?? zamanAsimi);
      final metin = await res.transform(utf8.decoder).join().timeout(sure ?? zamanAsimi);
      Object? json;
      try {
        json = jsonDecode(metin);
      } on FormatException {
        json = null;
      }
      final map = json is Map<String, dynamic> ? json : <String, dynamic>{};
      if (res.statusCode != 200) {
        throw KocHatasi(map['hata'] as String? ?? 'Bilgisayar ${res.statusCode} hatası verdi.', durum: res.statusCode);
      }
      return map;
    } on KocHatasi {
      rethrow;
    } on TimeoutException {
      throw const KocHatasi('Bilgisayar cevap vermedi.', cevapGelmedi: true);
    } on SocketException {
      throw const KocHatasi('Bilgisayara ulaşılamadı. Aynı Wi-Fi\'de mi, koc sunucu açık mı?');
    } on HttpException catch (e) {
      throw KocHatasi('Bağlantı koptu: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Adreste koç sunucusu var mı? Yoksa null (ağ taramasında çok kısa süreyle çağrılır).
  Future<KocSunucuBilgisi?> merhaba(String adres, int port, {Duration sure = const Duration(seconds: 2)}) async {
    try {
      final j = await _istek(adres, port, '/merhaba', sure: sure);
      if (j['uygulama'] != 'koc') return null;
      return KocSunucuBilgisi(
        adres: adres,
        port: port,
        sunucuId: j['sunucuId'] as String? ?? '',
        ad: j['ad'] as String? ?? adres,
      );
    } on KocHatasi {
      return null;
    }
  }

  /// Bilgisayar terminalde 6 haneli kod gösterir.
  Future<void> esleBasla(String adres, int port, {required String cihazAdi}) =>
      _istek(adres, port, '/esle/basla', govde: {'cihazAdi': cihazAdi});

  /// Doğru kodla anahtar alınır.
  Future<({String anahtar, String sunucuId, String ad})> esle(
    String adres,
    int port, {
    required String kod,
    required String cihazId,
    required String cihazAdi,
  }) async {
    final j = await _istek(adres, port, '/esle', govde: {'kod': kod, 'cihazId': cihazId, 'cihazAdi': cihazAdi});
    final anahtar = j['anahtar'];
    if (anahtar is! String || anahtar.isEmpty) throw const KocHatasi('Bilgisayar anahtar vermedi.');
    return (anahtar: anahtar, sunucuId: j['sunucuId'] as String? ?? '', ad: j['ad'] as String? ?? adres);
  }

  /// [gzipliGovde]: gzip ile sıkıştırılmış JSON (büyük olabilir; ana iş parçacığı dışında hazırlanır).
  Future<Map<String, dynamic>> esitle(String adres, int port, String anahtar, List<int> gzipliGovde) =>
      _istek(adres, port, '/esitle', gzipliGovde: gzipliGovde, anahtar: anahtar, sure: esitlemeSuresi);

  Future<void> eslemeyiKaldir(String adres, int port, String anahtar) =>
      _istek(adres, port, '/eslemeyi-kaldir', govde: const {}, anahtar: anahtar, sure: const Duration(seconds: 5));
}
