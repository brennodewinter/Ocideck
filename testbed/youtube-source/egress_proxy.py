"""Per-job CONNECT proxy for the explicit operator's YouTube source helper.

The downloader does not inherit Dart NetGuard. Each HTTPS connection is
resolved here, refused unless every IPv4 answer is public, and opened by
numeric address. TLS remains end-to-end and validates the original hostname.
Only YouTube's extraction/media hosts and port 443 are permitted. This is a
transport boundary for the pinned downloader, not an OS process sandbox.
"""
import hmac
import ipaddress
import re
import secrets
import select
import socket
import socketserver
import threading
import time


class EgressRefused(Exception):
    pass


def allowed_host(host):
    if not re.fullmatch(r'[a-z0-9.-]{1,253}', host):
        return False
    return any(host == base or host.endswith('.' + base) for base in (
        'youtube.com', 'youtube-nocookie.com', 'googlevideo.com',
        'ytimg.com', 'ggpht.com', 'gstatic.com', 'youtubei.googleapis.com'))


def public_ipv4(host, resolve=socket.getaddrinfo):
    if not allowed_host(host):
        raise EgressRefused('host')
    rows = resolve(host, 443, socket.AF_INET, socket.SOCK_STREAM)
    addresses = list(dict.fromkeys(row[4][0] for row in rows))
    if not addresses or any(not _public_address(ip) for ip in addresses):
        raise EgressRefused('address')
    return addresses[0]


def _public_address(value):
    address = ipaddress.ip_address(value)
    return (address.version == 4 and address.is_global and
            not address.is_multicast and not address.is_reserved)


class _Handler(socketserver.BaseRequestHandler):
    def handle(self):
        upstream = None
        try:
            self.request.settimeout(10)
            data = bytearray()
            # Read only the header; the TLS client waits for CONNECT success.
            while not data.endswith(b'\r\n\r\n'):
                chunk = self.request.recv(1)
                if not chunk or len(data) >= 8192:
                    raise EgressRefused('header')
                data.extend(chunk)
            host = self._destination(bytes(data))
            address = public_ipv4(host)
            upstream = socket.create_connection((address, 443), timeout=10)
            with self.server.sockets_lock:
                self.server.sockets.add(upstream)
            self.request.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
            self._tunnel(upstream)
        except (OSError, ValueError, EgressRefused):
            try:
                self.request.sendall(b'HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
            except OSError:
                pass
        finally:
            if upstream is not None:
                upstream.close()
                with self.server.sockets_lock:
                    self.server.sockets.discard(upstream)

    def _destination(self, data):
        lines = data.decode('ascii').split('\r\n')
        match = re.fullmatch(r'CONNECT ([a-z0-9.-]+):443 HTTP/1\.[01]', lines[0])
        if not match:
            raise EgressRefused('method')
        values = [line.split(':', 1)[1].strip() for line in lines[1:]
                  if line.lower().startswith('proxy-authorization:')]
        if len(values) != 1 or not hmac.compare_digest(
                values[0], self.server.authorization):
            raise EgressRefused('authorization')
        return match[1]

    def _tunnel(self, upstream):
        peers = (self.request, upstream)
        while not self.server.stop_event.is_set():
            if time.monotonic() >= self.server.deadline:
                return
            readable, _, _ = select.select(peers, [], [], .1)
            for source in readable:
                data = source.recv(65536)
                if not data or not self.server.charge(len(data)):
                    return
                target = upstream if source is self.request else self.request
                target.sendall(data)


class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = False
    daemon_threads = True

    def verify_request(self, request, client_address):
        return self.concurrency.acquire(blocking=False)

    def process_request_thread(self, request, client_address):
        with self.sockets_lock:
            self.sockets.add(request)
        try:
            super().process_request_thread(request, client_address)
        finally:
            with self.sockets_lock:
                self.sockets.discard(request)
            self.concurrency.release()

    def charge(self, size):
        with self.budget_lock:
            self.remaining -= size
            return self.remaining >= 0


class YoutubeEgressProxy:
    def __init__(self, *, max_bytes=32 * 1024 * 1024, timeout=120):
        import base64
        token = secrets.token_hex(24)
        self.server = _Server(('127.0.0.1', 0), _Handler)
        self.server.authorization = 'Basic ' + base64.b64encode(
            ('ocideck:' + token).encode()).decode()
        self.server.remaining = max_bytes
        self.server.budget_lock = threading.Lock()
        self.server.stop_event = threading.Event()
        self.server.concurrency = threading.BoundedSemaphore(8)
        self.server.sockets = set()
        self.server.sockets_lock = threading.Lock()
        self.server.deadline = time.monotonic() + timeout
        self.url = f'http://ocideck:{token}@127.0.0.1:{self.server.server_address[1]}'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.stop_event.set()
        self.server.shutdown()
        self.server.server_close()
        with self.server.sockets_lock:
            for connection in self.server.sockets:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()
        self.thread.join(timeout=2)
