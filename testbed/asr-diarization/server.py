"""Loopback-only reference server for the optional OciDeck ASR v1 route.

No request, audio, transcript or embedding logs. No downloads, persistence,
redirects, cloud fallback or speaker identity database. Models are explicit.
Only expose the container port on host loopback; this is not a deployment kit.
"""
import argparse
import hmac
import json
import os
import threading
import select
import socket
import ssl
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


MAX_BODY = 64 * 1024 * 1024
BUSY = threading.BoundedSemaphore(1)
PREFIX = '/ocideck-asr/v1/'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def _authorized(self):
        origin = self.headers.get('Origin')
        if origin and origin != self.server.origin:
            return False
        token = self.server.token
        return not token or hmac.compare_digest(
            self.headers.get('Authorization', ''), f'Bearer {token}')

    def _reply(self, status, value):
        data = json.dumps(value).encode('utf-8')
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Connection', 'close')
            if self.server.origin and self.headers.get('Origin') == self.server.origin:
                self.send_header('Access-Control-Allow-Origin', self.server.origin)
                self.send_header('Vary', 'Origin')
            self.end_headers()
            self.wfile.write(data)
        except (OSError, TimeoutError):
            pass
        self.close_connection = True

    def do_OPTIONS(self):
        if not self.server.origin or self.headers.get('Origin') != self.server.origin:
            self._reply(403, {'error': 'origin'})
            return
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', self.server.origin)
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        if not self._authorized():
            self._reply(401, {'error': 'authorization'})
        elif self.path == PREFIX + 'capabilities':
            self._reply(200, self.server.backend.capabilities())
        else:
            self._reply(404, {'error': 'path'})

    def do_POST(self):
        if not self._authorized():
            self._reply(401, {'error': 'authorization'})
            return
        if self.path != PREFIX + 'transcribe':
            self._reply(404, {'error': 'path'})
            return
        if not BUSY.acquire(blocking=False):
            self._reply(429, {'error': 'busy'})
            return
        try:
            self._transcribe()
        except (ValueError, OSError, TimeoutError):
            self._reply(422, {'error': 'invalid audio or options'})
        except Exception:
            self._reply(500, {'error': 'processing failed'})
        finally:
            BUSY.release()

    def _transcribe(self):
        length = int(self.headers.get('Content-Length', '0'))
        content_type = self.headers.get('Content-Type', '')
        if (length <= 0 or length > MAX_BODY or len(content_type) > 256 or
                '\r' in content_type or '\n' in content_type or
                not content_type.startswith('multipart/form-data;')):
            raise ValueError('invalid upload')
        body = self.rfile.read(length)
        if len(body) != length:
            raise ValueError('incomplete upload')
        message = BytesParser(policy=default).parsebytes(
            ('Content-Type: ' + content_type + '\r\nMIME-Version: 1.0\r\n\r\n').encode() + body)
        if not message.is_multipart():
            raise ValueError('invalid multipart')
        fields = {}
        for part in message.iter_parts():
            name = part.get_param('name', header='content-disposition')
            if name not in {'language', 'file', 'diarize', 'response_format', 'language_mode'} or name in fields:
                raise ValueError('invalid field')
            fields[name] = part.get_payload(decode=True)
        audio = fields.get('file')
        language = fields.get('language', b'').decode('ascii')
        diarize = fields.get('diarize')
        if not audio or diarize not in (b'true', b'false'):
            raise ValueError('missing options')
        mode = fields.get('language_mode')
        if mode not in (None, b'mixed'):
            raise ValueError('Invalid language mode')
        extra = {'cancelled': self._peer_closed}
        if mode == b'mixed':
            if not self.server.backend.capabilities().get('features', {}).get('language_switching', False):
                raise ValueError('Language switching unavailable')
            extra['language_switching'] = True
        result = self.server.backend.transcribe(audio, language, diarize == b'true', **extra)
        self._reply(200, result)

    def _peer_closed(self):
        try:
            readable, _, _ = select.select([self.connection], [], [], 0)
            if readable and isinstance(self.connection, ssl.SSLSocket):
                # SSLSocket rejects MSG_PEEK. HTTP/1.0 does not pipeline another
                # request; a nonblocking read can consume TLS close_notify.
                timeout = self.connection.gettimeout()
                try:
                    self.connection.setblocking(False)
                    return not self.connection.recv(1)
                except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
                    return False
                finally:
                    self.connection.settimeout(timeout)
            return bool(readable) and not self.connection.recv(1, socket.MSG_PEEK)
        except OSError:
            return True


if __name__ == '__main__':
    from vosk_backend import VoskBackend
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-nl')
    parser.add_argument('--model-en')
    parser.add_argument('--speaker-model')
    parser.add_argument('--container', action='store_true')
    args = parser.parse_args()
    models = {language: path for language, path in
              [('nl', args.model_nl), ('en', args.model_en)] if path}
    if not models:
        parser.error('Install and select at least one model')
    backend = VoskBackend(models, args.speaker_model)
    server = ThreadingHTTPServer(('0.0.0.0' if args.container else '127.0.0.1', 8093), Handler)
    server.backend = backend
    server.token = os.environ.get('OCIDECK_ASR_TOKEN', '')
    server.origin = os.environ.get('OCIDECK_ASR_ORIGIN', '')
    server.serve_forever()
