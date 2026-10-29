// OciDeck — bootstrap loader with a file:// guard (#2661).
//
// External file because the page CSP forbids inline script
// (script-src 'self' 'wasm-unsafe-eval', no 'unsafe-inline').
//
// The bundle only works over http(s). Opened straight from disk (file://)
// every browser refuses the pieces the engine needs — wasm and module
// fetches fail CORS, the service worker may not register — and the console
// fills with errors that end in a dead page. Better to say so plainly, in
// the same splash slot the loader uses, than to boot halfway.
(function () {
  'use strict';

  if (location.protocol !== 'http:' && location.protocol !== 'https:') {
    var host = document.getElementById('splash') || document.body;
    if (host === document.body) {
      host = document.createElement('div');
      host.style.cssText =
        'position:fixed;inset:0;display:flex;flex-direction:column;' +
        'align-items:center;justify-content:center;gap:10px;' +
        'background:#14161b;color:#e8ecf3;' +
        'font:15px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,' +
        '"Helvetica Neue",Arial,sans-serif;';
      document.body.appendChild(host);
    }
    host.style.zIndex = '1';
    host.innerHTML =
      '<img src="app-icons/Icon-192.png" alt="" width="72" height="72">' +
      '<p style="margin:0;font-weight:600">OciDeck</p>' +
      '<p style="margin:0;color:#8b95a6;font-size:13px;text-align:center">' +
      'OciDeck-web werkt niet vanaf een geopend bestand (file://).<br>' +
      'OciDeck-web cannot run from an opened file (file://).</p>' +
      '<p style="margin:0;color:#8b95a6;font-size:13px;text-align:center">' +
      'Serveer deze map over HTTP — bijvoorbeeld ' +
      '<code>python3 -m http.server</code> — en open ' +
      '<code>http://localhost:8000</code>.<br>' +
      'Serve this folder over HTTP — e.g. <code>python3 -m http.server</code>' +
      ' — then open <code>http://localhost:8000</code>.</p>';
    return;
  }

  // Same effect as <script src="flutter_bootstrap.js" async>: the engine
  // starts fetching immediately and runs when ready. Injected rather than
  // written as a tag so the file:// branch above can skip it entirely.
  var bootstrap = document.createElement('script');
  bootstrap.src = 'flutter_bootstrap.js';
  bootstrap.async = true;
  document.body.appendChild(bootstrap);
})();
