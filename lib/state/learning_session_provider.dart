import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/learning_session.dart';

/// Learning identity of the current tab.
///
/// Overridden by the tab scope. A root read deliberately yields null so course
/// progress can never be attached to another tab by accident.
final learningSessionProvider = Provider<LearningSessionRef?>((ref) => null);
