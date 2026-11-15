import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;

/// Scrolt [scroll] door zolang een primaire-knop-sleep de aanwijzer boven of
/// onder het veld houdt (#2907).
///
/// Native editors scrollen tijdens een tekstsleep vanzelf door wanneer de
/// aanwijzer voorbij de beeldrand rust; Flutter doet dat alleen achter een
/// `SelectionArea` — `EditableText` en Quill kennen het niet, zodat een
/// sleepselectie stokte zodra de aanwijzer stilstond. Deze omhulling levert
/// hetzelfde: het volgen begint bij een primaire-knop-aanraking binnen het
/// veld en eindigt bij omhoog, annuleren of een gebruikersgestuurde scroll —
/// een sleep op de schuifbalk of een pan meldt zich via een
/// `ScrollStartNotification` met `dragDetails` en wint het dan van deze
/// helper. De tick plant zichzelf opnieuw zolang de aanwijzer voorbij de
/// rand rust.
class EdgeDragAutoScroll extends StatefulWidget {
  final ScrollController scroll;
  final Widget child;

  const EdgeDragAutoScroll({
    super.key,
    required this.scroll,
    required this.child,
  });

  @override
  State<EdgeDragAutoScroll> createState() => _EdgeDragAutoScrollState();
}

class _EdgeDragAutoScrollState extends State<EdgeDragAutoScroll> {
  /// Pixels per seconde per pixel dat de aanwijzer voorbij de rand ligt,
  /// met een plafond — dezelfde groeiende snelheid als native randscrolls.
  static const _speedPerPixel = 8.0;
  static const _maxSpeed = 1400.0;
  static const _tickPeriod = Duration(milliseconds: 16);

  int? _pointer;
  Offset _pointerGlobal = Offset.zero;
  Timer? _timer;

  Rect? get _rect {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Hoe ver de aanwijzer voorbij de boven- (negatief) of onderrand (positief)
  /// ligt; 0 wanneer hij binnen het veld is.
  double _overshoot(double dy, Rect rect) {
    if (dy > rect.bottom) return dy - rect.bottom;
    if (dy < rect.top) return dy - rect.top;
    return 0;
  }

  void _stopTracking() {
    _pointer = null;
    _timer?.cancel();
    _timer = null;
  }

  void _evaluate() {
    if (_pointer == null) return;
    final rect = _rect;
    if (rect == null || _overshoot(_pointerGlobal.dy, rect) == 0) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_tickPeriod, (_) => _tick());
  }

  void _tick() {
    if (_pointer == null || !widget.scroll.hasClients) {
      _stopTracking();
      return;
    }
    final rect = _rect;
    final overshoot = rect == null ? 0 : _overshoot(_pointerGlobal.dy, rect);
    if (overshoot == 0) {
      _stopTracking();
      return;
    }
    final position = widget.scroll.position;
    final speed = math.min(overshoot.abs() * _speedPerPixel, _maxSpeed);
    final next =
        position.pixels +
        speed * _tickPeriod.inMilliseconds / 1000 * overshoot.sign;
    position.jumpTo(
      next.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        // Een scroll die de gebruiker zélf sleept (schuifbalk, pan) wint;
        // onze eigen jumpTo-ticks komen zonder dragDetails binnen.
        if (notification.dragDetails != null) _stopTracking();
        return false;
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton == 0) return;
          _pointer = event.pointer;
          _pointerGlobal = event.position;
          _evaluate();
        },
        onPointerMove: (event) {
          if (event.pointer != _pointer) return;
          _pointerGlobal = event.position;
          _evaluate();
        },
        onPointerUp: (event) {
          if (event.pointer == _pointer) _stopTracking();
        },
        onPointerCancel: (event) {
          if (event.pointer == _pointer) _stopTracking();
        },
        child: widget.child,
      ),
    );
  }
}
