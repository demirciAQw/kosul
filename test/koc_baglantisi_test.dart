import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/features/sync/data/esleme_deposu.dart';
import 'package:kocum/features/sync/data/koc_bulucu.dart';
import 'package:kocum/features/sync/data/koc_esitleyici.dart';
import 'package:kocum/features/sync/data/koc_istemcisi.dart';
import 'package:kocum/features/sync/domain/koc_baglantisi.dart';

void main() {
  group('saf kurallar', () {
    test('özel ağ adresleri', () {
      for (final ip in ['192.168.1.5', '10.0.0.2', '172.16.0.1', '172.31.9.9']) {
        expect(ozelAgAdresi(ip), isTrue, reason: ip);
      }
      for (final ip in ['8.8.8.8', '172.32.0.1', '192.169.1.1', '1.2.3', '300.1.1.1', 'abc']) {
        expect(ozelAgAdresi(ip), isFalse, reason: ip);
      }
    });

    test('taranacak adresler: kendisi hariç 253 adres, yakınlar önce', () {
      final a = taranacakAdresler('192.168.1.40');
      expect(a.length, 253);
      expect(a, isNot(contains('192.168.1.40')));
      expect(a.take(2).toSet(), {'192.168.1.39', '192.168.1.41'});
      expect(taranacakAdresler('8.8.8.8'), isEmpty);
    });

    test('eşleme kodu ve elle adres', () {
      expect(eslemeKodu('123 456'), '123456');
      expect(eslemeKodu('123-456'), '123456');
      expect(eslemeKodu('12345'), isNull);
      expect(eslemeKodu('12a456'), isNull);
      expect(adresCoz(' 192.168.1.20 '), (adres: '192.168.1.20', port: kocVarsayilanPort));
      expect(adresCoz('10.0.0.3:9000'), (adres: '10.0.0.3', port: 9000));
      expect(adresCoz('8.8.8.8'), isNull);
      expect(adresCoz('192.168.1.20:0'), isNull);
      expect(adresCoz('bilgisayar'), isNull);
    });

    test('otomatik deneme en fazla 2 dakikada bir', () {
      final t = DateTime(2026, 11, 14, 10);
      expect(denemeZamaniGeldi(null, t), isTrue);
      expect(denemeZamaniGeldi(t, t.add(const Duration(seconds: 119))), isFalse);
      expect(denemeZamaniGeldi(t, t.add(const Duration(minutes: 2))), isTrue);
      // Telefonun saati geri alınırsa beklemede takılı kalmaz.
      expect(denemeZamaniGeldi(t, t.subtract(const Duration(minutes: 1))), isTrue);
    });

    test('yedek özeti dışa aktarma zamanından etkilenmez, veriden etkilenir', () {
      final a = {
        'format': 'kocum.backup',
        'exportedAt': '2026-11-14T10:00',
        'questions': [1],
      };
      final b = {...a, 'exportedAt': '2026-11-14T11:00'};
      final c = {
        ...a,
        'questions': [1, 2],
      };
      expect(yedekOzeti(a), yedekOzeti(b));
      expect(yedekOzeti(a), isNot(yedekOzeti(c)));
      expect(a['exportedAt'], '2026-11-14T10:00'); // girdi değişmez
    });

    test('istek: özet aynıysa yedek gitmez', () {
      final yedek = {'format': 'kocum.backup', 'questions': []};
      final ilk = esitlemePaketi(yedek, null, null);
      expect(ilk.tam, isTrue);
      final govde = jsonDecode(utf8.decode(gzip.decode(ilk.gzip))) as Map;
      expect(govde['yedek'], isNotNull);
      expect(govde['sonEsitleme'], isNull);
      final ikinci = esitlemePaketi(yedek, 'z1', ilk.ozet);
      expect(ikinci.tam, isFalse);
      final govde2 = jsonDecode(utf8.decode(gzip.decode(ikinci.gzip))) as Map;
      expect(govde2.containsKey('yedek'), isFalse);
      expect(govde2['yedekOzeti'], ilk.ozet);
      expect(govde2['sonEsitleme'], 'z1');
    });

    test('eşleme ve durum JSON gidiş-dönüş; bozuk girdi', () {
      const e = KocEslemesi(adres: '192.168.1.5', port: 8765, anahtar: 'k', sunucuId: 's', sunucuAdi: 'masa');
      final geri = KocEslemesi.fromJson(jsonDecode(jsonEncode(e.toJson())))!;
      expect(
        (geri.adres, geri.port, geri.anahtar, geri.sunucuId, geri.sunucuAdi),
        ('192.168.1.5', 8765, 'k', 's', 'masa'),
      );
      expect(KocEslemesi.fromJson({'adres': '', 'anahtar': 'k'}), isNull);
      expect(KocEslemesi.fromJson('bozuk'), isNull);
      final d = const EsitlemeDurumu().basarili(sunucuZamani: 'z', an: DateTime(2026, 1, 2), ozet: 'o').hatali('yok');
      final d2 = EsitlemeDurumu.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect((d2.sonEsitleme, d2.sonBasari, d2.sonHata, d2.sonOzet), ('z', DateTime(2026, 1, 2), 'yok', 'o'));
      // Başarılı eşitleme eski hatayı siler.
      expect(d2.basarili(sunucuZamani: 'z2', an: DateTime(2026), ozet: 'o').sonHata, isNull);
    });
  });

  group('çakışma kuralı (telefon tarafı)', () {
    var n = 0;
    String yeniId() => 'yeni${++n}';
    setUp(() => n = 0);

    test('telefonda değişmemiş kayıt gelen sürümle değişir', () {
      final y = sunucudanGelenleriUygula(
        yerel: {
          'a': const EsitKayit(id: 'a', veri: {'id': 'a', 'metin': 'eski'}),
        },
        gelenler: [
          {'id': 'a', 'metin': 'yeni'},
          {'id': 'b', 'metin': 'yepyeni'},
        ],
        yeniId: yeniId,
      );
      expect(
        [for (final k in y) (k.id, k.veri['metin'], k.esitlenmedi)],
        [('a', 'yeni', false), ('b', 'yepyeni', false)],
      );
    });

    test('iki tarafta değişirse telefondaki kalır, gelen kopya olur ve sunucuya gider', () {
      final y = sunucudanGelenleriUygula(
        yerel: {
          'a': const EsitKayit(id: 'a', veri: {'id': 'a', 'metin': 'telefon'}, esitlenmedi: true),
        },
        gelenler: [
          {'id': 'a', 'metin': 'masaüstü'},
        ],
        yeniId: yeniId,
      );
      expect(y.single.id, 'yeni1');
      expect(y.single.veri['metin'], '(çakışma kopyası) masaüstü');
      expect(y.single.veri['id'], 'yeni1');
      expect(y.single.esitlenmedi, isTrue);
    });

    test('gelen silme, telefondaki değişikliği silmez; değişmemiş kayıt silinir', () {
      final y = sunucudanGelenleriUygula(
        yerel: {
          'a': const EsitKayit(id: 'a', veri: {'id': 'a'}, esitlenmedi: true),
          'b': const EsitKayit(id: 'b', veri: {'id': 'b'}),
        },
        gelenler: [
          {'id': 'a', 'silindi': true},
          {'id': 'b', 'silindi': true},
          {'metin': 'kimliksiz'},
        ],
        yeniId: yeniId,
      );
      expect([for (final k in y) (k.id, k.silindi)], [('b', true)]);
    });

    test('metinsiz kayıtta kopya işaretlenir', () {
      final k = cakismaKopyasi({'id': 'x', 'ad': 'his'}, 'y');
      expect(k, {'id': 'y', 'ad': 'his', 'cakismaKopyasi': true});
    });

    test('silinenler 30 gün sonra temizlenebilir', () {
      final simdi = DateTime(2026, 3, 1);
      expect(temizlenebilir(silindi: true, guncelleme: DateTime(2026, 1, 15), simdi: simdi), isTrue);
      expect(temizlenebilir(silindi: true, guncelleme: DateTime(2026, 2, 15), simdi: simdi), isFalse);
      expect(temizlenebilir(silindi: false, guncelleme: DateTime(2020), simdi: simdi), isFalse);
    });
  });

  group('eşitleyici, sahte koç sunucusuna karşı', () {
    late HttpServer sunucu;
    late AppDatabase db;
    late EslemeDeposu depo;
    late List<Map<String, dynamic>> gelenler;
    String? sunucudakiOzet;
    var cevapKodu = 200;
    var saat = DateTime(2026, 11, 14, 10);
    var yedek = <String, dynamic>{'format': 'kocum.backup', 'exportedAt': 'x', 'questions': <Object>[]};

    setUp(() async {
      gelenler = [];
      sunucudakiOzet = null;
      cevapKodu = 200;
      sunucu = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      sunucu.listen((req) async {
        expect(req.headers.value(HttpHeaders.authorizationHeader), 'Bearer gizli');
        expect(req.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
        final ham = await req.fold<List<int>>([], (a, b) => a..addAll(b));
        final govde = jsonDecode(utf8.decode(gzip.decode(ham))) as Map<String, dynamic>;
        gelenler.add(govde);
        Map<String, Object?> cevap;
        if (cevapKodu != 200) {
          cevap = {'hata': 'Bu cihaz eşli değil.'};
        } else if (govde['yedek'] == null && govde['yedekOzeti'] != sunucudakiOzet) {
          cevap = {'yedekGerekli': true};
        } else {
          if (govde['yedek'] != null) sunucudakiOzet = govde['yedekOzeti'] as String;
          cevap = {'sunucuZamani': 'z${gelenler.length}', 'yedekKaydedildi': govde['yedek'] != null, 'tablolar': {}};
        }
        req.response
          ..statusCode = cevapKodu
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(cevap));
        await req.response.close();
      });
      db = AppDatabase(NativeDatabase.memory());
      var id = 0;
      depo = EslemeDeposu(db, () => 'cihaz${++id}');
      await depo.eslemeKaydet(
        KocEslemesi(adres: '127.0.0.1', port: sunucu.port, anahtar: 'gizli', sunucuId: 's1', sunucuAdi: 'masa'),
      );
    });

    tearDown(() async {
      await sunucu.close(force: true);
      await db.close();
    });

    KocEsitleyici esitleyici({KocBulucu? bulucu}) => KocEsitleyici(
      depo: depo,
      istemci: KocIstemcisi(),
      bulucu: bulucu ?? _SahteBulucu(null),
      yedekTopla: () async => yedek,
      saat: () => saat,
    );

    test('ilk eşitlemede tam yedek, sonra sadece özet; aralık beklenir', () async {
      final e = esitleyici();
      final d1 = await e.dene();
      expect(d1!.sonHata, isNull);
      expect(d1.sonEsitleme, 'z1');
      expect(gelenler.single['yedek'], isNotNull);
      expect(gelenler.single['sonEsitleme'], isNull);

      // 1 dakika sonra otomatik deneme yapılmaz.
      saat = saat.add(const Duration(minutes: 1));
      expect(await e.dene(), isNull);
      expect(gelenler.length, 1);

      // Elle istenirse hemen; veri aynı olduğu için yedek gitmez.
      final d2 = await e.dene(zorla: true);
      expect(d2!.sonEsitleme, 'z2');
      expect(gelenler.last.containsKey('yedek'), isFalse);
      expect(gelenler.last['sonEsitleme'], 'z1');
      expect((await depo.durum()).sonEsitleme, 'z2');
    });

    test('sunucu yedeği kaybettiyse tam yedek yeniden gider', () async {
      final e = esitleyici();
      await e.dene(zorla: true);
      sunucudakiOzet = 'başka';
      final d = await e.dene(zorla: true);
      expect(d!.sonHata, isNull);
      expect(gelenler.length, 3);
      expect(gelenler[1].containsKey('yedek'), isFalse);
      expect(gelenler[2]['yedek'], isNotNull);
    });

    test('veri değişince tam yedek gider', () async {
      final e = esitleyici();
      await e.dene(zorla: true);
      yedek = {
        ...yedek,
        'questions': [1],
      };
      await e.dene(zorla: true);
      expect(gelenler.last['yedek'], isNotNull);
    });

    test('eşleme bilgisayarda kaldırılmışsa anlaşılır hata kaydedilir', () async {
      cevapKodu = 401;
      final d = await esitleyici().dene(zorla: true);
      expect(d!.sonHata, contains('tanımıyor'));
      expect((await depo.durum()).sonHata, contains('tanımıyor'));
      expect(await depo.esleme(), isNotNull); // anahtar sessizce silinmez
    });

    test('adres değiştiyse yenisi bulunur ve kaydedilir', () async {
      final dogru = sunucu.port;
      await depo.eslemeKaydet(
        const KocEslemesi(adres: '127.0.0.1', port: 1, anahtar: 'gizli', sunucuId: 's1', sunucuAdi: 'masa'),
      );
      final d = await esitleyici(
        bulucu: _SahteBulucu(KocSunucuBilgisi(adres: '127.0.0.1', port: dogru, sunucuId: 's1', ad: 'masa')),
      ).dene(zorla: true);
      expect(d!.sonHata, isNull);
      expect((await depo.esleme())!.port, dogru);
    });

    test('koç yoksa hata kaydedilir ama eşleme kalır', () async {
      await depo.eslemeKaydet(
        const KocEslemesi(adres: '127.0.0.1', port: 1, anahtar: 'gizli', sunucuId: 's1', sunucuAdi: 'masa'),
      );
      final d = await esitleyici().dene(zorla: true);
      expect(d!.sonHata, isNotNull);
      expect(await depo.esleme(), isNotNull);
    });

    test('eşli değilse hiçbir şey yapılmaz; eşleme silinince telefon kimliği kalır', () async {
      final id = await depo.cihazId();
      await depo.eslemeyiSil();
      expect(await esitleyici().dene(zorla: true), isNull);
      expect(gelenler, isEmpty);
      expect(await depo.cihazId(), id);
    });
  });
}

class _SahteBulucu extends KocBulucu {
  _SahteBulucu(this._sonuc) : super(KocIstemcisi());
  final KocSunucuBilgisi? _sonuc;

  @override
  Future<KocSunucuBilgisi?> yeniden(String sunucuId, {bool tara = false}) async => _sonuc;
}
