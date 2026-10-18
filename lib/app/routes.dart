abstract final class AppRoutes {
  // Alt gezinme sekmeleri
  static const home = '/';
  static const books = '/books';
  static const notebook = '/notebook';
  static const mockExams = '/mock';
  static const insights = '/insights';

  // Tam ekran sayfalar
  static const newSession = '/session/new';
  static const activeSession = '/session/active';
  static String sessionResults(String id) => '/session/$id/results';
  static const newQuestion = '/questions/new';
  static const incompleteQuestions = '/questions/incomplete';
  static String question(String id) => '/questions/$id';
  static String editQuestion(String id) => '/questions/$id/edit';
  static const plan = '/plan';
  static const newPlan = '/plan/new';
  static const sessions = '/sessions';
  static const newNote = '/notes/new';
  static String note(String id) => '/notes/$id';
  static String book(String id) => '/books/$id';
  static String bookTest(String bookId, String nodeId) => '/books/$bookId/tests/$nodeId';
  static const review = '/review';
  static const newMockExam = '/mock/new';
  static const karneImport = '/mock/karne';
  static String mockExam(String id) => '/mock/$id';
  static String editMockExam(String id) => '/mock/$id/edit';
}
