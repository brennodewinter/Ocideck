// Upstream bouwt config.websocket als wss://{PUBLIC_URL zonder https://} —
// bij DISABLE_HTTPS=1 met PUBLIC_URL=http://localhost:8000 wordt dat
// 'wss://http://localhost:8000/…' en kan geen client verbinden. Dit bestand
// wordt achter config.js geplakt en overschrijft met letterlijke waarden.
//
// Bewust letterlijk 127.0.0.1 (niet location.host): de testbed is loopback-
// only by design, en OciDeck's deploymentlezer (jitsi_config.dart) leest
// config.js als tekst — een expressie kan hij niet evalueren, en dat is
// precies de bedoeling. ws:// op een letterlijk loopback-adres is ook de
// enige niet-TLS-vorm die OciDeck's transport accepteert.
config.websocket = 'ws://127.0.0.1:8000/xmpp-websocket';
config.bosh = 'http://127.0.0.1:8000/http-bind';
