import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/text/turkish_text.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../../library/domain/library.dart';
import '../../../library/library_providers.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';

Future<void> showQuestionFilterSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FilterSheet(),
    );

class _Item {
  const _Item(this.value, this.label, [this.depth = 0]);
  final String value;
  final String label;
  final int depth;
}

const _all = '__all__';

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late QuestionFilter _f = ref.read(questionFilterProvider);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final books = ref.watch(libraryProvider).value ?? const <Book>[];

    final subjects = {
      for (final n in curriculum) n.subjectLabel,
      for (final b in books) subjectKey(b.examType, b.subject),
    }.toList()
      ..sort();
    final topics = _f.subject == null
        ? const <CurriculumNode>[]
        : depthFirst(curriculum.where((n) => n.subjectLabel == _f.subject));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filtrele', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              _menu(
                key: const ValueKey('f-subject'),
                label: 'Ders',
                value: _f.subject,
                items: [for (final s in subjects) _Item(s, s)],
                onChanged: (v) => setState(() {
                  _f = _f.copyWith(subject: () => v, topicId: () => null, mebNodeIds: const {});
                }),
              ),
              const SizedBox(height: 12),
              _menu(
                key: ValueKey('f-topic-${_f.subject}'),
                label: 'Konu',
                value: _f.topicId,
                enabled: topics.isNotEmpty,
                filterable: true,
                items: [for (final t in topics) _Item(t.id, t.title, t.depth)],
                onChanged: (v) => setState(() {
                  _f = _f.copyWith(
                    topicId: () => v,
                    mebNodeIds: v == null ? const <String>{} : descendantIds(curriculum, v),
                  );
                }),
              ),
              if (books.isNotEmpty) ...[
                const SizedBox(height: 12),
                _menu(
                  key: const ValueKey('f-book'),
                  label: 'Kitap',
                  value: _f.bookId,
                  items: [for (final b in books) _Item(b.id, b.title)],
                  onChanged: (v) => setState(() => _f = _f.copyWith(bookId: () => v)),
                ),
              ],
              const SizedBox(height: 12),
              _menu(
                key: const ValueKey('f-reason'),
                label: 'Yanlış nedeni',
                value: _f.reasons.isEmpty ? null : _f.reasons.first.name,
                items: [for (final r in MistakeReason.values) _Item(r.name, r.label)],
                onChanged: (v) => setState(() {
                  _f = _f.copyWith(reasons: v == null ? const <MistakeReason>{} : {MistakeReason.values.byName(v)});
                }),
              ),
              const SizedBox(height: 20),
              Text('Zorluk: ${_f.minDifficulty} – ${_f.maxDifficulty}', style: theme.textTheme.titleSmall),
              RangeSlider(
                values: RangeValues(_f.minDifficulty.toDouble(), _f.maxDifficulty.toDouble()),
                min: 1,
                max: 10,
                divisions: 9,
                labels: RangeLabels('${_f.minDifficulty}', '${_f.maxDifficulty}'),
                onChanged: (v) => setState(() {
                  _f = _f.copyWith(minDifficulty: v.start.round(), maxDifficulty: v.end.round());
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in QuestionStatus.values)
                    FilterChip(
                      label: Text(status.label),
                      selected: _f.statuses.contains(status),
                      onSelected: (on) => setState(() {
                        final next = {..._f.statuses};
                        on ? next.add(status) : next.remove(status);
                        _f = _f.copyWith(statuses: next);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _f = QuestionFilter(text: _f.text, starredOnly: _f.starredOnly);
                      }),
                      child: const Text('Temizle'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        ref.read(questionFilterProvider.notifier).apply(_f);
                        Navigator.pop(context);
                      },
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu({
    required Key key,
    required String label,
    required String? value,
    required List<_Item> items,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
    bool filterable = false,
  }) {
    return DropdownMenu<String>(
      key: key,
      enabled: enabled,
      initialSelection: value ?? _all,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      label: Text(label),
      enableFilter: filterable,
      requestFocusOnTap: filterable,
      // Türkçe katlamalı arama: "isci" yazınca "İşçi ve Havuz" bulunur.
      filterCallback: (entries, filter) {
        final q = normalizeTr(filter);
        return q.isEmpty || filter == 'Hepsi'
            ? entries
            : entries.where((e) => normalizeTr(e.label).contains(q)).toList();
      },
      dropdownMenuEntries: [
        const DropdownMenuEntry(value: _all, label: 'Hepsi'),
        for (final item in items)
          DropdownMenuEntry(
            value: item.value,
            label: item.label,
            labelWidget: Padding(
              padding: EdgeInsetsDirectional.only(start: item.depth * 16.0),
              child: Text(item.label),
            ),
          ),
      ],
      onSelected: (v) => onChanged(v == null || v == _all ? null : v),
    );
  }
}
