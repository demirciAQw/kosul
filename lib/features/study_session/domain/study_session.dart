import '../../../core/utils/formatters.dart';
import '../../../core/utils/id_generator.dart';

enum SessionStatus { running, awaitingResults, completed }

/// Kitapsız oturumda ne yapıldığı. Yalnızca "Soru çözümü" doğru/yanlış/boş ister.
enum StudyActivity {
  questions('Soru çözümü', true),
  lecture('Konu çalışması', false),
  video('Video', false),
  review('Tekrar', false),
  other('Diğer', false);

  const StudyActivity(this.label, this.hasQuestions);
  final String label;
  final bool hasQuestions;
}

/// Oturuma eklenecek bir seçim bloğu (seçim ağacından ya da kitapsız formdan üretilir).
class SessionItemDraft {
  const SessionItemDraft({
    required this.label,
    required this.pages,
    this.bookId,
    this.contentNodeId,
    this.mebNodeId,
    this.estimatedQuestions,
    this.subject,
    this.activity,
  });

  final String label; // "345 TYT Mat › Problemler › Yaş Problemleri"
  final String? bookId;
  final String? contentNodeId; // null = tüm kitap
  final String? mebNodeId;
  final List<int> pages; // sıralı
  final int? estimatedQuestions;
  final String? subject; // "TYT Matematik"
  final StudyActivity? activity; // kitaplı bloklarda null = soru çözümü
}

class SessionItem {
  const SessionItem({
    required this.id,
    required this.label,
    this.bookId,
    this.contentNodeId,
    this.mebNodeId,
    this.pages = const [],
    this.estimatedQuestions,
    this.correct,
    this.wrong,
    this.blank,
    this.subject,
    this.activity,
  });

  final String id;
  final String label;
  final String? bookId;
  final String? contentNodeId;
  final String? mebNodeId;
  final List<int> pages;
  final int? estimatedQuestions;
  final int? correct;
  final int? wrong;
  final int? blank;
  final String? subject;
  final StudyActivity? activity;

  bool get hasResults => correct != null || wrong != null || blank != null;
  int get solved => (correct ?? 0) + (wrong ?? 0) + (blank ?? 0);
  String get pageSpec => formatPages(pages);

  /// Doğru/yanlış/boş girilecek bir blok mu? (Konu anlatımı, video vb. değil.)
  bool get hasQuestions => activity?.hasQuestions ?? true;
  bool get isBookless => bookId == null;

  /// Kart ve listelerde gösterilecek test adı: kitap adı olmadan.
  /// "345 TYT Mat › Problemler › Yaş" → "Problemler › Yaş"
  String get testLabel {
    if (isBookless) return label;
    final parts = label.split(' › ');
    return parts.length > 1 ? parts.skip(1).join(' › ') : label;
  }
}

class StudySession {
  const StudySession({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.items,
    this.endedAt,
  });

  final String id;
  final SessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<SessionItem> items;

  /// Süre HER ZAMAN damgalardan hesaplanır, asla sayaçtan okunmaz.
  Duration elapsedAt(DateTime now) => (endedAt ?? now).difference(startedAt);

  int get totalSolved => items.fold(0, (sum, i) => sum + i.solved);
  bool get hasQuestionWork => items.any((i) => i.hasQuestions);

  double? get secondsPerQuestion {
    final end = endedAt;
    if (end == null || totalSolved == 0) return null;
    return end.difference(startedAt).inSeconds / totalSolved;
  }
}

class ItemResult {
  const ItemResult({required this.itemId, required this.correct, required this.wrong, required this.blank});
  final String itemId;
  final int correct;
  final int wrong;
  final int blank;
}

sealed class StudySessionException implements Exception {
  const StudySessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class SessionAlreadyRunningException extends StudySessionException {
  const SessionAlreadyRunningException() : super('Zaten süren bir oturum var.');
}

final class SessionNotRunningException extends StudySessionException {
  const SessionNotRunningException() : super('Bu oturum zaten bitirilmiş.');
}

final class EmptySelectionException extends StudySessionException {
  const EmptySelectionException() : super('En az bir konu ya da sayfa seç.');
}

final class InvalidTimesException extends StudySessionException {
  const InvalidTimesException() : super('Bitiş, başlangıçtan sonra olmalı (en fazla 16 saat).');
}

final class InvalidResultException extends StudySessionException {
  const InvalidResultException() : super('Doğru, yanlış ve boş sayıları negatif olamaz.');
}

abstract interface class StudySessionRepository {
  Stream<StudySession?> watchRunning();
  Stream<List<StudySession>> watchAwaitingResults();
  Stream<StudySession?> watchById(String id);

  /// Koşan bir oturum varsa [SessionAlreadyRunningException].
  Future<StudySession> start(List<SessionItemDraft> items, DateTime at);
  Future<void> finish(String sessionId, DateTime at);

  /// Yanlışlıkla başlatılan oturumu iz bırakmadan siler. Bu oturumda fotoğrafsız
  /// işaretlenmiş "hızlı" kartlar da silinir; fotoğraflı kartlar defterde kalır.
  Future<void> cancel(String sessionId);

  /// Tüm sonuçları yazar ve oturumu tamamlar. Soru başına süresi henüz
  /// bilinmeyen kartlara oturumun ortalaması işlenir.
  Future<void> saveResults(String sessionId, List<ItemResult> results);

  /// Tek bloğun sayılarını yazar (optik formdan); oturumun durumunu değiştirmez.
  Future<void> saveItemResult(ItemResult result);

  /// Bitmiş ve sonuç bekleyen oturumlar, en yeni başta (geçmiş ekranı).
  Stream<List<StudySession>> watchHistory({int limit = 200});

  /// Unutulup açık kalan sayaç gibi hataları düzeltmek için.
  Future<void> updateTimes(String sessionId, {required DateTime startedAt, required DateTime endedAt});

  /// Bitmiş oturumu siler. Defterdeki sorular kalır (oturum bağı kopar).
  Future<void> deleteFinished(String sessionId);
}

// ───────────────────────── Use case'ler ─────────────────────────

class StartStudySession {
  StartStudySession(this._repository, this._clock);
  final StudySessionRepository _repository;
  final Clock _clock;

  Future<StudySession> call(List<SessionItemDraft> items) {
    if (items.isEmpty) throw const EmptySelectionException();
    return _repository.start(items, _clock());
  }
}

/// Oturumu kapatır, durum "sonuç bekliyor" olur (rozet). Sonuç girişi
/// ertelenebilir; kullanıcı hemen yeni bir oturuma geçebilir.
class FinishStudySession {
  FinishStudySession(this._repository, this._clock);
  final StudySessionRepository _repository;
  final Clock _clock;

  Future<void> call(String sessionId) => _repository.finish(sessionId, _clock());
}

class CancelStudySession {
  CancelStudySession(this._repository);
  final StudySessionRepository _repository;

  Future<void> call(String sessionId) => _repository.cancel(sessionId);
}

class SubmitSessionResults {
  SubmitSessionResults(this._repository);
  final StudySessionRepository _repository;

  Future<void> call(String sessionId, List<ItemResult> results) {
    if (results.any((r) => r.correct < 0 || r.wrong < 0 || r.blank < 0)) {
      throw const InvalidResultException();
    }
    return _repository.saveResults(sessionId, results);
  }
}
