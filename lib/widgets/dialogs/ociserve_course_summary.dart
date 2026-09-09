import '../../models/ociserve_models.dart';

class OciServeCourseSummary {
  const OciServeCourseSummary({
    required this.versionId,
    required this.title,
    required this.imageHash,
    required this.lessons,
    required this.states,
  });

  final String versionId;
  final String title;
  final String imageHash;
  final List<OciServeFeedItem> lessons;
  final Map<String, OciServeLessonState> states;

  factory OciServeCourseSummary.from(
    String versionId,
    List<OciServeFeedItem> source,
    Map<String, OciServeLessonState> progressByLesson, {
    required String fallbackTitle,
  }) {
    final lessons = [...source]
      ..sort((a, b) => a.lessonOrder.compareTo(b.lessonOrder));
    return OciServeCourseSummary(
      versionId: versionId,
      title: lessons.first.courseTitle.isEmpty
          ? fallbackTitle
          : lessons.first.courseTitle,
      imageHash: lessons.first.courseImageHash,
      lessons: lessons,
      states: {
        for (final lesson in lessons)
          lesson.lessonId:
              ?progressByLesson[_progressKey(versionId, lesson.lessonId)],
      },
    );
  }

  int get done => lessons
      .where((lesson) => states[lesson.lessonId]?.completed == true)
      .length;
  bool get completed => done == lessons.length;
  bool get started => lessons.any((lesson) => states[lesson.lessonId] != null);
  double get fraction => lessons.isEmpty ? 0 : done / lessons.length;
  Duration get displayed => Duration(
    milliseconds: states.values.fold(
      0,
      (total, state) => total + state.displayedMilliseconds,
    ),
  );
  OciServeFeedItem get nextLesson {
    if (completed) return lessons.first;
    return lessons.firstWhere(
      (lesson) {
        final state = states[lesson.lessonId];
        return state?.lastSlideAnchor != null && state?.completed != true;
      },
      orElse: () => lessons.firstWhere(
        (lesson) => states[lesson.lessonId]?.completed != true,
      ),
    );
  }

  int get nextLessonNumber => lessons.indexOf(nextLesson) + 1;

  static int compareForStudentOverview(
    OciServeCourseSummary a,
    OciServeCourseSummary b,
  ) {
    final status = _statusOrder(a).compareTo(_statusOrder(b));
    if (status != 0) return status;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  static int _statusOrder(OciServeCourseSummary course) {
    if (course.completed) return 2;
    return course.started ? 0 : 1;
  }

  static String _progressKey(String versionId, String lessonId) =>
      '$versionId\u0000$lessonId';
}
