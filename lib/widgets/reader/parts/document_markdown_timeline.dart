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
    return Padding(
      padding: EdgeInsets.only(bottom: event.timelineLast ? 22 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rail(t),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.alphaBlend(
                        t.marker.withValues(alpha: 0.075),
                        t.paper,
                      ),
                      Color.alphaBlend(
                        t.marker.withValues(alpha: 0.018),
                        t.paper,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color.alphaBlend(
                      t.marker.withValues(alpha: 0.20),
                      t.border,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.marker.withValues(alpha: 0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3.5, color: t.marker),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 17, 15),
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
                                color: t.marker,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Datum en tijd staan bewust onder elkaar. Zo blijft ook een gezoneerd
  /// tijdstip rustig leesbaar bij documentstijlen met bredere letters.
  Widget _rail(_Theme t) => SizedBox(
    width: 126,
    child: Stack(
      alignment: Alignment.topRight,
      clipBehavior: Clip.none,
      children: [
        // De verticale rail begint en eindigt bij de eerste en laatste marker.
        Positioned(
          right: 18,
          top: event.timelineFirst ? 23 : 0,
          bottom: event.timelineLast ? null : 0,
          height: event.timelineLast
              ? 33 - (event.timelineFirst ? 23 : 0)
              : null,
          child: Container(width: 2, color: t.marker.withValues(alpha: 0.28)),
        ),
        Positioned(
          right: -12,
          top: 24,
          width: 23,
          child: Container(height: 2, color: t.marker.withValues(alpha: 0.28)),
        ),
        Positioned(
          right: 11,
          top: 17,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: t.paper,
              shape: BoxShape.circle,
              border: Border.all(color: t.marker, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: t.marker.withValues(alpha: 0.22),
                  blurRadius: 12,
                  spreadRadius: 3.5,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: t.marker,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        if (event.timelineLast)
          Positioned(
            right: 13,
            top: 33,
            width: 12,
            child: Container(
              height: 2,
              color: t.marker.withValues(alpha: 0.28),
            ),
          ),
        Positioned(left: 0, right: 40, top: 10, child: _moment(t)),
      ],
    ),
  );

  Widget _moment(_Theme t) {
    final pieces = event.timelineMarker.split(' ');
    final isProjectedInstant =
        pieces.length == 3 && pieces[2].startsWith('UTC');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (event.timelineMarkerHeader.isNotEmpty) ...[
          Text(
            event.timelineMarkerHeader.toUpperCase(),
            textAlign: TextAlign.end,
            style: t.body.copyWith(
              fontSize: t.bodyFontSize * 0.56,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: t.marker,
            ),
          ),
          const SizedBox(height: 3),
        ],
        Text(
          isProjectedInstant ? pieces[0] : event.timelineMarker,
          textAlign: TextAlign.end,
          style: t.body.copyWith(
            fontSize: t.bodyFontSize * 0.81,
            height: 1.12,
            fontWeight: FontWeight.w700,
            color: t.subheading,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (isProjectedInstant) ...[
          const SizedBox(height: 1),
          Text(
            pieces[1],
            style: t.body.copyWith(
              fontSize: t.bodyFontSize * 0.76,
              height: 1.08,
              fontWeight: FontWeight.w700,
              color: t.subheading,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            pieces[2],
            style: t.body.copyWith(
              fontSize: t.bodyFontSize * 0.63,
              height: 1.08,
              fontWeight: FontWeight.w600,
              color: t.subheading.withValues(alpha: 0.78),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  /// Het pilletje onder een gebeurtenis met de metadata erin — de kop vet, de
  /// waarde erachter. Eigen methode omdat [build] anders over de
  /// methodelengte-grens loopt, en omdat het één afgerond ding is.
  Widget _metadataPill(_Theme t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          t.marker.withValues(alpha: 0.13),
          t.marker.withValues(alpha: 0.065),
        ],
      ),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: t.marker.withValues(alpha: 0.24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: t.marker, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: t.body.copyWith(
                fontSize: t.bodyFontSize * 0.74,
                height: 1.2,
              ),
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
        ),
      ],
    ),
  );
}
