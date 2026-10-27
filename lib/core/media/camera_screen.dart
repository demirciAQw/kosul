import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'fast_camera.dart';

/// Kamera ekranının sonucu: çekilen fotoğrafın yolu ya da galeriden seçme isteği.
class CameraShot {
  const CameraShot.photo(String this.path) : wantsGallery = false;
  const CameraShot.gallery()
      : path = null,
        wantsGallery = true;
  final String? path;
  final bool wantsGallery;
}

/// Uygulama içi kamera: tam ekran önizleme, büyük deklanşör, flaş, galeri.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.camera});
  final FastCamera camera;

  static Future<CameraShot?> open(BuildContext context, FastCamera camera) =>
      Navigator.of(context, rootNavigator: true).push<CameraShot>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraScreen(camera: camera),
      ));

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _busy = false;
  bool _failed = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    widget.camera.showing(true);
    widget.camera.open().then((c) {
      if (mounted && c == null) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    widget.camera.showing(false);
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = widget.camera.controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (mounted) Navigator.of(context).pop(CameraShot.photo(file.path));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Çekilemedi: $e')));
    }
  }

  Future<void> _toggleFlash() async {
    final c = widget.camera.controller;
    if (c == null) return;
    final next = _flash == FlashMode.off ? FlashMode.auto : (_flash == FlashMode.auto ? FlashMode.torch : FlashMode.off);
    try {
      await c.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Kapat',
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.camera,
                builder: (context, _) {
                  final c = widget.camera.controller;
                  if (c == null) {
                    return Center(
                      child: _failed
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Kamera açılamadı. İzin verildiğini kontrol et ya da galeriden seç.',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                            )
                          : const CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  return Center(child: CameraPreview(c));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Galeriden seç',
                    color: Colors.white,
                    iconSize: 30,
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () => Navigator.of(context).pop(const CameraShot.gallery()),
                  ),
                  GestureDetector(
                    onTap: _shoot,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _busy ? Colors.white54 : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Flaş',
                    color: Colors.white,
                    iconSize: 30,
                    icon: Icon(switch (_flash) {
                      FlashMode.auto => Icons.flash_auto_rounded,
                      FlashMode.torch || FlashMode.always => Icons.flash_on_rounded,
                      _ => Icons.flash_off_rounded,
                    }),
                    onPressed: _toggleFlash,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
