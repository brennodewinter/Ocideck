import 'package:intl/intl.dart' show Bidi;
import 'dart:ui' show TextDirection;

/// De basisrichting van één alinea, uit het eerste sterke teken — dezelfde
/// regel als HTML `dir="auto"` en `unicode-bidi: plaintext` (#2752). De
/// interface blijft zoals ze is; deze richting geldt alleen voor de inhoud.
TextDirection paragraphTextDirection(String text) {
  return Bidi.detectRtlDirectionality(text)
      ? TextDirection.rtl
      : TextDirection.ltr;
}
