import 'dart:io';

import 'package:flutter/material.dart';

/// Soru / çözüm fotoğrafı için 3:4 yuva.
/// Boşken dokun: fotoğraf ekle. Doluyken dokun ya da kırp butonu: yeniden kırp.
/// Kayıtlı (eski) bir fotoğraf yeniden kırpılamaz; dokununca yenisi çekilir.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    super.key,
    required this.label,
    required this.path,
    required this.onPick,
    required this.onCrop,
    required this.onClear,
    this.required = false,
    this.hasError = false,
    this.busy = false,
    this.canCrop = true,
    this.ready,
  });

  final String label;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onCrop;
  final VoidCallback onClear;
  final bool required;
  final bool hasError;
  final bool busy;
  final bool canCrop;

  /// Arka planda sıkıştırılıyorsa: bitene kadar "hazırlanıyor" gösterilir.
  final Future<void>? ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = hasError ? scheme.error : scheme.onSurfaceVariant;
    final filled = path != null;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hasError ? scheme.error : scheme.outlineVariant, width: hasError ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: busy ? null : (filled && canCrop ? onCrop : onPick),
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : !filled
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: accent, size: 32),
                        const SizedBox(height: 8),
                        Text(required ? '$label *' : label, style: TextStyle(color: accent)),
                        if (!required)
                          Text('isteğe bağlı', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent)),
                        const SizedBox(height: 4),
                        Text(
                          'Çek ya da seç, sonra kırp',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: accent),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // cacheWidth: 1440 px'lik görsel yerine ~600 px çözülür; binlerce
                        // kartlı listelerde de bellek ve kaydırma akıcılığı korunur.
                        FutureBuilder<void>(
                          // Aynı fotoğrafta yeniden kurulduğunda bekleme baştan başlamasın.
                          key: ValueKey(path),
                          future: ready ?? Future<void>.value(),
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(height: 8),
                                    Text('Hazırlanıyor'),
                                  ],
                                ),
                              );
                            }
                            if (snap.hasError) {
                              return Center(child: Icon(Icons.broken_image_outlined, color: scheme.error, size: 32));
                            }
                            return Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 600, gaplessPlayback: true);
                          },
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(label, style: Theme.of(context).textTheme.labelMedium),
                            ),
                          ),
                        ),
                        if (canCrop)
                          Positioned(
                          right: 4,
                          bottom: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Yeniden kırp',
                            visualDensity: VisualDensity.compact,
                            onPressed: onCrop,
                            icon: const Icon(Icons.crop_rounded, size: 18),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Kaldır',
                            visualDensity: VisualDensity.compact,
                            onPressed: onClear,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
