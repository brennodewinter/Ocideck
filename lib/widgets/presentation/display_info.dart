import 'dart:ui';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../utils/log.dart';
import 'package:flutter/foundation.dart';

import 'display_info_data.dart';
export 'display_info_data.dart';
import 'display_info_io.dart'
    if (dart.library.js_interop) 'display_info_web.dart'
    as impl;

/// Geeft alle schermen terug, of een lege lijst op web / als het faalt.
@visibleForTesting
List<DisplayInfo> Function()? debugGetAllDisplays;
@visibleForTesting
Offset? Function()? debugGetCurrentWindowCenter;
@visibleForTesting
void Function(int, List<DisplayInfo>)? debugMoveToDisplay;

List<DisplayInfo> _readDisplays() =>
    (debugGetAllDisplays ?? impl.getAllDisplays)();

/// Geeft het centrum van het huidige venster terug, of null op web / als het faalt.
Offset? _windowCenter() =>
    (debugGetCurrentWindowCenter ?? impl.getCurrentWindowCenter)();

/// Index van het scherm dat [point] bevat, in de volgorde waarin het platform
/// zijn schermen opsomt. Deze index blijft binnen de gegeven snapshot en gaat
/// nooit naar native. Null bij geen scherm, een null-punt, of een punt buiten alle
/// schermen of bij overlappende (gespiegelde) schermen (#1913, #3216).
int? screenIndexContaining(List<DisplayInfo> displays, Offset? point) {
  if (point == null) return null;
  int? match;
  for (var i = 0; i < displays.length; i++) {
    final d = displays[i];
    if (Rect.fromLTWH(d.x, d.y, d.width, d.height).contains(point)) {
      if (match != null) return null;
      match = i;
    }
  }
  return match;
}

/// Immutable display enumeration for one placement decision. Indices never
/// cross the native boundary; a target is identified within this snapshot.
class DisplaySnapshot {
  DisplaySnapshot(List<DisplayInfo> displays, this.windowCenter)
    : displays = List.unmodifiable(displays);

  final List<DisplayInfo> displays;
  final Offset? windowCenter;

  DisplayInfo? get presenter {
    final index = screenIndexContaining(displays, windowCenter);
    return index == null ? null : displays[index];
  }

  bool get canPresentAudience =>
      displays.length >= 2 && presenter?.nativeId != null;

  DisplayInfo? find(String? id) {
    if (id == null) return null;
    for (final display in displays) {
      if (display.nativeId == id) return display;
    }
    return null;
  }

  DisplayInfo? next() {
    final current = presenter;
    if (!canPresentAudience || current == null) return null;
    return displays[(displays.indexOf(current) + 1) % displays.length];
  }

  DisplayInfo otherThan(DisplayInfo selected) {
    if (!canPresentAudience || find(selected.nativeId) == null) {
      throw StateError('No distinct audience display available');
    }
    return displays.firstWhere((d) => d.nativeId != selected.nativeId);
  }
}

/// The sole application access to a display list and window center. Invalid,
/// ambiguous or failed enumeration is an empty snapshot, never a guessed index.
DisplaySnapshot captureDisplaySnapshot() {
  try {
    final displays = _readDisplays();
    if (displays.isEmpty) return DisplaySnapshot(const [], null);
    final ids = displays.map((d) => d.nativeId).toSet();
    if (ids.length != displays.length ||
        displays.any(
          (d) =>
              d.nativeId == null ||
              d.nativeId!.isEmpty ||
              d.nativeId == '0' ||
              !d.hasValidBounds,
        )) {
      throw StateError('Invalid or ambiguous display snapshot');
    }
    return DisplaySnapshot(displays, _windowCenter());
  } catch (error) {
    logWarning('captureDisplaySnapshot: display detection failed', error);
    return DisplaySnapshot(const [], null);
  }
}

/// Covers only the explicitly selected other display. The native bridge
/// revalidates both identities and reads live bounds immediately before use.
Future<DisplayInfo> coverAudienceDisplay(
  WindowController controller,
  DisplaySnapshot snapshot, {
  DisplayInfo? presenter,
  DisplayInfo? target,
}) async {
  final selected = presenter ?? snapshot.presenter;
  if (selected == null) throw StateError('Presenter display is unknown');
  final destination = target ?? snapshot.otherThan(selected);
  if (!snapshot.canPresentAudience ||
      snapshot.find(selected.nativeId) == null ||
      snapshot.find(destination.nativeId) == null ||
      destination.nativeId == selected.nativeId) {
    throw StateError('Display snapshot no longer contains both targets');
  }
  await controller.coverScreen(
    presenterDisplay: selected.nativeId,
    targetDisplay: destination.nativeId,
  );
  return destination;
}

/// Revalidates identities after the asynchronous audience move. This fresh
/// snapshot is validation of the same target, never another index selection.
Future<void> moveToDisplay(
  DisplayInfo target, {
  required DisplayInfo previous,
}) async {
  final live = captureDisplaySnapshot();
  final display = live.find(target.nativeId);
  if (target.nativeId == previous.nativeId ||
      !live.canPresentAudience ||
      display == null ||
      live.find(previous.nativeId) == null) {
    throw StateError('Display disappeared during the move');
  }
  final debug = debugMoveToDisplay;
  if (debug != null) {
    debug(live.displays.indexOf(display), live.displays);
  } else {
    await impl.moveToDisplay(display, previous: previous);
  }
}
