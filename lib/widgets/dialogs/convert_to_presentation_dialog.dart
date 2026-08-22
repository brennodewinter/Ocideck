import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// De bevestigingsdialoog vóór document → presentatie (DOCUMENT_MODE.md §11.3).
///
/// Geen enge waarschuwing maar geruststelling: we maken een **kopie** in een
/// nieuw tabblad, het originele document blijft ongewijzigd. Wél expliciet het
/// voorgestelde aantal dia's (gesplitst per kop en blok) én de drop-lijst — een
/// thematische `---` wordt een diagrens (intentieverlies), en de conversie is
/// asymmetrisch en lossy (geen bijectie-belofte).
class ConvertToPresentationDialog extends StatelessWidget {
  /// Het voorgestelde aantal dia's — de zero-loss deconstructie zelf, geen gok.
  final int slideCount;

  const ConvertToPresentationDialog({super.key, required this.slideCount});

  static Future<bool?> show(BuildContext context, {required int slideCount}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => ConvertToPresentationDialog(slideCount: slideCount),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Naar presentatie converteren?')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$slideCount ${l10n.d('dia\'s uit dit document.')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.d(
                'We maken een kopie in een nieuw tabblad; je originele bestand blijft ongewijzigd.',
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.d('Wat verandert er bij het converteren:'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 6),
            _drop(l10n.d('Een thematische regel (---) wordt een diagrens.')),
            _drop(
              l10n.d(
                'De documentstijl (thema, paginaformaat, marges) gaat niet mee.',
              ),
            ),
            _drop(l10n.d('Documentvelden (kop- en voettekst) gaan niet mee.')),
            _drop(
              l10n.d(
                'Voetnoten worden platte tekst; een presentatie kent geen noten.',
              ),
            ),
            _drop(
              l10n.d(
                'De indeling in dia\'s is een voorstel; presentatie en document zijn geen perfecte spiegeling van elkaar.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.d('Converteren')),
        ),
      ],
    );
  }

  Widget _drop(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.arrow_right, size: 16, color: AppTheme.slate400),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
