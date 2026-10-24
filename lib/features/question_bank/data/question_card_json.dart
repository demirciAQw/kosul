import '../../../core/json/json_reader.dart';
import '../../../core/utils/enum_x.dart';
import '../domain/question_card.dart';

/// Yedekleme/taşıma için JSON sözleşmesi (domain varlığını kirletmeden).
/// Görseller göreli yol olarak yazılır; yedek arşivi `media/` klasörünü de içerir.
extension QuestionCardJson on QuestionCard {
  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.name,
        'origin': origin.name,
        if (questionImage != null) 'questionImage': questionImage,
        if (solutionImage != null) 'solutionImage': solutionImage,
        if (solutionText != null) 'solutionText': solutionText,
        'sourceName': sourceName,
        if (bookId != null) 'bookId': bookId,
        if (contentNodeId != null) 'contentNodeId': contentNodeId,
        if (sessionId != null) 'sessionId': sessionId,
        if (mebNodeId != null) 'mebNodeId': mebNodeId,
        'subject': subject,
        if (testTotalQuestions != null) 'testTotalQuestions': testTotalQuestions,
        if (reason != null) 'reason': reason!.name,
        if (avgSecondsPerQuestion != null) 'avgSecondsPerQuestion': avgSecondsPerQuestion,
        'difficulty': difficulty,
        'isStarred': isStarred,
        if (note != null) 'note': note,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (questionNo != null) 'questionNo': questionNo,
        if (testLabel != null) 'testLabel': testLabel,
        if (mockExamId != null) 'mockExamId': mockExamId,
        if (reasonNote != null) 'reasonNote': reasonNote,
        if (topicText != null) 'topicText': topicText,
        if (correctAnswer != null) 'correctAnswer': correctAnswer,
        if (givenAnswer != null) 'givenAnswer': givenAnswer,
      };
}

QuestionCard questionCardFromJson(Map<String, dynamic> json, {String path = r'$'}) {
  final r = JsonReader(json, path);
  final created = DateTime.tryParse(r.requireString('createdAt'));
  if (created == null) throw JsonFormatException(r.at('createdAt'), 'ISO-8601 tarih bekleniyordu');

  final status = QuestionStatus.values.byNameOrNull(r.requireString('status')) ??
      (throw JsonFormatException(r.at('status'), 'Bilinmeyen durum'));
  final reasonName = r.optString('reason');
  final reason = MistakeReason.values.byNameOrNull(reasonName);
  if (reasonName != null && reason == null) {
    throw JsonFormatException(r.at('reason'), 'Bilinmeyen yanlış nedeni');
  }
  final starred = r.raw['isStarred'];
  if (starred != null && starred is! bool) {
    throw JsonFormatException(r.at('isStarred'), 'true/false bekleniyordu');
  }

  return QuestionCard(
    id: r.requireString('id'),
    status: status,
    origin: QuestionOrigin.values.byNameOr(r.optString('origin'), QuestionOrigin.independent),
    questionImage: r.optString('questionImage'),
    solutionImage: r.optString('solutionImage'),
    solutionText: r.optString('solutionText', maxLength: 10000),
    sourceName: r.requireString('sourceName'),
    bookId: r.optString('bookId'),
    contentNodeId: r.optString('contentNodeId'),
    sessionId: r.optString('sessionId'),
    mebNodeId: r.optString('mebNodeId'),
    subject: r.requireString('subject'),
    testTotalQuestions: r.optInt('testTotalQuestions', min: 1),
    reason: reason,
    avgSecondsPerQuestion: r.raw['avgSecondsPerQuestion'] == null
        ? null
        : r.requireDouble('avgSecondsPerQuestion', min: 0),
    difficulty: r.requireInt('difficulty', min: 1, max: 10),
    isStarred: (starred as bool?) ?? false,
    note: r.optString('note', maxLength: 5000),
    createdAt: created.toLocal(),
    questionNo: r.optInt('questionNo', min: 1),
    testLabel: r.optString('testLabel'),
    mockExamId: r.optString('mockExamId'),
    reasonNote: r.optString('reasonNote'),
    topicText: r.optString('topicText'),
    correctAnswer: r.optString('correctAnswer', maxLength: 500),
    givenAnswer: r.optString('givenAnswer', maxLength: 500),
  );
}
