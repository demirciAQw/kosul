import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Uygulama içi kamera (performans modunda). Telefonun kamera uygulamasını
/// başlatmak her seferinde saniyeler sürer; burada kamera bir kez açılır ve
/// uygulama öndeyken hazır bekler (görüntü akışı duraklatılır), arka plana
/// geçince kapatılır.
class FastCamera extends ChangeNotifier {
  CameraController? _controller;
  Future<CameraController?>? _opening;
  bool _showing = false;

  /// Uygulama öndeyken kamerayı hazır tut (Ayarlar › Kamerayı hazır tut).
  bool keepWarm = false;

  /// Kullanılabilir (açık ve hazır) kamera; yoksa null.
  CameraController? get controller => _controller?.value.isInitialized == true ? _controller : null;

  /// Kamerayı açar (açıksa onu döndürür). Kamera yoksa ya da izin verilmezse null.
  Future<CameraController?> open() => _opening ??= _open();

  Future<CameraController?> _open() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ??
          cameras.firstOrNull;
      if (back == null) {
        _opening = null;
        return null;
      }
      // 1080p: soru yazısı için yeterli, çekim gecikmesiz; ses kapalı.
      final c = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      _controller = c;
      if (!_showing) await _quiet(c.pausePreview);
      notifyListeners();
      return c;
    } catch (_) {
      _opening = null;
      return null;
    }
  }

  /// Uygulama öne geldi: ayar açıksa kamerayı hazırla.
  Future<void> warmUp() async {
    if (keepWarm) await open();
  }

  /// Uygulama arka plana geçti ya da kapanıyor: kamera kapatılır.
  Future<void> close() async {
    final c = _controller;
    _controller = null;
    _opening = null;
    notifyListeners();
    if (c != null) await _quiet(c.dispose);
  }

  /// Kamera ekranı açıldı/kapandı: önizleme akışı yalnızca ekrandayken çalışır.
  Future<void> showing(bool on) async {
    _showing = on;
    final c = controller;
    if (c == null) return;
    await _quiet(on ? c.resumePreview : c.pausePreview);
    // Hazır tutma kapalıysa ekran kapanınca kamera da kapanır.
    if (!on && !keepWarm) await close();
  }

  static Future<void> _quiet(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
