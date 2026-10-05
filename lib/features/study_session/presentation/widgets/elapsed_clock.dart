import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';

/// Yalnızca GÖRÜNTÜLEME için saniyede bir yenilenir. Kaynak her zaman
/// [startedAt]: ekran kapalıyken/uygulama öldürüldüğünde hiçbir şey kaybolmaz.
class ElapsedClock extends StatefulWidget {
  const ElapsedClock({super.key, required this.startedAt, this.style});
  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<ElapsedClock> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    return Text(
      formatDuration(DateTime.now().difference(widget.startedAt)),
      // Sabit genişlikli rakamlar: saniye değişirken metin titremez.
      style: base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
