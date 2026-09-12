part of 'tabs_provider.dart';

final _learningSessionClosers =
    Expando<Future<void> Function(LearningSessionRef)>();
final _learningExpiryTimers = Expando<Map<String, Timer>>();

/// Registreert serverafmelding voor een lokaal al verwijderd OciServe-tabblad.
void setLearningSessionCloser(
  TabsNotifier notifier,
  Future<void> Function(LearningSessionRef)? closer,
) {
  _learningSessionClosers[notifier] = closer;
}

/// Opent een onveranderlijke OciServe-les in een afspeeltabblad.
Future<OpenResult> openLearningPackage(
  TabsNotifier notifier,
  Uint8List bytes,
  String name,
  LearningSessionRef learningSession, {
  required String password,
  required String packageProfile,
  String? initialAnchor,
}) async {
  if (!learningSession.expiresAt.isAfter(DateTime.now().toUtc())) {
    return OpenResult.unreadable;
  }
  final result = await _openLearningPackage(
    notifier,
    bytes,
    name,
    learningSession,
    password: password,
    packageProfile: packageProfile,
    initialAnchor: initialAnchor,
  );
  if (result == OpenResult.opened) {
    _scheduleLearningExpiry(notifier, learningSession);
  }
  return result;
}

void _scheduleLearningExpiry(
  TabsNotifier notifier,
  LearningSessionRef session,
) {
  final timers = _learningExpiryTimers[notifier] ??= {};
  timers.remove(session.playbackSessionId)?.cancel();
  final remaining = session.expiresAt.difference(DateTime.now().toUtc());
  timers[session.playbackSessionId] = Timer(remaining, () {
    timers.remove(session.playbackSessionId);
    final index = notifier.currentState.tabs.indexWhere(
      (tab) =>
          tab.learningSession?.playbackSessionId == session.playbackSessionId,
    );
    if (index >= 0) notifier.closeTab(index);
  });
}

void _cancelLearningExpiry(TabsNotifier notifier, LearningSessionRef? session) {
  if (session == null) return;
  _learningExpiryTimers[notifier]?.remove(session.playbackSessionId)?.cancel();
}

void _cancelAllLearningExpiry(TabsNotifier notifier) {
  for (final timer
      in _learningExpiryTimers[notifier]?.values ?? const <Timer>[]) {
    timer.cancel();
  }
  _learningExpiryTimers[notifier]?.clear();
}

/// Verwijdert alle leertabbladen lokaal en geeft hun sessies terug.
///
/// Logout en app-afsluiting wachten daarna zelf op server-close. De callback
/// staat hier tijdelijk uit om dubbele best-effort-aanroepen te voorkomen.
List<LearningSessionRef> closeLearningTabsLocally(TabsNotifier notifier) {
  final sessions = notifier.currentState.tabs
      .map((tab) => tab.learningSession)
      .whereType<LearningSessionRef>()
      .toList(growable: false);
  final closer = _learningSessionClosers[notifier];
  _learningSessionClosers[notifier] = null;
  try {
    for (
      var index = notifier.currentState.tabs.length - 1;
      index >= 0;
      index--
    ) {
      if (notifier.currentState.tabs[index].learningSession != null) {
        notifier.closeTab(index);
      }
    }
  } finally {
    _learningSessionClosers[notifier] = closer;
  }
  return sessions;
}
