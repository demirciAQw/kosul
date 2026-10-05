import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/curriculum_data.dart';
import 'domain/curriculum.dart';

final curriculumRepositoryProvider = Provider<CurriculumRepository>(
    (ref) => DriftCurriculumRepository(ref.watch(appDatabaseProvider)));

final curriculumProvider = StreamProvider<List<CurriculumNode>>(
    (ref) => ref.watch(curriculumRepositoryProvider).watchAll());
