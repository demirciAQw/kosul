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
import '../../../library/domain/progress.dart';
import '../../../library/library_providers.dart';
import '../../../library/presentation/library_sheet.dart';
import '../../../library/presentation/test_picker_sheet.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../question_prefill.dart';
import '../widgets/photo_slot.dart';
import '../../../../app/palette.dart';
import '../../../study_session/study_session_providers.dart';
import '../../../study_session/presentation/session_quick_mark.dart';
import '../../../study_session/domain/study_session.dart';

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
  final _reasonNote = TextEditingController();

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

  /// Şıklar: doğru cevap ve öğrencinin işaretlediği ("A"–"E").
  String? _correctAnswer;
  String? _givenAnswer;

  /// Açık uçlu soru: cevaplar şık yerine yazıyla girilir.
  bool _written = false;
  final _correctText = TextEditingController();
  final _givenText = TextEditingController();
  bool _answerError = false;
  int _difficulty = 5;
  bool _starred = false;
  bool _saving = false;
  bool _pickingQuestion = false;
  bool _pickingSolution = false;
  Set<DraftIssue> _issues = const {};

  bool get _editing => widget.editCardId != null;

  /// Kaynak kullanıcı ya da bağlam tarafından belirlendi mi? Belirlenmediyse
  /// kitap listesi (geç de olsa) yüklenince "Kitap" varsayılır.
  bool _originDecided = false;

  /// Son oturumdan kendiliğinden dolduruldu (bilgi şeridi için).
  String? _recentLabel;
  bool get _bookMode => _origin == QuestionOrigin.book;

  /// Kitaptan eklenen sorunun testi "çözüldü" olarak işaretlensin mi?
  bool _markSolved = true;

  /// Kaydedilmemiş emek var mı? (Çıkarken onay sormak için.)
  bool get _dirty =>
      _question != null ||
      _solution != null ||
      (!_editing &&
          (_solutionText.text.trim().isNotEmpty ||
              _note.text.trim().isNotEmpty ||
              _reasonNote.text.trim().isNotEmpty ||
              _reason != null ||
              _correctAnswer != null ||
              _givenAnswer != null ||
              _correctText.text.trim().isNotEmpty ||
              _givenText.text.trim().isNotEmpty));

  @override
  void initState() {
    super.initState();
    _media = ref.read(mediaStorageProvider);
    _capture = ref.read(photoCaptureProvider);
    if (_editing) {
      _loading = true;
      unawaited(_loadCard(widget.editCardId!));
    } else if (widget.prefill != null) {
      _originDecided = true;
      _applyPrefill(widget.prefill);
    } else {
      // Kitabı olan biri için en sık yol: kitaptan, test ve soru no ile.
      final hasBooks = ref.read(libraryProvider).value?.isNotEmpty ?? false;
      _origin = hasBooks ? QuestionOrigin.book : QuestionOrigin.independent;
      _originDecided = hasBooks;
      unawaited(_fillFromRecentSession());
    }
  }

  /// Süren ya da son 3 saatte biten oturumun kitap bloğunu getirir: oturum
  /// bitince Defter'den eklenen soru da o kitaba ve teste bağlanır.
  Future<void> _fillFromRecentSession() async {
    final repo = ref.read(studySessionRepositoryProvider);
    final running = await repo.watchRunning().first;
    final history = running != null ? const <StudySession>[] : await repo.watchHistory(limit: 1).first;
    final session = running ?? history.firstOrNull;
    if (session == null || !mounted) return;
    final end = session.endedAt ?? DateTime.now();
    if (DateTime.now().difference(end).inHours >= 3) return;
    final item = session.items.where((i) => i.hasQuestions && i.bookId != null).firstOrNull;
    if (item == null || _bookId != null) return; // kullanıcı kendisi seçmişse dokunma
    final prefill = sessionItemPrefill(ref, session, item);
    setState(() {
      _originDecided = true;
      _applyPrefill(prefill);
      _recentLabel = prefill.testLabel ?? prefill.sourceName;
    });
  }

  void _clearRecent() => setState(() {
        _recentLabel = null;
        _bookId = null;
        _contentNodeId = null;
        _testLabel = null;
        _sessionId = null;
        _sessionItemId = null;
        _source.clear();
      });

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
      _reasonNote.text = card.reasonNote ?? '';
      _written = card.hasWrittenAnswer;
      if (_written) {
        _correctText.text = card.correctAnswer ?? '';
        _givenText.text = card.givenAnswer ?? '';
      } else {
        _correctAnswer = card.correctAnswer;
        _givenAnswer = card.givenAnswer;
      }
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
    for (final c in [_solutionText, _source, _testTotal, _avgSeconds, _note, _questionNo, _reasonNote, _correctText, _givenText]) {
      c.dispose();
    }
    // Kaydedilmeden çıkıldıysa geçici dosyaları temizle (kaydedilenler zaten kalıcı depoda).
    // Kaydedilmeden çıkıldıysa geçici dosyalar silinir; sıkıştırma sürüyorsa bitince.
    for (final photo in [_question, _solution].whereType<CapturedPhoto>()) {
      unawaited(_media.discardTemp(photo.originalPath));
      unawaited(photo.ready.then((_) => _media.discardTemp(photo.path), onError: (_) {}));
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
    if (!_originDecided && !_editing && books.isNotEmpty) {
      _origin = QuestionOrigin.book;
      _originDecided = true;
    }
    final book = books.where((b) => b.id == _bookId).firstOrNull;
    final test = book == null ? null : findNode(book, _contentNodeId);
    final results = ref.watch(testResultsProvider).value ?? const <String, TestResult>{};
    final testSolved = test != null && results.containsKey(test.id);
    final contextLine = [
      if (_testLabel != null && !_bookMode) _testLabel!,
      if (_questionNo.text.trim().isNotEmpty) '${_questionNo.text.trim()}. soru',
    ].join(', ');

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (await _confirmDiscard()) router.canPop() ? router.pop() : router.go(AppRoutes.home);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Soruyu düzenle' : 'Soru ekle'),
        leading: IconButton(tooltip: 'Vazgeç', icon: const Icon(Icons.close_rounded), onPressed: _cancel),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Soruyu sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: _starred ? 'Güzel Sorular klasöründen çıkar' : 'Güzel Sorular klasörüne ekle',
            onPressed: () => setState(() => _starred = !_starred),
            icon: Icon(
              _starred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _starred ? KocumColors.star : null,
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
            onSelectionChanged: (s) => setState(() {
              _status = s.first;
              _answerError = false;
            }),
          ),
          const _SectionTitle('Cevaplar'),
          SegmentedButton<bool>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Şıklı'), icon: Icon(Icons.radio_button_checked_rounded)),
              ButtonSegment(value: true, label: Text('Yazılı'), icon: Icon(Icons.edit_note_rounded)),
            ],
            selected: {_written},
            onSelectionChanged: (v) => setState(() {
              _written = v.first;
              _answerError = false;
            }),
          ),
          const SizedBox(height: 10),
          if (_written) ...[
            TextField(
              controller: _correctText,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _answerError = false),
              decoration: InputDecoration(
                labelText: _status == QuestionStatus.blank ? 'Doğru cevap (isteğe bağlı)' : 'Doğru cevap',
                hintText: 'Örn. x = 3 ya da kısa açıklama',
                errorText: _answerError && _status != QuestionStatus.blank && _correctText.text.trim().isEmpty
                    ? 'Doğru cevabı yaz'
                    : null,
              ),
            ),
            if (_status == QuestionStatus.wrong)
              TextField(
                controller: _givenText,
                minLines: 1,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _answerError = false),
                decoration: InputDecoration(
                  labelText: 'Senin cevabın',
                  errorText: _answerError && _givenText.text.trim().isEmpty ? 'Kendi cevabını yaz' : null,
                ),
              ),
          ] else ...[
          _AnswerPicker(
            label: _status == QuestionStatus.blank ? 'Doğru cevap (isteğe bağlı)' : 'Doğru cevap',
            value: _correctAnswer,
            error: _answerError && _status != QuestionStatus.blank && _correctAnswer == null,
            onChanged: (v) => setState(() {
              _correctAnswer = v;
              _answerError = false;
            }),
          ),
          if (_status == QuestionStatus.wrong) ...[
            const SizedBox(height: 8),
            _AnswerPicker(
              label: 'Senin cevabın',
              value: _givenAnswer,
              disabled: _correctAnswer,
              error: _answerError && (_givenAnswer == null || _givenAnswer == _correctAnswer),
              onChanged: (v) => setState(() {
                _givenAnswer = v;
                _answerError = false;
              }),
            ),
          ],
          ],
          if (_answerError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _answerProblem() ?? '',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const _SectionTitle('Kaynak'),
          SegmentedButton<QuestionOrigin>(
            showSelectedIcon: false,
            segments: [for (final o in QuestionOrigin.values) ButtonSegment(value: o, label: Text(o.label))],
            selected: {_origin},
            onSelectionChanged: (s) => setState(() {
              final wasBook = _bookMode;
              _origin = s.first;
              _originDecided = true;
              if (wasBook && !_bookMode && _contentNodeId != null) {
                // Kitaptan çıkınca testin bilgileri yanıltmasın.
                _contentNodeId = null;
                _testLabel = null;
              }
            }),
          ),
          if (_bookMode && _recentLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.history_rounded, color: theme.colorScheme.onPrimaryContainer),
                  title: Text('Son oturumdan: $_recentLabel',
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                  trailing: TextButton(onPressed: _clearRecent, child: const Text('Temizle')),
                ),
              ),
            ),
          if (_bookMode) ...[
            const SizedBox(height: 12),
            if (books.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.library_add_outlined),
                  title: const Text('Henüz kitap yok'),
                  subtitle: const Text('Kitap ekleyince soruyu yalnızca test ve soru no ile eklersin.'),
                  trailing: TextButton(onPressed: () => showLibrarySheet(context), child: const Text('Kitap ekle')),
                ),
              )
            else ...[
              DropdownMenu<String>(
                key: ValueKey('book-$_bookId'),
                initialSelection: _bookId,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Kitap'),
                dropdownMenuEntries: [for (final b in books) DropdownMenuEntry(value: b.id, label: b.title)],
                onSelected: (id) => _selectBook(books.where((b) => b.id == id).firstOrNull),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: book == null ? null : () => _pickTest(book),
                      icon: const Icon(Icons.format_list_numbered_rounded),
                      label: Text(
                        test?.title ?? 'Test seç',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _NumberField(
                      controller: _questionNo,
                      label: 'Soru no',
                      errorText: _issues.contains(DraftIssue.invalidQuestionNo) ? 'En az 1' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (book != null && test == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Testi seç: soru o teste ve konusuna bağlanır, test kitap haritasında işaretlenir.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              if (book != null && test != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    [
                      nodeLabel(book, test.id),
                      if (test.questionCount != null) '${test.questionCount} soru',
                      if (testSolved) 'çözüldü',
                    ].join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (!testSolved && !_editing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _markSolved,
                    onChanged: (v) => setState(() => _markSolved = v ?? false),
                    title: const Text('Bu testi çözüldü olarak işaretle'),
                  ),
              ],
            ],
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PhotoSlot(
                  label: 'Soru',
                  path: _displayPath(solution: false),
                  ready: _question?.ready,
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
                  ready: _solution?.ready,
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
            if (_reason == MistakeReason.other)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _reasonNote,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nedenini kendi cümlenle yaz',
                    hintText: 'Örn. Şekli yanlış çizdim',
                  ),
                ),
              ),
          ],
          if (!_bookMode) ...[
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
          const SizedBox(height: 12),
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
          ],
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
    ),
    );
  }

  void _selectBook(Book? book) {
    if (book == null) return;
    setState(() {
      final subject = subjectKey(book.examType, book.subject);
      if (subject != _subject) _mebNodeId = null;
      if (book.id != _bookId) {
        _contentNodeId = null;
        _testLabel = null;
      }
      _bookId = book.id;
      _source.text = book.title;
      _subject = subject;
    });
  }

  /// Test bilinince konu da bilinir: ders, konu ve test adı testten gelir.
  Future<void> _pickTest(Book book) async {
    final test = await pickBookTest(context, book);
    if (test == null || !mounted) return;
    setState(() {
      _contentNodeId = test.id;
      _mebNodeId = effectiveMeb(book, test.id);
      _testLabel = nodeLabel(book, test.id);
      _subject = subjectKey(book.examType, book.subject);
      if (test.questionCount != null) _testTotal.text = '${test.questionCount}';
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kaydetmeden çıkılsın mı?'),
        content: const Text('Çektiğin fotoğraflar ve yazdıkların kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Geri dön')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Çık')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancel() async {
    final router = GoRouter.of(context);
    if (!await _confirmDiscard()) return;
    router.canPop() ? router.pop() : router.go(AppRoutes.home);
  }

  Future<void> _delete() async {
    final original = _original;
    if (original == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Soruyu sil?'),
        content: const Text('Soru, fotoğrafları ve tekrar geçmişi silinir. Bu geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(deleteQuestionCardProvider).call(original.id);
    messenger.showSnackBar(const SnackBar(content: Text('Soru silindi.')));
    // Düzenleme ekranı ve altındaki soru ayrıntısı birlikte kapanır.
    router.go(AppRoutes.notebook);
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
      // Sıkıştırma sürüyorsa bitince sil (yarım dosya kalmasın).
      unawaited(old.ready.then((_) => _media.discardTemp(old.path), onError: (_) {}));
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
      reasonNote: _reasonNote.text,
      correctAnswer: _written ? _correctText.text : _correctAnswer,
      givenAnswer: _status == QuestionStatus.wrong ? (_written ? _givenText.text : _givenAnswer) : null,
      writtenAnswer: _written,
      difficulty: _difficulty,
      isStarred: _starred,
      note: _note.text,
    );
  }

  /// Boş değilse şıklar zorunlu: yanlışta ikisi de (ve farklı), doğruda doğru şık.
  String? _answerProblem() {
    if (_written) {
      String norm(String s) => lowerTr(s.trim()).replaceAll(RegExp(r'\s+'), ' ');
      final c = _correctText.text.trim(), g = _givenText.text.trim();
      switch (_status) {
        case QuestionStatus.blank:
          return null;
        case QuestionStatus.correct:
          return c.isEmpty ? 'Doğru cevabı yaz.' : null;
        case QuestionStatus.wrong:
          if (c.isEmpty || g.isEmpty) return 'Doğru cevabı ve senin cevabını yaz.';
          if (norm(c) == norm(g)) return 'Yanlış soruda iki cevap aynı olamaz.';
          return null;
      }
    }
    switch (_status) {
      case QuestionStatus.blank:
        return null;
      case QuestionStatus.correct:
        return _correctAnswer == null ? 'Doğru cevabı seç.' : null;
      case QuestionStatus.wrong:
        if (_correctAnswer == null || _givenAnswer == null) return 'Doğru cevabı ve senin cevabını seç.';
        if (_correctAnswer == _givenAnswer) return 'Yanlış soruda iki şık aynı olamaz.';
        return null;
    }
  }

  Future<void> _save({required bool addAnother}) async {
    final answerProblem = _answerProblem();
    if (answerProblem != null) {
      setState(() => _answerError = true);
      _snack(answerProblem);
      return;
    }
    if (_bookMode && _bookId == null && (ref.read(libraryProvider).value?.isNotEmpty ?? false)) {
      _snack('Önce kitabı seç.');
      return;
    }
    // Fotoğraflar arka planda sıkıştırılıyor olabilir: kaydetmeden önce bitsin.
    try {
      await Future.wait([if (_question != null) _question!.ready, if (_solution != null) _solution!.ready]);
    } on Exception {
      _snack('Fotoğraf hazırlanamadı; yeniden çekmeyi dene.');
      return;
    }
    if (!mounted) return;
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
      // Kitaptan eklenen sorunun testi kitap haritasında "çözüldü" olur.
      final bookId = _bookId;
      final nodeId = _contentNodeId;
      if (_bookMode && _markSolved && bookId != null && nodeId != null) {
        await ref.read(testProgressRepositoryProvider).saveIfAbsent([
          TestResult(nodeId: nodeId, bookId: bookId, solvedAt: saved.createdAt, sessionId: _sessionId),
        ]);
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
          _reasonNote.clear();
          _reason = null;
          _correctAnswer = null;
          _givenAnswer = null;
          _correctText.clear();
          _givenText.clear();
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

/// A–E şık seçici. Seçili şıkka yeniden dokunmak seçimi kaldırır.
class _AnswerPicker extends StatelessWidget {
  const _AnswerPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled,
    this.error = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Bu şık seçilemez (yanlış soruda doğru cevapla aynı şık).
  final String? disabled;
  final bool error;

  static const letters = ['A', 'B', 'C', 'D', 'E'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: error ? scheme.error : scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in letters)
                ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  label: SizedBox(width: 18, child: Text(l, textAlign: TextAlign.center)),
                  selected: value == l,
                  side: error && value == null ? BorderSide(color: scheme.error) : null,
                  onSelected: l == disabled ? null : (on) => onChanged(on ? l : null),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
