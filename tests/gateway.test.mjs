// Emitted Jac client against the real API contract with an isolated HTTP stub.
import {beforeEach, expect, mock, test} from 'bun:test';
globalThis.window = {crypto: globalThis.crypto, Error};
const storage = new Map();
globalThis.sessionStorage = {
  getItem: key => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: key => storage.delete(key),
};
mock.module('@jac/runtime', () => ({__jacJsx() {}, __jacSpawn() {}}));
const g = await import('./compiled/ui/gateway.js');
const token = 'test-only-shop-access-token';
const id = '1234567890abcdef1234567890abcdef';
const evidenceId = 'abcdef1234567890abcdef1234567890';
let calls, handler;
function raw(overrides = {}) {
  return {id, description:'The display is visibly cracked.', claimed_model_id:'demo-laptop-01',
    status:'draft', revision:0, created_at:'2026-10-17T10:00:00Z', updated_at:'2026-10-17T10:00:00Z',
    evidence:[], assessment:null, active_assessment_id:null, ...overrides};
}
const ok = data => Response.json({ok:true,data:{result:{ok:true,data,error:null}}});
const fail = (code, message) => Response.json({ok:true,data:{result:{ok:false,data:{},error:{code,message}}}});
beforeEach(() => {
  g.disconnect(); calls = []; sessionStorage.setItem('fixora-session-token',token);
  handler = () => { throw new Error('Unexpected API operation'); };
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    const name = url.split('/').at(-1);
    calls.push({url,name,body,options});
    expect(options.method).toBe('POST');
    if (name === 'demo_login') expect(body.access_token).toBeUndefined();
    else expect(body.access_token).toBe(token);
    return handler(name,body);
  };
});
test('no session means no API request; no synthetic cases are seeded', async () => {
  g.disconnect();
  expect(await g.refresh_cases()).toEqual([]);
  await expect(g.api_call('list_cases',{})).rejects.toThrow('sign in');
  expect(calls).toHaveLength(0);
});
test('normal login gets a session from the server without requesting a shop token', async () => {
  handler = () => fail('INVALID_CREDENTIALS','Incorrect demo credentials.');
  await expect(g.connect('customer','customer@fixora.demo','wrong')).rejects.toThrow('INVALID_CREDENTIALS');
  expect(sessionStorage.getItem('fixora-session-token')).toBeNull();
  handler = name => ok(name === 'demo_login' ? {session_token:token,role:'customer'} : {database:'connected'});
  await g.connect('customer','customer@fixora.demo','Fixora123!');
  expect(calls.at(-2).body).toEqual({email:'customer@fixora.demo',password:'Fixora123!',role:'customer'});
  expect(calls.at(-1).name).toBe('platform_status');
  expect(sessionStorage.getItem('fixora-session-token')).toBe(token);
  expect(sessionStorage.getItem('fixora-api-token')).toBeNull();
});
test('failed connection after login clears the new session and any legacy shop token', async () => {
  sessionStorage.setItem('fixora-api-token','legacy-private-token');
  handler = name => name === 'demo_login' ? ok({session_token:token,role:'owner'}) : fail('DATABASE_UNAVAILABLE','Database unavailable.');
  await expect(g.connect('owner','owner@fixora.demo','Fixora123!')).rejects.toThrow('DATABASE_UNAVAILABLE');
  expect(sessionStorage.getItem('fixora-api-token')).toBeNull();
  expect(sessionStorage.getItem('fixora-session-token')).toBeNull();
});
test('HTTP 200 application errors and malformed transport responses are not success', async () => {
  handler = () => fail('STALE_REVISION','Reload the case.');
  await expect(g.api_call('update_case',{})).rejects.toThrow('STALE_REVISION');
  handler = () => Response.json({ok:false});
  await expect(g.api_call('get_case',{})).rejects.toThrow('unexpected response');
  handler = () => new Response('',{status:503});
  await expect(g.api_call('get_case',{})).rejects.toThrow('HTTP 503');
});
test('network errors do not expose low-level messages or silently replay operations', async () => {
  handler = () => { throw new Error('private diagnostics should not reach UI'); };
  await expect(g.api_call('create_case',{})).rejects.toThrow('may have been saved');
  expect(calls).toHaveLength(1);
});
test('listing follows all cursor pages without imposing customer ownership', async () => {
  handler = (_,body) => ok(body.cursor ? {cases:[raw({id:'b'.repeat(32)})],next_cursor:null} : {cases:[raw()],next_cursor:id});
  const rows = await g.refresh_cases();
  expect(rows).toHaveLength(2);
  expect(calls[1].body.cursor).toBe(id);
  expect(rows[0].model).toBe('Fixora Demo FD-100');
});
test('selected case hydrates actual GridFS evidence and reuses in-memory previews', async () => {
  handler = name => name === 'get_case' ? ok({case:raw({evidence:[{id:evidenceId,kind:'product',filename:'device.png',mime_type:'image/png',size_bytes:3}]})}) : ok({mime_type:'image/png',content_base64:'YWJj'});
  let c = await g.get_case(id);
  expect(c.evidence[0].kind).toBe('photo');
  expect(c.evidence[0].preview).toBe('data:image/png;base64,YWJj');
  c = await g.get_case(id);
  expect(calls.filter(x => x.name === 'get_evidence')).toHaveLength(1);
});
test('creation maps selected catalogue model and sends a fresh submission ID', async () => {
  handler = (_,body) => ok({case:raw({description:body.description,claimed_model_id:body.claimed_model_id})});
  const c = await g.create_case('alex','Fixora Demo FD-200','  Cracked screen  ');
  expect(calls[0].body.claimed_model_id).toBe('demo-laptop-02');
  expect(calls[0].body.description).toBe('Cracked screen');
  expect(calls[0].body.submission_id.length).toBeGreaterThanOrEqual(8);
  expect(c.description).toBe('Cracked screen');
  await expect(g.create_case('alex','Fixora Demo FD-100',' ')).rejects.toThrow('Describe');
});
test('uploads translate photo kind and strip the data URL prefix', async () => {
  handler = () => ok({case:raw({revision:8,evidence:[{id:evidenceId,kind:'product',filename:'photo.png',mime_type:'image/png',size_bytes:3}]}),uploaded_evidence:{id:evidenceId}});
  const c = await g.attach_evidence(id,7,{kind:'photo',name:'photo.png',preview:'data:image/png;base64,YWJj'});
  expect(calls[0].body).toMatchObject({kind:'product',content_base64:'YWJj',expected_revision:7});
  expect(c.revision).toBe(8);
  expect(c.evidence[0].preview).toBe('data:image/png;base64,YWJj');
});
test('assessment start and advance use returned IDs and revisions without guessing', async () => {
  let current = raw({revision:2});
  handler = name => {
    if (name === 'get_case') return ok({case:current});
    current = raw({status:'processing',revision:name === 'start_assessment' ? 3 : 5,
      active_assessment_id:'a'.repeat(32),assessment:{id:'a'.repeat(32),next_stage:0,stages:{}}});
    return ok({case:current});
  };
  let c = await g.advance_case(id,2);
  expect(c.revision).toBe(3);
  expect(calls.at(-1).name).toBe('start_assessment');
  c = await g.advance_case(id,c.revision);
  expect(c.revision).toBe(5);
  expect(calls.at(-1).body).toMatchObject({assessment_id:'a'.repeat(32),expected_revision:3});
});
test('stale assessment cannot start from a cached revision', async () => {
  handler = () => ok({case:raw({revision:4})});
  await expect(g.advance_case(id,3)).rejects.toThrow('STALE_REVISION');
  expect(calls.map(c => c.name)).toEqual(['get_case']);
});
test('failed and blocked specialist findings are displayed without fabricated repairs', () => {
  const failed = g.adapt_case(raw({status:'failed',assessment:{id:'a'.repeat(32),next_stage:0,stages:{document:{status:'failed',findings:{},error:{code:'MODEL_QUOTA_EXCEEDED',message:'Provider quota exceeded.'}}}}}));
  expect(failed.failure).toContain('MODEL_QUOTA_EXCEEDED');
  expect(g.assessment(failed).options).toEqual([]);
  const blocked = g.adapt_case(raw({status:'needs_information',assessment:{id:'a'.repeat(32),next_stage:0,stages:{document:{status:'blocked',findings:{summary:'Clarify invoice.',invoice:{invoice_number:'INV-1',amount_minor:10000,currency:'LKR'},analysis_mode:'live_model'},conflicts:['Model mismatch'],missing_fields:['purchase_date']}}}}));
  expect(blocked.messages.at(-1).text).toContain('Model mismatch');
  expect(g.assessment(blocked).invoice_total).toBe('LKR 100.00');
  expect(g.assessment(blocked).mode).toBe('live_model');
  expect(g.assessment(blocked).purchase_date).toBe('Not extracted');
});
test('resolution preserves completed status, all repair options and actual currencies', () => {
  const options = [{repair_id:'display',estimate:{total_cost_minor:2650000,currency:'LKR'}}];
  const c = g.adapt_case(raw({status:'completed',revision:13,assessment:{id:'a'.repeat(32),next_stage:5,stages:{
    coverage:{status:'completed',findings:{coverage:{outcome:'outside_period',explanation:'Expired.',policy_id:'policy-1',policy_version:1,date_eligible:false,expiry_date:'2025-06-15'},policy_clauses:[]}},
    repair_parts:{status:'completed',findings:{options,analysis_mode:'live_model'}},
    resolution:{status:'completed',findings:{report:{recommendation:'Arrange inspection.',limitations:[]},analysis_mode:'live_model'}}}}}));
  const a = g.assessment(c);
  expect(c.status).toBe('completed');
  expect(a.options).toEqual(options);
  expect(a.coverage).toBe('Outside warranty period');
  expect(a.next_action).toBe('Arrange inspection.');
  expect(g.money(2650000,'LKR')).toBe('LKR 26500.00');
});
test('correction and evidence removal rely on server revision invalidation', async () => {
  handler = () => ok({case:raw({revision:21})});
  let c = await g.correct_case(id,20,'Fixora Demo FD-300','Corrected description');
  expect(calls.at(-1).body).toMatchObject({expected_revision:20,claimed_model_id:'demo-laptop-03'});
  expect(c.backend.assessment).toBeNull();
  c = await g.remove_evidence(id,21,evidenceId);
  expect(calls.at(-1).body).toMatchObject({evidence_id:evidenceId,expected_revision:21});
});
test('customer update is a server description revision and retains the selected model', async () => {
  handler = (name,body) => ok({case:name === 'get_case' ? raw() : raw({description:body.description,revision:1})});
  const c = await g.send_message(id,0,'There is also a scratch.');
  expect(calls.at(-1).name).toBe('update_case');
  expect(calls.at(-1).body.claimed_model_id).toBe('demo-laptop-01');
  expect(c.description).toContain('Customer update: There is also a scratch.');
});
test('invalid uploads fail before image decoding or API requests', async () => {
  await expect(g.read_image({type:'text/plain',size:1},'invoice',()=>{})).rejects.toThrow('JPEG or PNG');
  await expect(g.read_image({type:'image/png',size:5242881},'photo',()=>{})).rejects.toThrow('5 MB');
  expect(calls).toHaveLength(0);
});
