const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const zlib = require('node:zlib');

module.exports = function createServer(root, mode) {
  const config = fs.readFileSync(path.join(root, '.htaccess'), 'utf8');
  const types = {'.html':'text/html', '.js':'text/javascript', '.mjs':'text/javascript',
    '.wasm':'application/wasm', '.json':'application/json', '.ttf':'font/ttf',
    '.otf':'font/otf', '.png':'image/png', '.svg':'image/svg+xml', '.css':'text/css'};
  const cache = new Map();
  const {fixtures} = require('./scenarios.cjs');
  return http.createServer((req, res) => {
    try {
      // A subdirectory deployment catches absolute asset/bootstrap paths as well.
      const url = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      if (!url.startsWith('/ocideck/')) { res.writeHead(404).end(); return; }
      const relative = url.slice('/ocideck/'.length) || 'index.html';
      const fixture = fixtures.get(relative);
      if (fixture) {
        res.writeHead(200, {'Content-Type':fixture.type}).end(fixture.bytes);
        return;
      }
      const file = path.resolve(root, relative);
      if (!file.startsWith(root + path.sep) || !fs.statSync(file).isFile()) {
        res.writeHead(404).end(); return;
      }
      if (!cache.has(file)) {
        let bytes = fs.readFileSync(file);
        if (mode === 'fallback' && relative === 'flutter_bootstrap.js') {
          const original = bytes.toString();
          const altered = original.replace(/wasmAllowList:\s*\{[^}]*\}/,
            'wasmAllowList: {blink: false, webkit: false, gecko: false}');
          if (original === altered) throw new Error('No wasmAllowList to override');
          bytes = Buffer.from(altered);
        }
        cache.set(file, zlib.gzipSync(bytes));
      }
      const headers = {'Content-Type':types[path.extname(file)] || 'application/octet-stream',
        'Content-Encoding':'gzip', 'Cache-Control':'no-cache'};
      for (const [, name, value] of config.matchAll(/Header always set ([\w-]+) "([^"]*)"/g)) {
        if (name === 'Cache-Control') continue;
        if (mode === 'single-thread' && name.startsWith('Cross-Origin-')) continue;
        headers[name] = value;
      }
      res.writeHead(200, headers).end(cache.get(file));
    } catch (error) { res.writeHead(404).end(String(error)); }
  });
};
