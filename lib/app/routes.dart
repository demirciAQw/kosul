abstract final class AppRoutes {
  // Alt gezinme sekmeleri
  static const home = '/';
  static const plan = '/plan';
  static const notebook = '/notebook';
  static const insights = '/insights';

  // Tam ekran sayfalar
  static const newSession = '/session/new';
  static const activeSession = '/session/active';
  static String sessionResults(String id) => '/session/$id/results';
  static const newQuestion = '/questions/new';
  static String question(String id) => '/questions/$id';
  static const newPlan = '/plan/new';
  static const review = '/review';
}
