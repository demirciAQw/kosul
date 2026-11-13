// Anlık ekranı: kendi kabuğu var (alt sekme yok). Üstte arama, ortada tarihli
// liste, altta her zaman açık yazma alanı. Sol üstteki düğme ana uygulamaya
// geçer; son açılan mod hatırlanır. Ayrıca: anlık düzenleme sayfası ve
// "Son silinenler" (etiketler 30 gün geri alınabilir).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/text/turkish_text.dart';
import '../../../core/utils/formatters.dart';
import '../../sync/sync_providers.dart';
import '../anlik_providers.dart';
import '../data/anlik_deposu.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'etiket_seridi.dart';
import 'etiketli_metin.dart';
import 'yazma_alani.dart';

class AnlikEkrani extends ConsumerStatefulWidget {
  const AnlikEkrani({super.key, this.yaz = false});

  /// Android kısayolu ("Anlık yaz"): yazma alanı odaklı açılır.
  final bool yaz;

  @override
  ConsumerState<AnlikEkrani> createState() => _AnlikEkraniState();
}

class _AnlikEkraniState extends ConsumerState<AnlikEkrani> {
  var _sorgu = '';

  @override
  void initState() {
    super.initState();
    unawaited(modKaydet(ref.read(appDatabaseProvider), anlik: true));
  }

  void _anaUygulama() {
    unawaited(modKaydet(ref.read(appDatabaseProvider), anlik: false));
    context.go(AppRoutes.home);
  }

  void _etiketAc(Etiket e) => context.push(AppRoutes.anlikEtiket(e.id));

  @override
  Widget build(BuildContext context) {
    final anliklar = ref.watch(anliklarProvider).value;
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final baglar = ref.watch(baglarProvider).value ?? const <Bag>[];
    final adla = {
      for (final e in etiketler)
        if (!e.silindi) e.normAd: e,
    };
    final q = normalizeTr(_sorgu);
    final gorunen = [
      for (final a in anliklar ?? const <Anlik>[])
        if (!a.silindi && (q.isEmpty || normalizeTr(a.metin).contains(q))) a,
    ];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Ana uygulama', icon: const Icon(Icons.apps_rounded), onPressed: _anaUygulama),
        titleSpacing: 0,
        title: TextField(
          decoration: const InputDecoration(
            hintText: 'Anlıklarda ara',
            prefixIcon: Icon(Icons.search_rounded),
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _sorgu = v),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'silinen') {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => const _SonSilinenler(),
                );
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'silinen', child: Text('Son silinen etiketler'))],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: anliklar == null
                ? const Center(child: CircularProgressIndicator())
                : gorunen.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        q.isEmpty ? 'Henüz anlık yok. Aşağıya kısaca ne olduğunu yaz.' : 'Sonuç yok.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: false,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: gorunen.length,
                    itemBuilder: (context, i) {
                      final a = gorunen[i];
                      final gunBasi = i == 0 || !_ayniGun(gorunen[i - 1].olusturma, a.olusturma);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (gunBasi)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(_gunBasligi(a.olusturma), style: Theme.of(context).textTheme.labelLarge),
                            ),
                          AnlikKarti(
                            anlik: a,
                            etiketler: etiketler,
                            baglar: baglar,
                            etiketBul: (n) => adla[n],
                            onEtiket: _etiketAc,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          YazmaAlani(
            otomatikOdak: widget.yaz,
            onEtiketAc: _etiketAc,
            onKaydedildi: () => unawaited(ref.read(kocEsitleyiciProvider).dene().catchError((_) => null)),
          ),
        ],
      ),
    );
  }
}

bool _ayniGun(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _gunBasligi(DateTime d) {
  final bugun = DateTime.now();
  if (_ayniGun(d, bugun)) return 'Bugün';
  if (_ayniGun(d, bugun.subtract(const Duration(days: 1)))) return 'Dün';
  return '${formatDate(d)}, ${weekdayShort(d)}';
}

/// Listede bir anlık: şerit, metin, saat ve duygu. Dokununca düzenleme açılır.
class AnlikKarti extends StatelessWidget {
  const AnlikKarti({
    super.key,
    required this.anlik,
    required this.etiketler,
    required this.baglar,
    required this.etiketBul,
    this.onEtiket,
  });

  final Anlik anlik;
  final List<Etiket> etiketler;
  final List<Bag> baglar;
  final Etiket? Function(String) etiketBul;
  final void Function(Etiket)? onEtiket;

  @override
  Widget build(BuildContext context) {
    final ciplar = seritCipleri(
      metin: anlik.metin,
      etiketler: etiketler,
      anlikBaglari: [
        for (final b in baglar)
          if (b.kaynakId == anlik.id) b,
      ],
    );
    final duygu = anlik.duygu;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.anlikDuzenle(anlik.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ciplar.isNotEmpty) ...[
                EtiketSeridi(ciplar: ciplar, kucuk: true, onAc: onEtiket),
                const SizedBox(height: 6),
              ],
              EtiketliMetin(
                anlik.metin,
                etiketBul: etiketBul,
                onEtiket: onEtiket,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  formatClock(anlik.olusturma),
                  if (duygu != null) 'his ${duygu > 0 ? '+$duygu' : '$duygu'}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Anlık düzenleme: aynı yazma alanı, ayrıca silme.
class AnlikDuzenleEkrani extends ConsumerWidget {
  const AnlikDuzenleEkrani({super.key, required this.anlikId});
  final String anlikId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anlik = (ref.watch(anliklarProvider).value ?? const <Anlik>[]).where((a) => a.id == anlikId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(anlik == null ? 'Anlık' : formatShortDate(anlik.olusturma)),
        actions: [
          if (anlik != null)
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final evet = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Anlık silinsin mi?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
                    ],
                  ),
                );
                if (evet != true) return;
                await ref.read(anlikDeposuProvider).anlikSil(anlikId);
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: anlik == null
          ? const Center(child: Text('Bu anlık bulunamadı.'))
          : Column(
              children: [
                const Spacer(),
                YazmaAlani(
                  key: ValueKey(anlik.id),
                  anlik: anlik,
                  otomatikOdak: true,
                  onEtiketAc: (e) => context.push(AppRoutes.anlikEtiket(e.id)),
                  onKaydedildi: () => context.pop(),
                ),
              ],
            ),
    );
  }
}

class _SonSilinenler extends ConsumerWidget {
  const _SonSilinenler();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final liste = sonSilinenler(etiketler, DateTime.now());
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Son silinen etiketler', style: Theme.of(context).textTheme.titleMedium),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('30 gün içinde geri alabilirsin. Anlıkların silinmedi.'),
          ),
          if (liste.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Silinen etiket yok.')),
          for (final e in liste)
            ListTile(
              leading: const Icon(Icons.label_off_outlined),
              title: Text(e.ad),
              subtitle: Text(formatShortDate(e.guncelleme)),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await ref.read(anlikDeposuProvider).etiketGeriAl(e.id);
                  } on EtiketHatasi catch (h) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h.mesaj)));
                    }
                  }
                },
                child: const Text('Geri al'),
              ),
            ),
        ],
      ),
    );
  }
}
