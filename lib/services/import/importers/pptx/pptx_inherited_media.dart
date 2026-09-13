import 'package:xml/xml.dart';

import '../../models/conversion_issue.dart';
import '../../models/source_image.dart';
import '../../pipeline/parse_guard.dart';
import 'pptx_context.dart';
import 'pptx_media.dart';

/// Leest de zichtbare beelden die een dia via zijn indeling en diamodel erft.
///
/// PowerPoint bewaart omslagen en vaste merkdecoratie vaak niet in
/// `slideN.xml`. Alleen de dia zelf lezen levert dan geldige tekst op met stille
/// beeldgaten. De volgorde blijft inhoud, indeling, model: zo wint echte
/// dia-inhoud bij de vaste OciDeck-beeldvakken en blijft een indelingsachtergrond
/// het eerste beeld op een kale titel- of slotdia.
void appendInheritedPictures({
  required PptxContext context,
  required XmlDocument slideDocument,
  required String slidePath,
  required int slideIndex,
  required List<SourceImage> images,
  required List<ConversionIssue> issues,
}) {
  final layoutPath = context.firstRelatedPart(slidePath, 'ppt/slideLayouts/');
  if (layoutPath == null) return;
  final layout = context.readXml(layoutPath);
  if (layout == null) return;

  _appendPartPictures(
    context: context,
    document: layout,
    partPath: layoutPath,
    slideIndex: slideIndex,
    images: images,
    issues: issues,
    layoutPart: true,
  );

  if (!_showsMasterShapes(slideDocument.rootElement) ||
      !_showsMasterShapes(layout.rootElement)) {
    return;
  }
  final masterPath = context.firstRelatedPart(layoutPath, 'ppt/slideMasters/');
  if (masterPath == null) return;
  final master = context.readXml(masterPath);
  if (master == null) return;
  _appendPartPictures(
    context: context,
    document: master,
    partPath: masterPath,
    slideIndex: slideIndex,
    images: images,
    issues: issues,
    layoutPart: false,
  );
}

bool _showsMasterShapes(XmlElement root) {
  final value = root.getAttribute('showMasterSp');
  return value != '0' && value != 'false';
}

void _appendPartPictures({
  required PptxContext context,
  required XmlDocument document,
  required String partPath,
  required int slideIndex,
  required List<SourceImage> images,
  required List<ConversionIssue> issues,
  required bool layoutPart,
}) {
  final rels = context.relsFor(partPath);
  final tree = descendantsLocal(document, 'spTree').firstOrNull;
  if (tree == null) return;
  for (final picture in _visiblePictures(tree)) {
    final parsed = guardParse<SourceImage>(
      sink: issues,
      slideIndex: slideIndex,
      component: IssueComponent.media,
      feature: 'Afbeelding of media',
      description: 'kon niet worden gelezen en is overgeslagen',
      logOp: 'PptxImporter: dia ${slideIndex + 1} geerfde afbeelding',
      body: () => parsePic(
        picture,
        context,
        rels,
        partPath,
        role: SourceImageRole.decoration,
      ),
    );
    if (parsed == null) {
      if (picReferencesMissingMedia(picture, context, rels, partPath)) {
        issues.add(
          ConversionIssue(
            slideIndex: slideIndex,
            component: IssueComponent.media,
            cause: IssueCause.missingPart,
            feature: 'Afbeelding of media',
            description: 'ontbrak in het bestand en is overgeslagen',
          ),
        );
      }
      continue;
    }
    final image = layoutPart && (parsed.placement?.isFullBleed ?? false)
        ? _withRole(parsed, SourceImageRole.background)
        : parsed;
    if (images.any((current) => _sameVisual(current, image))) continue;
    images.add(image);
  }
}

Iterable<XmlElement> _visiblePictures(XmlElement parent) sync* {
  for (final child in parent.children.whereType<XmlElement>()) {
    if (child.name.local == 'grpSp') {
      yield* _visiblePictures(child);
      continue;
    }
    if (child.name.local != 'pic') continue;
    final properties = descendantsLocal(child, 'cNvPr').firstOrNull;
    final hidden = properties?.getAttribute('hidden');
    if (hidden == '1' || hidden == 'true') continue;
    if (descendantsLocal(child, 'ph').isNotEmpty) continue;
    yield child;
  }
}

SourceImage _withRole(SourceImage image, SourceImageRole role) => SourceImage(
  bytes: image.bytes,
  ext: image.ext,
  name: image.name,
  caption: image.caption,
  placement: image.placement,
  role: role,
);

bool _sameVisual(SourceImage left, SourceImage right) {
  if (left.sha256 != right.sha256) return false;
  final a = left.placement;
  final b = right.placement;
  if (a == null || b == null) return a == null && b == null;
  const epsilon = 0.000001;
  return (a.left - b.left).abs() < epsilon &&
      (a.top - b.top).abs() < epsilon &&
      (a.width - b.width).abs() < epsilon &&
      (a.height - b.height).abs() < epsilon;
}
