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

async function partCase(scenario, model = 'Studio 14') {
  const sample = await g.get_case('sample-complete');
  let c = await g.create_case('alex', model, scenario);
  c = await g.send_message(c.id, c.revision, scenario === 'missing_charger' ? 'My charger is missing. Can I get a compatible one from the shop?' : 'Please check a replacement part for this laptop.');
  c = await g.attach_evidence(c.id, c.revision, {...sample.evidence[0],id:'invoice-'+c.id});
  c = await g.attach_evidence(c.id, c.revision, {...sample.evidence[1],id:'photo-'+c.id});
  return advance(c);
}

test('missing charger automatically publishes a compatible shop offer and reload retains it', async () => {
  let c = await partCase('missing_charger');
  expect(c.availability.sku).toBe('FX-AC14');
  expect(c.availability.status).toBe('in_stock');
  expect(c.availability.unit_minor).toBe(6000);
  expect(c.availability.labour_minor).toBe(0);
  expect(c.coverage).toBe('needs_review');
  const published = c.messages.find(m=>m.id===c.availability.message_id);
  expect(published.text).toContain('available from our shop');
  expect(published.text).toContain('No stock is reserved');
  expect(published.revision).toBe(c.revision);
  await g.refresh_cases();
  c = await g.get_case(c.id);
  expect(c.availability.message_id).toBe(published.id);
});

test('part checks are model-specific and repeated refreshes do not duplicate messages', async () => {
  let c = await partCase('replacement','Pro 15');
  expect(c.availability.sku).toBe('FX-CH15');
  expect(c.availability.unit_minor).toBe(5500);
  const id = c.availability.message_id;
  c = await g.check_parts(c.id,c.revision);
  c = await g.check_parts(c.id,c.revision);
  expect(c.availability.message_id).toBe(id);
  expect(c.messages.filter(m=>m.kind.startsWith('availability:')).length).toBe(1);
  expect(c.decisions.length).toBe(0);
});

test('out-of-stock and uncertain matches never claim shop availability', async () => {
  const out = await partCase('no_stock');
  expect(out.availability.status).toBe('out_of_stock');
  expect(out.availability.stock).toBe(0);
  expect(out.messages.some(m=>m.text.includes('is available from our shop'))).toBe(false);
  let unknown = await partCase('uncertain_compatibility');
  expect(unknown.availability.compatibility).toBe('unknown');
  expect(unknown.availability.sku).toBe('');
  expect(unknown.messages.some(m=>m.text.includes('is available from our shop'))).toBe(false);
  unknown = await g.correct_case(unknown.id,unknown.revision,'Studio 14','Model and matching fictional charger specification confirmed from label.');
  unknown = await advance(unknown);
  expect(unknown.availability.status).toBe('in_stock');
});

test('inventory lookup failure can retry without changing warranty decision state', async () => {
  let c = await partCase('inventory_failure');
  expect(c.status).toBe('awaiting_approval');
  expect(c.availability.status).toBe('error');
  expect(c.availability.message_id).toBe('');
  const rev = c.revision;
  c = await g.check_parts(c.id,c.revision,true);
  expect(c.availability.status).toBe('in_stock');
  expect(c.revision).toBe(rev);
  expect(c.status).toBe('awaiting_approval');
  expect(c.decisions.length).toBe(0);
});

test('correction invalidates availability and preserves revision-tagged earlier offers', async () => {
  let c = await partCase('replacement');
  const oldRevision = c.revision;
  const oldMessage = c.availability.message_id;
  c = await g.correct_case(c.id,c.revision,'Air 13','Confirmed Air 13 instead of Studio 14.');
  expect(c.availability.revision).toBe(oldRevision);
  expect(c.availability.revision).not.toBe(c.revision);
  await expect(g.check_parts(c.id,c.revision)).rejects.toThrow('assess the current');
  c = await advance(c);
  expect(c.availability.sku).toBe('FX-CH13');
  expect(c.availability.revision).toBe(c.revision);
  expect(c.availability.message_id).not.toBe(oldMessage);
  expect(c.messages.find(m=>m.id===oldMessage).revision).toBe(oldRevision);
});

test('legacy records without availability or message tags load without losing saved content', async () => {
  await update('fixora-demo-v1',rows=>rows.map(row=>{ const {availability,...old}=row; old.messages=old.messages.map(({kind,revision,...m})=>m); return old; }));
  const rows = await g.refresh_cases();
  expect(rows.length).toBe(7);
  expect(rows[0].availability.status).toBe('unchecked');
  expect(rows[0].messages[0].text).toContain('Hi Alex');
  const c = await g.check_parts(rows[0].id,rows[0].revision);
  expect(c.availability.status).toBe('in_stock');
});
