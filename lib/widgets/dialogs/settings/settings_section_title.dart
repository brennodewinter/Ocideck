import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// De ankers van het instellingenvenster: per sectiekop een [GlobalKey], plus
/// welke kop op dit moment oplicht omdat een zoekresultaat ernaartoe sprong.
///
/// Waarom een [InheritedWidget] en geen parameter: een sectiekop staat diep in
/// een paneel, en de panelen horen niet te weten dát er gezocht kan worden. Zo
/// kan een paneel een gewone widget zijn in plaats van een `extension` op de
/// toestand van het venster — het hoeft alleen [SettingsSectionTitle] te
/// gebruiken en krijgt het anker gratis.
///
/// De registratie gebeurt tijdens `build`. Dat mag hier: [keys] is een
/// eigenschap van de zoekfunctie, niet van de tekening, en er wordt niets van
/// afgeleid dat deze frame nog getekend moet worden.
class SettingsSectionAnchors extends InheritedWidget {
  /// Per sectietekst het anker waar de zoekfunctie naartoe scrollt. De kaart is
  /// van de venstertoestand; deze widget vult hem alleen aan.
  final Map<String, GlobalKey> keys;

  /// De sectie die op dit moment oplicht, of `null`.
  final String? highlighted;

  const SettingsSectionAnchors({
    super.key,
    required this.keys,
    required this.highlighted,
    required super.child,
  });

  static SettingsSectionAnchors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSectionAnchors>();

  @override
  bool updateShouldNotify(SettingsSectionAnchors oldWidget) =>
      highlighted != oldWidget.highlighted || !identical(keys, oldWidget.keys);
}

/// De sectiekop in het instellingenvenster.
///
/// Registreert zijn eigen anker onder de getoonde tekst, zodat de zoekfunctie
/// ernaartoe kan scrollen, en licht op wanneer dat gebeurd is. Buiten een
/// [SettingsSectionAnchors] werkt de kop gewoon, zonder anker — dat is wat een
/// losse test of een preview nodig heeft.
class SettingsSectionTitle extends StatelessWidget {
  final String text;

  const SettingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final anchors = SettingsSectionAnchors.maybeOf(context);
    final highlighted = anchors?.highlighted == text;
    return KeyedSubtree(
      key: anchors?.keys.putIfAbsent(text, GlobalKey.new),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: highlighted
            ? const EdgeInsets.fromLTRB(8, 6, 8, 8)
            : const EdgeInsets.only(bottom: 8),
        decoration: highlighted
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accentFg, width: 2),
                color: AppTheme.accent.withValues(alpha: 0.06),
              )
            : null,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.slate500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
