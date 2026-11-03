/* DOM layout adapter only. Never connects to PC, Pi, or hardware. */
const app={},cache={};let page,scheduled=false;
function load(id){if(cache[id])return cache[id].exports;const m={exports:{}};cache[id]=m;
  const relative=p=>{let parts=id.split('/');parts.pop();for(const part of p.split('/')){if(part==='..')parts.pop();else if(part!=='.')parts.push(part);}return parts.join('/');};
  new Function('require','module','exports',MODULES[id])(p=>load(relative(p)),m,m.exports);return m.exports;}
window.getApp=()=>app;
window.Page=definition=>{page=definition;page.data=JSON.parse(JSON.stringify(page.data));page.setData=function(patch,done){Object.assign(this.data,patch);if(!scheduled){scheduled=true;requestAnimationFrame(()=>{scheduled=false;render();if(done)done();});}};};
const toast=text=>{const el=document.querySelector('#toast');el.textContent=text;el.hidden=false;setTimeout(()=>el.hidden=true,2200);};
window.wx={showToast:o=>toast(o.title),showModal:o=>o.success({confirm:confirm(o.content)}),setStorageSync:()=>{},
  request:o=>o.fail({errMsg:'布局预览只提供内置演示，请在微信开发者工具中使用电脑网关'}),
  createSelectorQuery:()=>{let selector,callback;const q={in:()=>q,select:s=>(selector=s,q),boundingClientRect:f=>(callback=f,q),exec:()=>setTimeout(()=>{const e=document.querySelector(selector);callback(e?e.getBoundingClientRect():null);},30)};return q;},
  createCanvasContext:id=>{const el=document.querySelector(`[data-canvas-id="${id}"]`);if(!el)return new Proxy({},{get:()=>()=>{}});
    const width=el.getBoundingClientRect().width;if(el.width!==Math.round(width)){el.width=Math.round(width);el.height=Math.round(width);}
    const c=el.getContext('2d');const props={setFillStyle:'fillStyle',setStrokeStyle:'strokeStyle',setLineWidth:'lineWidth',setFontSize:'font',setTextAlign:'textAlign',setTextBaseline:'textBaseline'};
    return new Proxy({},{get:(_,method)=>method==='draw'?()=>{}:props[method]?value=>{c[props[method]]=method==='setFontSize'?`${value}px sans-serif`:value;}:typeof c[method]==='function'?c[method].bind(c):c[method]});}
};
const evaluate=(s,scope)=>{try{return new Function('scope','with(scope){return ('+s+');}')(scope);}catch(e){return undefined;}};
function value(s,scope){const full=/^{{((?:(?!}})[\s\S])*)}}$/.exec(s);if(full)return evaluate(full[1],scope);return s.replace(/{{([\s\S]*?)}}/g,(_,expr)=>{const v=evaluate(expr,scope);return v==null?'':String(v);});}
const xml=new DOMParser().parseFromString('<root>'+WXML+'</root>','text/xml');
if(xml.querySelector('parsererror'))throw new Error(xml.querySelector('parsererror').textContent);
function children(parent,scope,target){let branch=false;
  for(const node of parent.childNodes){if(node.nodeType===3){target.appendChild(document.createTextNode(value(node.textContent,scope)));continue;}if(node.nodeType!==1)continue;
    if(node.hasAttribute('wx-if')){branch=!!value(node.getAttribute('wx-if'),scope);if(!branch)continue;}
    else if(node.hasAttribute('wx-elif')){if(branch)continue;branch=!!value(node.getAttribute('wx-elif'),scope);if(!branch)continue;}
    else if(node.hasAttribute('wx-else')){if(branch)continue;branch=true;}else branch=false;
    if(node.hasAttribute('wx-for')){const rows=value(node.getAttribute('wx-for'),scope)||[];rows.forEach((item,index)=>element(node,Object.assign({},scope,{item,index}),target));}
    else element(node,scope,target);
  }
}
function element(node,scope,target){const tag=node.tagName;
  if(tag==='block'){children(node,scope,target);return;}
  const htmlTag={view:'div',text:'span',image:'img',picker:'select',switch:'input',input:'input',canvas:'canvas',button:'button'}[tag]||'div';
  const el=document.createElement(htmlTag),dataset={};
  for(const a of node.attributes){if(a.name.startsWith('wx-')||a.name.startsWith('bind'))continue;const v=value(a.value,scope);
    if(a.name.startsWith('data-')){dataset[a.name.slice(5)]=v;el.setAttribute(a.name,typeof v==='object'?JSON.stringify(v):v);}
    else if(a.name==='canvas-id')el.setAttribute('data-canvas-id',v);
    else if(a.name==='disabled')el.disabled=!!v;
    else if(a.name==='password')el.type='password';
    else if(a.name==='value')el.value=v;
    else if(a.name==='checked')el.checked=!!v;
    else el.setAttribute(a.name,v==null?'':v);
  }
  if(tag==='switch')el.type='checkbox';
  if(tag==='picker'){const rows=value(node.getAttribute('range'),scope)||[];rows.forEach((text,i)=>{const opt=document.createElement('option');opt.value=i;opt.textContent=text;el.appendChild(opt);});el.value=value(node.getAttribute('value'),scope);}
  else if(tag!=='input'&&tag!=='switch')children(node,scope,el);
  const events={bindtap:'click',bindinput:'input',bindchange:'change',bindtouchstart:'pointerdown',bindtouchend:'pointerup',bindtouchcancel:'pointercancel'};
  for(const [binding,eventName] of Object.entries(events)){if(!node.hasAttribute(binding))continue;el.addEventListener(eventName,event=>{
    if(el.disabled)return;const method=node.getAttribute(binding),r=el.getBoundingClientRect();
    if(binding==='bindtouchstart')el.setPointerCapture(event.pointerId);
    const detail={value:tag==='switch'?el.checked:el.value};
    page[method]({currentTarget:{dataset},detail,changedTouches:[{x:event.clientX-r.left,y:event.clientY-r.top}],touches:[]});
  });}
  target.appendChild(el);
}
function render(){const root=document.querySelector('#app'),focus=document.activeElement,key=focus&&focus.getAttribute('data-key');root.replaceChildren();children(xml.documentElement,page.data,root);
  if(key){const input=root.querySelector(`[data-key="${key}"]`);if(input)input.focus();}
  if(page.data.tab==='map')page.drawMap();
}
load('pages/index/index');app.controller=null;window.previewPage=page;page.onLoad();render();page.onReady();
document.addEventListener('pointerup',()=>{if(page.data.held!=='S')page.touchEnd();});
document.addEventListener('pointercancel',()=>{if(page.data.held!=='S')page.touchEnd();});
document.addEventListener('visibilitychange',()=>document.hidden?page.onHide():page.onShow());
