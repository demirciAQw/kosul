// Eşitlemeyi yürütür: yedeği toplar, değişmediyse sadece özetini, değiştiyse
// tamamını (fotoğrafsız, gzip ile) bilgisayara gönderir ve durumu kaydeder.
//
// Otomatik denemeler (uygulama açılınca, oturum bitince) en fazla 2 dakikada
// bir yapılır ve koç bulunamazsa sessizce vazgeçer. Bilgisayarın IP'si
// değiştiyse mDNS ile yeni adresi bulup bir kez daha dener. Cevap gelmezse aynı
// isteği (aynı tek kullanımlık istekId ile) bir kez yeniden gönderir; sunucu
// kayıtları iki kez uygulamaz.
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
    this.kaynaklar = const [],
    IdGenerator? idUret,
  }) : idUret = idUret ?? const UuidV7Generator();

  final EslemeDeposu depo;
  final KocIstemcisi istemci;
  final KocBulucu bulucu;
  final Future<Map<String, dynamic>> Function() yedekTopla;
  final Clock saat;

  /// Yedeğin yanında giden kayıtlar (v8.6: anlıklar, etiketler, bağlar).
  final List<EsitKayitKaynagi> kaynaklar;

  /// Her eşitleme isteğine tek kullanımlık kimlik verir.
  final IdGenerator idUret;

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
    final tablolar = <String, List<Map<String, Object?>>>{};
    for (final k in kaynaklar) {
      tablolar.addAll(await k.esitlenecekler());
    }
    final id1 = idUret.next();
    var paket = await Isolate.run(() => esitlemePaketi(yedek, son, oncekiOzet, istekId: id1, tablolar: tablolar));
    var cevap = EsitlemeCevabi.fromJson(await _yolla(esleme, paket.gzip));
    if (cevap.yedekGerekli) {
      final id2 = idUret.next();
      paket = await Isolate.run(() => esitlemePaketi(yedek, son, null, istekId: id2, tablolar: tablolar));
      cevap = EsitlemeCevabi.fromJson(await _yolla(esleme, paket.gzip));
    }
    final zaman = cevap.sunucuZamani;
    if (zaman == null) throw const KocHatasi('Bilgisayarın cevabı anlaşılamadı.');
    // Önce gidenlerin işareti kalkar, sonra gelenler yazılır (çakışma kuralı
    // "telefonda hâlâ eşitlenmemiş" olanlara bakar).
    for (final k in kaynaklar) {
      await k.esitlendi(tablolar);
      await k.gelenleriUygula(cevap.tablolar);
    }
    return durum.basarili(sunucuZamani: zaman, an: saat(), ozet: paket.ozet);
  }

  /// Cevap gelmezse aynı gövde (aynı istekId) bir kez daha gönderilir.
  Future<Map<String, dynamic>> _yolla(KocEslemesi esleme, List<int> govde) async {
    try {
      return await istemci.esitle(esleme.adres, esleme.port, esleme.anahtar, govde);
    } on KocHatasi catch (e) {
      if (!e.cevapGelmedi) rethrow;
      return istemci.esitle(esleme.adres, esleme.port, esleme.anahtar, govde);
    }
  }
}

/// İstek gövdesini hazırlar (ana iş parçacığı dışında çalışır: yedek büyük olabilir).
/// [oncekiOzet] ile aynıysa yedek gönderilmez, sadece özet gider.
({String ozet, List<int> gzip, bool tam}) esitlemePaketi(
  Map<String, dynamic> yedek,
  String? sonEsitleme,
  String? oncekiOzet, {
  String? istekId,
  Map<String, List<Map<String, Object?>>> tablolar = const {},
}) {
  final ozet = yedekOzeti(yedek);
  final tam = ozet != oncekiOzet;
  final govde = esitlemeIstegi(
    sonEsitleme: sonEsitleme,
    ozet: ozet,
    istekId: istekId,
    yedek: tam ? yedek : null,
    tablolar: tablolar,
  );
  return (ozet: ozet, gzip: gzip.encode(utf8.encode(jsonEncode(govde))), tam: tam);
}
