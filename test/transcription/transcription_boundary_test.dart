// De scheidslijn die het hele epiek beschermt (#2510, TRANSCRIPTION.md
// §4.3): code in `lib/services/transcription/` mag nooit stil audio of
// transcript naar de bestaande AI- of opslagroutes sturen. Die belofte is
// alleen echt als hij structureel geldt — een code-review kan een import
// missen, deze toets niet.
//
// De regel is bewust grof: géén import van de AI-laag, van
// opslag-/netwerkdiensten, of van HTTP/WebSocket-pakketten. De serverroute
// uit #2524 komt straks als eigen profiel mét eigen egress-bewijs
// (NetGuard + consent per taak) — deze toets blijft dan bestaan, met het
// serverprofiel als enige doorgaans bekende uitzondering.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Directory('lib/services/transcription');

  // De scheidslijn in één lijstje: wat hier staat mag de transcriptielaag
  // nooit importeren — niet direct, niet "even" voor een logregel.
  const forbidden = [
    'ai_client',
    'ai_security_gate',
    'ai_translate',
    'webdav',
    's3_service',
    'oci_serve',
    'ociserve',
    'package:http',
    'dart:io',
    'dart:html',
    'package:web',
    'websocket',
  ];

  test('de transcriptielaag kent geen AI- of netwerkafhankelijkheid', () {
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.dart'),
    );
    expect(files, isNotEmpty, reason: 'de laag bestaat');

    for (final file in files) {
      final isIo = file.path.endsWith('_io.dart');
      final isWeb = file.path.endsWith('_web.dart');
      final imports = RegExp(
        "import\\s+'([^']+)'",
      ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!);
      for (final uri in imports) {
        for (final bad in forbidden) {
          // `dart:io` en `package:web` zijn de twee toegestane uitzonderingen,
          // elk alleen in zijn eigen gesplitste helft: `_io` is waar het
          // bestandssysteem en de NetGuard-sockets horen, `_web` is waar de
          // browser-API's horen — IndexedDB voor de modelopslag, WebCrypto voor
          // de hash en de gebruiker-gestarte `fetch` voor het model (#2513).
          // De fetch daar is het web-equivalent van de NetGuard-route: de
          // browser toetst elke redirect-hop via CORS.
          if (bad == 'dart:io' && isIo) continue;
          if (bad == 'package:web' && isWeb) continue;
          expect(
            uri.contains(bad),
            isFalse,
            reason: '${file.path} importeert $uri — dat raakt $bad',
          );
        }
      }
    }
  });

  test('de laag mag state/ en widgets/ niet kennen (laagregel)', () {
    for (final file in dir.listSync().whereType<File>()) {
      final text = file.readAsStringSync();
      for (final bad in ["'../state/", "'../widgets/"]) {
        expect(
          text.contains(bad),
          isFalse,
          reason: '${file.path} importeert $bad — services staan onderaan',
        );
      }
    }
  });
}
