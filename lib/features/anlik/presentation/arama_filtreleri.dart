// Anlık aramasının filtre çipleri: etiket (hepsi / herhangi), tarih aralığı,
// duygu aralığı, etiketin geldiği yer ve etiketsizler. Filtre değeri
// AnlikFiltresi'dir (saf Dart, domain/anlik_arama.dart).
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/anlik.dart';
import '../domain/anlik_arama.dart';
import 'etiket_secici.dart';

class AramaFiltreleri extends StatelessWidget {
  const AramaFiltreleri({super.key, required this.filtre, required this.degisti});
  final AnlikFiltresi filtre;
  final ValueChanged<AnlikFiltresi> degisti;

  Future<void> _etiket(BuildContext context) async {
    final secilen = await etiketSec(context, secili: filtre.etiketler, baslik: 'Etikete göre süz');
    if (secilen != null) degisti(filtre.kopya(etiketler: secilen));
  }

  Future<void> _tarih(BuildContext context) async {
    final simdi = DateTime.now();
    final aralik = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: simdi,
      initialDateRange: filtre.baslangic == null
          ? null
          : DateTimeRange(start: filtre.baslangic!, end: filtre.bitis ?? simdi),
    );
    if (aralik != null) degisti(filtre.kopya(baslangic: () => aralik.start, bitis: () => aralik.end));
  }

  Future<void> _duygu(BuildContext context) async {
    var aralik = RangeValues((filtre.duyguEnAz ?? -3).toDouble(), (filtre.duyguEnCok ?? 3).toDouble());
    final tamam = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Duygu: ${aralik.start.round()} … ${aralik.end.round()}',
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                RangeSlider(
                  values: aralik,
                  min: -3,
                  max: 3,
                  divisions: 6,
                  labels: RangeLabels('${aralik.start.round()}', '${aralik.end.round()}'),
                  onChanged: (v) => yenile(() => aralik = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kaldır')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uygula')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (tamam == null) return;
    degisti(
      tamam
          ? filtre.kopya(duyguEnAz: () => aralik.start.round(), duyguEnCok: () => aralik.end.round())
          : filtre.kopya(duyguEnAz: () => null, duyguEnCok: () => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    const nedenAdi = {BagNeden.metin: 'Metin içi', BagNeden.serit: 'Şerit', BagNeden.ai: 'Yapay zekâ'};
    final tarihVar = filtre.baslangic != null;
    final duyguVar = filtre.duyguEnAz != null || filtre.duyguEnCok != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        spacing: 6,
        children: [
          FilterChip(
            label: Text(filtre.etiketler.isEmpty ? 'Etiket' : 'Etiket (${filtre.etiketler.length})'),
            selected: filtre.etiketler.isNotEmpty,
            onSelected: (_) => _etiket(context),
          ),
          if (filtre.etiketler.length > 1)
            ActionChip(
              label: Text(filtre.mod == EtiketModu.hepsi ? 'Hepsi' : 'Herhangi biri'),
              onPressed: () =>
                  degisti(filtre.kopya(mod: filtre.mod == EtiketModu.hepsi ? EtiketModu.herhangi : EtiketModu.hepsi)),
            ),
          FilterChip(
            label: Text(tarihVar ? '${formatDayMonth(filtre.baslangic!)} – ${formatDayMonth(filtre.bitis!)}' : 'Tarih'),
            selected: tarihVar,
            onSelected: (_) =>
                tarihVar ? degisti(filtre.kopya(baslangic: () => null, bitis: () => null)) : _tarih(context),
          ),
          FilterChip(
            label: Text(duyguVar ? 'Duygu ${filtre.duyguEnAz ?? -3}…${filtre.duyguEnCok ?? 3}' : 'Duygu'),
            selected: duyguVar,
            onSelected: (_) => _duygu(context),
          ),
          for (final n in nedenAdi.entries)
            FilterChip(
              label: Text(n.value),
              selected: filtre.nedenler.contains(n.key),
              onSelected: (v) => degisti(
                filtre.kopya(nedenler: v ? {...filtre.nedenler, n.key} : ({...filtre.nedenler}..remove(n.key))),
              ),
            ),
          FilterChip(
            label: const Text('Etiketsiz'),
            selected: filtre.etiketsiz,
            onSelected: (v) => degisti(filtre.kopya(etiketsiz: v)),
          ),
          if (!filtre.bos)
            ActionChip(
              avatar: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Temizle'),
              onPressed: () => degisti(const AnlikFiltresi()),
            ),
        ],
      ),
    );
  }
}
