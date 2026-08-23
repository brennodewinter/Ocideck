/// Een scherm zoals de presentator het ziet: positie en afmeting.
///
/// Op desktop komt dit uit nativeapi's `Display`; op web is er geen scherm-
/// detectie en blijft de lijst leeg.
class DisplayInfo {
  const DisplayInfo({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final double x, y, width, height;
}
