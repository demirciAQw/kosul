import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../../core/media/photo_capture_service.dart';
import '../../../../core/media/photo_flow.dart';
import '../../../../core/text/turkish_text.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../widgets/media_image.dart';
import '../widgets/question_tile.dart' show statusColor;

/// Eksikler: hızlı işaretlenen ya da yarım bırakılan sorular.
/// Fotoğraf ve neden satırın üstünden tek dokunuşla eklenir; gerisi için karta dokun.
class IncompleteQuestionsScreen extends ConsumerStatefulWidget {
  const IncompleteQuestionsScreen({super.key});

  @override
  ConsumerState<IncompleteQuestionsScreen> createState() => _IncompleteQuestionsScreenState();
}

class _IncompleteQuestionsScreenState extends ConsumerState<IncompleteQuestionsScreen> {
  MissingPart? _only;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(incompleteQuestionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Eksikler')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Liste yüklenemedi: $e')),
        data: (all) {
          if (all.isEmpty) return const _AllDone();
          final list = _only == null ? all : [for (final i in all) if (i.missing.contains(_only)) i];
          final groups = <String, List<IncompleteCard>>{};
          for (final item in list) {
            final key = '${item.card.subject}|${item.card.testLabel ?? item.card.sourceName}';
            (groups[key] ??= []).add(item);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Tümü (${all.length})'),
                      selected: _only == null,
                      onSelected: (_) => setState(() => _only = null),
                    ),
                    for (final part in MissingPart.values) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('${part.label} yok (${all.where((i) => i.missing.contains(part)).length})'),
                        selected: _only == part,
                        onSelected: (on) => setState(() => _only = on ? part : null),
                      ),
                    ],
                  ],
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Bu filtrede eksik soru yok.', textAlign: TextAlign.center),
                ),
              for (final entry in groups.entries) ...[
                _GroupHeader(
                  title: entry.value.first.card.testLabel ?? entry.value.first.card.sourceName,
                  subtitle: [
                    entry.value.first.card.subject,
                    if (entry.value.first.card.testLabel != null) entry.value.first.card.sourceName,
                  ].join(', '),
                ),
                for (final item in entry.value) _IncompleteTile(key: ValueKey(item.card.id), item: item),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _IncompleteTile extends ConsumerStatefulWidget {
  const _IncompleteTile({super.key, required this.item});
  final IncompleteCard item;

  @override
  ConsumerState<_IncompleteTile> createState() => _IncompleteTileState();
}

class _IncompleteTileState extends ConsumerState<_IncompleteTile> {
  bool _busy = false;

  QuestionCard get _card => widget.item.card;

  Future<void> _addPhoto() async {
    final source = await askPhotoSource(context);
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final capture = ref.read(photoCaptureProvider);
    setState(() => _busy = true);
    try {
      final photo = await capturePhoto(context, capture, source, title: 'Soruyu kırp');
      if (photo == null) return;
      await ref
          .read(updateQuestionCardProvider)
          .call(_card, QuestionDraft.fromCard(_card).copyWith(questionImagePath: () => photo.path));
      await PhotoCaptureService.deleteQuietly(photo.originalPath);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fotoğraf eklenemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickReason() async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showReasonSheet(context, status: _card.status);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(updateQuestionCardProvider)
          .call(_card, QuestionDraft.fromCard(_card).copyWith(reason: () => reason));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Neden kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _card;
    final missing = widget.item.missing;
    final color = statusColor(card.status);
    final image = card.questionImage;

    return ListTile(
      onTap: () => context.push(AppRoutes.editQuestion(card.id)),
      leading: SizedBox.square(
        dimension: 48,
        child: image != null
            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: MediaImage(image, cacheWidth: 160))
            : DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Text(
                    card.questionNo?.toString() ?? '?',
                    style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
      ),
      title: Text(
        card.questionNo == null ? card.status.label : '${card.questionNo}. soru, ${lowerTr(card.status.label)}',
      ),
      subtitle: Text('Eksik: ${missing.map((m) => lowerTr(m.label)).join(', ')}'),
      trailing: _busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (missing.contains(MissingPart.reason))
                  IconButton(
                    tooltip: 'Neden seç',
                    onPressed: _pickReason,
                    icon: const Icon(Icons.help_outline_rounded),
                  ),
                if (missing.contains(MissingPart.photo))
                  IconButton(
                    tooltip: 'Fotoğraf ekle',
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                  ),
              ],
            ),
    );
  }
}

/// Tek dokunuşla neden seçimi.
Future<MistakeReason?> showReasonSheet(BuildContext context, {required QuestionStatus status}) =>
    showModalBottomSheet<MistakeReason>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status == QuestionStatus.blank ? 'Neden boş bıraktın?' : 'Neden yanlış yaptın?',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in MistakeReason.values)
                    ActionChip(label: Text(r.label), onPressed: () => Navigator.pop(sheet, r)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

class _AllDone extends StatelessWidget {
  const _AllDone();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Eksik soru yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Optik formla işaretlediğin sorular fotoğraf, çözüm ve neden eklenene kadar burada bekler.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
