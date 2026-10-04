// Onderaan de invulpagina: de inzending opslaan als pakket (FORM_INTAKE.md §5.2,
// fase 1 — een zip die de invuller zelf mailt).
//
// De knop is altijd te bedienen (§8): staat er nog iets open, dan wijst de pagina dat
// aan ([onBlocked]) in plaats van een knop die zonder uitleg dood is. Het pakket zelf
// bouwt [buildFormSubmission]; deze balk regelt alleen welk formulier daarbij hoort,
// het opslaan en wat de invuller te lezen krijgt.

import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_intake_context.dart';
import '../../services/form/form_submission_export.dart';
import '../../services/form/form_submission_seal.dart';
import 'form_export_support.dart';
import 'form_fingerprint_dialog.dart';
import 'form_intake_send_dialog.dart';

class FormExportBar extends StatefulWidget {
  const FormExportBar({
    super.key,
    required this.fill,
    required this.support,
    required this.onBlocked,
    this.now,
  });

  final FormFill fill;
  final FormExportSupport support;

  /// Er staat nog iets open: de pagina laat zien wat.
  final VoidCallback onBlocked;

  /// De klok, voor het manifest; in een test een vaste waarde.
  final DateTime Function()? now;

  @override
  State<FormExportBar> createState() => _FormExportBarState();
}

class _FormExportBarState extends State<FormExportBar> {
  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final fill = widget.fill;
    if (!fill.canSend) {
      widget.onBlocked();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _build(fill, widget.support);
      if (result == null || !mounted) return;
      final built = result.built;
      if (built is FormSubmissionBuilt) {
        final name = await _save(built.fileName, built.bytes, result.published);
        if (name != null && mounted) {
          _say(
            context.l10n
                .d('Inzending opgeslagen als {naam}.')
                .replaceAll('{naam}', name),
          );
        }
      } else {
        _reportBuildFailure(built);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wat de invuller te lezen krijgt als het pakket er niet kwam.
  void _reportBuildFailure(FormSubmissionResult built) {
    final l10n = context.l10n;
    switch (built) {
      case FormSubmissionBuilt():
        break;
      case FormSubmissionBlocked():
        widget.onBlocked();
      case FormSubmissionWrongForm():
        _say(
          l10n.d(
            'Dit is niet het formulier waar je antwoorden bij horen. Kies het bestand dat je van de organisator kreeg.',
          ),
        );
      case FormSubmissionPhotoUnreadable(:final path):
        _say(
          l10n
              .d(
                'Een foto kon niet worden gelezen: {pad}. Voeg hem opnieuw toe.',
              )
              .replaceAll('{pad}', path),
        );
      case FormSubmissionRefused():
        _say(
          l10n.d(
            'De inzending past niet in een pakket: te veel foto’s, of een foto die te groot is.',
          ),
        );
    }
  }

  /// De inzending verzegeld opslaan (§5.1, §5.6): met het bundelbestand en de vingerafdruk van
  /// de organisator, voor alle organisatoren die de bundel noemt.
  Future<void> _exportSealed() async {
    final fill = widget.fill;
    final seal = widget.support.seal;
    if (seal == null) return;
    if (!fill.canSend) {
      widget.onBlocked();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _build(fill, widget.support);
      if (result == null || !mounted) return;
      final built = result.built;
      if (built is FormSubmissionBuilt) {
        await _sealAndSave(seal, built, result.published);
      } else {
        _reportBuildFailure(built);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sealAndSave(
    FormSealSupport seal,
    FormSubmissionBuilt built,
    String published,
  ) async {
    final spec = widget.fill.spec;
    final known = seal.recall(spec);
    final bundle = known?.bundle ?? await seal.pickBundle();
    if (bundle == null || !mounted) return;
    final fingerprint = known?.fingerprint ?? await askFormFingerprint(context);
    if (fingerprint == null || !mounted) return;
    final outcome = await sealFormSubmission(
      built: built,
      bundleText: bundle,
      published: published,
      fingerprintText: fingerprint,
      pins: await seal.readPins(),
      now: (widget.now ?? DateTime.now)(),
    );
    if (!mounted) return;
    if (outcome is! FormSubmissionSealed) {
      // Een vingerafdruk of bundel die niet werkt wordt niet onthouden; een gesloten formulier
      // of een te grote inzending zegt niets over die twee.
      if (outcome is FormSealBadFingerprint ||
          outcome is FormSealBundleRefused) {
        seal.forget(spec);
      }
      _say(_sealRefusal(context.l10n, outcome));
      return;
    }
    await seal.writePins(outcome.pins);
    final name = await _save(outcome.fileName, outcome.bytes, published);
    if (name == null || !mounted) return;
    seal.remember(spec, bundle, fingerprint);
    _say(
      context.l10n
          .d(
            'Verzegeld opgeslagen als {naam}, alleen te openen door: {organisatoren}.',
          )
          .replaceAll('{naam}', name)
          .replaceAll('{organisatoren}', outcome.organisers.join(', ')),
    );
  }

  /// De zin bij een verzegeling die niet doorging.
  String _sealRefusal(
    AppLocalizations l10n,
    FormSealOutcome outcome,
  ) => switch (outcome) {
    FormSealBadFingerprint() => l10n.d(
      'Dat is geen vingerafdruk. Hij bestaat uit 52 tekens, meestal in groepjes van vier.',
    ),
    FormSealBundleRefused(:final issue) => switch (issue) {
      FormBundleIssue.notABundle => l10n.d(
        'Dit bestand is geen bundel die OciDeck kan lezen.',
      ),
      FormBundleIssue.unsupportedVersion ||
      FormBundleIssue.rulesTooNew => l10n.d(
        'Dit formulier of deze bundel is van een nieuwere versie van OciDeck. Werk OciDeck bij.',
      ),
      FormBundleIssue.fingerprintMismatch => l10n.d(
        'De vingerafdruk past niet bij deze bundel: het formulier komt niet van wie de uitnodiging zegt. Controleer de vingerafdruk en het bundelbestand.',
      ),
      FormBundleIssue.badSignature => l10n.d(
        'De handtekening van de bundel klopt niet: hij is veranderd of niet van wie de vingerafdruk zegt. Vraag de organisator om een nieuwe bundel.',
      ),
      FormBundleIssue.templateMismatch => l10n.d(
        'Deze bundel hoort niet bij dit formulier. Gebruik het bundelbestand dat bij precies dit formulier hoort.',
      ),
      FormBundleIssue.expired => l10n.d(
        'Deze bundel is verlopen. Vraag de organisator om een nieuwe.',
      ),
      FormBundleIssue.rollback => l10n.d(
        'Deze bundel is ouder dan een bundel die je eerder van deze organisator kreeg. Vraag de organisator om de nieuwste.',
      ),
      FormBundleIssue.badStructure ||
      FormBundleIssue.noFingerprint ||
      FormBundleIssue.badFingerprint => l10n.d(
        'De bundel bevat iets wat niet kan. Vraag de organisator om een nieuwe bundel.',
      ),
    },
    FormSealClosed(:final closes) =>
      l10n
          .d(
            'Dit formulier is gesloten: de laatste dag was {datum}. Neem contact op met de organisator.',
          )
          .replaceAll('{datum}', closes),
    FormSealTooLarge(:final cap) =>
      l10n
          .d(
            'De inzending is groter dan de organisator toestaat ({mb} MB). Haal een foto weg of maak er een kleiner.',
          )
          .replaceAll('{mb}', (cap / (1024 * 1024)).toStringAsFixed(1)),
    FormSealFailed() => l10n.d('De inzending kon niet worden verzegeld.'),
    FormSubmissionSealed() => '',
  };

  /// Insturen via OciServe (FORM_INTAKE.md §6.4): hetzelfde pakket als de
  /// zip, maar dan naar de server uit de uitnodiging. Versturen is een eigen
  /// bevestigde stap in het venster; hier wordt alleen het pakket gebouwd.
  Future<void> _send(FormIntakeContext intakeContext) async {
    final fill = widget.fill;
    if (!fill.canSend) {
      widget.onBlocked();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _build(fill, widget.support);
      if (result == null || !mounted) return;
      final built = result.built;
      if (built is! FormSubmissionBuilt) {
        _reportBuildFailure(built);
        return;
      }
      final updated = await showFormIntakeSendDialog(
        context,
        intakeContext: intakeContext,
        package: built.bytes,
      );
      if (updated != null) {
        await widget.support.intake?.save(fill.spec, updated);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// De verzendknop als dit document bij een OciServe-uitnodiging hoort; de
  /// context van een padloos document zit in het sessiegeheugen, een gewoon
  /// document heeft hem niet en dan is er gewoon geen knop.
  Widget _sendSection(AppLocalizations l10n, ThemeData theme) {
    final intake = widget.support.intake;
    if (intake == null) return const SizedBox.shrink();
    return FutureBuilder<FormIntakeContext?>(
      future: intake.load(widget.fill.spec),
      builder: (context, snapshot) {
        final intakeContext = snapshot.data;
        if (intakeContext == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              l10n
                  .d(
                    'Rechtstreeks naar de organisator op {server}. Je bevestigt in het venster dat opent; er wordt nooit vanzelf iets verstuurd.',
                  )
                  .replaceAll('{server}', intakeContext.baseUrl),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _send(intakeContext),
              icon: const Icon(Icons.send_outlined),
              label: Text(l10n.d('Insturen via OciServe…')),
            ),
          ],
        );
      },
    );
  }

  /// Het pakket, met het gepubliceerde formulier waarmee het gebouwd is. `null` als
  /// de invuller geen formulier kiest.
  Future<({FormSubmissionResult built, String published})?> _build(
    FormFill fill,
    FormExportSupport support,
  ) async {
    final full = support.frontMatter + fill.text;
    var published = support.recall(fill.spec);
    if (published == null || templateTextIssues(published, full).isNotEmpty) {
      published = await support.pickPublished();
      if (published == null) return null;
    }
    final built = await buildFormSubmission(
      fill: fill,
      frontMatter: support.frontMatter,
      published: published,
      readImage: support.readImage,
      now: (widget.now ?? DateTime.now)(),
      random: Random.secure(),
      clientVersion: support.clientVersion,
    );
    return (built: built, published: published);
  }

  /// Bewaart [bytes] onder [fileName] en onthoudt het gepubliceerde formulier. Geeft de naam
  /// waaronder het is opgeslagen, `null` als het niet is gelukt of de invuller annuleerde.
  Future<String?> _save(
    String fileName,
    Uint8List bytes,
    String published,
  ) async {
    final l10n = context.l10n;
    final String? name;
    try {
      name = await widget.support.save(fileName, bytes);
    } on Object {
      // Een schijf die vol zit, een map zonder schrijfrechten, een venster dat het
      // systeem niet opent: voor de invuller is het één ding, het is niet gelukt.
      if (mounted) _say(l10n.d('De inzending kon niet worden opgeslagen.'));
      return null;
    }
    if (name == null) return null;
    widget.support.remember(widget.fill.spec, published);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Text(
            l10n.d(
              'Een zipbestand met je antwoorden en foto’s, om naar de organisator te mailen.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.folder_zip_outlined),
            label: Text(l10n.d('Inzending opslaan als zip…')),
          ),
          if (widget.support.seal != null) ...[
            const SizedBox(height: 20),
            Text(
              l10n.d(
                'Een versleuteld bestand (.zip.age) dat alleen de organisator kan openen. Daarvoor heb je het bundelbestand en de vingerafdruk uit de uitnodiging nodig.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportSealed,
              icon: const Icon(Icons.lock_outline),
              label: Text(l10n.d('Verzegeld opslaan…')),
            ),
          ],
          _sendSection(l10n, theme),
        ],
      ),
    );
  }
}
