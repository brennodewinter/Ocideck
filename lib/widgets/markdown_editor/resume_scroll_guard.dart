import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Slikt de caret-reveal die een app-hervatting onbedoeld uitlokt (#2914).
///
/// Op desktop parkeert [FocusManager] de primaire focus zodra de app naar de
/// achtergrond gaat, en zet hem bij hervatting terug op dezelfde node. Quill
/// reageert op die terugkeer met `_showCaretOnScreen`: een `animateTo` naar
/// de caret — óók wanneer de gebruiker bewust weg had gescrold. Staat die
/// caret op of naast een embed, dan springt het beeld naar dat blok (bij een
/// mermaid-diagram: naar de kaart), terwijl de lezer ergens anders keek.
///
/// Had dit veld de focus toen de app naar achteren ging, dan is de
/// eerstvolgende `animateTo` ná de hervatting vrijwel zeker die onterechte
/// reveal; deze controller slikt precies die ene. Gewone scrolls, `jumpTo`
/// en elke `animateTo` buiten dat venster lopen ongewijzigd door.
class ResumeScrollGuard extends ScrollController with WidgetsBindingObserver {
  ResumeScrollGuard({required this._focusNode}) {
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final FocusNode _focusNode;

  /// De node verloor de focus doordat de app naar de achtergrond ging, niet
  /// door een keuze van de gebruiker — de hervatting geeft hem terug.
  bool _suspendedWhileFocused = false;

  /// Bewapend tot de eerste `animateTo` of tot het venster voorbij is.
  bool _armed = false;
  Timer? _disarmTimer;

  void _onFocusChanged() {
    // FocusManagers opschorting loopt synchroon middenin de
    // lifecycle-dispatch: als deze melding komt terwijl de app al naar
    // achteren is, was het verlies de parkeeractie en geen gebruikersklik.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_focusNode.hasFocus &&
        lifecycle != null &&
        lifecycle != AppLifecycleState.resumed) {
      _suspendedWhileFocused = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _suspendedWhileFocused) {
      _suspendedWhileFocused = false;
      _armed = true;
      _disarmTimer?.cancel();
      // Quills reveal landt binnen een frame na de focus-terugkeer; het
      // toetsenbord-pad houdt ~0,5 s aan. Blijft de reveal uit (focus kwam
      // elders terecht, of de caret stond al in beeld), dan mag de vlag geen
      // latere, legitieme scroll slikken — vandaar de zelfruimer.
      _disarmTimer = Timer(const Duration(seconds: 1), () => _armed = false);
    }
  }

  int _swallowed = 0;

  /// Hoe vaak deze controller al een bewapende `animateTo` sloeg — meetpunt
  /// voor tests, zodat die kunnen zien dat de reveal daadwerkelijk vuurde in
  /// plaats van stilletjes uit te blijven.
  @visibleForTesting
  int get swallowedForTesting => _swallowed;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    if (_armed) {
      _armed = false;
      _swallowed++;
      _disarmTimer?.cancel();
      _disarmTimer = null;
      return Future<void>.value();
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  void dispose() {
    _disarmTimer?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
