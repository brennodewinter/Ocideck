// Wat het exportvenster toont als een export omvalt — en hoe het de goede
// afloop benoemt.
//
// Los van het venster omdat het pure tekstkeuze is: geen toestand, geen
// widgets, en zo te toetsen zonder een dialoog te openen.
import '../../l10n/app_localizations.dart';
import '../../services/download_delivery.dart';
import '../../services/export_service.dart' show ExportFailure;

/// Het kopje boven de naam van wat er zojuist is opgeleverd.
///
/// Op web is dat geen bestand op een pad maar een download die is *aangeboden*:
/// de pagina kan niet zien of hij in de downloadmap aankwam (#1902). "Geëxpor-
/// teerd naar" beweert daar meer dan we weten, en dat is precies het verschil
/// dat de gebruiker nodig heeft als er niets blijkt te staan.
String exportDeliveryLabel(AppLocalizations l10n) => deliversByDownload
    ? l10n.d('Aangeboden als download:')
    : l10n.t('exportedTo');

/// Waar een export was toen hij omviel.
///
/// De drie stappen falen om verschillende redenen en vragen iets anders van de
/// gebruiker, en er is geen andere manier om ze uit elkaar te houden: alle drie
/// gooien ze een uitzondering uit dezelfde `try`. Zonder dit onderscheid stond
/// er alleen de kale uitzondering in het venster — bij #714 letterlijk
/// `Invalid argument(s): 1`, wat nergens heen wijst.
enum ExportStage {
  /// Voorbereiden en de poorten (classificatie, privacy, kwaliteit).
  preparing,

  /// De dia's naar beeld renderen. Alleen PDF en PPTX komen hier; HTML niet.
  rendering,

  /// Het bestand opbouwen en wegschrijven.
  writing,
}

/// De tekst bij een mislukte export: welke stap het was, wat de gebruiker
/// daaraan kan doen, en pas dán de technische melding.
///
/// De ruwe uitzondering blijft staan — hij is het enige waarmee een fout te
/// vinden is en hij hoort in een foutrapport — maar hij is niet langer de hele
/// boodschap. Zie #714: `Invalid argument(s): 1` als volledige tekst laat de
/// gebruiker met niets achter, en verzwijgt dat de HTML-export van hetzelfde
/// deck wél lukt omdat die niet langs het renderen komt.
String exportFailureText(
  AppLocalizations l10n,
  ExportStage stage,
  Object error,
) {
  final what = switch (stage) {
    ExportStage.preparing => l10n.d(
      'De export is gestopt tijdens het voorbereiden.',
    ),
    ExportStage.rendering => l10n.d(
      'Het renderen van de dia\'s naar beeld is mislukt. Dit ligt aan een dia, niet aan het bestandsformaat: de HTML-export komt hier niet langs en werkt in dit geval meestal wel.',
    ),
    // Bewust niet het woord uit de fase-tekst ("…samenstellen…"): die tekst is
    // in export_dialog_error_test.dart de vlag voor "het dialoog hangt nog", en
    // een foutmelding die hem herhaalt zou die toets stilletjes waardeloos
    // maken.
    ExportStage.writing => l10n.d(
      'Het bestand kon niet worden opgebouwd of weggeschreven. Controleer of er schijfruimte is en of de exportmap beschrijfbaar is.',
    ),
  };
  return '${l10n.d('De export is mislukt.')}\n$what\n\n'
      '${l10n.d('Technische melding:')} $error';
}

/// De tekst bij een export die niet op een uitzondering strandde maar op een
/// beslissing van de dienst.
///
/// De dienst kent de taal van de gebruiker niet en levert daarom de reden en
/// niet de zin (#576); hier wordt er een zin van. Bewust zonder "technische
/// melding": er is geen uitzondering om te tonen, en een lege regel achter het
/// kopje leest als een weggevallen fout.
String exportFailureReasonText(
  AppLocalizations l10n,
  ExportFailure failure,
) => switch (failure) {
  ExportFailure.downloadNotStarted =>
    '${l10n.d('De export is mislukt.')}\n'
        '${l10n.d('De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.')}',
};
