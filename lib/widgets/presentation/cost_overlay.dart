import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/presentation_cost.dart';
import '../../services/presentation_cost_session.dart';
import '../../theme/presenter_palette.dart';

/// Het oplopende sessietotaal rechtsonder op de getoonde dia (#2437).
///
/// Dit is een sessie-overlay, geen dia-inhoud: hij leeft in de
/// presentatie-stack van zowel het eigen scherm als het publieksvenster en
/// komt nooit in de render- of exportketen terecht.
///
/// Twee gedaanten. Op het presentatorscherm krijgt hij de [session] zelf: hij
/// tikt eenmaal per seconde, leest de monotone teller opnieuw uit en roept
/// [onTick] zodat de presenter het verse bedrag naar de beamer kan duwen. Op
/// het publieksvenster bestaat geen sessie — daar is [minor] de geduwde
/// waarde en tikt de widget niet zelf.
class CostOverlay extends StatefulWidget {
  /// De kostensessie — alleen op het presentatorscherm.
  final PresentationCostSession? session;

  /// Het bedrag in kleinste eenheden wanneer er geen [session] is
  /// (het publieksvenster, gepusht via 'costTick').
  final int minor;

  /// Het EUR-equivalent van [minor] op de beamer (#2438); op het
  /// presentatorscherm komt het equivalent uit [session]. `null` bij een
  /// EUR-sessie of een ontbrekende koers — dan staat er ook niets.
  final int? eurMinor;
  final CostCurrency currency;

  /// De breedte van de dia waar de overlay op ligt — stuurt de lettermaat.
  final double slideWidth;

  /// Wordt elke seconde aangeroepen zolang [session] leeft — de aanroep voor
  /// de beamer-push. De tik zelf hoeft geen hele boom te herbouwen.
  final VoidCallback? onTick;

  const CostOverlay({
    super.key,
    this.session,
    this.minor = 0,
    this.eurMinor,
    required this.currency,
    required this.slideWidth,
    this.onTick,
  });

  @override
  State<CostOverlay> createState() => _CostOverlayState();
}

class _CostOverlayState extends State<CostOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      // #2437 eist minstens één update per minuut; een seconde-tik houdt het
      // bedrag zichtbaar oplopend. De tik herbouwt alleen deze overlay.
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        widget.onTick?.call();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minor = widget.session?.currentCostMinor ?? widget.minor;
    final eur = widget.session?.eurMinorOf(minor) ?? widget.eurMinor;
    final amount =
        formatAmountMinor(minor, widget.currency) +
        (eur == null
            ? ''
            : ' ≈ ${formatAmountMinor(eur, kCostCurrencies.first)}');
    final fontSize = (widget.slideWidth / 64).clamp(13.0, 30.0);
    // Geen liveRegion: een per seconde bijgewerkte teller mag een
    // schermlezer niet blijven onderbreken — het label is op aanvraag leesbaar.
    return Semantics(
      label: '${context.l10n.d('Kostenindicatie')}: $amount',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.7,
          vertical: fontSize * 0.3,
        ),
        decoration: BoxDecoration(
          color: PresenterPalette.bgDeepest.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(fontSize * 0.35),
          border: Border.all(
            color: PresenterPalette.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          amount,
          style: TextStyle(
            color: PresenterPalette.text,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
