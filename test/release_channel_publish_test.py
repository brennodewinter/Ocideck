"""Publication transport tests: no network, signing service or release mutation."""
import json
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHA = '1' * 40
CONTROLLER = '2' * 40

FAKE_CURL = r'''#!/usr/bin/env python3
import base64,json,os,sys
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
args=sys.argv[1:]
assert 'secret-test-token' not in ' '.join(args)
config=sys.stdin.read()
assert 'secret-test-token' in config
state_path=Path(os.environ['FAKE_STATE']); s=json.loads(state_path.read_text())
u=next((a for a in args if a.startswith('https://')),None)
if u is None:
    import re
    u=re.search(r'^url = "([^\n]+)"',config,re.M).group(1)
s['calls'].append(u)
if u.startswith('https://api.github.com/'):
    path=urlsplit(u).path
    if '/git/ref/heads/' in path:
        out={'ref':'refs/heads/codex/release-candidate-v0.7.7-'+('1'*40),'object':{'sha':'1'*40}}
    elif '/contents/' in path:
        name=path.split('/contents/',1)[1];out={'encoding':'base64','content':s['github_files'][name]}
    elif '/actions/workflows/' in path:
        workflow=path.split('/actions/workflows/',1)[1].split('/',1)[0];out={'workflow_runs':s['github_runs'][workflow]}
    elif path.endswith('/jobs'):
        rid=path.split('/runs/',1)[1].split('/',1)[0];out={'jobs':s['github_jobs'][rid]}
    else:sys.exit(22)
    state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_text(json.dumps(out));print('200',end='');sys.exit()

if '--request' in args and args[args.index('--request')+1]=='DELETE':
    assert '/branches/' in u;s['locked']=False;s['unlock_count']=s.get('unlock_count',0)+1
    state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(b'');print('204',end='');sys.exit()
if '--request' in args and args[args.index('--request')+1]=='PATCH':
    payload=json.loads(args[args.index('--data-binary')+1]);assert payload=={'draft':False}
    if s.get('fail_flip'):
        state_path.write_text(json.dumps(s));sys.exit(22)
    assert len(s['assets']) >= 5
    s['draft']=False;s['flip_count']=s.get('flip_count',0)+1
    state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(b'{}');print('200',end='');sys.exit()
if '--request' in args and '--form' not in args:
    payload=json.loads(args[args.index('--data-binary')+1])
    if u.endswith('/branches'):
        if s.get('locked'):
            state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(b'{}');print('409',end='');sys.exit()
        s['locked']=True;s['lease_posts']=s.get('lease_posts',0)+1
        body=json.dumps({'name':payload['new_branch_name'],'commit':{'id':payload['old_ref_name']}}).encode()
        state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(body)
        if s.get('lost_lease'):sys.exit(28)
        print('201',end='');sys.exit()
    if u.endswith('/tags'):
        s['tag_sha']=payload['target'];s['tag_exists']=True;s['tag_posts']=s.get('tag_posts',0)+1
        assert payload['message'].endswith('\nRelease-Mode: channels')
    elif u.endswith('/releases'):
        s['release_exists']=True;s['release_posts']=s.get('release_posts',0)+1
        assert payload['draft'] is True;s['draft']=True
    else: sys.exit(22)
    state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(b'{}')
    if s.get('lost_post'):sys.exit(28)
    print('201',end='');sys.exit()
if '--request' in args:
    part=args[args.index('--form')+1]; f=Path(part[len('attachment=@"'):-1])
    s['assets'].append({'id':len(s['assets'])+1,'name':f.name,'bytes':base64.b64encode(f.read_bytes()).decode(),'browser_download_url':'https://forge.test/download/'+f.name})
    state_path.write_text(json.dumps(s))
    if s.get('lost_post'): sys.exit(28)
    Path(args[args.index('--output')+1]).write_bytes(b'{}');print('201',end='');sys.exit()
if ('/tags/' in u and '/releases/tags/' not in u and not s.get('tag_exists',True)) or ('/releases/tags/' in u and not s.get('release_exists',True)):
    state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(b'{}');print('404',end='');sys.exit()
if '/contents/' in u: out=json.dumps({'sha':s.get('workflow_blob_bad',s['workflow_blob'])}).encode()
elif '/branches/codex%2Frelease-publish-lock-' in u: out=json.dumps({'commit':{'id':s['run']['commit_sha']}}).encode()
elif '/branches/' in u: out=json.dumps({'commit':{'id':s.get('branch_sha',s['tag_sha'])}}).encode()
elif '/releases/tags/' in u: out=json.dumps({'id':7,'tag_name':'v0.7.7','draft':s.get('draft',False)}).encode()
elif '/download/' in u:
    name=u.rsplit('/',1)[1]; out=base64.b64decode(next(a['bytes'] for a in s['assets'] if a['name']==name))
elif '/tags/' in u: out=json.dumps({'commit':{'sha':s['tag_sha']}}).encode()
elif '/actions/runs?' in u:
    query=parse_qs(urlsplit(u).query);workflow=query['workflow_id'][0]
    assert query['head_sha']==['1'*40]
    pages=s.get('quality_pages',{}).get(workflow)
    values=pages[int(query['page'][0])-1] if pages else s['quality_runs'].get(workflow,[])
    out=json.dumps({'workflow_runs':values}).encode()
elif '/actions/runs/' in u and u.endswith('/jobs') and not u.endswith('/9/jobs'):
    out=json.dumps(s.get('quality_jobs',[{'name':'quality','status':'success'}])).encode()
elif u.endswith('/actions/runs/9/jobs'): out=json.dumps(s['jobs']).encode()
elif u.endswith('/actions/runs/9'): out=json.dumps(s['run']).encode()
elif '/releases/7/assets?limit=' in u:
    page=int(parse_qs(urlsplit(u).query)['page'][0]);out=json.dumps(s['assets'][(page-1)*50:page*50]).encode()
elif u.endswith('/releases/7'): out=json.dumps({'id':7,'tag_name':'v0.7.7','draft':s.get('draft',False)}).encode()
else: sys.exit(22)
state_path.write_text(json.dumps(s));Path(args[args.index('--output')+1]).write_bytes(out);print('200',end='')
'''


FAKE_GIT = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['FAKE_STATE']);s=json.loads(p.read_text());a=sys.argv[3:]
assert os.environ['GIT_TERMINAL_PROMPT']=='0'
assert 'StrictHostKeyChecking=yes' in os.environ['GIT_SSH_COMMAND']
s.setdefault('git_calls',[]).append(a)
if a[:2]==['remote','get-url']:
    if s.get('missing_mirror') and a[2]=='mirror':sys.exit(2)
    out=s.get('mirror_url','git@forge.test:org/repo.git')
elif a[0]=='ls-remote':
    remote=a[2];sha=s.get('mirror_sha',s['tag_sha']) if remote=='mirror' else s['tag_sha'] if s.get('tag_exists',True) else None
    if sha is None:p.write_text(json.dumps(s));sys.exit(2)
    out='a'*40+'\t'+a[3]+'\n'+sha+'\t'+a[4]
elif a[0]=='fetch':s['fetched']=True;out=''
elif a[0]=='rev-parse':out=s['tag_sha']
elif a[0]=='push':
    assert '--force' not in a
    assert s.get('fetched')
    s['mirror_sha']=s['tag_sha'];s['mirror_pushes']=s.get('mirror_pushes',0)+1;out=''
    if s.get('lost_git_push'):p.write_text(json.dumps(s));sys.exit(1)
else:sys.exit(1)
p.write_text(json.dumps(s));print(out)
'''


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name).resolve()
        self.channel = 'web'
        self.dist = self.path / 'dist'
        self.proof = self.path / 'evidence'
        self.dist.mkdir()
        self.proof.mkdir()
        asset = self.dist / 'ocideck-web-0.7.7.tar.gz'
        asset.write_bytes(b'archive bytes')
        subprocess.run(['python3', str(ROOT / 'tool/release_channel.py'), 'create', '--tag', 'v0.7.7', '--sha', SHA, '--controller-sha', CONTROLLER, '--channel', 'web', '--run-id', '9', '--dist', str(self.dist), '--output', str(self.proof / 'channel-manifest-web.json')], check=True, capture_output=True)
        for name in ('channel-manifest-web.json', 'SHA256SUMS.web'):
            (self.proof / (name + '.minisig')).write_bytes(b'signature')
        bin_dir = self.path / 'bin'
        bin_dir.mkdir()
        (bin_dir / 'curl').write_text(FAKE_CURL)
        (bin_dir / 'git').write_text(FAKE_GIT)
        (bin_dir / 'minisign').write_text('#!/bin/sh\nexit "${BAD_SIGNATURE:-0}"\n')
        for file in bin_dir.iterdir():
            file.chmod(0o755)
        self.state = {'assets': [], 'calls': [], 'tag_sha': SHA, 'run': {'id': 9, 'commit_sha': CONTROLLER, 'status': 'success', 'workflow_id': 'release-channel.yml', 'prettyref': 'main'}, 'jobs': [{'name': 'build', 'status': 'success'}, {'name': 'evidence', 'status': 'success'}, {'name': 'consumer-rpm', 'status': 'skipped'}]}
        self.state['quality_runs'] = {workflow: [{'id': index + 100, 'commit_sha': SHA,
            'workflow_id': workflow, 'status': 'success'}]
            for index, workflow in enumerate(('static-gate.yml', 'scans.yml', 'linux-gate.yml'))}
        workflow = (ROOT / '.forgejo/workflows/release.yml').read_bytes()
        self.state['workflow_blob'] = hashlib.sha1(b'blob ' + str(len(workflow)).encode() + b'\0' + workflow).hexdigest()
        self.state_file = self.path / 'state.json'
        self.env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'], FORGEJO_TOKEN='secret-test-token', FORGEJO_API_URL='https://forge.test/api/v1/repos/a/b', FAKE_STATE=str(self.state_file))

    def run_publish(self):
        self.state_file.write_text(json.dumps(self.state))
        result = subprocess.run(['bash', str(ROOT / 'scripts/publish_release_channel.sh'), '--release-id', 'auto' if getattr(self, 'create', False) or getattr(self, 'auto_status', False) else '7', '--run-id', '9', '--tag', 'v0.7.7', '--sha', SHA, '--controller-sha', CONTROLLER, '--channel', self.channel, '--dist', str(self.dist), '--evidence', str(self.proof), '--receipt', str(self.path / 'receipt.json'), '--staging-dir', str(self.path / 'sealed')] + (['--create-release'] if getattr(self, 'create', False) else []) + (['--verify-only'] if getattr(self, 'verify_only', False) else []), env=self.env, capture_output=True, text=True)
        self.state = json.loads(self.state_file.read_text())
        self.assertNotIn('secret-test-token', result.stdout + result.stderr)
        return result

    def configure_windows(self):
        self.channel = 'windows'
        for path in [*self.dist.iterdir(), *self.proof.iterdir()]:
            path.unlink()
        zip_bytes, installer_bytes = b'zip bytes', b'installer bytes'
        (self.dist / 'ocideck-windows-x64-0.7.7.zip').write_bytes(zip_bytes)
        (self.dist / 'ocideck-windows-x64-setup-0.7.7.exe').write_bytes(installer_bytes)
        (self.dist / 'ocideck-windows-cohort-0.7.7.json').write_text(json.dumps({'tag_commit': SHA, 'run_id': 20,
            'sha256': {'zip': hashlib.sha256(zip_bytes).hexdigest(), 'installer': hashlib.sha256(installer_bytes).hexdigest()}}))
        self.state['github_files'] = {'.github/workflows/' + name: base64.b64encode((ROOT / '.github/workflows' / name).read_bytes()).decode()
                                     for name in ('release.yml', 'windows-test-check.yml')}
        self.state['github_files']['pubspec.yaml'] = base64.b64encode(b'version: 0.7.7+49\n').decode()
        for kind, content in [('cdx', {'metadata': {'component': {'version': '0.7.7+49'}}}),
                              ('spdx', {'packages': [{'name': 'ocideck', 'versionInfo': '0.7.7+49'}]})]:
            body = json.dumps(content).encode()
            (self.dist / ('ocideck-0.7.7.' + kind + '.json')).write_bytes(body)
            self.state['github_files']['sbom/ocideck.' + kind + '.json'] = base64.b64encode(body).decode()
        self.state['github_runs'], self.state['github_jobs'] = {}, {}
        for workflow, rid, name in [('release.yml', 20, 'Build Windows'), ('windows-test-check.yml', 10, 'Test (windows-2022)')]:
            self.state['github_runs'][workflow] = [{'id': rid, 'head_sha': SHA, 'head_branch': 'codex/release-candidate-v0.7.7-' + SHA,
                'event': 'workflow_dispatch', 'path': '.github/workflows/' + workflow, 'display_title': 'Windows candidate v0.7.7',
                'status': 'completed', 'conclusion': 'success'}]
            self.state['github_jobs'][str(rid)] = [{'name': name, 'status': 'completed', 'conclusion': 'success'}]
        self.state['quality_runs'].pop('linux-gate.yml')
        subprocess.run(['python3', str(ROOT / 'tool/release_channel.py'), 'create', '--tag', 'v0.7.7', '--sha', SHA,
            '--controller-sha', CONTROLLER, '--channel', 'windows', '--run-id', '9', '--dist', str(self.dist),
            '--output', str(self.proof / 'channel-manifest-windows.json')], check=True, capture_output=True)
        for name in ('channel-manifest-windows.json', 'SHA256SUMS.windows'):
            (self.proof / (name + '.minisig')).write_bytes(b'signature')
        self.env['GH_DISPATCH_TOKEN'] = 'secret-test-token'

    def test_windows_requires_own_suite_native_and_cohort_not_linux_gate(self):
        self.configure_windows()
        result = self.run_publish()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(9, len(self.state['assets']))
        self.assertFalse(any('workflow_id=linux-gate.yml' in url for url in self.state['calls']))
        self.assertTrue(any('/actions/workflows/windows-test-check.yml/runs?' in url for url in self.state['calls']))

    def test_windows_pending_suite_blocks_publication(self):
        self.configure_windows()
        self.state['github_runs']['windows-test-check.yml'][0]['status'] = 'in_progress'
        self.state['github_runs']['windows-test-check.yml'][0]['conclusion'] = None
        result = self.run_publish()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], self.state['assets'])

    def test_windows_changed_workflow_blocks_publication(self):
        self.configure_windows()
        self.state['github_files']['.github/workflows/release.yml'] = base64.b64encode(b'unsafe workflow').decode()
        result = self.run_publish()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], self.state['assets'])

    def test_lost_post_reconciles_and_repeat_reuses_identical_bytes(self):
        self.state['lost_post'] = True
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(len(self.state['assets']), 5)
        receipt = json.loads((self.path / 'receipt.json').read_text())
        self.assertEqual(receipt['controller_sha'], CONTROLLER)
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(len(self.state['assets']), 5)

    def test_pending_jobs_rejected_before_upload(self):
        self.state['jobs'][0]['status'] = 'running'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['assets'], [])

    def test_source_quality_is_required_before_any_public_write(self):
        original = json.loads(json.dumps(self.state))
        for problem in ('missing', 'different_sha', 'different_workflow', 'invalid_id', 'newer_pending', 'skipped_job', 'failed_job'):
            with self.subTest(problem=problem):
                self.state = json.loads(json.dumps(original))
                values = self.state['quality_runs']['linux-gate.yml']
                if problem == 'missing':
                    values.clear()
                elif problem == 'different_sha':
                    values[0]['commit_sha'] = CONTROLLER
                elif problem == 'different_workflow':
                    values[0]['workflow_id'] = 'release-channel.yml'
                elif problem == 'invalid_id':
                    values[0]['id'] = True
                elif problem == 'newer_pending':
                    values.append(dict(values[0], id=999, status='running'))
                else:
                    self.state['quality_jobs'] = [{'name': 'quality', 'status': 'skipped' if problem == 'skipped_job' else 'failure'}]
                self.assertNotEqual(self.run_publish().returncode, 0)
                self.assertEqual([], self.state['assets'])
                self.assertFalse(self.state.get('lease_posts'))
                self.assertFalse(self.state.get('tag_posts'))

    def test_source_quality_inspects_later_pages_before_selecting_latest(self):
        workflow = 'linux-gate.yml'
        first = [dict(self.state['quality_runs'][workflow][0], id=index, status='failure')
                 for index in range(200, 300)]
        self.state['quality_pages'] = {workflow: [first, [dict(first[0], id=301, status='success')]]}
        self.assertEqual(0, self.run_publish().returncode)
        self.assertTrue(any('page=2&' in url and 'workflow_id=linux-gate.yml' in url for url in self.state['calls']))

    def test_wrong_source_or_controller_rejected(self):
        self.state['tag_sha'] = '3' * 40
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['assets'], [])
        self.state['tag_sha'] = SHA
        self.state['run']['commit_sha'] = SHA
        self.assertNotEqual(self.run_publish().returncode, 0)

    def test_signature_failure_never_calls_api(self):
        self.env['BAD_SIGNATURE'] = '1'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['calls'], [])

    def test_conflicting_asset_not_replaced(self):
        self.assertEqual(self.run_publish().returncode, 0)
        self.state['assets'][0]['bytes'] = 'YmFk'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(len(self.state['assets']), 5)

    def test_cross_host_download_rejected_without_token_forward(self):
        self.assertEqual(self.run_publish().returncode, 0)
        self.state['assets'][0]['browser_download_url'] = 'https://attacker.test/asset'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertFalse(any('attacker.test' in call for call in self.state['calls']))

    def test_failure_never_writes_receipt_and_conflict_never_overwrites(self):
        self.state['jobs'][0]['status'] = 'running'
        self.assertNotEqual(self.run_publish().returncode, 0)
        receipt = self.path / 'receipt.json'
        self.assertFalse(receipt.exists())
        self.state['jobs'][0]['status'] = 'success'
        receipt.write_bytes(b'previous receipt')
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(receipt.read_bytes(), b'previous receipt')

    def test_assets_after_first_page_are_reused(self):
        self.assertEqual(self.run_publish().returncode, 0)
        ours = self.state['assets']
        prefix = [{'id': n + 100, 'name': 'other-' + str(n)} for n in range(55)]
        self.state['assets'] = prefix + ours
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(len(self.state['assets']), 60)
        self.assertTrue(any('page=2' in call for call in self.state['calls']))

    def test_draft_release_never_uploads_or_receipts(self):
        self.state['draft'] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['assets'], [])
        self.assertFalse((self.path / 'receipt.json').exists())

    def test_archive_io_uses_streamed_copy_hash_and_curl_output(self):
        script = (ROOT / 'scripts/publish_release_channel.sh').read_text()
        self.assertNotIn('.read_bytes()', script)
        self.assertIn('stream.read(1024 * 1024)', script)
        self.assertIn('os.O_NOFOLLOW | os.O_NONBLOCK', script)
        self.assertIn("['--output', str(destination)]", script)

    def test_first_channel_creates_tag_and_public_release_once_after_checks(self):
        self.create = True
        self.state.update(tag_exists=False, release_exists=False, lost_post=True)
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['tag_posts'], 1)
        self.assertEqual(self.state['release_posts'], 1)
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['tag_posts'], 1)
        self.assertEqual(self.state['release_posts'], 1)

    def test_create_rejects_wrong_frozen_branch_before_mutation(self):
        self.create = True
        self.state.update(tag_exists=False, release_exists=False, branch_sha='4' * 40)
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertNotIn('tag_posts', self.state)
        self.assertNotIn('release_posts', self.state)

    def test_create_signature_failure_never_creates_tag(self):
        self.create = True
        self.state.update(tag_exists=False, release_exists=False)
        self.env['BAD_SIGNATURE'] = '1'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['calls'], [])

    def test_existing_remote_lease_refuses_second_writer(self):
        self.state['locked'] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['assets'], [])
        self.assertTrue(self.state['locked'])

    def test_lost_lease_post_never_claims_ownership(self):
        self.state['lost_lease'] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertTrue(self.state['locked'])
        self.assertEqual(self.state['assets'], [])
        self.assertNotIn('unlock_count', self.state)

    def test_post_lease_failure_preserves_lock_success_releases_it(self):
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertFalse(self.state['locked'])
        self.assertEqual(self.state['unlock_count'], 1)
        self.state['assets'][0]['bytes'] = 'YmFk'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertTrue(self.state['locked'])
        self.assertEqual(self.state['unlock_count'], 1)

    def test_old_source_workflow_cannot_bootstrap_tag(self):
        self.create = True
        self.state.update(tag_exists=False, release_exists=False, workflow_blob_bad='9' * 40)
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertNotIn('tag_posts', self.state)
        self.assertNotIn('lease_posts', self.state)

    def test_failed_bootstrap_retains_signed_candidate_and_draft(self):
        self.create = True
        self.state.update(tag_exists=False, release_exists=False, fail_flip=True)
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertTrue(self.state['draft'])
        self.assertTrue(self.state['locked'])
        self.assertEqual((self.path / 'sealed/dist/ocideck-web-0.7.7.tar.gz').read_bytes(), b'archive bytes')
        self.assertTrue((self.path / 'sealed/evidence/channel-manifest-web.json.minisig').exists())
        self.assertFalse((self.path / 'receipt.json').exists())

    def test_candidate_staging_rejects_changed_or_symlink_bytes(self):
        self.assertEqual(self.run_publish().returncode, 0)
        sealed = self.path / 'sealed/dist/ocideck-web-0.7.7.tar.gz'
        sealed.write_bytes(b'wrong staged bytes')
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertFalse(self.state['locked'])
        sealed.unlink()
        sealed.symlink_to(self.dist / sealed.name)
        self.assertNotEqual(self.run_publish().returncode, 0)

    def test_own_existing_draft_resumes_and_publishes_after_all_assets(self):
        self.create = True
        self.state.update(draft=True, release_exists=True)
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertFalse(self.state['draft'])
        self.assertEqual(self.state['flip_count'], 1)

    def test_staged_candidate_can_be_input_after_original_is_removed(self):
        self.assertEqual(self.run_publish().returncode, 0)
        import shutil
        shutil.rmtree(self.dist)
        shutil.rmtree(self.proof)
        self.dist = self.path / 'sealed/dist'
        self.proof = self.path / 'sealed/evidence'
        self.assertEqual(self.run_publish().returncode, 0)

    def test_verify_only_reads_public_bytes_without_mutations_or_state_writes(self):
        self.assertEqual(self.run_publish().returncode, 0)
        self.verify_only = True
        self.auto_status = True
        before = {str(p.relative_to(self.path)): (p.stat().st_mtime_ns, p.read_bytes()) for p in self.path.rglob('*') if p.is_file() and p != self.state_file}
        mutations = {key: self.state.get(key) for key in ('lease_posts', 'unlock_count', 'tag_posts', 'release_posts', 'flip_count')}
        self.assertEqual(self.run_publish().returncode, 0)
        after = {str(p.relative_to(self.path)): (p.stat().st_mtime_ns, p.read_bytes()) for p in self.path.rglob('*') if p.is_file() and p != self.state_file}
        self.assertEqual(before, after)
        self.assertEqual(mutations, {key: self.state.get(key) for key in mutations})

    def test_verify_only_missing_tampered_or_pending_is_red_and_never_repaired(self):
        self.assertEqual(self.run_publish().returncode, 0)
        self.verify_only = True
        saved = self.state['assets'].pop()
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(len(self.state['assets']), 4)
        self.state['assets'].append(saved)
        self.state['assets'][0]['bytes'] = 'YmFk'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.state['jobs'][0]['status'] = 'running'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['lease_posts'], 1)

    def test_verify_only_never_bootstraps_even_with_create_flag(self):
        self.create = True
        self.verify_only = True
        self.state.update(tag_exists=False, release_exists=False)
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertNotIn('lease_posts', self.state)
        self.assertNotIn('tag_posts', self.state)
        self.assertNotIn('release_posts', self.state)

    def test_missing_mirror_remote_stops_before_public_mutation(self):
        self.state['missing_mirror'] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['calls'], [])

    def test_mirror_tag_missing_pushes_once_and_reconciles_lost_response(self):
        self.state.update(mirror_sha=None, lost_git_push=True)
        self.assertEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['mirror_pushes'], 1)
        self.assertEqual(self.state['mirror_sha'], SHA)
        receipt = json.loads((self.path / 'receipt.json').read_text())
        self.assertEqual(receipt['mirror_source'], SHA)

    def test_conflicting_mirror_and_credential_url_are_rejected(self):
        self.state['mirror_sha'] = '9' * 40
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['calls'], [])
        self.state['mirror_sha'] = SHA
        self.state['mirror_url'] = 'https://password@forge.test/org/repo'
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.state['calls'], [])

    def test_verify_only_missing_mirror_never_pushes(self):
        self.verify_only = True
        self.state['mirror_sha'] = None
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertNotIn('mirror_pushes', self.state)
        self.assertFalse(any(call[0] in ('fetch', 'push') for call in self.state['git_calls']))


if __name__ == '__main__':
    unittest.main()
