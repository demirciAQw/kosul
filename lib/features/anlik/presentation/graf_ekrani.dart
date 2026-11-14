// Noktasal grafik ekranı: o anki arama ve filtre sonucuyla (yoksa bütün
// anlıklarla) çizilir. Üstte görünüm seçici, altta "Düzen ↔ Bağ" kaydırıcısı;
// ikisi de hatırlanır. Düğüme dokun: anlık / etiket sayfası (ana etiketler
// görünümünde katlı etiket açılır). Etikete uzun bas: sadece komşuları vurgulanır.
// Çizim CustomPainter ile; grafik kütüphanesi yok. Hesap isolate içinde.
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/palette.dart';
import '../../../app/routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/core_providers.dart';
import '../anlik_providers.dart';
import '../domain/anlik.dart';
import '../domain/graf.dart';
import '../domain/kuvvet_duzeni.dart';
import 'etiketli_metin.dart';

/// Grafiğe ne gidecek: arama sonucu anlıklar (null = hepsi) ve takvimde
/// renklenecek etiketler.
class GrafGirdisi {
  const GrafGirdisi({this.anlikIds, this.etiketIds = const {}});
  final Set<String>? anlikIds;
  final Set<String> etiketIds;
}

const _gorunumAnahtari = 'graf.gorunum';
const _bagAnahtari = 'graf.bag';

class GrafEkrani extends ConsumerStatefulWidget {
  const GrafEkrani({super.key, this.girdi = const GrafGirdisi()});
  final GrafGirdisi girdi;

  @override
  ConsumerState<GrafEkrani> createState() => _GrafEkraniState();
}

class _GrafEkraniState extends ConsumerState<GrafEkrani> {
  var _gorunum = GrafGorunum.baglar;
  var _bag = 0.3; // kaydırıcının yeri
  var _bagHesap = 0.3; // hesapta kullanılan (kaydırıcı bırakılınca güncellenir)
  final _acik = <String>{};
  String? _vurgu;
  GrafVerisi? _veri;
  Map<String, ({double x, double y})>? _konum;
  var _hesapNo = 0;
  String _sonImza = '';

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_ayarlariOku());
  }

  Future<void> _ayarlariOku() async {
    final satirlar = await (_db.select(
      _db.appMeta,
    )..where((m) => m.metaKey.isIn([_gorunumAnahtari, _bagAnahtari]))).get();
    if (!mounted) return;
    setState(() {
      for (final r in satirlar) {
        if (r.metaKey == _gorunumAnahtari) _gorunum = GrafGorunum.coz(r.metaValue);
        if (r.metaKey == _bagAnahtari) _bag = _bagHesap = (double.tryParse(r.metaValue) ?? 0.3).clamp(0, 1);
      }
    });
  }

  void _kaydet(String anahtar, String deger) => unawaited(
    _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(metaKey: Value(anahtar), metaValue: Value(deger))),
  );

  void _hesapla(List<Anlik> anliklar, List<Etiket> etiketler, List<Bag> baglar) {
    final secili = widget.girdi.anlikIds;
    final liste = secili == null
        ? anliklar
        : [
            for (final a in anliklar)
              if (secili.contains(a.id)) a,
          ];
    final imza =
        '${_gorunum.name}|$_bagHesap|${_acik.join(',')}|${liste.length}|${etiketler.length}|${baglar.length}|'
        '${anliklar.isEmpty ? '' : anliklar.first.guncelleme}|${baglar.fold<int>(0, (s, b) => s + (b.silindi ? 1 : 0))}';
    if (imza == _sonImza) return;
    _sonImza = imza;
    final veri = grafVerisi(
      _gorunum,
      anliklar: liste,
      etiketler: etiketler,
      baglar: baglar,
      acikAnaEtiketler: _acik,
      vurguluEtiketler: widget.girdi.etiketIds,
    );
    final no = ++_hesapNo;
    final bag = _bagHesap;
    _veri = veri;
    unawaited(
      _duzenHesapla(veri, bag).then((k) {
        if (mounted && no == _hesapNo) setState(() => _konum = k);
      }),
    );
  }

  Dugum? _bul(Offset p) {
    final veri = _veri, konum = _konum;
    if (veri == null || konum == null) return null;
    Dugum? en;
    var enUzak = double.infinity;
    for (final d in veri.dugumler) {
      final k = konum[d.id];
      if (k == null) continue;
      final uzak = (Offset(k.x, k.y) - p).distance;
      if (uzak <= math.max(d.yaricap + 6, 12) && uzak < enUzak) {
        en = d;
        enUzak = uzak;
      }
    }
    return en;
  }

  void _dokun(Offset p) {
    final d = _bul(p);
    if (d == null) {
      if (_vurgu != null) setState(() => _vurgu = null);
      return;
    }
    if (d.tur == DugumTur.anlik) {
      context.push(AppRoutes.anlikDuzenle(d.id.substring('anlik:'.length)));
    } else if (d.tur == DugumTur.etiket) {
      final id = d.id.substring('etiket:'.length);
      if (_gorunum == GrafGorunum.anaEtiketler && (d.katli || _acik.contains(id))) {
        setState(() {
          _acik.contains(id) ? _acik.remove(id) : _acik.add(id);
          _konum = null;
        });
      } else {
        context.push(AppRoutes.anlikEtiket(id));
      }
    }
  }

  void _uzunBas(Offset p) {
    final d = _bul(p);
    setState(() => _vurgu = d?.tur == DugumTur.etiket && d!.id != _vurgu ? d.id : null);
  }

  @override
  Widget build(BuildContext context) {
    final anliklar = ref.watch(anliklarProvider).value;
    final etiketler = ref.watch(etiketlerProvider).value;
    final baglar = ref.watch(baglarProvider).value;
    if (anliklar != null && etiketler != null && baglar != null) _hesapla(anliklar, etiketler, baglar);
    final veri = _veri, konum = _konum;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grafik'),
        actions: [
          DropdownButton<GrafGorunum>(
            value: _gorunum,
            underline: const SizedBox.shrink(),
            items: [for (final g in GrafGorunum.values) DropdownMenuItem(value: g, child: Text(g.ad))],
            onChanged: (g) {
              if (g == null) return;
              _kaydet(_gorunumAnahtari, g.name);
              setState(() {
                _gorunum = g;
                _konum = null;
                _vurgu = null;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (widget.girdi.anlikIds != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Arama sonucu: ${widget.girdi.anlikIds!.length} anlık',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          Expanded(
            child: veri == null || konum == null
                ? const Center(child: CircularProgressIndicator())
                : veri.dugumler.isEmpty
                ? const Center(child: Text('Gösterilecek bir şey yok.'))
                : LayoutBuilder(
                    builder: (context, kutu) {
                      // Dünya sınırları: bütün düğümler sığsın.
                      var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
                      for (final k in konum.values) {
                        minX = math.min(minX, k.x);
                        minY = math.min(minY, k.y);
                        maxX = math.max(maxX, k.x);
                        maxY = math.max(maxY, k.y);
                      }
                      const pay = 60.0;
                      final w = maxX - minX + 2 * pay, h = maxY - minY + 2 * pay;
                      final olcek = math.min(kutu.maxWidth / w, kutu.maxHeight / h);
                      final kaydir = Offset(pay - minX, pay - minY);
                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 12,
                        boundaryMargin: const EdgeInsets.all(400),
                        child: SizedBox(
                          width: kutu.maxWidth,
                          height: kutu.maxHeight,
                          child: GestureDetector(
                            onTapUp: (e) => _dokun(e.localPosition / olcek - kaydir),
                            onLongPressStart: (e) => _uzunBas(e.localPosition / olcek - kaydir),
                            child: CustomPaint(
                              painter: _GrafRessami(
                                veri: veri,
                                konum: konum,
                                olcek: olcek,
                                kaydir: kaydir,
                                vurgu: _vurgu == null ? null : komsular(veri, _vurgu!),
                                parlaklik: Theme.of(context).brightness,
                                yaziRengi: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Text('Düzen'),
                  Expanded(
                    child: Slider(
                      value: _bag,
                      onChanged: (v) => setState(() => _bag = v),
                      onChangeEnd: (v) {
                        _kaydet(_bagAnahtari, v.toStringAsFixed(2));
                        setState(() {
                          _bagHesap = v;
                          _konum = null;
                        });
                      },
                    ),
                  ),
                  const Text('Bağ'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üst düzey fonksiyon: kapanış ekranın durumunu (gönderilemez nesneler)
/// yakalamasın, isolate'e sadece veri gitsin.
Future<Map<String, ({double x, double y})>> _duzenHesapla(GrafVerisi veri, double bag) =>
    Isolate.run(() => kuvvetDuzeni(veri, bag: bag));

Color _duyguRengi(double? d, Brightness p) {
  if (d == null) return p == Brightness.dark ? KocumColors.grey500 : KocumColors.grey500;
  if (d < -0.5) return Color.lerp(KocumColors.grey500, KocumColors.red, (-d / 3).clamp(0.3, 1))!;
  if (d > 0.5) return Color.lerp(KocumColors.grey500, KocumColors.green, (d / 3).clamp(0.3, 1))!;
  return KocumColors.amber;
}

class _GrafRessami extends CustomPainter {
  _GrafRessami({
    required this.veri,
    required this.konum,
    required this.olcek,
    required this.kaydir,
    required this.vurgu,
    required this.parlaklik,
    required this.yaziRengi,
  });

  final GrafVerisi veri;
  final Map<String, ({double x, double y})> konum;
  final double olcek;
  final Offset kaydir;
  final Set<String>? vurgu;
  final Brightness parlaklik;
  final Color yaziRengi;

  Offset? _p(String id) {
    final k = konum[id];
    return k == null ? null : (Offset(k.x, k.y) + kaydir) * olcek;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cizgi = Paint()
      ..strokeWidth = 1
      ..color = yaziRengi.withValues(alpha: 0.18);
    final soluk = Paint()
      ..strokeWidth = 1
      ..color = yaziRengi.withValues(alpha: 0.12);
    for (final k in veri.kenarlar) {
      final a = _p(k.a), b = _p(k.b);
      if (a == null || b == null) continue;
      final silik = vurgu != null && !(vurgu!.contains(k.a) && vurgu!.contains(k.b));
      if (k.soluk) {
        _kesikli(canvas, a, b, silik ? (Paint()..color = Colors.transparent) : soluk);
      } else {
        canvas.drawLine(a, b, silik ? (Paint()..color = yaziRengi.withValues(alpha: 0.04)) : cizgi);
      }
    }
    for (final d in veri.dugumler) {
      final p = _p(d.id);
      if (p == null) continue;
      final silik = vurgu != null && !vurgu!.contains(d.id);
      var renk = switch (d.tur) {
        DugumTur.etiket => etiketRengi(d.etiket, parlaklik: parlaklik),
        DugumTur.gun => _duyguRengi(d.duygu, parlaklik),
        DugumTur.anlik => d.vurgulu ? KocumColors.blue : _duyguRengi(d.duygu, parlaklik),
      };
      if (silik) renk = renk.withValues(alpha: 0.15);
      final r = math.max(1.5, d.yaricap * math.sqrt(olcek));
      canvas.drawCircle(p, r, Paint()..color = renk);
      if (d.katli) {
        canvas.drawCircle(
          p,
          r + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = renk,
        );
      }
      if (d.ad.isNotEmpty && d.tur != DugumTur.anlik && !silik) {
        final yazi = TextPainter(
          text: TextSpan(
            text: d.ad,
            style: TextStyle(fontSize: d.tur == DugumTur.gun ? 10 : 12, color: yaziRengi),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: 140);
        yazi.paint(canvas, p + Offset(-yazi.width / 2, r + 2));
      }
    }
  }

  void _kesikli(Canvas c, Offset a, Offset b, Paint p) {
    final uzunluk = (b - a).distance;
    if (uzunluk == 0) return;
    final yon = (b - a) / uzunluk;
    for (var t = 0.0; t < uzunluk; t += 8) {
      c.drawLine(a + yon * t, a + yon * math.min(t + 4, uzunluk), p);
    }
  }

  @override
  bool shouldRepaint(_GrafRessami eski) =>
      eski.veri != veri || eski.konum != konum || eski.olcek != olcek || eski.vurgu != vurgu;
}
