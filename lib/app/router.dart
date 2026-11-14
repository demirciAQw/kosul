import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/anlik/anlik_providers.dart';
import '../features/anlik/presentation/anlik_ekrani.dart';
import '../features/anlik/presentation/etiket_sayfasi.dart';
import '../features/anlik/presentation/graf_ekrani.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/presentation/book_detail_screen.dart';
import '../features/library/presentation/books_screen.dart';
import '../features/library/presentation/test_detail_screen.dart';
import '../features/mock_exam/domain/karne_import.dart';
import '../features/mock_exam/presentation/edit_mock_exam_screen.dart';
import '../features/mock_exam/presentation/karne_import_screen.dart';
import '../features/mock_exam/presentation/mock_exam_detail_screen.dart';
import '../features/mock_exam/presentation/mock_exams_screen.dart';
import '../features/notes/presentation/note_editor_screen.dart';
import '../features/planning/presentation/create_plan_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/sync/presentation/esleme_ekrani.dart';
import '../features/planning/presentation/plan_screen.dart';
import '../features/question_bank/presentation/question_prefill.dart';
import '../features/question_bank/presentation/screens/add_question_screen.dart';
import '../features/question_bank/presentation/screens/incomplete_screen.dart';
import '../features/question_bank/presentation/screens/notebook_screen.dart';
import '../features/question_bank/presentation/screens/question_detail_screen.dart';
import '../features/question_bank/presentation/screens/review_screen.dart';
import '../features/study_session/presentation/screens/active_session_screen.dart';
import '../features/study_session/presentation/screens/session_history_screen.dart';
import '../features/study_session/presentation/screens/session_results_screen.dart';
import '../features/study_session/presentation/screens/session_setup_screen.dart';
import 'app_shell.dart';
import 'routes.dart';
import '../features/tools/presentation/tools_screen.dart';
import '../features/tools/presentation/practice_test_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    // Son açılan mod hatırlanır: Anlık'ta kapatıldıysa Anlık açılır.
    initialLocation: ref.read(baslangictaAnlikProvider) ? AppRoutes.anlik : AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.books, builder: (context, state) => const BooksScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.notebook, builder: (context, state) => const NotebookScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.mockExams, builder: (context, state) => const MockExamsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.insights, builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.tools, builder: (context, state) => const ToolsScreen()),
          ]),
        ],
      ),
      // Tam ekran sayfalar: alt çubuğun üstünde açılır. Sabit yollar (new,
      // incomplete) parametreli yollardan ÖNCE gelmeli.
      GoRoute(path: AppRoutes.newSession, builder: (context, state) => const SessionSetupScreen()),
      GoRoute(path: AppRoutes.activeSession, builder: (context, state) => const ActiveSessionScreen()),
      GoRoute(
        path: '/session/:id/results',
        builder: (context, state) => SessionResultsScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.newQuestion,
        builder: (context, state) => AddQuestionScreen(prefill: state.extra as QuestionPrefill?),
      ),
      GoRoute(
        path: AppRoutes.incompleteQuestions,
        builder: (context, state) => const IncompleteQuestionsScreen(),
      ),
      GoRoute(
        path: '/questions/:id/edit',
        builder: (context, state) => AddQuestionScreen(editCardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/questions/:id',
        builder: (context, state) => QuestionDetailScreen(cardId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.plan, builder: (context, state) => const PlanScreen()),
      GoRoute(path: AppRoutes.newPlan, builder: (context, state) => const CreatePlanScreen()),
      GoRoute(path: AppRoutes.sessions, builder: (context, state) => const SessionHistoryScreen()),
      GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
      GoRoute(
        path: AppRoutes.anlik,
        builder: (context, state) => AnlikEkrani(yaz: state.uri.queryParameters['yaz'] == '1'),
      ),
      GoRoute(
        path: AppRoutes.anlikGraf,
        builder: (context, state) => GrafEkrani(girdi: state.extra as GrafGirdisi? ?? const GrafGirdisi()),
      ),
      GoRoute(
        path: '/anlik/etiket/:id',
        builder: (context, state) => EtiketSayfasi(etiketId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/anlik/a/:id',
        builder: (context, state) => AnlikDuzenleEkrani(anlikId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.kocEsleme, builder: (context, state) => const EslemeEkrani()),
      GoRoute(path: AppRoutes.practiceTest, builder: (context, state) => const PracticeTestScreen()),
      GoRoute(
        path: AppRoutes.newNote,
        builder: (context, state) => NoteEditorScreen(initialSubject: state.extra as String?),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (context, state) => NoteEditorScreen(noteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/books/:id/tests/:nodeId',
        builder: (context, state) => TestDetailScreen(
          bookId: state.pathParameters['id']!,
          nodeId: state.pathParameters['nodeId']!,
        ),
      ),
      GoRoute(
        path: '/books/:id',
        builder: (context, state) => BookDetailScreen(bookId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.review, builder: (context, state) => const ReviewScreen()),
      GoRoute(path: AppRoutes.newMockExam, builder: (context, state) => const EditMockExamScreen()),
      GoRoute(
        path: AppRoutes.karneImport,
        builder: (context, state) => KarneImportScreen(plan: state.extra! as KarneImportPlan),
      ),
      GoRoute(
        path: '/mock/:id/edit',
        builder: (context, state) => EditMockExamScreen(examId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/mock/:id',
        builder: (context, state) => MockExamDetailScreen(examId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
