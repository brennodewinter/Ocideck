#!/usr/bin/env bash
# Publiceer geverifieerde kanaalbytes; alleen expliciet mag het eerste kanaal tag en release aanmaken.
set -euo pipefail
RELEASE_CHANNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RELEASE_CHANNEL_ROOT
exec python3 - "$@" <<'PY'
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys, tempfile, stat
from pathlib import Path
from urllib.parse import quote, urlsplit


def bounded_read(path, limit=1048576):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('evidence is not regular')
        content = stream.read(limit + 1)
        if len(content) > limit:
            raise ValueError('evidence exceeds size bound')
        return content


def private_directory(path):
    path = path.absolute()
    for parent in [*reversed(path.parents), path]:
        if parent.is_symlink():
            raise ValueError('staging path contains symlink')
    path.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('staging directory must be private and owned by current user')
    return path


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def stage_file(source, destination, file_hash):
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.sealing-', delete=False) as output:
        pending = Path(output.name)
        try:
            fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, 'rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    raise ValueError('upload is not regular')
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        except BaseException:
            pending.unlink()
            raise
    try:
        try:
            os.link(pending, destination)
        except FileExistsError:
            if file_hash(pending) != file_hash(destination):
                raise ValueError('sealed candidate bytes differ')
        sync_directory(destination.parent)
    finally:
        pending.unlink()


def main():
    parser = argparse.ArgumentParser()
    for name in ('release-id', 'run-id', 'tag', 'sha', 'controller-sha', 'channel', 'dist', 'evidence', 'receipt', 'staging-dir'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--create-release', action='store_true')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if not args.verify_only and (args.release_id == 'auto') != args.create_release:
        raise ValueError('--create-release requires --release-id auto')
    for value in ([args.run_id] if args.release_id == 'auto' else [args.release_id, args.run_id]):
        if not re.fullmatch(r'[1-9][0-9]*', value):
            raise ValueError('invalid release/run ID')
    root = Path(os.environ['RELEASE_CHANNEL_ROOT'])
    spec = importlib.util.spec_from_file_location('release_channel', root / 'tool/release_channel.py')
    channel = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(channel)
    channel.identity(args.tag, args.sha, args.channel)
    if not re.fullmatch(r'[0-9a-f]{40}', args.controller_sha) or args.controller_sha == '0' * 40:
        raise ValueError('invalid controller SHA')
    git_env = dict(os.environ, GIT_TERMINAL_PROMPT='0',
                   GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=yes -o BatchMode=yes')

    def git(*arguments, allow_absent=False):
        try:
            result = subprocess.run(['git', '-C', str(root), *arguments], env=git_env,
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=240)
        except subprocess.TimeoutExpired:
            raise ValueError('bounded Git remote operation timed out') from None
        if allow_absent and result.returncode == 2 and not result.stdout.strip():
            return None
        if result.returncode:
            raise ValueError('bounded Git remote operation failed')
        return result.stdout.decode().strip()

    for remote in ('origin', 'mirror'):
        url = git('remote', 'get-url', remote)
        parsed_remote = urlsplit(url)
        if parsed_remote.scheme in ('http', 'https'):
            if parsed_remote.scheme != 'https' or parsed_remote.username or parsed_remote.password:
                raise ValueError('credential-free HTTPS remote required')
        elif parsed_remote.scheme == 'ssh':
            if parsed_remote.password or parsed_remote.username not in (None, 'git'):
                raise ValueError('credential-free SSH remote required')
        elif not re.fullmatch(r'git@[^\s:]+:[^\s]+', url):
            raise ValueError('unsupported or credential-bearing remote URL')

    def remote_tag(remote):
        ref = 'refs/tags/' + args.tag
        response = git('ls-remote', '--exit-code', remote, ref, ref + '^{}', allow_absent=True)
        if response is None:
            return None
        entries = {}
        for line in response.splitlines():
            sha, name = line.split()
            if name not in (ref, ref + '^{}') or name in entries or not re.fullmatch(r'[0-9a-f]{40}', sha):
                raise ValueError('invalid remote tag readback')
            entries[name] = sha
        if ref not in entries:
            raise ValueError('remote tag readback incomplete')
        return entries.get(ref + '^{}', entries[ref])

    original_tag = remote_tag('origin')
    mirror_tag = remote_tag('mirror')
    for present in (original_tag, mirror_tag):
        if present is not None and present != args.sha:
            raise ValueError('remote tag differs; never replace existing tag')
    if args.verify_only and (original_tag != args.sha or mirror_tag != args.sha):
        raise ValueError('public source tag is not present on both remotes')
    dist, evidence = Path(args.dist), Path(args.evidence)
    manifest = evidence / ('channel-manifest-' + args.channel + '.json')
    sums = evidence / ('SHA256SUMS.' + args.channel)
    args.manifest, args.dist = manifest, dist
    bounded_read(manifest)
    verified = channel.verify(args)
    if verified['run_id'] != args.run_id:
        raise ValueError('manifest run mismatch')
    expected_sums = ''.join(f'{digest}  {name}\n' for name, digest in sorted(verified['files'].items())).encode()
    if sums.is_symlink() or bounded_read(sums) != expected_sums:
        raise ValueError('checksum list differs from signed manifest')
    proof = [manifest, sums]
    for file in proof:
        signature = Path(str(file) + '.minisig')
        if signature.is_symlink() or not signature.is_file():
            raise ValueError('missing regular signature')
        result = subprocess.run(['minisign', '-Vm', str(file), '-x', str(signature), '-p', str(root / 'minisign.pub')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            raise ValueError('invalid evidence signature')
    token = os.environ.get('FORGEJO_TOKEN')
    if not token:
        result = subprocess.run(['security', 'find-generic-password', '-s', 'forgejo-pawprint-api', '-w'], capture_output=True, text=True)
        if result.returncode:
            raise ValueError('token unavailable')
        token = result.stdout.strip()
    if not token or any(c in token for c in '\r\n"\\'):
        raise ValueError('invalid token')
    base = os.environ.get('FORGEJO_API_URL', 'https://pawprint.vigilis.online/api/v1/repos/LibreKAT/Ocideck').rstrip('/')
    parsed = urlsplit(base)
    if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('invalid HTTPS API URL')
    config = f'header = "Authorization: token {token}"\n'

    def request(path, upload=None, output=None, payload=None, missing=False, method=None, expected=None):
        command = ['curl', '--config', '-', '--silent', '--show-error', '--max-time', '240', '--proto', '=https']
        if upload is not None:
            if any(c in str(upload) for c in '\r\n"\\'):
                raise ValueError('unsupported upload path')
            command += ['--request', 'POST', '--form', 'attachment=@"' + str(upload) + '"']
        if method is not None and payload is None:
            command += ['--request', method]
        if payload is not None:
            command += ['--request', method or 'POST', '--header', 'Content-Type: application/json', '--data-binary', json.dumps(payload)]
        url = path if path.startswith('https://') else base + path
        target = urlsplit(url)
        if target.scheme != parsed.scheme or target.netloc != parsed.netloc or target.username or target.password or target.fragment:
            raise ValueError('asset download escaped repository host')
        with tempfile.NamedTemporaryFile() as response:
            destination = output if output is not None else Path(response.name)
            command += ['--output', str(destination)]
            if output is None:
                command += ['--max-filesize', '2097152']
            command += ['--write-out', '%{http_code}', url]
            result = subprocess.run(command, input=config.encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if missing and result.returncode == 0 and result.stdout == b'404':
                return None
            if result.returncode or (result.stdout != expected.encode() if expected else not re.fullmatch(rb'2[0-9][0-9]', result.stdout)):
                raise ValueError('Forgejo request failed; reconcile release before retry')
            return bounded_read(destination, 2097152) if output is None else None

    def data(path, missing=False):
        body = request(path, missing=missing)
        return None if body is None else json.loads(body, object_pairs_hook=channel.no_duplicates)

    # A successful build is not proof that this source passed its quality gates.
    quality_runs = {}
    workflows = ('static-gate.yml', 'scans.yml') if args.channel == 'windows' else ('static-gate.yml', 'scans.yml', 'macos-gate.yml' if args.channel == 'macos' else 'linux-gate.yml')
    for workflow in workflows:
        latest = None
        seen = set()
        for page in range(1, 21):
            response = data('/actions/runs?limit=100&page=' + str(page)
                            + '&head_sha=' + args.sha + '&workflow_id=' + workflow)
            values = response.get('workflow_runs') if isinstance(response, dict) else None
            if not isinstance(values, list) or len(values) > 100:
                raise ValueError('invalid source quality response')
            for value in values:
                if (not isinstance(value, dict) or type(value.get('id')) is not int or value['id'] <= 0
                        or value['id'] in seen or value.get('commit_sha') != args.sha
                        or value.get('workflow_id') not in (workflow, '.forgejo/workflows/' + workflow)):
                    raise ValueError('source quality run identity differs')
                seen.add(value['id'])
                if latest is None or value['id'] > latest['id']:
                    latest = value
            if len(values) < 100:
                break
        else:
            raise ValueError('source quality history exceeds inspection bound')
        if latest is None or latest.get('status') != 'success':
            raise ValueError('latest exact-source quality gate is not successful: ' + workflow)
        quality_jobs = data('/actions/runs/' + str(latest['id']) + '/jobs')
        if (not isinstance(quality_jobs, list) or not quality_jobs
                or any(not isinstance(job, dict) or job.get('status') != 'success' for job in quality_jobs)):
            raise ValueError('source quality jobs are not all successful: ' + workflow)
        quality_runs[workflow] = latest['id']
    print('Verified exact-source quality runs: ' + json.dumps(quality_runs, sort_keys=True), file=sys.stderr)

    run = data('/actions/runs/' + args.run_id)
    if str(run.get('id')) != args.run_id or run.get('commit_sha') != args.controller_sha or run.get('status') != 'success':
        raise ValueError('candidate run is not successful on exact source')
    if run.get('workflow_id') not in ('release-channel.yml', '.forgejo/workflows/release-channel.yml'):
        raise ValueError('unexpected candidate workflow')
    if run.get('prettyref') not in ('main', 'refs/heads/main'):
        raise ValueError('candidate controller did not run on main')
    jobs = data('/actions/runs/' + args.run_id + '/jobs')
    if not isinstance(jobs, list) or not jobs or any(j.get('status') not in ('success', 'skipped') for j in jobs):
        raise ValueError('candidate jobs are not terminal green')
    if not all(any(j.get('name') == name and j.get('status') == 'success' for j in jobs) for name in (('build-macos' if args.channel == 'macos' else 'build'), 'evidence')):
        raise ValueError('build/evidence job proof missing')
    consumer_names = {
        'linux-deb': '.deb proef op een schone Ubuntu',
        'linux-rpm': '.rpm proef op een schone Fedora',
        'linux-appimage': 'AppImage proef op een schone Ubuntu',
        'linux-flatpak': 'Flatpak installatie en inhoud op een schone Ubuntu',
        'linux-tar': 'Linux-tar-archief proef op een schone Linux-tar',
    }
    if args.channel == 'windows':
        sys.path.insert(0, str(root / 'tool'))
        from release_windows_candidate import GitHub, verify as verify_windows
        windows_runs = verify_windows(GitHub(), root, dist, args.tag, args.sha,
            'codex/release-candidate-' + args.tag + '-' + args.sha)
        print('Verified exact-source Windows runs: ' + json.dumps(windows_runs, sort_keys=True), file=sys.stderr)
    elif args.channel == 'macos':
        if not any(j.get('name') == 'build-macos' and j.get('status') == 'success' for j in jobs):
            raise ValueError('macOS signed archive consumer proof missing')
    elif args.channel != 'web':
        selected = consumer_names.get(args.channel)
        if not selected or not any(j.get('name') == selected and j.get('status') == 'success' for j in jobs):
            raise ValueError('selected consumer proof missing')
    files = [dist / name for name in verified['files']]
    files += proof + [Path(str(file) + '.minisig') for file in proof]

    def listing():
        result = {}
        for page in range(1, 1001):
            values = data(release_path + '/assets?limit=50&page=' + str(page))
            if not isinstance(values, list):
                raise ValueError('invalid assets response')
            for value in values:
                name = value.get('name')
                if not isinstance(name, str) or name in result:
                    raise ValueError('invalid or duplicate release asset')
                result[name] = value
            if len(values) < 50:
                return result
        raise ValueError('asset pagination exceeded bound')

    def readback(asset, output):
        asset_id = str(asset.get('id', ''))
        if not re.fullmatch(r'[1-9][0-9]*', asset_id):
            raise ValueError('invalid asset ID')
        url = asset.get('browser_download_url', '')
        if not isinstance(url, str) or not url.startswith('https://'):
            raise ValueError('missing HTTPS asset download URL')
        return request(url, output=output)

    lock_name = 'codex/release-publish-lock-' + args.tag
    lock_path = '/branches/' + quote(lock_name, safe='')
    lease_owned = False

    def acquire_lease():
        nonlocal lease_owned
        if lease_owned:
            return
        # Alleen het ontvangen create-antwoord geeft eigendom; timeout is handmatig herstel.
        response = request('/branches', payload={'new_branch_name': lock_name,
                           'old_ref_name': args.controller_sha}, expected='201')
        branch = json.loads(response, object_pairs_hook=channel.no_duplicates)
        if branch.get('name') != lock_name or branch.get('commit', {}).get('id') != args.controller_sha:
            raise ValueError('publish lease ownership not proven; inspect remote lock')
        lease_owned = True

    with tempfile.TemporaryDirectory(prefix='ocideck-publish-') as temp:
        stage = private_directory(Path(temp).resolve() / 'verification' if args.verify_only else Path(args.staging_dir))
        staged_dist = private_directory(stage / 'dist')
        staged_evidence = private_directory(stage / 'evidence')
        sync_directory(stage.parent)
        snapshots = []
        for file in files:
            snapshot = (staged_dist if file.parent == dist else staged_evidence) / file.name
            stage_file(file, snapshot, channel.file_hash)
            snapshots.append(snapshot)
        sync_directory(stage)
        args.dist = staged_dist
        args.manifest = staged_evidence / manifest.name
        if channel.verify(args) != verified:
            raise ValueError('sealed manifest differs')
        for snapshot in snapshots:
            if snapshot.name in verified['files'] and channel.file_hash(snapshot) != verified['files'][snapshot.name]:
                raise ValueError('asset changed before publication')
        if json.loads(bounded_read(staged_evidence / manifest.name), object_pairs_hook=channel.no_duplicates) != verified or bounded_read(staged_evidence / sums.name) != expected_sums:
            raise ValueError('evidence changed before publication')
        for file in (staged_evidence / manifest.name, staged_evidence / sums.name):
            if subprocess.run(['minisign', '-Vm', str(file), '-x', str(file) + '.minisig', '-p', str(root / 'minisign.pub')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise ValueError('snapshot signature mismatch')
        if args.verify_only:
            tag = data('/tags/' + quote(args.tag, safe=''))
            if tag.get('commit', {}).get('sha') != args.sha:
                raise ValueError('public tag source mismatch')
            if args.release_id == 'auto':
                args.release_id = str(data('/releases/tags/' + quote(args.tag, safe='')).get('id', ''))
                if not re.fullmatch(r'[1-9][0-9]*', args.release_id):
                    raise ValueError('invalid public release ID')
            release_path = '/releases/' + args.release_id
            release = data(release_path)
            if release.get('draft') is not False or release.get('tag_name') != args.tag or str(release.get('id')) != args.release_id:
                raise ValueError('release is not public on expected tag')
            current = listing()
            for file in snapshots:
                if file.name not in current:
                    raise ValueError('public asset missing')
                readback(current[file.name], Path(temp) / 'status-download')
                if channel.file_hash(Path(temp) / 'status-download') != channel.file_hash(file):
                    raise ValueError('public asset readback differs')
            print(json.dumps({'status': 'verified', 'release_id': args.release_id,
                              'source': args.sha, 'controller_sha': args.controller_sha,
                              'run_id': args.run_id, 'channel': args.channel, 'mirror_source': args.sha}, sort_keys=True))
            return
        tag_path = '/tags/' + quote(args.tag, safe='')
        tag = data(tag_path, missing=args.create_release)
        if tag is None:
            frozen = 'codex/release-candidate-' + args.tag + '-' + args.sha
            branch = data('/branches/' + quote(frozen, safe=''))
            if branch.get('commit', {}).get('id') != args.sha:
                raise ValueError('frozen branch differs from signed source')
            workflow = bounded_read(root / '.forgejo/workflows/release.yml')
            if b'  push:' in workflow or b'workflow_dispatch:' not in workflow:
                raise ValueError('trusted legacy workflow still permits automatic tag publication')
            blob = hashlib.sha1(b'blob ' + str(len(workflow)).encode() + b'\0' + workflow).hexdigest()
            content_path = '/contents/.forgejo/workflows/release.yml?ref='
            source_workflow = data(content_path + args.sha)
            controller_workflow = data(content_path + args.controller_sha)
            if source_workflow.get('sha') != blob or controller_workflow.get('sha') != blob:
                raise ValueError('source/controller legacy publication workflow differs')
            acquire_lease()
            try:
                request('/tags', payload={'tag_name': args.tag, 'target': args.sha,
                                         'message': 'OciDeck ' + args.tag + '; immutable tested source ' + args.sha + '\nRelease-Mode: channels'})
            except ValueError:
                pass
            tag = data(tag_path)
        if tag.get('commit', {}).get('sha') != args.sha:
            raise ValueError('public tag source mismatch')
        if args.create_release:
            release = data('/releases/tags/' + quote(args.tag, safe=''), missing=True)
            if release is None:
                acquire_lease()
                try:
                    request('/releases', payload={'tag_name': args.tag, 'name': 'OciDeck ' + args.tag,
                            'draft': True, 'prerelease': False,
                            'body': 'Independent channel candidate: ' + args.channel + '. Publication is pending until its signed files have been verified.'})
                except ValueError:
                    pass
                release = data('/releases/tags/' + quote(args.tag, safe=''))
            args.release_id = str(release.get('id', ''))
            if not re.fullmatch(r'[1-9][0-9]*', args.release_id):
                raise ValueError('invalid created release ID')
        release_path = '/releases/' + args.release_id
        release = data(release_path)
        if release.get('draft') is not False and not (args.create_release and release.get('draft') is True):
            raise ValueError('existing release is not public')
        if str(release.get('id')) != args.release_id or release.get('tag_name') != args.tag:
            raise ValueError('release identity mismatch')
        if data(tag_path).get('commit', {}).get('sha') != args.sha:
            raise ValueError('tag source changed before publication')
        acquire_lease()
        for file in snapshots:
            if file.is_symlink() or not file.is_file():
                raise ValueError('upload is not regular')
            local_hash = channel.file_hash(file)
            current = listing()
            if file.name not in current:
                try:
                    request(release_path + '/assets?name=' + quote(file.name, safe=''), file)
                except ValueError:
                    # A timed-out POST may already have committed. Never POST twice.
                    pass
                current = listing()
            download = Path(temp) / 'download'
            if file.name in current:
                readback(current[file.name], download)
            if file.name not in current or channel.file_hash(download) != local_hash:
                raise ValueError('missing or conflicting immutable asset: ' + file.name)
        if remote_tag('origin') != args.sha:
            raise ValueError('origin tag does not match published source')
        if remote_tag('mirror') is None:
            git('fetch', '--no-tags', 'origin', 'refs/tags/' + args.tag)
            if git('rev-parse', 'FETCH_HEAD^{}') != args.sha:
                raise ValueError('fetched annotated tag differs from source')
            try:
                git('push', 'mirror', 'FETCH_HEAD:refs/tags/' + args.tag)
            except ValueError:
                # Push may have committed before its response was lost; read only.
                pass
        if remote_tag('mirror') != args.sha:
            raise ValueError('mirror tag readback failed; existing tags are never moved')
        if release.get('draft') is True:
            request(release_path, payload={'draft': False}, method='PATCH')
        public = data(release_path)
        if public.get('draft') is not False or public.get('tag_name') != args.tag or str(public.get('id')) != args.release_id:
            raise ValueError('public release readback failed')
        if data(tag_path).get('commit', {}).get('sha') != args.sha:
            raise ValueError('public tag changed')
        current = listing()
        for file in snapshots:
            if file.name not in current:
                raise ValueError('public asset missing')
            readback(current[file.name], Path(temp) / 'public-download')
            if channel.file_hash(Path(temp) / 'public-download') != channel.file_hash(file):
                raise ValueError('public asset readback differs')
        receipt = {'schema': 1, 'release_id': args.release_id, 'run_id': args.run_id,
                   'tag': args.tag, 'source': args.sha, 'controller_sha': args.controller_sha,
                   'channel': args.channel, 'mirror_source': args.sha, 'files': {file.name: channel.file_hash(file) for file in snapshots}}
        content = channel.encoded(receipt)
        target = Path(args.receipt)
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.receipt-', delete=False) as output:
            pending = Path(output.name)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        try:
            try:
                os.link(pending, target)
            except FileExistsError:
                fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                with os.fdopen(fd, 'rb') as existing:
                    if not stat.S_ISREG(os.fstat(existing.fileno()).st_mode):
                        raise ValueError('receipt is not regular')
                    if existing.read(65537) != content:
                        raise ValueError('existing receipt differs')
            directory = os.open(target.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            pending.unlink()
        if data(lock_path).get('commit', {}).get('id') != args.controller_sha:
            raise ValueError('remote publish lease changed; inspect before unlocking')
        request(lock_path, method='DELETE', expected='204')
        print(json.dumps(receipt, sort_keys=True))

try:
    main()
except (ValueError, OSError, TypeError, KeyError, subprocess.TimeoutExpired) as error:
    print('Channel publication stopped: ' + (str(error) if isinstance(error, ValueError) else 'local verification or transport failure'), file=sys.stderr)
    sys.exit(1)
PY
