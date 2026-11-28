// Runs a public intake invitation against the compiled release bundle.
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const playwright = require('playwright');
const createServer = require('./server.cjs');

const title = 'Public cookbook intake';
const publicOrigin = 'https://intake.example.test';
const formUrl = `${publicOrigin}/api/v1/intake/forms/cookbook`;
const form = {
  form_ref: 'cookbook', version: 1, accepting: true, operational_status: 'open',
  snapshot: {
    format: 'ociserve-intake-form/1', title, purposes: ['Recipes'],
    privacy_text: 'Store recipes for up to one year.',
    retention: {draft_days: 30, submitted_days: 365},
    correction_policy: {allowed: true},
    definition: {
      format: 'ocideck-form/1',
      markdown: ['<!-- form id=cookbook version=1 lang=en -->', '# Cookbook',
        '<!-- field id=dish type=text required -->', '**Recipe name**',
        '<!-- answer -->', '<!-- /field id=dish -->', ''].join('\n'),
    },
  },
};

async function verify(browser, appUrl, invitation, viewport) {
  const mobile = viewport.width < 500;
  const context = await browser.newContext({locale: 'en-GB', viewport, isMobile: mobile, hasTouch: mobile});
  try {
    const page = await context.newPage();
    page.setDefaultTimeout(30000);
    const reads = [];
    await page.route(formUrl, async route => {
      const request = route.request();
      reads.push({method: request.method(), headers: await request.allHeaders()});
      return route.fulfill({
        json: form,
        headers: {
          'access-control-allow-origin': new URL(appUrl).origin,
          'cross-origin-resource-policy': 'cross-origin',
          'access-control-expose-headers': 'etag',
          etag: `"${'a'.repeat(64)}"`,
        },
      });
    });
    const agree = page.getByRole('button', {name: 'Agree', exact: true});
    for (const firstLaunch of [true, false]) {
      await page.goto(invitation);
      const semantics = page.locator('flt-semantics-placeholder');
      await semantics.waitFor({state: 'attached', timeout: 120000});
      await semantics.dispatchEvent('click');
      if (firstLaunch) {
        await agree.waitFor();
        assert.equal(reads.length, 0, 'the fresh profile must still observe licensing');
        await page.getByRole('checkbox').click();
        await agree.click();
      }
      await page.getByText(title, {exact: true}).waitFor();
      assert.equal(reads.length, firstLaunch ? 1 : 2);
      assert.equal(reads.at(-1).method, 'GET');
      for (const header of ['authorization', 'cookie', 'referer']) {
        assert.equal(reads.at(-1).headers[header], undefined);
      }
      await page.getByRole('button', {name: 'Fill in form', exact: true}).click();
      await page.getByText('Recipe name', {exact: true}).first().waitFor();
    }
  } finally {
    await context.close();
  }
}

async function main() {
  const bundle = path.resolve(process.argv[2] || 'build/web');
  const names = (process.argv[3] || 'chromium,webkit').split(',');
  const server = createServer(bundle, 'auto');
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/ocideck/`;
  const landing = http.createServer((request, response) => {
    if (request.method !== 'GET' || request.url !== '/public/cookbook') {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(303, {location: `${url}#intake=${encodeURIComponent(formUrl)}`}).end();
  });
  await new Promise(resolve => landing.listen(0, '127.0.0.1', resolve));
  try {
    const invitation = `http://127.0.0.1:${landing.address().port}/public/cookbook`;
    for (const name of names) {
      const browser = await playwright[name].launch({headless: true});
      try {
        for (const viewport of [{width: 1440, height: 900}, {width: 430, height: 932}]) {
          await verify(browser, url, invitation, viewport);
        }
        console.log(`${name} ${browser.version()}: published invitation opens in fresh and returning profiles at both widths`);
      } finally {
        await browser.close();
      }
    }
  } finally {
    await Promise.all([server, landing].map(listener =>
      new Promise(resolve => listener.close(resolve))));
  }
}

main().catch(error => {console.error(error); process.exitCode = 1;});
