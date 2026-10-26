import 'dart:async';
import 'dart:io';

import '../domain/ocr.dart';
import '../domain/question_text.dart';
import '../domain/reader/figure_detector.dart';
import '../domain/reader/page_reader.dart';
import 'page_image_tools.dart';

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
    PageImageTools? images,
    Future<List<FigureRegion>> Function(FigureJob job)? figures,
  })  : _images = images,
        _figures = figures,
        _engine = engine,
        _repository = repository,
        _resolve = resolve,
        _clock = clock ?? DateTime.now;

  final OcrEngine _engine;
  final OcrRepository _repository;
  final String Function(String) _resolve;
  final DateTime Function() _clock;
  final Duration gap;

  /// Okuyucu sürümü: değişince eski kayıtlar arka planda yeniden okunur.
  static const engineVersion = 'kocum-okuyucu-2';

  /// Grafik ve şekilleri açıklayan model (Gemini Nano; destekleyen cihazda).
  /// Etkinleşince sürüm değişir; eski sorular bir kez yeniden işlenir.
  Future<String?> Function(String path)? describe;

  String get engine => describe == null ? engineVersion : '$engineVersion+genai';

  /// Döndürme ve görüntü örnekleme (telefonda); testlerde verilmez.
  final PageImageTools? _images;

  /// Şekil bulucu (telefonda ayrı iş parçacığında).
  final Future<List<FigureRegion>> Function(FigureJob job)? _figures;

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
    for (final job in pendingJobs(wanted: wanted, existing: existing, engine: engine)) {
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
    String? temp;
    try {
      final path = _resolve(job.imagePath);
      var lines = await _engine.recognize(path);
      final rotation = dominantRotation(lines);
      var source = path;
      final tools = _images;
      // Yan ya da ters sayfa: döndürülüp yeniden okunur. Döndürme yönü cihaza göre
      // değişebileceği için iki yön denenir; düz okunan kabul edilir.
      if (rotation != 0 && tools != null) {
        for (final degrees in {(360 - rotation) % 360, rotation}) {
          final rotated = await tools.rotate(path, degrees);
          if (rotated == null) continue;
          final again = await _engine.recognize(rotated);
          if (again.isNotEmpty && dominantRotation(again) == 0) {
            lines = again;
            source = rotated;
            temp = rotated;
            break;
          }
          await _deleteQuietly(rotated);
        }
      }
      final image = tools == null ? null : await tools.sample(source);
      final words = withWords(lines);
      final width = image?.fullWidth.toDouble() ??
          words.fold<double>(1, (m, l) => l.left + l.width > m ? l.left + l.width : m);
      final height = image?.fullHeight.toDouble() ??
          words.fold<double>(1, (m, l) => l.top + l.height > m ? l.top + l.height : m);
      final reading = readPage(words, width, height, preferredNumber: job.preferredNumber);

      var figures = const <FigureRegion>[];
      final detect = _figures;
      if (image != null && detect != null) {
        final sx = image.width / width, sy = image.height / height;
        figures = await detect(FigureJob(image.rgba, image.width, image.height, [
          for (final l in words) TextBox(l.text, l.left * sx, l.top * sy, l.width * sx, l.height * sy),
        ]));
      }

      // Grafik, şekil ve fotoğraflar için kısa açıklama (en büyük ikisi; İngilizce).
      final figureJson = [for (final f in figures) <String, Object?>{...f.toJson()}];
      final describer = describe;
      if (describer != null && tools != null && job.ownerType == 'question') {
        final targets = [
          for (final (i, f) in figures.indexed)
            if (f.kind != 'annotation') (i, (f.box[2] - f.box[0]) * (f.box[3] - f.box[1])),
        ]..sort((a, b) => b.$2.compareTo(a.$2));
        for (final (i, _) in targets.take(2)) {
          final crop = await tools.crop(source, figures[i].box);
          if (crop == null) continue;
          final text = await describer(crop);
          await _deleteQuietly(crop);
          if (text != null) figureJson[i]['description'] = text;
        }
      }

      final ordered = readingOrder(lines);
      final main = reading.main;
      final record = OcrRecord(
        id: job.id,
        ownerType: job.ownerType,
        ownerId: job.ownerId,
        imagePath: job.imagePath,
        status: 'done',
        fullText: ordered.map((l) => l.text).join('\n'),
        // Soru fotoğraflarında asıl sorunun kökü (maddeler, öncüller ve soru
        // cümlesiyle) ve şıkları; not ve çözüm sayfalarında yalnızca yapı.
        parsed: job.ownerType == 'question' && main != null
            ? ParsedQuestion(stem: main.fullStem, number: main.number, options: main.options)
            : null,
        lines: ordered,
        durationMs: watch.elapsedMilliseconds,
        processedAt: _clock(),
        engine: engine,
        structure: {
          'rotation': rotation,
          'width': width.round(),
          'height': height.round(),
          ...reading.toJson(),
          'figures': figureJson,
        },
      );
      await _repository.save(record);
      onRecord?.call(record);
    } catch (e) {
      // Başarısız okuma da kaydedilir: aynı fotoğraf her açılışta boşuna
      // denenmez (fotoğraf ya da okuyucu sürümü değişirse, "Yeniden oku" ile tekrar).
      final record = OcrRecord(
        id: job.id,
        ownerType: job.ownerType,
        ownerId: job.ownerId,
        imagePath: job.imagePath,
        status: 'failed',
        error: '$e',
        durationMs: watch.elapsedMilliseconds,
        processedAt: _clock(),
        engine: engine,
      );
      await _repository.save(record);
      onRecord?.call(record);
    } finally {
      if (temp != null) await _deleteQuietly(temp);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
