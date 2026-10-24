// Parser voor de Jitsi-deploymentdeclaratie (`config.js`). Dat bestand is
// JavaScript, geen JSON — uitvoeren is uit den boze (remote code in ons
// proces), dus extraheren we precies de sleutels die de preflight nodig heeft
// met een commentaar-bewuste scan. Regels:
//
//   * commentaar (`//…`, `/*…*/`) wordt eerst gestript — upstream-configs
//     staan vol uitgecommentarieerde voorbeeldwaarden die anders als echt
//     zouden meetellen (let op: `wss://` in strings mag niet als `//`-comment
//     begin tellen, vandaar de string-bewuste stripper);
//   * twee schrijfwijzen tellen mee: `key: 'value'` in het object én
//     `config.key = 'value'` als losse toewijzing — custom-config.js wordt
//     door jitsi-web achteraan geplakt en overschrijft zo, dus de LAATSTE
//     toewijzing wint;
//   * alles wat niet gevraagd wordt, wordt genegeerd — dit is een lezer, geen
//     JS-interpreter.
//
// Puur en deterministisch: de fetch staat in `jitsi_config_platform*.dart`,
// dit bestand kent geen I/O.

/// Waarom `config.js` niet binnenkwam. De preflight mapt dit op
/// `providerUnavailable` — de reden gaat mee als diagnosable detail, nooit
/// als nieuwe netwerkpoort.
class JitsiConfigFetchException implements Exception {
  const JitsiConfigFetchException(this.reason);
  final String reason;
  @override
  String toString() => 'config.js ophalen geweigerd: $reason';
}

/// Wat een Jitsi-deployment over zichzelf vertelt via config.js.
class JitsiDeploymentConfig {
  const JitsiDeploymentConfig({
    this.websocket,
    this.bosh,
    this.domain,
    this.anonymousDomain,
    this.muc,
    this.focus,
  });

  /// `config.websocket` — de WebSocket-XMPP-ingang (wss://…/xmpp-websocket).
  final String? websocket;

  /// `config.bosh` — de BOSH-ingang; alleen ter info, wij spreken WebSocket.
  final String? bosh;

  /// `config.hosts.domain` — het virtuele XMPP-domein (vaak `meet.jitsi`,
  /// maar een self-hosted kan alles kiezen; DISCOVERY blijft leidend, deze
  /// waarde is alleen het startpunt).
  final String? domain;

  /// `config.hosts.anonymousdomain` — aanwezig ⇒ anonieme gasten mogen mee;
  /// afwezig ⇒ alleen accounts (de preflight meldt dan accountRequired).
  final String? anonymousDomain;

  /// `config.hosts.muc` — de aangeboden MUC-component. Niet blind te
  /// vertrouwen: #2533 ontdekt het component via XEP-0030; dit veld is een
  /// hint om te rapporteren, nooit een bron.
  final String? muc;

  /// `config.hosts.focus` — de focus/Jicofo-JID zoals gedeclareerd.
  final String? focus;

  /// De ingress die OciDeck voor signalling gebruikt — alleen WebSocket.
  String? get signalling => websocket;
}

/// Extraheert de preflight-relevante sleutels uit config.js-brontekst.
/// Geeft nooit een fout terug: ontbrekende of onleesbare sleutels zijn `null`,
/// het is aan de preflight om te beslissen of dat genoeg is.
JitsiDeploymentConfig parseJitsiConfig(String source) {
  final clean = _stripComments(source);
  return JitsiDeploymentConfig(
    websocket: _lastValue(clean, 'websocket'),
    bosh: _lastValue(clean, 'bosh'),
    domain: _hostField(clean, 'domain'),
    anonymousDomain: _hostField(clean, 'anonymousdomain'),
    muc: _hostField(clean, 'muc'),
    focus: _hostField(clean, 'focus'),
  );
}

/// Laatste `key: 'v'` of `config.key = 'v'` voor een top-level sleutel.
/// `\b` voorkomt dat `websocketKeepAliveUrl` als `websocket` meetelt.
String? _lastValue(String js, String key) {
  final escaped = RegExp.escape(key);
  return _lastOf([
    (js, 0, RegExp("\\b$escaped\\b\\s*[:=]\\s*'([^']*)'")),
    (js, 0, RegExp('\\b$escaped\\b\\s*[:=]\\s*"([^"]*)"')),
  ]);
}

/// Laatste `hosts`-sleutel op positie: `config.hosts.<k> = 'v'` (de
/// append-vorm van custom-config.js) én `<k>: 'v'` binnen `hosts: {…}`. De
/// match die het laatst in de bron staat wint — zo overschrijft een
/// toewijzing achteraan het object eerder in het bestand.
String? _hostField(String js, String key) {
  final escaped = RegExp.escape(key);
  final sources = <(String, int, RegExp)>[
    (js, 0, RegExp("\\bhosts\\s*\\.\\s*$escaped\\b\\s*[:=]\\s*'([^']*)'")),
    (js, 0, RegExp('\\bhosts\\s*\\.\\s*$escaped\\b\\s*[:=]\\s*"([^"]*)"')),
  ];
  final block = _objectAfter(js, 'hosts');
  if (block != null) {
    sources.addAll([
      (block.$2, block.$1, RegExp("\\b$escaped\\b\\s*:\\s*'([^']*)'")),
      (block.$2, block.$1, RegExp('\\b$escaped\\b\\s*:\\s*"([^"]*)"')),
    ]);
  }
  return _lastOf(sources);
}

/// Laatste capture over alle (tekst, offset, regex)-bronnen — de offset
/// schuift matches uit een sub-object naar hun echte positie in het origineel,
/// en de tekst grenst het zoekgebied af aan dat ene object.
String? _lastOf(List<(String text, int offset, RegExp re)> sources) {
  var bestPos = -1;
  String? best;
  for (final (text, offset, re) in sources) {
    for (final m in re.allMatches(text)) {
      final pos = offset + m.start;
      if (pos >= bestPos) {
        bestPos = pos;
        best = m.group(1);
      }
    }
  }
  return best;
}

/// De tekst van het object na `key: {` als (startpositie, inhoud) —
/// brace-counting. Waardes met `}` breken de teller; de hosts-sleutels die we
/// zoeken bevatten geen accolades, dus een misvormde invoer levert hooguit
/// `null` op.
(int, String)? _objectAfter(String js, String key) {
  final re = RegExp("\\b${RegExp.escape(key)}\\b\\s*:\\s*\\{");
  Match? found;
  for (final match in re.allMatches(js)) {
    found = match;
  }
  if (found == null) return null;
  var depth = 0;
  for (var i = found.end - 1; i < js.length; i++) {
    if (js[i] == '{') depth++;
    if (js[i] == '}') {
      depth--;
      if (depth == 0) return (found.end, js.substring(found.end, i));
    }
  }
  return null;
}

/// Stript `//…` en `/*…*/` met behoud van string-inhoud (`'…'`, `"…"`,
/// `` `…` ``). Zonder dit zou `// bosh: 'x'` als echte sleutel meetellen —
/// upstream-configs staan er vol mee.
String _stripComments(String js) {
  final out = StringBuffer();
  var inSingle = false, inDouble = false, inTemplate = false;
  var inLineComment = false, inBlockComment = false;
  for (var i = 0; i < js.length; i++) {
    final c = js[i];
    final next = i + 1 < js.length ? js[i + 1] : '';
    if (inLineComment) {
      if (c == '\n') {
        inLineComment = false;
        out.write(c);
      }
      continue;
    }
    if (inBlockComment) {
      if (c == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (inSingle || inDouble || inTemplate) {
      out.write(c);
      if (c == '\\') {
        if (next.isNotEmpty) {
          out.write(next);
          i++;
        }
        continue;
      }
      if (inSingle && c == "'") inSingle = false;
      if (inDouble && c == '"') inDouble = false;
      if (inTemplate && c == '`') inTemplate = false;
      continue;
    }
    if (c == '/' && next == '/') {
      inLineComment = true;
      continue;
    }
    if (c == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (c == "'") inSingle = true;
    if (c == '"') inDouble = true;
    if (c == '`') inTemplate = true;
    out.write(c);
  }
  return out.toString();
}
