import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/plan_repository_impl.dart';
import 'domain/planning.dart';

final planRepositoryProvider =
    Provider<PlanRepository>((ref) => DriftPlanRepository(ref.watch(appDatabaseProvider)));

final plansProvider = StreamProvider<List<StudyPlan>>((ref) => ref.watch(planRepositoryProvider).watchPlans());

final createPlanProvider = Provider((ref) => CreatePlan(
      ref.watch(planRepositoryProvider),
      ref.watch(idGeneratorProvider),
      ref.watch(clockProvider),
    ));

final addPlanTasksProvider =
    Provider((ref) => AddPlanTasks(ref.watch(planRepositoryProvider), ref.watch(idGeneratorProvider)));

final editPlanProvider = Provider((ref) => EditPlan(ref.watch(planRepositoryProvider)));
