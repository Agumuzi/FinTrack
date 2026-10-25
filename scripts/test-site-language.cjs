#!/usr/bin/env node
'use strict';

// Regression test: switching away from Russian must never recurse or freeze.
// Run with: node scripts/test-site-language.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const listeners = new Map();
const root = { lang: 'en', dataset: {} };
const themeButton = { addEventListener() {}, setAttribute(name, value) { this[name] = value; } };
const menuButton = { addEventListener() {}, setAttribute(name, value) { this[name] = value; } };
const nav = {
  addEventListener() {},
  classList: { contains() { return false; }, remove() {}, toggle() { return false; } }
};
const tab = {
  dataset: { screen: 'records' },
  addEventListener() {},
  setAttribute(name, value) { this[name] = value; },
  getAttribute(name) { return name === 'aria-selected' ? 'true' : null; }
};
const image = { alt: '' };
const description = { textContent: '' };
const copyStatus = { textContent: '' };
const metaTheme = { content: '' };

const selectors = new Map([
  ['.theme-toggle', themeButton],
  ['meta[name="theme-color"]', metaTheme],
  ['.menu-toggle', menuButton],
  ['#primary-nav', nav],
  ['#gallery-image', image],
  ['#screen-panel', { setAttribute() {} }],
  ['#gallery-description', description],
  ['#copy-checksum', { addEventListener() {} }],
  ['#copy-status', copyStatus],
  ['#release-timeline', null]
]);
const document = {
  documentElement: root,
  querySelector(selector) { return selectors.get(selector) ?? null; },
  querySelectorAll(selector) {
    if (selector === '[data-screen]') return [tab];
    return [];
  },
  addEventListener(type, listener) { listeners.set(type, listener); },
  dispatchEvent(event) { listeners.get(event.type)?.(event); }
};
const window = {
  matchMedia() { return { matches: false, addEventListener() {} }; }
};
const code = fs.readFileSync(path.join(__dirname, '../website/script.js'), 'utf8');
vm.runInNewContext(code, { document, window, localStorage: {}, console }, { timeout: 2000 });

const cases = [
  ['ru', /Упорядочивайте операции/, 'Переключить на тёмную тему'],
  ['en', /Organize entries by date/, 'Switch to dark mode'],
  ['zh-CN', /按日期、类别与币种整理账目/, '切换深色模式'],
  ['ru', /Упорядочивайте операции/, 'Переключить на тёмную тему'],
  ['zh-CN', /按日期、类别与币种整理账目/, '切换深色模式'],
  ['en', /Organize entries by date/, 'Switch to dark mode']
];
for (const [language, pattern, themeLabel] of cases) {
  root.lang = language;
  document.dispatchEvent({ type: 'fintrack:languagechange' });
  assert.match(description.textContent, pattern, `Gallery must follow ${language}`);
  assert.equal(themeButton['aria-label'], themeLabel);
  assert.ok(image.alt.includes('FinTrack v1.4.1') || image.alt.includes('FinTrack v1.4.1'), 'Missing image alt');
}
console.log('PASS: Russian ⇄ English ⇄ Chinese language switching without recursion');
