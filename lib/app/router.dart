import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/home/home_screen.dart';
import '../features/planning/presentation/create_plan_screen.dart';
import '../features/planning/presentation/plan_screen.dart';
import '../features/question_bank/presentation/question_prefill.dart';
import '../features/question_bank/presentation/screens/add_question_screen.dart';
import '../features/question_bank/presentation/screens/notebook_screen.dart';
import '../features/question_bank/presentation/screens/question_detail_screen.dart';
import '../features/question_bank/presentation/screens/review_screen.dart';
import '../features/study_session/presentation/screens/active_session_screen.dart';
import '../features/study_session/presentation/screens/session_results_screen.dart';
import '../features/study_session/presentation/screens/session_setup_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.plan, builder: (context, state) => const PlanScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.notebook, builder: (context, state) => const NotebookScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.insights, builder: (context, state) => const DashboardScreen()),
          ]),
        ],
      ),
      // Tam ekran sayfalar: alt çubuğun üstünde açılır.
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
        path: '/questions/:id',
        builder: (context, state) => QuestionDetailScreen(cardId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.newPlan, builder: (context, state) => const CreatePlanScreen()),
      GoRoute(path: AppRoutes.review, builder: (context, state) => const ReviewScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
