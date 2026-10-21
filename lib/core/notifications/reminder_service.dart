import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Günlük hatırlatıcılar (tekrar zamanı, çalışma zamanı).
///
/// Saat dilimi adı gerekmesin diye seçilen yerel saat UTC'ye çevrilip her gün
/// aynı anda tekrarlanır. "Yaklaşık zamanında" modu kullanılır: ek izin ekranı
/// çıkmaz, Android pil tasarrufu için birkaç dakika kaydırabilir.
class ReminderService {
  ReminderService([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const reviewId = 5101;
  static const studyId = 5102;
  static const _testId = 5199;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'kocum_reminders',
      'Hatırlatıcılar',
      channelDescription: 'Günlük tekrar ve çalışma hatırlatmaları',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<void> init() async {
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// [hour]:[minute] (yerel saat) için her gün tekrarlayan bildirim kurar.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(next, tz.UTC),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  /// Ayarlardan "dene": bildirimlerin gerçekten geldiğini hemen gösterir.
  Future<void> showTest() => _plugin.show(
        _testId,
        'Hatırlatıcılar çalışıyor',
        'Seçtiğin saatte böyle bir bildirim gelecek.',
        _details,
      );
}
