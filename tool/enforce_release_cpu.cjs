#!/usr/bin/env node
'use strict';

// Runner 13.2 drops job CPU options; bind the kernel's own container before updating it.
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const { isDeepStrictEqual } = require('node:util');

const FORGE = 'https://pawprint.vigilis.online';
const REPOSITORY = 'LibreKAT/Ocideck';
const API = FORGE + '/api/v1/repos/' + REPOSITORY;
const LIMIT = 2000000000;
const MAX_BYTES = 1024 * 1024;

function requireValue(condition) {
  if (!condition) throw new Error('release CPU guard refused unverifiable state');
}

function privateIPv4(address) {
  const parts = address.split('.');
  if (parts.length !== 4 || parts.some(p => !/^\d{1,3}$/.test(p) || Number(p) > 255)) return false;
  const [a, b] = parts.map(Number);
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

function kernelIdentity(mountinfo, routes) {
  const roots = {};
  for (const line of mountinfo.trim().split('\n')) {
    const fields = line.split(' ');
    if (!['/etc/hostname', '/etc/hosts'].includes(fields[4])) continue;
    requireValue(!roots[fields[4]]);
    roots[fields[4]] = fields[3];
  }
  const hostname = /^((?:\/[^/\s\\]+)*\/containers\/)([a-f0-9]{64})\/hostname$/.exec(roots['/etc/hostname'] || '');
  const hosts = /^((?:\/[^/\s\\]+)*\/containers\/)([a-f0-9]{64})\/hosts$/.exec(roots['/etc/hosts'] || '');
  requireValue(hostname && hosts && hostname[1] === hosts[1] && hostname[2] === hosts[2]);
  const defaults = routes.trim().split('\n').slice(1).map(line => line.trim().split(/\s+/))
    .filter(fields => fields[1] === '00000000');
  requireValue(defaults.length === 1);
  const route = defaults[0];
  requireValue(/^[a-fA-F0-9]{8}$/.test(route[2]) && /^[a-fA-F0-9]+$/.test(route[3])
    && (parseInt(route[3], 16) & 3) === 3 && route[7] === '00000000');
  const gateway = route[2].match(/../g).reverse().map(part => parseInt(part, 16)).join('.');
  requireValue(privateIPv4(gateway));
  return { id: hostname[2], gateway };
}

function cpuMax(content) {
  requireValue(content.length < 128);
  const match = /^(max|[1-9]\d*)\s+([1-9]\d*)\s*$/.exec(content);
  requireValue(match);
  const quota = match[1] === 'max' ? null : Number(match[1]);
  const period = Number(match[2]);
  requireValue(Number.isSafeInteger(period) && (quota === null || Number.isSafeInteger(quota)));
  return { quota, period };
}

function twoCpus(value) {
  return value.quota !== null && value.quota === value.period * 2;
}

function requestJSON({ url, method = 'GET', body, token, deadline }, modules = { http, https }, now = Date.now) {
  return new Promise((resolve, reject) => {
    let request;
    let timer;
    let finished = false;
    function finish(error, value) {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (error) {
        reject(new Error('release CPU guard request failed'));
        if (request) request.destroy();
      } else resolve(value);
    }
    try {
      const target = new URL(url);
      requireValue(!target.username && !target.password && !target.hash);
      const forge = target.origin === FORGE && target.pathname.startsWith('/api/v1/repos/' + REPOSITORY + '/actions/');
      const docker = target.protocol === 'http:' && target.port === '2375' && privateIPv4(target.hostname)
        && /^\/v1\.56\/containers\/[a-f0-9]{64}\/(json|update)$/.test(target.pathname);
      requireValue((forge && method === 'GET' && token && !/[\r\n]/.test(token))
        || (docker && !token && ((method === 'GET' && target.pathname.endsWith('/json'))
          || (method === 'POST' && target.pathname.endsWith('/update') && body === '{"NanoCpus":2000000000}'))));
      const remaining = deadline - now();
      requireValue(remaining > 0);
      const headers = { Accept: 'application/json' };
      if (forge) headers.Authorization = 'token ' + token;
      if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
        headers['Content-Length'] = Buffer.byteLength(body);
      }
      const options = { method, headers, agent: false };
      if (forge) options.rejectUnauthorized = true;
      request = (forge ? modules.https : modules.http).request(target, options, response => {
        if (response.statusCode !== 200) {
          response.resume();
          finish(true);
          return;
        }
        let length = 0;
        const chunks = [];
        response.on('data', chunk => {
          if (finished) return;
          length += chunk.length;
          if (length > MAX_BYTES) {
            finish(true);
            response.destroy();
          } else chunks.push(chunk);
        });
        response.on('error', () => finish(true));
        response.on('aborted', () => finish(true));
        response.on('end', () => {
          if (finished) return;
          try {
            requireValue(now() < deadline);
            finish(false, JSON.parse(Buffer.concat(chunks).toString('utf8')));
          } catch (_) { finish(true); }
        });
      });
      request.on('error', () => finish(true));
      timer = setTimeout(() => finish(true), Math.min(15000, remaining));
      request.end(body);
    } catch (_) { finish(true); }
  });
}

function inspectIdentity(value, identity, expected, kernelHostname) {
  requireValue(value && value.Id === identity.id && value.State?.Status === 'running'
    && value.Config?.Hostname === kernelHostname && value.Config?.Image === expected.image
    && typeof value.HostnamePath === 'string' && value.HostnamePath.endsWith('/containers/' + identity.id + '/hostname')
    && typeof value.HostsPath === 'string' && value.HostsPath.endsWith('/containers/' + identity.id + '/hosts'));
  const name = /^\/FORGEJO-ACTIONS-TASK-([1-9]\d*)_WORKFLOW-([a-f0-9]{64})_JOB-([a-zA-Z0-9_-]+)$/.exec(value.Name || '');
  // Docker JOB is a display name; the fresh API-attested TASK identifies the job.
  requireValue(name && Number.isSafeInteger(Number(name[1])));
  const host = value.HostConfig;
  requireValue(host && host.Memory === expected.memory && typeof host.Privileged === 'boolean'
    && ['PidMode', 'IpcMode', 'UTSMode', 'NetworkMode'].every(key => typeof host[key] === 'string' && host[key] !== 'host')
    && Number.isSafeInteger(host.NanoCpus) && host.NanoCpus >= 0);
  return Number(name[1]);
}

async function enforce({ env = process.env, read = path => fs.readFileSync(path, 'utf8'), hostname = os.hostname,
  request = requestJSON, now = Date.now } = {}) {
  const expected = {
    image: env.EXPECTED_IMAGE, memory: Number(env.EXPECTED_MEMORY_GIB) * 1024 ** 3,
    controller: env.GITHUB_SHA, source: env.SOURCE_SHA, run: Number(env.GITHUB_RUN_ID), job: env.GITHUB_JOB,
  };
  requireValue(env.GITHUB_REPOSITORY === REPOSITORY && /^[48]$/.test(env.EXPECTED_MEMORY_GIB || '')
    && /^pawprint\.vigilis\.online\/librekat\/[a-z0-9._-]+(?::[a-zA-Z0-9._-]+)?@sha256:[a-f0-9]{64}$/.test(expected.image || '')
    && /^[a-f0-9]{40}$/.test(expected.controller || '') && /^[a-f0-9]{40}$/.test(expected.source || '')
    && /^[1-9]\d*$/.test(env.GITHUB_RUN_ID || '') && Number.isSafeInteger(expected.run)
    && /^[a-zA-Z0-9_-]+$/.test(expected.job || '') && env.FORGEJO_TOKEN && !/[\r\n]/.test(env.FORGEJO_TOKEN));
  const deadline = now() + 60000;
  const identity = kernelIdentity(read('/proc/self/mountinfo'), read('/proc/net/route'));
  const docker = 'http://' + identity.gateway + ':2375/v1.56/containers/' + identity.id;
  async function call(url, method = 'GET', body, token) {
    requireValue(now() < deadline);
    const response = await request({ url, method, body, token, deadline });
    requireValue(now() < deadline);
    return response;
  }
  const before = await call(docker + '/json');
  const task = inspectIdentity(before, identity, expected, hostname());
  const kernelBefore = cpuMax(read('/sys/fs/cgroup/cpu.max'));
  // Never widen an administrator's existing CPU restriction or repair an unknown policy.
  requireValue(before.HostConfig.CpuQuota === 0 && before.HostConfig.CpuPeriod === 0
    && ((before.HostConfig.NanoCpus === 0 && kernelBefore.quota === null)
      || (before.HostConfig.NanoCpus === LIMIT && twoCpus(kernelBefore))));
  const run = await call(API + '/actions/runs/' + expected.run, 'GET', undefined, env.FORGEJO_TOKEN);
  requireValue(run && run.id === expected.run && run.repository?.full_name === REPOSITORY
    && Number.isSafeInteger(run.repository.id) && run.repository.id > 0 && run.commit_sha === expected.controller
    && run.status === 'running' && run.workflow_id === 'release-channel.yml' && run.trigger_event === 'workflow_dispatch'
    && typeof run.event_payload === 'string');
  const payload = JSON.parse(run.event_payload);
  requireValue(payload?.inputs?.source_sha === expected.source);
  const jobs = await call(API + '/actions/runs/' + expected.run + '/jobs', 'GET', undefined, env.FORGEJO_TOKEN);
  requireValue(Array.isArray(jobs) && jobs.length < 100);
  const matches = jobs.filter(job => job && job.task_id === task);
  requireValue(matches.length === 1 && matches[0].status === 'running' && matches[0].run_id === expected.run
    && matches[0].repo_id === run.repository.id && Number.isSafeInteger(matches[0].id) && matches[0].id > 0);
  let updated = false;
  if (before.HostConfig.NanoCpus !== LIMIT || !twoCpus(kernelBefore)) {
    const result = await call(docker + '/update', 'POST', '{"NanoCpus":2000000000}');
    requireValue(result && typeof result === 'object' && !Array.isArray(result)
      && Object.keys(result).every(key => key === 'Warnings')
      && (result.Warnings === null || (Array.isArray(result.Warnings) && result.Warnings.length === 0)));
    updated = true;
  }
  const after = await call(docker + '/json');
  requireValue(inspectIdentity(after, identity, expected, hostname()) === task && after.Name === before.Name);
  const oldHost = { ...before.HostConfig }, newHost = { ...after.HostConfig };
  delete oldHost.NanoCpus;
  delete newHost.NanoCpus;
  const kernelAfter = cpuMax(read('/sys/fs/cgroup/cpu.max'));
  requireValue(isDeepStrictEqual(oldHost, newHost) && after.HostConfig.NanoCpus === LIMIT && twoCpus(kernelAfter));
  return { source: expected.source, controller: expected.controller, run: expected.run, job: matches[0].id,
    task, container: identity.id, image: expected.image, memory_bytes: after.HostConfig.Memory,
    cpu_before: { nano_cpus: before.HostConfig.NanoCpus, kernel: kernelBefore },
    cpu_after: { nano_cpus: after.HostConfig.NanoCpus, kernel: kernelAfter }, updated };
}

if (require.main === module) {
  Promise.resolve().then(() => { requireValue(process.argv.length === 2); return enforce(); })
    .then(receipt => process.stdout.write(JSON.stringify(receipt) + '\n'))
    .catch(() => { process.stderr.write('release CPU guard: verification failed; release work refused\n'); process.exitCode = 1; });
}

module.exports = { enforce, kernelIdentity, cpuMax, requestJSON };
