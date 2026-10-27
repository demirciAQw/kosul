import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../../ocr/data/genai_describer.dart';
import '../../ocr/ocr_providers.dart';
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
        _Section('Performans'),
        Card(
          child: SwitchListTile(
            secondary: const ToneIcon(Icons.bolt_rounded, color: KocumColors.amber),
            title: const Text('Hızlı fotoğraf modu'),
            subtitle: const Text(
              'Fotoğraflar daha küçük çözünürlükte işlenir: kırpma ekranı daha çabuk açılır, '
              'kayıt daha çabuk biter. Çok küçük yazılı sorularda netlik biraz azalabilir.',
            ),
            value: s.fastPhotos,
            onChanged: (on) => _change(context, ref, s.copyWith(fastPhotos: on)),
          ),
        ),
        Card(
          child: SwitchListTile(
            secondary: const ToneIcon(Icons.camera_alt_outlined, color: KocumColors.amber),
            title: const Text('Kamerayı hazır tut'),
            subtitle: const Text(
              'Hızlı fotoğraf modunda uygulama kendi kamerasını kullanır. Bu açıksa kamera, uygulama '
              'öndeyken hazır bekler ve anında açılır; uygulama arka plana geçince kapanır. Kamera açık '
              'olduğu için ekranda yeşil nokta görünür ve pil biraz daha fazla harcanır.',
            ),
            value: s.fastPhotos && s.warmCamera,
            onChanged: s.fastPhotos ? (on) => _change(context, ref, s.copyWith(warmCamera: on)) : null,
          ),
        ),
        _Section('Arama'),
        Card(
          child: SwitchListTile(
            secondary: const ToneIcon(Icons.manage_search_rounded, color: KocumColors.blue),
            title: const Text('Akıllı arama'),
            subtitle: const Text(
              'Yazım hatalarını tolere eder ("türv" → Türev), tek kelimesi benzeyen soruyu da '
              'bulur ve sonuçları benzerliğe göre sıralar. Kapalıyken birebir metin aranır.',
            ),
            value: s.smartSearch,
            onChanged: (on) => _change(context, ref, s.copyWith(smartSearch: on)),
          ),
        ),
        _Section('Fotoğraftaki metin'),
        const _OcrCard(),
        const _GenAiCard(),
        _Section('Haftalık sabit programım'),
        _FixedScheduleCard(settings: s),
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

/// Okul, kurs, dershane saatleri: yapay zekâ raporuna girer; program bu
/// saatlerin dışına kurulur.
class _FixedScheduleCard extends ConsumerStatefulWidget {
  const _FixedScheduleCard({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_FixedScheduleCard> createState() => _FixedScheduleCardState();
}

class _FixedScheduleCardState extends ConsumerState<_FixedScheduleCard> {
  late final _text = TextEditingController(text: widget.settings.fixedSchedule);

  bool get _changed => _text.text.trim() != widget.settings.fixedSchedule.trim();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    await ref.read(settingsProvider.notifier).change(widget.settings.copyWith(fixedSchedule: _text.text.trim()));
    messenger.showSnackBar(const SnackBar(content: Text('Sabit program kaydedildi.')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Okul, kurs, dershane saatleri',
                hintText: 'Örn.\nPzt–Cum 08:00–15:30 okul\nSalı ve Perşembe 17:00–19:30 dershane\nHer gün 15:40–18:00 etüt',
                alignLabelWithHint: true,
              ),
            ),
            TextButton(onPressed: _changed ? _save : null, child: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }
}

/// Fotoğraftaki metni okuma: açma/kapama ve ilerleme.
class _OcrCard extends ConsumerWidget {
  const _OcrCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;
    final records = ref.watch(ocrRecordsProvider).value ?? const {};
    final done = records.values.where((r) => r.ok).length;
    final failed = records.values.where((r) => !r.ok).length;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const ToneIcon(Icons.document_scanner_outlined, color: KocumColors.green),
            title: const Text('Fotoğraflardaki metni oku'),
            subtitle: const Text(
              'Soru ve not fotoğrafları arka planda, telefonda okunur (internet gerekmez). '
              'Soru, şıklar ve metin her soruya bağlı saklanır; arama ve raporlar bunu da kullanır.',
            ),
            value: settings?.ocrEnabled ?? true,
            onChanged: settings == null
                ? null
                : (on) => ref.read(settingsProvider.notifier).change(settings.copyWith(ocrEnabled: on)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$done fotoğraf okundu${failed > 0 ? ', $failed okunamadı' : ''}.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resim açıklaması (Gemini Nano): cihaz durumu, indirme ve aç/kapa.
class _GenAiCard extends ConsumerStatefulWidget {
  const _GenAiCard();

  @override
  ConsumerState<_GenAiCard> createState() => _GenAiCardState();
}

class _GenAiCardState extends ConsumerState<_GenAiCard> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    await ref.read(genAiDescriberProvider).download();
    ref.invalidate(genAiStatusProvider);
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;
    final status = ref.watch(genAiStatusProvider);
    final value = status.value;
    final unavailable = value == 'unavailable';
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const ToneIcon(Icons.auto_awesome_outlined, color: KocumColors.blue),
            title: const Text('Resim açıklaması (Gemini Nano)'),
            subtitle: const Text(
              'Sorulardaki grafik, şekil ve fotoğraflar telefonda kısa bir açıklamayla etiketlenir; '
              'açıklamalar aramaya ve Claude raporuna girer. Yalnızca destekleyen cihazlarda, İngilizce.',
            ),
            value: (settings?.genAiDescriptions ?? true) && !unavailable,
            onChanged: settings == null || unavailable
                ? null
                : (on) => ref.read(settingsProvider.notifier).change(settings.copyWith(genAiDescriptions: on)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status.isLoading ? 'Durum denetleniyor…' : genAiStatusLabel(value ?? 'unknown'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (value == 'downloadable')
                  TextButton(
                    onPressed: _downloading ? null : _download,
                    child: Text(_downloading ? 'İniyor…' : 'İndir'),
                  ),
                IconButton(
                  tooltip: 'Yeniden denetle',
                  onPressed: () => ref.invalidate(genAiStatusProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
