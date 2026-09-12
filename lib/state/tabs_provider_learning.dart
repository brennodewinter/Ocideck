part of 'tabs_provider.dart';

final _learningSessionClosers =
    Expando<Future<void> Function(LearningSessionRef)>();

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
}) => _openLearningPackage(
  notifier,
  bytes,
  name,
  learningSession,
  password: password,
  packageProfile: packageProfile,
  initialAnchor: initialAnchor,
);

/// Verwijdert alle leertabbladen lokaal en geeft hun sessies terug.
///
/// Logout en app-afsluiting wachten daarna zelf op server-close. De callback
/// staat hier tijdelijk uit om dubbele best-effort-aanroepen te voorkomen.
List<LearningSessionRef> closeLearningTabsLocally(TabsNotifier notifier) {
  final sessions = notifier.state.tabs
      .map((tab) => tab.learningSession)
      .whereType<LearningSessionRef>()
      .toList(growable: false);
  final closer = _learningSessionClosers[notifier];
  _learningSessionClosers[notifier] = null;
  try {
    for (var index = notifier.state.tabs.length - 1; index >= 0; index--) {
      if (notifier.state.tabs[index].learningSession != null) {
        notifier.closeTab(index);
      }
    }
  } finally {
    _learningSessionClosers[notifier] = closer;
  }
  return sessions;
}
