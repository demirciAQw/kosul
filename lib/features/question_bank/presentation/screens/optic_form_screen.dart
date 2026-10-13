import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/question_card.dart';
import '../widgets/question_tile.dart' show statusColor;

/// Optik formun bir bölümü: genelde kitaptaki tek bir test.
/// Numaralar her bölümde 1'den başlar ("6. test, 5. soru"; 105. soru değil).
class OpticSection {
  const OpticSection({
    required this.key,
    required this.title,
    required this.total,
    this.initialMarks = const {},
    this.initiallyIncluded = true,
  });

  final String key; // test düğümü kimliği ya da "single"
  final String title;
  final int total;
  final Map<int, QuestionStatus> initialMarks;
  final bool initiallyIncluded;
}

class OpticSectionResult {
  const OpticSectionResult({
    required this.key,
    required this.included,
    required this.total,
    required this.marks,
  });

  final String key;

  /// false = "bu testi çözmedim": sayılara katılmaz, kayıtlara dokunulmaz.
  final bool included;
  final int total;
  final Map<int, QuestionStatus> marks; // yalnızca yanlış ve boşlar

  int get wrong => marks.values.where((s) => s == QuestionStatus.wrong).length;
  int get blank => marks.values.where((s) => s == QuestionStatus.blank).length;
  int get correct => total - wrong - blank;
}

/// Optik formun sonucu. İşaretsiz numaralar doğru sayılır.
class OpticFormResult {
  const OpticFormResult(this.sections);

  /// Tek bölümlü form (kitapsız blok, deneme dersi).
  factory OpticFormResult.single({required int total, required Map<int, QuestionStatus> marks}) =>
      OpticFormResult([OpticSectionResult(key: 'single', included: true, total: total, marks: marks)]);

  final List<OpticSectionResult> sections;

  Iterable<OpticSectionResult> get _included => sections.where((s) => s.included);
  int get total => _included.fold(0, (a, s) => a + s.total);
  int get wrong => _included.fold(0, (a, s) => a + s.wrong);
  int get blank => _included.fold(0, (a, s) => a + s.blank);
  int get correct => total - wrong - blank;

  /// İlk bölümün işaretleri (tek bölümlü formlar için kısayol).
  Map<int, QuestionStatus> get marks => sections.first.marks;

  /// YKS neti: 4 yanlış 1 doğruyu götürür.
  double get net => correct - wrong / 4;
}

class _SectionState {
  _SectionState(OpticSection s)
      : key = s.key,
        title = s.title,
        total = s.total < 1 ? 1 : s.total,
        included = s.initiallyIncluded,
        marks = {
          for (final e in s.initialMarks.entries)
            if (e.value != QuestionStatus.correct && e.key >= 1) e.key: e.value,
        };

  final String key;
  final String title;
  int total;
  bool included;
  final Map<int, QuestionStatus> marks;

  OpticSectionResult toResult() => OpticSectionResult(
        key: key,
        included: included,
        total: total,
        marks: {
          for (final e in marks.entries)
            if (e.key <= total) e.key: e.value,
        },
      );
}

/// Optik form: yanlış ve boşlara dokun; doğru, yanlış, boş ve net kendiliğinden.
class OpticFormScreen extends StatefulWidget {
  const OpticFormScreen({
    super.key,
    required this.title,
    required this.sections,
    this.subtitle,
    this.totalEditable = true,
    this.showNet = false,
  });

  final String title;
  final String? subtitle;
  final List<OpticSection> sections;

  /// Yalnızca tek bölümlü formda soru sayısı değiştirilebilir.
  final bool totalEditable;
  final bool showNet;

  static const maxTotal = 200;

  /// Vazgeçilirse null.
  static Future<OpticFormResult?> open(
    BuildContext context, {
    required String title,
    required List<OpticSection> sections,
    String? subtitle,
    bool totalEditable = true,
    bool showNet = false,
  }) =>
      Navigator.of(context, rootNavigator: true).push<OpticFormResult>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OpticFormScreen(
          title: title,
          subtitle: subtitle,
          sections: sections,
          totalEditable: totalEditable,
          showNet: showNet,
        ),
      ));

  @override
  State<OpticFormScreen> createState() => _OpticFormScreenState();
}

class _OpticFormScreenState extends State<OpticFormScreen> {
  late final List<_SectionState> _sections = [for (final s in widget.sections) _SectionState(s)];

  /// Dokununca uygulanacak işaret. Uzun basış diğerini koyar.
  QuestionStatus _mode = QuestionStatus.wrong;
  bool _dirty = false;

  bool get _multi => _sections.length > 1;

  OpticFormResult get _result => OpticFormResult([for (final s in _sections) s.toResult()]);

  void _tap(_SectionState section, int number, {bool alternate = false}) {
    final target = alternate
        ? (_mode == QuestionStatus.wrong ? QuestionStatus.blank : QuestionStatus.wrong)
        : _mode;
    setState(() {
      _dirty = true;
      if (section.marks[number] == target) {
        section.marks.remove(number);
      } else {
        section.marks[number] = target;
      }
    });
  }

  void _setTotal(int value) => setState(() {
        _dirty = true;
        _sections.first.total = value.clamp(1, OpticFormScreen.maxTotal).toInt();
      });

  Future<void> _editTotal() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _TotalDialog(initial: _sections.first.total),
    );
    if (value != null && value > 0) _setTotal(value);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('İşaretler kaydedilmesin mi?'),
        content: const Text('Bu ekranda yaptığın değişiklikler kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Geri dön')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Kaydetmeden çık')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: _sections.every((s) => s.marks.isEmpty)
                  ? null
                  : () => setState(() {
                        _dirty = true;
                        for (final s in _sections) {
                          s.marks.clear();
                        }
                      }),
              child: const Text('Temizle'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            if (!_multi)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
                child: Row(
                  children: [
                    if (widget.totalEditable) ...[
                      IconButton(
                        tooltip: 'Bir azalt',
                        onPressed: _sections.first.total > 1 ? () => _setTotal(_sections.first.total - 1) : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _editTotal,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text('${_sections.first.total} soru', style: theme.textTheme.titleMedium),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Bir artır',
                        onPressed: _sections.first.total < OpticFormScreen.maxTotal
                            ? () => _setTotal(_sections.first.total + 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('${_sections.first.total} soru', style: theme.textTheme.titleMedium),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<QuestionStatus>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: QuestionStatus.wrong,
                      label: Text('Dokununca: yanlış'),
                      icon: Icon(Icons.close_rounded),
                    ),
                    ButtonSegment(
                      value: QuestionStatus.blank,
                      label: Text('Dokununca: boş'),
                      icon: Icon(Icons.remove_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Text(
                _multi
                    ? 'Her test kendi numarasıyla başlar. Çözmediğin testi kapat; sayılara katılmaz.'
                    : 'Yanlış ya da boş bıraktığın numaralara dokun; işaretsizler doğru sayılır. '
                        'Uzun basınca öteki işaret konur.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  for (final section in _sections) ...[
                    if (_multi)
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          section: section,
                          onToggle: (on) => setState(() {
                            _dirty = true;
                            section.included = on;
                          }),
                        ),
                      ),
                    if (section.included)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        sliver: SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 64,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: section.total,
                          itemBuilder: (context, i) {
                            final number = i + 1;
                            return _Bubble(
                              number: number,
                              status: section.marks[number],
                              onTap: () => _tap(section, number),
                              onLongPress: () => _tap(section, number, alternate: true),
                            );
                          },
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
            Material(
              color: scheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      _Count(value: '${result.correct}', label: 'doğru', color: statusColor(QuestionStatus.correct)),
                      _Count(value: '${result.wrong}', label: 'yanlış', color: statusColor(QuestionStatus.wrong)),
                      _Count(value: '${result.blank}', label: 'boş', color: statusColor(QuestionStatus.blank)),
                      if (widget.showNet) _Count(value: formatNet(result.net), label: 'net', color: scheme.primary),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(result),
                        child: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.onToggle});
  final _SectionState section;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = section.toResult();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: section.included ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.title, style: theme.textTheme.titleSmall),
                Text(
                  section.included
                      ? '${section.total} soru, ${r.correct} D, ${r.wrong} Y, ${r.blank} B'
                      : 'Çözülmedi; sayılara katılmıyor',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text('Çözdüm', style: theme.textTheme.labelMedium),
          Switch(value: section.included, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _TotalDialog extends StatefulWidget {
  const _TotalDialog({required this.initial});
  final int initial;

  @override
  State<_TotalDialog> createState() => _TotalDialogState();
}

class _TotalDialogState extends State<_TotalDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Testteki soru sayısı'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'Örn. 16'),
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v.trim())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, int.tryParse(_controller.text.trim())),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.number, required this.status, required this.onTap, required this.onLongPress});

  final int number;
  final QuestionStatus? status;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marked = status;
    final fill = marked == null ? Colors.transparent : statusColor(marked);
    final ink = marked == null ? scheme.onSurface : Colors.white;
    return Semantics(
      button: true,
      label: '$number. soru, ${marked?.label ?? 'doğru'}',
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: BorderSide(color: marked == null ? scheme.outline : fill, width: 1.5),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$number', style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 15)),
              if (marked != null)
                Icon(
                  marked == QuestionStatus.wrong ? Icons.close_rounded : Icons.remove_rounded,
                  size: 12,
                  color: ink,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
