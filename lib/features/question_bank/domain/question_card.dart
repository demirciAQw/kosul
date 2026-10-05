enum QuestionStatus {
  wrong('Yanlış'),
  blank('Boş'),
  correct('Doğru');

  const QuestionStatus(this.label);
  final String label;
}

enum QuestionOrigin {
  book('Kitap'),
  independent('Bağımsız'), // Telegram, deneme kulübü, öğretmen föyü…
  mockExam('Deneme');

  const QuestionOrigin(this.label);
  final String label;
}

/// Enum `.name` ile saklanır: sıra/etiket değişse de eski kayıtlar bozulmaz.
enum MistakeReason {
  knowledgeGap('Bilgi eksikliği'),
  misconception('Kavram yanılgısı'),
  calculation('İşlem hatası'),
  misreading('Soruyu yanlış okuma'),
  carelessness('Dikkatsizlik'),
  timePressure('Süre yetmedi'),
  wrongMethod('Yanlış yöntem'),
  guessed('Şansla işaretleme'),
  other('Diğer');

  const MistakeReason(this.label);
  final String label;
}

class QuestionCard {
  const QuestionCard({
    required this.id,
    required this.status,
    required this.origin,
    required this.questionImage,
    required this.sourceName,
    required this.subject,
    required this.difficulty,
    required this.createdAt,
    this.solutionImage,
    this.solutionText,
    this.bookId,
    this.contentNodeId,
    this.sessionId,
    this.mebNodeId,
    this.testTotalQuestions,
    this.reason,
    this.avgSecondsPerQuestion,
    this.isStarred = false,
    this.note,
  });

  final String id;
  final QuestionStatus status;
  final QuestionOrigin origin;
  final String questionImage; // göreli medya yolu
  final String? solutionImage;
  final String? solutionText;
  final String sourceName;
  final String? bookId;
  final String? contentNodeId;
  final String? sessionId;
  final String? mebNodeId;
  final String subject; // "TYT Matematik"
  final int? testTotalQuestions;
  final MistakeReason? reason;
  final double? avgSecondsPerQuestion;
  final int difficulty; // 1–10
  final bool isStarred; // GK (Güzel Soru)
  final String? note;
  final DateTime createdAt;

  QuestionCard copyWith({bool? isStarred}) => QuestionCard(
        id: id,
        status: status,
        origin: origin,
        questionImage: questionImage,
        solutionImage: solutionImage,
        solutionText: solutionText,
        sourceName: sourceName,
        bookId: bookId,
        contentNodeId: contentNodeId,
        sessionId: sessionId,
        mebNodeId: mebNodeId,
        subject: subject,
        testTotalQuestions: testTotalQuestions,
        reason: reason,
        avgSecondsPerQuestion: avgSecondsPerQuestion,
        difficulty: difficulty,
        isStarred: isStarred ?? this.isStarred,
        note: note,
        createdAt: createdAt,
      );
}

typedef Getter<T> = T Function();

/// Gelişmiş arama motorunun sorgu nesnesi (açılır menüler + metin).
class QuestionFilter {
  const QuestionFilter({
    this.text,
    this.subject,
    this.bookId,
    this.topicId,
    this.mebNodeIds = const {},
    this.reasons = const {},
    this.statuses = const {},
    this.starredOnly = false,
    this.minDifficulty = 1,
    this.maxDifficulty = 10,
  });

  final String? text;
  final String? subject;
  final String? bookId;

  /// Menüde seçili konu (görüntü için).
  final String? topicId;

  /// Sorguda kullanılan kimlikler: seçili konu + tüm alt konuları.
  final Set<String> mebNodeIds;
  final Set<MistakeReason> reasons;
  final Set<QuestionStatus> statuses;
  final bool starredOnly;
  final int minDifficulty;
  final int maxDifficulty;

  /// Filtre menüsünde seçilmiş kriter sayısı (rozet için; metin ve yıldız hariç).
  int get activeCount =>
      (subject != null ? 1 : 0) +
      (bookId != null ? 1 : 0) +
      (topicId != null ? 1 : 0) +
      (reasons.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      ((minDifficulty != 1 || maxDifficulty != 10) ? 1 : 0);

  bool get isUnfiltered => text == null && !starredOnly && activeCount == 0;

  /// Boş bırakılabilen alanlar `() => değer` ile verilir: `copyWith(subject: () => null)`.
  QuestionFilter copyWith({
    Getter<String?>? text,
    Getter<String?>? subject,
    Getter<String?>? bookId,
    Getter<String?>? topicId,
    Set<String>? mebNodeIds,
    Set<MistakeReason>? reasons,
    Set<QuestionStatus>? statuses,
    bool? starredOnly,
    int? minDifficulty,
    int? maxDifficulty,
  }) =>
      QuestionFilter(
        text: text != null ? text() : this.text,
        subject: subject != null ? subject() : this.subject,
        bookId: bookId != null ? bookId() : this.bookId,
        topicId: topicId != null ? topicId() : this.topicId,
        mebNodeIds: mebNodeIds ?? this.mebNodeIds,
        reasons: reasons ?? this.reasons,
        statuses: statuses ?? this.statuses,
        starredOnly: starredOnly ?? this.starredOnly,
        minDifficulty: minDifficulty ?? this.minDifficulty,
        maxDifficulty: maxDifficulty ?? this.maxDifficulty,
      );
}

// ───────────────────────── Yeni kayıt taslağı ─────────────────────────

enum DraftIssue {
  missingQuestionImage('Sorunun fotoğrafını ekle.'),
  missingSolution('Doğru çözümü ekle: fotoğraf ya da metin zorunlu.'),
  missingSource('Kaynağı seç ya da yaz.'),
  missingSubject('Dersi seç.'),
  missingReason('Yanlış ya da boş bırakma nedenini seç.'),
  invalidDifficulty('Zorluk 1 ile 10 arasında olmalı.'),
  invalidTestSize('Testteki soru sayısı en az 1 olmalı.');

  const DraftIssue(this.message);
  final String message;
}

class QuestionDraft {
  const QuestionDraft({
    required this.status,
    required this.origin,
    required this.sourceName,
    this.questionImagePath,
    this.solutionImagePath,
    this.solutionText,
    this.bookId,
    this.contentNodeId,
    this.sessionId,
    this.mebNodeId,
    this.subject,
    this.testTotalQuestions,
    this.reason,
    this.avgSecondsPerQuestion,
    this.difficulty = 5,
    this.isStarred = false,
    this.note,
  });

  final QuestionStatus status;
  final QuestionOrigin origin;
  final String? questionImagePath; // GEÇİCİ mutlak yol (sıkıştırılmış)
  final String? solutionImagePath;
  final String? solutionText;
  final String sourceName;
  final String? bookId;
  final String? contentNodeId;
  final String? sessionId;
  final String? mebNodeId;
  final String? subject;
  final int? testTotalQuestions;
  final MistakeReason? reason;
  final double? avgSecondsPerQuestion;
  final int difficulty;
  final bool isStarred;
  final String? note;

  bool get hasSolution => solutionImagePath != null || (solutionText?.trim().isNotEmpty ?? false);

  List<DraftIssue> validate() => [
        if (questionImagePath == null) DraftIssue.missingQuestionImage,
        if (!hasSolution) DraftIssue.missingSolution,
        if (sourceName.trim().isEmpty) DraftIssue.missingSource,
        if (subject == null || subject!.trim().isEmpty) DraftIssue.missingSubject,
        if (status != QuestionStatus.correct && reason == null) DraftIssue.missingReason,
        if (difficulty < 1 || difficulty > 10) DraftIssue.invalidDifficulty,
        if (testTotalQuestions != null && testTotalQuestions! < 1) DraftIssue.invalidTestSize,
      ];
}

class QuestionDraftInvalid implements Exception {
  const QuestionDraftInvalid(this.issues);
  final List<DraftIssue> issues;
  @override
  String toString() => issues.map((i) => i.message).join(' ');
}
