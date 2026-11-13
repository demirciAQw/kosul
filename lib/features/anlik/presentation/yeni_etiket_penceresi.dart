// Yeni etiket penceresi (her yoldan aynı pencere): ad, tür, isteğe bağlı üst
// etiket ve renk. Kullanıcı "Oluştur" demeden etiket oluşmaz; vazgeçerse null döner.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anlik_providers.dart';
import '../data/anlik_deposu.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'etiketli_metin.dart';

Future<Etiket?> yeniEtiketPenceresi(BuildContext context, {String ad = '', String? ustId}) =>
    showModalBottomSheet<Etiket>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _YeniEtiket(ad: ad, ustId: ustId),
    );

class _YeniEtiket extends ConsumerStatefulWidget {
  const _YeniEtiket({required this.ad, this.ustId});
  final String ad;
  final String? ustId;

  @override
  ConsumerState<_YeniEtiket> createState() => _YeniEtiketState();
}

class _YeniEtiketState extends ConsumerState<_YeniEtiket> {
  late final _ad = TextEditingController(text: widget.ad);
  var _tur = EtiketTur.diger;
  late String? _ust = widget.ustId;
  int? _renk;
  String? _hata;

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _olustur() async {
    try {
      final e = await ref.read(anlikDeposuProvider).etiketOlustur(ad: _ad.text, tur: _tur, renk: _renk, ustId: _ust);
      if (mounted) Navigator.pop(context, e);
    } on EtiketHatasi catch (h) {
      setState(() => _hata = h.mesaj);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final baglar = ref.watch(baglarProvider).value ?? const <Bag>[];
    final agac = etiketAgaci(etiketler, baglar);
    final tekrarsiz = <String, Etiket>{for (final s in agac) s.etiket.id: s.etiket};
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Yeni etiket', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _ad,
              autofocus: widget.ad.isEmpty,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(labelText: 'Ad', errorText: _hata),
              onChanged: (_) => setState(() => _hata = null),
              onSubmitted: (_) => _olustur(),
            ),
            const SizedBox(height: 12),
            Text('Tür', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final t in EtiketTur.values)
                  ChoiceChip(label: Text(t.ad), selected: _tur == t, onSelected: (_) => setState(() => _tur = t)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _ust,
              decoration: const InputDecoration(labelText: 'Üst etiket (isteğe bağlı)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Yok (ana etiket)')),
                for (final e in tekrarsiz.values) DropdownMenuItem(value: e.id, child: Text(e.ad)),
              ],
              onChanged: (v) => setState(() => _ust = v),
            ),
            const SizedBox(height: 12),
            Text('Renk', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Türün rengi'),
                  selected: _renk == null,
                  onSelected: (_) => setState(() => _renk = null),
                ),
                for (final r in etiketRenkSecenekleri)
                  GestureDetector(
                    onTap: () => setState(() => _renk = r),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(r),
                      child: _renk == r ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _olustur, child: const Text('Oluştur')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
