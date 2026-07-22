import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// De geregistreerde luisteraar, of null wanneer er niets openstaat. Bewaard
/// zodat afmelden dezelfde functie meegeeft — `removeEventListener` werkt op
/// identiteit, dus een nieuw gemaakte closure haalt niets weg.
web.EventListener? _listener;

/// Web: `beforeunload` tegenhouden zolang er niet-opgeslagen werk is.
///
/// Het gedrag is bij elke moderne browser hetzelfde: zowel `preventDefault()`
/// als een niet-lege `returnValue` telt als "vraag het de gebruiker", en welke
/// van de twee gehonoreerd wordt verschilt per browser — vandaar allebei. De
/// tekst is niet te kiezen; de browser toont zijn eigen zin.
///
/// Alleen registreren wanneer het nodig is. Een altijd aanwezige luisteraar
/// laat sommige browsers de pagina uit hun snelle terug-cache (bfcache) houden,
/// en dat maakt de app trager voor iedereen die niets onopgeslagen heeft.
void setUnsavedWorkGuard(bool hasUnsavedWork) {
  if (hasUnsavedWork) {
    if (_listener != null) return;
    _listener = ((web.Event event) {
      event.preventDefault();
      (event as web.BeforeUnloadEvent).returnValue = '1';
    }).toJS;
    web.window.addEventListener('beforeunload', _listener);
    return;
  }
  if (_listener == null) return;
  web.window.removeEventListener('beforeunload', _listener);
  _listener = null;
}
