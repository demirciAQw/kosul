import '../domain/question_card.dart';

/// Soru ekleme ekranını bağlamla önceden doldurmak için (ör. oturum sonucundan).
class QuestionPrefill {
  const QuestionPrefill({
    this.origin = QuestionOrigin.book,
    this.sourceName,
    this.bookId,
    this.contentNodeId,
    this.sessionId,
    this.mebNodeId,
    this.subject,
    this.testTotalQuestions,
    this.avgSecondsPerQuestion,
  });

  final QuestionOrigin origin;
  final String? sourceName;
  final String? bookId;
  final String? contentNodeId;
  final String? sessionId;
  final String? mebNodeId;
  final String? subject;
  final int? testTotalQuestions;
  final double? avgSecondsPerQuestion;
}
