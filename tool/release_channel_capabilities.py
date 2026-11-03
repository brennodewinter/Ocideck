"""Read-only prerequisites and measured progress for a selected release channel."""
from datetime import datetime
from pathlib import Path
import re
import shutil
from urllib.parse import quote


def inspect(api, wanted, phase='build'):
    """Check metadata only; credentials themselves never leave their owning service."""
    label = 'ocideck-macos-arm64' if wanted['channel'] == 'macos' else 'docker'
    if phase not in ('build', 'assets', 'website'):
        raise ValueError('unknown capability phase')
    needed = {'GH_DISPATCH_TOKEN'} if phase == 'build' and wanted['channel'] == 'windows' else set()
    if phase == 'website':
        needed = {'WEBSITE_REPO_KEY_V1', 'WEBSITE_REPO_KNOWN_HOSTS_V1'}
        label = 'docker'
    blockers = []
    try:
        repository = api.get('')
        if not isinstance(repository, dict) or repository.get('permissions', {}).get('push') is not True:
            blockers.append('repository write permission not proven')
        if phase != 'assets':
            runners = api.get('/actions/runners?visible=true&limit=100&page=1')
            if not isinstance(runners, list) or len(runners) >= 100:
                raise ValueError('runner inventory incomplete')
            available = [runner for runner in runners if isinstance(runner, dict)
                         and runner.get('status') in ('idle', 'active')
                         and label in [value.split(':', 1)[0] for value in runner.get('labels', [])]]
            if not available:
                blockers.append('no online runner with label ' + label)
        if needed:
            secrets = api.get('/actions/secrets?page=1&limit=100')
            if not isinstance(secrets, list) or len(secrets) >= 100:
                raise ValueError('secret inventory incomplete')
            names = {secret.get('name') for secret in secrets if isinstance(secret, dict)}
            blockers.extend('missing repository secret ' + name for name in sorted(needed - names))
        frozen = api.get('/git/refs/heads/' + quote(wanted['frozen_ref'], safe=''))
        if not isinstance(frozen, dict) or frozen.get('object', {}).get('sha') != wanted['source']:
            blockers.append('frozen source ref differs')
    except (ValueError, OSError, TypeError, KeyError) as error:
        blockers.append('capability metadata unavailable: ' + str(error))
    return {'phase': phase, 'runner_label': label, 'ready': not blockers,
            'blockers': blockers, 'required_secret_names': sorted(needed),
            'runtime_checks': 'image pull, signing and external service credentials remain worker checks'}


def require_space(path, size):
    """Reserve room for one complete copy plus filesystem metadata before writing."""
    path = Path(path).absolute()
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError('storage path contains symlink')
    existing = path
    while not existing.exists():
        existing = existing.parent
    required = size + 16 * 1024 * 1024
    if shutil.disk_usage(existing).free < required:
        raise ValueError('insufficient staging space: need ' + str(required) + ' bytes')


def elapsed(start, end):
    try:
        left, right = (datetime.fromisoformat(value.replace('Z', '+00:00')) for value in (start, end))
        seconds = (right - left).total_seconds()
        return seconds if left.tzinfo and right.tzinfo and seconds >= 0 else None
    except (ValueError, TypeError, AttributeError):
        return None


def timing(run):
    return {'queue_seconds': elapsed(run.get('created'), run.get('started')),
            'execution_seconds': elapsed(run.get('started'), run.get('stopped')),
            'last_progress_at': run.get('updated'),
            'comparison': 'same source/controller/channel and cache regime only; incidents and manual waits are separate'}


ERROR = re.compile(r'::error::|##\[error\]|❌|\[E\]|Unhandled exception|^.*FAILED(?:\s|$)')


def first_failure(content):
    """Scan the whole bounded log, retaining its supplied timestamp without inventing one."""
    for number, line in enumerate(content.splitlines(), 1):
        if ERROR.search(line):
            return {'line': number, 'message': line[:1000]}
    return None
