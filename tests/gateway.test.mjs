// Run with scripts/test-ui.sh. No real HTTP, browser storage or credentials.
import {beforeEach, expect, mock, test} from 'bun:test';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';

globalThis.window = {crypto: globalThis.crypto, location: {protocol: 'http:', hostname: 'localhost'}, dispatchEvent: mock(() => {})};
mock.module('@jac/runtime', () => ({...React, __jacJsx: (type, props, children = []) => React.createElement(type ?? React.Fragment, props,
  ...children.flat(Infinity).map((child, index) => React.isValidElement(child) && child.key == null ? React.cloneElement(child, {key: index}) : child)), __jacSpawn() {}}));
mock.module('framer-motion', () => ({motion: {span: ({initial, animate, transition, children, ...props}) => React.createElement('span', props, children)}, useReducedMotion: () => true}));
const g = await import('./compiled/ui/gateway.js');
const {DemoLogin} = await import('./compiled/ui/login.js');
const {ShopDashboard} = await import('./compiled/ui/dashboard.js');
const {CaseRecord, Assessment, PartAvailability} = await import('./compiled/ui/models.js');
let calls, replies;
const savedCase = () => ({id: 'a'.repeat(32), revision: 7, evidence: [{id: 'b'.repeat(32), kind: 'invoice'}],
  messages: [], customer: 'Test customer', customer_id: '94770000001', title: 'Screen fault', model: 'FD-100', reference: 'test',
  findings: {coverage: 'potentially covered', invoice: 'SAVED-INVOICE'}});

beforeEach(() => {
  calls = []; replies = [];
  globalThis.window.dispatchEvent.mockClear();
  globalThis.fetch = mock(async (url, options = {}) => {
    calls.push({url, ...options, body: options.body ? JSON.parse(options.body) : undefined});
    const next = replies.shift() ?? {case: savedCase()};
    return new Response(JSON.stringify(next.body ?? next), {status: next.status ?? 200, headers: {'Content-Type': 'application/json'}});
  });
});

test('owner requests use cookie credentials and hydrate protected evidence URLs', async () => {
  replies.push({cases: [savedCase()]});
  const rows = await g.load_cases();
  expect(calls[0].url).toBe('http://localhost:8011/owner/cases');
  expect(calls[0].credentials).toBe('include');
  expect(calls[0].cache).toBe('no-store');
  expect(rows[0].evidence[0].preview).toContain(`/owner/cases/${rows[0].id}/evidence/`);
  expect(g.assessment(rows[0]).invoice).toBe('SAVED-INVOICE');
});

test('owner review sends the displayed revision and a request ID without service credentials', async () => {
  await g.review_case('a'.repeat(32), 7, 'approved', 'Inspected by the shop.');
  const call = calls[0];
  expect(call.url).toEndWith('/review');
  expect(call.method).toBe('POST');
  expect(call.body.expected_revision).toBe(7);
  expect(call.body.request_id).toMatch(/^[A-Za-z0-9_-]{8,80}$/);
  expect(call.body.action).toBe('approved');
  expect(call.body.access_token).toBeUndefined();
});

test('assessment is queued by one request independently of browser stage advancement', async () => {
  await g.advance_case('a'.repeat(32), 7);
  expect(calls).toHaveLength(1);
  expect(calls[0].url).toEndWith('/assess');
});

test('server conflicts preserve a useful error rather than inventing a local result', async () => {
  replies.push({status: 409, body: {error: 'This case changed. Refresh it before saving.'}});
  await expect(g.review_case('a'.repeat(32), 6, 'approved', 'Reason')).rejects.toThrow('This case changed');
});

test('expired sessions notify the UI to clear the private workspace', async () => {
  replies.push({status: 401, body: {detail: 'Sign in to the owner workspace.'}});
  await expect(g.load_cases()).rejects.toThrow('Sign in');
  expect(window.dispatchEvent).toHaveBeenCalledTimes(1);
  expect(window.dispatchEvent.mock.calls[0][0].type).toBe('fixora-session-expired');
});

test('internal notes and public replies use separate operations', async () => {
  await g.save_internal_note('a'.repeat(32), 7, 'Private diagnosis');
  await g.send_shop_message('a'.repeat(32), 7, 'Please visit the shop');
  expect(calls[0].url).toEndWith('/note');
  expect(calls[1].url).toEndWith('/message');
  await expect(g.send_shop_message('a'.repeat(32), 7, '   ')).rejects.toThrow('Write a message');
});

test('retired customer browser mutations cannot create or change cases', async () => {
  await expect(g.create_case('customer', 'model', 'scenario')).rejects.toThrow('WhatsApp');
  await expect(g.send_message('id', 1, 'message')).rejects.toThrow('WhatsApp');
  expect(calls).toHaveLength(0);
});

test('owner login renders without customer accounts or embedded demo credentials', () => {
  const html = renderToStaticMarkup(React.createElement(DemoLogin, {dark: false, onTheme() {}, onLogin() {}}));
  expect(html).toContain('Owner password');
  expect(html).not.toContain('Fixora123!');
  expect(html).not.toContain('customer@fixora.demo');
  expect(html).not.toContain('Use demo credentials');
});

function dashboardProps(c, detail = false) {
  return {cases: c.id ? [c] : [], c, detail, busy: false, tab: 'assessment', draft: '', error: '',
    onTab() {}, onDraft() {}, onSelect() {}, onAction() {}, onEvidence() {}};
}

test('an empty owner inbox renders cleanly without seeded browser cases', () => {
  const html = renderToStaticMarkup(React.createElement(ShopDashboard, dashboardProps(new CaseRecord())));
  expect(html).toContain('Saved in MongoDB');
  expect(html).toContain('No complaints found');
  expect(html).not.toContain('Studio 14');
  expect(html).not.toContain('Alex Morgan');
});

test('owner findings render saved extraction, catalogue prices and currency', () => {
  const c = new CaseRecord({...savedCase(), stage: 5, assessed_revision: 7, status: 'awaiting_approval', assessment_status: 'completed',
    analysis_mode: 'Recorded fixture extraction', findings: new Assessment({invoice: 'SAVED-INVOICE', invoice_total: 'LKR 1200.00'}),
    availability: new PartAvailability({revision: 7, status: 'in_stock', compatibility: 'confirmed', part_name: 'Saved display part',
      sku: 'SAVED-SKU', stock: 2, unit_minor: 1500, labour_minor: 350, currency: 'LKR'})});
  const html = renderToStaticMarkup(React.createElement(ShopDashboard, dashboardProps(c, true)));
  expect(html).toContain('SAVED-INVOICE');
  expect(html).toContain('SAVED-SKU');
  expect(html).toContain('LKR 18.50');
  expect(html).not.toContain('USD 899.00');
  expect(html).toContain('Recorded fixture extraction');
});
