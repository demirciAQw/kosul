import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';

/// Kalıcı depodaki (göreli yollu) fotoğrafı gösterir.
class MediaImage extends ConsumerWidget {
  const MediaImage(this.path, {super.key, this.fit = BoxFit.cover, this.cacheWidth});

  final String path;
  final BoxFit fit;

  /// Küçük önizlemelerde belleği korur: tam çözünürlük yerine bu genişlikte çözülür.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(mediaStorageProvider).resolve(path);
    return Image.file(
      file,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

/// Tam ekran, iki parmakla yakınlaştırılabilir görüntüleyici.
void openImageZoom(BuildContext context, String path) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: MediaImage(path, fit: BoxFit.contain, cacheWidth: 2048)),
      ),
    ),
  ));
}
