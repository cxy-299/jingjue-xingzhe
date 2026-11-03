const mapData=require('./map-data');
const clone=x=>JSON.parse(JSON.stringify(x));
function route(occupied,start,goal){
  const blocked=new Set(occupied), key=p=>p[1]*20+p[0];
  if(!Array.isArray(start)||!Array.isArray(goal)||start.length!==2||goal.length!==2||[...start,...goal].some(v=>!Number.isInteger(v)||v<0||v>19)||blocked.has(key(goal))||blocked.has(key(start)))return [];
  const queue=[start], parents=new Map([[key(start),null]]);
  for(let n=0;n<queue.length;n++){
    const p=queue[n];if(key(p)===key(goal)){
      const out=[];let q=p;while(q){out.push(q);q=parents.get(key(q));}return out.reverse();
    }
    [[0,1],[-1,0],[0,-1],[1,0]].forEach(([dx,dy])=>{const q=[p[0]+dx,p[1]+dy],k=key(q);
      if(q.every(v=>v>=0&&v<20)&&!blocked.has(k)&&!parents.has(k)){parents.set(k,p);queue.push(q);}});
  }return [];
}
class DemoClient {
  constructor(changed){this.changed=changed;this.active=false;this.armed=false;this.visible=true;this.step=0;this.ticks=0;this.state=null;}
  connect(){
    this.disconnect();this.active=true;this.visible=true;
    this.state={demo:true,name:'境觉行者',connected:true,desktop_enabled:true,firmware:'R20 / K14 · 演示',mode:'manual',direction:'S',
      sensors:{distance_mm:854,yaw_deg:0,tof_valid:true,imu_valid:true,fault:0},wheels:{targets:[0,0,0,0],speeds:[0,0,0,0],duties:[0,0,0,0]},
      map:{size:20,occupied:mapData.occupied,current:[17,2],start:[17,2],goal:[17,17],route:[],measured:[],pose_confirmed:true},
      tasks:{active:false,status:'演示待机',mission_id:101,digit:7,arrival_mm:200},
      vision:{online:true,digit:7,confirmed:true,fps:20,detector_ms:16.6,model:'Printed Digit v4 · 演示',message:'模拟数字7，未连接相机',detections:[{detection_id:1,class_name:'a4_digit_7',confidence:0.96}]},
      remote:{armed:false,reason:'演示就绪，请启用本次控制',events:[]},detail:'内置模拟数据，不打开串口、不连接机器人'};
    this.timer=setInterval(()=>this.tick(),100);this.emit();return Promise.resolve();
  }
  emit(){if(this.state){this.state.remote.armed=this.armed;this.changed(clone(this.state),{connected:this.active,armed:this.armed,error:''});}}
  async action(name,p={}){
    if(!this.active||!this.visible)throw new Error('演示会话已暂停');const s=this.state;
    if(name==='arm'){this.armed=true;s.remote.reason='本次演示控制已启用';}
    else if(name==='heartbeat'){}
    else if(name==='stop'){this.panic();return;}
    else {
      if(!['nav.preview','nav.pose','vision.prepare','vision.search','vision.lock','task.read'].includes(name)&&!this.armed)throw new Error('先启用本次控制');
      if(name==='manual.move'){if(!['F','B','L','R'].includes(p.direction))throw new Error('方向无效');s.direction=p.direction;s.mode='manual';}
      else if(name==='manual.release'){s.direction='S';s.tasks.active=false;}
      else if(name==='manual.speed'){if(![12,16,20].includes(p.value))throw new Error('档位无效');this.speed=p.value;s.direction='S';}
      else if(name==='nav.preview'){const r=route(s.map.occupied,s.map.current,p.goal);if(!r.length)throw new Error('终点不可达或位于安全区');s.map.goal=p.goal;s.map.route=r;}
      else if(name==='nav.pose'){if(!route(s.map.occupied,p.position,p.position).length)throw new Error('当前位置无效');this.panic();s.map.current=p.position;s.map.route=[];}
      else if(name==='nav.start'){if(!s.map.route.length)throw new Error('先点击地图预览终点');s.mode='autonav';s.tasks.active=true;s.tasks.status='演示逐格导航';this.step=0;}
      else if(name==='vision.prepare'||name==='vision.search'||name==='vision.lock'){if(!Number.isInteger(p.digit)||p.digit<0||p.digit>9)throw new Error('数字范围0至9');this.panic();s.vision.digit=p.digit;s.vision.detections=[{detection_id:1,class_name:'a4_digit_'+p.digit,confidence:0.96}];s.tasks.digit=p.digit;s.tasks.arrival_mm=p.arrival_mm||200;s.tasks.mission_id++;s.tasks.status=name==='vision.lock'?'具体数字目标已锁定 · 演示':'任务已准备 · 演示';}
      else if(name==='task.read'){this.panic();s.tasks.status='已读取演示任务，等待明确启动';}
      else if(name==='task.start'){s.mode='mission';s.tasks.active=true;s.tasks.status='两阶段接近 · 演示';}
      else if(name==='follow.start'||name==='follow.digit'){s.mode='follow';s.tasks.active=true;s.tasks.status='ToF保持200mm · 演示';}
      else if(name==='turn.start'){s.sensors.yaw_deg+=(p.direction==='left'?90:-90);s.tasks.status='转角完成 · 演示';}
      else if(name==='avoid.enable'||name==='avoid.disable')s.detail='前进避障'+(name.endsWith('enable')?'开启':'关闭')+' · 演示';
      else if(name==='pid.set'){this.panic();s.detail='演示PID已设置';}
      else throw new Error('未知演示指令');
    }this.emit();return {accepted:true,result:{message:'演示操作完成'},state:clone(s)};
  }
  tick(){if(!this.visible||!this.state)return;const s=this.state;this.ticks++;
    if(this.armed&&s.tasks.active&&s.mode==='autonav'&&this.ticks%5===0){this.step++;if(this.step<s.map.route.length)s.map.current=s.map.route[this.step];else{s.tasks.active=false;s.tasks.status='到达演示终点';}}
    const v=this.armed&&s.direction!=='S'?(this.speed||12):0;
    s.wheels={targets:[v,v,v,v],speeds:[v,v,v,v],duties:[v*30,v*30,v*30,v*30]};this.emit();
  }
  release(){return this.action('manual.release');}
  panic(reason){this.armed=false;if(this.state){this.state.direction='S';this.state.tasks.active=false;this.state.tasks.status='已停止 · 演示';this.state.remote.reason=reason||'已停止，需重新启用';this.emit();}}
  hide(){this.visible=false;this.panic('页面已离开，需重新启用');}
  show(){this.visible=true;this.emit();}
  disconnect(){if(this.timer)clearInterval(this.timer);this.timer=null;this.panic();this.active=false;this.emit();}
}
module.exports={DemoClient,route};
