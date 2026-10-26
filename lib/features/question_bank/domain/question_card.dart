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

/// Kartı "tamamlanmış" saymak için eksik olabilecek parçalar (Eksikler listesi).
enum MissingPart {
  photo('Fotoğraf'),
  solution('Çözüm'),
  reason('Neden'),
  topic('Konu');

  const MissingPart(this.label);
  final String label;
}

class QuestionCard {
  const QuestionCard({
    required this.id,
    required this.status,
    required this.origin,
    required this.sourceName,
    required this.subject,
    required this.difficulty,
    required this.createdAt,
    this.questionImage,
    this.solutionImage,
    this.solutionText,
    this.bookId,
    this.contentNodeId,
    this.sessionId,
    this.mebNodeId,
    this.testTotalQuestions,
    this.reason,
    this.reasonNote,
    this.topicText,
    this.correctAnswer,
    this.givenAnswer,
    this.avgSecondsPerQuestion,
    this.isStarred = false,
    this.note,
    this.questionNo,
    this.testLabel,
    this.sessionItemId,
    this.mockExamId,
  });

  final String id;
  final QuestionStatus status;
  final QuestionOrigin origin;
  final String? questionImage; // göreli medya yolu; hızlı kartlarda null
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

  /// "Diğer" seçildiğinde kullanıcının kendi açıklaması.
  final String? reasonNote;

  /// Serbest konu/kazanım adı (karneden): MEB konusu yoksa analizde bu kullanılır.
  final String? topicText;

  /// Şıklar: doğru cevap ve öğrencinin işaretlediği ("A"–"E").
  final String? correctAnswer;
  final String? givenAnswer;

  /// "Doğru cevap C, senin cevabın B" / "Doğru cevap D, boş bıraktın".
  String? get answerText {
    final dc = correctAnswer;
    if (dc == null) return null;
    // Yazılı cevaplar tırnak içinde: "Doğru cevap: "x = 3""
    final written = !isChoiceAnswer(dc) || (givenAnswer != null && !isChoiceAnswer(givenAnswer));
    String q(String s) => written ? '"$s"' : s;
    final sep = written ? ': ' : ' ';
    if (status == QuestionStatus.blank) return 'Doğru cevap$sep${q(dc)}, boş bıraktın';
    final g = givenAnswer;
    if (status == QuestionStatus.correct || g == null || g == dc) return 'Doğru cevap$sep${q(dc)}';
    return 'Doğru cevap$sep${q(dc)}, senin cevabın$sep${q(g)}';
  }

  /// Cevaplar şık değil, yazılı mı (açık uçlu soru)?
  bool get hasWrittenAnswer =>
      (correctAnswer != null && !isChoiceAnswer(correctAnswer)) || (givenAnswer != null && !isChoiceAnswer(givenAnswer));
  final double? avgSecondsPerQuestion;
  final int difficulty; // 1–10
  final bool isStarred; // GK (Güzel Soru)
  final String? note;
  final DateTime createdAt;

  /// "Testin 7. sorusu": kitap/deneme içindeki numara.
  final int? questionNo;
  final String? testLabel;
  final String? sessionItemId;
  final String? mockExamId;

  bool get hasPhoto => questionImage != null;

  /// Ekranda gösterilecek neden: "Diğer" için kullanıcının kendi cümlesi.
  String? get reasonText {
    final r = reason;
    if (r == null) return null;
    final custom = reasonNote?.trim();
    return r == MistakeReason.other && custom != null && custom.isNotEmpty ? custom : r.label;
  }
  bool get hasSolution => solutionImage != null || (solutionText?.trim().isNotEmpty ?? false);
  bool get needsReason => status != QuestionStatus.correct && reason == null;

  /// Yalnızca hızlı işaretlemeyle oluşmuş, üzerinde emek olmayan kart
  /// (optikte işaret kaldırılınca silinebilir).
  bool get isBare => !hasPhoto && !hasSolution && note == null;

  /// [topicAvailable]: bu ders için müfredatta konu listesi var mı? Yoksa
  /// konu "eksik" sayılmaz; kart sonsuza dek listede takılı kalmasın.
  List<MissingPart> missingParts({required bool topicAvailable}) => [
        if (!hasPhoto) MissingPart.photo,
        if (!hasSolution) MissingPart.solution,
        if (needsReason) MissingPart.reason,
        if (topicAvailable && mebNodeId == null && (topicText?.trim().isEmpty ?? true)) MissingPart.topic,
      ];

  /// "Soru 7" ya da durum adı.
  String get shortTitle => questionNo == null ? status.label : 'Soru $questionNo';

  /// "Problemler › Yaş Problemleri, 7. soru"
  String get locationText {
    final where = testLabel ?? sourceName;
    return questionNo == null ? where : '$where, $questionNo. soru';
  }

  QuestionCard copyWith({
    bool? isStarred,
    QuestionStatus? status,
    String? Function()? topicText,
    String? Function()? mebNodeId,
  }) =>
      QuestionCard(
        id: id,
        status: status ?? this.status,
        origin: origin,
        questionImage: questionImage,
        solutionImage: solutionImage,
        solutionText: solutionText,
        sourceName: sourceName,
        bookId: bookId,
        contentNodeId: contentNodeId,
        sessionId: sessionId,
        mebNodeId: mebNodeId != null ? mebNodeId() : this.mebNodeId,
        subject: subject,
        testTotalQuestions: testTotalQuestions,
        reason: reason,
        reasonNote: reasonNote,
        topicText: topicText != null ? topicText() : this.topicText,
        correctAnswer: correctAnswer,
        givenAnswer: givenAnswer,
        avgSecondsPerQuestion: avgSecondsPerQuestion,
        difficulty: difficulty,
        isStarred: isStarred ?? this.isStarred,
        note: note,
        createdAt: createdAt,
        questionNo: questionNo,
        testLabel: testLabel,
        sessionItemId: sessionItemId,
        mockExamId: mockExamId,
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

// ───────────────────────── Yeni kayıt / düzenleme taslağı ─────────────────────────

/// v2: fotoğraf, çözüm ve neden isteğe bağlıdır. Eksik kart kaydedilir ve
/// Eksikler listesinde tamamlanmayı bekler. Zorunlu olan yalnızca ders.
enum DraftIssue {
  missingSubject('Dersi seç.'),
  invalidDifficulty('Zorluk 1 ile 10 arasında olmalı.'),
  invalidTestSize('Testteki soru sayısı en az 1 olmalı.'),
  invalidQuestionNo('Soru numarası en az 1 olmalı.');

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
    this.reasonNote,
    this.topicText,
    this.correctAnswer,
    this.givenAnswer,
    this.writtenAnswer = false,
    this.avgSecondsPerQuestion,
    this.difficulty = 5,
    this.isStarred = false,
    this.note,
    this.questionNo,
    this.testLabel,
    this.sessionItemId,
    this.mockExamId,
  });

  /// Mevcut kartın değerleriyle başlayan taslak (düzenleme için). Fotoğraf
  /// yolları boştur: "yeni fotoğraf yok, eskisi kalsın" anlamına gelir.
  factory QuestionDraft.fromCard(QuestionCard c) => QuestionDraft(
        status: c.status,
        origin: c.origin,
        sourceName: c.sourceName,
        solutionText: c.solutionText,
        bookId: c.bookId,
        contentNodeId: c.contentNodeId,
        sessionId: c.sessionId,
        mebNodeId: c.mebNodeId,
        subject: c.subject,
        testTotalQuestions: c.testTotalQuestions,
        reason: c.reason,
        reasonNote: c.reasonNote,
        topicText: c.topicText,
        correctAnswer: c.correctAnswer,
        givenAnswer: c.givenAnswer,
        writtenAnswer: c.hasWrittenAnswer,
        avgSecondsPerQuestion: c.avgSecondsPerQuestion,
        difficulty: c.difficulty,
        isStarred: c.isStarred,
        note: c.note,
        questionNo: c.questionNo,
        testLabel: c.testLabel,
        sessionItemId: c.sessionItemId,
        mockExamId: c.mockExamId,
      );

  final QuestionStatus status;
  final QuestionOrigin origin;
  final String? questionImagePath; // GEÇİCİ mutlak yol (sıkıştırılmış); düzenlemede = yeni fotoğraf
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
  final String? reasonNote;
  final String? topicText;
  final String? correctAnswer;
  final String? givenAnswer;

  /// Açık uçlu soru: cevaplar şık (A–E) değil, serbest metin.
  final bool writtenAnswer;
  final double? avgSecondsPerQuestion;
  final int difficulty;
  final bool isStarred;
  final String? note;
  final int? questionNo;
  final String? testLabel;
  final String? sessionItemId;
  final String? mockExamId;

  QuestionDraft copyWith({
    Getter<MistakeReason?>? reason,
    Getter<String?>? reasonNote,
    Getter<String?>? questionImagePath,
    Getter<String?>? solutionImagePath,
  }) =>
      QuestionDraft(
        status: status,
        origin: origin,
        sourceName: sourceName,
        questionImagePath: questionImagePath != null ? questionImagePath() : this.questionImagePath,
        solutionImagePath: solutionImagePath != null ? solutionImagePath() : this.solutionImagePath,
        solutionText: solutionText,
        bookId: bookId,
        contentNodeId: contentNodeId,
        sessionId: sessionId,
        mebNodeId: mebNodeId,
        subject: subject,
        testTotalQuestions: testTotalQuestions,
        reason: reason != null ? reason() : this.reason,
        reasonNote: reasonNote != null ? reasonNote() : this.reasonNote,
        topicText: topicText,
        correctAnswer: correctAnswer,
        givenAnswer: givenAnswer,
        writtenAnswer: writtenAnswer,
        avgSecondsPerQuestion: avgSecondsPerQuestion,
        difficulty: difficulty,
        isStarred: isStarred,
        note: note,
        questionNo: questionNo,
        testLabel: testLabel,
        sessionItemId: sessionItemId,
        mockExamId: mockExamId,
      );

  List<DraftIssue> validate() => [
        if (subject == null || subject!.trim().isEmpty) DraftIssue.missingSubject,
        if (difficulty < 1 || difficulty > 10) DraftIssue.invalidDifficulty,
        if (testTotalQuestions != null && testTotalQuestions! < 1) DraftIssue.invalidTestSize,
        if (questionNo != null && questionNo! < 1) DraftIssue.invalidQuestionNo,
      ];
}

class QuestionDraftInvalid implements Exception {
  const QuestionDraftInvalid(this.issues);
  final List<DraftIssue> issues;
  @override
  String toString() => issues.map((i) => i.message).join(' ');
}

const unknownSourceName = 'Kaynak belirtilmemiş';

/// Tek harflik şık mı ("A"–"E")?
bool isChoiceAnswer(String? s) => s != null && const {'A', 'B', 'C', 'D', 'E'}.contains(s);
