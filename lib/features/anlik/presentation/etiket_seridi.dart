// Etiket şeridi: anlığın (ya da yazma alanının) üstünde etiket çipleri ve `+`.
// Metinden gelen çipler çerçevelidir ve şeritten kaldırılamaz.
import 'package:flutter/material.dart';

import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'etiketli_metin.dart';

class EtiketSeridi extends StatelessWidget {
  const EtiketSeridi({
    super.key,
    required this.ciplar,
    this.onEkle,
    this.onKaldir,
    this.onAc,
    this.onUzunBas,
    this.kucuk = false,
  });

  final List<SeritCipi> ciplar;
  final VoidCallback? onEkle;
  final void Function(SeritCipi)? onKaldir;
  final void Function(Etiket)? onAc;
  final void Function(Etiket)? onUzunBas;
  final bool kucuk;

  @override
  Widget build(BuildContext context) {
    final parlaklik = Theme.of(context).brightness;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in ciplar)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: onUzunBas == null ? null : () => onUzunBas!(c.etiket),
                child: InputChip(
                  visualDensity: kucuk ? VisualDensity.compact : null,
                  materialTapTargetSize: kucuk ? MaterialTapTargetSize.shrinkWrap : null,
                  avatar: Icon(Icons.label_rounded, size: 16, color: etiketRengi(c.etiket, parlaklik: parlaklik)),
                  label: Text(c.etiket.ad),
                  side: c.metinden ? BorderSide(color: etiketRengi(c.etiket, parlaklik: parlaklik), width: 1.5) : null,
                  onPressed: onAc == null ? null : () => onAc!(c.etiket),
                  onDeleted: onKaldir == null
                      ? null
                      : () {
                          if (c.metinden) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(content: Text('Bu etiket metinde geçiyor, metinden sil.')));
                          } else {
                            onKaldir!(c);
                          }
                        },
                ),
              ),
            ),
          if (onEkle != null)
            ActionChip(
              visualDensity: kucuk ? VisualDensity.compact : null,
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(ciplar.isEmpty ? 'Etiket' : ''),
              labelPadding: ciplar.isEmpty ? null : EdgeInsets.zero,
              onPressed: onEkle,
            ),
        ],
      ),
    );
  }
}
