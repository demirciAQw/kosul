// Eşitlemeyi yürütür: yedeği toplar, değişmediyse sadece özetini, değiştiyse
// tamamını (fotoğrafsız, gzip ile) bilgisayara gönderir ve durumu kaydeder.
//
// Otomatik denemeler (uygulama açılınca, oturum bitince) en fazla 2 dakikada
// bir yapılır ve koç bulunamazsa sessizce vazgeçer. Bilgisayarın IP'si
// değiştiyse mDNS ile yeni adresi bulup bir kez daha dener.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../../core/utils/id_generator.dart';
import '../domain/koc_baglantisi.dart';
import 'esleme_deposu.dart';
import 'koc_bulucu.dart';
import 'koc_istemcisi.dart';

class KocEsitleyici {
  KocEsitleyici({
    required this.depo,
    required this.istemci,
    required this.bulucu,
    required this.yedekTopla,
    required this.saat,
    this.degisti,
  });

  final EslemeDeposu depo;
  final KocIstemcisi istemci;
  final KocBulucu bulucu;
  final Future<Map<String, dynamic>> Function() yedekTopla;
  final Clock saat;

  /// Durum değişince (arayüz yenilensin diye) çağrılır.
  final void Function()? degisti;

  DateTime? _sonDeneme;
  Future<EsitlemeDurumu?>? _suren;

  /// Eşitlemeyi dener. Eşli değilse ya da otomatik denemede vakit gelmediyse
  /// null döner. [zorla]: kullanıcı "Şimdi eşitle" dedi (aralık beklenmez,
  /// bilgisayarın yeni adresi ağ taranarak da aranır).
  Future<EsitlemeDurumu?> dene({bool zorla = false}) {
    final suren = _suren;
    if (suren != null) return suren;
    final simdi = saat();
    if (!zorla && !denemeZamaniGeldi(_sonDeneme, simdi)) return Future.value(null);
    _sonDeneme = simdi;
    final yeni = _calis(zorla).whenComplete(() => _suren = null);
    _suren = yeni;
    return yeni;
  }

  Future<EsitlemeDurumu?> _calis(bool zorla) async {
    var esleme = await depo.esleme();
    if (esleme == null) return null;
    final durum = await depo.durum();
    EsitlemeDurumu yeni;
    try {
      try {
        yeni = await _gonder(esleme, durum);
      } on KocHatasi catch (e) {
        if (e.durum != null) rethrow;
        // Bağlantı kurulamadı: bilgisayar başka bir adres almış olabilir.
        final bulunan = await bulucu.yeniden(esleme.sunucuId, tara: zorla);
        if (bulunan == null || (bulunan.adres == esleme.adres && bulunan.port == esleme.port)) rethrow;
        esleme = esleme.adresle(bulunan.adres, bulunan.port);
        await depo.eslemeKaydet(esleme);
        yeni = await _gonder(esleme, durum);
      }
    } on KocHatasi catch (e) {
      yeni = durum.hatali(e.eslesmeYok ? 'Bilgisayar bu telefonu tanımıyor. Eşlemeyi kaldırıp yeniden eşle.' : e.mesaj);
    } on Exception catch (e) {
      yeni = durum.hatali('Eşitlenemedi: $e');
    }
    await depo.durumKaydet(yeni);
    degisti?.call();
    return yeni;
  }

  Future<EsitlemeDurumu> _gonder(KocEslemesi esleme, EsitlemeDurumu durum) async {
    final yedek = await yedekTopla();
    final son = durum.sonEsitleme, oncekiOzet = durum.sonOzet;
    var paket = await Isolate.run(() => esitlemePaketi(yedek, son, oncekiOzet));
    var cevap = EsitlemeCevabi.fromJson(await istemci.esitle(esleme.adres, esleme.port, esleme.anahtar, paket.gzip));
    if (cevap.yedekGerekli) {
      paket = await Isolate.run(() => esitlemePaketi(yedek, son, null));
      cevap = EsitlemeCevabi.fromJson(await istemci.esitle(esleme.adres, esleme.port, esleme.anahtar, paket.gzip));
    }
    final zaman = cevap.sunucuZamani;
    if (zaman == null) throw const KocHatasi('Bilgisayarın cevabı anlaşılamadı.');
    return durum.basarili(sunucuZamani: zaman, an: saat(), ozet: paket.ozet);
  }
}

/// İstek gövdesini hazırlar (ana iş parçacığı dışında çalışır: yedek büyük olabilir).
/// [oncekiOzet] ile aynıysa yedek gönderilmez, sadece özet gider.
({String ozet, List<int> gzip, bool tam}) esitlemePaketi(
  Map<String, dynamic> yedek,
  String? sonEsitleme,
  String? oncekiOzet,
) {
  final ozet = yedekOzeti(yedek);
  final tam = ozet != oncekiOzet;
  final govde = esitlemeIstegi(sonEsitleme: sonEsitleme, ozet: ozet, yedek: tam ? yedek : null);
  return (ozet: ozet, gzip: gzip.encode(utf8.encode(jsonEncode(govde))), tam: tam);
}
