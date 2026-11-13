// Şeritteki `+`: alttan açılan arama kutulu etiket listesi.
//
// Etiketler ağaç halinde (üstler başlık, altları girintili). Liste kapanmadan
// birden çok etiket işaretlenir, "Ekle" ile hepsi döner. Aranan ad yoksa en
// altta "… ekle" satırı yeni etiket penceresini açar. [tekSecim]: ilk seçilen
// döner (ör. "üst etiket ekle").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/turkish_text.dart';
import '../anlik_providers.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import 'etiketli_metin.dart';
import 'yeni_etiket_penceresi.dart';

Future<Set<String>?> etiketSec(
  BuildContext context, {
  Set<String> secili = const {},
  Set<String> gizli = const {},
  String baslik = 'Etiket ekle',
  bool tekSecim = false,
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EtiketSecici(secili: secili, gizli: gizli, baslik: baslik, tekSecim: tekSecim),
);

class _EtiketSecici extends ConsumerStatefulWidget {
  const _EtiketSecici({required this.secili, required this.gizli, required this.baslik, required this.tekSecim});
  final Set<String> secili;
  final Set<String> gizli;
  final String baslik;
  final bool tekSecim;

  @override
  ConsumerState<_EtiketSecici> createState() => _EtiketSeciciState();
}

class _EtiketSeciciState extends ConsumerState<_EtiketSecici> {
  late final Set<String> _secili = {...widget.secili};
  var _sorgu = '';

  Future<void> _yeni() async {
    final e = await yeniEtiketPenceresi(context, ad: _sorgu.trim());
    if (e == null || !mounted) return;
    if (widget.tekSecim) {
      Navigator.pop(context, {e.id});
    } else {
      setState(() => _secili.add(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final baglar = ref.watch(baglarProvider).value ?? const <Bag>[];
    final q = normalizeTr(_sorgu);
    final satirlar = q.isEmpty
        ? etiketAgaci(etiketler, baglar)
        : [
            for (final e in etiketOnerileri(
              etiketler: etiketler,
              baglar: baglar,
              anlikZamanlari: const {},
              simdi: DateTime.now(),
              sorgu: _sorgu,
            ))
              (etiket: e, derinlik: 0),
          ];
    final gorunen = [
      for (final s in satirlar)
        if (!widget.gizli.contains(s.etiket.id)) s,
    ];
    final parlaklik = Theme.of(context).brightness;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.baslik, style: Theme.of(context).textTheme.titleLarge)),
                  if (!widget.tekSecim)
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _secili),
                      child: Text(_secili.isEmpty ? 'Tamam' : 'Ekle (${_secili.length})'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Etiket ara'),
                onChanged: (v) => setState(() => _sorgu = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final s in gorunen)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(left: 16 + 24.0 * s.derinlik, right: 16),
                      value: _secili.contains(s.etiket.id),
                      secondary: Icon(Icons.label_rounded, color: etiketRengi(s.etiket, parlaklik: parlaklik)),
                      title: Text(
                        s.etiket.ad,
                        style: s.derinlik == 0 && q.isEmpty ? const TextStyle(fontWeight: FontWeight.w600) : null,
                      ),
                      onChanged: (v) {
                        if (widget.tekSecim) {
                          Navigator.pop(context, {s.etiket.id});
                          return;
                        }
                        setState(() => v == true ? _secili.add(s.etiket.id) : _secili.remove(s.etiket.id));
                      },
                    ),
                  if (yeniEtiketGosterilsinMi(etiketler, _sorgu))
                    ListTile(leading: const Icon(Icons.add_rounded), title: Text('${_sorgu.trim()} ekle'), onTap: _yeni)
                  else if (gorunen.isEmpty)
                    ListTile(leading: const Icon(Icons.add_rounded), title: const Text('Yeni etiket'), onTap: _yeni),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
