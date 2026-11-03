const {GatewayClient}=require('../../lib/client');
const {DemoClient}=require('../../lib/demo');
const empty={sensors:{},wheels:{targets:[0,0,0,0],speeds:[0,0,0,0],duties:[0,0,0,0]},map:{current:[],goal:[],occupied:[],route:[]},tasks:{},vision:{detections:[]},remote:{events:[]}};
Page({
  data:{tab:'drive',tabs:[{id:'drive',name:'驾驶',mark:'01'},{id:'map',name:'地图',mark:'02'},{id:'vision',name:'视觉',mark:'03'},{id:'connect',name:'连接',mark:'04'}],
    demo:true,connected:false,armed:false,state:empty,error:'',base:'http://192.168.137.1:8765',token:'',
    digit:7,digits:['数字 0','数字 1','数字 2','数字 3','数字 4','数字 5','数字 6','数字 7','数字 8','数字 9'],arrival:'200',
    poseX:'17',poseY:'2',setback:'0',p:'4',i:'1',d:'0',advanced:false,speed:12,selected:null,
    wheels:[],distance:'—',yaw:'—',taskText:'等待连接',frame:'',frameMessage:'',mapWidth:300,held:'S'},
  onLoad(){this.openDemo();},
  onReady(){this.measureMap();},
  onShow(){if(this.client)this.client.show();},
  onHide(){this.cancelTouch();if(this.client)this.client.hide();},
  onUnload(){this.cancelTouch();if(this.client)this.client.disconnect();getApp().controller=null;},
  update(s,meta){
    const patch={connected:meta.connected,armed:meta.armed,error:meta.error||''};
    if(s){patch.state=s;patch.distance=s.sensors.distance_mm==null?'—':s.sensors.distance_mm;
      patch.yaw=s.sensors.yaw_deg==null?'—':Number(s.sensors.yaw_deg).toFixed(1);
      patch.taskText=s.tasks.status||s.detail||'待机';
      patch.wheels=[0,1,2,3].map(n=>({name:'M'+(n+1),target:s.wheels.targets[n],actual:s.wheels.speeds[n],duty:s.wheels.duties[n]}));}
    this.setData(patch);if(this.data.tab==='map')this.drawMap();
  },
  replace(client){if(this.client)this.client.disconnect();this.client=client;getApp().controller=client;},
  openDemo(){const client=new DemoClient((s,m)=>this.update(s,m));this.replace(client);this.setData({demo:true,frame:'',frameMessage:''});client.connect();},
  switchDemo(e){this.cancelTouch();if(this.client)this.client.disconnect();
    this.setData({demo:e.detail.value,connected:false,armed:false,state:empty,error:'',frame:'',held:'S'});
    if(e.detail.value)this.openDemo();else this.setData({tab:'connect',taskText:'等待连接电脑网关'});},
  input(e){const key=e.currentTarget.dataset.key;if(['base','token','arrival','poseX','poseY','setback','p','i','d'].includes(key))this.setData({[key]:e.detail.value});},
  async connect(){try{
    const c=new GatewayClient(opts=>new Promise((resolve,reject)=>wx.request(Object.assign({},opts,{success:resolve,fail:err=>reject(new Error(err.errMsg||'网络请求失败'))}))),
      (s,m)=>this.update(s,m));this.replace(c);await c.connect(this.data.base,this.data.token);wx.setStorageSync('jingjue_gateway',this.data.base);
  }catch(e){this.alert(e.message);}},
  disconnect(){this.cancelTouch();if(this.client)this.client.disconnect();this.setData({connected:false,armed:false});},
  async send(action,payload){if(!this.client)return;try{return await this.client.action(action,payload);}catch(e){this.alert(e.message);}},
  arm(){this.send('arm');},
  stop(){this.cancelTouch();if(this.client)this.client.panic('手机停止S');this.setData({held:'S'});},
  touchStart(e){if(!this.data.connected||!this.data.armed)return;const direction=e.currentTarget.dataset.dir;
    this.setData({held:direction});this.send('manual.move',{direction});},
  touchEnd(){if(this.data.held==='S')return;this.cancelTouch();if(this.client)this.client.release().catch(e=>this.alert(e.message));},
  cancelTouch(){this.setData({held:'S'});},
  speed(e){const value=Number(e.currentTarget.dataset.value);this.setData({speed:value});this.send('manual.speed',{value});},
  turn(e){this.send('turn.start',{direction:e.currentTarget.dataset.dir});},
  avoid(e){this.send(e.currentTarget.dataset.enabled==='true'?'avoid.enable':'avoid.disable');},
  selectTab(e){if(this.data.held!=='S')this.touchEnd();this.setData({tab:e.currentTarget.dataset.tab});if(this.data.tab==='map')this.measureMap();},
  measureMap(){wx.createSelectorQuery().in(this).select('#map').boundingClientRect(rect=>{if(rect){this.mapRect=rect;this.setData({mapWidth:rect.width});this.drawMap();}}).exec();},
  drawMap(){const m=this.data.state.map;if(!m||!m.occupied)return;const w=this.data.mapWidth,cell=w/20,c=wx.createCanvasContext('map',this),blocked=new Set(m.occupied),measured=new Set(m.measured||[]);
    c.setFillStyle('#123044');c.fillRect(0,0,w,w);
    for(let y=0;y<20;y++)for(let x=0;x<20;x++){const idx=y*20+x;c.setFillStyle(measured.has(idx)?'#f8c65c':blocked.has(idx)?'#444853':'#123044');c.fillRect(x*cell,(19-y)*cell,cell-1,cell-1);}
    if(m.route&&m.route.length){c.setStrokeStyle('#41cbe6');c.setLineWidth(Math.max(2,cell*.2));c.beginPath();m.route.forEach((p,n)=>{const x=(p[0]+.5)*cell,y=(19.5-p[1])*cell;if(n)c.lineTo(x,y);else c.moveTo(x,y);});c.stroke();}
    const marker=(p,color,text)=>{if(!p)return;const x=(p[0]+.5)*cell,y=(19.5-p[1])*cell;c.setFillStyle(color);c.beginPath();c.arc(x,y,cell*.65,0,Math.PI*2);c.fill();c.setFillStyle('#071722');c.setFontSize(cell*.8);c.setTextAlign('center');c.setTextBaseline('middle');c.fillText(text,x,y);};
    marker(m.goal,'#f5bf56','终');marker(m.current,'#46e3bb','车');
    if(this.data.selected){const p=this.data.selected;c.setStrokeStyle('#ffffff');c.setLineWidth(2);c.strokeRect(p[0]*cell,(19-p[1])*cell,cell,cell);}
    c.draw();
  },
  mapTap(e){if(!this.mapRect)return;const touch=e.changedTouches[0],r=this.mapRect;
    const x=Math.floor((touch.x===undefined?touch.clientX-r.left:touch.x)/r.width*20),y=19-Math.floor((touch.y===undefined?touch.clientY-r.top:touch.y)/r.width*20);
    if(x<0||x>19||y<0||y>19)return;this.setData({selected:[x,y]});this.send('nav.preview',{goal:[x,y]});},
  pose(){const position=[Number(this.data.poseX),Number(this.data.poseY)];
    if(position.some(v=>!Number.isInteger(v)||v<0||v>19))return this.alert('坐标应为0至19的整数');
    wx.showModal({title:'确认实际车位',content:'请确认车已停车，实际位于 ('+position.join(', ')+')，车头朝地图 +Y。',success:r=>{if(r.confirm)this.send('nav.pose',{position});}});},
  navigate(){const setback=Number(this.data.setback);if(!Number.isInteger(setback)||setback< -30||setback>50)return this.alert('探头偏移为-30至50mm整数');this.send('nav.start',{setback_mm:setback});},
  digit(e){this.setData({digit:Number(e.detail.value)});},
  lock(e){const row=e.currentTarget.dataset.row;const match=/^a4_digit_([0-9])$/.exec(row.class_name||'');if(!match)return this.alert('请选择当前数字目标');this.setData({digit:Number(match[1])});this.send('vision.lock',{digit:Number(match[1]),detection_id:row.detection_id,arrival_mm:Number(this.data.arrival)});},
  vision(e){const arrival=Number(this.data.arrival);if(!Number.isInteger(arrival)||arrival<180||arrival>1000)return this.alert('到达距离为180至1000mm');this.send(e.currentTarget.dataset.action,{digit:this.data.digit,arrival_mm:arrival});},
  task(e){this.send(e.currentTarget.dataset.action);},
  async frame(){if(this.data.demo)return;try{const data=await this.client.frame();this.setData({frame:'data:image/jpeg;base64,'+wx.arrayBufferToBase64(data),frameMessage:'电脑网关转发的相机快照'});}catch(e){this.setData({frameMessage:e.message});}},
  toggleAdvanced(){this.setData({advanced:!this.data.advanced});},
  pid(){this.send('pid.set',{p:Number(this.data.p),i:Number(this.data.i),d:Number(this.data.d)});},
  alert(message){wx.showToast({title:message,icon:'none',duration:2600});}
});
