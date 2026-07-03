#!/usr/bin/env python3
"""OciDeck fetch-hulppunt: haalt een deck-URL server-zijdig op voor de webversie.

De browser mag cross-origin alleen lezen van servers die CORS sturen; de
meeste bronnen doen dat niet. De webapp probeert daarom eerst direct te
fetchen en valt terug op dit same-origin hulppunt: GET /?url=<encoded>.

Dit is per definitie een server-side fetcher en dus een SSRF-doelwit; de
regels hieronder spiegelen NetGuard (lib/utils/net_guard.dart) van de app:

  * alleen http/https;
  * doelhost wordt éérst geresolved; ELK adres moet publiek zijn
    (loopback, RFC1918, link-local, CGNAT 100.64/10, ULA fc00::/7,
    multicast, unspecified en ge-embedde IPv4-in-IPv6 worden geweigerd);
  * de verbinding wordt gepind op het gevalideerde adres, zodat een
    DNS-rebind tussen check en connect nergens heen kan (TLS valideert
    tegen de oorspronkelijke hostnaam via SNI);
  * redirects worden niet gevolgd (een 3xx kan naar binnen wijzen);
  * de respons is begrensd (standaard 512 MiB) en wordt gestreamd
    doorgegeven als application/octet-stream — de app zelf blijft de
    enige die de inhoud valideert (magic bytes, veiligheidsscan, parse).

Draait als eigen gebruiker achter de webserver, bv. Apache:

    ProxyPass "/fetch-proxy" "http://127.0.0.1:8123/"

Omgevingsvariabelen: OCIDECK_PROXY_BIND (127.0.0.1), OCIDECK_PROXY_PORT
(8123), OCIDECK_PROXY_MAX_BYTES (536870912), OCIDECK_PROXY_ALLOWED_ORIGINS
(komma-lijst; indien gezet moet Origin of Referer ermee beginnen).
"""

import http.client
import ipaddress
import os
import socket
import ssl
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BIND = os.environ.get("OCIDECK_PROXY_BIND", "127.0.0.1")
PORT = int(os.environ.get("OCIDECK_PROXY_PORT", "8123"))
MAX_BYTES = int(os.environ.get("OCIDECK_PROXY_MAX_BYTES", str(512 * 1024 * 1024)))
ALLOWED_ORIGINS = [
    o.strip().rstrip("/")
    for o in os.environ.get("OCIDECK_PROXY_ALLOWED_ORIGINS", "").split(",")
    if o.strip()
]
CONNECT_TIMEOUT = 15
READ_TIMEOUT = 60
CHUNK = 64 * 1024


def blocked_ip(ip: ipaddress._BaseAddress) -> bool:
    """Spiegel van NetGuard.isBlockedAddress: alles wat niet publiek
    routeerbaar is wordt geweigerd, inclusief IPv4 die in een IPv6-adres is
    ge-embed (mapped ::ffff:0:0/96, compatible ::/96, NAT64 64:ff9b::/96)."""
    if isinstance(ip, ipaddress.IPv6Address):
        embedded = ip.ipv4_mapped
        if embedded is None and ip in ipaddress.ip_network("64:ff9b::/96"):
            embedded = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
        if embedded is None and ip in ipaddress.ip_network("::/96") and int(ip):
            embedded = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
        if embedded is not None:
            return blocked_ip(embedded)
    # is_global is de strengste vlag: False voor loopback, privé (RFC1918 én
    # fc00::/7), link-local, CGNAT 100.64/10, multicast, unspecified, reserved.
    return not ip.is_global


def resolve_pinned(host: str, port: int):
    """NetGuard.safeResolve: resolve de host en weiger zodra ÉÉN adres
    intern is; geef anders het eerste adres terug om de socket op te pinnen."""
    lowered = host.lower().rstrip(".")
    if not lowered or lowered == "localhost" or lowered.endswith(".localhost"):
        return None
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except OSError:
        return None
    addrs = []
    for info in infos:
        try:
            addrs.append(ipaddress.ip_address(info[4][0]))
        except ValueError:
            return None
    if not addrs or any(blocked_ip(a) for a in addrs):
        return None
    return str(addrs[0])


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    """HTTPS naar een gepind IP, met SNI en certificaatvalidatie tegen de
    oorspronkelijke hostnaam — de TLS-laag dwingt zo af dat het gepinde adres
    echt de gevraagde server is."""

    def __init__(self, pinned_ip: str, hostname: str, port: int):
        self._pinned_ip = pinned_ip
        self._tls_hostname = hostname
        ctx = ssl.create_default_context()
        super().__init__(
            hostname, port, timeout=CONNECT_TIMEOUT, context=ctx
        )

    def connect(self):
        raw = socket.create_connection(
            (self._pinned_ip, self.port), timeout=self.timeout
        )
        self.sock = self._context.wrap_socket(
            raw, server_hostname=self._tls_hostname
        )


class PinnedHTTPConnection(http.client.HTTPConnection):
    def __init__(self, pinned_ip: str, hostname: str, port: int):
        self._pinned_ip = pinned_ip
        super().__init__(hostname, port, timeout=CONNECT_TIMEOUT)

    def connect(self):
        self.sock = socket.create_connection(
            (self._pinned_ip, self.port), timeout=self.timeout
        )


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "OciDeckFetchProxy/1"

    def log_message(self, fmt, *args):  # geen URL's in de log (privacy)
        sys.stderr.write("fetch-proxy: %s\n" % (fmt % args))

    def _refuse(self, code: int, reason: str):
        body = reason.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _origin_allowed(self) -> bool:
        if not ALLOWED_ORIGINS:
            return True
        for header in ("Origin", "Referer"):
            value = (self.headers.get(header) or "").rstrip("/")
            if any(
                value == o or value.startswith(o + "/") for o in ALLOWED_ORIGINS
            ):
                return True
        return False

    def do_GET(self):  # noqa: N802 (http.server-conventie)
        if not self._origin_allowed():
            return self._refuse(403, "origin niet toegestaan")
        query = parse_qs(urlparse(self.path).query)
        target = (query.get("url") or [""])[0].strip()
        parsed = urlparse(target)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            return self._refuse(400, "alleen http(s)-URL's")
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        pinned = resolve_pinned(parsed.hostname, port)
        if pinned is None:
            return self._refuse(403, "host niet toegestaan")

        conn_cls = (
            PinnedHTTPSConnection if parsed.scheme == "https" else PinnedHTTPConnection
        )
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        try:
            conn = conn_cls(pinned, parsed.hostname, port)
            try:
                # http.client zet zelf de Host-header op de hostnaam die aan
                # de constructor is gegeven — het gepinde IP blijft onzichtbaar.
                conn.request(
                    "GET",
                    path,
                    headers={
                        "User-Agent": "OciDeckFetchProxy/1",
                        "Accept": "*/*",
                    },
                )
                conn.sock.settimeout(READ_TIMEOUT)
                resp = conn.getresponse()
                if 300 <= resp.status < 400:
                    return self._refuse(502, "redirects worden niet gevolgd")
                if resp.status != 200:
                    return self._refuse(502, "bron gaf status %d" % resp.status)
                declared = resp.getheader("Content-Length")
                if declared and declared.isdigit() and int(declared) > MAX_BYTES:
                    return self._refuse(502, "bestand te groot")

                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("Cache-Control", "no-store")
                if declared and declared.isdigit():
                    self.send_header("Content-Length", declared)
                    chunked = False
                else:
                    self.send_header("Transfer-Encoding", "chunked")
                    chunked = True
                self.end_headers()

                total = 0
                while True:
                    chunk = resp.read(CHUNK)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_BYTES:
                        # Te groot: verbinding kappen; de client ziet een
                        # afgebroken respons en behandelt dat als mislukt.
                        self.close_connection = True
                        return
                    if chunked:
                        self.wfile.write(b"%x\r\n" % len(chunk))
                        self.wfile.write(chunk)
                        self.wfile.write(b"\r\n")
                    else:
                        self.wfile.write(chunk)
                if chunked:
                    self.wfile.write(b"0\r\n\r\n")
            finally:
                conn.close()
        except (OSError, ssl.SSLError, http.client.HTTPException):
            # Bronhost/route defect of TLS-weigering: één neutrale melding,
            # zonder de (mogelijk gevoelige) doel-URL te echoën.
            try:
                self._refuse(502, "kon de bron niet bereiken")
            except OSError:
                pass


def main():
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    sys.stderr.write(
        "fetch-proxy: luistert op %s:%d (cap %d bytes, origins: %s)\n"
        % (BIND, PORT, MAX_BYTES, ", ".join(ALLOWED_ORIGINS) or "alle")
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
