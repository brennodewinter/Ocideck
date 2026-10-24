// Upstream bouwt config.websocket als wss://{PUBLIC_URL zonder https://} —
// bij DISABLE_HTTPS=1 met PUBLIC_URL=http://localhost:8000 wordt dat
// 'wss://http://localhost:8000/…' en kan geen client verbinden. Leid schema
// en host af van waar de pagina zelf vandaan komt; werkt op elke poort en
// zowel http als https. Dit bestand wordt achter config.js geplakt.
config.websocket =
    (location.protocol === 'https:' ? 'wss://' : 'ws://') +
    location.host + '/xmpp-websocket';
config.bosh = location.protocol + '//' + location.host + '/http-bind';
