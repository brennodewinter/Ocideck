import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/export_block_localization.dart';
import '../../services/download_delivery.dart';
import '../../models/privacy_disposition.dart';
import '../../services/classification_policy.dart';
import '../../services/privacy/privacy_export_policy.dart';
import '../../services/risk_quality.dart';
import '../../services/document_export_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../parts/document_export_pdf_support.dart';
import 'dialog_shell.dart';
import 'export_failure_text.dart';

/// Toon de reden wanneer het classificatiebeleid documentexport weigert.
bool documentClassificationAllowed(
  BuildContext context,
  ExportDecision decision,
) {
  if (decision.allowed) return true;
  final l10n = context.l10n;
  showErrorSnackBar(
    ScaffoldMessenger.of(context),
    l10n,
    exportBlockMessage(l10n, decision) ?? '',
  );
  return false;
}

/// Vraag een expliciet privacybesluit vóór een documentexport.
Future<bool> confirmDocumentPrivacyExport(
  BuildContext context,
  PrivacyExportDecision decision,
) async {
  if (decision.allowed) return true;
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        decision.hardBlocked
            ? l10n.d('Export geblokkeerd')
            : l10n.d('Persoonsgegevens in dit document'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${decision.summary.unresolved} ${l10n.d('bevinding(en) zonder keuze.')}',
          ),
          const SizedBox(height: 8),
          Text(
            decision.hardBlocked
                ? l10n.d(
                    'Verwijder de gevonden gegevens uit het document of wijzig de instelling bij Beveiliging.',
                  )
                : l10n.d(
                    'Controleer de inhoud en bevestig bewust dat je deze kopie wilt exporteren.',
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            decision.hardBlocked ? l10n.d('Sluiten') : l10n.t('cancel'),
          ),
        ),
        if (!decision.hardBlocked)
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Toch exporteren')),
          ),
      ],
    ),
  );
  return confirmed == true;
}

/// De risico-exportpoort (#2490): bij blokkerende bevindingen gaat een
/// export niet stil door — de gebruiker bevestigt bewust dat het een
/// onvolledig concept is, of annuleert en herstelt eerst.
Future<bool> confirmRiskQualityExport(
  BuildContext context,
  RiskQualityReport report,
) async {
  if (!report.hasErrors) return true;
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.d('Onbetrouwbare risico-cijfers in export')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${report.errors.length} ${l10n.d('blokkerende bevinding(en):')}',
            ),
            const SizedBox(height: 8),
            for (final f in report.errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'L${f.line}  ${f.message}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.d(
                'Exporteer je toch, dan gaat het bestand als concept met onzekere cijfers uit — open het overzicht om ze eerst te herstellen.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.d('Toch exporteren')),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// De compacte export-dialoog voor een plat-Markdown-**document**
/// (DOCUMENT_MODE.md §11.2). Kiest het **profiel** (Volledig / Geredigeerd) en
/// het **formaat** (`.md` / HTML), en bewoordt eerlijk (§11.5, eis 6) dat dit
/// een *geredigeerde kopie voor een ontvanger* is — niet je byte-getrouwe
/// meester, die alleen **Opslaan** schrijft.
///
/// De dialoog raakt de bron niet zelf aan: het echte bouwen-en-wegschrijven
/// (langs `buildDocumentExportBundle → AudienceDeck`) zit in [onExport], die de
/// documenteditor meelevert en het geschreven pad teruggeeft. Zo blijft de
/// projectiegrens waar hij hoort en blijft deze widget puur presentatie.
class DocumentExportDialog extends StatefulWidget {
  /// Bouwt en schrijft de export voor het gekozen profiel en formaat, en
  /// geeft de uitkomst terug — geschreven mét waarschuwingen, geannuleerd,
  /// geweigerd mét reden, of mislukt (#2467).
  final Future<DocumentExportOutcome> Function(
    PrivacyExportProfile,
    DocumentExportFormat,
  )
  onExport;

  /// Of de privacycontrole tijdens het bewerken aanstaat. Documentexport
  /// controleert de inhoud alsnog tegen de exportregel.
  final bool privacyChecksEnabled;

  const DocumentExportDialog({
    super.key,
    required this.onExport,
    required this.privacyChecksEnabled,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<DocumentExportOutcome> Function(
      PrivacyExportProfile,
      DocumentExportFormat,
    )
    onExport,
    required bool privacyChecksEnabled,
  }) => showDialog(
    context: context,
    builder: (_) => DocumentExportDialog(
      onExport: onExport,
      privacyChecksEnabled: privacyChecksEnabled,
    ),
  );

  @override
  State<DocumentExportDialog> createState() => _DocumentExportDialogState();
}

class _DocumentExportDialogState extends State<DocumentExportDialog> {
  /// Voor de opdrachtgever is volledig de standaard: alleen wat je zelf op
  /// "weglaten" zette gaat eruit. Dezelfde standaard als de deck-export.
  PrivacyExportProfile _profile = PrivacyExportProfile.full;
  DocumentExportFormat _format = DocumentExportFormat.md;

  bool _busy = false;
  DocumentExportOutcome? _outcome;
  String? _failure;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    DocumentExportOutcome? outcome;
    String? failure;
    try {
      outcome = await widget.onExport(_profile, _format);
    } catch (error) {
      // Benoemd en niet kaal, en breder dan `on Exception`: de bestandskiezer
      // op web gooit een `ArgumentError`, en dat is een `Error` — een vangst op
      // `Exception` had hem laten lopen en de knop alsnog laten draaien.
      // Zónder deze vangst blijft de knop eeuwig draaien. Precies wat er op web
      // gebeurt: de bestandskiezer daar kan geen pad kiezen zonder de bytes al
      // te hebben en gooit een `ArgumentError`, en dan komt `setState` hieronder
      // nooit. Een export die niet lukt hoort dat te zeggen, niet te blijven
      // hangen.
      failure = error.toString();
      logError('DocumentExport: export mislukt', error);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Geannuleerd is geen toestand om te tonen: de gebruiker koos zelf om
      // weg te klikken, dus de opties blijven gewoon staan (#2467).
      _outcome = outcome is DocumentExportCancelled ? null : outcome;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OciDialogShell(
      width: 560,
      height: 620,
      maxWidth: 620,
      maxHeight: 720,
      child: OciDialogScaffold(
        title: l10n.d('Document exporteren'),
        leading: const Icon(Icons.ios_share_outlined),
        body: SingleChildScrollView(
          child: _outcome is DocumentExportWritten
              ? _resultView(l10n, _outcome as DocumentExportWritten)
              : _optionsView(l10n),
        ),
        actions: _outcome is DocumentExportWritten
            ? [
                if (!deliversByDownload)
                  TextButton.icon(
                    onPressed: _openWritten,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.d('Openen')),
                  ),
                TextButton(
                  onPressed: () => setState(() => _outcome = null),
                  child: Text(l10n.d('Nog een export')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.t('close')),
                ),
              ]
            : [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(l10n.t('cancel')),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share, size: 16),
                  label: Text(l10n.d('Exporteren…')),
                ),
              ],
      ),
    );
  }

  Widget _optionsView(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Eerlijke bewoording (§11.5, eis 6): dit is een kopie voor een
        // ontvanger, niet de meester. Alleen Opslaan schrijft die.
        _honestNote(l10n),
        const SizedBox(height: 12),
        _profileSelector(l10n),
        const SizedBox(height: 12),
        _formatSelector(l10n),
        if (_failure != null) ...[
          const SizedBox(height: 12),
          _failureNote(l10n, _failure!),
        ],
        if (_outcome is DocumentExportRefused) ...[
          const SizedBox(height: 12),
          _refusalNote(l10n, _outcome as DocumentExportRefused),
        ],
        if (_outcome is DocumentExportFailed) ...[
          const SizedBox(height: 12),
          _failureNote(
            l10n,
            l10n.d(
              'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.',
            ),
          ),
        ],
      ],
    );
  }

  /// De export kon niet naar het gekozen doel. De gebruiker ziet nú pas waarom
  /// — eerder verdween zo'n weigering als een zwijgende `null` (#2467).
  Widget _refusalNote(AppLocalizations l10n, DocumentExportRefused refused) {
    final text = switch (refused.reason) {
      DocumentExportRefusal.sourceIsTarget => l10n.d(
        'Dat doel is je brondocument zelf. Een export is een kopie voor een ontvanger — het origineel wordt nooit overschreven. Kies een andere naam of map.',
      ),
      DocumentExportRefusal.classificationBlocked => l10n.d(
        'Deze export is geblokkeerd door de classificatie-instellingen.',
      ),
      DocumentExportRefusal.privacyBlocked => l10n.d(
        'Deze export is geblokkeerd door de privacy-exportregel.',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: AppTheme.slate700),
      ),
    );
  }

  /// Het geschreven bestand openen in de systeemviewer (desktop alleen; op web
  /// leverde de browser de download al af). De knop is er voor wie het
  /// resultaat meteen wil controleren in plaats van het pad te onthouden.
  Future<void> _openWritten() async {
    final outcome = _outcome;
    if (outcome is! DocumentExportWritten) return;
    try {
      await launchUrl(Uri.file(outcome.path));
    } on Exception catch (e) {
      logWarning('DocumentExport: openen van ${outcome.path} mislukt', e);
    }
  }

  /// Zegt dat het niet gelukt is, en wat de gebruiker nu kan doen.
  ///
  /// De technische reden staat erbij maar niet vooraan: die is voor wie hem
  /// nodig heeft, en de eerste zin is voor wie gewoon verder wil.
  Widget _failureNote(AppLocalizations l10n, String detail) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.warningBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'De export is niet gelukt. Je document is niet gewijzigd; probeer het opnieuw of kies een ander formaat.',
          ),
          style: TextStyle(fontSize: 11.5, color: AppTheme.warningFg),
        ),
        const SizedBox(height: 4),
        SelectableText(
          detail,
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate500),
        ),
      ],
    ),
  );

  Widget _honestNote(AppLocalizations l10n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.infoBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 15, color: AppTheme.slate600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.d(
              'Exporteren maakt een geredigeerde kopie voor een ontvanger. Je byte-getrouwe origineel bewaar je met Opslaan.',
            ),
            style: TextStyle(fontSize: 11.5, color: AppTheme.slate700),
          ),
        ),
      ],
    ),
  );

  Widget _profileSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Voor wie is deze export?'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SegmentedButton<PrivacyExportProfile>(
          segments: [
            ButtonSegment(
              value: PrivacyExportProfile.full,
              label: Text(l10n.d('Volledig')),
              icon: const Icon(Icons.lock_open_outlined, size: 15),
            ),
            ButtonSegment(
              value: PrivacyExportProfile.redacted,
              label: Text(l10n.d('Geredigeerd')),
              icon: const Icon(Icons.visibility_off_outlined, size: 15),
            ),
          ],
          selected: {_profile},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => setState(() => _profile = s.first),
        ),
        const SizedBox(height: 4),
        Text(
          _profile == PrivacyExportProfile.full
              ? l10n.d(
                  'Voor de opdrachtgever of auditor: alleen wat je zelf op "weglaten" hebt gezet, gaat eruit. De rest blijft leesbaar.',
                )
              : l10n.d(
                  'Voor de bredere kring: alles wat de controle vindt gaat eruit. Het bestand krijgt "-geredigeerd" in de naam.',
                ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        if (!widget.privacyChecksEnabled) ...[
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'De privacycontrole staat uit bij Beveiliging. Documentexport controleert de inhoud wel tegen de exportregel.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.warningFg),
          ),
        ],
      ],
    );
  }

  Widget _formatSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Welk formaat?'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // Een rooster van tegels, geen keuzechips: zeven formaten worden zo
        // gelijkmatige kaarten met icoon en naam die netjes afbreken naar
        // meerdere regels. De tegels hebben een vaste breedte en de label
        // breekt erin af, dus een langere vertaling of 200% tekstgrootte maakt
        // de tegel hoger in plaats van breder — geen vaste breedte die ergens
        // knelt. `Wrap` centreert de tegels, zodat een onvolutte laatste regel
        // (zeven is oneven) er niet uitzakt.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _formatOptions)
              _FormatTile(
                label: l10n.d(option.label),
                icon: option.icon,
                selected: _format == option.format,
                onTap: () => setState(() => _format = option.format),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(switch (_format) {
          DocumentExportFormat.md => l10n.d(
            'Een geredigeerde kopie van de platte tekst — opent in elke Markdown-lezer.',
          ),
          DocumentExportFormat.html => l10n.d(
            'Eén toegankelijk HTML-bestand dat in elke browser opent zonder internet, met tabellen, wiskunde, mermaid en grafieken.',
          ),
          DocumentExportFormat.pdf => l10n.d(
            'Een PDF met echte tekst: te selecteren, te doorzoeken en voor te lezen, met de koppen als bladwijzers. Formules, mermaid-diagrammen en grafieken worden getekend; noten staan achterin.',
          ),
          DocumentExportFormat.latex => l10n.d(
            'Een LaTeX article-document. Wiskunde gaat rechtstreeks door; afbeeldingen worden op relatief pad gereferentieerd. Compileer met pdflatex of xelatex.',
          ),
          DocumentExportFormat.epub => l10n.d(
            'Een ePub 3 met herflowbare tekst voor e-readers, tablets en telefoons. Koppen worden navigatie, noten staan achterin.',
          ),
          DocumentExportFormat.odt => l10n.d(
            'Een ODT (OpenDocument Text) die opent in LibreOffice of Word. Bewerkbaar, met native voetnoten en koppen als outline. Het open tegenhanger van een Word-bestand.',
          ),
          DocumentExportFormat.docx => l10n.d(
            'Een Word-document (.docx) dat opent in Word, Pages en LibreOffice. Bewerkbaar, met native voetnoten en koppen als outline. Mermaid-diagrammen worden als hoogwaardige afbeeldingen ingebed.',
          ),
        }, style: TextStyle(fontSize: 11, color: AppTheme.slate400)),
      ],
    );
  }

  Widget _resultView(AppLocalizations l10n, DocumentExportWritten written) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppTheme.successFg, size: 36),
          const SizedBox(height: 12),
          SelectableText(
            '${exportDeliveryLabel(l10n)}\n${written.path}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.successFg),
          ),
          // De bouwwaarschuwingen horen blijvend bij het resultaat — het
          // bestand staat er, maar "geëxporteerd" mag niet als "gecontroleerd"
          // worden gelezen (#2467).
          if (written.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final warning in written.warnings) _warningNote(l10n, warning),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final copied = l10n.d('Gekopieerd');
              await Clipboard.setData(ClipboardData(text: written.path));
              if (!mounted) return;
              messenger.showSnackBar(SnackBar(content: Text(copied)));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.d('Kopiëren')),
          ),
        ],
      );

  Widget _warningNote(AppLocalizations l10n, DocumentExportWarning warning) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.warningBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 15,
              color: AppTheme.warningFg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(switch (warning) {
                DocumentExportUnsupportedCharacters(:final runes) =>
                  unsupportedCharactersMessage(l10n, runes),
                DocumentExportCoarseLogo(:final logo) => coarseLogoMessage(
                  l10n,
                  logo,
                ),
                DocumentExportTablesTooWide(:final count) =>
                  tablesTooWideMessage(l10n, count),
              }, style: TextStyle(fontSize: 11.5, color: AppTheme.warningFg)),
            ),
          ],
        ),
      );
}

/// Eén keuze in de formaatkiezer.
///
/// Als lijst en niet als reeks `ChoiceChip`-regels, zodat de volgorde en de
/// bewoording op één plek staan — de dialoog leest hem gewoon af.
class _FormatOption {
  const _FormatOption(this.format, this.label, this.icon);

  final DocumentExportFormat format;

  /// De Nederlandse brontekst; de dialoog haalt er de vertaling bij.
  final String label;
  final IconData icon;
}

/// Een formaat-tegel in het rooster: icoon boven, naam eronder, geselecteerd =
/// accentrand en lichte accenttint.
///
/// Dezelfde accenttints als de categoriepillen in `add_slide_dialog_pills.dart`,
/// zodat de keuzes voelen als hetzelfde oppervlak in plaats van import-Material
/// chrome. `InkWell` maakt hem toetsenbord-toegankelijk (focus + Enter), en
/// `Semantics` meldt de gekozen staat aan de schermlezer.
///
/// Vaste breedte: in een `scrollable` AlertDialog ligt de inhoud in een
/// `IntrinsicWidth`, die een `LayoutBuilder` niet toelaat. De vaste breedte is
/// geen probleem voor lange talen: de label breekt binnen de tegel af, de tegel
/// wordt hoger in plaats van breder.
class _FormatTile extends StatelessWidget {
  static const double width = 124;

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FormatTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: accent.withValues(alpha: 0.06),
        focusColor: accent.withValues(alpha: 0.14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : AppTheme.slate50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : AppTheme.slate200,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? AppTheme.accentFg : AppTheme.slate500,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppTheme.accentFg : AppTheme.slate700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// De formaten in de volgorde waarin ze worden aangeboden: eerst de platte
/// tekst waar het hele product op staat, dan wat een ontvanger leest — HTML,
/// PDF, ePub, ODT — dan de zetweg voor wie zelf verder wil.
const _formatOptions = [
  _FormatOption(
    DocumentExportFormat.md,
    'Markdown (.md)',
    Icons.description_outlined,
  ),
  _FormatOption(DocumentExportFormat.html, 'HTML', Icons.public_outlined),
  _FormatOption(DocumentExportFormat.pdf, 'PDF', Icons.picture_as_pdf_outlined),
  _FormatOption(
    DocumentExportFormat.epub,
    'ePub (.epub)',
    Icons.menu_book_outlined,
  ),
  _FormatOption(DocumentExportFormat.odt, 'ODT (.odt)', Icons.article_outlined),
  _FormatOption(
    DocumentExportFormat.docx,
    'Word (.docx)',
    Icons.file_copy_outlined,
  ),
  _FormatOption(
    DocumentExportFormat.latex,
    'LaTeX (.tex)',
    Icons.science_outlined,
  ),
];

/// Waarschuwt dat een kale `.md`- of `.tex`-download de verwijzingen naar
/// losse bestanden niet meeneemt, en vraagt of de gebruiker toch wil doorgaan
/// (DOCUMENT_MODE.md §11.4). De spiegel van de bevestiging die deck-opslag op
/// web al had: geen blokkade — een tekstueel bestand kan bewust de bedoeling
/// zijn — maar nooit stilzwijgend.
Future<bool?> confirmDocumentExportWebAssetLoss(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Afbeeldingen en grafiekdata gaan niet mee')),
      content: Text(
        // Eén stringliteral: de l10n-extractie leest naast-elkaar-geplaatste
        // literals als losse sleutels, en dan matcht de vertaling niet.
        // ignore: lines_longer_than_80_chars
        l10n.d(
          'Dit document verwijst naar afbeeldingen of grafiekdata in losse bestanden. Een kale .md- of .tex-download bevat alleen de tekst — bij de ontvanger zijn de verwijzingen dood. Kies HTML, PDF of DOCX om alles in één bestand te leveren, of ga door als alleen de tekst telt.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.d('Annuleren')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.d('Doorgaan')),
        ),
      ],
    ),
  );
}
