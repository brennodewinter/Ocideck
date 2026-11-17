import http.client
import importlib.util
import json
import pathlib
import socket
import sys
import threading
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2] / 'testbed/youtube-source'
for name in ['egress_proxy', 'register_decoder', 'source_runtime', 'source_server']:
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
source_server = sys.modules['source_server']


class ContractBackend:
    decoder = None

    def __init__(self):
        self.calls = []
        self.block = False
        self.started = threading.Event()
        self.cancelled = threading.Event()

    def execute(self, action, fields, cancelled):
        self.calls.append((action, fields))
        self.started.set()
        while self.block:
            if cancelled():
                self.cancelled.set()
                raise source_server.SourceFailure('cancelled')
            self.cancelled.wait(.01)
        return {'status': 'completed', 'title': 'Contract fixture',
                'duration_ms': 1000, 'audio': False, 'tracks': []}


class HttpContractTests(unittest.TestCase):
    def setUp(self):
        self.backend = ContractBackend()
        self.server = source_server.create_server(self.backend, port=0,
            origin='https://app.example', token='test-only-token')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.stop()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, action='metadata', *, body=None, headers=None, method='POST'):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        try:
            connection.request(method, source_server.PREFIX + action,
                body if body is not None else json.dumps({'video_id': 'M7lc1UVf-VE'}),
                headers if headers is not None else {
                    'Content-Type': 'application/json', 'Authorization': 'Bearer test-only-token'})
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_origin_and_token_checks_precede_provider_work(self):
        for headers in [{'Content-Type': 'application/json'},
                        {'Content-Type': 'application/json', 'Authorization': 'Bearer test-only-token',
                         'Origin': 'https://other.example'}]:
            status, _ = self.request(headers=headers)
            self.assertEqual(status, 401)
        self.assertEqual(self.backend.calls, [])
        status, result = self.request('capabilities', method='GET')
        self.assertEqual(status, 200)
        self.assertEqual(result['protocol'], 'ocideck-youtube')
        self.assertFalse(result['audio'])
        self.assertFalse(result['audio_fragments'])
        self.assertEqual(self.backend.calls, [])

    def test_json_shape_and_type_are_rejected_before_processing(self):
        for body, kind in [('[]', 'application/json'), ('{', 'application/json'),
                           ('x' * 4097, 'application/json'), ('{}', 'text/plain')]:
            status, _ = self.request(body=body, headers={
                'Authorization': 'Bearer test-only-token', 'Content-Type': kind})
            self.assertEqual(status, 422)
        self.assertEqual(self.backend.calls, [])

    def test_one_requested_video_is_echoed_and_no_url_is_forwarded(self):
        status, result = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(result['video_id'], 'M7lc1UVf-VE')
        self.assertEqual(self.backend.calls, [('metadata', {'video_id': 'M7lc1UVf-VE'})])

    def _disconnect_job(self):
        self.backend.block = True
        peer = socket.create_connection(('127.0.0.1', self.server.server_port), timeout=2)
        body = b'{"video_id":"M7lc1UVf-VE"}'
        peer.sendall((f'POST {source_server.PREFIX}metadata HTTP/1.1\r\n'
                      'Host: 127.0.0.1\r\nAuthorization: Bearer test-only-token\r\n'
                      'Content-Type: application/json\r\n'
                      f'Content-Length: {len(body)}\r\n\r\n').encode() + body)
        self.assertTrue(self.backend.started.wait(2))
        return peer

    def test_real_http_disconnect_cancels_processing_and_releases_capacity(self):
        peer = self._disconnect_job()
        peer.close()
        self.assertTrue(self.backend.cancelled.wait(2))
        deadline = time.monotonic() + 2
        while not self.server.busy.acquire(blocking=False):
            self.assertLess(time.monotonic(), deadline)
            threading.Event().wait(.01)
        self.server.busy.release()

    def test_operator_stop_cancels_and_drains_active_handlers(self):
        peer = self._disconnect_job()
        try:
            self.server.stop()
            self.server.server_close()
            self.assertTrue(self.backend.cancelled.is_set())
            self.assertFalse(self.server.connections)
        finally:
            peer.close()


if __name__ == '__main__':
    unittest.main()
