// Ayarlar'daki "Bilgisayarla eşle" satırı: eşli mi, son eşitleme ne zaman.
// Dokununca eşleme ekranı açılır.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../../../core/utils/formatters.dart';
import '../sync_providers.dart';

class KocAyarKarti extends ConsumerWidget {
  const KocAyarKarti({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esleme = ref.watch(kocEslemesiProvider).value;
    final durum = ref.watch(esitlemeDurumuProvider).value;
    final son = durum?.sonBasari;
    final String alt;
    if (esleme == null) {
      alt = 'Aynı Wi-Fi\'deyken yedeğin bilgisayarına kendiliğinden gitsin';
    } else if (durum?.sonHata != null) {
      alt = '${esleme.sunucuAdi}: ${durum!.sonHata}';
    } else {
      alt = '${esleme.sunucuAdi}: son eşitleme ${son == null ? 'henüz yok' : formatShortDate(son.toLocal())}';
    }
    return Card(
      child: ListTile(
        leading: ToneIcon(Icons.computer_rounded, color: esleme == null ? KocumColors.blue : KocumColors.green),
        title: const Text('Bilgisayarla eşle'),
        subtitle: Text(alt),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
