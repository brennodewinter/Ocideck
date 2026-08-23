/// Afloop-flow voor session-data-edits na een presentatie (#1235).
///
/// Tijdens het presenteren kan de spreker checklists invullen en tabelcellen
/// bewerken. Dat is **sessiedata** (de uitkomst van deze presentatie), geen
/// deck-bewerking. Deze file biedt de spreker aan het eind de keuze:
///
/// - **Downloaden als losse bestanden** — per gewijzigde dia één `.md` naar een
///   map (desktop) of als browser-downloads (web), en de wijzigingen in het deck
///   ongedaan gemaakt. Het deck blijft schoon.
/// - **In deck behouden** — huidig gedrag; de wijzigingen blijven in het deck.
///
/// De live-fix #914 (een te volle dia opknippen) is een deck-bewerking en wordt
/// hier nadrukkelijk niet aangeboden of teruggedraaid: die edits komen via
/// `onSlideChanged` binnen, niet via `onSessionEdit`. Zie `shell_actions_present.dart`.
///
/// **Privacy-projectiegrens:** de export levert dia-inhoud aan een ontvanger
/// (losse bestanden die elders gebruikt worden) en gaat daarom door
/// `PrivacyProjection.forAudience` — net als PDF/PPTX/presentatie. Bevindingen
/// (mogelijke persoonsgegevens) worden in de dialoog gemeld via een schildje;
/// de spreker mag doorgaan, maar is geïnformeerd.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import '../../platform/platform_features.dart';
import '../../services/privacy/privacy_own_identity.dart';
import '../../services/privacy/privacy_projection.dart';
import '../../services/privacy/privacy_scanner.dart';
import '../../state/deck_provider.dart';
import '../../state/privacy_provider.dart';
import '../../state/settings_provider.dart';
import '../../utils/atomic_file.dart';
import '../../utils/file_download.dart';
import '../../utils/log.dart';
import '../../utils/safe_filename.dart';

/// De keuze uit de afloop-dialoog.
enum _SessionExportChoice { keep, download }

/// Biedt na afloop van een presentatie aan om session-data-edits als losse
/// `.md`-bestanden te bewaren en het deck schoon te houden. Toont de dialoog
/// alleen wanneer [sessionOriginals] niet leeg is — geen edits, geen vraag.
///
/// [sessionOriginals] mapt slide-id → de oorspronkelijke dia vóór de eerste
/// session-data-edit (inclusief eerdere live-fixes die mogen blijven). Bij
/// "downloaden" worden de *huidige* (bewerkte) dia's geëxporteerd en daarna het
/// deck via [DeckNotifier.revertSlidesById] in één ongedaan-stap hersteld.
Future<void> offerSessionExport(
  BuildContext context,
  WidgetRef ref, {
  required DeckNotifier deckNotifier,
  required Map<String, Slide> sessionOriginals,
}) async {
  if (sessionOriginals.isEmpty) return;
  final deck = deckNotifier.currentState.deck;
  if (deck == null) return;
  // De huidige (bewerkte) versie per gewijzigde dia, op bron-index.
  final edited = <int, Slide>{};
  for (var i = 0; i < deck.slides.length; i++) {
    if (sessionOriginals.containsKey(deck.slides[i].id)) {
      edited[i] = deck.slides[i];
    }
  }
  if (edited.isEmpty || !context.mounted) return;

  // Privacyscan op de session-dia's: de export gaat door de projectiegrens,
  // en de dialoog waarschuwt als er mogelijke persoonsgegevens in staan.
  final scanner = ref.read(privacyScannerProvider);
  final findings = _scanSessionSlides(scanner, deck, edited);

  final choice = await _showSessionExportDialog(context, edited, findings);
  // null = weggeklikt/escape → "in deck behouden" (de veilige default).
  if (choice != _SessionExportChoice.download || !context.mounted) return;

  // Projectie: de export levert aan een ontvanger, dus redactie geldt — tenzij
  // de gebruiker regels heeft uitgezet (disabledRules). Zie privacyexpert-skill.
  final settings = ref.read(settingsProvider);
  final audience = PrivacyProjection.forAudience(
    deck.copyWith(slides: edited.values.toList()),
    disabledRules: settings.privacyDisabledRules,
    regions: settings.privacyRegions,
    ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
  );
  final ok = await _downloadSessionSlides(context, ref, audience, edited);
  if (ok) {
    deckNotifier.revertSlidesById(sessionOriginals);
  }
}

/// Scant alleen de session-dia's op persoonsgegevens. Geeft de bevindingen
/// terug die op die dia's vuren — voor het waarschuwingsschildje in de dialoog.
List<PrivacyFinding> _scanSessionSlides(
  PrivacyScanner scanner,
  Deck deck,
  Map<int, Slide> edited,
) {
  final indices = edited.keys.toSet();
  final scan = scanner.scan(deck);
  return scan.findings.where((f) => indices.contains(f.slideIndex)).toList();
}

Future<_SessionExportChoice?> _showSessionExportDialog(
  BuildContext context,
  Map<int, Slide> edited,
  List<PrivacyFinding> findings,
) {
  final l10n = context.l10n;
  final titles = edited.values
      .map((s) => s.title.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  final count = edited.length;
  final content = StringBuffer(
    l10n
        .d(
          'Tijdens het presenteren heb je checklists ingevuld en tabellen bijgewerkt op {aantal} dia’s.',
        )
        .replaceAll('{aantal}', '$count'),
  );
  if (titles.isNotEmpty) {
    content
      ..writeln()
      ..writeln();
    // ponytail: max 8 titels tonen; bij meer alleen het aantal — een dialoog
    // met 40 regels is onleesbaar. Upgrade: een scroll-lijst zodra dat nodig is.
    final shown = titles.take(8).join('\n');
    content.write(shown);
    if (titles.length > 8) {
      content
        ..writeln()
        ..write(
          l10n
              .d('en nog {aantal} dia’s.')
              .replaceAll('{aantal}', '${titles.length - 8}'),
        );
    }
  }
  return showDialog<_SessionExportChoice>(
    context: context,
    // escape/away-klik = "in deck behouden" (de veilige default)
    barrierDismissible: true,
    builder: (ctx) => _SessionExportDialog(
      content: content.toString(),
      findings: findings,
      onKeep: () => Navigator.pop(ctx, _SessionExportChoice.keep),
      onDownload: () => Navigator.pop(ctx, _SessionExportChoice.download),
    ),
  );
}

/// De dialoog-widget, met een waarschuwingsschildje als er privacy-bevindingen
/// zijn. Het schildje is rood en klikbaar; klik toont de bevindingen in een
/// detail-dialoog.
class _SessionExportDialog extends StatelessWidget {
  final String content;
  final List<PrivacyFinding> findings;
  final VoidCallback onKeep;
  final VoidCallback onDownload;

  const _SessionExportDialog({
    required this.content,
    required this.findings,
    required this.onKeep,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Row(
        children: [
          Text(l10n.d('Sessie-wijzigingen bewaren?')),
          if (findings.isNotEmpty) ...[
            const SizedBox(width: 8),
            _PrivacyShieldBadge(findings: findings),
          ],
        ],
      ),
      content: Text(content),
      actions: [
        // Default-knop (enter/escape via de dichtstbijzijnde actie): "in deck
        // behouden" — veiligst bij wegklikken, en met één ongedaan terug te
        // draaien. De download-optie staat ernaast als de actieve keuze.
        TextButton(onPressed: onKeep, child: Text(l10n.d('In deck behouden'))),
        FilledButton(
          onPressed: onDownload,
          child: Text(l10n.d('Downloaden als losse bestanden')),
        ),
      ],
    );
  }
}

/// Het rode schildje dat waarschuwt voor mogelijke persoonsgegevens in de
/// session-data. Klikbaar: toont de bevindingen in een detail-dialoog. Het
/// schildje knippert (opacity pulseert tussen 0.4 en 1.0, ~1.2s cyclus) om de
/// aandacht te trekken — een stille badge in een drukke dialoog valt weg.
class _PrivacyShieldBadge extends StatefulWidget {
  final List<PrivacyFinding> findings;

  const _PrivacyShieldBadge({required this.findings});

  @override
  State<_PrivacyShieldBadge> createState() => _PrivacyShieldBadgeState();
}

class _PrivacyShieldBadgeState extends State<_PrivacyShieldBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    return InkWell(
      onTap: () => _showPrivacyFindingsDialog(context, widget.findings),
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: l10n
            .d('Let op: er staan mogelijk persoonsgegevens in de sessie-data.')
            .replaceAll('{aantal}', '${widget.findings.length}'),
        child: FadeTransition(
          opacity: _opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 16, color: errorColor),
                const SizedBox(width: 4),
                Text(
                  '${widget.findings.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: errorColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Schrijft per gewijzigde dia één `.md` uit het geprojecteerde [audience]-
/// deck. Desktop: één map kiezen, alles daarin schrijven. Web: losse browser-
/// downloads (geen schrijfbaar bestandssysteem). [edited] levert de bron-index
/// per slide-id, zodat de bestandsnaam de oorspronkelijke volgorde behoudt.
Future<bool> _downloadSessionSlides(
  BuildContext context,
  WidgetRef ref,
  AudienceDeck audience,
  Map<int, Slide> edited,
) async {
  final l10n = context.l10n;
  final md = ref.read(markdownServiceProvider);
  final settings = ref.read(settingsProvider);
  // Breng de geprojecteerde dia's terug op bron-index via het id, zodat de
  // bestandsnaam en de inhoud kloppen.
  final projectedById = {for (final s in audience.slides) s.id};
  final exported = <int, Slide>{};
  for (final entry in edited.entries) {
    if (projectedById.contains(entry.value.id)) {
      final p = audience.slides.firstWhere((s) => s.id == entry.value.id);
      exported[entry.key] = p;
    } else {
      exported[entry.key] = entry.value;
    }
  }
  if (!supportsLocalProjectFolders) {
    var ok = true;
    for (final entry in exported.entries) {
      final name = _sessionSlideFileName(entry.key, entry.value);
      final content = md.generateSlide(entry.value, forExport: true);
      if (!downloadTextFile(name, content)) ok = false;
    }
    return ok;
  }
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: l10n.d('Map voor sessie-bestanden kiezen'),
    initialDirectory: settings.homeDirectory,
  );
  if (dir == null) return false; // gebruiker geannuleerd — deck ongemoeid
  try {
    for (final entry in exported.entries) {
      final name = _sessionSlideFileName(entry.key, entry.value);
      final content = md.generateSlide(entry.value, forExport: true);
      await writeStringAtomic(File('$dir/$name'), content);
    }
    return true;
  } catch (e, s) {
    logError('sessionExport: schrijven naar map mislukt', e, s);
    return false;
  }
}

/// `<index+1:02> - <slugged titel>.md`. Vast volgorde, herkenbaar, geen
/// naamconflicten door de index.
String _sessionSlideFileName(int index, Slide slide) {
  final title = sanitizeFilename(slide.title, fallback: 'dia');
  return '${(index + 1).toString().padLeft(2, '0')} - $title.md';
}

/// Toont de privacy-bevindingen in de session-data in een eenvoudige lijst.
/// Per bevinding: de regel, het veld, en het gemaskeerde sample (nooit de
/// volledige waarde — zie [PrivacyFinding.maskedSample]).
void _showPrivacyFindingsDialog(
  BuildContext context,
  List<PrivacyFinding> findings,
) {
  final l10n = context.l10n;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Privacy-bevindingen in sessie-data')),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              l10n.d(
                'De privacyscan vond mogelijk persoonsgegevens in de sessie-data. De export redigeert deze automatisch; klik op een bevinding voor de details.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final f in findings)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(f.ruleId, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${f.field} · ${f.maskedSample}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
      ],
    ),
  );
}
