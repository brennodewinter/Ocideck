#!/usr/bin/env python3
"""Probe server: serves files, optionally with COOP/COEP, collects POST /result."""
import http.server, json, sys, time, pathlib

COI = '--coi' in sys.argv
OUT = pathlib.Path('/tmp/wasm-probe/results')
OUT.mkdir(exist_ok=True)
LOG = pathlib.Path('/tmp/wasm-probe/netlog.txt')
LOG.touch()

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        if COI:
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        if self.path == '/result':
            ts = time.strftime('%H%M%S')
            try:
                d = json.loads(body)
                name = f"{d.get('model','?')}-{d.get('audio','?')}-t{d.get('threads','?')}-{'coi' if COI else 'nocoi'}-{ts}.json"
            except Exception:
                name = f'raw-{ts}.json'
            (OUT / name).write_bytes(body)
        elif self.path == '/netlog':
            with LOG.open('ab') as f:
                f.write(body + b'\n')
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        with LOG.open('a') as f:
            f.write('%s %s\n' % (self.address_string(), fmt % args))

# Serveer root: --root <dir> of cwd. COI-variant: --coi.
ROOT = pathlib.Path.cwd()
if '--root' in sys.argv:
    ROOT = pathlib.Path(sys.argv[sys.argv.index('--root') + 1]).resolve()

import functools
PORT = 8931
if '--port' in sys.argv:
    PORT = int(sys.argv[sys.argv.index('--port') + 1])
handler = functools.partial(H, directory=str(ROOT))
http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler).serve_forever()
