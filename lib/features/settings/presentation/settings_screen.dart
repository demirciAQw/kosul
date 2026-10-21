import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../domain/settings.dart';
import '../settings_providers.dart';

/// Ayarlar: hatırlatıcılar ve görünüm.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ayarlar okunamadı: $e')),
        data: (s) => _SettingsBody(settings: s),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.settings});
  final AppSettings settings;

  Future<void> _change(BuildContext context, WidgetRef ref, AppSettings next, {bool askPermission = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (askPermission) {
      final granted = await ref.read(reminderServiceProvider).requestPermission();
      if (!granted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Bildirim izni verilmedi. Telefonun ayarlarından Koçum için bildirimleri açabilirsin.'),
        ));
      }
    }
    try {
      await ref.read(settingsProvider.notifier).change(next);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hatırlatıcı kurulamadı: $e')));
    }
  }

  Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) => showTimePicker(
        context: context,
        initialTime: initial,
        helpText: 'Hatırlatma saati',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _Section('Hatırlatıcılar'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const ToneIcon(Icons.replay_rounded, color: KocumColors.red),
                title: const Text('Tekrar hatırlatıcısı'),
                subtitle: const Text('Tekrar zamanı gelen soruları her gün hatırlat'),
                value: s.reviewReminder,
                onChanged: (on) => _change(context, ref, s.copyWith(reviewReminder: on), askPermission: on),
              ),
              ListTile(
                enabled: s.reviewReminder,
                leading: const SizedBox(width: 40),
                title: const Text('Saat'),
                trailing: Text(s.reviewTime.format(context), style: theme.textTheme.titleMedium),
                onTap: () async {
                  final t = await _pickTime(context, s.reviewTime);
                  if (t != null && context.mounted) await _change(context, ref, s.copyWith(reviewTime: t));
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              SwitchListTile(
                secondary: const ToneIcon(Icons.timer_outlined, color: KocumColors.blue),
                title: const Text('Çalışma hatırlatıcısı'),
                subtitle: const Text('Her gün çalışmaya başlamayı hatırlat'),
                value: s.studyReminder,
                onChanged: (on) => _change(context, ref, s.copyWith(studyReminder: on), askPermission: on),
              ),
              ListTile(
                enabled: s.studyReminder,
                leading: const SizedBox(width: 40),
                title: const Text('Saat'),
                trailing: Text(s.studyTime.format(context), style: theme.textTheme.titleMedium),
                onTap: () async {
                  final t = await _pickTime(context, s.studyTime);
                  if (t != null && context.mounted) await _change(context, ref, s.copyWith(studyTime: t));
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Bildirim, pil tasarrufu yüzünden birkaç dakika geç gelebilir.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final reminders = ref.read(reminderServiceProvider);
                  await reminders.requestPermission();
                  await reminders.showTest();
                },
                child: const Text('Şimdi dene'),
              ),
            ],
          ),
        ),
        _Section('Görünüm'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tema', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Telefon'), icon: Icon(Icons.smartphone_rounded)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => _change(context, ref, s.copyWith(themeMode: v.first)),
                  ),
                ),
              ],
            ),
          ),
        ),
        _Section('Hakkında'),
        Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icon/logo.png', width: 36, height: 36),
            ),
            title: const Text('Koçum'),
            subtitle: const Text('Sürüm 6.5. Tüm veriler bu telefonda saklanır.'),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
