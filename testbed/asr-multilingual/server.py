"""Explicit, offline-after-install loopback reference server for mixed language ASR."""
import argparse
import importlib.util
import os
import ssl
from pathlib import Path

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
os.environ['DO_NOT_TRACK'] = '1'
os.environ['OMP_NUM_THREADS'] = '4'

from whisper_backend import WhisperBackend

source = Path(__file__).parent.parent / 'asr-diarization/server.py'
spec = importlib.util.spec_from_file_location('ocideck_reference_http', source)
http = importlib.util.module_from_spec(spec)
spec.loader.exec_module(http)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-directory', type=Path, required=True)
    parser.add_argument('--model-name', choices=['base', 'small', 'large-v3-turbo'], required=True)
    parser.add_argument('--port', type=int, default=8093)
    parser.add_argument('--tls-cert', type=Path)
    parser.add_argument('--tls-key', type=Path)
    args = parser.parse_args()
    if bool(args.tls_cert) != bool(args.tls_key):
        parser.error('Provide both TLS certificate and key')
    try:
        backend = WhisperBackend(args.model_directory, args.model_name)
    except (OSError, ValueError):
        parser.error('Install the selected pinned model and verify its files before starting')
    server = http.ThreadingHTTPServer(('127.0.0.1', args.port), http.Handler)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    server.backend = backend
    server.token = os.environ.get('OCIDECK_ASR_TOKEN', '')
    server.origin = os.environ.get('OCIDECK_ASR_ORIGIN', '')
    server.serve_forever()
