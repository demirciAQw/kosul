import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/features/settings/data/settings_repository.dart';
import 'package:kocum/features/settings/domain/settings.dart';

void main() {
  test('ayarlar kaydedilir ve aynen okunur', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    expect((await repo.load()).reviewReminder, isFalse); // varsayılan

    const s = AppSettings(
      reviewReminder: true,
      reviewTime: TimeOfDay(hour: 21, minute: 15),
      studyReminder: true,
      studyTime: TimeOfDay(hour: 6, minute: 5),
      themeMode: ThemeMode.dark,
    );
    await repo.save(s);
    final back = await repo.load();
    expect(back.reviewReminder, isTrue);
    expect(back.reviewTime, const TimeOfDay(hour: 21, minute: 15));
    expect(back.studyTime, const TimeOfDay(hour: 6, minute: 5));
    expect(back.themeMode, ThemeMode.dark);
  });

  test('bozuk ayar varsayılana döner', () {
    final s = AppSettings.fromJson({'reviewReminder': 'evet', 'reviewTime': '25:99', 'themeMode': 'mor'});
    expect(s.reviewReminder, isFalse);
    expect(s.reviewTime, const TimeOfDay(hour: 20, minute: 0));
    expect(s.themeMode, ThemeMode.system);
  });

  test('tekrar hatırlatıcısı bekleyen soru sayısını söyler', () {
    expect(reviewReminderBody(12), contains('12 soru'));
    expect(reviewReminderBody(0), isNot(contains('0 soru')));
  });
}
