const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {GatewayClient}=require('../miniprogram/lib/client');
const {DemoClient,route}=require('../miniprogram/lib/demo');
const map=require('../miniprogram/lib/map-data');
const flush=()=>new Promise(r=>setImmediate(r));
const tests=[],clients=[];function test(name,fn){tests.push([name,fn]);}
function fake(){let now=100000, seq=-1, armed=false, direction='S',holdArm=null,delay=false;const writes=[];
  const snapshot=()=>({demo:true,remote:{armed},direction});
  const request=async opt=>{if(opt.url.endsWith('/v1/session'))return{statusCode:200,data:{session_id:'test',server_time_ms:now}};
    if(opt.url.endsWith('/v1/state'))return{statusCode:200,data:snapshot()};
    const d=opt.data;writes.push(d);
    if(d.seq<=seq)return{statusCode:409,data:{error:'stale'}};seq=d.seq;
    if(d.action==='arm')armed=true;if(d.action==='stop'){armed=false;direction='S';}
    if(d.action==='manual.move')direction=d.payload.direction;if(d.action==='manual.release')direction='S';
    const result={statusCode:200,data:{accepted:true,state:snapshot()}};
    if(d.action==='arm'&&delay)return new Promise(r=>{holdArm=()=>r(result);});return result;};
  const client=new GatewayClient(request,()=>{},()=>now);clients.push(client);
  return{client,writes,advance:ms=>now+=ms,delay:()=>delay=true,resolve:()=>holdArm(),snapshot};
}
test('demo map valid goal, blocked goal, app hide stops',async()=>{
  assert.ok(route(map.occupied,[17,2],[17,17]).length>5);assert.equal(route(map.occupied,[17,2],[0,0]).length,0);
  const d=new DemoClient(()=>{});await d.connect();await assert.rejects(()=>d.action('manual.move',{direction:'F'}));
  await d.action('arm');await d.action('manual.move',{direction:'F'});assert.equal(d.state.direction,'F');d.hide();assert.equal(d.state.direction,'S');assert.equal(d.armed,false);
  d.show();assert.equal(d.armed,false);await d.action('nav.preview',{goal:[17,17]});await d.action('arm');await d.action('nav.start');
  for(let i=0;i<100;i++)d.tick();assert.equal(d.state.tasks.active,false);assert.deepEqual(d.state.map.current,[17,17]);d.disconnect();
});
test('real client validates address and code',()=>{const {client:c}=fake();
  for(const url of ['https://example.com','http://8.8.8.8:8765','http://192.168.999.2:8765','http://192.168.1.2:70000'])assert.throws(()=>c.configure(url,'long-secret-123456'));
  assert.throws(()=>c.configure('http://192.168.1.2:8765','short'));c.configure('http://192.168.1.2:8765','long-secret-123456');
});
test('explicit arm, release cancels queued press, no resume after hide',async()=>{const f=fake(),c=f.client;await c.connect('http://127.0.0.1:8765','offline-secret-123');
  await c.action('arm');assert.ok(c.armed);const pending=c.action('manual.move',{direction:'F'}).catch(()=>{});await c.release();await pending;
  assert.equal(f.snapshot().direction,'S');c.hide();await flush();c.show();await flush();assert.equal(c.armed,false);assert.equal(f.snapshot().remote.armed,false);
  assert.ok(f.writes.every((x,i,a)=>!i||x.seq>a[i-1].seq));c.disconnect();
});
test('late arm response after hide cannot restore permission',async()=>{const f=fake(),c=f.client;await c.connect('http://127.0.0.1:8765','offline-secret-123');
  f.delay();const arm=c.action('arm');await flush();c.hide();f.resolve();await arm;await flush();assert.equal(c.armed,false);assert.equal(f.snapshot().remote.armed,false);c.show();await flush();assert.equal(c.armed,false);c.disconnect();
});
test('stale queued commands expire before HTTP send',async()=>{const f=fake(),c=f.client;await c.connect('http://127.0.0.1:8765','offline-secret-123');
  let unblock;c.tail=new Promise(r=>unblock=r);const a=c.action('manual.move',{direction:'F'});f.advance(450);unblock();await assert.rejects(a,/过期/);assert.ok(!f.writes.some(x=>x.action==='manual.move'));c.disconnect();
});
test('native page and lifecycle bindings resolve',()=>{const root=path.join(__dirname,'../miniprogram');let page,app;
  const sandbox={require:p=>require(path.resolve(root,'pages/index',p)),Page:p=>page=p,App:a=>app=a,console};
  vm.runInNewContext(fs.readFileSync(path.join(root,'pages/index/index.js'),'utf8'),sandbox);
  vm.runInNewContext(fs.readFileSync(path.join(root,'app.js'),'utf8'),sandbox);
  const wxml=fs.readFileSync(path.join(root,'pages/index/index.wxml'),'utf8');
  for(const m of wxml.matchAll(/wx:(?:if|elif)="([^"]+)"/g))assert.ok(m[1].startsWith('{{')&&m[1].endsWith('}}'),'WXML condition must be bound: '+m[1]);
  const bound=[...wxml.matchAll(/bind(?:tap|touchstart|touchend|touchcancel|input|change)="([^"]+)"/g)].map(x=>x[1]);
  for(const method of bound)assert.equal(typeof page[method],'function',method);
  assert.equal(typeof app.onHide,'function');assert.equal(typeof page.onHide,'function');assert.equal(typeof page.onUnload,'function');
  for(const name of ['app.json','sitemap.json','pages/index/index.json'])JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
  JSON.parse(fs.readFileSync(path.join(root,'../project.config.json'),'utf8'));
});
(async()=>{let failed=0;for(const [name,fn]of tests){try{await fn();console.log('PASS '+name);}catch(e){failed++;console.error('FAIL '+name,e);}finally{clients.forEach(c=>c.disconnect());}}
 console.log(JSON.stringify({tests:tests.length,passed:tests.length-failed,failed}));process.exitCode=failed?1:0;})();
