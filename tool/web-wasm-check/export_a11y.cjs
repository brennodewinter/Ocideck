const assert = require('node:assert/strict');
const {resolve} = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require('playwright');
const axe = require('axe-core');

async function checkExport() {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(resolve('build/html-a11y/fixture.html')).href);
    await page.locator('.mermaid svg').waitFor({state: 'visible'});
    assert.equal(await page.getByRole('main').count(), 1);
    assert.equal(await page.getByRole('heading', {level: 1, name: 'Workshop handout'}).count(), 1);
    assert.equal(await page.getByRole('columnheader', {name: 'Count'}).count(), 1);
    assert.equal(await page.getByRole('img', {name: /January 120, February 138/}).count(), 1);
    assert.equal(await page.locator('.ocideck-callout[role="img"][aria-label]').count(), 1);
    assert.equal(await page.getByText('Update the plan', {exact: true}).isVisible(), true);

    const first = page.getByRole('link', {name: 'Start the workshop'});
    const last = page.getByRole('link', {name: 'Review the method'});
    await page.keyboard.press('Tab');
    assert.equal(await first.evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Tab');
    assert.equal(await last.evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Shift+Tab');
    assert.equal(await first.evaluate(node => node === document.activeElement), true);

    await page.evaluate(axe.source);
    const audit = () => page.evaluate(async () => {
      const report = await window.axe.run({
        runOnly: ['color-contrast', 'image-alt', 'aria-roles', 'aria-valid-attr-value',
          'button-name', 'link-name', 'landmark-one-main', 'html-has-lang'],
      });
      return report.violations.map(({id, nodes}) =>
        ({id, targets: nodes.map(node => node.target)}));
    });
    assert.deepEqual(await audit(), []);

    // Give a real link insufficient contrast. The control
    // proves Chromium executed the contrast rule against this exported page.
    await first.evaluate(node => {
      node.style.backgroundColor = '#ffffff';
      node.style.color = '#eeeeee';
    });
    assert.ok((await audit()).some(rule => rule.id === 'color-contrast'));
    console.log('HTML export accessibility: semantics, keyboard order and contrast passed');
  } finally {
    await browser.close();
  }
}

checkExport().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
