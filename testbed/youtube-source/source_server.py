"""Explicit loopback source server; never enabled by opening a deck/URL."""
import argparse
import importlib.util
import json
import os
import pathlib
import ssl
import signal
import socket
import threading
from http.server import ThreadingHTTPServer

from source_runtime import SourceFailure, YoutubeRuntime


_SHARED = pathlib.Path(__file__).resolve().parents[1] / 'asr-diarization/server.py'
_SPEC = importlib.util.spec_from_file_location('source_http_shared', _SHARED)
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)
PREFIX = '/ocideck-youtube/v1/'


class SourceHandler(_MODULE.Handler):
    def setup(self):
        super().setup()
        with self.server.connections_lock:
            self.server.connections.add(self.connection)

    def finish(self):
        try:
            super().finish()
        finally:
            with self.server.connections_lock:
                self.server.connections.discard(self.connection)

    def do_GET(self):
        if not self._authorized():
            self._reply(401, {'error': 'access'})
        elif self.path == PREFIX + 'capabilities':
            self._reply(200, {'protocol': 'ocideck-youtube', 'version': 1,
                              'captions': True, 'audio': self.server.runtime.decoder is not None,
                              'audio_fragments': self.server.runtime.decoder is not None,
                              'audio_encoding': 'pcm16-wav',
                              'max_audio_bytes': 8 * 1024 * 1024})
        else:
            self._reply(404, {'error': 'unavailable'})

    def do_POST(self):
        if not self._authorized():
            self._reply(401, {'error': 'access'})
            return
        action = self.path.removeprefix(PREFIX)
        if not self.path.startswith(PREFIX) or action not in ('metadata', 'captions', 'audio'):
            self._reply(404, {'error': 'unavailable'})
            return
        if not self.server.busy.acquire(blocking=False):
            self._reply(503, {'error': 'busy'})
            return
        try:
            self._process(action)
        except SourceFailure as error:
            status = {'access': 403, 'rateLimited': 429, 'tooLarge': 413,
                      'live': 409, 'missingHelper': 503}.get(error.code, 422)
            self._reply(status, {'error': error.code})
        except (ValueError, OSError, TimeoutError):
            self._reply(422, {'error': 'protocol'})
        except Exception:
            self._reply(500, {'error': 'network'})
        finally:
            self.server.busy.release()

    def _process(self, action):
        length = int(self.headers.get('Content-Length', '0'))
        if (not 0 < length <= 4096 or self.headers.get('Transfer-Encoding') or
                self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json'):
            raise SourceFailure('protocol')
        data = self.rfile.read(length)
        if len(data) != length:
            raise SourceFailure('protocol')
        fields = json.loads(data)
        if not isinstance(fields, dict):
            raise SourceFailure('protocol')
        result = self.server.runtime.execute(action, fields,
            cancelled=lambda: self.server.stopping.is_set() or self._peer_closed())
        self._reply(200, {'protocol': 'ocideck-youtube', 'version': 1,
                          'video_id': fields['video_id'], **result})


class SourceHTTPServer(ThreadingHTTPServer):
    # Wait for cancelled jobs to reap their groups and remove private staging
    # before the operator process exits, including on SIGTERM/Ctrl-C.
    daemon_threads = False

    def stop(self):
        self.stopping.set()
        with self.connections_lock:
            connections = tuple(self.connections)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.shutdown()


def create_server(runtime, *, port, origin=None, token='', cert=None, key=None):
    server = SourceHTTPServer(('127.0.0.1', port), SourceHandler)
    server.runtime = runtime
    server.origin = origin
    server.token = token
    server.busy = threading.BoundedSemaphore(1)
    server.stopping = threading.Event()
    server.connections = set()
    server.connections_lock = threading.Lock()
    if bool(cert) != bool(key):
        server.server_close()
        raise ValueError('TLS certificate and key must be supplied together')
    if cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node', required=True, type=pathlib.Path)
    parser.add_argument('--decoder-registration', type=pathlib.Path)
    parser.add_argument('--port', type=int, default=8866)
    parser.add_argument('--origin', help='Exact allowed browser origin, no wildcard')
    parser.add_argument('--cert', type=pathlib.Path)
    parser.add_argument('--key', type=pathlib.Path)
    args = parser.parse_args()
    if args.origin and (not args.origin.startswith(('http://', 'https://')) or '*' in args.origin):
        parser.error('Provide one exact browser origin')
    runtime = YoutubeRuntime(args.node, args.decoder_registration)
    server = create_server(runtime, port=args.port, origin=args.origin,
                           token=os.environ.get('OCIDECK_YOUTUBE_TOKEN', ''),
                           cert=args.cert, key=args.key)
    def stop_server(*_):
        threading.Thread(target=server.stop, daemon=True).start()
    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.stopping.set()
        server.server_close()
