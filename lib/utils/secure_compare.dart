/// Constant-time vergelijking van twee lijsten bytes.
///
/// Short-circuit `==` stopt bij het eerste verschil, wat een timing-zijkanaal
/// geeft op hoeveel bytes overeenkomen. Deze functie XOR-t alle bytes
/// accumulerend en returnt pas op het eind — de looptijd hangt af van de
/// lengte, niet van de inhoud.
///
/// Lokaal in een desktop-app is timing niet praktisch te meten (het
/// dreigingsmodel stelt dat de machine vertrouwd is), maar dit is
/// defence-in-depth: een externe auditor flagt `==` op hashes direct, en een
/// toekomstige hergebruik in een netwerkcontext hoeft niet opnieuw nagedacht.
bool constantTimeEqualsBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Constant-time vergelijking van twee strings (code-unit per code-unit).
///
/// Equivalent aan [constantTimeEqualsBytes] over `codeUnits`, maar zonder de
/// byte-conversie die voor hex-strings geen verschil maakt. Voor hashes die
/// als hex-strings worden opgeslagen (het zegel, het redaction-commitment, de
/// TSA-imprint) is dit de vergelijker die `==` vervangt.
bool constantTimeEqualsString(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
