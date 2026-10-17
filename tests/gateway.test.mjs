// Run with scripts/test-ui.sh. Only an isolated, in-memory IndexedDB is used.
import {beforeEach, expect, mock, test} from 'bun:test';
import 'fake-indexeddb/auto';
import {del, get, update} from 'idb-keyval';

globalThis.window = {crypto: globalThis.crypto};
// The gateway imports these emitted runtime symbols but does not use JSX/spawn.
mock.module('@jac/runtime', () => ({__jacJsx() {}, __jacSpawn() {}}));
const g = await import('./compiled/ui/gateway.js');

beforeEach(async () => {
  await del('fixora-demo-v1');
  await g.refresh_cases();
});

async function advance(c) {
  let result = await g.advance_case(c.id, c.revision);
  while (result.status === 'processing') result = await g.advance_case(result.id, result.revision);
  return result;
}

test('seven persisted sample cases and customer-scoped search', async () => {
  expect((await g.load_cases()).length).toBe(7);
  expect((await g.search_cases('', 'alex', false)).length).toBe(4);
  expect((await g.search_cases('', 'jamie', false)).length).toBe(3);
  expect((await g.search_cases('FX-1052', 'alex', false)).length).toBe(0);
  expect((await g.search_cases('FX-1052', 'alex', true)).length).toBe(1);
});

test('message validation preserves saved inputs and new cases require evidence', async () => {
  let c = await g.create_case('alex', 'Studio 14', 'complete');
  await expect(g.send_message(c.id, c.revision, '   ')).rejects.toThrow('Write a message');
  c = await g.send_message(c.id, c.revision, 'Charging stops when the connector moves.');
  await expect(g.advance_case(c.id, c.revision)).rejects.toThrow('Attach one invoice');
  expect((await g.get_case(c.id)).description).toBe('Charging stops when the connector moves.');
});

test('upload type and size validation runs before image decoding', async () => {
  await expect(g.read_image({type:'text/plain',size:10}, 'invoice', () => {})).rejects.toThrow('JPEG or PNG');
  await expect(g.read_image({type:'image/png',size:5242881}, 'photo', () => {})).rejects.toThrow('5 MB');
});

test('shop replies publish to customer chat without changing assessment or decisions', async () => {
  let c = await g.get_case('sample-auto');
  const revision = c.revision;
  const decisionCount = c.decisions.length;
  await expect(g.send_shop_message(c.id, revision, '   ')).rejects.toThrow('Write a reply');
  c = await g.send_shop_message(c.id, revision, 'Please bring your charger when you visit.');
  await g.refresh_cases();
  c = await g.get_case(c.id);
  expect(c.messages.at(-1).role).toBe('shop');
  expect(c.messages.at(-1).internal).toBe(false);
  expect(c.messages.at(-1).text).toBe('Please bring your charger when you visit.');
  expect(c.revision).toBe(revision);
  expect(c.status).toBe('approved');
  expect(c.decisions.length).toBe(decisionCount);
});

test('upload-to-assessment-to-owner-decision survives reloading', async () => {
  const sample = await g.get_case('sample-complete');
  let c = await g.create_case('alex', 'Studio 14', 'complete');
  c = await g.send_message(c.id, c.revision, 'Charging stops when the connector moves.');
  c = await g.attach_evidence(c.id, c.revision, {...sample.evidence[0],id:'test-invoice'});
  await expect(g.attach_evidence(c.id, c.revision, {...sample.evidence[0],id:'extra'})).rejects.toThrow('maximum');
  c = await g.attach_evidence(c.id, c.revision, {...sample.evidence[1],id:'test-photo'});
  c = await advance(c);
  expect(c.status).toBe('awaiting_approval');
  c = await g.review_case(c.id, c.revision, 'approved', 'Supported sample repair confirmed.');
  await g.refresh_cases();
  const saved = await g.get_case(c.id);
  expect(saved.status).toBe('approved');
  expect(saved.evidence.length).toBe(2);
  expect(saved.messages.at(-1).text).toContain('Supported sample repair confirmed.');
});

test('corrections invalidate current approval but preserve decision history', async () => {
  let c = await g.get_case('sample-auto');
  c = await g.correct_case(c.id,c.revision,'Studio 14','Confirmed from the product label.','shop');
  expect(c.status).toBe('draft');
  expect(c.decisions.length).toBe(1);
  expect(c.messages.at(-1).role).toBe('shop');
  expect(c.decisions[0].revision).not.toBe(c.revision);
  await expect(g.review_case(c.id,c.revision,'approved','Too early')).rejects.toThrow('Assess the latest');
});

test('conflicts and uncertain inspection findings cannot be approved', async () => {
  let c = await g.get_case('sample-conflict');
  await expect(g.review_case(c.id,c.revision,'approved','Guess')).rejects.toThrow('Resolve the missing');
  c = await g.correct_case(c.id,c.revision,'Pro 15','Model confirmed from label; customer explained mismatch.');
  expect((await advance(c)).status).toBe('awaiting_approval');
  let i = await g.get_case('sample-inspection');
  i = await g.inspect_case(i.id,i.revision,'Further diagnostics required','Power fault not established.');
  expect((await advance(i)).status).toBe('needs_inspection');
  i = await g.get_case(i.id);
  i = await g.inspect_case(i.id,i.revision,'Charging connector failure confirmed','Continuity test confirms connector fault.');
  i = await advance(i);
  expect(i.status).toBe('awaiting_approval');
  expect(i.messages.filter(m=>m.internal).length).toBe(2);
});

test('timeout has a retry path; missing stock is not fabricated', async () => {
  let c = await g.get_case('sample-failure');
  c = await advance(c);
  expect(c.status).toBe('awaiting_approval');
  expect(g.assessment(await g.get_case('sample-no_stock')).stock).toBe(0);
  const rejected = await g.get_case('sample-rejected');
  expect(rejected.coverage).toBe('outside_period');
  expect(g.assessment(rejected).next_action).toContain('paid repair');
});

test('atomic writes reject stale tabs without overwriting newer decisions', async () => {
  const c = await g.get_case('sample-complete');
  await update('fixora-demo-v1', rows => rows.map(row => row.id === c.id ? {...row,version:row.version+1,status:'needs_information'} : row));
  await expect(g.review_case(c.id,c.revision,'approved','Stale tab')).rejects.toThrow('changed in another view');
  const stored = await get('fixora-demo-v1');
  expect(stored.find(row=>row.id===c.id).status).toBe('needs_information');
  expect(stored.find(row=>row.id===c.id).decisions.length).toBe(0);
});
