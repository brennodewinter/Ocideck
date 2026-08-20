import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/privacy_disposition.dart';
import '../../services/document_export_service.dart';
import '../../theme/app_theme.dart';

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
  /// Bouwt en schrijft de export voor het gekozen profiel en formaat, en geeft
  /// het geschreven pad terug (of `null` bij wegklikken van de bestandskiezer of
  /// een fout).
  final Future<String?> Function(PrivacyExportProfile, DocumentExportFormat)
  onExport;

  /// Of de privacycontrole aanstaat. Staat ze uit, dan is een geredigeerde
  /// kopie niet echt op persoonsgegevens nagekeken en zegt de dialoog dat.
  final bool privacyChecksEnabled;

  const DocumentExportDialog({
    super.key,
    required this.onExport,
    required this.privacyChecksEnabled,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<String?> Function(
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
  String? _writtenPath;

  Future<void> _run() async {
    setState(() => _busy = true);
    final path = await widget.onExport(_profile, _format);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _writtenPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.d('Document exporteren')),
      content: SizedBox(
        width: 460,
        child: _writtenPath != null
            ? _resultView(l10n, _writtenPath!)
            : _optionsView(l10n),
      ),
      actions: _writtenPath != null
          ? [
              TextButton(
                onPressed: () => setState(() => _writtenPath = null),
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
      ],
    );
  }

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
              'Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.',
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
        const SizedBox(height: 6),
        // Bewust een Wrap met keuzechips en geen SegmentedButton: vier keuzes
        // passen daar niet meer naast elkaar in de 460 punten van deze dialoog,
        // en al helemaal niet in een taal met langere woorden of bij 200%
        // tekstgrootte. Een Wrap breekt dan gewoon af naar de volgende regel.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in _formatOptions)
              ChoiceChip(
                label: Text(l10n.d(option.label)),
                avatar: Icon(option.icon, size: 15),
                selected: _format == option.format,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _format = option.format),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(switch (_format) {
          DocumentExportFormat.md => l10n.d(
            'Een geredigeerde kopie van de platte tekst — opent in elke Markdown-lezer.',
          ),
          DocumentExportFormat.html => l10n.d(
            'Eén toegankelijk HTML-bestand dat in elke browser opent zonder internet, met tabellen, wiskunde, mermaid en grafieken.',
          ),
          DocumentExportFormat.pdf => l10n.d(
            'Een PDF met echte tekst: te selecteren, te doorzoeken en voor te lezen, met de koppen als bladwijzers. Formules, mermaid-diagrammen en grafieken staan erin als bron; noten staan achterin.',
          ),
          DocumentExportFormat.latex => l10n.d(
            'Een LaTeX article-document. Wiskunde gaat rechtstreeks door; afbeeldingen worden op relatief pad gereferentieerd. Compileer met pdflatex of xelatex.',
          ),
        }, style: TextStyle(fontSize: 11, color: AppTheme.slate400)),
      ],
    );
  }

  Widget _resultView(AppLocalizations l10n, String path) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check_circle, color: AppTheme.successFg, size: 36),
      const SizedBox(height: 12),
      SelectableText(
        '${l10n.t('exportedTo')}\n$path',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppTheme.successFg),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final copied = l10n.d('Gekopieerd');
          await Clipboard.setData(ClipboardData(text: path));
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text(copied)));
        },
        icon: const Icon(Icons.copy, size: 16),
        label: Text(l10n.d('Kopiëren')),
      ),
    ],
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

/// De formaten in de volgorde waarin ze worden aangeboden: eerst de platte
/// tekst waar het hele product op staat, dan wat een ontvanger leest, dan de
/// zetweg voor wie zelf verder wil.
const _formatOptions = [
  _FormatOption(
    DocumentExportFormat.md,
    'Markdown (.md)',
    Icons.description_outlined,
  ),
  _FormatOption(DocumentExportFormat.html, 'HTML', Icons.public_outlined),
  _FormatOption(
    DocumentExportFormat.pdf,
    'PDF',
    Icons.picture_as_pdf_outlined,
  ),
  _FormatOption(
    DocumentExportFormat.latex,
    'LaTeX (.tex)',
    Icons.science_outlined,
  ),
];
