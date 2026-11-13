// v8.6.0 Anlık: ((…)) ayrıştırıcı, bağ yeniden hesabı, döngü engeli, silme
// seçenekleri, öneri sırası, esitlenmedi işaretleme ve içe aktarma.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/anlik/data/anlik_deposu.dart';
import 'package:kocum/features/anlik/domain/anlik.dart';
import 'package:kocum/features/anlik/domain/anlik_esitleme.dart';
import 'package:kocum/features/anlik/domain/etiket_kurallari.dart';
import 'package:kocum/features/anlik/domain/etiket_metni.dart';

class _Sayac implements IdGenerator {
  var i = 0;
  @override
  String next() => 'id${(++i).toString().padLeft(3, '0')}';
}

final _t0 = DateTime(2026, 11, 14, 10);

Etiket _e(String id, String ad, {bool silindi = false, DateTime? olusturma}) =>
    Etiket(id: id, ad: ad, normAd: ad.toLowerCase(), olusturma: olusturma ?? _t0, guncelleme: _t0, silindi: silindi);

Bag _ust(String id, String alt, String ust) => Bag(
  id: id,
  tip: BagTip.ust,
  kaynakTur: UcTur.etiket,
  kaynakId: alt,
  hedefTur: UcTur.etiket,
  hedefId: ust,
  olusturma: _t0,
  guncelleme: _t0,
);

Bag _etiketli(String id, String anlik, String etiket, {BagNeden neden = BagNeden.metin, bool silindi = false}) => Bag(
  id: id,
  tip: BagTip.etiketli,
  kaynakTur: UcTur.anlik,
  kaynakId: anlik,
  hedefTur: UcTur.etiket,
  hedefId: etiket,
  neden: neden,
  olusturma: _t0,
  guncelleme: _t0,
  silindi: silindi,
);

void main() {
  group('((…)) ayrıştırıcı', () {
    List<String> adlar(String m) => [for (final a in metinEtiketleri(m)) a.ad];

    test('basit, birden çok, Türkçe harfler', () {
      expect(adlar('((selam)) dedim, ((İstanbul)) güzel'), ['selam', 'İstanbul']);
      expect(metinEtiketAdlari('((Işık)) ve ((ışık))'), {'isik'});
      expect(adlar('((  çok   boşluk  ))'), ['çok boşluk']);
    });

    test('iç içe: en içteki alınır', () {
      expect(adlar('((a ((b)) c))'), ['b']);
      expect(adlar('(((x)))'), ['x']);
    });

    test('kapanmamış, boş, satır atlayan ve çok uzun atlanır', () {
      expect(adlar('((abc'), isEmpty);
      expect(adlar('(( )) ve (()) ve ((!!))'), isEmpty);
      expect(adlar('((iki\nsatır))'), isEmpty);
      expect(adlar('((${'a' * 41}))'), isEmpty);
      expect(adlar('((açık ((kapalı))'), ['kapalı']);
    });

    test('konumlar doğru', () {
      final a = metinEtiketleri('x ((his)) y').single;
      expect((a.bas, a.son), (2, 9));
    });

    test('yazarken açık etiket ve tamamlama', () {
      expect(acikEtiket('bugün ((ti', 10), (sorgu: 'ti', bas: 6));
      expect(acikEtiket('((his)) ', 8), isNull);
      expect(acikEtiket('ab', 2), isNull);
      final t = etiketiTamamla('bugün ((ti', 10, 'tiksinti');
      expect(t.metin, 'bugün ((tiksinti)) ');
      expect(t.imlec, t.metin.length);
      // Önceden kapatılmışsa çift kapanış olmaz.
      final t2 = etiketiTamamla('((ti)) sonra', 4, 'tiksinti');
      expect(t2.metin, '((tiksinti)) sonra');
    });

    test('düz yazıya çevirme ve yeniden adlandırma', () {
      expect(etiketiDuzYaziYap('((His)) ve ((başka)) ve ((his))', 'his'), 'His ve ((başka)) ve his');
      expect(etiketiYenidenAdlandir('((his)) var', 'his', 'duygu'), '((duygu)) var');
    });
  });

  group('bağ kuralları', () {
    test('metin bağları: ekle, sil, geri getir; şerit bağlarına dokunulmaz', () {
      final mevcut = [
        _etiketli('b1', 'a', 'e1'),
        _etiketli('b2', 'a', 'e2', silindi: true),
        _etiketli('b3', 'a', 'e3', neden: BagNeden.serit),
      ];
      final f = metinBagFarki(metindekiler: {'e2', 'e4'}, mevcut: mevcut);
      expect(f.ekle, {'e4'});
      expect([for (final b in f.geriGetir) b.id], ['b2']);
      expect([for (final b in f.sil) b.id], ['b1']);
    });

    test('döngü engeli', () {
      final baglar = [_ust('u1', 'tiksinti', 'his'), _ust('u2', 'his', 'duygu')];
      expect(donguOlurMu(altId: 'duygu', ustId: 'tiksinti', baglar: baglar), isTrue);
      expect(donguOlurMu(altId: 'his', ustId: 'his', baglar: baglar), isTrue);
      expect(donguOlurMu(altId: 'tiksinti', ustId: 'duygu', baglar: baglar), isFalse);
      expect(altlariylaBirlikte('duygu', baglar), {'duygu', 'his', 'tiksinti'});
      expect(anaEtiketMi('duygu', baglar), isTrue);
      expect(anaEtiketMi('his', baglar), isFalse);
    });

    test('ağaç: ana etiketler başlık, altları girintili; çok üstlü her yerde', () {
      final etiketler = [_e('his', 'his'), _e('tik', 'tiksinti'), _e('mut', 'mutluluk'), _e('ok', 'okul')];
      final baglar = [_ust('u1', 'tik', 'his'), _ust('u2', 'mut', 'his'), _ust('u3', 'tik', 'ok')];
      final a = etiketAgaci(etiketler, baglar);
      expect(
        [for (final s in a) '${'-' * s.derinlik}${s.etiket.ad}'],
        ['his', '-mutluluk', '-tiksinti', 'okul', '-tiksinti'],
      );
    });

    test('öneri sırası: son 7 gün, sonra en çok kullanılan, sonra ad', () {
      final simdi = DateTime(2026, 11, 14);
      final etiketler = [_e('a', 'ayşe'), _e('b', 'bıkkınlık'), _e('c', 'can'), _e('d', 'deniz')];
      final zaman = {
        'x1': simdi.subtract(const Duration(days: 30)),
        'x2': simdi.subtract(const Duration(days: 20)),
        'x3': simdi.subtract(const Duration(days: 2)),
      };
      final baglar = [
        _etiketli('1', 'x1', 'c'),
        _etiketli('2', 'x2', 'c'),
        _etiketli('3', 'x3', 'd'),
        _etiketli('4', 'x1', 'b'),
      ];
      final o = etiketOnerileri(etiketler: etiketler, baglar: baglar, anlikZamanlari: zaman, simdi: simdi);
      expect([for (final e in o) e.id], ['d', 'c', 'b', 'a']);
      final s = etiketOnerileri(etiketler: etiketler, baglar: baglar, anlikZamanlari: zaman, simdi: simdi, sorgu: 'N');
      expect([for (final e in s) e.id], ['d', 'c', 'b']); // hepsi "n" içerir; başta geçen yok
      expect(yeniEtiketGosterilsinMi(etiketler, 'Can'), isFalse);
      expect(yeniEtiketGosterilsinMi(etiketler, 'kantin'), isTrue);
      expect(yeniEtiketGosterilsinMi(etiketler, '  '), isFalse);
    });

    test('şerit: metindekiler çerçeveli, diğerleri kaldırılabilir', () {
      final etiketler = [_e('his', 'his'), _e('ok', 'okul')];
      final c = seritCipleri(
        metin: '((his)) oldu',
        etiketler: etiketler,
        anlikBaglari: [
          _etiketli('b', 'a', 'ok', neden: BagNeden.serit),
          _etiketli('m', 'a', 'his'),
        ],
      );
      expect([for (final x in c) (x.etiket.id, x.metinden, x.bag?.id)], [('his', true, null), ('ok', false, 'b')]);
    });

    test('silme planı: sadece bu ya da alt etiketleriyle; anlıklar kalır, metin düz yazıya döner', () {
      final etiketler = [_e('his', 'his'), _e('tik', 'tiksinti')];
      final baglar = [_ust('u', 'tik', 'his'), _etiketli('b1', 'a1', 'his'), _etiketli('b2', 'a2', 'tik')];
      final anliklar = [
        Anlik(id: 'a1', metin: '((his)) yoğun', olusturma: _t0, guncelleme: _t0),
        Anlik(id: 'a2', metin: '((tiksinti))', olusturma: _t0, guncelleme: _t0),
      ];
      final p1 = etiketSilmePlani(
        etiketId: 'his',
        altlariyla: false,
        etiketler: etiketler,
        baglar: baglar,
        anliklar: anliklar,
      );
      expect(p1.etiketler, {'his'});
      expect(p1.baglar, {'u', 'b1'});
      expect(p1.metniDegisenler, {'a1': 'his yoğun'});
      expect((p1.anlikSayisi, p1.altSayisi), (1, 1));
      final p2 = etiketSilmePlani(
        etiketId: 'his',
        altlariyla: true,
        etiketler: etiketler,
        baglar: baglar,
        anliklar: anliklar,
      );
      expect(p2.etiketler, {'his', 'tik'});
      expect(p2.baglar, {'u', 'b1', 'b2'});
      expect(p2.metniDegisenler.length, 2);
    });

    test('etiket birleştirme: en eski kalır', () {
      final h = etiketBirlestirmeHaritasi([
        _e('z', 'his', olusturma: DateTime(2026, 1, 2)),
        _e('y', 'his', olusturma: DateTime(2026, 1, 1)),
        _e('x', 'okul'),
      ]);
      expect(h, {'z': 'y'});
    });
  });

  group('içe aktarma', () {
    test('ön bilgideki zaman ve duygu; metin ve ((…)) korunur', () {
      final o = mdAnlikOku('---\nzaman: 2026-11-10 14:30\nduygu: -2\n---\n((garson)) çağıramadım\n', _t0)!;
      expect(o.zaman, DateTime(2026, 11, 10, 14, 30));
      expect(o.duygu, -2);
      expect(o.metin, '((garson)) çağıramadım');
      expect(mdAnlikOku('ön bilgisiz', _t0)!.zaman, _t0);
      expect(mdAnlikOku('---\nzaman: x\n---\n', _t0), isNull);
      expect(mdAnlikId('2026-11-10 Garson.md'), 'md-2026-11-10-garson');
    });
  });

  group('depo (veritabanı)', () {
    late AppDatabase db;
    late AnlikDeposu depo;
    var saat = _t0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      saat = _t0;
      depo = AnlikDeposu(db, _Sayac(), () => saat);
    });
    tearDown(() => db.close());

    test('kayıtta metin bağları kurulur, bilinmeyen ad bağ almaz; metinden silinince bağ kalkar', () async {
      final his = await depo.etiketOlustur(ad: 'his', tur: EtiketTur.duygu);
      final id = await depo.anlikKaydet(metin: '((His)) ve ((bilinmeyen))', duygu: -1);
      var b = (await depo.baglar()).where((x) => x.tip == BagTip.etiketli && x.etkin).toList();
      expect([for (final x in b) x.hedefId], [his.id]);
      await depo.anlikKaydet(id: id, metin: 'artık yok');
      b = (await depo.baglar()).where((x) => x.tip == BagTip.etiketli && x.etkin).toList();
      expect(b, isEmpty);
      // Geri yazılınca eski bağ geri gelir (yeni satır açılmaz).
      await depo.anlikKaydet(id: id, metin: '((his)) yine');
      expect((await depo.baglar()).where((x) => x.tip == BagTip.etiketli).length, 1);
    });

    test('şerit etiketi kaydedilmeden eklenir; × bağı siler, etiket kalır', () async {
      final ok = await depo.etiketOlustur(ad: 'okul', tur: EtiketTur.yer);
      final id = await depo.anlikKaydet(metin: 'sıkıldım', seritEtiketleri: {ok.id});
      final bag = (await depo.baglar()).single;
      expect((bag.neden, bag.kaynakId), (BagNeden.serit, id));
      await depo.bagKaldir(bag.id);
      expect((await depo.baglar()).single.silindi, isTrue);
      expect((await depo.etiketler()).single.silindi, isFalse);
    });

    test('aynı adla ikinci etiket olmaz; üst etiket ve döngü engeli', () async {
      final his = await depo.etiketOlustur(ad: 'his');
      expect(() => depo.etiketOlustur(ad: 'HİS '), throwsA(isA<EtiketHatasi>()));
      final tik = await depo.etiketOlustur(ad: 'tiksinti', ustId: his.id);
      expect(() => depo.ustEkle(his.id, tik.id), throwsA(isA<EtiketHatasi>()));
    });

    test('yeni etiket, metinde zaten geçen ((ad)) için bağ kurar', () async {
      await depo.anlikKaydet(metin: '((kantin)) kalabalık');
      expect(await depo.baglar(), isEmpty);
      await depo.etiketOlustur(ad: 'kantin');
      expect((await depo.baglar()).single.neden, BagNeden.metin);
    });

    test('etiket silme ve son silinenlerden geri alma', () async {
      final his = await depo.etiketOlustur(ad: 'his');
      final a = await depo.anlikKaydet(metin: '((his)) yoğun');
      saat = saat.add(const Duration(minutes: 1));
      final plan = await depo.etiketSil(his.id, altlariyla: false);
      expect(plan.anlikSayisi, 1);
      expect((await depo.anliklar()).single.metin, 'his yoğun');
      expect((await depo.anliklar()).single.silindi, isFalse);
      expect(sonSilinenler(await depo.etiketler(), saat).single.id, his.id);
      saat = saat.add(const Duration(minutes: 1));
      await depo.etiketGeriAl(his.id);
      final bag = (await depo.baglar()).single;
      expect((bag.silindi, bag.neden, bag.kaynakId), (false, BagNeden.serit, a));
    });

    test('esitlenmedi: değişen gider, eşitlenince kalkar; yolda değişen kalır', () async {
      final id = await depo.anlikKaydet(metin: 'bir');
      final giden = await depo.esitlenecekler();
      expect(giden['anliklar']!.single['metin'], 'bir');
      saat = saat.add(const Duration(seconds: 1));
      await depo.anlikKaydet(id: id, metin: 'iki'); // istek yoldayken değişti
      await depo.esitlendi(giden);
      expect((await depo.esitlenecekler())['anliklar']!.single['metin'], 'iki');
      await depo.esitlendi(await depo.esitlenecekler());
      expect(await depo.esitlenecekler(), isEmpty);
    });

    test('gelenler: yeni kayıt yazılır; telefonda değişmişse çakışma kopyası olur', () async {
      final id = await depo.anlikKaydet(metin: 'telefon');
      final n = await depo.gelenleriUygula({
        'anliklar': [
          {'id': id, 'metin': 'masa', 'olusturma': _t0.toUtc().toIso8601String(), 'guncelleme': 'x'},
          {'id': 'yeni', 'metin': 'masadan', 'olusturma': _t0.toUtc().toIso8601String()},
          {'bozuk': true},
        ],
      });
      expect(n, 2);
      final hepsi = {for (final a in await depo.anliklar()) a.id: a};
      expect(hepsi[id]!.metin, 'telefon');
      expect(hepsi['yeni']!.esitlenmedi, isFalse);
      final kopya = hepsi.values.firstWhere((a) => a.metin.startsWith('(çakışma'));
      expect(kopya.esitlenmedi, isTrue);
    });

    test('gelen etiket aynı adlıysa birleştirilir', () async {
      final yerel = await depo.etiketOlustur(ad: 'his');
      final a = await depo.anlikKaydet(metin: 'x', seritEtiketleri: {yerel.id});
      await depo.esitlendi(await depo.esitlenecekler());
      final eski = _t0.subtract(const Duration(days: 1)).toUtc().toIso8601String();
      await depo.gelenleriUygula({
        'etiketler': [
          {'id': 'uzak', 'ad': 'His', 'olusturma': eski, 'guncelleme': eski},
        ],
      });
      final etiketler = await depo.etiketler();
      expect(etiketler.where((e) => !e.silindi).single.id, 'uzak');
      expect((await depo.baglar()).single.hedefId, 'uzak');
      expect((await depo.baglar()).single.kaynakId, a);
    });

    test('md içe aktarma: etiketler oluşur, ikinci kez aktarılmaz', () async {
      final d = [(ad: '2026-11-10.md', icerik: '---\nzaman: 2026-11-10\n---\n((garson)) çağıramadım', zaman: _t0)];
      expect(await depo.mdIceAktar(d), (eklenen: 1, atlanan: 0));
      expect(await depo.mdIceAktar(d), (eklenen: 0, atlanan: 1));
      expect((await depo.etiketler()).single.ad, 'garson');
      expect((await depo.baglar()).single.neden, BagNeden.metin);
      expect((await depo.anliklar()).single.olusturma, DateTime(2026, 11, 10));
    });
  });
}
