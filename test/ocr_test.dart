import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/features/ocr/data/ocr_queue.dart';
import 'package:kocum/features/ocr/data/ocr_repository_impl.dart';
import 'package:kocum/features/ocr/domain/ocr.dart';
import 'package:kocum/features/ocr/domain/question_text.dart';

/// Satırları sırayla, alt alta yerleştirir (ML Kit çıktısı gibi).
List<OcrLine> _stack(List<String> texts) =>
    [for (final (i, t) in texts.indexed) OcrLine(t, left: 10, top: 20.0 * i, height: 16)];

class _FakeEngine implements OcrEngine {
  _FakeEngine(this.byPath);
  final Map<String, List<OcrLine>> byPath;
  final calls = <String>[];

  @override
  Future<List<OcrLine>> recognize(String absolutePath) async {
    calls.add(absolutePath);
    final lines = byPath[absolutePath];
    if (lines == null) throw StateError('okunamadı');
    return lines;
  }
}

void main() {
  group('Soru metni ayrıştırma', () {
    test('kök, numara ve alt alta şıklar', () {
      final p = parseQuestion(_stack([
        '7. f(x) = 2x + 3 olduğuna göre',
        'f(4) kaçtır?',
        'A) 8',
        'B) 9',
        'C) 10',
        'D) 11',
        'E) 12',
      ]));
      expect(p.number, 7);
      expect(p.stem, contains('f(x) = 2x + 3'));
      expect(p.stem, contains('f(4) kaçtır?'));
      expect(p.options.keys, ['A', 'B', 'C', 'D', 'E']);
      expect(p.options['D'], '11');
    });

    test('aynı satırda iki şık ve çok satırlı şık', () {
      final p = parseQuestion([
        const OcrLine('Hangisi doğrudur?', left: 10, top: 0, height: 16),
        const OcrLine('A) Birinci B) İkinci', left: 10, top: 30, height: 16),
        const OcrLine('C) Uzun bir şık', left: 10, top: 60, height: 16),
        const OcrLine('devamı burada', left: 10, top: 80, height: 16),
        const OcrLine('D) Dört E) Beş', left: 10, top: 110, height: 16),
      ]);
      expect(p.options['A'], 'Birinci');
      expect(p.options['B'], 'İkinci');
      expect(p.options['C'], 'Uzun bir şık devamı burada');
      expect(p.options['E'], 'Beş');
    });

    test('şıksız metin olduğu gibi kalır', () {
      final p = parseQuestion(_stack(['Paragrafta anlatılmak istenen', 'ana düşünce nedir']));
      expect(p.hasOptions, isFalse);
      expect(p.stem, contains('ana düşünce'));
    });
  });

  group('Okunacak fotoğraflar', () {
    final rec = OcrRecord(
      id: 'question:a',
      ownerType: 'question',
      ownerId: 'a',
      imagePath: 'q/a1.webp',
      status: 'done',
      processedAt: DateTime(2026),
    );

    test('yeni ya da fotoğrafı değişen okunur; okunmuş atlanır', () {
      const same = OcrJob(id: 'question:a', ownerType: 'question', ownerId: 'a', imagePath: 'q/a1.webp');
      const changed = OcrJob(id: 'question:a', ownerType: 'question', ownerId: 'a', imagePath: 'q/a2.webp');
      const fresh = OcrJob(id: 'question:b', ownerType: 'question', ownerId: 'b', imagePath: 'q/b.webp');
      expect(pendingJobs(wanted: [same, fresh], existing: {'question:a': rec}).map((j) => j.id), ['question:b']);
      expect(pendingJobs(wanted: [changed], existing: {'question:a': rec}), hasLength(1));
    });

    test('sahibi silinen kayıt temizlenir', () {
      expect(orphanIds(wanted: const [], existing: {'question:a': rec}), {'question:a'});
    });
  });

  test('kuyruk: okur, başarısızı da kaydeder, veri setine bildirir, yeniden okur', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftOcrRepository(db);
    final engine = _FakeEngine({
      '/m/q/a.webp': _stack(['1. Soru kökü', 'A) bir', 'B) iki', 'C) üç']),
    });
    final dataset = <OcrRecord>[];
    final queue = OcrQueue(
      engine: engine,
      repository: repo,
      resolve: (rel) => '/m/$rel',
      gap: Duration.zero,
      onRecord: dataset.add,
    );
    const ok = OcrJob(id: 'question:a', ownerType: 'question', ownerId: 'a', imagePath: 'q/a.webp');
    const bad = OcrJob(id: 'question:b', ownerType: 'question', ownerId: 'b', imagePath: 'q/b.webp');
    await queue.sync([ok, bad], const {});
    await queue.drain();

    final all = await repo.watchAll().first;
    expect(all['question:a']!.ok, isTrue);
    expect(all['question:a']!.parsed!.options['C'], 'üç');
    expect(all['question:b']!.status, 'failed');
    expect(dataset.map((r) => r.id).toSet(), {'question:a', 'question:b'});
    final json = all['question:a']!.toDatasetJson();
    expect((json['ownerId'], json['number']), ('a', 1));

    // Aynı kayıtlarla yeniden eşitleme: tekrar okunmaz.
    await queue.sync([ok, bad], all);
    await queue.drain();
    expect(engine.calls, hasLength(2));

    await queue.retry(ok);
    await queue.drain();
    expect(engine.calls, hasLength(3));
  });
}
