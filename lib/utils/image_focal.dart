import 'package:flutter/painting.dart';

/// Converts a normalized image focal point (0..1 per axis, 0.5 = centre) into
/// the [Alignment] that brings that point of the picture toward the centre of
/// its slot when the image overflows (cover mode, zoom-in, or a fixed panel).
///
/// Flutter clamps alignment at the child's edges, so a focal point can never
/// pull the image past its own border — worst case the matching edge sits flush
/// against the slot. The centre default (0.5, 0.5) maps to [Alignment.center],
/// so decks without a focal point render exactly as before.
Alignment focalAlignment(double focalX, double focalY) => Alignment(
  (focalX.clamp(0.0, 1.0) * 2) - 1,
  (focalY.clamp(0.0, 1.0) * 2) - 1,
);

/// Whether a focal point differs from the centre default, i.e. the author moved
/// the crop. Used to keep existing "anchor to top when zoomed out" behaviour for
/// untouched images and only override it once a focal point is set.
bool hasCustomFocal(double focalX, double focalY) =>
    focalX != 0.5 || focalY != 0.5;
