// Ayarlar'daki "Obsidian anlarını içe aktar" satırı: seçilen `Anlar/*.md`
// dosyaları tek seferlik anlık olur (ön bilgideki `zaman` tarih olur,
// metin ve ((…)) korunur). Aynı dosya ikinci kez aktarılmaz.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../anlik_providers.dart';

class MdIceAktarKarti extends ConsumerWidget {
  const MdIceAktarKarti({super.key});

  Future<void> _aktar(BuildContext context, WidgetRef ref) async {
    final secim = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      // Android .md için MIME türünü her zaman tanımıyor: her dosya seçilebilir, .md olmayanlar atlanır.
      type: FileType.any,
      withData: true,
    );
    if (secim == null || secim.files.isEmpty) return;
    final simdi = DateTime.now();
    final dosyalar = [
      for (final f in secim.files)
        if (f.bytes != null && f.name.toLowerCase().endsWith('.md'))
          (ad: f.name, icerik: utf8.decode(f.bytes!, allowMalformed: true), zaman: simdi),
    ];
    final sonuc = await ref.read(anlikDeposuProvider).mdIceAktar(dosyalar);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${sonuc.eklenen} anlık eklendi'
          '${sonuc.atlanan > 0 ? ', ${sonuc.atlanan} dosya atlandı (boş ya da önceden aktarılmış)' : ''}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: const ToneIcon(Icons.download_rounded, color: KocumColors.blue),
      title: const Text('Obsidian anlarını içe aktar'),
      subtitle: const Text('Anlar/*.md dosyalarını seç; her biri bir anlık olur'),
      onTap: () => _aktar(context, ref),
    ),
  );
}
