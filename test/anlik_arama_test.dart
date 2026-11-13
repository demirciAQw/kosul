// v8.6.1: Anlık araması (kısa yazım, ağırlıklar, filtreler, alt etiketler),
// etiket etiketi, yeniden adlandırma, birleştirme ve döngü engeli.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/anlik/data/anlik_deposu.dart';
import 'package:kocum/features/anlik/domain/anlik.dart';
import 'package:kocum/features/anlik/domain/anlik_arama.dart';
import 'package:kocum/features/anlik/domain/etiket_kurallari.dart';

class _Sayac implements IdGenerator {
  var i = 0;
  @override
  String next() => 'id${(++i).toString().padLeft(3, '0')}';
}

final _t0 = DateTime(2026, 11, 14, 10);

Etiket _e(String id, String ad) => Etiket(id: id, ad: ad, normAd: ad, olusturma: _t0, guncelleme: _t0);

Anlik _a(String id, String metin, {int gun = 0, int? duygu}) => Anlik(
  id: id,
  metin: metin,
  olusturma: _t0.add(Duration(days: gun)),
  guncelleme: _t0,
  duygu: duygu,
);

Bag _b(String id, String k, String h, {BagTip tip = BagTip.etiketli, BagNeden neden = BagNeden.serit}) => Bag(
  id: id,
  tip: tip,
  kaynakTur: tip == BagTip.ust ? UcTur.etiket : UcTur.anlik,
  kaynakId: k,
  hedefTur: UcTur.etiket,
  hedefId: h,
  neden: neden,
  olusturma: _t0,
  guncelleme: _t0,
);

void main() {
  group('kısa yazım', () {
    test('#his, -#ders, ((his)) ve serbest metin', () {
      final s = sorguCoz('kantin #His -#ders ((tiksinti)) çok -((okul)) #çok_sevdiğim');
      expect(s.metin, 'kantin çok');
      expect(s.dahil, {'his', 'tiksinti', 'cok sevdigim'});
      expect(s.haric, {'ders', 'okul'});
      expect(sorguCoz('a#b').dahil, isEmpty); // kelime ortasındaki # etiket değil
    });
  });

  group('arama', () {
    final etiketler = [_e('his', 'his'), _e('tik', 'tiksinti'), _e('ders', 'ders'), _e('kan', 'kantin')];
    final anliklar = [
      _a('a1', 'bugün çok yoruldum', gun: 0, duygu: -2),
      _a('a2', 'kantinde sıra', gun: 1, duygu: 1),
      _a('a3', 'matematik', gun: 2),
      _a('a4', 'etiketsiz bir not', gun: 3, duygu: 3),
    ];
    final baglar = [
      _b('u', 'tik', 'his', tip: BagTip.ust),
      _b('1', 'a1', 'tik', neden: BagNeden.metin),
      _b('2', 'a2', 'kan'),
      _b('3', 'a3', 'ders'),
      _b('4', 'a2', 'his'),
    ];
    List<String> ara(String kutu, [AnlikFiltresi f = const AnlikFiltresi()]) => [
      for (final a in anlikAra(anliklar: anliklar, etiketler: etiketler, baglar: baglar, kutu: kutu, filtre: f)) a.id,
    ];

    test('boş arama: hepsi, yeniden eskiye', () => expect(ara(''), ['a4', 'a3', 'a2', 'a1']));

    test('üst etiketle arama alt etiketlileri de getirir', () {
      expect(ara('#his'), ['a2', 'a1']);
      expect(ara('#tiksinti'), ['a1']);
      expect(ara('((his)) -#kantin'), ['a1']);
      expect(ara('#yok'), isEmpty);
    });

    test('etiket adı metinden ağır basar; yazım hatası tolere edilir', () {
      // "kantin": a2'nin etiketi (1.0) ve metni ("kantinde", 0.7)
      expect(ara('kantin').first, 'a2');
      expect(ara('tiksnti'), ['a1']);
      expect(ara('yoruldum'), ['a1']);
    });

    test('filtreler: hepsi / herhangi, tarih, duygu, nereden, etiketsiz', () {
      expect(ara('', const AnlikFiltresi(etiketler: {'his', 'kan'})), ['a2']);
      expect(ara('', const AnlikFiltresi(etiketler: {'tik', 'ders'}, mod: EtiketModu.herhangi)), ['a3', 'a1']);
      expect(
        ara('', AnlikFiltresi(baslangic: _t0.add(const Duration(days: 1)), bitis: _t0.add(const Duration(days: 2)))),
        ['a3', 'a2'],
      );
      expect(ara('', const AnlikFiltresi(duyguEnAz: 0)), ['a4', 'a2']); // duygusu boş olan elenir
      expect(ara('', const AnlikFiltresi(nedenler: {BagNeden.metin})), ['a1']);
      expect(ara('', const AnlikFiltresi(etiketsiz: true)), ['a4']);
      expect(const AnlikFiltresi().bos, isTrue);
    });
  });

  group('kurallar', () {
    test('birleştirme döngüsü: kaynağın üstü hedefin altındaysa', () {
      // a → b (a'nın üstü b), b → c ; a'yı c ile birleştir: c → b → c döngü
      final baglar = [_b('1', 'a', 'b', tip: BagTip.ust), _b('2', 'b', 'c', tip: BagTip.ust)];
      expect(birlestirmeDonguOlurMu(kaynakId: 'a', hedefId: 'c', baglar: baglar), isTrue);
      expect(birlestirmeDonguOlurMu(kaynakId: 'a', hedefId: 'b', baglar: baglar), isFalse); // kendine bağ silinir
      expect(birlestirmeDonguOlurMu(kaynakId: 'c', hedefId: 'a', baglar: baglar), isTrue);
    });

    test('yinelenen ve kendine bağlar silinir, en eski kalır', () {
      final baglar = [
        _b('1', 'x', 'e'),
        _b('2', 'x', 'e'),
        _b('3', 'x', 'e', neden: BagNeden.metin),
        _b('4', 'e', 'e', tip: BagTip.ust),
      ];
      expect(yinelenenBaglar(baglar), {'2', '4'});
    });
  });

  group('depo', () {
    late AppDatabase db;
    late AnlikDeposu depo;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      depo = AnlikDeposu(db, _Sayac(), () => _t0);
    });
    tearDown(() => db.close());

    test('yeniden adlandırma metni de günceller; aynı ad başka etikette varsa hata', () async {
      final his = await depo.etiketOlustur(ad: 'his');
      await depo.etiketOlustur(ad: 'duygu');
      await depo.anlikKaydet(metin: '((his)) ve ((His))');
      expect(metninde(normAd: 'his', anliklar: await depo.anliklar()).length, 1);
      expect(await depo.etiketYenidenAdlandir(his.id, 'hissiyat'), 1);
      expect((await depo.anliklar()).single.metin, '((hissiyat)) ve ((hissiyat))');
      expect(() => depo.etiketYenidenAdlandir(his.id, 'Duygu'), throwsA(isA<EtiketHatasi>()));
      await depo.etiketYenidenAdlandir(his.id, 'Hissiyat'); // sadece büyük harf: izinli
    });

    test('birleştirme: bağlar ve metin taşınır, çift bağ kalmaz, kaynak silinir', () async {
      final a = await depo.etiketOlustur(ad: 'üzgün');
      final b = await depo.etiketOlustur(ad: 'üzüntü');
      final alt = await depo.etiketOlustur(ad: 'yas', ustId: a.id);
      final x = await depo.anlikKaydet(metin: '((üzgün)) ((üzüntü))');
      await depo.etiketBirlestir(kaynakId: a.id, hedefId: b.id);
      final anlik = (await depo.anliklar()).single;
      expect(anlik.metin, '((üzüntü)) ((üzüntü))');
      final etkin = (await depo.baglar()).where((x) => !x.silindi).toList();
      expect(etkin.where((g) => g.tip == BagTip.etiketli && g.kaynakId == x).length, 1);
      expect(etkin.singleWhere((g) => g.tip == BagTip.ust).kaynakId, alt.id);
      expect(etkin.singleWhere((g) => g.tip == BagTip.ust).hedefId, b.id);
      expect((await depo.etiketler()).firstWhere((e) => e.id == a.id).silindi, isTrue);
    });

    test('etiket etiketi: alt ekleme ve döngü engeli', () async {
      final his = await depo.etiketOlustur(ad: 'his');
      final tik = await depo.etiketOlustur(ad: 'tiksinti');
      await depo.ustEkle(tik.id, his.id);
      await depo.ustEkle(tik.id, his.id); // ikinci kez: çift bağ yok
      expect((await depo.baglar()).length, 1);
      expect(() => depo.ustEkle(his.id, tik.id), throwsA(isA<EtiketHatasi>()));
    });
  });
}
