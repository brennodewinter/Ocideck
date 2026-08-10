import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/marp_style.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/slide_dedup_service.dart';
import '../../theme/app_theme.dart';
import '../slides/slide_preview.dart';

/// One side of a slide comparison: a rendered slide plus what it needs to
/// preview (project base path for relative images, and its deck's theme) and a
/// short human label ("Deck A · slide 3").
class SlideDiffRef {
  final String label;
  final Slide slide;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final MarpStyle deckMarpStyle;

  const SlideDiffRef({
    required this.label,
    required this.slide,
    required this.projectPath,
    required this.themeProfile,
    this.deckMarpStyle = const MarpStyle(),
  });
}

/// Shows two look-alike slides side by side and lists the fields that differ,
/// so the user can tell near-duplicates apart before adding one. When several
/// look-alikes exist, a chip row picks which one to compare against [primary].
class SlideDiffDialog extends StatefulWidget {
  final SlideDiffRef primary;
  final List<SlideDiffRef> others;

  const SlideDiffDialog({
    super.key,
    required this.primary,
    required this.others,
  });

  static Future<void> show(
    BuildContext context, {
    required SlideDiffRef primary,
    required List<SlideDiffRef> others,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SlideDiffDialog(primary: primary, others: others),
    );
  }

  @override
  State<SlideDiffDialog> createState() => _SlideDiffDialogState();
}

class _SlideDiffDialogState extends State<SlideDiffDialog> {
  final _dedup = SlideDedupService();
  int _otherIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final other = widget.others[_otherIndex];
    final diffs = _dedup.diff(widget.primary.slide, other.slide);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.difference_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.d('Verschillen tussen slides'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.others.length > 1) ...[
              _otherPicker(l10n),
              const SizedBox(height: 12),
            ],
            _previews(widget.primary, other),
            const SizedBox(height: 16),
            Expanded(child: _diffList(l10n, diffs)),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Widget _otherPicker(AppLocalizations l10n) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 2),
            child: Text(
              l10n.d('Vergelijk met:'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ),
          for (var i = 0; i < widget.others.length; i++)
            ChoiceChip(
              label: Text(
                widget.others[i].label,
                style: const TextStyle(fontSize: 11),
              ),
              selected: _otherIndex == i,
              onSelected: (_) => setState(() => _otherIndex = i),
            ),
        ],
      ),
    );
  }

  Widget _previews(SlideDiffRef a, SlideDiffRef b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _previewColumn(a, accent: false)),
        const SizedBox(width: 14),
        Expanded(child: _previewColumn(b, accent: true)),
      ],
    );
  }

  Widget _previewColumn(SlideDiffRef ref, {required bool accent}) {
    final color = accent ? AppTheme.accentFg : AppTheme.slate400;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: accent ? 2 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SlidePreviewWidget(
                slide: ref.slide,
                projectPath: ref.projectPath,
                themeProfile: ref.themeProfile,
                deckMarpStyle: ref.deckMarpStyle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ref.label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _diffList(AppLocalizations l10n, List<SlideFieldDiff> diffs) {
    if (diffs.isEmpty) {
      // Reachable when the slides differ only in a field this list does not
      // surface (e.g. image crop focus, auto-advance, or the skip flag).
      return Center(
        child: Text(
          l10n.d(
            'Geen zichtbare verschillen — de slides zijn inhoudelijk gelijk.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.slate500, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      itemCount: diffs.length,
      separatorBuilder: (_, _) => const Divider(height: 18),
      itemBuilder: (_, i) => _diffRow(l10n, diffs[i]),
    );
  }

  Widget _diffRow(AppLocalizations l10n, SlideFieldDiff diff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fieldLabel(l10n, diff.field),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _valueBox(l10n, diff.before, accent: false)),
            const SizedBox(width: 10),
            Expanded(child: _valueBox(l10n, diff.after, accent: true)),
          ],
        ),
      ],
    );
  }

  Widget _valueBox(
    AppLocalizations l10n,
    String value, {
    required bool accent,
  }) {
    final empty = value.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? AppTheme.accent.withValues(alpha: 0.08)
            : AppTheme.slate100,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          left: BorderSide(
            color: accent ? AppTheme.accentFg : AppTheme.slate400,
            width: 2.5,
          ),
        ),
      ),
      child: Text(
        empty ? l10n.d('(leeg)') : value,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
          color: empty ? AppTheme.slate400 : AppTheme.slate800,
        ),
      ),
    );
  }

  String _fieldLabel(AppLocalizations l10n, SlideField field) {
    switch (field) {
      case SlideField.type:
        return l10n.d('Type');
      case SlideField.title:
        return l10n.d('Titel');
      case SlideField.subtitle:
        return l10n.d('Ondertitel');
      case SlideField.bullets:
        return l10n.d('Opsomming');
      case SlideField.bullets2:
        return l10n.d('Tweede opsomming');
      case SlideField.columnTitle1:
        return l10n.d('Kop kolom 1');
      case SlideField.columnTitle2:
        return l10n.d('Kop kolom 2');
      case SlideField.listStyle:
        return l10n.d('Lijststijl');
      case SlideField.quote:
        return l10n.d('Citaat');
      case SlideField.quoteAuthor:
        return l10n.d('Bron citaat');
      case SlideField.body:
        return l10n.d('Inhoud');
      case SlideField.codeLanguage:
        return l10n.d('Codetaal');
      case SlideField.image:
        return l10n.d('Afbeelding');
      case SlideField.imageCaption:
        return l10n.d('Bijschrift');
      case SlideField.image2:
        return l10n.d('Tweede afbeelding');
      case SlideField.imageCaption2:
        return l10n.d('Tweede bijschrift');
      case SlideField.video:
        return l10n.d('Video');
      case SlideField.audio:
        return l10n.d('Audio');
      case SlideField.table:
        return l10n.d('Tabel');
      case SlideField.notes:
        return l10n.d('Notities');
    }
  }
}
