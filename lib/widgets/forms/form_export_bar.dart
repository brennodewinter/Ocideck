// Onderaan de invulpagina: de inzending opslaan als pakket (FORM_INTAKE.md §5.2,
// fase 1 — een zip die de invuller zelf mailt).
//
// De knop is altijd te bedienen (§8): staat er nog iets open, dan wijst de pagina dat
// aan ([onBlocked]) in plaats van een knop die zonder uitleg dood is. Het pakket zelf
// bouwt [buildFormSubmission]; deze balk regelt alleen welk formulier daarbij hoort,
// het opslaan en wat de invuller te lezen krijgt.

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/form/form_submission_export.dart';
import 'form_export_support.dart';

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
    final l10n = context.l10n;
    final support = widget.support;
    setState(() => _busy = true);
    try {
      final result = await _build(fill, support);
      if (result == null || !mounted) return;
      switch (result.built) {
        case final FormSubmissionBuilt built:
          await _save(built, result.published);
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _save(FormSubmissionBuilt built, String published) async {
    final l10n = context.l10n;
    final String? name;
    try {
      name = await widget.support.save(built.fileName, built.bytes);
    } on Object {
      // Een schijf die vol zit, een map zonder schrijfrechten, een venster dat het
      // systeem niet opent: voor de invuller is het één ding, het is niet gelukt.
      if (mounted) _say(l10n.d('De inzending kon niet worden opgeslagen.'));
      return;
    }
    if (name == null) return;
    widget.support.remember(widget.fill.spec, published);
    if (!mounted) return;
    _say(l10n.d('Inzending opgeslagen als {naam}.').replaceAll('{naam}', name));
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
        ],
      ),
    );
  }
}
