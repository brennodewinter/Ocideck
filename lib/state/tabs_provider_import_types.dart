// De woordenschat van het importpad: hoe een poging afliep, en wat er te
// melden valt als hij geweigerd werd.
//
// Deze twee horen bij elkaar en niet bij de tabbladlogica — de shell leest ze,
// de flows in `tabs_provider.dart` en zijn part-extensies geven ze terug. Ze
// staan hier apart zodat de notifier zelf over tabbladen gaat en niet ook nog
// de uitkomsttypen van het importeren draagt.

part of 'tabs_provider.dart';

/// How a single open/import attempt ended. Used by the import flows to decide
/// whether to clean up downloaded/extracted files and what to report.
enum OpenResult {
  /// The deck was opened in a tab.
  opened,

  /// The file could not be read or parsed (missing, over-size, corrupt).
  unreadable,

  /// The file is not a Marp/OciDeck presentation — readable, but not a deck.
  /// Kept distinct from [unreadable] so the UI can say so specifically.
  notAPresentation,

  /// The file was refused because it contains executable content; the security
  /// alarm has been raised via [importSecurityAlarmProvider].
  blocked,

  /// The package is encrypted and the user cancelled the password prompt (or no
  /// resolver was available). Handled silently — no error is surfaced.
  passwordCancelled,
}

/// A blocked import surfaced to the UI: the offending file plus what was found.
/// The shell listens on [importSecurityAlarmProvider] and shows the alarm.
class ImportSecurityAlarm {
  final String path;
  final List<MarkdownSafetyFinding> findings;
  const ImportSecurityAlarm({required this.path, required this.findings});
}
