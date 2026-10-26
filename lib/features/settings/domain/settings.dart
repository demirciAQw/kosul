import 'package:flutter/material.dart';

/// Kullanıcı ayarları: hatırlatıcılar ve görünüm.
class AppSettings {
  const AppSettings({
    this.reviewReminder = false,
    this.reviewTime = const TimeOfDay(hour: 20, minute: 0),
    this.studyReminder = false,
    this.studyTime = const TimeOfDay(hour: 17, minute: 30),
    this.themeMode = ThemeMode.system,
    this.fixedSchedule = '',
    this.booksDeadline,
    this.fastPhotos = false,
    this.smartSearch = true,
    this.ocrEnabled = true,
    this.genAiDescriptions = true,
  });

  /// Her gün tekrar zamanı gelen soruları hatırlat.
  final bool reviewReminder;
  final TimeOfDay reviewTime;

  /// Her gün çalışmaya başlamayı hatırlat.
  final bool studyReminder;
  final TimeOfDay studyTime;

  final ThemeMode themeMode;

  /// Okul, kurs, dershane gibi sabit saatler (serbest metin). Yapay zekâ
  /// programı bu saatlerin dışına kurar.
  final String fixedSchedule;

  /// Hedef: sistemdeki tüm kitapları bu tarihe kadar bitirmek.
  final DateTime? booksDeadline;

  /// Hızlı fotoğraf modu: daha küçük çözünürlük; kırpma ve kayıt daha hızlı.
  final bool fastPhotos;

  /// Akıllı arama: yazım hatalarını düzeltir, benzerliğe göre sıralar.
  final bool smartSearch;

  /// Fotoğraflardaki metni arka planda oku (ML Kit, telefonda).
  final bool ocrEnabled;

  /// Grafik ve şekilleri Gemini Nano ile açıkla (destekleyen cihazda).
  final bool genAiDescriptions;

  AppSettings copyWith({
    bool? reviewReminder,
    TimeOfDay? reviewTime,
    bool? studyReminder,
    TimeOfDay? studyTime,
    ThemeMode? themeMode,
    String? fixedSchedule,
    DateTime? Function()? booksDeadline,
    bool? fastPhotos,
    bool? smartSearch,
    bool? ocrEnabled,
    bool? genAiDescriptions,
  }) =>
      AppSettings(
        reviewReminder: reviewReminder ?? this.reviewReminder,
        reviewTime: reviewTime ?? this.reviewTime,
        studyReminder: studyReminder ?? this.studyReminder,
        studyTime: studyTime ?? this.studyTime,
        themeMode: themeMode ?? this.themeMode,
        fixedSchedule: fixedSchedule ?? this.fixedSchedule,
        booksDeadline: booksDeadline != null ? booksDeadline() : this.booksDeadline,
        fastPhotos: fastPhotos ?? this.fastPhotos,
        smartSearch: smartSearch ?? this.smartSearch,
        ocrEnabled: ocrEnabled ?? this.ocrEnabled,
        genAiDescriptions: genAiDescriptions ?? this.genAiDescriptions,
      );

  Map<String, dynamic> toJson() => {
        'reviewReminder': reviewReminder,
        'reviewTime': _time(reviewTime),
        'studyReminder': studyReminder,
        'studyTime': _time(studyTime),
        'themeMode': themeMode.name,
        'fixedSchedule': fixedSchedule,
        if (booksDeadline != null) 'booksDeadline': booksDeadline!.toIso8601String(),
        'fastPhotos': fastPhotos,
        'smartSearch': smartSearch,
        'ocrEnabled': ocrEnabled,
        'genAiDescriptions': genAiDescriptions,
      };

  /// Bozuk ya da eksik alanlar varsayılana döner; ayar dosyası uygulamayı düşürmez.
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      reviewReminder: j['reviewReminder'] is bool ? j['reviewReminder'] as bool : d.reviewReminder,
      reviewTime: _parse(j['reviewTime']) ?? d.reviewTime,
      studyReminder: j['studyReminder'] is bool ? j['studyReminder'] as bool : d.studyReminder,
      studyTime: _parse(j['studyTime']) ?? d.studyTime,
      themeMode: ThemeMode.values.where((m) => m.name == j['themeMode']).firstOrNull ?? d.themeMode,
      fixedSchedule: j['fixedSchedule'] is String ? j['fixedSchedule'] as String : d.fixedSchedule,
      booksDeadline: j['booksDeadline'] is String ? DateTime.tryParse(j['booksDeadline'] as String) : null,
      fastPhotos: j['fastPhotos'] == true,
      smartSearch: j['smartSearch'] != false,
      ocrEnabled: j['ocrEnabled'] != false,
      genAiDescriptions: j['genAiDescriptions'] != false,
    );
  }

  static String _time(TimeOfDay t) => '${t.hour}:${t.minute}';

  static TimeOfDay? _parse(Object? v) {
    if (v is! String) return null;
    final parts = v.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}

/// Tekrar hatırlatıcısının metni: bekleyen soru sayısına göre.
String reviewReminderBody(int due) => due > 0
    ? '$due soru tekrar seni bekliyor. Birkaç dakikan yeter.'
    : 'Bugünkü tekrarlarına bir göz at.';

const studyReminderBody = 'Çalışma zamanı. Küçük bir oturum bile sayılır.';
