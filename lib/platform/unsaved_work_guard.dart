import 'unsaved_work_guard_io.dart'
    if (dart.library.js_interop) 'unsaved_work_guard_web.dart'
    as impl;

/// Laat het platform weten dat er niet-opgeslagen werk openstaat.
///
/// Op desktop bewaakt `windowManager` het sluiten al: `setPreventClose(true)`
/// levert `onWindowClose`, en de shell vraagt daar of het werk eerst opgeslagen
/// moet worden. Op web bestaat die haak niet — er is geen venster dat de app
/// bezit — en tegelijk is dáár het risico het grootst: crashherstel werkt niet
/// in de browser ([RecoveryService] is er een no-op, want er is geen
/// app-supportmap). Een tabblad dat wegklikt neemt het werk mee.
///
/// De browser biedt daar precies één beheersmaatregel voor: `beforeunload`. De
/// tekst is niet te kiezen (browsers tonen sinds jaren hun eigen zin), dus dit
/// is bewust geen melding maar een rem: de gebruiker krijgt de kans te blijven.
///
/// Op desktop is dit een no-op — de bestaande bewaking is completer, en twee
/// bevestigingen achter elkaar leert niemand iets.
void setUnsavedWorkGuard(bool hasUnsavedWork) =>
    impl.setUnsavedWorkGuard(hasUnsavedWork);
