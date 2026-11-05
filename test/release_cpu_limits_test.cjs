'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { enforce, kernelIdentity, cpuMax, requestJSON } = require('../tool/enforce_release_cpu.cjs');

const CID = 'a'.repeat(64);
const IMAGE = 'pawprint.vigilis.online/librekat/ocideck-ci:flutter-3.47.7@sha256:' + 'b'.repeat(64);
const DOCKER = 'http://172.18.0.1:2375/v1.56/containers/' + CID;
const FORGE = 'https://pawprint.vigilis.online/api/v1/repos/LibreKAT/Ocideck/actions/runs/13031';
const clone = value => JSON.parse(JSON.stringify(value));

function fixture() {
  const f = {
    env: { EXPECTED_IMAGE: IMAGE, EXPECTED_MEMORY_GIB: '8', GITHUB_REPOSITORY: 'LibreKAT/Ocideck',
      GITHUB_SHA: 'c'.repeat(40), SOURCE_SHA: 'd'.repeat(40), GITHUB_RUN_ID: '13031', GITHUB_JOB: 'build', FORGEJO_TOKEN: 'test-only-token' },
    mounts: `14 13 8:1 /var/lib/forgejo/dind/containers/${CID}/hostname /etc/hostname rw - ext4 /dev/a rw\n`
      + `15 13 8:1 /var/lib/forgejo/dind/containers/${CID}/hosts /etc/hosts rw - ext4 /dev/a rw\n`,
    routes: 'Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\neth0 00000000 010012AC 0003 0 0 0 00000000 0 0 0\n',
    kernel: 'max 100000\n', updatedKernel: '200000 100000\n', hostname: CID.slice(0, 12), requests: [],
    before: { Id: CID, Name: '/FORGEJO-ACTIONS-TASK-15303_WORKFLOW-' + 'e'.repeat(64) + '_JOB-build',
      State: { Status: 'running' }, Config: { Hostname: CID.slice(0, 12), Image: IMAGE, Env: ['PRIVATE=must-not-escape'] },
      HostnamePath: '/var/lib/docker/containers/' + CID + '/hostname', HostsPath: '/var/lib/docker/containers/' + CID + '/hosts',
      HostConfig: { Memory: 8 * 1024 ** 3, Privileged: false, PidMode: '', IpcMode: 'private', UTSMode: '',
        NetworkMode: 'forgejo-stack_default', NanoCpus: 0, CpuQuota: 0, CpuPeriod: 0, Binds: [], SecurityOpt: null } },
    run: { id: 13031, repository: { full_name: 'LibreKAT/Ocideck', id: 2 }, commit_sha: 'c'.repeat(40),
      status: 'running', workflow_id: 'release-channel.yml', trigger_event: 'workflow_dispatch',
      event_payload: JSON.stringify({ inputs: { source_sha: 'd'.repeat(40) } }) },
    jobs: [{ id: 27944, run_id: 13031, repo_id: 2, task_id: 15303, status: 'running',
      name: 'Localized human display name', handle: 'cf3d72e7-5a02-4118-a36c-afd49111348b' }],
    updateResult: { Warnings: [] },
  };
  let updated = false, inspections = 0;
  f.dependencies = {
    env: f.env, hostname: () => f.hostname,
    read: filename => {
      if (filename === '/proc/self/mountinfo') return f.mounts;
      if (filename === '/proc/net/route') return f.routes;
      if (filename === '/sys/fs/cgroup/cpu.max') return updated ? f.updatedKernel : f.kernel;
      throw new Error('unexpected file');
    },
    request: async options => {
      f.requests.push({ ...options });
      if (options.url === DOCKER + '/json') {
        const value = clone(f.before);
        if (++inspections > 1) {
          if (updated) value.HostConfig.NanoCpus = 2000000000;
          if (f.after) f.after(value);
        }
        return value;
      }
      if (options.url === DOCKER + '/update') { updated = true; return clone(f.updateResult); }
      if (options.url === FORGE) return clone(f.run);
      if (options.url === FORGE + '/jobs') return clone(f.jobs);
      throw new Error('unexpected request');
    },
  };
  f.posts = () => f.requests.filter(r => r.method === 'POST');
  return f;
}

test('binds self to its actual task, updates only NanoCpus once, verifies kernel and emits a safe receipt', async () => {
  const f = fixture();
  const result = await enforce(f.dependencies);
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].url, DOCKER + '/update');
  assert.equal(f.posts()[0].body, '{"NanoCpus":2000000000}');
  assert.equal(f.posts()[0].token, undefined);
  assert.equal(result.container, CID);
  assert.equal(result.run, 13031);
  assert.equal(result.task, 15303);
  assert.equal(result.job, 27944);
  assert.equal(result.source, f.env.SOURCE_SHA);
  assert.equal(result.controller, f.env.GITHUB_SHA);
  assert.deepEqual(result.cpu_after, { nano_cpus: 2000000000, kernel: { quota: 200000, period: 100000 } });
  assert.equal(result.updated, true);
  for (const request of f.requests) {
    assert.equal(request.token, request.url.startsWith(FORGE) ? 'test-only-token' : undefined);
  }
  const receipt = JSON.stringify(result);
  for (const forbidden of ['test-only-token', 'must-not-escape', 'PRIVATE', 'Authorization', 'Env', 'http://']) {
    assert.equal(receipt.includes(forbidden), false);
  }
});

test('an already enforced container is verified using only GET requests', async () => {
  const f = fixture();
  f.before.HostConfig.NanoCpus = 2000000000;
  f.kernel = '200000 100000\n';
  const receipt = await enforce(f.dependencies);
  assert.equal(receipt.updated, false);
  assert.equal(f.posts().length, 0);
  assert.equal(f.requests.filter(r => r.url === DOCKER + '/json').length, 2);
});

test('4 GiB profile uses the same guard and fixed two-core policy', async () => {
  const f = fixture(); f.env.EXPECTED_MEMORY_GIB = '4'; f.before.HostConfig.Memory = 4 * 1024 ** 3;
  assert.equal((await enforce(f.dependencies)).memory_bytes, 4 * 1024 ** 3);
});

test('a real consumer display name need not equal its canonical workflow slug', async () => {
  const f = fixture();
  f.env.GITHUB_JOB = 'consumer-deb';
  f.before.Name = f.before.Name.replace('_JOB-build', '_JOB-deb-proef-op-een-schone-Ubuntu');
  f.jobs[0].name = '.deb proef op een schone Ubuntu';
  assert.equal((await enforce(f.dependencies)).task, 15303);
  assert.equal(f.posts().length, 1);
});

test('a matrix display suffix is accepted only with the same unique API-attested task', async () => {
  const f = fixture();
  f.env.GITHUB_JOB = 'canary';
  f.before.Name = f.before.Name.replace('_JOB-build', '_JOB-canary-2');
  f.jobs[0].name = 'canary-2';
  assert.equal((await enforce(f.dependencies)).task, 15303);
  assert.equal(f.posts().length, 1);
});

const badIdentity = {
  'duplicate hostname mount': f => { f.mounts += f.mounts.split('\n')[0] + '\n'; },
  'missing hosts mount': f => { f.mounts = f.mounts.split('\n')[0] + '\n'; },
  'different mount container IDs': f => { f.mounts = f.mounts.replace(CID + '/hosts', 'f'.repeat(64) + '/hosts'); },
  'non-container mount path': f => { f.mounts = f.mounts.replaceAll('/containers/', '/directories/'); },
  'different mount prefixes': f => { f.mounts = f.mounts.replace('/var/lib/forgejo/dind/containers/' + CID + '/hosts', '/other/containers/' + CID + '/hosts'); },
  'ambiguous default gateway': f => { f.routes += f.routes.split('\n')[1] + '\n'; },
  'public gateway': f => { f.routes = f.routes.replace('010012AC', '08080808'); },
  'missing gateway': f => { f.routes = f.routes.split('\n')[0] + '\n'; },
  'route not up': f => { f.routes = f.routes.replace('0003', '0002'); },
  'kernel hostname differs': f => { f.hostname = 'different'; },
  'daemon ID differs': f => { f.before.Id = 'f'.repeat(64); },
  'daemon hostname mount differs': f => { f.before.HostnamePath = '/var/lib/docker/containers/' + 'f'.repeat(64) + '/hostname'; },
  'daemon hosts mount differs': f => { f.before.HostsPath += '/extra'; },
  'image differs': f => { f.before.Config.Image = IMAGE.replace('b'.repeat(64), 'f'.repeat(64)); },
  'unpinned expected image': f => { f.env.EXPECTED_IMAGE = 'example:latest'; },
  'repository env differs': f => { f.env.GITHUB_REPOSITORY = 'someone/else'; },
  'repository API differs': f => { f.run.repository.full_name = 'someone/else'; },
  'controller head differs': f => { f.run.commit_sha = 'f'.repeat(40); },
  'source differs': f => { f.run.event_payload = JSON.stringify({ inputs: { source_sha: 'f'.repeat(40) } }); },
  'source is absent': f => { delete f.env.SOURCE_SHA; },
  'run differs': f => { f.run.id += 1; },
  'run is not running': f => { f.run.status = 'success'; },
  'workflow differs': f => { f.run.workflow_id = 'arbitrary.yml'; },
  'event differs': f => { f.run.trigger_event = 'push'; },
  'task differs': f => { f.jobs[0].task_id += 1; },
  'job run differs': f => { f.jobs[0].run_id += 1; },
  'job repository differs': f => { f.jobs[0].repo_id += 1; },
  'duplicate task': f => { f.jobs.push(clone(f.jobs[0])); },
  'job is not running': f => { f.jobs[0].status = 'success'; },
  'malformed Docker job name': f => { f.before.Name += '/different'; },
  'Docker task differs': f => { f.before.Name = f.before.Name.replace('TASK-15303_', 'TASK-15304_'); },
  'memory differs': f => { f.before.HostConfig.Memory /= 2; },
  'memory policy is not 4 or 8': f => { f.env.EXPECTED_MEMORY_GIB = '16'; },
  'unknown privilege state': f => { delete f.before.HostConfig.Privileged; },
  'host PID namespace': f => { f.before.HostConfig.PidMode = 'host'; },
  'host network': f => { f.before.HostConfig.NetworkMode = 'host'; },
  'host IPC namespace': f => { f.before.HostConfig.IpcMode = 'host'; },
  'host UTS namespace': f => { f.before.HostConfig.UTSMode = 'host'; },
  'unknown kernel quota': f => { f.kernel = 'unknown'; },
  'existing one-core NanoCpus policy': f => { f.before.HostConfig.NanoCpus = 1000000000; },
  'existing one-core kernel policy': f => { f.kernel = '100000 100000\n'; },
  'NanoCpus and kernel disagree': f => { f.before.HostConfig.NanoCpus = 2000000000; },
  'nonzero legacy quota': f => { f.before.HostConfig.CpuQuota = 100000; },
  'nonzero legacy period': f => { f.before.HostConfig.CpuPeriod = 100000; },
  'oversized run number': f => { f.env.GITHUB_RUN_ID = '999999999999999999999999'; },
};
for (const [name, change] of Object.entries(badIdentity)) {
  test('refuses before any POST: ' + name, async () => {
    const f = fixture(); change(f);
    await assert.rejects(enforce(f.dependencies));
    assert.equal(f.posts().length, 0);
  });
}

for (const [name, change] of Object.entries({
  'warning': f => { f.updateResult = { Warnings: ['ignored setting'] }; },
  'unexpected update response': f => { f.updateResult = { Warnings: [], extra: true }; },
  'readback CPU mismatch': f => { f.after = d => { d.HostConfig.NanoCpus = 0; }; },
  'readback memory change': f => { f.after = d => { d.HostConfig.Memory /= 2; }; },
  'readback unrelated HostConfig change': f => { f.after = d => { d.HostConfig.Binds.push('/unrelated'); }; },
  'readback identity change': f => { f.after = d => { d.Id = 'f'.repeat(64); }; },
  'kernel remains max': f => { f.updatedKernel = 'max 100000\n'; },
  'kernel ratio wrong': f => { f.updatedKernel = '100000 100000\n'; },
  'kernel becomes unknown': f => { f.updatedKernel = 'unknown'; },
})) {
  test('fails closed without retry after a single POST: ' + name, async () => {
    const f = fixture(); change(f);
    await assert.rejects(enforce(f.dependencies));
    assert.equal(f.posts().length, 1);
  });
}

test('an expired overall deadline prevents any update', async () => {
  const f = fixture(); let time = 0;
  f.dependencies.now = () => time;
  const request = f.dependencies.request;
  f.dependencies.request = async options => { const result = await request(options); time += 30001; return result; };
  await assert.rejects(enforce(f.dependencies));
  assert.equal(f.posts().length, 0);
});

test('CPU-only enforcement preserves a known privilege flag without changing isolation policy', async () => {
  const f = fixture(); f.before.HostConfig.Privileged = true;
  assert.equal((await enforce(f.dependencies)).updated, true);
  assert.equal(f.before.HostConfig.Privileged, true);
  assert.equal(f.posts()[0].body, '{"NanoCpus":2000000000}');
});

test('failed update transport is never retried and never produces a receipt', async () => {
  const f = fixture(); const request = f.dependencies.request;
  f.dependencies.request = async options => {
    const value = await request(options);
    if (options.method === 'POST') throw new Error('connection disappeared after POST');
    return value;
  };
  await assert.rejects(enforce(f.dependencies));
  assert.equal(f.posts().length, 1);
  assert.equal(f.requests.at(-1).method, 'POST');
});

function transportFixture(action) {
  const calls = [];
  const module = { request(url, options, callback) {
    const req = new EventEmitter();
    req.destroyed = false;
    req.destroy = () => { req.destroyed = true; };
    req.end = body => {
      calls.push({ url: String(url), options, body, req });
      queueMicrotask(() => {
        const response = new EventEmitter(); response.statusCode = 200;
        response.resume = () => {}; response.destroy = () => {};
        callback(response); action(response, req);
      });
    };
    return req;
  } };
  return { calls, modules: { http: module, https: module } };
}

test('transport isolates authorization to the fixed TLS Forgejo repository', async () => {
  const f = transportFixture(response => { response.emit('data', Buffer.from('{}')); response.emit('end'); });
  await requestJSON({ url: FORGE, token: 'test-only-token', deadline: Date.now() + 1000 }, f.modules);
  await requestJSON({ url: DOCKER + '/json', deadline: Date.now() + 1000 }, f.modules);
  await requestJSON({ url: DOCKER + '/update', method: 'POST', body: '{"NanoCpus":2000000000}',
    deadline: Date.now() + 1000 }, f.modules);
  assert.equal(f.calls[0].options.headers.Authorization, 'token test-only-token');
  assert.equal(f.calls[0].options.rejectUnauthorized, true);
  assert.equal(f.calls[1].options.headers.Authorization, undefined);
  assert.equal(f.calls[1].options.rejectUnauthorized, undefined);
  assert.equal(f.calls[2].options.headers.Authorization, undefined);
  assert.equal(f.calls[2].body, '{"NanoCpus":2000000000}');
  for (const options of [
    { url: 'https://attacker.example/actions/run', token: 'test-only-token' },
    { url: 'https://pawprint.vigilis.online/api/v1/repos/Other/Repo/actions/runs/1', token: 'test-only-token' },
    { url: DOCKER + '/json', token: 'test-only-token' },
    { url: 'http://127.0.0.1:2375/v1.56/containers/' + CID + '/json' },
    { url: DOCKER + '/update', method: 'POST', body: '{"Memory":0}' },
  ]) await assert.rejects(requestJSON({ ...options, deadline: Date.now() + 1000 }, f.modules));
  assert.equal(f.calls.length, 3);
});

for (const [name, action] of [
  ['redirect', response => { response.statusCode = 302; }],
  ['oversized response', response => { response.emit('data', Buffer.alloc(1024 * 1024 + 1)); }],
  ['invalid JSON', response => { response.emit('data', Buffer.from('private-body')); response.emit('end'); }],
  ['aborted response', response => { response.emit('aborted'); }],
  ['response error', response => { response.emit('error', new Error('private-body')); }],
]) {
  test('bounded transport refuses ' + name + ' without leaking response or retrying', async () => {
    const f = transportFixture(response => {
      if (name === 'redirect') return;
      action(response);
    });
    if (name === 'redirect') {
      f.modules.http.request = (url, options, callback) => {
        const req = new EventEmitter(); req.destroy = () => {}; req.end = () => {
          f.calls.push({}); queueMicrotask(() => callback({ statusCode: 302, resume() {} }));
        }; return req;
      };
    }
    await assert.rejects(requestJSON({ url: DOCKER + '/json', deadline: Date.now() + 500 }, f.modules), error => {
      assert.equal(error.message, 'release CPU guard request failed'); return true;
    });
    assert.equal(f.calls.length, 1);
  });
}

test('transport absolute deadline bounds a silent response', async () => {
  const f = transportFixture(() => {});
  await assert.rejects(requestJSON({ url: DOCKER + '/json', deadline: Date.now() + 150 }, f.modules));
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].req.destroyed, true);
});

test('CLI exposes no environment token or raw error on failure and has no override arguments', () => {
  const guard = path.resolve(__dirname, '../tool/enforce_release_cpu.cjs');
  const result = spawnSync(process.execPath, [guard, '--container', CID], {
    env: { ...process.env, FORGEJO_TOKEN: 'test-only-token' }, encoding: 'utf8', timeout: 3000,
  });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, 'release CPU guard: verification failed; release work refused\n');
});

test('kernel quota parser rejects unsafe numeric values', () => {
  assert.deepEqual(cpuMax('200000 100000\n'), { quota: 200000, period: 100000 });
  for (const value of ['0 100000', '200000 0', 'NaN 100000', '999999999999999999999 100000']) {
    assert.throws(() => cpuMax(value));
  }
  assert.equal(kernelIdentity(fixture().mounts, fixture().routes).id, CID);
});
