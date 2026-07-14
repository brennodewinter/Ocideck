import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The "PrivacyKat" mark: an EU-blue (#003399) shield with cat ears and an
/// EU-yellow (#FFCC00) keyhole. The product's own mark for personal data — used
/// wherever a privacy-sensitive risk is pointed out: the "personal data" shield
/// the recipient sees on a slide, the privacy rows in the quality panel, and (as
/// an egress marker) a deck fetched from an external URL or a lookup that talks
/// to a third party. The yellow rim keeps the dark-blue body legible on a dark
/// background. Kept as an inline string (rendered via `SvgPicture.string`, like
/// the mermaid diagrams) so it needs no bundled asset.
const String privacyKatSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M4.6 6.2 L7 3.2 L9.1 6.2 L12 5.4 L14.9 6.2 L17 3.2 L19.4 6.2 '
    'V11.3 C19.4 16.1 16.2 19.5 12 21.4 C7.8 19.5 4.6 16.1 4.6 11.3 Z" '
    'fill="#003399" stroke="#FFCC00" stroke-width="1.4" stroke-linejoin="round"/>'
    '<circle cx="12" cy="11" r="1.85" fill="#FFCC00"/>'
    '<path d="M11.15 12.3 L10.75 15.4 H13.25 L12.85 12.3 Z" fill="#FFCC00"/>'
    '</svg>';

/// A non-blocking privacy marker: the PrivacyKat shield with an explanation on
/// hover. It never blocks the action it sits next to — it makes visible that
/// the action reaches outside this device, and says what that discloses.
///
/// [label] is optional: the status bar shows one ("Extern"), while a settings
/// switch that already carries its own title needs only the mark and the
/// tooltip.
class PrivacyBadge extends StatelessWidget {
  /// The full explanation, shown on hover. Say what leaves the device and to
  /// whom — a badge that only says "privacy" warns about nothing.
  final String tooltip;

  /// Optional short caption next to the mark.
  final String? label;

  final double size;

  const PrivacyBadge({
    super.key,
    required this.tooltip,
    this.label,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final caption = label;
    return Tooltip(
      message: tooltip,
      // De uitleg is een hele zin; laat hem afbreken in plaats van uitwaaieren.
      textAlign: TextAlign.start,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.string(privacyKatSvg, width: size, height: size),
          if (caption != null) ...[
            const SizedBox(width: 4),
            Text(
              caption,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
