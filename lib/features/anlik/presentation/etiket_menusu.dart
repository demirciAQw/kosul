// Etikete uzun basınca açılan menü (şeritte, listede ya da etiket sayfasında):
// etiket etiketi ekle (alt), üst etiket ekle, yeniden adlandır, birleştir, sil.
// Döngü (his → tiksinti → his) engellenir ve söylenir.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anlik_providers.dart';
import '../data/anlik_deposu.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'etiket_sayfasi.dart';
import 'etiket_secici.dart';

Future<void> etiketMenusu(BuildContext context, WidgetRef ref, Etiket etiket) async {
  final secim = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiket.ad, style: Theme.of(c).textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.subdirectory_arrow_right_rounded),
            title: const Text('Etiket etiketi ekle'),
            subtitle: Text('Seçilenler "${etiket.ad}" altına girer'),
            onTap: () => Navigator.pop(c, 'alt'),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward_rounded),
            title: const Text('Üst etiket ekle'),
            onTap: () => Navigator.pop(c, 'ust'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Yeniden adlandır'),
            onTap: () => Navigator.pop(c, 'ad'),
          ),
          ListTile(
            leading: const Icon(Icons.merge_rounded),
            title: const Text('Birleştir'),
            onTap: () => Navigator.pop(c, 'birlestir'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Sil'),
            onTap: () => Navigator.pop(c, 'sil'),
          ),
        ],
      ),
    ),
  );
  if (secim == null || !context.mounted) return;
  final depo = ref.read(anlikDeposuProvider);
  void soyle(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  try {
    switch (secim) {
      case 'alt':
        final baglar = ref.read(baglarProvider).value ?? const <Bag>[];
        final secilen = await etiketSec(
          context,
          baslik: '"${etiket.ad}" altına ekle',
          gizli: {etiket.id, ...(ustHaritasi(baglar)[etiket.id] ?? const <String>{})},
          secili: {...(altHaritasi(baglar)[etiket.id] ?? const <String>{})},
        );
        if (secilen == null) return;
        final engellenen = <String>[];
        for (final id in secilen) {
          try {
            await depo.ustEkle(id, etiket.id);
          } on EtiketHatasi {
            engellenen.add(id);
          }
        }
        if (engellenen.isNotEmpty) soyle('${engellenen.length} etiket eklenmedi: döngü olurdu.');
      case 'ust':
        final secilen = await etiketSec(
          context,
          baslik: '"${etiket.ad}" için üst etiket',
          gizli: {etiket.id},
          tekSecim: true,
        );
        if (secilen == null || secilen.isEmpty) return;
        await depo.ustEkle(etiket.id, secilen.first);
      case 'ad':
        if (!context.mounted) return;
        await _yenidenAdlandir(context, ref, etiket);
      case 'birlestir':
        if (!context.mounted) return;
        await _birlestir(context, ref, etiket);
      case 'sil':
        if (!context.mounted) return;
        await etiketSilDiyalogu(context, ref, etiket);
    }
  } on EtiketHatasi catch (h) {
    if (context.mounted) soyle(h.mesaj);
  }
}

Future<void> _yenidenAdlandir(BuildContext context, WidgetRef ref, Etiket etiket) async {
  final etkilenen = metninde(normAd: etiket.normAd, anliklar: ref.read(anliklarProvider).value ?? const []).length;
  final kutu = TextEditingController(text: etiket.ad);
  final yeni = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Yeniden adlandır'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$etkilenen anlık etkilenecek: metindeki ((${etiket.ad})) yazıları da değişir.'),
          const SizedBox(height: 12),
          TextField(
            controller: kutu,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Yeni ad'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, kutu.text), child: const Text('Değiştir')),
      ],
    ),
  );
  kutu.dispose();
  if (yeni == null || yeni.trim() == etiket.ad) return;
  await ref.read(anlikDeposuProvider).etiketYenidenAdlandir(etiket.id, yeni);
}

Future<void> _birlestir(BuildContext context, WidgetRef ref, Etiket etiket) async {
  final secilen = await etiketSec(
    context,
    baslik: '"${etiket.ad}" hangisiyle birleşsin?',
    gizli: {etiket.id},
    tekSecim: true,
  );
  if (secilen == null || secilen.isEmpty || !context.mounted) return;
  final hedef = (ref.read(etiketlerProvider).value ?? const <Etiket>[]).where((e) => e.id == secilen.first).firstOrNull;
  if (hedef == null) return;
  final evet = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('"${etiket.ad}" → "${hedef.ad}"'),
      content: Text(
        '"${etiket.ad}" etiketinin bütün anlıkları ve alt etiketleri "${hedef.ad}" etiketine geçer; '
        'metindeki ((${etiket.ad})) yazıları ((${hedef.ad})) olur. "${etiket.ad}" son silinenlere gider.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Birleştir')),
      ],
    ),
  );
  if (evet != true) return;
  await ref.read(anlikDeposuProvider).etiketBirlestir(kaynakId: etiket.id, hedefId: hedef.id);
}
