// Anlık yazma alanı: üstte etiket şeridi, `((` yazınca öneri listesi, metin
// kutusu, duygu seçici (-3…+3, boş bırakılabilir) ve gönder düğmesi.
// Yeni anlık için Anlık ekranının altında, düzenleme için tam sayfada kullanılır.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../anlik_providers.dart';
import '../domain/anlik.dart';
import '../domain/etiket_kurallari.dart';
import '../domain/etiket_metni.dart';
import 'etiket_secici.dart';
import 'etiket_seridi.dart';
import 'etiketli_metin.dart';
import 'yeni_etiket_penceresi.dart';

class YazmaAlani extends ConsumerStatefulWidget {
  const YazmaAlani({super.key, this.anlik, this.otomatikOdak = false, this.onKaydedildi, this.onEtiketAc});

  /// Düzenlenen anlık (yoksa yeni).
  final Anlik? anlik;
  final bool otomatikOdak;
  final VoidCallback? onKaydedildi;
  final void Function(Etiket)? onEtiketAc;

  @override
  ConsumerState<YazmaAlani> createState() => _YazmaAlaniState();
}

class _YazmaAlaniState extends ConsumerState<YazmaAlani> {
  late final EtiketliMetinDenetleyici _metin;
  final _odak = FocusNode();
  final _seritte = <String>{};
  int? _duygu;
  var _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _metin = EtiketliMetinDenetleyici(text: widget.anlik?.metin ?? '', etiketBul: _etiketBul)
      ..addListener(() => setState(() {}));
    _duygu = widget.anlik?.duygu;
    if (widget.otomatikOdak) WidgetsBinding.instance.addPostFrameCallback((_) => _odak.requestFocus());
  }

  @override
  void dispose() {
    _metin.dispose();
    _odak.dispose();
    super.dispose();
  }

  Etiket? _etiketBul(String normAd) {
    final hepsi = ref.read(etiketlerProvider).value ?? const <Etiket>[];
    return hepsi.where((e) => !e.silindi && e.normAd == normAd).firstOrNull;
  }

  void _tamamla(String ad) {
    final t = etiketiTamamla(_metin.text, _metin.selection.baseOffset, ad);
    _metin.value = TextEditingValue(
      text: t.metin,
      selection: TextSelection.collapsed(offset: t.imlec),
    );
  }

  Future<void> _yeniEtiket(String ad) async {
    final e = await yeniEtiketPenceresi(context, ad: ad);
    if (e != null) _tamamla(e.ad);
  }

  Future<void> _seritEkle() async {
    final secilen = await etiketSec(context, secili: {..._seritte});
    if (secilen == null) return;
    if (widget.anlik == null) {
      setState(() {
        _seritte
          ..clear()
          ..addAll(secilen);
      });
    } else {
      await ref.read(anlikDeposuProvider).seritEtiketiEkle(widget.anlik!.id, secilen);
    }
  }

  /// Bilinmeyen ((ad)) için yeni etiket penceresi açılır; vazgeçilirse düz yazı olur.
  Future<String> _bilinmeyenleriSor(String metin) async {
    var sonuc = metin;
    final sorulan = <String>{};
    for (final a in metinEtiketleri(metin)) {
      if (_etiketBul(a.normAd) != null || !sorulan.add(a.normAd)) continue;
      final e = await yeniEtiketPenceresi(context, ad: a.ad);
      if (e == null) sonuc = etiketiDuzYaziYap(sonuc, a.normAd);
      if (!mounted) return sonuc;
    }
    return sonuc;
  }

  Future<void> _kaydet() async {
    if (_metin.text.trim().isEmpty || _kaydediliyor) return;
    setState(() => _kaydediliyor = true);
    try {
      final metin = await _bilinmeyenleriSor(_metin.text.trim());
      await ref
          .read(anlikDeposuProvider)
          .anlikKaydet(id: widget.anlik?.id, metin: metin, duygu: _duygu, seritEtiketleri: {..._seritte});
      if (!mounted) return;
      if (widget.anlik == null) {
        _metin.clear();
        setState(() {
          _seritte.clear();
          _duygu = null;
        });
      }
      widget.onKaydedildi?.call();
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<void> _duyguSec() async {
    final secilen = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nasıl hissettin?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = -3; d <= 3; d++)
                    ChoiceChip(
                      label: Text(d > 0 ? '+$d' : '$d'),
                      selected: _duygu == d,
                      onSelected: (_) => Navigator.pop(context, d),
                    ),
                  ActionChip(label: const Text('Boş bırak'), onPressed: () => Navigator.pop(context, 99)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (secilen == null) return;
    setState(() => _duygu = secilen == 99 ? null : secilen);
  }

  @override
  Widget build(BuildContext context) {
    final etiketler = ref.watch(etiketlerProvider).value ?? const <Etiket>[];
    final baglar = ref.watch(baglarProvider).value ?? const <Bag>[];
    final anliklar = ref.watch(anliklarProvider).value ?? const <Anlik>[];
    final anlikBaglari = widget.anlik == null
        ? const <Bag>[]
        : [
            for (final b in baglar)
              if (b.kaynakId == widget.anlik!.id) b,
          ];
    final ciplar = seritCipleri(
      metin: _metin.text,
      etiketler: etiketler,
      anlikBaglari: anlikBaglari,
      seritteSecilenler: _seritte,
    );
    final imlec = _metin.selection.baseOffset;
    final acik = imlec < 0 ? null : acikEtiket(_metin.text, imlec);
    final oneriler = acik == null
        ? const <Etiket>[]
        : etiketOnerileri(
            etiketler: etiketler,
            baglar: baglar,
            anlikZamanlari: {for (final a in anliklar) a.id: a.olusturma},
            simdi: DateTime.now(),
            sorgu: acik.sorgu,
          ).take(6).toList();
    final yeniAd = acik == null ? '' : etiketAdiDuzelt(acik.sorgu);
    final parlaklik = Theme.of(context).brightness;

    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (acik != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in oneriler)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.label_rounded, color: etiketRengi(e, parlaklik: parlaklik)),
                          title: Text(e.ad),
                          onTap: () => _tamamla(e.ad),
                        ),
                      if (yeniEtiketGosterilsinMi(etiketler, yeniAd))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.add_rounded),
                          title: Text('Yeni etiket: $yeniAd'),
                          onTap: () => _yeniEtiket(yeniAd),
                        ),
                    ],
                  ),
                ),
              EtiketSeridi(
                ciplar: ciplar,
                kucuk: true,
                onEkle: _seritEkle,
                onAc: widget.onEtiketAc,
                onKaldir: (c) {
                  if (c.bag != null) {
                    ref.read(anlikDeposuProvider).bagKaldir(c.bag!.id);
                  } else {
                    setState(() => _seritte.remove(c.etiket.id));
                  }
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _metin,
                      focusNode: _odak,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'Ne oldu? ((etiket)) yazabilirsin',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _duyguSec,
                    child: Text(
                      _duygu == null ? 'His' : (_duygu! > 0 ? '+$_duygu' : '$_duygu'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Kaydet',
                    onPressed: _metin.text.trim().isEmpty || _kaydediliyor ? null : _kaydet,
                    icon: Icon(widget.anlik == null ? Icons.send_rounded : Icons.check_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
