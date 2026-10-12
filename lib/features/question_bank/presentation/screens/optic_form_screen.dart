import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/question_card.dart';
import '../widgets/question_tile.dart' show statusColor;

/// Optik formun sonucu. İşaretsiz numaralar doğru sayılır.
class OpticFormResult {
  const OpticFormResult({required this.total, required this.marks});

  final int total;
  final Map<int, QuestionStatus> marks; // yalnızca yanlış ve boşlar

  int get wrong => marks.values.where((s) => s == QuestionStatus.wrong).length;
  int get blank => marks.values.where((s) => s == QuestionStatus.blank).length;
  int get correct => total - wrong - blank;

  /// YKS neti: 4 yanlış 1 doğruyu götürür.
  double get net => correct - wrong / 4;
}

/// Optik form: testin soru numaralarına dokunarak yanlış ve boşları işaretle.
/// Doğru, yanlış ve boş sayıları kendiliğinden hesaplanır.
class OpticFormScreen extends StatefulWidget {
  const OpticFormScreen({
    super.key,
    required this.title,
    required this.initialTotal,
    this.subtitle,
    this.totalEditable = true,
    this.initialMarks = const {},
    this.showNet = false,
  });

  final String title;
  final String? subtitle;
  final int initialTotal;
  final bool totalEditable;
  final Map<int, QuestionStatus> initialMarks;
  final bool showNet;

  static const maxTotal = 200;

  /// Vazgeçilirse null.
  static Future<OpticFormResult?> open(
    BuildContext context, {
    required String title,
    required int initialTotal,
    String? subtitle,
    bool totalEditable = true,
    Map<int, QuestionStatus> initialMarks = const {},
    bool showNet = false,
  }) =>
      Navigator.of(context, rootNavigator: true).push<OpticFormResult>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OpticFormScreen(
          title: title,
          subtitle: subtitle,
          initialTotal: initialTotal,
          totalEditable: totalEditable,
          initialMarks: initialMarks,
          showNet: showNet,
        ),
      ));

  @override
  State<OpticFormScreen> createState() => _OpticFormScreenState();
}

class _OpticFormScreenState extends State<OpticFormScreen> {
  late int _total = widget.initialTotal.clamp(1, OpticFormScreen.maxTotal).toInt();
  late final Map<int, QuestionStatus> _marks = {
    for (final e in widget.initialMarks.entries)
      if (e.value != QuestionStatus.correct) e.key: e.value,
  };

  /// Dokununca uygulanacak işaret. Uzun basış diğerini koyar.
  QuestionStatus _mode = QuestionStatus.wrong;

  OpticFormResult get _result => OpticFormResult(
        total: _total,
        marks: {
          for (final e in _marks.entries)
            if (e.key <= _total) e.key: e.value,
        },
      );

  void _tap(int number, {bool alternate = false}) {
    final target = alternate
        ? (_mode == QuestionStatus.wrong ? QuestionStatus.blank : QuestionStatus.wrong)
        : _mode;
    setState(() {
      if (_marks[number] == target) {
        _marks.remove(number);
      } else {
        _marks[number] = target;
      }
    });
  }

  void _setTotal(int value) => setState(() => _total = value.clamp(1, OpticFormScreen.maxTotal).toInt());

  Future<void> _editTotal() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _TotalDialog(initial: _total),
    );
    if (value != null && value > 0) _setTotal(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _marks.isEmpty ? null : () => setState(_marks.clear),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Row(
              children: [
                if (widget.totalEditable) ...[
                  IconButton(
                    tooltip: 'Bir azalt',
                    onPressed: _total > 1 ? () => _setTotal(_total - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _editTotal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text('$_total soru', style: theme.textTheme.titleMedium),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bir artır',
                    onPressed: _total < OpticFormScreen.maxTotal ? () => _setTotal(_total + 1) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('$_total soru', style: theme.textTheme.titleMedium),
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
              'Yanlış ya da boş bıraktığın numaralara dokun; işaretsizler doğru sayılır. '
              'Uzun basınca öteki işaret konur.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 64,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _total,
              itemBuilder: (context, i) {
                final number = i + 1;
                return _Bubble(
                  number: number,
                  status: _marks[number],
                  onTap: () => _tap(number),
                  onLongPress: () => _tap(number, alternate: true),
                );
              },
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
              Text(
                '$number',
                style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 15),
              ),
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
