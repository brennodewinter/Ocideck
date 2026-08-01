/// Waaróm een import mislukte, als een stabiele code die de UI naar een
/// vertaalde melding vertaalt.
///
/// De code en niet de tekst is wat de servicelaag naar buiten draagt: de
/// melding die de gebruiker leest hoort in de taal van de gebruiker, en die
/// keuze zit hier niet — er is geen `BuildContext`. Zelfde afspraak als
/// `WebdavError`, `S3Error` en `GitForgeError`; de vertaling staat in
/// `importFailureText` (lib/utils/user_facing_error.dart).
enum ImportFailureReason {
  /// Groter dan de toegestane invoerlimiet. args: `bestand`, `limiet`.
  tooLarge,

  /// Het appbrede webgeheugen kan de ingebedde media niet meer opnemen.
  memoryBudgetExceeded,

  /// Geen leesbaar zip-archief, of te klein — het is geen presentatie.
  /// args: `bestand`.
  notAPresentation,

  /// Wel een archief, maar beschadigd of onvolledig. args: `bestand`.
  corrupt,

  /// Een herkend formaat dat nog niet wordt ondersteund. args: `bestand`,
  /// `formaat`.
  formatNotSupported,

  /// Leeg: er zaten geen dia's in. args: `bestand`, `formaat`.
  noSlides,

  /// Een onverwachte leesfout — het bestand oogde goed maar liet zich niet
  /// omzetten. args: `bestand`, `formaat`.
  unreadable,

  /// Het gebouwde deck bevat na neutralisatie tóch uitvoerbare inhoud
  /// (`<script>`, een `javascript:`-link) en wordt fail-closed geweigerd — de
  /// import komt niet door dezelfde poort die een vreemd `.md` bij het openen
  /// tegenhoudt (#876). args: `bestand`.
  unsafeContent,

  /// Geen van de bovenstaande; de UI valt terug op een generieke melding en de
  /// vrije [ImportFailure.message] hoort in het log.
  other,
}

/// A recoverable import failure, reported through `Result` rather than thrown.
///
/// [reason] is the stable code the UI turns into a localised message via
/// `importFailureText`; [args] fills the `{naam}`-placeholders in that message
/// (filename, format, size limit). [message] stays as a Dutch technical string
/// for the log — it is never shown to the user directly. [cause] carries the
/// original exception for diagnostics when available.
class ImportFailure {
  const ImportFailure(
    this.message, {
    this.cause,
    this.reason = ImportFailureReason.other,
    this.args = const {},
  });

  final String message;
  final Object? cause;
  final ImportFailureReason reason;
  final Map<String, String> args;

  /// Dezelfde fout met [key] → [value] toegevoegd aan [args].
  ///
  /// De service is de enige uitgang van de import en kent de bestandsnaam; een
  /// importer die diep in het parsen faalt niet. Zo vult de service `bestand`
  /// aan bij een fout die van een importer terugkomt, zonder dat elke importer
  /// die naam hoeft door te geven.
  ImportFailure withArg(String key, String value) => ImportFailure(
    message,
    cause: cause,
    reason: reason,
    args: {...args, key: value},
  );

  @override
  String toString() => message;
}
