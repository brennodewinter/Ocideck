part of 'tree_layout.dart';

/// Een knoop uit de geneste bullets. [hasId] markeert een rode-draad-id
/// (`**X-01**` / `**Y-01**`): de sterretjes zijn opmaak en horen niet op de dia.
class _HNode {
  _HNode(this.text, this.hasId);

  final String text;
  final bool hasId;
  final List<_HNode> children = [];
}

class _Laid {
  _Laid(this.node, this.depth);

  final _HNode node;
  final int depth;
  final List<_Laid> children = [];
  double slot = 0;
  double x = 0;
  double y = 0;
}

final RegExp _improvementIdMarkup = RegExp(r'\*\*[YX]-\d+\*\*');

double _paintTreeHeader(
  List<SceneNode> nodes, {
  required String title,
  required String guidance,
  required TreePalette palette,
}) {
  const margin = 32.0;
  var y = 24.0;
  final heading = title.trim();
  if (heading.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: y + 26,
        text: heading,
        fontSize: 26,
        fill: palette.ink,
        fontWeight: 700,
      ),
    );
    y += 40;
  }
  if (guidance.isNotEmpty) {
    nodes.add(
      SceneText(
        x: margin,
        y: y + 14,
        text: guidance,
        fontSize: 13,
        fill: palette.muted,
      ),
    );
    y += 26;
  }
  return y + 8;
}

void _paintHierarchy({
  required List<SceneNode> nodes,
  required List<String> bullets,
  required TextMeasurer measurer,
  required TreePalette palette,
  required double top,
  required double width,
  required double height,
}) {
  final roots = _parseHierarchy(bullets);
  if (roots.isEmpty) return;
  const margin = 32.0;
  final left = margin;
  final cw = math.max(48.0, width - 2 * margin);
  final ch = math.max(48.0, height - 24 - top);

  // Een korte keten — het 5× Why-geval — als trap. Een kolom laat de
  // breedte van een 16:9-dia leeg, een rij maakt een zin onleesbaar smal.
  // De diagonaal gebruikt beide en leest als een afdaling naar de oorzaak.
  // Langere ketens en echte vertakkingen gaan door de boomlay-out: daar
  // wint de vorm van de boom het van de trap.
  final chain = _chainOf(roots);
  if (chain != null && chain.length <= 8) {
    _paintChain(
      nodes: nodes,
      chain: chain,
      measurer: measurer,
      palette: palette,
      left: left,
      top: top,
      cw: cw,
      ch: ch,
    );
    return;
  }
  _paintBranching(
    nodes: nodes,
    roots: roots,
    measurer: measurer,
    palette: palette,
    left: left,
    top: top,
    cw: cw,
    ch: ch,
  );
}

List<_HNode> _parseHierarchy(List<String> bullets) {
  final roots = <_HNode>[];
  final stack = <({int level, _HNode node})>[];
  for (final raw in bullets) {
    final body = bulletText(raw).trim();
    if (body.isEmpty) continue;
    final text = body
        .replaceAll('**', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) continue;
    final node = _HNode(text, _improvementIdMarkup.hasMatch(body));
    final level = bulletLevel(raw);
    while (stack.isNotEmpty && stack.last.level >= level) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.node.children.add(node);
    }
    stack.add((level: level, node: node));
  }
  return roots;
}

/// De knopen van een onvertakte keten, of `null` wanneer de boom vertakt
/// of uit meerdere wortels bestaat.
List<_HNode>? _chainOf(List<_HNode> roots) {
  if (roots.length != 1) return null;
  final chain = <_HNode>[];
  var node = roots.first;
  while (true) {
    chain.add(node);
    if (node.children.isEmpty) return chain;
    if (node.children.length != 1) return null;
    node = node.children.first;
  }
}

void _paintChain({
  required List<SceneNode> nodes,
  required List<_HNode> chain,
  required TextMeasurer measurer,
  required TreePalette palette,
  required double left,
  required double top,
  required double cw,
  required double ch,
}) {
  final n = chain.length;
  final fontSize = n > 6 ? 14.0 : 16.0;
  final lineH = measurer.lineHeight(fontSize: fontSize);
  const badge = 26.0;
  const pad = 14.0;
  var cardW = 220.0;
  for (final node in chain) {
    final natural =
        measurer.widthOf(node.text, fontSize: fontSize) + badge + pad * 2 + 10;
    if (natural > cardW) cardW = natural;
  }
  // 520, niet 440: een Nederlandse zin van één regel ("Na de fusie is het
  // beleid nooit samengevoegd") viel anders nét over de rand en brak af
  // terwijl de rest van de keten op één regel bleef.
  final maxCardW = math.min(520.0, cw);
  cardW = cardW.clamp(math.min(200.0, maxCardW), maxCardW);
  final innerW = math.max(24.0, cardW - badge - pad * 2 - 10);
  final wrapped = [
    for (final node in chain) _wrapLabel(node.text, innerW, fontSize, measurer),
  ];
  final minGap = n <= 3 ? 28.0 : 16.0;
  final gaps = minGap * math.max(0, n - 1);
  final cap = n <= 2 ? 128.0 : (n <= 4 ? 108.0 : 84.0);
  final room = math.max(n * 36.0, ch - gaps);
  var cardH = math.min(cap, room / n);
  if (cardH * n + gaps > ch && ch > n * 32) {
    cardH = (ch - gaps) / n;
  }
  cardH = cardH.clamp(32.0, cap);
  final used = n * cardH + gaps;
  final slack = math.max(0.0, ch - used);
  final stepY = n <= 1 ? 0.0 : cardH + minGap + slack / (n - 1);
  final travel = math.max(0.0, cw - cardW);
  final stepX = n <= 1 ? 0.0 : travel / (n - 1);
  final stackH = cardH + stepY * math.max(0, n - 1);
  final x0 = n == 1 ? left + (cw - cardW) / 2 : left;
  var y = top + math.max(0.0, (ch - stackH) / 2);

  final boxes = <({_HNode node, List<String> lines, double x, double y})>[];
  for (var i = 0; i < n; i++) {
    final maxLines = math.max(1, ((cardH - 16) / lineH).floor());
    boxes.add((
      node: chain[i],
      lines: _fitLines(wrapped[i], maxLines, innerW, fontSize, measurer),
      x: x0 + stepX * i,
      y: y,
    ));
    y += stepY;
  }

  for (var i = 1; i < boxes.length; i++) {
    final prev = boxes[i - 1];
    final next = boxes[i];
    _arrow(
      nodes,
      prev.x + cardW / 2,
      prev.y + cardH,
      next.x + cardW / 2,
      next.y,
      palette.accent,
    );
  }
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    _paintNodeCard(
      nodes: nodes,
      lines: box.lines,
      x: box.x,
      y: box.y,
      w: cardW,
      h: cardH,
      fontSize: fontSize,
      lineH: lineH,
      palette: palette,
      emphasized: i == 0 || i == n - 1 || box.node.hasId,
      cause: box.node.hasId || (i == n - 1 && n > 1),
      index: i + 1,
      measurer: measurer,
    );
  }
}

void _paintBranching({
  required List<SceneNode> nodes,
  required List<_HNode> roots,
  required TextMeasurer measurer,
  required TreePalette palette,
  required double left,
  required double top,
  required double cw,
  required double ch,
}) {
  final laid = [for (final root in roots) _lay(root, 0)];
  var cursor = 0.0;
  for (final root in laid) {
    cursor = _assignSlots(root, cursor);
  }
  final leaves = math.max(1.0, cursor);
  final ranks = laid.map(_rankCount).fold(1, math.max);
  final lrCardW = (cw - 18 * math.max(0, ranks - 1)) / ranks;
  final tdCardW = (cw - 14 * math.max(0, leaves - 1)) / leaves;

  // Links-rechts wanneer de diepte de kaarten anders tot een smalle strook
  // per blad zou persen. Een brede, ondiepe boom (CTQ) blijft boven-onder:
  // de kinderen staan dan naast elkaar, wat een boom is en geen lijst.
  final leftToRight = ranks >= 4 && lrCardW > tdCardW * 1.15;
  final pitchAlong = leftToRight ? cw / ranks : cw / leaves;
  final pitchAcross = leftToRight ? ch / leaves : ch / ranks;
  final cardW = math.min(
    leftToRight ? 280.0 : 320.0,
    math.max(36.0, pitchAlong - 14),
  );
  final cardH = math.min(112.0, math.max(22.0, pitchAcross - 10));
  final fontSize = cardH < 36 ? 11.0 : (cardH < 56 ? 13.0 : 15.0);
  final lineH = measurer.lineHeight(fontSize: fontSize);

  for (final root in laid) {
    _placeLaid(
      root,
      left: left,
      top: top,
      cw: cw,
      ch: ch,
      cardW: cardW,
      cardH: cardH,
      leaves: leaves,
      ranks: ranks,
      leftToRight: leftToRight,
    );
  }

  final flat = <_Laid>[];
  for (final root in laid) {
    _walkLaid(root, flat.add);
  }
  for (final node in flat) {
    for (final child in node.children) {
      if (leftToRight) {
        _elbowRight(
          nodes,
          node.x + cardW,
          node.y + cardH / 2,
          child.x,
          child.y + cardH / 2,
          palette.accent,
        );
      } else {
        _elbowDown(
          nodes,
          node.x + cardW / 2,
          node.y + cardH,
          child.x + cardW / 2,
          child.y,
          palette.accent,
        );
      }
    }
  }
  for (final node in flat) {
    final innerW = math.max(20.0, cardW - 28);
    final maxLines = cardH < 46 ? 1 : (cardH < 78 ? 2 : 3);
    final lines = _fitLines(
      _wrapLabel(node.node.text, innerW, fontSize, measurer),
      maxLines,
      innerW,
      fontSize,
      measurer,
    );
    _paintNodeCard(
      nodes: nodes,
      lines: lines,
      x: node.x,
      y: node.y,
      w: cardW,
      h: cardH,
      fontSize: fontSize,
      lineH: lineH,
      palette: palette,
      emphasized: node.depth == 0 || node.node.hasId,
      cause: node.node.hasId,
      index: null,
      measurer: measurer,
    );
  }
}

_Laid _lay(_HNode node, int depth) {
  final laid = _Laid(node, depth);
  for (final child in node.children) {
    laid.children.add(_lay(child, depth + 1));
  }
  return laid;
}

double _assignSlots(_Laid node, double start) {
  if (node.children.isEmpty) {
    node.slot = start;
    return start + 1;
  }
  var cursor = start;
  for (final child in node.children) {
    cursor = _assignSlots(child, cursor);
  }
  node.slot = (start + cursor - 1) / 2;
  return cursor;
}

int _rankCount(_Laid node) {
  var deepest = node.depth + 1;
  for (final child in node.children) {
    final rank = _rankCount(child);
    if (rank > deepest) deepest = rank;
  }
  return deepest;
}

void _placeLaid(
  _Laid node, {
  required double left,
  required double top,
  required double cw,
  required double ch,
  required double cardW,
  required double cardH,
  required double leaves,
  required int ranks,
  required bool leftToRight,
}) {
  final along = leftToRight ? node.depth + 0.5 : node.slot + 0.5;
  final across = leftToRight ? node.slot + 0.5 : node.depth + 0.5;
  final alongSpan = leftToRight ? ranks.toDouble() : leaves;
  final acrossSpan = leftToRight ? leaves : ranks.toDouble();
  final cx = left + along / alongSpan * cw;
  final cy = top + across / acrossSpan * ch;
  node.x = _clampOrigin(cx - cardW / 2, cardW, left, cw);
  node.y = _clampOrigin(cy - cardH / 2, cardH, top, ch);
  for (final child in node.children) {
    _placeLaid(
      child,
      left: left,
      top: top,
      cw: cw,
      ch: ch,
      cardW: cardW,
      cardH: cardH,
      leaves: leaves,
      ranks: ranks,
      leftToRight: leftToRight,
    );
  }
}

double _clampOrigin(double origin, double size, double min, double span) {
  if (size >= span) return min;
  return origin.clamp(min, min + span - size);
}

void _walkLaid(_Laid node, void Function(_Laid node) visit) {
  visit(node);
  for (final child in node.children) {
    _walkLaid(child, visit);
  }
}

void _paintNodeCard({
  required List<SceneNode> nodes,
  required List<String> lines,
  required double x,
  required double y,
  required double w,
  required double h,
  required double fontSize,
  required double lineH,
  required TreePalette palette,
  required bool emphasized,
  required bool cause,
  required int? index,
  required TextMeasurer measurer,
}) {
  nodes.add(
    SceneRect(
      x: x,
      y: y,
      width: w,
      height: h,
      fill: cause ? _mixHex(palette.box, palette.accent, 0.16) : palette.box,
      stroke: emphasized ? palette.accent : palette.rule,
      strokeWidth: emphasized ? 2 : 1.25,
      cornerRadius: 12,
    ),
  );
  var textX = x + 16;
  if (index != null) {
    const badge = 26.0;
    final badgeY = y + (h - badge) / 2;
    nodes.add(
      SceneRect(
        x: x + 12,
        y: badgeY,
        width: badge,
        height: badge,
        fill: palette.accent,
        cornerRadius: badge / 2,
      ),
    );
    final label = '$index';
    final labelW = measurer.widthOf(label, fontSize: 13);
    nodes.add(
      SceneText(
        x: x + 12 + (badge - labelW) / 2,
        y: badgeY + badge / 2 + 5,
        text: label,
        fontSize: 13,
        fill: palette.onAccent,
        fontWeight: 700,
      ),
    );
    textX = x + 12 + badge + 10;
  }
  final block = lines.length * lineH;
  var baseline = y + (h - block) / 2 + fontSize;
  for (final line in lines) {
    nodes.add(
      SceneText(
        x: textX,
        y: baseline,
        text: line,
        fontSize: fontSize,
        fill: palette.ink,
        fontWeight: emphasized ? 600 : 400,
      ),
    );
    baseline += lineH;
  }
}

void _arrow(
  List<SceneNode> nodes,
  double x1,
  double y1,
  double x2,
  double y2,
  String color,
) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return;
  const head = 8.0;
  final ux = dx / len;
  final uy = dy / len;
  final shaft = math.max(0.0, len - head);
  nodes.add(
    SceneLine(
      x1: x1,
      y1: y1,
      x2: x1 + ux * shaft,
      y2: y1 + uy * shaft,
      stroke: color,
      strokeWidth: 2,
    ),
  );
  final tipX = x1 + ux * len;
  final tipY = y1 + uy * len;
  final px = -uy;
  final py = ux;
  const wing = 7.0;
  nodes.add(
    ScenePath(
      points: [
        tipX,
        tipY,
        tipX - ux * wing + px * wing * 0.55,
        tipY - uy * wing + py * wing * 0.55,
        tipX - ux * wing - px * wing * 0.55,
        tipY - uy * wing - py * wing * 0.55,
      ],
      fill: color,
      closed: true,
    ),
  );
}

void _elbowDown(
  List<SceneNode> nodes,
  double x1,
  double y1,
  double x2,
  double y2,
  String color,
) {
  if ((y2 - y1).abs() < 4) {
    _arrow(nodes, x1, y1, x2, y2, color);
    return;
  }
  final mid = y1 + (y2 - y1) * 0.45;
  nodes.add(
    SceneLine(x1: x1, y1: y1, x2: x1, y2: mid, stroke: color, strokeWidth: 2),
  );
  nodes.add(
    SceneLine(x1: x1, y1: mid, x2: x2, y2: mid, stroke: color, strokeWidth: 2),
  );
  _arrow(nodes, x2, mid, x2, y2, color);
}

void _elbowRight(
  List<SceneNode> nodes,
  double x1,
  double y1,
  double x2,
  double y2,
  String color,
) {
  if ((x2 - x1).abs() < 4) {
    _arrow(nodes, x1, y1, x2, y2, color);
    return;
  }
  final mid = x1 + (x2 - x1) * 0.45;
  nodes.add(
    SceneLine(x1: x1, y1: y1, x2: mid, y2: y1, stroke: color, strokeWidth: 2),
  );
  nodes.add(
    SceneLine(x1: mid, y1: y1, x2: mid, y2: y2, stroke: color, strokeWidth: 2),
  );
  _arrow(nodes, mid, y2, x2, y2, color);
}

List<String> _wrapLabel(
  String text,
  double maxWidth,
  double fontSize,
  TextMeasurer measurer,
) {
  if (measurer.widthOf(text, fontSize: fontSize) <= maxWidth) return [text];
  final lines = <String>[];
  var current = '';
  for (final word in text.split(' ')) {
    for (final part in _breakWide(word, maxWidth, fontSize, measurer)) {
      final candidate = current.isEmpty ? part : '$current $part';
      if (measurer.widthOf(candidate, fontSize: fontSize) <= maxWidth) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = part;
      }
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [text] : lines;
}

List<String> _breakWide(
  String word,
  double maxWidth,
  double fontSize,
  TextMeasurer measurer,
) {
  if (measurer.widthOf(word, fontSize: fontSize) <= maxWidth) return [word];
  final parts = <String>[];
  var rest = word;
  while (rest.isNotEmpty) {
    var take = rest.length;
    while (take > 1 &&
        measurer.widthOf(rest.substring(0, take), fontSize: fontSize) >
            maxWidth) {
      take--;
    }
    parts.add(rest.substring(0, take));
    rest = rest.substring(take);
  }
  return parts;
}

List<String> _fitLines(
  List<String> lines,
  int maxLines,
  double maxWidth,
  double fontSize,
  TextMeasurer measurer,
) {
  if (lines.length <= maxLines) return lines;
  final kept = lines.take(maxLines).toList();
  var last = kept.last;
  const mark = '…';
  while (last.isNotEmpty &&
      measurer.widthOf('$last$mark', fontSize: fontSize) > maxWidth) {
    last = last.substring(0, last.length - 1);
  }
  kept[maxLines - 1] = '$last$mark';
  return kept;
}
