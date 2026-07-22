import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// De bedieningsbalk van de publieksweergave: waar ben ik, hoe kom ik verder,
/// en hoe kom ik eruit.
///
/// Alleen zichtbaar op muisbeweging, en na drie seconden weer weg — de
/// presenter regelt dat, deze widget toont alleen de toestand. Permanente
/// knoppen op een projectiebeeld zijn erger dan geen knoppen: ze staan straks
/// op iedere foto van de zaal. Maar hélemaal niets was wat #607 opleverde: een
/// eerste presentatie waarin iemand moest raden hoe hij eruit kwam, voor een
/// zaal, op het moment van de grootste spanning.
///
/// Een eigen widget en geen methode op de presenter-state, omdat het er precies
/// één is: invoer erin, knoppen eruit, geen enkel veld van de presenter nodig.
class AudienceControlsBar extends StatelessWidget {
  const AudienceControlsBar({
    super.key,
    required this.index,
    required this.total,
    required this.visible,
    required this.onPrev,
    required this.onNext,
    required this.onExit,
  });

  /// Nulgebaseerd; de balk toont `index + 1`.
  final int index;
  final int total;
  final bool visible;

  /// Null wanneer die kant er niet is — de knop staat er dan wel, gedimd.
  /// Weghalen zou de balk laten verspringen tussen de eerste dia en de rest.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.d('Vorige'),
                      onPressed: onPrev,
                      icon: const Icon(Icons.chevron_left),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '${l10n.d('Slide')} ${index + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.d('Volgende'),
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    const SizedBox(width: 4),
                    // De sluitknop noemt Escape in zijn tooltip: dat is de
                    // sneltoets die nergens stond en die je de tweede keer
                    // gebruikt in plaats van de muis.
                    IconButton(
                      tooltip: l10n.d('Afsluiten (Escape)'),
                      onPressed: onExit,
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// De publieksweergave mét haar eigen bediening: [child] is het diabeeld, en
/// bij muisbeweging verschijnt er drie seconden een [AudienceControlsBar]
/// overheen.
///
/// De zichtbaarheid woont hier en niet bij de presenter, omdat dat het enige is
/// wat er te regelen valt en het nergens anders toe doet — één vlag en één
/// timer die alleen deze balk aangaan.
class AudienceSurface extends StatefulWidget {
  const AudienceSurface({
    super.key,
    required this.child,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onExit,
  });

  final Widget child;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onExit;

  @override
  State<AudienceSurface> createState() => _AudienceSurfaceState();
}

class _AudienceSurfaceState extends State<AudienceSurface> {
  /// Lang genoeg om de knop te vinden, kort genoeg om niet in beeld te blijven
  /// staan tijdens het praten.
  static const _hideAfter = Duration(seconds: 3);

  Timer? _timer;
  bool _visible = false;

  /// Wordt bij élke muisbeweging aangeroepen, dus meldt alleen een wijziging
  /// als er werkelijk iets verandert — anders zou een bewegende muis een
  /// setState-storm opleveren midden in een presentatie.
  void _reveal() {
    _timer?.cancel();
    _timer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
    if (_visible) return;
    setState(() => _visible = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onHover: (_) => _reveal(),
    child: Stack(
      children: [
        widget.child,
        AudienceControlsBar(
          index: widget.index,
          total: widget.total,
          visible: _visible,
          onPrev: widget.onPrev,
          onNext: widget.onNext,
          onExit: widget.onExit,
        ),
      ],
    ),
  );
}
