"""Zelftoets van het fetch-hulppunt.

Draait als `python3 -I -B server/fetch-proxy/test_ocideck_fetch_proxy.py`, en
via test/fetch_proxy_selftest_test.dart in `make check` — anders toetst niets
dit bestand.
"""

import importlib.util
import io
import os
import socket
import struct
import threading
import unittest
from contextlib import redirect_stderr
from unittest import mock

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "ocideck_fetch_proxy", os.path.join(_HERE, "ocideck_fetch_proxy.py")
)
proxy = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(proxy)


class _Proxy:
    """Het hulppunt op een vrije loopbackpoort, in een eigen draad."""

    def __enter__(self):
        self.server = proxy.ThreadingHTTPServer(("127.0.0.1", 0), proxy.Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return self.server.server_address[1]

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


def _exchange(port, request, timeout=5):
    """Stuurt [request] en leest tot de server de verbinding sluit."""
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as conn:
        conn.sendall(request)
        data = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                return data
            data += chunk


class AccessLogTest(unittest.TestCase):
    def test_log_lines_carry_no_target_url(self):  # #2754
        err = io.StringIO()
        with redirect_stderr(err), _Proxy() as port:
            # Geweigerd zonder Sec-Fetch-Site: de gewone toegangsregel.
            _exchange(
                port,
                b"GET /?url=https%3A%2F%2Fexample.test%2Fgeheim-token HTTP/1.1\r\n"
                b"Host: x\r\nConnection: close\r\n\r\n",
            )
            # Een onleesbare verzoekregel: send_error zet die regel in zijn
            # bericht, en dat bericht ging ook naar het log.
            _exchange(port, b"GET /?url=a geheim-token HTTP/1.1\r\n\r\n")
        log = err.getvalue()
        self.assertNotIn("geheim-token", log)
        self.assertIn("GET 403", log)
        self.assertIn(" 400 ", log)


def _breaking_source():
    """Een bron die 1000 bytes aankondigt, er 10 stuurt en dan reset."""
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)

    def serve():
        conn, _ = listener.accept()
        conn.recv(65536)
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n0123456789")
        # SO_LINGER 0: close() stuurt een RST, zoals een bron die wegvalt.
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        conn.close()
        listener.close()

    threading.Thread(target=serve, daemon=True).start()
    return listener.getsockname()[1]


class MidStreamFailureTest(unittest.TestCase):
    def test_source_lost_after_headers_closes_without_second_response(self):  # #2755
        source = _breaking_source()
        with mock.patch.object(proxy, "ALLOW_ANY", True), mock.patch.object(
            proxy, "ALLOWED_PORTS", {source}
        ), mock.patch.object(
            proxy, "resolve_pinned", lambda host, port: "127.0.0.1"
        ), redirect_stderr(io.StringIO()), _Proxy() as port:
            # Bewust zonder Connection: close — de proxy moet zelf afbreken,
            # anders wacht de client op bytes die nooit komen.
            reply = _exchange(
                port,
                b"GET /?url=http%%3A%%2F%%2Fbron.test%%3A%d%%2Fdeck HTTP/1.1\r\n"
                b"Host: x\r\n\r\n" % source,
            )
        self.assertTrue(reply.startswith(b"HTTP/1.1 200"), reply)
        self.assertEqual(reply.count(b"HTTP/1.1 "), 1, reply)


if __name__ == "__main__":
    unittest.main()
