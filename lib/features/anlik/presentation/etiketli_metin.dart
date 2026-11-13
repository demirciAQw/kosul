// Metin içindeki ((…)) etiketlerini renkli gösteren iki parça:
// - EtiketliMetinDenetleyici: yazma alanı için (yazarken renklenir)
// - EtiketliMetin: listede okunan metin (etikete dokununca sayfası açılır)
// Etiket renkleri de burada (türe göre).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/palette.dart';
import '../domain/anlik.dart';
import '../domain/etiket_metni.dart';

/// Etiketin rengi: kendi rengi yoksa türünün rengi.
Color etiketRengi(Etiket? e, {Brightness parlaklik = Brightness.light}) {
  if (e?.renk != null) return Color(e!.renk!);
  final koyu = parlaklik == Brightness.dark;
  return switch (e?.tur) {
    EtiketTur.kisi => koyu ? KocumColors.blueDark : KocumColors.blue,
    EtiketTur.duygu => koyu ? KocumColors.redDark : KocumColors.red,
    EtiketTur.konu => koyu ? KocumColors.greenDark : KocumColors.green,
    EtiketTur.yer => KocumColors.amber,
    _ => koyu ? KocumColors.grey500 : KocumColors.grey700,
  };
}

/// Yeni etiket penceresinde seçilebilen renkler.
const etiketRenkSecenekleri = <int>[0xFF1A73E8, 0xFFD93025, 0xFF1E8E3E, 0xFFE37400, 0xFF9334E6, 0xFF12B5CB];

class EtiketliMetinDenetleyici extends TextEditingController {
  EtiketliMetinDenetleyici({super.text, required this.etiketBul});

  /// Normalize ad → etiket (bilinmiyorsa null: gri ve kesik altı çizili).
  Etiket? Function(String normAd) etiketBul;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final atiflar = metinEtiketleri(text);
    if (atiflar.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final parlaklik = Theme.of(context).brightness;
    final parcalar = <TextSpan>[];
    var i = 0;
    for (final a in atiflar) {
      if (a.bas > i) parcalar.add(TextSpan(text: text.substring(i, a.bas)));
      final e = etiketBul(a.normAd);
      parcalar.add(
        TextSpan(
          text: text.substring(a.bas, a.son),
          style: e == null
              ? const TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed)
              : TextStyle(
                  color: etiketRengi(e, parlaklik: parlaklik),
                  fontWeight: FontWeight.w600,
                ),
        ),
      );
      i = a.son;
    }
    if (i < text.length) parcalar.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: style, children: parcalar);
  }
}

/// Okunan anlık metni: ((…)) kısımları renkli ve dokunulabilir.
class EtiketliMetin extends StatefulWidget {
  const EtiketliMetin(this.metin, {super.key, required this.etiketBul, this.onEtiket, this.style, this.maxLines});
  final String metin;
  final Etiket? Function(String normAd) etiketBul;
  final void Function(Etiket)? onEtiket;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<EtiketliMetin> createState() => _EtiketliMetinState();
}

class _EtiketliMetinState extends State<EtiketliMetin> {
  final _tanicilar = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _tanicilar) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _tanicilar) {
      t.dispose();
    }
    _tanicilar.clear();
    final parlaklik = Theme.of(context).brightness;
    final metin = widget.metin;
    final parcalar = <InlineSpan>[];
    var i = 0;
    for (final a in metinEtiketleri(metin)) {
      if (a.bas > i) parcalar.add(TextSpan(text: metin.substring(i, a.bas)));
      final e = widget.etiketBul(a.normAd);
      if (e == null) {
        parcalar.add(TextSpan(text: metin.substring(a.bas, a.son)));
      } else {
        final t = TapGestureRecognizer()..onTap = () => widget.onEtiket?.call(e);
        _tanicilar.add(t);
        parcalar.add(
          TextSpan(
            text: a.ad,
            recognizer: t,
            style: TextStyle(
              color: etiketRengi(e, parlaklik: parlaklik),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      i = a.son;
    }
    if (i < metin.length) parcalar.add(TextSpan(text: metin.substring(i)));
    return Text.rich(
      TextSpan(children: parcalar),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
