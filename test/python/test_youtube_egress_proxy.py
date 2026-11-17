import importlib.util
import pathlib
import socket
import threading
import unittest
from unittest import mock


PATH = pathlib.Path(__file__).resolve().parents[2] / 'testbed/youtube-source/egress_proxy.py'
SPEC = importlib.util.spec_from_file_location('youtube_egress_proxy', PATH)
proxy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proxy)


class EgressProxyTests(unittest.TestCase):
    def test_suffix_host_confusion_and_ip_literals_are_refused(self):
        for host in ['youtube.com.evil.test', 'notyoutube.com',
                     '127.0.0.1', '169.254.169.254', 'localhost',
                     'youtube.com@evil.test', 'github.com']:
            resolver = mock.Mock()
            with self.assertRaises(proxy.EgressRefused):
                proxy.public_ipv4(host, resolver)
            resolver.assert_not_called()
        for host in ['www.youtube.com', 'r1---sn-a.googlevideo.com',
                     'i.ytimg.com', 'youtubei.googleapis.com']:
            self.assertTrue(proxy.allowed_host(host))

    def test_all_answers_must_be_public_and_ipv4(self):
        for address in ['127.0.0.1', '10.0.0.1', '192.168.1.1',
                        '169.254.169.254', '100.64.1.1', '172.16.0.1',
                        '0.0.0.0', '224.0.0.1', '240.0.0.1',
                        '192.0.2.1', '::ffff:127.0.0.1']:
            resolver = lambda *_: [
                (None, None, None, None, ('93.184.216.34', 443)),
                (None, None, None, None, (address, 443))]
            with self.assertRaises(proxy.EgressRefused):
                proxy.public_ipv4('www.youtube.com', resolver)
        resolver = mock.Mock(return_value=[
            (None, None, None, None, ('93.184.216.34', 443))])
        self.assertEqual(proxy.public_ipv4('www.youtube.com', resolver),
                         '93.184.216.34')
        resolver.assert_called_once_with('www.youtube.com', 443,
                                         socket.AF_INET, socket.SOCK_STREAM)

    def test_authentication_and_connect_only_before_dns(self):
        with proxy.YoutubeEgressProxy() as running:
            for request in [
                b'CONNECT www.youtube.com:443 HTTP/1.1\r\n\r\n',
                b'GET https://www.youtube.com/ HTTP/1.1\r\n\r\n',
                b'CONNECT www.youtube.com:80 HTTP/1.1\r\n\r\n',
            ]:
                with mock.patch.object(proxy, 'public_ipv4') as resolver:
                    with socket.socket() as client:
                        client.settimeout(2)
                        client.connect(running.server.server_address)
                        client.sendall(request)
                        self.assertIn(b'403 Forbidden', client.recv(4096))
                    resolver.assert_not_called()

    def test_valid_connect_dials_the_verified_numeric_address(self):
        with proxy.YoutubeEgressProxy() as running:
            upstream = mock.Mock()
            with mock.patch.object(proxy, 'public_ipv4', return_value='93.184.216.34'), \
                    mock.patch.object(proxy.socket, 'create_connection', return_value=upstream) as connect, \
                    mock.patch.object(proxy._Handler, '_tunnel'):
                with socket.socket() as client:
                    client.settimeout(2)
                    client.connect(running.server.server_address)
                    client.sendall(('CONNECT www.youtube.com:443 HTTP/1.1\r\n'
                                    'Proxy-Authorization: ' + running.server.authorization +
                                    '\r\n\r\n').encode())
                    self.assertIn(b'200 Connection established', client.recv(4096))
                connect.assert_called_once_with(('93.184.216.34', 443), timeout=10)

    def test_job_budget_is_shared_across_connections(self):
        with proxy.YoutubeEgressProxy(max_bytes=10) as running:
            self.assertTrue(running.server.charge(6))
            self.assertFalse(running.server.charge(5))
            self.assertFalse(running.server.charge(1))

    def test_exit_closes_pending_headers_and_listener(self):
        entered = threading.Event()
        original = proxy._Handler.handle

        def handle(handler):
            entered.set()
            original(handler)

        with mock.patch.object(proxy._Handler, 'handle', handle):
            with proxy.YoutubeEgressProxy() as running:
                client = socket.socket()
                client.settimeout(2)
                client.connect(running.server.server_address)
                self.assertTrue(entered.wait(2))
            try:
                self.assertEqual(client.recv(1), b'')
            finally:
                client.close()


if __name__ == '__main__':
    unittest.main()
