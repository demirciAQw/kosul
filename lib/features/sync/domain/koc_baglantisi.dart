// Bilgisayarla eşleme ve eşitlemenin saf kuralları (ağ ve veritabanı yok).
//
// Telefon, bilgisayardaki `koc sunucu`ya yerel ağda bağlanır. Burada: eşleme
// bilgisi, eşitleme durumu, isteğin ve cevabın biçimi, yedek özeti, "ne zaman
// denenir" kuralı ve aynı kayıt iki tarafta değişince ne olacağı.
// Sunucu tarafı aynı kuralları koc-arac/koc/esitleme.py içinde uygular.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const kocVarsayilanPort = 8765;
const kocServisAdi = '_koc._tcp.local';
const cakismaOneki = '(çakışma kopyası) ';

/// Otomatik eşitleme en fazla bu sıklıkla denenir.
const otomatikEsitlemeAraligi = Duration(minutes: 2);

/// Eşli bilgisayar. [anahtar] eşlemede bir kez verilir, sonraki her istekte gider.
class KocEslemesi {
  const KocEslemesi({
    required this.adres,
    required this.port,
    required this.anahtar,
    required this.sunucuId,
    required this.sunucuAdi,
  });

  final String adres;
  final int port;
  final String anahtar;
  final String sunucuId;
  final String sunucuAdi;

  KocEslemesi adresle(String yeniAdres, int yeniPort) =>
      KocEslemesi(adres: yeniAdres, port: yeniPort, anahtar: anahtar, sunucuId: sunucuId, sunucuAdi: sunucuAdi);

  Map<String, Object?> toJson() => {
    'adres': adres,
    'port': port,
    'anahtar': anahtar,
    'sunucuId': sunucuId,
    'sunucuAdi': sunucuAdi,
  };

  static KocEslemesi? fromJson(Object? j) {
    if (j is! Map) return null;
    final adres = j['adres'], anahtar = j['anahtar'];
    if (adres is! String || anahtar is! String || adres.isEmpty || anahtar.isEmpty) return null;
    return KocEslemesi(
      adres: adres,
      port: j['port'] is int ? j['port'] as int : kocVarsayilanPort,
      anahtar: anahtar,
      sunucuId: j['sunucuId'] as String? ?? '',
      sunucuAdi: j['sunucuAdi'] as String? ?? 'Bilgisayar',
    );
  }
}

/// Son eşitlemenin izi. [sonEsitleme] sunucunun saatidir (telefonun saati değil).
class EsitlemeDurumu {
  const EsitlemeDurumu({this.sonEsitleme, this.sonBasari, this.sonHata, this.sonOzet});

  final String? sonEsitleme;
  final DateTime? sonBasari;
  final String? sonHata;

  /// Sunucuya en son giden yedeğin özeti; aynıysa yedek yeniden gönderilmez.
  final String? sonOzet;

  EsitlemeDurumu basarili({required String sunucuZamani, required DateTime an, required String ozet}) =>
      EsitlemeDurumu(sonEsitleme: sunucuZamani, sonBasari: an, sonOzet: ozet);

  EsitlemeDurumu hatali(String hata) =>
      EsitlemeDurumu(sonEsitleme: sonEsitleme, sonBasari: sonBasari, sonHata: hata, sonOzet: sonOzet);

  Map<String, Object?> toJson() => {
    'sonEsitleme': sonEsitleme,
    'sonBasari': sonBasari?.toIso8601String(),
    'sonHata': sonHata,
    'sonOzet': sonOzet,
  };

  static EsitlemeDurumu fromJson(Object? j) {
    if (j is! Map) return const EsitlemeDurumu();
    return EsitlemeDurumu(
      sonEsitleme: j['sonEsitleme'] as String?,
      sonBasari: DateTime.tryParse(j['sonBasari'] as String? ?? ''),
      sonHata: j['sonHata'] as String?,
      sonOzet: j['sonOzet'] as String?,
    );
  }
}

/// Sunucu de aynı aralıkları kabul eder: 10.x, 172.16–31.x, 192.168.x.
bool ozelAgAdresi(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return false;
  final n = p.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return false;
  final a = n[0]!, b = n[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// mDNS çalışmazsa telefonun kendi /24 ağındaki diğer adresler sırayla denenir.
/// Telefona yakın adresler önce (ev ağlarında bilgisayar genelde küçük numaralıdır).
List<String> taranacakAdresler(String kendiIp) {
  if (!ozelAgAdresi(kendiIp)) return const [];
  final p = kendiIp.split('.');
  final kendi = int.parse(p[3]);
  final onek = '${p[0]}.${p[1]}.${p[2]}';
  final sonlar = [
    for (var i = 1; i <= 254; i++)
      if (i != kendi) i,
  ]..sort((x, y) => (x - kendi).abs().compareTo((y - kendi).abs()));
  return [for (final i in sonlar) '$onek.$i'];
}

/// "123 456", "123-456" gibi yazımları da kabul eder. Geçersizse null.
String? eslemeKodu(String girdi) {
  final rakamlar = girdi.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{6}$').hasMatch(rakamlar) ? rakamlar : null;
}

/// "192.168.1.5" ya da "192.168.1.5:9000". Geçersizse null.
({String adres, int port})? adresCoz(String girdi) {
  final s = girdi.trim();
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$').firstMatch(s);
  if (m == null) return null;
  final port = m.group(2) == null ? kocVarsayilanPort : int.parse(m.group(2)!);
  if (port < 1 || port > 65535 || !ozelAgAdresi(m.group(1)!)) return null;
  return (adres: m.group(1)!, port: port);
}

/// Otomatik denemelerde son denemeden beri [aralik] geçmediyse beklenir.
bool denemeZamaniGeldi(DateTime? sonDeneme, DateTime simdi, {Duration aralik = otomatikEsitlemeAraligi}) =>
    sonDeneme == null || simdi.difference(sonDeneme) >= aralik || simdi.isBefore(sonDeneme);

/// Yedeğin özeti. Dışa aktarma zamanı ([exportedAt]) özete girmez: veri aynıysa
/// özet de aynı kalır ve yedek yeniden gönderilmez.
String yedekOzeti(Map<String, dynamic> yedek) {
  final kopya = Map<String, dynamic>.of(yedek)..remove('exportedAt');
  return sha256.convert(utf8.encode(jsonEncode(kopya))).toString();
}

/// `POST /esitle` gövdesi. Yedek değişmediyse [yedek] null olur, sadece özet gider.
/// [istekId] tek kullanımlıktır: cevap yolda kaybolup aynı gövde yeniden
/// gönderilirse sunucu kayıtları ikinci kez uygulamaz, önceki cevabı verir.
Map<String, Object?> esitlemeIstegi({
  required String? sonEsitleme,
  required String ozet,
  String? istekId,
  Map<String, dynamic>? yedek,
  Map<String, List<Map<String, Object?>>> tablolar = const {},
}) => {
  'surum': 1,
  'sonEsitleme': sonEsitleme,
  'yedekOzeti': ozet,
  if (istekId != null) 'istekId': istekId,
  if (yedek != null) 'yedek': yedek,
  if (tablolar.isNotEmpty) 'tablolar': tablolar,
};

class EsitlemeCevabi {
  const EsitlemeCevabi({
    this.sunucuZamani,
    this.yedekGerekli = false,
    this.yedekKaydedildi = false,
    this.tablolar = const {},
  });

  final String? sunucuZamani;

  /// Telefon "yedek aynı" dedi ama sunucudaki farklı: tam yedek yeniden gönderilmeli.
  final bool yedekGerekli;
  final bool yedekKaydedildi;
  final Map<String, List<Map<String, Object?>>> tablolar;

  static EsitlemeCevabi fromJson(Object? j) {
    if (j is! Map) return const EsitlemeCevabi();
    final t = j['tablolar'];
    return EsitlemeCevabi(
      sunucuZamani: j['sunucuZamani'] as String?,
      yedekGerekli: j['yedekGerekli'] == true,
      yedekKaydedildi: j['yedekKaydedildi'] == true,
      tablolar: {
        if (t is Map)
          for (final e in t.entries)
            if (e.value is List)
              '${e.key}': [
                for (final k in e.value as List)
                  if (k is Map) k.cast<String, Object?>(),
              ],
      },
    );
  }
}

/// Eşitlenen bir kayıt (v8.6'dan itibaren anlık, etiket, bağ). [esitlenmedi]:
/// son eşitlemeden beri telefonda değişti.
class EsitKayit {
  const EsitKayit({required this.id, required this.veri, this.silindi = false, this.esitlenmedi = false});
  final String id;
  final Map<String, Object?> veri;
  final bool silindi;
  final bool esitlenmedi;
}

/// Sunucudan gelenler telefona nasıl yazılır.
///
/// Sunucu çakışmayı kendi tarafında çözer; ama telefon, istek yoldayken aynı
/// kaydı yeniden değiştirmiş olabilir. O zaman telefondaki kalır, gelen yeni
/// kimlikle "(çakışma kopyası)" olur ve bir sonraki eşitlemede sunucuya gider.
/// Gelen bir silme ise telefondaki değişiklik kalır (kopya gerekmez).
List<EsitKayit> sunucudanGelenleriUygula({
  required Map<String, EsitKayit> yerel,
  required List<Map<String, Object?>> gelenler,
  required String Function() yeniId,
}) {
  final yazilacak = <EsitKayit>[];
  for (final g in gelenler) {
    final id = g['id'];
    if (id is! String || id.isEmpty) continue;
    final silindi = g['silindi'] == true;
    final mevcut = yerel[id];
    if (mevcut != null && mevcut.esitlenmedi) {
      if (silindi) continue;
      final kopyaId = yeniId();
      final kopya = cakismaKopyasi(g, kopyaId);
      yazilacak.add(EsitKayit(id: kopyaId, veri: kopya, esitlenmedi: true));
      continue;
    }
    yazilacak.add(EsitKayit(id: id, veri: g, silindi: silindi));
  }
  return yazilacak;
}

Map<String, Object?> cakismaKopyasi(Map<String, Object?> kayit, String yeniId) {
  final kopya = Map<String, Object?>.of(kayit)..['id'] = yeniId;
  final metin = kopya['metin'];
  if (metin is String) {
    kopya['metin'] = '$cakismaOneki$metin';
  } else {
    kopya['cakismaKopyasi'] = true;
  }
  return kopya;
}

/// Silinmiş ve 30 günden eski kayıtlar kalıcı olarak temizlenebilir.
bool temizlenebilir({required bool silindi, required DateTime guncelleme, required DateTime simdi}) =>
    silindi && simdi.difference(guncelleme) > const Duration(days: 30);
