import 'question_text.dart';

/// Bir fotoğrafın okuma sonucu (soruya ya da nota bağlı).
class OcrRecord {
  const OcrRecord({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.imagePath,
    required this.status,
    required this.processedAt,
    this.fullText = '',
    this.parsed,
    this.lines = const [],
    this.durationMs,
    this.error,
    this.engine = 'mlkit-latin',
    this.structure,
  });

  final String id;
  final String ownerType; // question | solution | note
  final String ownerId;
  final String imagePath;
  final String status; // done | failed
  final String fullText;
  final ParsedQuestion? parsed;
  final List<OcrLine> lines;
  final int? durationMs;
  final String? error;
  final DateTime processedAt;

  /// Hangi okuyucu sürümüyle okundu (sürüm değişince yeniden okunur).
  final String engine;

  /// Sayfa yapısı: yön, sorular (kök, öncüller, şıklar, kesik mi), şekiller.
  final Map<String, Object?>? structure;

  bool get ok => status == 'done';

  /// Bulunan şekil/grafik/fotoğraf bölgeleri (türleriyle).
  List<Map<String, Object?>> get figures => [
        for (final f in (structure?['figures'] as List?) ?? const [])
          if (f is Map) f.cast<String, Object?>(),
      ];

  /// Veri seti satırı: kimlikle soruya/nota bağlı; konumlarıyla satırlar.
  Map<String, Object?> toDatasetJson() => {
        'type': 'ocr',
        'id': id,
        'owner': ownerType,
        'ownerId': ownerId,
        'image': imagePath,
        'status': status,
        'at': processedAt.toIso8601String(),
        'ms': durationMs,
        'number': parsed?.number,
        'stem': parsed?.stem,
        'options': parsed?.options,
        'text': fullText,
        'lines': [for (final l in lines) l.toJson()],
        if (error != null) 'error': error,
        'engine': engine,
        if (structure != null) 'structure': structure,
      };

  /// Arama ve rapor için tek metin: kök + şıklar (yoksa ham metin).
  String get searchable {
    final p = parsed;
    if (p == null) return fullText;
    return [p.stem, for (final e in p.options.entries) '${e.key}) ${e.value}'].where((s) => s.isNotEmpty).join('\n');
  }
}

/// Okunacak bir fotoğraf.
class OcrJob {
  const OcrJob({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.imagePath,
    this.preferredNumber,
  });
  final String id;
  final String ownerType;
  final String ownerId;
  final String imagePath; // medya köküne göre göreli

  /// Kartın soru numarası: fotoğrafta birden çok soru varsa asıl olan bu.
  final int? preferredNumber;

  static String questionId(String cardId) => 'question:$cardId';
  static String solutionId(String cardId) => 'solution:$cardId';
  static String noteId(String noteId, int index) => 'note:$noteId:$index';
}

/// Telefonda metin tanıma (ML Kit). Testlerde sahtesi kullanılır.
abstract interface class OcrEngine {
  /// [absolutePath] fotoğrafındaki satırlar ve konumları.
  Future<List<OcrLine>> recognize(String absolutePath);
}

abstract interface class OcrRepository {
  Stream<Map<String, OcrRecord>> watchAll();
  Future<void> save(OcrRecord record);
  Future<void> deleteIds(Iterable<String> ids);
}

/// Hangi fotoğrafların okunması gerektiği: kaydı olmayan ya da fotoğrafı
/// değişmiş olanlar. Sıra: sorular (en yeni önce), notlar, çözümler.
List<OcrJob> pendingJobs({
  required List<OcrJob> wanted,
  required Map<String, OcrRecord> existing,
  String? engine,
}) {
  int rank(String type) => switch (type) { 'question' => 0, 'note' => 1, _ => 2 };
  final out = [
    for (final j in wanted)
      if (existing[j.id] == null ||
          existing[j.id]!.imagePath != j.imagePath ||
          (engine != null && existing[j.id]!.engine != engine))
        j,
  ];
  // Kararlı sıralama: tür önceliği; aynı türde verilen sıra (en yeni önce) korunur.
  final indexed = [for (final (i, j) in out.indexed) (i, j)]
    ..sort((a, b) {
      final r = rank(a.$2.ownerType).compareTo(rank(b.$2.ownerType));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  return [for (final (_, j) in indexed) j];
}

/// Sahibi artık olmayan (soru silinmiş, fotoğraf kaldırılmış) kayıtlar.
Set<String> orphanIds({required List<OcrJob> wanted, required Map<String, OcrRecord> existing}) {
  final keep = {for (final j in wanted) j.id};
  return {for (final id in existing.keys) if (!keep.contains(id)) id};
}
