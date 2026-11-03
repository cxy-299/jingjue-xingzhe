// Execute the deployed page's script and exercise real target selection POSTs.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync('web/dashboard.html','utf8');
const nodes={};
const element=()=>({listeners:{},children:[],value:'bottle',textContent:'',hidden:false,
  classList:{toggle(){},remove(){}},addEventListener(k,f){this.listeners[k]=f;},
  appendChild(c){this.children.push(c);},getBoundingClientRect(){return {left:0,top:0,width:640,height:480};},
  querySelector(){return this.body||(this.body=element());}});
for(const id of html.matchAll(/id="([^"]+)"/g)) nodes[id[1]]=element();
const requests=[];
let failNext=false;
const context={document:{hidden:false,getElementById(id){assert(nodes[id],`missing ${id}`);return nodes[id];},
  createElement:element,addEventListener(){}},location:{protocol:'file:'},
  setTimeout(){return 1;},clearTimeout(){},setInterval(){},Date,console,
  fetch:async(url,opts)=>{requests.push({url,...JSON.parse(opts.body)});
    const failed=failNext;failNext=false;
    return {ok:!failed,json:async()=>failed?{error:'所选目标已离开'}:{}};}};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
assert(!nodes.navMap);
const person={detection_id:'d1',class_name:'person',confidence:.95,cx:150,cy:170,bbox:[100,100,200,240],frame_width:640,frame_height:480};
const bottle={...person,detection_id:'d2',class_name:'bottle',cx:350,bbox:[300,100,400,240]};
const render=rows=>vm.runInContext(`renderRows(${JSON.stringify(rows)})`,context);
(async()=>{
  render([person,bottle]);
  nodes.stream.listeners.click({clientX:150,clientY:170});
  assert.equal(nodes.taskClass.value,'person');
  // Polling can reorder detections and move their boxes before human confirmation.
  render([bottle,{...person,cx:155}]);
  assert(!nodes.taskLockButton.disabled);
  assert(nodes.chosenTarget.textContent.includes('持续可见'));
  const first=nodes.taskLockButton.listeners.click();
  assert(nodes.taskLockButton.disabled);
  await nodes.taskLockButton.listeners.click(); // double click is not a second lock
  await first;
  assert.equal(requests.length,1);
  assert.equal(requests[0].detection_id,'d1');
  assert.equal(requests[0].target_class,'person');
  assert.equal(requests[0].mode,'search');
  await nodes.taskFollow.listeners.click();assert.equal(requests[1].mode,'follow');
  await nodes.taskObserve.listeners.click();assert.equal(requests[2].mode,'observe');
  assert(nodes.taskLockButton.disabled);
  // Explicitly switch from person to bottle, then confirm after many refreshes.
  nodes.stream.listeners.click({clientX:350,clientY:170});
  for(let i=0;i<40;i++) render([person,{...bottle,cx:350+i%2}]);
  await nodes.taskLockButton.listeners.click();
  assert.equal(requests[3].target_class,'bottle');
  assert.equal(requests[3].detection_id,'d2');
  render([person]);
  assert(nodes.taskLockButton.disabled);
  await nodes.taskLockButton.listeners.click();
  assert.equal(requests.length,4); // vanished selection is not posted
  assert(nodes.taskAction.textContent.includes('离开'));
  render([person,bottle]);nodes.stream.listeners.click({clientX:350,clientY:170});
  failNext=true;await nodes.taskLockButton.listeners.click();
  assert(nodes.taskAction.textContent.includes('操作失败'));
  render([bottle,person]);
  assert(nodes.taskAction.textContent.includes('操作失败')); // polling cannot hide error
  console.log('TASK56_STABLE_SELECTION_REAPPEARANCE_UI_PASS');
})().catch(error=>{console.error(error);process.exitCode=1;});
