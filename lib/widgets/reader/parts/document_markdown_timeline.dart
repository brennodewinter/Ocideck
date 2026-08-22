// Part of the document-markdown-view library — see ../document_markdown_view.dart.
//
// Een documenttijdlijn is een gestileerde projectie van een gewone GFM-tabel.
// Iedere gebeurtenis is één blok, zodat de pagina-indeler een passende kaart
// heel doorschuift. Alleen een kaart die zelf hoger is dan het tekstvlak moet
// intern doorlopen; ieder vervolgvel wordt dan expliciet gemarkeerd.
part of '../document_markdown_view.dart';

class _TimelineEventView extends StatelessWidget {
  const _TimelineEventView({
    required this.theme,
    required this.event,
    required this.onTapLink,
  });

  final _Theme theme;
  final _Block event;
  final void Function(String url)? onTapLink;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    const railWidth = 118.0;
    return Padding(
      padding: EdgeInsets.only(bottom: event.timelineLast ? 22 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: railWidth,
              child: Stack(
                alignment: Alignment.topRight,
                clipBehavior: Clip.none,
                children: [
                  // De verticale rail: op het eerste blok begint hij onder de
                  // bovenmarge, op het laatste blok stopt hij aan de onderkant
                  // van het bolletje zodat de lijn niet doorloopt in het niets.
                  Positioned(
                    right: 18,
                    top: event.timelineFirst ? 23 : 0,
                    bottom: event.timelineLast ? null : 0,
                    height: event.timelineLast
                        ? 33 - (event.timelineFirst ? 23 : 0)
                        : null,
                    child: Container(width: 2, color: t.border),
                  ),
                  // Horizontale verbinding tussen bolletje en kaart, zodat de
                  // link visueel hard is in plaats van alleen bij benadering.
                  Positioned(
                    right: -12,
                    top: 24,
                    width: 23,
                    child: Container(height: 2, color: t.border),
                  ),
                  Positioned(
                    right: 11,
                    top: 17,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: t.paper,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.marker, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: t.marker.withValues(alpha: 0.16),
                            blurRadius: 10,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Eindmarkering: een horizontale dwarsstreep onder het laatste
                  // bolletje (┷) die aangeeft dat de tijdlijn klaar is.
                  if (event.timelineLast)
                    Positioned(
                      right: 13,
                      top: 33,
                      width: 12,
                      child: Container(height: 2, color: t.border),
                    ),
                  Positioned(
                    left: 0,
                    right: 38,
                    top: 13,
                    child: Text(
                      event.timelineMarkerHeader.isEmpty
                          ? event.timelineMarker
                          : '${event.timelineMarkerHeader} · ${event.timelineMarker}',
                      textAlign: TextAlign.end,
                      style: t.body.copyWith(
                        fontSize: t.bodyFontSize * 0.81,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: t.subheading,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(17, 14, 17, 15),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    t.marker.withValues(alpha: 0.035),
                    t.paper,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.timelineEventHeader.isNotEmpty) ...[
                      Text(
                        event.timelineEventHeader.toUpperCase(),
                        style: t.body.copyWith(
                          fontSize: t.bodyFontSize * 0.61,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: t.subheading,
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    InlineMarkdownText(
                      event.text,
                      style: t.body,
                      linkColor: t.link,
                      onTapLink: onTapLink,
                      footnoteNumbers: t.footnoteNumbers.isEmpty
                          ? null
                          : t.footnoteNumbers,
                    ),
                    if ((event.timelineMetadataHeader ?? '').isNotEmpty ||
                        (event.timelineMetadata ?? '').isNotEmpty) ...[
                      const SizedBox(height: 9),
                      _metadataPill(t),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Het pilletje onder een gebeurtenis met de metadata erin — de kop vet, de
  /// waarde erachter. Eigen methode omdat [build] anders over de
  /// methodelengte-grens loopt, en omdat het één afgerond ding is.
  Widget _metadataPill(_Theme t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: t.quoteBg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: t.border),
    ),
    child: Text.rich(
      TextSpan(
        style: t.body.copyWith(fontSize: t.bodyFontSize * 0.74, height: 1.2),
        children: [
          if ((event.timelineMetadataHeader ?? '').isNotEmpty)
            TextSpan(
              text: (event.timelineMetadata ?? '').isEmpty
                  ? event.timelineMetadataHeader
                  : '${event.timelineMetadataHeader}: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          TextSpan(text: event.timelineMetadata),
        ],
      ),
    ),
  );
}
