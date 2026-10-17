// Opt-in only: verify_live_agents.jac supplies an isolated database/server and secrets.
import {test, expect, mock} from 'bun:test';
import {readFile, writeFile} from 'node:fs/promises';
globalThis.window = {crypto:globalThis.crypto,Error};
const storage = new Map();
globalThis.sessionStorage = {getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,String(v)),removeItem:k=>storage.delete(k)};
mock.module('@jac/runtime',()=>({__jacJsx(){},__jacSpawn(){}}));
const base = process.env.FIXORA_TEST_BASE_URL;
if (!base) throw new Error('Run through scripts/verify_live_agents.jac with FIXORA_CHECK_FRONTEND=true.');
const actualFetch = globalThis.fetch;
globalThis.fetch = (url,options)=>actualFetch(new URL(url,base),options);
const g = await import('./compiled/ui/gateway.js');

test('compiled frontend → HTTP → MongoDB/GridFS → live model → saved findings', async () => {
  const scenario = JSON.parse(process.env.FIXORA_TEST_SCENARIO);
  await g.connect('customer','customer@fixora.demo','Fixora123!');
  const model = {'demo-laptop-01':'Fixora Demo FD-100','demo-laptop-02':'Fixora Demo FD-200','demo-laptop-03':'Fixora Demo FD-300'}[scenario.claimed_model_id];
  let c = await g.create_case('alex',model,scenario.description);
  for (const kind of ['invoice','product']) {
    const relative = scenario[kind];
    const bytes = await readFile('../../fixtures/'+relative);
    c = await g.attach_evidence(c.id,c.revision,{name:relative.split('/').at(-1),kind:kind==='product'?'photo':'invoice',preview:'data:image/png;base64,'+bytes.toString('base64')});
    expect(c.evidence.at(-1).preview.split(',')[1]).toBe(bytes.toString('base64'));
  }
  const measurements=[];
  c=await g.advance_case(c.id,c.revision); // start only
  for (let i=0;i<5 && c.status==='processing';i++) {
    const start=Date.now();
    c=await g.advance_case(c.id,c.revision);
    const stage=['document','vision','coverage','repair_parts','resolution'][i];
    const result=c.backend.assessment.stages[stage];
    measurements.push({stage,status:result.status,analysis_mode:result.findings.analysis_mode,error_code:result.error?.code??null,elapsed_seconds:(Date.now()-start)/1000});
    console.log(stage,result.status,result.error?.code??'');
  }
  // Save before asserting so provider failures remain diagnosable without credentials.
  await writeFile('../live-agent-last-case.json',JSON.stringify(c.backend,null,2));
  expect(c.status).toBe(scenario.expected_status);
  const a=g.assessment(c);
  expect(a.mode).toBe('live_model');
  const outcome={scenario:scenario.id,expected_status:scenario.expected_status,actual_status:c.status,passed:true,stages:measurements};
  if (c.status==='completed') {
    const report=c.backend.assessment.stages.resolution.findings.report;
    expect(report.is_demo).toBe(false);
    expect(report.customer_payable_minor).toBeNull();
    outcome.coverage=report.coverage.outcome;
    outcome.total_cost_minor=a.options[0].estimate.total_cost_minor;
    outcome.currency=a.options[0].estimate.currency;
    if(scenario.expected_total_cost_minor!==undefined) expect(outcome.total_cost_minor).toBe(scenario.expected_total_cost_minor);
    if(scenario.expected_coverage!==undefined) expect(outcome.coverage).toBe(scenario.expected_coverage);
  }
  expect((await g.refresh_cases()).some(row=>row.id===c.id)).toBe(true);
  // Fresh module memory forces all image previews to be fetched back from GridFS.
  const reloaded=await import('./compiled/ui/gateway.js?reload='+Date.now());
  const restored=await reloaded.get_case(c.id);
  expect(restored.status).toBe(c.status);
  expect(restored.evidence).toHaveLength(2);
  expect(restored.evidence.every(e=>e.preview.startsWith('data:image/png;base64,'))).toBe(true);
  await writeFile('../frontend-live-result.json',JSON.stringify({outcome,case_id:c.id,status:c.status},null,2));
},180000);
