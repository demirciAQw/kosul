import 'dart:async';

import '../domain/ocr.dart';
import '../domain/question_text.dart';

/// Arka plan okuma kuyruğu: fotoğraflar tek tek, aralarında kısa bir mola
/// verilerek okunur; kullanıcı arayüzü yavaşlamaz. Yeni soru eklenince ya da
/// fotoğraf değişince kendiliğinden sıraya girer; uygulama açılınca eski
/// fotoğraflar da sırayla okunur.
class OcrQueue {
  OcrQueue({
    required OcrEngine engine,
    required OcrRepository repository,
    required String Function(String relativePath) resolve,
    DateTime Function()? clock,
    this.gap = const Duration(milliseconds: 700),
    this.onRecord,
  })  : _engine = engine,
        _repository = repository,
        _resolve = resolve,
        _clock = clock ?? DateTime.now;

  final OcrEngine _engine;
  final OcrRepository _repository;
  final String Function(String) _resolve;
  final DateTime Function() _clock;
  final Duration gap;

  /// Her okuma sonucu (başarılı ya da değil) kaydedildikten sonra: veri seti dosyası için.
  final void Function(OcrRecord record)? onRecord;

  final _queue = <OcrJob>[];
  final _queued = <String>{};
  bool _running = false;
  bool _enabled = true;

  /// Sırada bekleyen fotoğraf sayısı (işlenmekte olan dahil).
  int get pending => _queued.length;

  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    if (v) unawaited(_pump());
  }

  /// İstenen fotoğraflarla kayıtları karşılaştırır: eksikleri sıraya alır,
  /// sahibi kalmayan kayıtları siler.
  Future<void> sync(List<OcrJob> wanted, Map<String, OcrRecord> existing) async {
    final orphans = orphanIds(wanted: wanted, existing: existing);
    if (orphans.isNotEmpty) await _repository.deleteIds(orphans);
    for (final job in pendingJobs(wanted: wanted, existing: existing)) {
      if (_queued.add(job.id)) _queue.add(job);
    }
    unawaited(_pump());
  }

  /// "Yeniden oku": sıranın başına alınır.
  Future<void> retry(OcrJob job) async {
    await _repository.deleteIds([job.id]);
    _queue.removeWhere((j) => j.id == job.id);
    _queued.add(job.id);
    _queue.insert(0, job);
    unawaited(_pump());
  }

  /// Çalışan işleme turu (yoksa null).
  Future<void>? _active;

  /// Sıradakiler bitene kadar bekler (testler ve kapatma için). Tur zaten
  /// çalışıyorsa onun bitmesini bekler; bu sırada eklenenler de işlenir.
  Future<void> drain() async {
    if (_active == null) await _pump();
    while (_active != null) {
      await _active;
    }
  }

  Future<void> _pump() {
    if (_running || !_enabled) return _active ?? Future<void>.value();
    _running = true;
    return _active = _run().whenComplete(() {
      _running = false;
      _active = null;
    });
  }

  Future<void> _run() async {
    while (_queue.isNotEmpty && _enabled) {
      final job = _queue.removeAt(0);
      await _process(job);
      _queued.remove(job.id);
      if (_queue.isNotEmpty) await Future<void>.delayed(gap);
    }
  }

  Future<void> _process(OcrJob job) async {
    final watch = Stopwatch()..start();
    try {
      final lines = await _engine.recognize(_resolve(job.imagePath));
      final ordered = readingOrder(lines);
      final full = ordered.map((l) => l.text).join('\n');
      final record = OcrRecord(
        id: job.id,
        ownerType: job.ownerType,
        ownerId: job.ownerId,
        imagePath: job.imagePath,
        status: 'done',
        fullText: full,
        // Soru fotoğraflarında kök ve şıklar ayrılır; not sayfaları düz metin.
        parsed: job.ownerType == 'question' ? parseQuestion(lines) : null,
        lines: ordered,
        durationMs: watch.elapsedMilliseconds,
        processedAt: _clock(),
      );
      await _repository.save(record);
      onRecord?.call(record);
    } catch (e) {
      // Başarısız okuma da kaydedilir: aynı fotoğraf her açılışta boşuna
      // denenmez (fotoğraf değişirse ya da "Yeniden oku" ile tekrar denenir).
      final record = OcrRecord(
        id: job.id,
        ownerType: job.ownerType,
        ownerId: job.ownerId,
        imagePath: job.imagePath,
        status: 'failed',
        error: '$e',
        durationMs: watch.elapsedMilliseconds,
        processedAt: _clock(),
      );
      await _repository.save(record);
      onRecord?.call(record);
    }
  }
}
