"""HTTP contract boundaries without model downloads or real voice inference."""
import http.client
import importlib.util
import json
from pathlib import Path
import sys
import threading
import types
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'testbed/asr-diarization/server.py'


class ReferenceHttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('asr_reference', SOURCE)
        cls.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'vosk_backend': types.SimpleNamespace(VoskBackend=object)}):
            spec.loader.exec_module(cls.module)
        cls.server = cls.module.ThreadingHTTPServer(('127.0.0.1', 0), cls.module.Handler)
        cls.server.origin = ''
        cls.server.token = ''
        cls.calls = []
        cls.server.backend = types.SimpleNamespace(
            capabilities=lambda: {'protocol': 'ocideck-asr', 'version': 1},
            transcribe=lambda audio, language, diarize, **extra: cls.calls.append(
                (audio, language, diarize)) or {'protocol': 'ocideck-asr', 'version': 1})
        cls.default_backend = cls.server.backend
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def setUp(self):
        self.server.origin = ''
        self.server.token = ''
        self.calls.clear()
        self.server.backend = self.default_backend
        self.assertTrue(self.module.BUSY.acquire(timeout=2))
        self.module.BUSY.release()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    @staticmethod
    def multipart(extra=(), language='nl'):
        fields = [('diarize', b'false'), ('file', b'pcm')]
        if language is not None:
            fields.insert(0, ('language', language.encode()))
        fields.extend(extra)
        body = b''
        for key, value in fields:
            body += (b'--proof\r\nContent-Disposition: form-data; name="' + key.encode() +
                     b'"\r\n\r\n' + value + b'\r\n')
        return body + b'--proof--\r\n'

    def test_language_switching_requires_capability(self):
        status, _, _ = self.request('POST', '/ocideck-asr/v1/transcribe',
            self.multipart([('language_mode', b'mixed')], language=None),
            {'Content-Type': 'multipart/form-data; boundary=proof'})
        self.assertEqual(status, 422)
        self.assertEqual(self.calls, [])

    def test_language_mode_is_forwarded_only_when_advertised(self):
        seen = []
        self.server.backend = types.SimpleNamespace(
            capabilities=lambda: {'features': {'language_switching': True}},
            transcribe=lambda audio, language, diarize, **extra:
                seen.append((language, diarize, extra)) or {'version': 1})
        status, _, _ = self.request('POST', '/ocideck-asr/v1/transcribe',
            self.multipart([('language_mode', b'mixed')], language=None),
            {'Content-Type': 'multipart/form-data; boundary=proof'})
        self.assertEqual(status, 200)
        self.assertEqual(seen[0][:2], ('', False))
        self.assertIs(seen[0][2]['language_switching'], True)
        self.assertTrue(callable(seen[0][2]['cancelled']))

    def test_disconnect_reaches_worker_and_releases_capacity(self):
        started = threading.Event()
        stopped = threading.Event()
        def process(audio, language, diarize, **extra):
            started.set()
            while not extra['cancelled']():
                if stopped.wait(0.01):
                    raise AssertionError('test ended before cancellation')
            stopped.set()
            raise ConnectionAbortedError('cancelled')
        self.server.backend = types.SimpleNamespace(transcribe=process)
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        try:
            connection.request('POST', '/ocideck-asr/v1/transcribe',
                self.multipart(), {'Content-Type': 'multipart/form-data; boundary=proof'})
            self.assertTrue(started.wait(2))
            connection.close()
            self.assertTrue(stopped.wait(2))
            self.assertTrue(self.module.BUSY.acquire(timeout=2))
            self.module.BUSY.release()
        finally:
            connection.close()
            stopped.set()

    def test_capability_has_no_audio_and_does_not_process(self):
        status, _, body = self.request('GET', '/ocideck-asr/v1/capabilities')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['version'], 1)
        self.assertEqual(self.calls, [])

    def test_unknown_origins_are_refused_before_processing(self):
        status, _, _ = self.request('POST', '/ocideck-asr/v1/transcribe',
                                    headers={'Origin': 'https://untrusted.invalid'})
        self.assertEqual(status, 401)
        self.assertEqual(self.calls, [])

    def test_exact_origin_gets_cors_without_wildcard(self):
        self.server.origin = 'https://slides.example.invalid'
        status, headers, _ = self.request('GET', '/ocideck-asr/v1/capabilities',
                                          headers={'Origin': self.server.origin})
        self.assertEqual(status, 200)
        self.assertEqual(headers['Access-Control-Allow-Origin'], self.server.origin)

    def test_enabled_auth_is_required(self):
        self.server.token = 'unit-test-value'
        status, _, _ = self.request('GET', '/ocideck-asr/v1/capabilities')
        self.assertEqual(status, 401)
        status, _, _ = self.request('GET', '/ocideck-asr/v1/capabilities',
                                    headers={'Authorization': 'Bearer unit-test-value'})
        self.assertEqual(status, 200)

    def test_malformed_and_oversized_requests_do_not_process(self):
        for headers in [{'Content-Length': str(self.module.MAX_BODY + 1)},
                        {'Content-Type': 'application/json'}]:
            with self.subTest(headers=headers):
                status, _, _ = self.request('POST', '/ocideck-asr/v1/transcribe', headers=headers)
                self.assertEqual(status, 422)
        self.assertEqual(self.calls, [])

    def test_multipart_reaches_backend_once_with_exact_options(self):
        body = b''
        for key, value in [('language', b'nl'), ('diarize', b'true'), ('file', b'pcm')]:
            body += (b'--proof\r\nContent-Disposition: form-data; name="' + key.encode() +
                     b'"\r\n\r\n' + value + b'\r\n')
        body += b'--proof--\r\n'
        status, _, _ = self.request('POST', '/ocideck-asr/v1/transcribe', body,
                                    {'Content-Type': 'multipart/form-data; boundary=proof'})
        self.assertEqual(status, 200)
        self.assertEqual(self.calls, [(b'pcm', 'nl', True)])


if __name__ == '__main__':
    unittest.main()
