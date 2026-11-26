/// Een scherm zoals de presentator het ziet: positie en afmeting.
///
/// Op desktop komt dit uit nativeapi's `Display`; op web is er geen scherm-
/// detectie en blijft de lijst leeg.
class DisplayInfo {
  const DisplayInfo({
    this.nativeId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Opaque platform identity, scoped to the current display configuration.
  /// Never an enumeration index; only compared by the native bridge.
  final String? nativeId;
  final double x, y, width, height;

  bool get hasValidBounds =>
      x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;
}
