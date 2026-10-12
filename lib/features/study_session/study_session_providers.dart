import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import 'data/study_session_repository_impl.dart';
import 'domain/study_session.dart';

final studySessionRepositoryProvider = Provider<StudySessionRepository>((ref) =>
    DriftStudySessionRepository(ref.watch(appDatabaseProvider), ref.watch(idGeneratorProvider)));

final startStudySessionProvider = Provider(
    (ref) => StartStudySession(ref.watch(studySessionRepositoryProvider), ref.watch(clockProvider)));
final finishStudySessionProvider = Provider(
    (ref) => FinishStudySession(ref.watch(studySessionRepositoryProvider), ref.watch(clockProvider)));
final cancelStudySessionProvider =
    Provider((ref) => CancelStudySession(ref.watch(studySessionRepositoryProvider)));
final submitSessionResultsProvider =
    Provider((ref) => SubmitSessionResults(ref.watch(studySessionRepositoryProvider)));

final runningSessionProvider = StreamProvider<StudySession?>(
    (ref) => ref.watch(studySessionRepositoryProvider).watchRunning());

/// "Eksiklerini doldur" rozetinin kaynağı.
final pendingSessionsProvider = StreamProvider<List<StudySession>>(
    (ref) => ref.watch(studySessionRepositoryProvider).watchAwaitingResults());

final sessionByIdProvider = StreamProvider.family<StudySession?, String>(
    (ref, id) => ref.watch(studySessionRepositoryProvider).watchById(id));
