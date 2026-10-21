import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/notifications/reminder_service.dart';
import '../question_bank/question_bank_providers.dart';
import 'data/settings_repository.dart';
import 'domain/settings.dart';

final reminderServiceProvider = Provider<ReminderService>(
    (ref) => throw UnimplementedError('reminderServiceProvider main() içinde override edilmeli'));

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(appDatabaseProvider)));

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  /// Kaydeder ve hatırlatıcıları yeni ayara göre kurar.
  Future<void> change(AppSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
    await applyReminders(
      ref.read(reminderServiceProvider),
      next,
      due: ref.read(dueCountProvider).value ?? 0,
    );
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Ayarlara göre hatırlatıcıları kurar ya da kaldırır. Tekrar metni o anki
/// bekleyen soru sayısını içerir; uygulama her açıldığında tazelenir.
Future<void> applyReminders(ReminderService reminders, AppSettings s, {required int due}) async {
  if (s.reviewReminder) {
    await reminders.scheduleDaily(
      id: ReminderService.reviewId,
      hour: s.reviewTime.hour,
      minute: s.reviewTime.minute,
      title: 'Tekrar zamanı',
      body: reviewReminderBody(due),
    );
  } else {
    await reminders.cancel(ReminderService.reviewId);
  }
  if (s.studyReminder) {
    await reminders.scheduleDaily(
      id: ReminderService.studyId,
      hour: s.studyTime.hour,
      minute: s.studyTime.minute,
      title: 'Koçum',
      body: studyReminderBody,
    );
  } else {
    await reminders.cancel(ReminderService.studyId);
  }
}
