import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/yks.dart';
import '../domain/mock_exam.dart';
import '../mock_exam_providers.dart';

/// Deneme ekleme / düzenleme: ders ders doğru ve yanlış; boş ve net kendiliğinden.
class EditMockExamScreen extends ConsumerStatefulWidget {
  const EditMockExamScreen({super.key, this.examId});
  final String? examId;

  @override
  ConsumerState<EditMockExamScreen> createState() => _EditMockExamScreenState();
}

class _SectionRow {
  _SectionRow(this.subject, this.questionCount, {int? correct, int? wrong})
      : correct = TextEditingController(text: correct == null || correct == 0 ? '' : '$correct'),
        wrong = TextEditingController(text: wrong == null || wrong == 0 ? '' : '$wrong');

  final String subject;
  final int questionCount;
  final TextEditingController correct;
  final TextEditingController wrong;

  int get c => int.tryParse(correct.text.trim()) ?? 0;
  int get w => int.tryParse(wrong.text.trim()) ?? 0;
  int get b => questionCount - c - w;
  bool get overflow => b < 0;
  double get net => netOf(c, w);

  void dispose() {
    correct.dispose();
    wrong.dispose();
  }
}

class _EditMockExamScreenState extends ConsumerState<EditMockExamScreen> {
  final _title = TextEditingController();
  final _duration = TextEditingController();
  final _note = TextEditingController();
  final _branchCount = TextEditingController(text: '20');

  late DateTime _date;
  MockKind _kind = MockKind.tyt;
  String _aytField = 'Sayısal';
  String? _branchSubject;
  List<_SectionRow> _rows = [];
  bool _loading = false;
  bool _saving = false;

  bool get _editing => widget.examId != null;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _date = DateTime(now.year, now.month, now.day);
    if (_editing) {
      _loading = true;
      _load(widget.examId!);
    } else {
      _kind = ref.read(mockKindFilterProvider);
      _applyPreset();
    }
  }

  Future<void> _load(String id) async {
    final exam = await ref.read(mockExamRepositoryProvider).findById(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (exam == null) return;
      _title.text = exam.title;
      _date = exam.takenOn;
      _kind = exam.kind;
      if (exam.durationMinutes != null) _duration.text = '${exam.durationMinutes}';
      _note.text = exam.note ?? '';
      if (exam.kind == MockKind.branch && exam.sections.isNotEmpty) {
        _branchSubject = exam.sections.first.subject;
        _branchCount.text = '${exam.sections.first.questionCount}';
      }
      _replaceRows([
        for (final s in exam.sections) _SectionRow(s.subject, s.questionCount, correct: s.correct, wrong: s.wrong),
      ]);
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _duration, _note, _branchCount]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _replaceRows(List<_SectionRow> next) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows = next;
  }

  /// Türe göre ders listesini kurar; aynı dersin girilmiş sayıları korunur.
  void _applyPreset() {
    final old = {for (final r in _rows) r.subject: r};
    final List<_SectionRow> next;
    if (_kind == MockKind.branch) {
      final subject = _branchSubject;
      final count = int.tryParse(_branchCount.text.trim()) ?? 0;
      next = subject == null || count < 1
          ? []
          : [_SectionRow(subject, count, correct: old[subject]?.c, wrong: old[subject]?.w)];
    } else {
      next = [
        for (final p in presetSections(_kind, aytField: _aytField))
          _SectionRow(p.subject, p.questionCount, correct: old[p.subject]?.c, wrong: old[p.subject]?.w),
      ];
    }
    _replaceRows(next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalNet = _rows.fold<double>(0, (sum, r) => sum + r.net);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Denemeyi düzenle' : 'Deneme ekle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<MockKind>(
            segments: [for (final k in MockKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _applyPreset();
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Deneme adı',
              hintText: 'Örn. 3D ${_kind == MockKind.branch ? 'Matematik' : _kind.label} Deneme 4',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(formatDate(_date)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: const InputDecoration(labelText: 'Süre', suffixText: 'dk'),
                ),
              ),
            ],
          ),
          if (_kind == MockKind.ayt) ...[
            const SizedBox(height: 16),
            Text('Alan', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final field in Yks.aytFields.keys)
                  ChoiceChip(
                    label: Text(field),
                    selected: _aytField == field,
                    onSelected: (_) => setState(() {
                      _aytField = field;
                      _applyPreset();
                    }),
                  ),
              ],
            ),
          ],
          if (_kind == MockKind.branch) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<String>(
                    key: ValueKey('branch-$_branchSubject'),
                    initialSelection: _branchSubject,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 360,
                    label: const Text('Ders'),
                    dropdownMenuEntries: [
                      for (final s in Yks.all) DropdownMenuEntry(value: s.key, label: s.key),
                    ],
                    onSelected: (s) => setState(() {
                      _branchSubject = s;
                      _applyPreset();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _branchCount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: const InputDecoration(labelText: 'Soru'),
                    onChanged: (_) => setState(_applyPreset),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Dersler', style: theme.textTheme.titleMedium)),
              Text('Toplam ${formatNet(totalNet)} net',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Doğru ve yanlışı yaz; boş ve net kendiliğinden hesaplanır. '
            'Yanlışları sonra optik formdan tek tek de işaretleyebilirsin.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Önce dersi ve soru sayısını seç.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final row in _rows) _RowEditor(row: row, onChanged: () => setState(() {})),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', hintText: 'Örn. Fen\'de süre yetmedi'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving || _rows.isEmpty ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Kaydet'),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      helpText: 'Deneme tarihi',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final overflow = _rows.where((r) => r.overflow).firstOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (overflow != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('${subjectName(overflow.subject)}: doğru ve yanlış toplamı '
            '${overflow.questionCount} soruyu geçiyor.'),
      ));
      return;
    }
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    final title = _title.text.trim();
    try {
      final exam = await ref.read(saveMockExamProvider).call(MockExamDraft(
            id: widget.examId,
            title: title.isEmpty ? '${_kind.label} denemesi, ${formatDayMonth(_date)}' : title,
            kind: _kind,
            takenOn: _date,
            durationMinutes: int.tryParse(_duration.text.trim()),
            note: _note.text,
            sections: [
              for (final r in _rows)
                MockSectionDraft(
                  subject: r.subject,
                  questionCount: r.questionCount,
                  correct: r.c,
                  wrong: r.w,
                  blank: r.b < 0 ? 0 : r.b,
                ),
            ],
          ));
      ref.read(mockKindFilterProvider.notifier).set(exam.kind);
      messenger.showSnackBar(SnackBar(content: Text('${exam.title} kaydedildi: ${formatNet(exam.net)} net.')));
      if (_editing) {
        router.pop();
      } else {
        await router.pushReplacement(AppRoutes.mockExam(exam.id));
      }
    } on MockExamException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Deneme kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RowEditor extends StatelessWidget {
  const _RowEditor({required this.row, required this.onChanged});
  final _SectionRow row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget field(TextEditingController c, String label) => SizedBox(
          width: 60,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) => onChanged(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subjectName(row.subject), style: theme.textTheme.bodyLarge),
                Text('${row.questionCount} soru',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          field(row.correct, 'D'),
          const SizedBox(width: 8),
          field(row.wrong, 'Y'),
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Text('B', style: theme.textTheme.labelSmall),
                Text(
                  row.overflow ? '!' : '${row.b}',
                  style: theme.textTheme.titleSmall?.copyWith(color: row.overflow ? scheme.error : null),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              formatNet(row.net),
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(color: row.overflow ? scheme.error : scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
