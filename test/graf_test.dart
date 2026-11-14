// v8.7 noktasal grafik: sarmal yerleşim, görünümler ve kuvvet düzeni (saf Dart).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/anlik/domain/anlik.dart';
import 'package:kocum/features/anlik/domain/graf.dart';
import 'package:kocum/features/anlik/domain/kuvvet_duzeni.dart';

final _t0 = DateTime(2026, 11, 9, 9); // pazartesi

Anlik _a(String id, int gun, {int? duygu}) => Anlik(
  id: id,
  metin: id,
  olusturma: _t0.add(Duration(days: gun)),
  guncelleme: _t0,
  duygu: duygu,
);

Etiket _e(String id) => Etiket(id: id, ad: id, normAd: id, olusturma: _t0, guncelleme: _t0);

Bag _b(
  String id,
  String k,
  String h, {
  BagTip tip = BagTip.etiketli,
  BagNeden neden = BagNeden.serit,
  BagDurum durum = BagDurum.onayli,
}) => Bag(
  id: id,
  tip: tip,
  kaynakTur: tip == BagTip.ust ? UcTur.etiket : UcTur.anlik,
  kaynakId: k,
  hedefTur: UcTur.etiket,
  hedefId: h,
  neden: neden,
  durum: durum,
  olusturma: _t0,
  guncelleme: _t0,
);

double _r(Dugum d) => math.sqrt(d.x * d.x + d.y * d.y);

void main() {
  final anliklar = [_a('a3', 2), _a('a1', 0, duygu: -2), _a('a2', 1, duygu: 2), _a('a4', 9)];
  final etiketler = [_e('his'), _e('tik'), _e('okul')];
  final baglar = [
    _b('u', 'tik', 'his', tip: BagTip.ust),
    _b('1', 'a1', 'tik', neden: BagNeden.metin),
    _b('2', 'a2', 'his'),
    _b('3', 'a3', 'okul', durum: BagDurum.onerildi),
  ];
  GrafVerisi g(GrafGorunum v, {Set<String> acik = const {}}) =>
      grafVerisi(v, anliklar: anliklar, etiketler: etiketler, baglar: baglar, acikAnaEtiketler: acik);

  test('sarmal: t=0 solda ve dışta, t=1 içte ve sağda; üstten geçer', () {
    final bas = sarmalNoktasi(0), son = sarmalNoktasi(1), orta = sarmalNoktasi(1 / 3);
    expect(bas.x, closeTo(-sarmalR, 1e-9));
    expect(bas.y.abs(), lessThan(1e-9));
    expect(son.x, greaterThan(0)); // θ = π − 1,5π = −π/2 … sağ alt çeyreğe yakın
    expect(math.sqrt(son.x * son.x + son.y * son.y), closeTo(sarmalR * 0.25, 1e-9));
    expect(orta.y, lessThan(0)); // üst (ekranda eksi y)
  });

  test('aynı girdi aynı konum; anlıklar tarih sırasına göre dizilir', () {
    final x = g(GrafGorunum.baglar), y = g(GrafGorunum.baglar);
    expect([for (final d in x.dugumler) (d.id, d.x, d.y)], [for (final d in y.dugumler) (d.id, d.x, d.y)]);
    final a1 = x.dugumler.firstWhere((d) => d.id == 'anlik:a1');
    final a4 = x.dugumler.firstWhere((d) => d.id == 'anlik:a4');
    expect(a1.x, lessThan(0));
    expect(_r(a1), greaterThan(_r(a4)));
  });

  test('bağlar görünümü: bütün etiketler, önerilen bağ soluk, etiket komşularının ortasında', () {
    final x = g(GrafGorunum.baglar);
    expect(x.dugumler.where((d) => d.tur == DugumTur.etiket).length, 3);
    expect(x.kenarlar.firstWhere((k) => k.a == 'anlik:a3').soluk, isTrue);
    final his = x.dugumler.firstWhere((d) => d.id == 'etiket:his');
    final a2 = x.dugumler.firstWhere((d) => d.id == 'anlik:a2');
    expect((his.x, his.y), (a2.x, a2.y));
  });

  test('metin içi: sadece ((…)) bağları', () {
    final x = g(GrafGorunum.metinIci);
    expect([for (final d in x.dugumler.where((d) => d.tur == DugumTur.etiket)) d.id], ['etiket:tik']);
    expect(x.kenarlar.length, 1);
  });

  test('takvim: 7 gün sonra açı başa döner ve yarıçap küçülür; hafta başı etiketli', () {
    final p0 = takvimNoktasi(0, 15), p7 = takvimNoktasi(7, 15);
    final r0 = math.sqrt(p0.x * p0.x + p0.y * p0.y), r7 = math.sqrt(p7.x * p7.x + p7.y * p7.y);
    expect(p7.x / r7, closeTo(p0.x / r0, 1e-9)); // aynı yön (açı ±π sarması önemsiz)
    expect(p7.y / r7, closeTo(p0.y / r0, 1e-9));
    expect(math.sqrt(p7.x * p7.x + p7.y * p7.y), lessThan(math.sqrt(p0.x * p0.x + p0.y * p0.y)));
    final x = g(GrafGorunum.takvim);
    final gunler = x.dugumler.where((d) => d.tur == DugumTur.gun).toList();
    expect(gunler.length, 10); // 9–18 Kasım
    expect(gunler.first.ad, '9–15 Kas');
    expect(gunler.first.yaricap, greaterThan(gunler[1].yaricap - 2.5)); // hafta başı büyük
    expect(x.dugumler.any((d) => d.tur == DugumTur.etiket), isFalse);
    expect(gunler[1].duygu, 2); // 10 Kasım: a2
    expect(gunler[3].duygu, isNull);
    final v = grafVerisi(
      GrafGorunum.takvim,
      anliklar: anliklar,
      etiketler: etiketler,
      baglar: baglar,
      vurguluEtiketler: {'his'},
    );
    expect(
      {
        for (final d in v.dugumler)
          if (d.vurgulu) d.id,
      },
      {'anlik:a1', 'anlik:a2'},
    ); // his + alt etiketi tik
  });

  test('ana etiketler: alt etiket düğümü yok, açılınca görünür', () {
    final x = g(GrafGorunum.anaEtiketler);
    final ad = {for (final d in x.dugumler.where((d) => d.tur == DugumTur.etiket)) d.id};
    expect(ad, {'etiket:his', 'etiket:okul'});
    final his = x.dugumler.firstWhere((d) => d.id == 'etiket:his');
    expect(his.katli, isTrue);
    expect(x.kenarlar.where((k) => k.b == 'etiket:his').length, 2); // a1 (tik üzerinden) ve a2
    final acik = g(GrafGorunum.anaEtiketler, acik: {'his'});
    expect(acik.dugumler.any((d) => d.id == 'etiket:tik'), isTrue);
  });

  test('etiket ağacı: anlık yok, sadece alt-üst kenarları', () {
    final x = g(GrafGorunum.etiketAgaci);
    expect(x.dugumler.every((d) => d.tur == DugumTur.etiket), isTrue);
    expect([for (final k in x.kenarlar) (k.a, k.b)], [('etiket:tik', 'etiket:his')]);
    expect(komsular(x, 'etiket:his'), {'etiket:his', 'etiket:tik'});
  });

  test('kuvvet düzeni: aynı girdi aynı sonuç; kaydırıcı solda sarmal korunur', () {
    final x = g(GrafGorunum.baglar);
    final k1 = kuvvetDuzeni(x, bag: 0.3), k2 = kuvvetDuzeni(x, bag: 0.3);
    expect(k1, k2);
    double sapma(Map<String, ({double x, double y})> k) => [
      for (final d in x.dugumler.where((d) => d.sabit))
        math.sqrt(math.pow(k[d.id]!.x - d.x, 2) + math.pow(k[d.id]!.y - d.y, 2)),
    ].reduce((a, b) => a + b);
    expect(sapma(kuvvetDuzeni(x, bag: 0)), lessThan(sapma(kuvvetDuzeni(x, bag: 1))));
  });

  test('2000 düğüm makul sürede', () {
    final cok = [for (var i = 0; i < 1500; i++) _a('x$i', i ~/ 10)];
    final ets = [for (var i = 0; i < 50; i++) _e('e$i')];
    final bs = [for (var i = 0; i < 1500; i++) _b('b$i', 'x$i', 'e${i % 50}')];
    final x = grafVerisi(GrafGorunum.baglar, anliklar: cok, etiketler: ets, baglar: bs);
    final sure = Stopwatch()..start();
    final k = kuvvetDuzeni(x);
    expect(k.length, 1550);
    expect(sure.elapsed, lessThan(const Duration(seconds: 20)));
  });
}
