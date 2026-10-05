import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../../core/media/media_storage.dart';
import '../../../../core/media/photo_capture_service.dart';
import '../../../../core/text/turkish_text.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../question_prefill.dart';
import '../widgets/photo_slot.dart';

class AddQuestionScreen extends ConsumerStatefulWidget {
  const AddQuestionScreen({super.key, this.prefill});
  final QuestionPrefill? prefill;

  @override
  ConsumerState<AddQuestionScreen> createState() => _AddQuestionScreenState();
}

class _AddQuestionScreenState extends ConsumerState<AddQuestionScreen> {
  final _solutionText = TextEditingController();
  final _source = TextEditingController();
  final _testTotal = TextEditingController();
  final _avgSeconds = TextEditingController();
  final _note = TextEditingController();

  late final MediaStorage _media;
  late final PhotoCaptureService _capture;

  QuestionStatus _status = QuestionStatus.wrong;
  QuestionOrigin _origin = QuestionOrigin.independent;
  CapturedPhoto? _question; // geçici: kırpılmış + sıkıştırılmış, orijinaliyle birlikte
  CapturedPhoto? _solution;
  String? _bookId, _contentNodeId, _sessionId, _subject, _mebNodeId;
  MistakeReason? _reason;
  int _difficulty = 5;
  bool _starred = false;
  bool _saving = false;
  bool _pickingQuestion = false;
  bool _pickingSolution = false;
  Set<DraftIssue> _issues = const {};

  @override
  void initState() {
    super.initState();
    _media = ref.read(mediaStorageProvider);
    _capture = ref.read(photoCaptureProvider);
    final p = widget.prefill;
    if (p != null) {
      _origin = p.origin;
      _bookId = p.bookId;
      _contentNodeId = p.contentNodeId;
      _sessionId = p.sessionId;
      _subject = p.subject;
      _mebNodeId = p.mebNodeId;
      _source.text = p.sourceName ?? '';
      if (p.testTotalQuestions != null) _testTotal.text = '${p.testTotalQuestions}';
      if (p.avgSecondsPerQuestion != null) _avgSeconds.text = '${p.avgSecondsPerQuestion!.round()}';
    }
  }

  @override
  void dispose() {
    for (final c in [_solutionText, _source, _testTotal, _avgSeconds, _note]) {
      c.dispose();
    }
    // Kaydedilmeden çıkıldıysa geçici dosyaları temizle (kaydedilenler zaten kalıcı depoda).
    for (final path in [...?_question?.tempFiles, ...?_solution?.tempFiles]) {
      unawaited(_media.discardTemp(path));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final subjects = {
      for (final n in curriculum) n.subjectLabel,
      for (final b in books) subjectKey(b.examType, b.subject),
    }.toList()
      ..sort();
    final topics = _subject == null
        ? const <CurriculumNode>[]
        : depthFirst(curriculum.where((n) => n.subjectLabel == _subject));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soru ekle'),
        actions: [
          IconButton(
            tooltip: _starred ? 'Güzel Sorular klasöründen çıkar' : 'Güzel Sorular klasörüne ekle',
            onPressed: () => setState(() => _starred = !_starred),
            icon: Icon(
              _starred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _starred ? Colors.amber.shade600 : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<QuestionStatus>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: QuestionStatus.wrong, label: Text('Yanlış'), icon: Icon(Icons.close_rounded)),
              ButtonSegment(value: QuestionStatus.blank, label: Text('Boş'), icon: Icon(Icons.remove_rounded)),
              ButtonSegment(value: QuestionStatus.correct, label: Text('Doğru'), icon: Icon(Icons.check_rounded)),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PhotoSlot(
                  label: 'Soru',
                  required: true,
                  path: _question?.path,
                  busy: _pickingQuestion,
                  hasError: _issues.contains(DraftIssue.missingQuestionImage),
                  onPick: () => _pickPhoto(solution: false),
                  onCrop: () => _recrop(solution: false),
                  onClear: () => _replacePhoto(solution: false, next: null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PhotoSlot(
                  label: 'Doğru çözüm',
                  required: true,
                  path: _solution?.path,
                  busy: _pickingSolution,
                  hasError: _issues.contains(DraftIssue.missingSolution),
                  onPick: () => _pickPhoto(solution: true),
                  onCrop: () => _recrop(solution: true),
                  onClear: () => _replacePhoto(solution: true, next: null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _solutionText,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Çözüm notu',
              helperText: 'Çözüm fotoğrafı eklemediysen zorunlu',
              errorText: _issues.contains(DraftIssue.missingSolution) ? DraftIssue.missingSolution.message : null,
            ),
          ),
          _SectionTitle('Kaynak'),
          SegmentedButton<QuestionOrigin>(
            showSelectedIcon: false,
            segments: [for (final o in QuestionOrigin.values) ButtonSegment(value: o, label: Text(o.label))],
            selected: {_origin},
            onSelectionChanged: (s) => setState(() => _origin = s.first),
          ),
          const SizedBox(height: 12),
          if (_origin == QuestionOrigin.book && books.isNotEmpty)
            DropdownMenu<String>(
              key: ValueKey('book-$_bookId'),
              initialSelection: _bookId,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Kitap'),
              errorText: _issues.contains(DraftIssue.missingSource) ? 'Kitap seç' : null,
              dropdownMenuEntries: [for (final b in books) DropdownMenuEntry(value: b.id, label: b.title)],
              onSelected: (id) => _selectBook(books.where((b) => b.id == id).firstOrNull),
            )
          else
            TextField(
              controller: _source,
              decoration: InputDecoration(
                labelText: _origin == QuestionOrigin.mockExam ? 'Deneme adı' : 'Kaynak',
                hintText: _origin == QuestionOrigin.mockExam ? 'Örn. 3D TYT Deneme 4' : 'Örn. Telegram, hoca föyü',
                errorText: _issues.contains(DraftIssue.missingSource) ? DraftIssue.missingSource.message : null,
              ),
            ),
          _SectionTitle('Ders ve konu'),
          DropdownMenu<String>(
            key: ValueKey('subject-$_subject'),
            initialSelection: _subject,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Ders'),
            errorText: _issues.contains(DraftIssue.missingSubject) ? DraftIssue.missingSubject.message : null,
            dropdownMenuEntries: [for (final s in subjects) DropdownMenuEntry(value: s, label: s)],
            onSelected: (s) => setState(() {
              if (s != _subject) _mebNodeId = null;
              _subject = s;
            }),
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            key: ValueKey('topic-$_subject'),
            enabled: topics.isNotEmpty,
            initialSelection: _mebNodeId,
            expandedInsets: EdgeInsets.zero,
            menuHeight: 360,
            label: const Text('MEB konusu'),
            helperText: topics.isEmpty ? 'Önce dersi seç' : 'Yazarak ara',
            enableFilter: true,
            requestFocusOnTap: true,
            // Türkçe katlamalı arama: "isci" yazınca "İşçi ve Havuz" bulunur.
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
                    child: Text(t.title, style: t.depth == 0 ? const TextStyle(fontWeight: FontWeight.w600) : null),
                  ),
                ),
            ],
            onSelected: (id) => setState(() => _mebNodeId = id),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _NumberField(controller: _testTotal, label: 'Testteki soru sayısı')),
              const SizedBox(width: 12),
              Expanded(child: _NumberField(controller: _avgSeconds, label: 'Soru başına süre', suffix: 'sn')),
            ],
          ),
          if (_status != QuestionStatus.correct) ...[
            const SizedBox(height: 12),
            DropdownMenu<MistakeReason>(
              initialSelection: _reason,
              expandedInsets: EdgeInsets.zero,
              label: Text(_status == QuestionStatus.blank ? 'Neden boş bıraktın?' : 'Neden yanlış yaptın?'),
              errorText: _issues.contains(DraftIssue.missingReason) ? 'Bir neden seç' : null,
              dropdownMenuEntries: [
                for (final r in MistakeReason.values) DropdownMenuEntry(value: r, label: r.label),
              ],
              onSelected: (r) => setState(() => _reason = r),
            ),
          ],
          _SectionTitle('Zorluk: $_difficulty / 10'),
          Slider(
            value: _difficulty.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_difficulty',
            onChanged: (v) => setState(() => _difficulty = v.round()),
          ),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
          ),
          if (_starred)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Bu soru Güzel Sorular klasörüne de eklenecek.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(addAnother: true),
                  child: const Text('Kaydet, yenisini ekle'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(addAnother: false),
                  child: _saving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectBook(Book? book) {
    if (book == null) return;
    setState(() {
      final subject = subjectKey(book.examType, book.subject);
      if (subject != _subject) _mebNodeId = null;
      if (book.id != _bookId) _contentNodeId = null;
      _bookId = book.id;
      _source.text = book.title;
      _subject = subject;
    });
  }

  Future<void> _pickPhoto({required bool solution}) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamerayla çek'),
              onTap: () => Navigator.pop(sheet, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(sheet, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final style = CropUiStyle.fromTheme(Theme.of(context));
    await _runPhotoOp(
      solution,
      () => _capture.capture(source, title: _cropTitle(solution), style: style),
    );
  }

  /// Her zaman tam çözünürlüklü orijinalden kırpar: fazla ya da eksik
  /// kırptıysan geri dönüp düzeltebilirsin, netlik kaybolmaz.
  Future<void> _recrop({required bool solution}) async {
    final current = solution ? _solution : _question;
    if (current == null) return;
    final style = CropUiStyle.fromTheme(Theme.of(context));
    await _runPhotoOp(
      solution,
      () => _capture.recrop(current, title: _cropTitle(solution), style: style),
    );
  }

  static String _cropTitle(bool solution) => solution ? 'Çözümü kırp' : 'Soruyu kırp';

  /// Kırpma ekranında vazgeçilirse (null) mevcut fotoğraf olduğu gibi kalır.
  Future<void> _runPhotoOp(bool solution, Future<CapturedPhoto?> Function() op) async {
    _setBusy(solution, true);
    try {
      final next = await op();
      if (next == null) return;
      if (!mounted) {
        unawaited(_media.discardTemp(next.path));
        return;
      }
      _replacePhoto(solution: solution, next: next);
    } on Exception catch (e) {
      if (mounted) _snack('Fotoğraf işlenemedi: $e');
    } finally {
      if (mounted) _setBusy(solution, false);
    }
  }

  void _setBusy(bool solution, bool value) => setState(() {
        if (solution) {
          _pickingSolution = value;
        } else {
          _pickingQuestion = value;
        }
      });

  void _replacePhoto({required bool solution, required CapturedPhoto? next}) {
    final old = solution ? _solution : _question;
    if (old != null) {
      unawaited(_media.discardTemp(old.path));
      // Yeniden kırpmada orijinal ortaktır; yalnızca gerçekten değiştiyse sil.
      if (old.originalPath != next?.originalPath) unawaited(_media.discardTemp(old.originalPath));
    }
    setState(() {
      if (solution) {
        _solution = next;
      } else {
        _question = next;
      }
      if (next != null) {
        _issues = {..._issues}
          ..remove(solution ? DraftIssue.missingSolution : DraftIssue.missingQuestionImage);
      }
    });
  }

  QuestionDraft _buildDraft() {
    final fromBook = _origin == QuestionOrigin.book;
    return QuestionDraft(
      status: _status,
      origin: _origin,
      questionImagePath: _question?.path,
      solutionImagePath: _solution?.path,
      solutionText: _solutionText.text,
      sourceName: _source.text,
      bookId: fromBook ? _bookId : null,
      contentNodeId: fromBook ? _contentNodeId : null,
      sessionId: _sessionId,
      subject: _subject,
      mebNodeId: _mebNodeId,
      testTotalQuestions: int.tryParse(_testTotal.text),
      avgSecondsPerQuestion: double.tryParse(_avgSeconds.text),
      reason: _status == QuestionStatus.correct ? null : _reason,
      difficulty: _difficulty,
      isStarred: _starred,
      note: _note.text,
    );
  }

  Future<void> _save({required bool addAnother}) async {
    final draft = _buildDraft();
    final issues = draft.validate();
    if (issues.isNotEmpty) {
      setState(() => _issues = issues.toSet());
      _snack(issues.first.message);
      return;
    }

    setState(() {
      _saving = true;
      _issues = const {};
    });
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(saveQuestionCardProvider).call(draft);
      if (!mounted) return;
      if (addAnother) {
        // Kaynak, ders, konu ve süre aynı kalır: aynı testten art arda hızlı giriş.
        _replacePhoto(solution: false, next: null);
        _replacePhoto(solution: true, next: null);
        setState(() {
          _solutionText.clear();
          _note.clear();
          _reason = null;
          _starred = false;
          _difficulty = 5;
        });
        messenger.showSnackBar(const SnackBar(content: Text('Soru kaydedildi. Sıradakini ekleyebilirsin.')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Soru kaydedildi.')));
        router.canPop() ? router.pop() : router.go(AppRoutes.home);
      }
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Soru kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label, this.suffix});
  final TextEditingController controller;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );
}
