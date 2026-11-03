/* No serial access. Requests are authenticated and mutations have monotonic IDs. */
class GatewayClient {
  constructor(request, changed, now) {
    this.request = request; this.changed = changed || (() => {}); this.now = now || Date.now;
    this.seq = 0; this.epoch = 0; this.session = null; this.active = false; this.visible = true;
    this.armed = false; this.wantArmed = false; this.tail = Promise.resolve(); this.polling = false; this.beating = false;
    this.state = null; this.offset = 0; this.error = '';
  }
  emit() { this.changed(this.state, { connected:this.active, armed:this.armed, error:this.error }); }
  configure(base, token) {
    const match = /^(http):\/\/(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?\/?$/.exec(base.trim());
    if (!match) throw new Error('请输入电脑局域网 IPv4 地址，例如 http://192.168.1.8:8765');
    const p = match[2].split('.').map(Number), port = Number(match[3] || 80);
    const privateIP = p[0]===10 || (p[0]===172 && p[1]>=16 && p[1]<=31) || (p[0]===192 && p[1]===168) || p[0]===127;
    if (p.some(v => v>255) || !privateIP || port<1 || port>65535) throw new Error('仅支持同网段私有 IPv4 或本机演示地址');
    if (!token || token.trim().length<12) throw new Error('请填写电脑网关显示的本次配对码');
    this.base = base.trim().replace(/\/$/, ''); this.token = token.trim();
  }
  api(path, data, extra) {
    return this.request(Object.assign({url:this.base+path,method:data===undefined?'GET':'POST',data,
      header:{Authorization:'Bearer '+this.token,'Content-Type':'application/json'},timeout:650},extra||{}))
      .then(r => { if (r.statusCode<200 || r.statusCode>=300) throw new Error(r.data && r.data.error || '网关拒绝请求'); return r.data; });
  }
  async connect(base, token) {
    this.disconnect(); this.configure(base,token); this.visible=true;
    const epoch=++this.epoch, sent=this.now();
    const result=await this.api('/v1/session',{label:'微信驾驶台'});
    if(epoch!==this.epoch || !this.visible) {
      // A delayed session response must not survive app background/disconnect.
      this.api('/v1/action',{session_id:result.session_id,seq:1,deadline_ms:result.server_time_ms+500,action:'stop',payload:{}}).catch(()=>{});
      return;
    }
    this.offset=result.server_time_ms-(sent+this.now())/2;
    this.session=result.session_id; this.seq=0; this.active=true; this.error=''; this.armed=false;
    await this.poll(); this.timer=setInterval(()=>{this.heartbeat();this.poll();},100); this.emit();
  }
  envelope(action,payload) { return {session_id:this.session,seq:++this.seq,deadline_ms:Math.floor(this.now()+this.offset+500),action,payload:payload||{}}; }
  ingest(s) { if(s) { this.state=s; this.armed=this.wantArmed && !!(s.remote && s.remote.armed); } this.emit(); }
  action(action,payload) {
    const epoch=this.epoch, queued=this.now();
    const run=async()=>{
      if (!this.active || !this.visible || epoch!==this.epoch) throw new Error('会话已暂停，请重新连接或启用');
      if(this.now()-queued>400) throw new Error('操作已过期，请重新点击');
      if(action==='arm')this.wantArmed=true;
      const result=await this.api('/v1/action',this.envelope(action,payload));
      if(epoch===this.epoch && this.visible) this.ingest(result.state);
      return result;
    };
    const promise=this.tail.then(run);
    this.tail=promise.catch(()=>{});
    return promise.catch(e=>{if(epoch===this.epoch){this.error=e.message;this.panic('请求失败，已撤销许可');}throw e;});
  }
  sendImmediate(action) {
    if(!this.session || !this.base) return Promise.resolve();
    return this.api('/v1/action',this.envelope(action)).catch(()=>{});
  }
  release() {
    // Drop queued presses. Higher sequence makes an in-flight old press unusable.
    ++this.epoch; this.tail=Promise.resolve();
    return this.sendImmediate('manual.release').then(r=>{if(r && this.visible)this.ingest(r.state);});
  }
  panic(reason) { ++this.epoch; this.tail=Promise.resolve(); this.armed=false; this.wantArmed=false; this.error=reason||''; this.sendImmediate('stop'); this.emit(); }
  heartbeat() {
    if(!this.active || !this.visible || !this.armed || this.beating)return;
    this.beating=true; this.action('heartbeat').catch(()=>{}).finally(()=>{this.beating=false;});
  }
  async poll() {
    if(!this.active || !this.visible || this.polling)return;
    this.polling=true; const epoch=this.epoch;
    try {const s=await this.api('/v1/state'); if(epoch===this.epoch && this.visible)this.ingest(s);}
    catch(e){if(epoch===this.epoch){this.panic('连接中断，请重新连接');this.active=false;this.emit();}}
    finally{this.polling=false;}
  }
  async frame() {return this.api('/v1/vision/frame',undefined,{responseType:'arraybuffer',timeout:900});}
  hide(){this.visible=false;this.panic('页面已离开，需重新启用');}
  show(){this.visible=true;if(this.active)this.poll();}
  disconnect(){if(this.timer)clearInterval(this.timer);this.timer=null;this.panic('连接已断开');this.active=false;this.session=null;this.emit();}
}
module.exports={GatewayClient};
