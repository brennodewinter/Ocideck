// Runs against the inert HTML/CSS snapshot, with a fixed desktop viewport.
(() => {
  if (!document.querySelector('meta[name="ocideck-style-snapshot"]')) return '';
  const palette = document.createElement('canvas');
  palette.width = palette.height = 1;
  const ink = palette.getContext('2d', { willReadFrequently: true });
  const color = value => {
    if (!value || !CSS.supports('color', value.trim())) return null;
    ink.clearRect(0, 0, 1, 1);
    ink.fillStyle = '#000000';
    ink.fillStyle = value.trim();
    ink.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = ink.getImageData(0, 0, 1, 1).data;
    return a < 128 ? null : '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('').toUpperCase();
  };
  const visible = el => {
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.visibility === 'visible' && style.opacity !== '0' &&
      rect.width > 0 && rect.height > 0 && rect.right > 0 && rect.left < innerWidth;
  };
  const matches = (selector, limit) => {
    const found = [];
    const elements = document.querySelectorAll(selector);
    for (let i = 0; i < Math.min(elements.length, 400); i++) {
      if (visible(elements[i])) found.push(elements[i]);
      if (found.length === limit) break;
    }
    return found;
  };
  const heading = matches('main h1, article h1, h1, [role="heading"][aria-level="1"]', 1)[0] ??
    matches('main h2, h2', 1)[0];
  const mainParagraphs = matches('main p, article p', 8);
  const paragraphs = mainParagraphs.length ? mainParagraphs : matches('p', 8);
  const primaryText = paragraphs[0] ?? document.body;
  const applied = el => getComputedStyle(el);
  const background = el => {
    for (let node = el; node; node = node.parentElement) {
      const value = color(applied(node).backgroundColor);
      if (value) return value;
    }
    return '#FFFFFF';
  };
  const foreground = el => color(applied(el).color);
  const mainBackground = background(primaryText);
  const headingBackground = heading ? background(heading) : mainBackground;
  const fontFamily = applied(primaryText).fontFamily.slice(0, 260);

  // Read named tokens from the CSSOM, then resolve each token at an actual
  // element so overrides, active media queries and variable aliases count.
  const tokenNames = new Set([
    '--brand-primary', '--brand-color', '--brand', '--primary', '--primary-color',
    '--color-primary', '--accent', '--accent-color', '--color-accent'
  ]);
  const declarations = rule => {
    const properties = rule.style;
    if (!properties) return;
    for (let i = 0; i < Math.min(properties.length, 300); i++) {
      const name = properties.item(i);
      if (name.startsWith('--') && /brand|accent|primary/i.test(name)) tokenNames.add(name);
    }
  };
  let rulesVisited = 0;
  const walk = (rules, depth = 0) => {
    if (!rules || depth > 8) return;
    for (const rule of rules) {
      if (++rulesVisited > 4500 || tokenNames.size >= 80) return;
      declarations(rule);
      if (rule.cssRules) walk(rule.cssRules, depth + 1);
    }
  };
  for (const sheet of document.styleSheets) {
    try { walk(sheet.cssRules); } catch (_) { /* A blocked @import is optional. */ }
  }

  const accents = new Map();
  const tokenScopes = [document.documentElement, document.body];
  const offer = (value, role, weight, scope) => {
    if (!value || value === mainBackground || value === headingBackground) return;
    const previous = accents.get(value) ?? { value, score: 0, roles: new Set() };
    previous.score += weight;
    previous.roles.add(role);
    accents.set(value, previous);
    if (tokenScopes.length < 10 && !tokenScopes.includes(scope)) tokenScopes.push(scope);
  };
  for (const el of matches('button, [role="button"], a[class*="btn"], a[class*="button"]', 20)) {
    offer(color(applied(el).backgroundColor), 'buttons', 8, el);
    offer(foreground(el), 'buttons', 2, el);
  }
  for (const el of matches('nav a, header a, main a, a', 24)) {
    offer(foreground(el), 'links', 3, el);
  }
  if (heading) offer(foreground(heading), 'heading', 5, heading);

  const tokens = new Map();
  for (const scope of tokenScopes) {
    const style = applied(scope);
    for (const name of tokenNames) {
      const raw = style.getPropertyValue(name).trim();
      if (!raw) continue;
      // Some design systems store bare RGB or HSL channels in custom
      // properties. Treat them as evidence only if a rendered control matches.
      for (const value of [color(raw), color(`hsl(${raw})`), color(`rgb(${raw})`)]) {
        if (accents.has(value) && !tokens.has(value)) tokens.set(value, name);
      }
    }
  }
  const spread = hex => {
    const rgb = hex.slice(1).match(/../g).map(part => parseInt(part, 16));
    return Math.max(...rgb) - Math.min(...rgb);
  };
  let accent = null;
  let best = -1;
  const ranked = [];
  for (const candidate of accents.values()) {
    const token = tokens.get(candidate.value);
    const score = Math.min(candidate.score, 24) + candidate.roles.size * 5 +
      Math.min(spread(candidate.value), 180) / 8 + (token ? 30 : 0) -
      (candidate.value === foreground(primaryText) && !token ? 15 : 0);
    ranked.push({ value: candidate.value, score });
    if (score > best) {
      best = score;
      accent = { value: candidate.value, roles: [...candidate.roles], token };
    }
  }

  const imageUrl = value => {
    if (value === 'none') return null;
    return value.match(/url\(["']?(https:\/\/[^"')]+)["']?\)/i)?.[1] ?? null;
  };
  let titleImage = null;
  for (let node = heading; node && !titleImage; node = node.parentElement) {
    titleImage = imageUrl(applied(node).backgroundImage);
  }
  const contentImage = imageUrl(applied(document.body).backgroundImage) ??
    imageUrl(applied(document.documentElement).backgroundImage);
  const logo = matches('header img[data-ocideck-image], nav img[data-ocideck-image], img[class*="logo"][data-ocideck-image], img[alt*="logo" i][data-ocideck-image]', 10)
    .find(el => /logo|brand/i.test([el.alt, el.className, el.getAttribute('data-ocideck-image')].join(' ')));
  const hasText = paragraphs.length || heading || document.body.innerText.trim().length > 18;
  return JSON.stringify({
    hasText: Boolean(hasText),
    accent,
    palette: [...new Set([
      accent?.value, foreground(primaryText), heading ? foreground(heading) : null,
      mainBackground, headingBackground,
      ...ranked.sort((a, b) => b.score - a.score).map(candidate => candidate.value)
    ].filter(Boolean))].slice(0, 8),
    textColor: foreground(primaryText),
    titleTextColor: heading ? foreground(heading) : foreground(primaryText),
    backgroundColor: mainBackground,
    titleBackgroundColor: headingBackground,
    fontFamily,
    titleImage: titleImage === contentImage ? null : titleImage,
    contentImage,
    logo: logo?.getAttribute('data-ocideck-image') ?? null
  });
})()
