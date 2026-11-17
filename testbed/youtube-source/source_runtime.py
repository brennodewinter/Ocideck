"""Bounded adapter to explicitly installed, pinned yt-dlp/Node components.

Not bundled in OciDeck and never installed by an application request. No
cookies, user configuration, playlist expansion, external downloaders,
remote JS component installation, arbitrary URL or shell execution.
"""
import importlib.metadata
import hashlib
import json
import os
import pathlib
import platform
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time

from egress_proxy import YoutubeEgressProxy
from register_decoder import verify_registration


MAX_AUDIO = 8 * 1024 * 1024
MAX_CAPTIONS = 2 * 1024 * 1024
MAX_DECODED = 64 * 1024 * 1024
PINNED_PACKAGES = {'yt-dlp': '2026.10.26', 'yt-dlp-ejs': '0.8.0'}
NODE_VERSION = 'v22.23.5'


class SourceFailure(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


class YoutubeRuntime:
    def __init__(self, node, decoder_registration=None):
        self.node = pathlib.Path(node).resolve(strict=True)
        # Only this concrete operator runtime has been built and live-probed.
        if (sys.platform != 'darwin' or platform.machine() != 'arm64' or
                not hasattr(os, 'waitid') or not hasattr(os, 'WNOWAIT')):
            raise SourceFailure('missingHelper')
        manifest = json.loads(pathlib.Path(__file__).with_name('runtime_manifest.json').read_text())
        for path, key in [(self.node, 'node'), (self.node.with_name('LICENSE'), 'LICENSE')]:
            with path.open('rb') as source:
                actual = hashlib.file_digest(source, 'sha256').hexdigest()
            if actual != manifest['node']['files'][key]:
                raise SourceFailure('missingHelper')
        for name, version in PINNED_PACKAGES.items():
            if importlib.metadata.version(name) != version:
                raise SourceFailure('missingHelper')
        found = subprocess.run([str(self.node), '--version'], check=True,
                               capture_output=True, timeout=5, env=self._env())
        if found.stdout.decode().strip() != NODE_VERSION:
            raise SourceFailure('missingHelper')
        self.decoder_registration = decoder_registration
        self.decoder = verify_registration(decoder_registration) if decoder_registration else None

    @staticmethod
    def _env():
        # Drop cookies, proxy overrides, API keys and Python/Node startup hooks.
        return {'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8'}

    def execute(self, action, fields, cancelled=lambda: False):
        video_id = fields.get('video_id')
        if not isinstance(video_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
            raise SourceFailure('protocol')
        if action not in ('metadata', 'captions', 'audio'):
            raise SourceFailure('protocol')
        expected = {'video_id'} | ({'track'} if action == 'captions' else
                                  {'start_ms', 'end_ms'} if action == 'audio' else set())
        if set(fields) != expected:
            raise SourceFailure('protocol')
        if action == 'captions' and (not isinstance(fields['track'], str) or
                not re.fullmatch(r'(manual|automatic):[A-Za-z0-9_.-]{1,80}', fields['track'])):
            raise SourceFailure('protocol')
        if action == 'audio':
            if any(type(fields[k]) is not int for k in ('start_ms', 'end_ms')):
                raise SourceFailure('protocol')
            if self.decoder is None:
                raise SourceFailure('missingHelper')
            if (fields['start_ms'] < 0 or fields['end_ms'] < 0 or
                    (fields['end_ms'] != 0 and fields['end_ms'] <= fields['start_ms'])):
                raise SourceFailure('protocol')
            try:
                self.decoder = verify_registration(self.decoder_registration)
            except (ValueError, OSError, KeyError):
                raise SourceFailure('missingHelper') from None
        deadline = time.monotonic() + 120
        with tempfile.TemporaryDirectory(prefix='ocideck-youtube-') as name:
            directory = pathlib.Path(name)
            with YoutubeEgressProxy(timeout=120) as proxy:
                common = self._arguments(video_id, proxy.url)
                raw = self._run(self._with_options(common, ['--skip-download', '--dump-single-json']),
                                directory, deadline, cancelled)
                try:
                    metadata = json.loads(raw)
                except (ValueError, UnicodeError):
                    raise SourceFailure('protocol') from None
                self._validate_video(metadata, video_id)
                if action == 'metadata':
                    return self._metadata(metadata)
                if action == 'captions':
                    return self._captions(common, metadata, fields['track'],
                                          directory, deadline, cancelled)
                return self._audio(common, metadata, fields, directory, deadline, cancelled)

    def _arguments(self, video_id, proxy_url):
        # Options precede the sole canonical URL. Never forward an input URL,
        # filename, language expression or options from an HTTP request.
        return [sys.executable, '-I', '-m', 'yt_dlp', '--ignore-config',
                '--no-playlist', '--no-cache-dir', '--no-progress', '--no-warnings',
                '--no-js-runtimes', '--js-runtimes', 'node:' + str(self.node),
                '--no-remote-components', '--proxy', proxy_url,
                '--socket-timeout', '12', '--retries', '0', '--extractor-retries', '0',
                '--', 'https://www.youtube.com/watch?v=' + video_id]

    @staticmethod
    def _validate_video(metadata, video_id):
        if not isinstance(metadata, dict) or metadata.get('id') != video_id:
            raise SourceFailure('protocol')
        if metadata.get('availability') in ('private', 'premium_only', 'subscriber_only', 'needs_auth'):
            raise SourceFailure('access')
        if metadata.get('live_status') not in ('not_live', 'was_live'):
            raise SourceFailure('live')
        duration = metadata.get('duration')
        if not isinstance(duration, (int, float)) or not 0 < duration <= 48 * 3600:
            raise SourceFailure('tooLarge')

    @staticmethod
    def _tracks(metadata):
        tracks = []
        for kind, key in [('manual', 'subtitles'), ('automatic', 'automatic_captions')]:
            available = metadata.get(key, {})
            if not isinstance(available, dict):
                continue
            for language, formats in sorted(available.items()):
                if (re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', language) and
                        isinstance(formats, list) and
                        any(isinstance(f, dict) and f.get('ext') == 'vtt' for f in formats)):
                    tracks.append({'id': kind + ':' + language,
                                   'language': language, 'kind': kind})
        return tracks[:250]

    def _metadata(self, metadata):
        return {'status': 'completed', 'title': str(metadata.get('title', ''))[:1000],
                'duration_ms': round(metadata['duration'] * 1000),
                'tracks': self._tracks(metadata),
                'audio': self.decoder is not None and any(f.get('vcodec') == 'none' and
                             f.get('acodec') not in (None, 'none')
                             for f in metadata.get('formats', []) if isinstance(f, dict))}

    def _captions(self, common, metadata, track_id, directory, deadline, cancelled):
        track = next((t for t in self._tracks(metadata) if t['id'] == track_id), None)
        if track is None:
            raise SourceFailure('captionsMissing')
        automatic = track['kind'] == 'automatic'
        options = ['--skip-download', '--write-auto-subs' if automatic else '--write-subs',
                   '--no-write-subs' if automatic else '--no-write-auto-subs',
                   '--sub-langs', '^' + re.escape(track['language']) + '$',
                   '--sub-format', 'vtt', '--output', 'captions.%(ext)s']
        self._run(self._with_options(common, options), directory, deadline, cancelled,
                  file_limit=MAX_CAPTIONS)
        files = list(directory.glob('captions.*.vtt'))
        if len(files) != 1 or files[0].stat().st_size > MAX_CAPTIONS:
            raise SourceFailure('captionsMissing')
        text = files[0].read_text(encoding='utf-8-sig')
        if not text.startswith('WEBVTT'):
            # An HLS playlist is not a caption document.
            raise SourceFailure('captionsMissing')
        return {'track': track_id, 'format': 'vtt', 'text': text}

    def _audio(self, common, metadata, fields, directory, deadline, cancelled):
        import base64
        import io
        import wave
        first = fields['start_ms'] * 16
        last = min(fields['end_ms'] * 16 if fields['end_ms'] else round(metadata['duration'] * 16000),
                   round(metadata['duration'] * 16000))
        if first >= last:
            raise SourceFailure('audioMissing')
        if (last - first) * 2 + 44 > MAX_AUDIO or last * 2 + 256 > MAX_DECODED:
            raise SourceFailure('tooLarge')
        options = ['--format', 'worstaudio[ext=m4a]/worstaudio',
                   '--max-filesize', str(MAX_AUDIO), '--output', 'audio.%(ext)s']
        self._run(self._with_options(common, options), directory, deadline, cancelled,
                  file_limit=MAX_AUDIO)
        files = [f for f in directory.glob('audio.*') if f.suffix in ('.m4a', '.webm')]
        if len(files) != 1:
            raise SourceFailure('audioMissing')
        if not 0 < files[0].stat().st_size <= MAX_AUDIO:
            raise SourceFailure('tooLarge')
        decoded = directory / 'decoded.wav'
        try:
            self.decoder = verify_registration(self.decoder_registration)
        except (ValueError, OSError, KeyError):
            raise SourceFailure('missingHelper') from None
        self._run([str(self.decoder), '-nostdin', '-v', 'error',
                   '-protocol_whitelist', 'file', '-format_whitelist', 'mov,matroska,webm',
                   '-i', str(files[0]), '-vn', '-ac', '1', '-ar', '16000',
                   '-c:a', 'pcm_s16le', '-fs', str(MAX_DECODED), str(decoded)],
                  directory, deadline, cancelled, file_limit=96 * 1024 * 1024)
        if cancelled():
            raise SourceFailure('cancelled')
        with wave.open(str(decoded), 'rb') as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 16000):
                raise SourceFailure('protocol')
            last = min(last, source.getnframes())
            if first >= last:
                raise SourceFailure('audioMissing')
            source.setpos(first)
            frames = source.readframes(last - first)
        if len(frames) != (last - first) * 2:
            raise SourceFailure('protocol')
        output = io.BytesIO()
        with wave.open(output, 'wb') as target:
            target.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            target.writeframes(frames)
        data = output.getvalue()
        return {'base64': base64.b64encode(data).decode('ascii'),
                'extension': 'wav', 'source_offset_ms': fields['start_ms'],
                'duration_ms': round((last - first) / 16)}

    @staticmethod
    def _with_options(common, options):
        return common[:-2] + options + common[-2:]

    def _run(self, arguments, directory, deadline, cancelled, file_limit=MAX_AUDIO):
        process = subprocess.Popen(arguments, cwd=directory, env=self._env(),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   bufsize=0, start_new_session=True)
        buffers = {process.stdout: bytearray(), process.stderr: bytearray()}
        try:
            with selectors.DefaultSelector() as selected:
                for stream in buffers:
                    os.set_blocking(stream.fileno(), False)
                    selected.register(stream, selectors.EVENT_READ)
                while selected.get_map() or not self._exited(process):
                    if cancelled():
                        raise SourceFailure('cancelled')
                    if time.monotonic() >= deadline:
                        raise SourceFailure('network')
                    if sum(f.stat().st_size for f in directory.iterdir() if f.is_file()) > file_limit:
                        raise SourceFailure('tooLarge')
                    for key, _ in selected.select(.05):
                        chunk = os.read(key.fileobj.fileno(), 32768)
                        if not chunk:
                            selected.unregister(key.fileobj)
                            continue
                        buffer = buffers[key.fileobj]
                        maximum = 4 * 1024 * 1024 if key.fileobj is process.stdout else 65536
                        if len(chunk) > maximum - len(buffer):
                            raise SourceFailure('tooLarge')
                        buffer.extend(chunk)
            if cancelled():
                raise SourceFailure('cancelled')
        finally:
            # WNOWAIT reserves the owned leader PID until all group signals
            # have been sent, even if yt-dlp exits before a Node child does.
            # Reaping first could allow that process-group identifier to recur.
            self._signal_group(process.pid, signal.SIGTERM)
            deadline = time.monotonic() + 2
            while not self._exited(process) and time.monotonic() < deadline:
                time.sleep(.02)
            self._signal_group(process.pid, signal.SIGKILL)
            process.wait(timeout=2)
            process.stdout.close()
            process.stderr.close()
        if process.returncode != 0:
            error = buffers[process.stderr].decode('utf-8', errors='replace').lower()
            code = 'rateLimited' if '429' in error else 'access' if any(
                word in error for word in ('sign in', 'private', 'removed', 'unavailable')) else 'network'
            raise SourceFailure(code)
        return bytes(buffers[process.stdout])

    @staticmethod
    def _exited(process):
        if hasattr(os, 'waitid'):
            return os.waitid(os.P_PID, process.pid,
                             os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None
        # The repository's older macOS test interpreter lacks waitid. `ps`
        # observes the owned child's zombie state without reaping it. The
        # pinned operator interpreter uses the syscall path above.
        status = subprocess.run(['/bin/ps', '-o', 'stat=', '-p', str(process.pid)],
                                capture_output=True, timeout=2)
        return status.stdout.strip().startswith(b'Z')

    @staticmethod
    def _signal_group(pid, signum):
        try:
            os.killpg(pid, signum)
        except ProcessLookupError:
            pass
        except PermissionError:
            # Darwin can report EPERM for a group containing only zombies.
            # Accept that only after observing no live member; never hide a
            # denied signal to a running worker or descendant.
            rows = subprocess.run(['/bin/ps', '-axo', 'pgid=,stat='],
                                  capture_output=True, timeout=2).stdout.splitlines()
            for row in rows:
                fields = row.split()
                if len(fields) == 2 and fields[0] == str(pid).encode() and not fields[1].startswith(b'Z'):
                    raise
