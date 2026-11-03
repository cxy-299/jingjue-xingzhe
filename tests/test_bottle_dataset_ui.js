// Execute actual portal script; verify scaled box coordinates and explicit labels.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync('web/bottle_dataset.html','utf8');
const nodes={};
const element=()=>({value:'',textContent:'',disabled:false,children:[],listeners:{},
 appendChild(c){this.children.push(c);},replaceChildren(){this.children=[];},
 addEventListener(k,f){this.listeners[k]=f;},setPointerCapture(){},
 getBoundingClientRect(){return {left:10,top:20,width:320,height:240};}});
for(const id of html.matchAll(/id="([^"]+)"/g))nodes[id[1]]=element();
nodes.canvas.getContext=()=>({clearRect(){},drawImage(){},strokeRect(){}});
const rows=[{id:'s/00000.jpg',session:'s',split:'train',scene:'partial_near',annotation:null},
 {id:'s/00001.jpg',session:'s',split:'train',scene:'partial_near',annotation:null}];
const requests=[];
const context={console,Date,Math,Number,String,encodeURIComponent,setInterval(){},
 document:{getElementById:id=>nodes[id],createElement:element},
 Image:class{constructor(){this.naturalWidth=640;this.naturalHeight=480;}set src(x){this.onload();}},
 fetch:async(url,opts)=>{if(!opts)return {ok:true,json:async()=>({items:rows,collection:{running:false,count:0,error:''}})};
 const body=JSON.parse(opts.body);requests.push({url,body});
 if(url==='/api/annotation')rows.find(x=>x.id===body.id).annotation={boxes:body.boxes,negative:body.negative};
 return {ok:true,json:async()=>({})};}};
vm.createContext(context);vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],context);
const tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 await tick();
 nodes.canvas.listeners.pointerdown({clientX:50,clientY:70,pointerId:1});
 nodes.canvas.listeners.pointermove({clientX:130,clientY:170});
 nodes.canvas.listeners.pointerup();
 nodes.next.onclick();assert(nodes.notice.textContent.includes('未保存'));
 await nodes.save.onclick();await tick();
 assert.deepEqual(requests[0],{url:'/api/annotation',body:{id:'s/00000.jpg',boxes:[[80,100,240,300]],negative:false}});
 await nodes.negative.onclick();await tick();
 assert.equal(requests[1].body.id,'s/00001.jpg');assert.equal(requests[1].body.negative,true);
 assert(!requests.some(x=>/mission|task\/mode|motion/.test(x.url)));
 console.log('BOTTLE_DATASET_UI_COORDINATES_REVIEW_NO_MOTION_PASS');
})().catch(e=>{console.error(e);process.exit(1);});
