import 'dart:convert';
import 'dart:typed_data';

import '../../../core/export/zip_writer.dart';
import '../../../core/media/media_storage.dart';
import '../../library/data/models/book_template_model.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../notes/domain/notes.dart';
import '../../planning/domain/planning.dart';
import '../../question_bank/data/question_card_json.dart';
import '../../question_bank/domain/question_card.dart';
import '../../study_session/domain/study_session.dart';

String? _iso(DateTime? d) => d?.toIso8601String();

/// Uygulamadaki her şey tek JSON'da. Fotoğraf yolları medya köküne göre
/// göreli; ZIP içinde "media/<yol>" olarak durur.
Map<String, dynamic> fullDataJson({
  required DateTime now,
  required List<QuestionCard> cards,
  required List<Book> books,
  required Map<String, TestResult> results,
  required List<StudySession> sessions,
  required List<MockExam> exams,
  required List<StudyPlan> plans,
  required List<StudyNote> notes,
}) =>
    {
      'format': 'kocum.backup',
      'version': 1,
      'exportedAt': now.toIso8601String(),
      'counts': {
        'questions': cards.length,
        'books': books.length,
        'testResults': results.length,
        'sessions': sessions.length,
        'mockExams': exams.length,
        'plans': plans.length,
        'notes': notes.length,
      },
      'questions': [for (final c in cards) c.toJson()],
      'books': [
        for (final b in books) {'id': b.id, 'createdAt': _iso(b.createdAt), ...BookTemplateModel.fromEntity(b).toJson()},
      ],
      'testResults': [
        for (final r in results.values)
          {
            'nodeId': r.nodeId,
            'bookId': r.bookId,
            'solvedAt': _iso(r.solvedAt),
            'correct': r.correct,
            'wrong': r.wrong,
            'blank': r.blank,
            'total': r.total,
            'sessionId': r.sessionId,
          },
      ],
      'sessions': [
        for (final s in sessions)
          {
            'id': s.id,
            'status': s.status.name,
            'startedAt': _iso(s.startedAt),
            'endedAt': _iso(s.endedAt),
            'items': [
              for (final i in s.items)
                {
                  'id': i.id,
                  'label': i.label,
                  'subject': i.subject,
                  'bookId': i.bookId,
                  'contentNodeId': i.contentNodeId,
                  'mebNodeId': i.mebNodeId,
                  'pages': i.pages,
                  'activity': i.activity?.name,
                  'estimatedQuestions': i.estimatedQuestions,
                  'correct': i.correct,
                  'wrong': i.wrong,
                  'blank': i.blank,
                },
            ],
          },
      ],
      'mockExams': [
        for (final e in exams)
          {
            'id': e.id,
            'title': e.title,
            'kind': e.kind.name,
            'takenOn': _iso(e.takenOn),
            'createdAt': _iso(e.createdAt),
            'durationMinutes': e.durationMinutes,
            'note': e.note,
            'sections': [
              for (final s in e.sections)
                {
                  'subject': s.subject,
                  'questionCount': s.questionCount,
                  'correct': s.correct,
                  'wrong': s.wrong,
                  'blank': s.blank,
                },
            ],
          },
      ],
      'plans': [
        for (final p in plans)
          {
            'id': p.id,
            'title': p.title,
            'startsOn': _iso(p.startsOn),
            'endsOn': _iso(p.endsOn),
            'createdAt': _iso(p.createdAt),
            'completedAt': _iso(p.completedAt),
            'tasks': [
              for (final t in p.tasks)
                {
                  'title': t.title,
                  'bookId': t.bookId,
                  'contentNodeId': t.contentNodeId,
                  'targetQuestions': t.targetQuestions,
                  'isDone': t.isDone,
                },
            ],
          },
      ],
      'notes': [
        for (final n in notes)
          {
            'id': n.id,
            'subject': n.subject,
            'title': n.title,
            'body': n.body,
            'isPinned': n.isPinned,
            'createdAt': _iso(n.createdAt),
            'updatedAt': _iso(n.updatedAt),
            'photos': n.photos,
          },
      ],
    };

/// Yedek ZIP: kocum_yedek.json + media/… (soru, çözüm ve not fotoğrafları).
/// [withPhotos] kapalıysa yalnızca JSON.
Future<({Uint8List bytes, int photos, int missing})> buildFullExportZip({
  required Map<String, dynamic> data,
  required List<QuestionCard> cards,
  required List<StudyNote> notes,
  required MediaStorage media,
  bool withPhotos = true,
  Map<String, List<int>> extraFiles = const {},
}) async {
  final zip = ZipWriter()..addText('kocum_yedek.json', const JsonEncoder.withIndent(' ').convert(data));
  // Uygulamanın kendi tuttuğu veri setleri (ör. arama kayıtları).
  for (final e in extraFiles.entries) {
    zip.add(e.key, e.value);
  }
  var photos = 0, missing = 0;
  if (withPhotos) {
    final paths = <String>{
      for (final c in cards) ...[c.questionImage, c.solutionImage].whereType<String>(),
      for (final n in notes) ...n.photos,
    };
    for (final p in paths) {
      final f = media.resolve(p);
      if (await f.exists()) {
        zip.add('media/$p', await f.readAsBytes());
        photos++;
      } else {
        missing++;
      }
    }
  }
  return (bytes: zip.finish(), photos: photos, missing: missing);
}
