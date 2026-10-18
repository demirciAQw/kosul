import 'package:flutter/material.dart';

/// Açık renk zemin üstünde renkli simge: Google uygulamalarındaki liste
/// rozetleri. Rengin %12'si zemin olur; göz yormadan satırları ayırt ettirir.
class ToneIcon extends StatelessWidget {
  const ToneIcon(this.icon, {super.key, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}
