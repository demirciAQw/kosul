import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/media/media_storage.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../library/domain/library.dart';
import '../../library/library_providers.dart';
import '../domain/notes.dart';
import '../notes_providers.dart';
import 'notes_view.dart' show deleteNoteWithUndo;
import '../../question_bank/presentation/widgets/media_image.dart';
import '../../../core/media/photo_flow.dart';

/// Not yaz / düzenle. Tarih ve saat kendiliğinden; yalnızca ders ve metin istenir.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.initialSubject});

  final String? noteId;
  final String? initialSubject;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  StudyNote? _original;
  String? _subject;

  /// Notun tarihi: yeni notta açıldığı an, düzenlemede kaydedilmiş tarih.
  /// Dokunarak değiştirilebilir.
  late DateTime _noteAt;
  bool _loading = false;
  bool _saving = false;

  /// Sayfa fotoğrafları: kayıtlılar ve yeni çekilenler, sırayla.
  final _photos = <NotePhotoDraft>[];
  final _originals = <String>[]; // yeni çekimlerin kırpılmamış hâlleri (temizlik için)
  bool _capturing = false;

  /// dispose içinde ref kullanılamaz; medya deposu bir kez alınır.
  late final MediaStorage _media;

  bool get _editing => widget.noteId != null;

  bool get _dirty {
    final o = _original;
    if (o == null) return _body.text.trim().isNotEmpty || _title.text.trim().isNotEmpty || _photos.isNotEmpty;
    return _body.text.trim() != o.body ||
        _title.text.trim() != (o.title ?? '') ||
        _subject != o.subject ||
        _noteAt != o.createdAt ||
        _photos.length != o.photos.length ||
        _photos.any((p) => p.temp != null);
  }

  @override
  void initState() {
    super.initState();
    _media = ref.read(mediaStorageProvider);
    _noteAt = ref.read(clockProvider)();
    _subject = widget.initialSubject;
    if (_editing) {
      _loading = true;
      _load(widget.noteId!);
    }
  }

  Future<void> _load(String id) async {
    final note = await ref.read(noteRepositoryProvider).findById(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _original = note;
      if (note == null) return;
      _subject = note.subject;
      _noteAt = note.createdAt;
      _title.text = note.title ?? '';
      _body.text = note.body;
      _photos
        ..clear()
        ..addAll([for (final p in note.photos) NotePhotoDraft.stored(p)]);
    });
  }

  /// Defter sayfası çek ya da galeriden seç; uygulama içinde kırpılır.
  Future<void> _addPhoto() async {
    final source = await askPhotoSource(context);
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _capturing = true);
    try {
      final photo = await capturePhoto(context, ref.read(photoCaptureProvider), source, title: 'Sayfayı kırp');
      if (photo == null || !mounted) return;
      setState(() {
        _photos.add(NotePhotoDraft.fresh(photo.path));
        _originals.add(photo.originalPath);
      });
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fotoğraf eklenemedi: $e')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _removePhoto(int i) {
    final p = _photos.removeAt(i);
    final temp = p.temp;
    if (temp != null) unawaited(_media.discardTemp(temp));
    setState(() {});
  }

  void _openPhoto(NotePhotoDraft p) {
    final stored = p.stored;
    if (stored != null) {
      openImageZoom(context, stored);
      return;
    }
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.file(File(p.temp!)))),
      ),
    ));
  }

  @override
  void dispose() {
    for (final path in [..._originals, for (final p in _photos) if (p.temp != null) p.temp!]) {
      unawaited(_media.discardTemp(path));
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kaydetmeden çıkılsın mı?'),
        content: const Text('Yazdıkların kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Geri dön')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Çık')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _close() async {
    final router = GoRouter.of(context);
    if (await _confirmDiscard()) router.pop();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final note = await ref.read(saveNoteProvider).call(
            existing: _original,
            subject: _subject,
            title: _title.text,
            body: _body.text,
            at: _noteAt,
            photos: List.of(_photos),
          );
      ref.read(noteSubjectFilterProvider.notifier).set(note.subject);
      messenger.showSnackBar(SnackBar(content: Text('Not ${note.subject} defterine kaydedildi.')));
      router.pop();
    } on NoteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Tarih ve saati değiştir: önce gün, sonra saat. Vazgeçilirse eski değer kalır.
  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _noteAt,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      helpText: 'Not tarihi',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_noteAt),
      helpText: 'Not saati',
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_noteAt);
    setState(() => _noteAt = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  Future<void> _delete() async {
    final note = _original;
    if (note == null) return;
    final router = GoRouter.of(context);
    await deleteNoteWithUndo(context, ref, note);
    router.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_editing && _original == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not bulunamadı.')));
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final subjects = allSubjectKeys(extra: [
      for (final n in curriculum) n.subjectLabel,
      for (final b in books) subjectKey(b.examType, b.subject),
      if (_subject != null) _subject!,
    ]);
    final o = _original;
    final stamp = '${formatDate(_noteAt)}, ${formatClock(_noteAt)}';
    final lastEdit = o != null && o.wasEdited
        ? 'Son düzenleme: ${formatDate(o.updatedAt)}, ${formatClock(o.updatedAt)}'
        : null;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (await _confirmDiscard()) router.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Notu düzenle' : 'Yeni not'),
          leading: IconButton(tooltip: 'Vazgeç', icon: const Icon(Icons.close_rounded), onPressed: _close),
          actions: [
            if (_editing)
              IconButton(tooltip: 'Notu sil', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: 'Tarihi ve saati değiştir',
                child: InputChip(
                  avatar: Icon(Icons.schedule_rounded, size: 18, color: scheme.primary),
                  label: Text(stamp),
                  deleteIcon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  onDeleted: _pickDateTime,
                  deleteButtonTooltipMessage: 'Değiştir',
                  onPressed: _pickDateTime,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                lastEdit ?? 'Tarih ve saat kendiliğinden yazıldı; değiştirmek için dokun.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            DropdownMenu<String>(
              key: ValueKey('note-subject-$_subject'),
              initialSelection: _subject,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 360,
              label: const Text('Ders'),
              helperText: 'Not bu dersin defterine kaydedilir',
              dropdownMenuEntries: [for (final s in subjects) DropdownMenuEntry(value: s, label: s)],
              onSelected: (s) => setState(() => _subject = s),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Başlık (isteğe bağlı)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              autofocus: !_editing,
              minLines: 8,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Not',
                hintText: 'Örn. Türevde zincir kuralını unutma: içerinin türevi ile çarp.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Sayfa fotoğrafları', style: theme.textTheme.titleSmall)),
                Text(
                  _photos.isEmpty ? 'isteğe bağlı' : '${_photos.length} sayfa',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 132,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (i, p) in _photos.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _PhotoThumb(
                        photo: p,
                        number: i + 1,
                        onOpen: () => _openPhoto(p),
                        onRemove: () => _removePhoto(i),
                      ),
                    ),
                  _AddPhotoTile(busy: _capturing, onTap: _capturing ? null : _addPhoto),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'El yazısı defter sayfalarını ekle; asıl görüntü her zaman saklanır.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : _close, child: const Text('Vazgeç'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
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
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.number, required this.onOpen, required this.onRemove});
  final NotePhotoDraft photo;
  final int number;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stored = photo.stored;
    return SizedBox(
      width: 99,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: onOpen,
                child: stored != null
                    ? MediaImage(stored, cacheWidth: 300)
                    : Image.file(File(photo.temp!), fit: BoxFit.cover, cacheWidth: 300),
              ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              tooltip: 'Sayfayı çıkar',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 99,
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: busy
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_outlined, color: scheme.onPrimaryContainer),
                      const SizedBox(height: 6),
                      Text('Sayfa ekle', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
