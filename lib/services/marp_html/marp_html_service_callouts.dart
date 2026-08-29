// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Image callout markup for the HTML export (IMAGE_CALLOUTS.md §4.2, §5, §12.2).
// The HTML export has its own callout markup and CSS, generated per export:
// nothing derived is persisted (§2.3). This function wraps the split-image
// panel's `<img>` in the `.ocideck-imgslot` structure, adds positioned
// `span.ocideck-callout` markers for each callout target, emits visually
// hidden description elements, and adds `aria-describedby` on the matching
// bullet `<li>`.
part of '../marp_html_service.dart';

/// Matches `<div class="split-image">` … `</div>` so the image inside can be
/// wrapped in the imgslot structure.
final RegExp _splitImageDiv = RegExp(
  r'<div class="split-image">\n([\s\S]*?)\n</div>',
);

/// Matches a bullet reference suffix: ` (X)` at the end of a line, where X is
/// a single uppercase letter (§2.1).
final RegExp _bulletRefSuffix = RegExp(r'\s\(([A-Z])\)$');

/// Renders image callout markers for a bulletsImage slide. Slides without
/// callouts are returned unchanged.
///
/// The [slide] carries the callout data (references, targets, descriptions),
/// the focal point and zoom for the imgslot CSS variables, and the anchor that
/// derives the stable id for each hidden description element.
///
/// In pin mode (the default) a marker is placed at the point — or at the
/// region's centre (§3.1). In region mode a region target is drawn as an
/// outlined rectangle with outside dimming and the number in its top-left
/// corner; a point target is still a pin (§3.1 — a renderer may reduce
/// geometry, never invent it). The marker is `role="img"` with an accessible
/// name of the form "reference, description" and "target n of m" when the
/// reference has more than one target (§12.2).
String renderImageCallouts(String body, Slide slide) {
  if (slide.callouts.isEmpty) return body;

  // 1. Wrap the image in the imgslot structure and add callout markers.
  var result = _renderImgslot(body, slide);

  // 2. Add aria-describedby to bullets that carry a callout reference.
  result = _addBulletCalloutDescriptions(result, slide);

  // 3. Emit visually hidden description elements.
  result = _addHiddenCalloutDescriptions(result, slide);

  return result;
}

/// Replaces the image markdown inside `<div class="split-image">` with the
/// `.ocideck-imgslot` structure carrying callout markers (§4.2).
String _renderImgslot(String body, Slide slide) {
  final divMatch = _splitImageDiv.firstMatch(body);
  if (divMatch == null) return body;
  final inner = divMatch.group(1)!;
  final imgMatch = _imageRef.firstMatch(inner);
  if (imgMatch == null) return body;

  final imgAlt = imgMatch.group(1)!;
  final imgSrc = imgMatch.group(2)!;
  final fx = slide.imageFocalX;
  final fy = slide.imageFocalY;
  final z = slide.imageZoom / 100.0;
  final hasZoom = slide.imageZoom > 0;
  // ponytail: --iw/--ih default to 16/9 because the Slide model carries no
  // intrinsic image dimensions at export time; a render-script pass that reads
  // naturalWidth/Height after load is the upgrade path.
  final slotVars = '--fx:$fx;--fy:$fy;--z:$z;--iw:16;--ih:9';

  // Build callout markers positioned in image-space percentages against the
  // imgbox. In pin mode a marker sits at the point, or at the region's centre.
  // In region mode a region target is an outlined rectangle with outside
  // dimming; a point target is still a pin (§3.1). In arrow mode a horizontal
  // arrow goes from the left edge (the fixed rail, §5) to the target — at the
  // point, or on the region's left edge at centre height (§3.1).
  final markers = StringBuffer();
  final isRegionMode = slide.calloutPresentation == CalloutPresentation.region;
  final isArrowMode = slide.calloutPresentation == CalloutPresentation.arrow;
  for (final callout in slide.callouts) {
    for (var i = 0; i < callout.targets.length; i++) {
      final target = callout.targets[i];
      final name = callout.targets.length > 1
          ? '${callout.reference}, ${callout.description}, '
                'target ${i + 1} of ${callout.targets.length}'
          : '${callout.reference}, ${callout.description}';

      // Arrow mode (§5): horizontal arrow from the fixed rail (left edge) to
      // the target. Region targets also get an outline; the arrow ends on the
      // rectangle's left edge at centre height.
      if (isArrowMode) {
        if (target is CalloutRegion) {
          final left = (target.x * 100).toStringAsFixed(2);
          final top = (target.y * 100).toStringAsFixed(2);
          final width = (target.w * 100).toStringAsFixed(2);
          final height = (target.h * 100).toStringAsFixed(2);
          markers.write(
            '<div class="ocideck-region" role="img" '
            'aria-label="${MarpHtmlService._htmlAttr(name)}" '
            'style="left:$left%;top:$top%;width:$width%;height:$height%">'
            '<span class="ocideck-region-num">'
            '${MarpHtmlService._htmlText(callout.reference)}'
            '</span></div>',
          );
          // Arrow to the region's left edge at centre y.
          final centerY = ((target.y + target.h / 2) * 100).toStringAsFixed(2);
          markers.write(
            '<div class="ocideck-arrow" role="img" '
            'aria-label="${MarpHtmlService._htmlAttr(name)}" '
            'style="left:0%;top:$centerY%;width:$left%"></div>',
          );
        } else {
          final p = target as CalloutPoint;
          final left = (p.x * 100).toStringAsFixed(2);
          final top = (p.y * 100).toStringAsFixed(2);
          markers.write(
            '<div class="ocideck-arrow" role="img" '
            'aria-label="${MarpHtmlService._htmlAttr(name)}" '
            'style="left:0%;top:$top%;width:$left%"></div>',
          );
          // Reference badge at the rail end.
          markers.write(
            '<span class="ocideck-callout" role="img" '
            'aria-label="${MarpHtmlService._htmlAttr(name)}" '
            'style="left:0%;top:$top%">'
            '${MarpHtmlService._htmlText(callout.reference)}'
            '</span>',
          );
        }
        continue;
      }

      // Region mode draws a region target as an outlined rectangle; a point
      // target is never given an invented box (§3.1).
      if (isRegionMode && target is CalloutRegion) {
        final left = (target.x * 100).toStringAsFixed(2);
        final top = (target.y * 100).toStringAsFixed(2);
        final width = (target.w * 100).toStringAsFixed(2);
        final height = (target.h * 100).toStringAsFixed(2);
        markers.write(
          '<div class="ocideck-region" role="img" '
          'aria-label="${MarpHtmlService._htmlAttr(name)}" '
          'style="left:$left%;top:$top%;width:$width%;height:$height%">'
          '<span class="ocideck-region-num">'
          '${MarpHtmlService._htmlText(callout.reference)}'
          '</span></div>',
        );
        continue;
      }
      final (cx, cy) = target is CalloutPoint
          ? (target.x, target.y)
          : (() {
              final r = target as CalloutRegion;
              return (r.x + r.w / 2, r.y + r.h / 2);
            })();
      final left = (cx * 100).toStringAsFixed(2);
      final top = (cy * 100).toStringAsFixed(2);
      markers.write(
        '<span class="ocideck-callout" role="img" '
        'aria-label="${MarpHtmlService._htmlAttr(name)}" '
        'style="left:$left%;top:$top%">'
        '${MarpHtmlService._htmlText(callout.reference)}'
        '</span>',
      );
    }
  }

  // Assemble the imgbox: the image plus the markers.
  final imgbox = StringBuffer()
    ..write(
      '<img src="${MarpHtmlService._htmlAttr(imgSrc)}" '
      'alt="${MarpHtmlService._htmlAttr(imgAlt)}">',
    )
    ..write(markers.toString());

  // Assemble the imgslot, with the zoom wrapper when ze > 0.
  final slot = StringBuffer();
  if (hasZoom) {
    // ponytail: `wide` is the default contain direction; without intrinsic
    // size the tall/wide choice can't be computed here. A render-script pass
    // that measures naturalWidth/Height is the upgrade path.
    slot.write('<div class="ocideck-imgslot" style="$slotVars">');
    slot.write('<div class="ocideck-imgzoom">');
    slot.write('<div class="ocideck-imgbox wide">');
    slot.write(imgbox);
    slot.write('</div></div></div>');
  } else {
    slot.write('<div class="ocideck-imgslot" style="$slotVars">');
    slot.write('<div class="ocideck-imgbox">');
    slot.write(imgbox);
    slot.write('</div></div>');
  }

  // Replace the image markdown inside the split-image div with the imgslot
  // HTML. The focus/alt comments are kept — they are inert under marked and
  // carry no rendering weight.
  final newInner = inner.replaceFirst(imgMatch.group(0)!, slot.toString());
  return body.replaceFirst(divMatch.group(0)!, newInner);
}

/// Adds `aria-describedby` to bullet `<li>` elements that carry a callout
/// reference (§12.2). The bullet list is replaced with an HTML `<ul>` so the
/// attribute can ride on the `<li>`; bullets without a callout keep their
/// text but lose inline markdown formatting, matching the timeline renderer.
String _addBulletCalloutDescriptions(String body, Slide slide) {
  final calloutRefs = {for (final c in slide.callouts) c.reference};

  // Find consecutive bullet lines and replace the group with HTML when any
  // bullet carries a callout reference.
  final lines = body.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final bulletMatch = MarpHtmlService._bulletLine.firstMatch(line.trimLeft());
    if (bulletMatch == null) {
      out.add(line);
      i++;
      continue;
    }
    // Collect the consecutive bullet group.
    final group = <String>[];
    while (i < lines.length) {
      final l = lines[i];
      final m = MarpHtmlService._bulletLine.firstMatch(l.trimLeft());
      if (m == null) break;
      group.add(m.group(1)!);
      i++;
    }
    // Check whether any bullet in this group carries a callout reference.
    final hasCallout = group.any(
      (text) => _bulletRefSuffix.hasMatch(text.trim()),
    );
    if (!hasCallout) {
      for (final text in group) {
        out.add('- $text');
      }
      continue;
    }
    // Build an HTML <ul> with aria-describedby on matching bullets.
    final ul = StringBuffer('\n<ul>');
    for (final text in group) {
      final refMatch = _bulletRefSuffix.firstMatch(text.trim());
      final ref = refMatch?.group(1);
      final descAttr = (ref != null && calloutRefs.contains(ref))
          ? ' aria-describedby="${MarpHtmlService._htmlAttr(_calloutDescId(slide, ref))}"'
          : '';
      ul.write('<li$descAttr>${MarpHtmlService._htmlText(text.trim())}</li>');
    }
    ul.write('</ul>\n');
    out.add(ul.toString());
  }
  return out.join('\n');
}

/// Emits one visually hidden description element per callout reference, after
/// the split-image div (§12.2). The id is derived from the slide anchor and
/// the reference, so the `aria-describedby` on the bullet and the marker's
/// accessible name agree.
String _addHiddenCalloutDescriptions(String body, Slide slide) {
  final descs = StringBuffer();
  for (final callout in slide.callouts) {
    if (callout.description.isEmpty) continue;
    descs.write(
      '<span class="ocideck-callout-desc" '
      'id="${MarpHtmlService._htmlAttr(_calloutDescId(slide, callout.reference))}">'
      '${MarpHtmlService._htmlText(callout.description)}'
      '</span>',
    );
  }
  if (descs.isEmpty) return body;
  // Place the hidden descriptions after the split-image div, inside the slide
  // body. They are visually hidden but present in the accessibility tree.
  final splitImageEnd = '</div>';
  final idx = body.lastIndexOf(splitImageEnd);
  if (idx < 0) return '$body\n$descs';
  return '${body.substring(0, idx + splitImageEnd.length)}\n'
      '$descs${body.substring(idx + splitImageEnd.length)}';
}

/// The stable id for a callout description element, derived from the slide
/// anchor and the reference (§12.2). Falls back to `slide0` when the slide
/// has no anchor — callouts require one (§2.2), so this is a safety net.
String _calloutDescId(Slide slide, String ref) {
  final anchor = slide.anchor.isNotEmpty ? slide.anchor : 'slide0';
  return 'ocideck-callout-$anchor-$ref';
}
