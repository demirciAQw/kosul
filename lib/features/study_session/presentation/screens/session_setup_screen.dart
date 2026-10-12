import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../../core/text/turkish_text.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../../curriculum/domain/yks.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../domain/study_session.dart';
import '../../study_session_providers.dart';
import '../widgets/topic_selection_view.dart';

enum _Mode { book, free }

/// Kitap › Ünite › Konu › Sayfa ağacından çoklu seçim ya da kitapsız çalışma, tek BAŞLA.
class SessionSetupScreen extends ConsumerStatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  _Mode _mode = _Mode.book;
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ne çalışacaksın?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Mode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Mode.book, label: Text('Kitaptan'), icon: Icon(Icons.menu_book_outlined)),
                  ButtonSegment(value: _Mode.free, label: Text('Kitapsız'), icon: Icon(Icons.edit_note_rounded)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
          ),
          Expanded(
            child: _mode == _Mode.book
                ? TopicSelectionView(
                    actionLabel: 'BAŞLA',
                    actionIcon: Icons.play_arrow_rounded,
                    busy: _starting,
                    onSubmit: _start,
                  )
                : _FreeSessionForm(busy: _starting, onStart: _start),
          ),
        ],
      ),
    );
  }

  Future<void> _start(List<SessionItemDraft> drafts) async {
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(sessionChronometerProvider).requestPermission();
      await ref.read(startStudySessionProvider).call(drafts);
      // Kurulum sayfasının yerine geçer: geri tuşu ana ekrana döner.
      unawaited(router.pushReplacement(AppRoutes.activeSession));
    } on StudySessionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        action: e is SessionAlreadyRunningException
            ? SnackBarAction(
                label: 'Oturuma dön',
                onPressed: () => router.pushReplacement(AppRoutes.activeSession),
              )
            : null,
      ));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

/// Kitap olmadan: ders (zorunlu), konu ve ne yapılacağı (isteğe bağlı).
/// Video, konu anlatımı, PDF test, okul ödevi… süre yine analize sayılır.
class _FreeSessionForm extends ConsumerStatefulWidget {
  const _FreeSessionForm({required this.busy, required this.onStart});

  final bool busy;
  final ValueChanged<List<SessionItemDraft>> onStart;

  @override
  ConsumerState<_FreeSessionForm> createState() => _FreeSessionFormState();
}

class _FreeSessionFormState extends ConsumerState<_FreeSessionForm> {
  final _note = TextEditingController();
  String? _subject;
  String? _topicId;
  StudyActivity _activity = StudyActivity.lecture;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final subjects = allSubjectKeys(extra: [
      for (final n in curriculum) n.subjectLabel,
      for (final b in books) subjectKey(b.examType, b.subject),
    ]);
    final topics = _subject == null
        ? const <CurriculumNode>[]
        : depthFirst(curriculum.where((n) => n.subjectLabel == _subject));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Video, konu anlatımı, PDF test ya da okul ödevi: kitap seçmeden sayacı başlat. '
                'Süre yine derse göre analize sayılır.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              DropdownMenu<String>(
                key: ValueKey('free-subject-$_subject'),
                initialSelection: _subject,
                expandedInsets: EdgeInsets.zero,
                menuHeight: 360,
                label: const Text('Ders'),
                dropdownMenuEntries: [for (final s in subjects) DropdownMenuEntry(value: s, label: s)],
                onSelected: (s) => setState(() {
                  if (s != _subject) _topicId = null;
                  _subject = s;
                }),
              ),
              const SizedBox(height: 12),
              if (topics.isNotEmpty)
                DropdownMenu<String>(
                  key: ValueKey('free-topic-$_subject'),
                  initialSelection: _topicId,
                  expandedInsets: EdgeInsets.zero,
                  menuHeight: 360,
                  label: const Text('Konu (isteğe bağlı)'),
                  enableFilter: true,
                  requestFocusOnTap: true,
                  filterCallback: (entries, filter) {
                    final q = normalizeTr(filter);
                    return q.isEmpty ? entries : entries.where((e) => normalizeTr(e.label).contains(q)).toList();
                  },
                  dropdownMenuEntries: [
                    for (final t in topics)
                      DropdownMenuEntry(
                        value: t.id,
                        label: t.title,
                        labelWidget: Padding(
                          padding: EdgeInsetsDirectional.only(start: t.depth * 16.0),
                          child: Text(t.title),
                        ),
                      ),
                  ],
                  onSelected: (id) => setState(() => _topicId = id),
                ),
              const SizedBox(height: 20),
              Text('Ne yapacaksın?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in StudyActivity.values)
                    ChoiceChip(
                      label: Text(a.label),
                      selected: _activity == a,
                      onSelected: (_) => setState(() => _activity = a),
                    ),
                ],
              ),
              if (_activity.hasQuestions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Bitirince doğru, yanlış ve boşlarını girersin; yanlışları optik formla işaretleyebilirsin.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (isteğe bağlı)',
                  hintText: 'Örn. Türev konu anlatımı videosu',
                ),
              ),
            ],
          ),
        ),
        Material(
          color: theme.colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _subject == null ? 'Önce dersi seç' : _activity.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: widget.busy || _subject == null ? null : () => _start(curriculum),
                    icon: widget.busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('BAŞLA'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _start(List<CurriculumNode> curriculum) {
    final subject = _subject;
    if (subject == null) return;
    final topic = curriculum.where((n) => n.id == _topicId).firstOrNull;
    final note = _note.text.trim();
    final what = [subject, if (topic != null) topic.title].join(' › ');
    final label = note.isEmpty ? '${_activity.label}: $what' : '$note ($what)';
    widget.onStart([
      SessionItemDraft(
        label: label,
        pages: const [],
        subject: subject,
        mebNodeId: topic?.id,
        activity: _activity,
      ),
    ]);
  }
}
