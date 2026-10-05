import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Koşan oturumu bildirim çubuğunda canlı sayan kronometre.
///
/// Tasarım kararı: Arka planda Dart isolate'i ya da foreground service
/// ÇALIŞTIRMIYORUZ. Android'in yerel kronometresi (`usesChronometer`) sayıyı
/// sistem tarafında günceller: pil tüketimi ~0, HyperOS/MIUI'nin agresif
/// arka plan öldürmesinden etkilenmez. Gerçek süre her zaman veritabanındaki
/// `startedAt` damgasından hesaplanır; bildirim yalnızca bir yansımadır.
class SessionChronometer {
  SessionChronometer([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const _notificationId = 4207;

  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
  }

  /// Android 13+ çalışma zamanı izni. Reddedilse bile sayaç doğru çalışır.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> show({required DateTime startedAt, required int itemCount}) {
    final android = AndroidNotificationDetails(
      'study_session',
      'Çalışma oturumu',
      channelDescription: 'Süren çalışma oturumunun süresini gösterir',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: true,
      usesChronometer: true,
      when: startedAt.millisecondsSinceEpoch,
    );
    return _plugin.show(
      _notificationId,
      'Çalışma oturumu sürüyor',
      '$itemCount bölüm seçili. Bitirmek için uygulamayı aç.',
      NotificationDetails(android: android),
    );
  }

  Future<void> hide() => _plugin.cancel(_notificationId);
}
