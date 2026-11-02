"""Zelftoets van het fetch-hulppunt.

Draait als `python3 -I -B server/fetch-proxy/test_ocideck_fetch_proxy.py`, en
via test/fetch_proxy_selftest_test.dart in `make check` — anders toetst niets
dit bestand.
"""

import importlib.util
import io
import os
import socket
import threading
import unittest
from contextlib import redirect_stderr

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


if __name__ == "__main__":
    unittest.main()
