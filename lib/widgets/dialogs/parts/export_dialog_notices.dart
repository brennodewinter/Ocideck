// Part of the export_dialog library — see ../export_dialog.dart.
//
// De drie meldingen die de gebruiker moet zien vóórdat hij op een formaatknop
// drukt: welke twee bestanden er naast de export komen te staan, wat de
// redactie wél en niet weghaalt, en dat ongecontroleerde AI-tekst in het
// bestand wordt aangekondigd.
//
// Afgesplitst toen `export_dialog.dart` tegen het plafond van 1000 regels liep.
// Niet willekeurig geknipt: dit is één onderwerp — wat er met dit bestand
// meegaat zodra het weggaat. `build` en alles wat `setState` aanroept blijft
// bewust in het hoofdbestand: dat is beschermd en niet vanuit een extensie te
// gebruiken.
part of '../export_dialog.dart';

extension _ExportDialogNotices on _ExportDialogState {
  /// De twee bestanden die naast de export komen te staan, bij naam.
  ///
  /// Dit stond nergens. OciDeck schreef `…-redaction-keys.json` in dezelfde map
  /// als het rapport — op web in dezelfde downloadmap — zónder er iets over te
  /// zeggen: geen tekst in de interface, geen regel in de handleiding. Met de
  /// salts uit dat bestand is elk weggelakt BSN in seconden terug te rekenen,
  /// dus wie het per ongeluk meestuurt, heft zijn eigen redactie op. Een
  /// waarborg waar je overheen kunt kijken omdat niemand hem noemt, is geen
  /// waarborg.
  ///
  /// Alleen tonen wanneer er werkelijk een manifest komt: een waarschuwing bij
  /// een export zonder redacties is ruis, en ruis leert de gebruiker om deze
  /// hele alinea over te slaan.
  Widget _manifestNotice(AppLocalizations l10n) {
    if (_bundle.manifest.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(fontSize: 11, color: AppTheme.slate400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Naast de export komen twee bestanden te staan waarmee een ontvanger de redacties kan natrekken.',
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '…$kRedactionManifestSuffix — '
            '${l10n.d('somt op wat er is weggelaten, zonder de waarden zelf. Dit bestand mag met het rapport mee.')}',
            style: style,
          ),
          if (_bundle.manifest.carriesSalts) ...[
            const SizedBox(height: 2),
            Text(
              '…$kRedactionKeysSuffix — '
              '${l10n.d('bevat de sleutels waarmee elke weggelakte waarde is terug te rekenen. Stuur dit bestand niet mee: dan is de redactie ongedaan gemaakt. Bewaar het bij de bron.')}',
              // Themabewust: in het donkere thema is amber700 op donkergrijs
              // niet te lezen, en dit is juist de regel die gelezen moet worden.
              style: style.copyWith(
                color: AppTheme.warningFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// De grens, op het moment van delen.
  ///
  /// Deze regel staat er **altijd**, en juist het stille geval is de reden. Een
  /// deck met bevindingen waarschuwt zichzelf al; een deck zonder bevindingen
  /// toont een groen "Klaar voor export — geen kwaliteitsproblemen gevonden", en
  /// dát leest als "schoon". Terwijl het niet meer zegt dan: wij hebben niets
  /// gevonden. Wie op die aanname deelt, is slechter af dan wie helemaal geen
  /// controle had — dan had hij tenminste zelf gekeken.
  Widget _privacyCaveat(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      l10n.d(
        'De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.',
      ),
      style: TextStyle(
        fontSize: 11,
        color: AppTheme.slate500,
        fontStyle: FontStyle.italic,
      ),
    ),
  );

  /// Wat er met ongecontroleerde AI-tekst gebeurt zodra dit bestand weggaat.
  ///
  /// Exporteren blijft mogelijk — verzegelen is een verklaring en blijft
  /// geblokkeerd, maar de normale weg om iets nagekeken te krijgen is het naar
  /// een reviewer sturen. Wél verandert er dan iets aan het bestand: het draagt
  /// de melding in zijn eigenschappen, in de HTML een balk, en `-ai-concept` in
  /// de naam. Dat hoort de auteur te weten vóórdat hij op een formaatknop
  /// drukt, om dezelfde reden als bij `-geredigeerd`: een verandering aan de
  /// bestandsnaam die je pas achteraf ziet, is een verrassing.
  Widget _aiDraftNotice(AppLocalizations l10n) {
    if (!ExportDocumentMetadata.fromDeck(_bundle.audience).hasUnreviewedAi) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 15, color: AppTheme.slate400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.d(
                'Er staat AI-tekst in dit deck die je nog niet hebt nagekeken. Exporteren kan; het bestand meldt dat dan zelf en krijgt "-ai-concept" in de naam.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ),
        ],
      ),
    );
  }
}
