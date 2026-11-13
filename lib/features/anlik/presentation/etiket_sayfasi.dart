// Etiket sayfası: o etiketi (ve alt etiketlerini) taşıyan anlıklar, tarih
// sırasıyla. Üst ve alt etiketler görünür. Menüden etiket silinir: önce sayı
// gösterilir ("his 14 anlıkta, 3 alt etikette"), iki seçenek sunulur.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../anlik_providers.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'anlik_ekrani.dart';
import 'etiketli_metin.dart';

class EtiketSayfasi extends ConsumerWidget {
  const EtiketSayfasi({super.key, required this.etiketId});
  final String etiketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final baglar = ref.watch(baglarProvider).value ?? const <Bag>[];
    final anliklar = ref.watch(anliklarProvider).value ?? const <Anlik>[];
    final etiket = etiketler.where((e) => e.id == etiketId).firstOrNull;
    if (etiket == null || etiket.silindi) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Bu etiket silinmiş.')),
      );
    }
    final kimlikle = {
      for (final e in etiketler)
        if (!e.silindi) e.id: e,
    };
    final adla = {
      for (final e in etiketler)
        if (!e.silindi) e.normAd: e,
    };
    final ustler = (ustHaritasi(baglar)[etiketId] ?? const <String>{}).map((id) => kimlikle[id]).whereType<Etiket>();
    final altlar = (altHaritasi(baglar)[etiketId] ?? const <String>{}).map((id) => kimlikle[id]).whereType<Etiket>();
    final liste = etiketinAnliklari(etiketId: etiketId, anliklar: anliklar, baglar: baglar);
    final parlaklik = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.label_rounded, color: etiketRengi(etiket, parlaklik: parlaklik)),
            const SizedBox(width: 8),
            Flexible(child: Text(etiket.ad, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'sil') await etiketSilDiyalogu(context, ref, etiket);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'sil', child: Text('Etiketi sil'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${etiket.tur.ad} · ${liste.length} anlık', style: Theme.of(context).textTheme.bodyMedium),
          if (ustler.isNotEmpty || altlar.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in ustler)
                  ActionChip(
                    avatar: const Icon(Icons.arrow_upward_rounded, size: 16),
                    label: Text(u.ad),
                    onPressed: () => context.push(AppRoutes.anlikEtiket(u.id)),
                  ),
                for (final a in altlar)
                  ActionChip(
                    avatar: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16),
                    label: Text(a.ad),
                    onPressed: () => context.push(AppRoutes.anlikEtiket(a.id)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          for (final a in liste)
            AnlikKarti(
              anlik: a,
              etiketler: etiketler,
              baglar: baglar,
              etiketBul: (n) => adla[n],
              onEtiket: (e) {
                if (e.id != etiketId) context.push(AppRoutes.anlikEtiket(e.id));
              },
            ),
        ],
      ),
    );
  }
}

/// Etiket silme: önce sayılar, sonra "sadece bu" ya da "alt etiketleriyle".
Future<void> etiketSilDiyalogu(BuildContext context, WidgetRef ref, Etiket etiket) async {
  final plan = etiketSilmePlani(
    etiketId: etiket.id,
    altlariyla: false,
    etiketler: ref.read(etiketlerProvider).value ?? const [],
    baglar: ref.read(baglarProvider).value ?? const [],
    anliklar: ref.read(anliklarProvider).value ?? const [],
  );
  final secim = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('"${etiket.ad}" silinsin mi?'),
      content: Text(
        '${etiket.ad} ${plan.anlikSayisi} anlıkta, ${plan.altSayisi} alt etikette.\n\n'
        'Anlıklar silinmez; metindeki ((${etiket.ad})) düz yazıya döner. '
        '30 gün içinde "Son silinen etiketler"den geri alabilirsin.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        if (plan.altSayisi > 0)
          TextButton(onPressed: () => Navigator.pop(c, 'alt'), child: const Text('Alt etiketleriyle sil')),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'tek'),
          child: Text(plan.altSayisi > 0 ? 'Sadece bunu sil' : 'Sil'),
        ),
      ],
    ),
  );
  if (secim == null) return;
  await ref.read(anlikDeposuProvider).etiketSil(etiket.id, altlariyla: secim == 'alt');
  if (context.mounted && context.canPop()) context.pop();
}
