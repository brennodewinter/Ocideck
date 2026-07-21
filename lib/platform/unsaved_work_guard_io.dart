/// Desktop/mobiel: geen `beforeunload`, en geen behoefte eraan.
///
/// `windowManager` houdt het venster al tegen (`setPreventClose`), en de shell
/// vraagt in `onWindowClose` of het werk eerst opgeslagen moet worden. Zie
/// `unsaved_work_guard.dart` voor waarom de webkant dit wél nodig heeft.
void setUnsavedWorkGuard(bool hasUnsavedWork) {}
