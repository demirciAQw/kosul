import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/di/core_providers.dart';
import '../../../../core/media/media_storage.dart';
import '../../../../core/media/photo_capture_service.dart';
import '../../../../core/media/photo_flow.dart';
import '../../../../core/text/turkish_text.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../../curriculum/domain/yks.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../question_prefill.dart';
import '../widgets/photo_slot.dart';

/// Soru ekleme ve (Eksikler'den) tamamlama ekranı.
///
/// v2: yalnızca ders zorunlu. Fotoğraf, çözüm ve neden isteğe bağlı; eksik
/// kalan kart Eksikler listesinde bekler. Neden seçimi tek dokunuşluk çiplerle.
class AddQuestionScreen extends ConsumerStatefulWidget {
  const AddQuestionScreen({super.key, this.prefill, this.editCardId});

  final QuestionPrefill? prefill;

  /// Doluysa var olan kart düzenlenir.
  final String? editCardId;

  @override
  ConsumerState<AddQuestionScreen> createState() => _AddQuestionScreenState();
}

class _AddQuestionScreenState extends ConsumerState<AddQuestionScreen> {
  final _solutionText = TextEditingController();
  final _source = TextEditingController();
  final _testTotal = TextEditingController();
  final _avgSeconds = TextEditingController();
  final _note = TextEditingController();
  final _questionNo = TextEditingController();

  late final MediaStorage _media;
  late final PhotoCaptureService _capture;

  QuestionCard? _original; // düzenleme modunda
  bool _loading = false;

  QuestionStatus _status = QuestionStatus.wrong;
  QuestionOrigin _origin = QuestionOrigin.independent;

  // Yeni çekilen (geçici) fotoğraflar.
  CapturedPhoto? _question;
  CapturedPhoto? _solution;

  // Düzenlemede kayıtlı fotoğrafı kaldırma isteği.
  bool _clearStoredQuestion = false;
  bool _clearStoredSolution = false;

  String? _bookId, _contentNodeId, _sessionId, _sessionItemId, _mockExamId, _subject, _mebNodeId, _testLabel;
  MistakeReason? _reason;
  int _difficulty = 5;
  bool _starred = false;
  bool _saving = false;
  bool _pickingQuestion = false;
  bool _pickingSolution = false;
  Set<DraftIssue> _issues = const {};

  bool get _editing => widget.editCardId != null;

  @override
  void initState() {
    super.initState();
    _media = ref.read(mediaStorageProvider);
    _capture = ref.read(photoCaptureProvider);
    if (_editing) {
      _loading = true;
      unawaited(_loadCard(widget.editCardId!));
    } else {
      _applyPrefill(widget.prefill);
    }
  }

  void _applyPrefill(QuestionPrefill? p) {
    if (p == null) return;
    _origin = p.origin;
    _status = p.status;
    _bookId = p.bookId;
    _contentNodeId = p.contentNodeId;
    _sessionId = p.sessionId;
    _sessionItemId = p.sessionItemId;
    _mockExamId = p.mockExamId;
    _subject = p.subject;
    _mebNodeId = p.mebNodeId;
    _testLabel = p.testLabel;
    _source.text = p.sourceName ?? '';
    if (p.testTotalQuestions != null) _testTotal.text = '${p.testTotalQuestions}';
    if (p.avgSecondsPerQuestion != null) _avgSeconds.text = '${p.avgSecondsPerQuestion!.round()}';
    if (p.questionNo != null) _questionNo.text = '${p.questionNo}';
  }

  Future<void> _loadCard(String id) async {
    final card = await ref.read(questionCardRepositoryProvider).findById(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _original = card;
      if (card == null) return;
      _status = card.status;
      _origin = card.origin;
      _bookId = card.bookId;
      _contentNodeId = card.contentNodeId;
      _sessionId = card.sessionId;
      _sessionItemId = card.sessionItemId;
      _mockExamId = card.mockExamId;
      _subject = card.subject;
      _mebNodeId = card.mebNodeId;
      _testLabel = card.testLabel;
      _reason = card.reason;
      _difficulty = card.difficulty;
      _starred = card.isStarred;
      _source.text = card.sourceName == unknownSourceName ? '' : card.sourceName;
      _solutionText.text = card.solutionText ?? '';
      _note.text = card.note ?? '';
      if (card.testTotalQuestions != null) _testTotal.text = '${card.testTotalQuestions}';
      if (card.avgSecondsPerQuestion != null) _avgSeconds.text = '${card.avgSecondsPerQuestion!.round()}';
      if (card.questionNo != null) _questionNo.text = '${card.questionNo}';
    });
  }

  @override
  void dispose() {
    for (final c in [_solutionText, _source, _testTotal, _avgSeconds, _note, _questionNo]) {
      c.dispose();
    }
    // Kaydedilmeden çıkıldıysa geçici dosyaları temizle (kaydedilenler zaten kalıcı depoda).
    for (final path in [...?_question?.tempFiles, ...?_solution?.tempFiles]) {
      unawaited(_media.discardTemp(path));
    }
    super.dispose();
  }

  /// Yuvada gösterilecek dosya: yeni çekim varsa o, yoksa kayıtlı fotoğraf.
  String? _displayPath({required bool solution}) {
    final fresh = solution ? _solution : _question;
    if (fresh != null) return fresh.path;
    final stored = solution ? _original?.solutionImage : _original?.questionImage;
    final cleared = solution ? _clearStoredSolution : _clearStoredQuestion;
    if (stored == null || cleared) return null;
    return _media.resolve(stored).path;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (_editing && _original == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Soru bulunamadı.')));
    }

    final theme = Theme.of(context);
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final subjects = allSubjectKeys(extra: [
      for (final n in curriculum) n.subjectLabel,
      for (final b in books) subjectKey(b.examType, b.subject),
      if (_subject != null) _subject!,
    ]);
    final topics = _subject == null
        ? const <CurriculumNode>[]
        : depthFirst(curriculum.where((n) => n.subjectLabel == _subject));
    final contextLine = [
      if (_testLabel != null) _testLabel!,
      if (_questionNo.text.trim().isNotEmpty) '${_questionNo.text.trim()}. soru',
    ].join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Soruyu tamamla' : 'Soru ekle'),
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
          if (contextLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(contextLine, style: theme.textTheme.titleSmall)),
                ],
              ),
            ),
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
                  path: _displayPath(solution: false),
                  canCrop: _question != null,
                  busy: _pickingQuestion,
                  onPick: () => _pickPhoto(solution: false),
                  onCrop: () => _recrop(solution: false),
                  onClear: () => _clearPhoto(solution: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PhotoSlot(
                  label: 'Doğru çözüm',
                  path: _displayPath(solution: true),
                  canCrop: _solution != null,
                  busy: _pickingSolution,
                  onPick: () => _pickPhoto(solution: true),
                  onCrop: () => _recrop(solution: true),
                  onClear: () => _clearPhoto(solution: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _solutionText,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Çözüm notu (isteğe bağlı)',
              helperText: 'Fotoğraf ya da not: biri yeterli. İkisi de yoksa soru Eksikler\'de bekler.',
              helperMaxLines: 2,
            ),
          ),
          if (_status != QuestionStatus.correct) ...[
            _SectionTitle(_status == QuestionStatus.blank ? 'Neden boş bıraktın?' : 'Neden yanlış yaptın?'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in MistakeReason.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _reason == r,
                    onSelected: (on) => setState(() => _reason = on ? r : null),
                  ),
              ],
            ),
          ],
          const _SectionTitle('Ders ve konu'),
          DropdownMenu<String>(
            key: ValueKey('subject-$_subject'),
            initialSelection: _subject,
            expandedInsets: EdgeInsets.zero,
            menuHeight: 360,
            label: const Text('Ders'),
            errorText: _issues.contains(DraftIssue.missingSubject) ? DraftIssue.missingSubject.message : null,
            dropdownMenuEntries: [for (final s in subjects) DropdownMenuEntry(value: s, label: s)],
            onSelected: (s) => setState(() {
              if (s != _subject) _mebNodeId = null;
              _subject = s;
              _issues = {..._issues}..remove(DraftIssue.missingSubject);
            }),
          ),
          const SizedBox(height: 12),
          if (topics.isNotEmpty)
            DropdownMenu<String>(
              key: ValueKey('topic-$_subject'),
              initialSelection: _mebNodeId,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 360,
              label: const Text('Konu'),
              helperText: 'Yazarak ara',
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
            )
          else
            Text(
              _subject == null
                  ? 'Konu seçmek için önce dersi seç.'
                  : 'Bu ders için konu listesi henüz yok; analizde nedenlere göre gruplanır.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const _SectionTitle('Kaynak'),
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
              dropdownMenuEntries: [for (final b in books) DropdownMenuEntry(value: b.id, label: b.title)],
              onSelected: (id) => _selectBook(books.where((b) => b.id == id).firstOrNull),
            )
          else
            TextField(
              controller: _source,
              decoration: InputDecoration(
                labelText: _origin == QuestionOrigin.mockExam ? 'Deneme adı' : 'Kaynak',
                hintText: _origin == QuestionOrigin.mockExam ? 'Örn. 3D TYT Deneme 4' : 'Örn. Telegram, hoca föyü',
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _questionNo,
                  label: 'Soru no',
                  errorText: _issues.contains(DraftIssue.invalidQuestionNo) ? 'En az 1' : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _NumberField(controller: _testTotal, label: 'Testteki soru sayısı')),
            ],
          ),
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('Diğer ayrıntılar', style: theme.textTheme.titleSmall),
              subtitle: Text('Süre, zorluk ve not', style: theme.textTheme.bodySmall),
              children: [
                _NumberField(controller: _avgSeconds, label: 'Soru başına süre', suffix: 'sn'),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Zorluk: $_difficulty / 10', style: theme.textTheme.titleSmall),
                ),
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
              ],
            ),
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
              if (!_editing) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    child: const Text('Kaydet, yenisini ekle'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
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
    final source = await askPhotoSource(context);
    if (source == null || !mounted) return;
    await _runPhotoOp(
      solution,
      () => capturePhoto(context, _capture, source, title: _cropTitle(solution)),
    );
  }

  /// Her zaman orijinalden kırpar: fazla ya da eksik kırptıysan geri dönüp
  /// düzeltebilirsin, netlik kaybolmaz.
  Future<void> _recrop({required bool solution}) async {
    final current = solution ? _solution : _question;
    if (current == null) return;
    await _runPhotoOp(
      solution,
      () => recropPhoto(context, _capture, current, title: _cropTitle(solution)),
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
        for (final path in next.tempFiles) {
          unawaited(_media.discardTemp(path));
        }
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
    });
  }

  /// Yeni çekim varsa onu bırakır (kayıtlı fotoğraf geri görünür); yoksa
  /// kayıtlı fotoğrafı kaldırılacak olarak işaretler.
  void _clearPhoto({required bool solution}) {
    final fresh = solution ? _solution : _question;
    if (fresh != null) {
      _replacePhoto(solution: solution, next: null);
      return;
    }
    setState(() {
      if (solution) {
        _clearStoredSolution = true;
      } else {
        _clearStoredQuestion = true;
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
      sessionItemId: _sessionItemId,
      mockExamId: _mockExamId,
      subject: _subject,
      mebNodeId: _mebNodeId,
      testLabel: _testLabel,
      questionNo: int.tryParse(_questionNo.text.trim()),
      testTotalQuestions: int.tryParse(_testTotal.text.trim()),
      avgSecondsPerQuestion: double.tryParse(_avgSeconds.text.trim()),
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
      final original = _original;
      final QuestionCard saved;
      if (original != null) {
        saved = await ref.read(updateQuestionCardProvider).call(
              original,
              draft,
              clearQuestionImage: _clearStoredQuestion,
              clearSolutionImage: _clearStoredSolution,
            );
      } else {
        saved = await ref.read(saveQuestionCardProvider).call(draft);
      }
      if (!mounted) return;
      final missing = saved.missingParts(topicAvailable: false);
      final hint = missing.isEmpty ? '' : ' Eksik: ${missing.map((m) => lowerTr(m.label)).join(', ')}.';
      if (addAnother) {
        // Kaynak, ders, konu ve süre aynı kalır: aynı testten art arda hızlı giriş.
        _replacePhoto(solution: false, next: null);
        _replacePhoto(solution: true, next: null);
        setState(() {
          _solutionText.clear();
          _note.clear();
          _questionNo.clear();
          _reason = null;
          _starred = false;
          _difficulty = 5;
        });
        messenger.showSnackBar(SnackBar(content: Text('Soru kaydedildi.$hint Sıradakini ekleyebilirsin.')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Soru kaydedildi.$hint')));
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
  const _NumberField({required this.controller, required this.label, this.suffix, this.errorText, this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        decoration: InputDecoration(labelText: label, suffixText: suffix, errorText: errorText),
      );
}
