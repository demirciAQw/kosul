import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/core_providers.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../question_bank/domain/practice_test.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/recurrence.dart';
import '../../question_bank/presentation/question_pdf.dart';
import '../../question_bank/question_bank_providers.dart';

/// Yanlışlarımdan test: seçeneklere göre soru seçer, PDF olarak paylaşır.
class PracticeTestScreen extends ConsumerStatefulWidget {
  const PracticeTestScreen({super.key});

  @override
  ConsumerState<PracticeTestScreen> createState() => _PracticeTestScreenState();
}

class _PracticeTestScreenState extends ConsumerState<PracticeTestScreen> {
  var _o = const PracticeTestOptions();
  int _seed = math.Random().nextInt(1 << 30);
  bool _answerKey = true;
  bool _busy = false;

  PracticeTestOptions _with({
    int? count,
    String? Function()? subject,
    String? Function()? topicKey,
    DifficultyBand? band,
    MistakeReason? Function()? reason,
    bool? coverWeakTopics,
    bool? photosOnly,
  }) =>
      PracticeTestOptions(
        count: count ?? _o.count,
        subject: subject != null ? subject() : _o.subject,
        topicKey: topicKey != null ? topicKey() : _o.topicKey,
        band: band ?? _o.band,
        reason: reason != null ? reason() : _o.reason,
        coverWeakTopics: coverWeakTopics ?? _o.coverWeakTopics,
        photosOnly: photosOnly ?? _o.photosOnly,
      );

  Future<void> _pdf(PracticeTest test, Map<String, CurriculumNode> curriculum) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final items = [
        for (final c in test.cards)
          PdfQuestion(c, [
            subjectName(c.subject),
            topicOfCard(c, curriculum)?.label,
            c.locationText,
          ].whereType<String>().join(' · ')),
      ];
      final title = [
        'Koçum testi',
        if (_o.subject != null) subjectName(_o.subject!),
        if (_o.band != DifficultyBand.any) _o.band.label,
        if (_o.reason != null) _o.reason!.label,
      ].join(' · ');
      final bytes = await buildQuestionPdf(
        title: title,
        subtitle: '${test.cards.length} soru',
        items: items,
        media: ref.read(mediaStorageProvider),
        answerKey: _answerKey,
      );
      final now = DateTime.now();
      final out = File('${(await getTemporaryDirectory()).path}/Kocum_Test_${now.millisecondsSinceEpoch}.pdf');
      await out.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(out.path, mimeType: 'application/pdf')]));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Test hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
    final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
    final mistakes = [for (final c in cards) if (c.status != QuestionStatus.correct) c];
    final subjects = {for (final c in mistakes) c.subject}.toList()..sort();
    final topics = <String, String>{};
    for (final c in mistakes) {
      if (_o.subject != null && c.subject != _o.subject) continue;
      final t = topicOfCard(c, curriculum);
      if (t != null) topics[t.key] = t.label;
    }
    final test = buildPracticeTest(cards, _o, curriculum: curriculum, seed: _seed);

    return Scaffold(
      appBar: AppBar(title: const Text('Yanlışlarımdan test')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Soru sayısı', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [10, 20, 30, 40, 60])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _o.count == n,
                  onSelected: (_) => setState(() => _o = _with(count: n)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownMenu<String?>(
            key: ValueKey('ders-${_o.subject}'),
            initialSelection: _o.subject,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Ders'),
            menuHeight: 320,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: null, label: 'Tüm dersler'),
              for (final s in subjects) DropdownMenuEntry(value: s, label: s),
            ],
            onSelected: (s) => setState(() => _o = _with(subject: () => s, topicKey: () => null)),
          ),
          const SizedBox(height: 12),
          DropdownMenu<String?>(
            key: ValueKey('konu-${_o.subject}-${_o.topicKey}'),
            initialSelection: _o.topicKey,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Konu'),
            menuHeight: 320,
            enabled: !_o.coverWeakTopics,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: null, label: 'Tüm konular'),
              for (final e in (topics.entries.toList()..sort((a, b) => a.value.compareTo(b.value))))
                DropdownMenuEntry(value: e.key, label: e.value),
            ],
            onSelected: (k) => setState(() => _o = _with(topicKey: () => k)),
          ),
          const SizedBox(height: 16),
          Text('Zorluk', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in DifficultyBand.values)
                ChoiceChip(
                  label: Text(b.label),
                  selected: _o.band == b,
                  onSelected: (_) => setState(() => _o = _with(band: b)),
                ),
            ],
          ),
          if (_o.band == DifficultyBand.mixed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Kolay, orta ve zordan eşit pay; kolaydan zora sıralı.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          Text('Hata nedeni', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Hepsi'),
                selected: _o.reason == null,
                onSelected: (_) => setState(() => _o = _with(reason: () => null)),
              ),
              for (final r in MistakeReason.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: _o.reason == r,
                  onSelected: (_) => setState(() => _o = _with(reason: () => r)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.coverWeakTopics,
            onChanged: (v) => setState(() => _o = _with(coverWeakTopics: v, topicKey: () => null)),
            title: const Text('Çok yanlış yaptığım konuların hepsi'),
            subtitle: const Text('En az 2 hata olan her konudan en az bir soru'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _o.photosOnly,
            onChanged: (v) => setState(() => _o = _with(photosOnly: v)),
            title: const Text('Yalnızca fotoğraflı sorular'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _answerKey,
            onChanged: (v) => setState(() => _answerKey = v),
            title: const Text('Sonda cevap anahtarı'),
          ),
          const SizedBox(height: 8),
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.cards.isEmpty ? 'Bu seçeneklere uyan soru yok' : '${test.cards.length} soruluk test hazır',
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  Text('Süzgece uyan: ${test.available} soru',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
                  for (final n in test.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(n, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: test.cards.isEmpty ? null : () => setState(() => _seed = math.Random().nextInt(1 << 30)),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Yeniden seç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || test.cards.isEmpty ? null : () => _pdf(test, curriculum),
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF oluştur'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
