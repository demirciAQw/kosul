import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/export/zip_writer.dart';
import '../../../core/text/turkish_text.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../domain/question_card.dart';
import '../domain/question_export.dart';
import '../../curriculum/domain/yks.dart';
import 'question_pdf.dart';

/// Defter'den dışa aktarma: hangi sorular, hangi dosyalar, nasıl adlandırılsın.
/// Sonuç tek bir ZIP olarak paylaşılır (Drive, WhatsApp, dosyalar…).
Future<void> showQuestionExportSheet(
  BuildContext context, {
  required Map<String, List<QuestionCard>> scopes,
  bool pdf = false,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExportSheet(scopes: scopes, startWithPdf: pdf),
    );

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.scopes, this.startWithPdf = false});
  final bool startWithPdf;

  /// Kapsam adı → sorular (ör. "Seçili 12 soru", "Bu arama", "Tüm defter").
  final Map<String, List<QuestionCard>> scopes;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  late String _scope = widget.scopes.keys.first;
  var _o = const QuestionExportOptions();
  bool _busy = false;

  /// Biçim: ZIP (fotoğraflar + tablo) ya da yazdırılabilir PDF (sayfada 4 soru).
  late bool _pdf = widget.startWithPdf;
  bool _answerKey = true;

  List<QuestionCard> get _cards => widget.scopes[_scope] ?? const [];

  String? _topicOf(QuestionCard c, Map<String, CurriculumNode> curriculum) {
    final node = c.mebNodeId == null ? null : curriculum[c.mebNodeId];
    if (node != null) return node.title;
    final t = c.topicText?.trim();
    return (t == null || t.isEmpty) ? null : titleCaseTr(t);
  }

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final media = ref.read(mediaStorageProvider);
    final curriculum = {for (final n in ref.read(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
    setState(() => _busy = true);
    try {
      final items = [
        for (final c in _cards)
          PdfQuestion(c, [
            subjectName(c.subject),
            if (_topicOf(c, curriculum) != null) _topicOf(c, curriculum)!,
            c.locationText,
          ].join(' · ')),
      ];
      final bytes = await buildQuestionPdf(
        title: 'Yanlış defterim',
        subtitle: '$_scope, ${_cards.length} soru',
        items: items,
        media: media,
        answerKey: _answerKey,
      );
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/Kocum_Yanlis_Defteri_${now.year}-${two(now.month)}-${two(now.day)}.pdf');
      await out.writeAsBytes(bytes, flush: true);
      navigator.pop();
      await SharePlus.instance.share(ShareParams(files: [XFile(out.path, mimeType: 'application/pdf')]));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('PDF hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final media = ref.read(mediaStorageProvider);
    final curriculum = {for (final n in ref.read(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
    setState(() => _busy = true);
    try {
      final plan = planQuestionExport(
        _cards,
        _o,
        topicOf: (c) {
          final node = c.mebNodeId == null ? null : curriculum[c.mebNodeId];
          if (node != null) return node.title;
          final t = c.topicText?.trim();
          return (t == null || t.isEmpty) ? null : titleCaseTr(t);
        },
      );
      final zip = ZipWriter();
      var missing = 0;
      for (final m in plan.media) {
        final file = media.resolve(m.mediaPath);
        if (await file.exists()) {
          zip.add(m.zipName, await file.readAsBytes());
        } else {
          missing++;
        }
      }
      if (plan.table != null) zip.addText('etiketler.csv', plan.table!, bom: true);
      if (plan.json != null) zip.addText('defter.json', plan.json!);
      if (zip.length == 0) {
        messenger.showSnackBar(const SnackBar(content: Text('Pakete girecek dosya yok. Seçenekleri kontrol et.')));
        return;
      }
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/Kocum_Defter_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}.zip');
      await out.writeAsBytes(zip.finish(), flush: true);
      navigator.pop();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(out.path, mimeType: 'application/zip')],
        subject: 'Koçum defteri',
        text: '${_cards.length} soru${missing > 0 ? ' ($missing fotoğraf bulunamadı)' : ''}',
      ));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = _cards.where((c) => c.questionImage != null).length;
    final solutions = _cards.where((c) => c.solutionImage != null).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Dışa aktar', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Tek bir ZIP dosyası olarak paylaşılır.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text('Hangi sorular', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in widget.scopes.entries)
                ChoiceChip(
                  label: Text('${e.key} (${e.value.length})'),
                  selected: _scope == e.key,
                  onSelected: (_) => setState(() => _scope = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Biçim', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('PDF (sayfada 4 soru)'),
                selected: _pdf,
                onSelected: (_) => setState(() => _pdf = true),
              ),
              ChoiceChip(
                label: const Text('ZIP (fotoğraflar ve tablo)'),
                selected: !_pdf,
                onSelected: (_) => setState(() => _pdf = false),
              ),
            ],
          ),
          if (_pdf) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _answerKey,
              onChanged: (v) => setState(() => _answerKey = v),
              title: const Text('Sonda cevap anahtarı'),
              subtitle: const Text('Kendini test etmek için sorular önce, cevaplar en sonda'),
            ),
            Text(
              'Her kutuda ders, konu ve kaynak yazar; fotoğrafı olmayan soruların yerine konumu yazılır.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ] else ...[
          const SizedBox(height: 12),
          Text('Pakete neler girsin', style: theme.textTheme.titleSmall),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.questionPhotos,
            onChanged: (v) => setState(() => _o = _o.copyWith(questionPhotos: v)),
            title: const Text('Soru fotoğrafları'),
            subtitle: Text('$photos fotoğraf'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.solutionPhotos,
            onChanged: (v) => setState(() => _o = _o.copyWith(solutionPhotos: v)),
            title: const Text('Çözüm fotoğrafları'),
            subtitle: Text('$solutions fotoğraf'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.table,
            onChanged: (v) => setState(() => _o = _o.copyWith(table: v)),
            title: const Text('Etiket tablosu (Excel)'),
            subtitle: const Text('Ders, konu, kaynak, soru no, şıklar, neden'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.fullData,
            onChanged: (v) => setState(() => _o = _o.copyWith(fullData: v)),
            title: const Text('Tüm veri (JSON)'),
            subtitle: const Text('Başka bir uygulamaya ya da yedeğe'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.folderBySubject,
            onChanged: (v) => setState(() => _o = _o.copyWith(folderBySubject: v)),
            title: const Text('Derslere göre klasörle'),
          ),
          const SizedBox(height: 4),
          Text('Fotoğraf adları', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in ExportNaming.values)
                ChoiceChip(
                  label: Text(n.label),
                  selected: _o.naming == n,
                  onSelected: (_) => setState(() => _o = _o.copyWith(naming: n)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            switch (_o.naming) {
              ExportNaming.tags => 'Örn. TYT_Matematik_Türev_Test_5_S7_Yanlış.webp',
              ExportNaming.date => 'Örn. 2026-10-19_TYT_Matematik_Yanlış.webp',
              ExportNaming.sequence => 'Örn. 001_TYT_Matematik.webp',
            },
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _cards.isEmpty || (!_pdf && _o.isEmpty) ? null : (_pdf ? _exportPdf : _export),
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded),
            label: Text(_busy ? 'Hazırlanıyor…' : (_pdf ? '${_cards.length} soruyla PDF oluştur' : '${_cards.length} soruyu paylaş')),
          ),
        ],
      ),
    );
  }
}
