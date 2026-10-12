import '../domain/question_card.dart';

/// Soru ekleme ekranını bağlamla önceden doldurmak için (ör. oturum sonucundan).
class QuestionPrefill {
  const QuestionPrefill({
    this.origin = QuestionOrigin.book,
    this.status = QuestionStatus.wrong,
    this.sourceName,
    this.bookId,
    this.contentNodeId,
    this.sessionId,
    this.sessionItemId,
    this.mockExamId,
    this.mebNodeId,
    this.subject,
    this.testTotalQuestions,
    this.avgSecondsPerQuestion,
    this.testLabel,
    this.questionNo,
  });

  final QuestionOrigin origin;
  final QuestionStatus status;
  final String? sourceName;
  final String? bookId;
  final String? contentNodeId;
  final String? sessionId;
  final String? sessionItemId;
  final String? mockExamId;
  final String? mebNodeId;
  final String? subject;
  final int? testTotalQuestions;
  final double? avgSecondsPerQuestion;
  final String? testLabel;
  final int? questionNo;
}
