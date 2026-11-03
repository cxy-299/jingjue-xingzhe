"""Actual full-system mapped approach PLUS its hoisted parent arithmetic cone.

The synthesized hierarchy exports LUT intermediates, not the RTL ports. Follow
their real primitive drivers back to target/yaw/enable boundaries. Never tie an
unknown internal node to a guessed value or force a register.
"""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board';DEST=ROOT/'tmp/sin12_r9_mapped_approach'

def main():
    assert (OUT/'sin12_hdmi_r9_build_exit.txt').read_text().strip()=='0'
    manifest=json.loads((OUT/'sin12_hdmi_r9_build_sources.json').read_text())
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
    net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg';text=net.read_text()
    child=re.search(r'module heading_approach_control \([\s\S]*?endmodule',text)[0]
    parent=re.search(r'module imu_turn_guard \([\s\S]*?endmodule',text)[0]
    assert not re.search(r'\bMULT\w*\s',child)
    for reg in ['previous_yaw','yaw_step','command_q','speed_q','window_age']:
        assert re.search(r'DFF\w*\s+'+reg+'_',child),reg
    assert re.search(r'module heading_approach_control_0 \(',text), 'Missing separate nav specialization'
    declarations=dict((m[2].strip(),m[1] or '') for m in re.finditer(r'^\s*(?:input|output|wire)\s+(\[[^\]]+\])?\s*(\\\S+\s*|\w+)\s*;',parent,re.M))
    def bits(expr):
        expr=expr.strip()
        if expr in ('VCC','GND'):return [expr]
        if "'" in expr:return []
        m=re.fullmatch(r'(\\\S+\s*|\w+)(?:\[(\d+)(?::(\d+))?\])?',expr)
        assert m,('Inspect non-net expression',expr)
        base=m[1].strip()
        if m[2] is not None:
            hi=int(m[2]);lo=int(m[3] or m[2]);return [f'{base}[{i}]' for i in range(min(lo,hi),max(lo,hi)+1)]
        width=declarations.get(base,'')
        return bits(base+width) if width else [base]
    instances=[];drivers={}
    for m in re.finditer(r'^\s*(\w+)\s+(\\\S+\s*|\w+)\s*\(([\s\S]*?)\);',parent,re.M):
        kind,name,body=m.groups();name=name.strip()
        if kind=='module':continue
        ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',body))
        outpins={'F'} if kind.startswith('LUT') else {'SUM','COUT'} if kind=='ALU' else {'Q'} if kind.startswith('DFF') else {'V'} if kind=='VCC' else {'G'} if kind=='GND' else set()
        row=dict(kind=kind,name=name,ports=ports,code=m[0],outpins=outpins)
        index=len(instances);instances.append(row)
        for pin in outpins & ports.keys():
            for bit in bits(ports[pin]):drivers[bit]=index
    actual=re.search(r'heading_approach_control\s+\\g_approach.u_approach\s*\(([\s\S]*?)\);',parent)[0]
    conns=dict(re.findall(r'\.(\w+)\(([^)]*)\)',actual))
    child_outputs=re.findall(r'^output\s+(?:\[[^\]]+\]\s*)?(\w+)\s*;',child,re.M)
    boundaries=['clk_50m_i_d','n177_5','sample_tick_d','inverted','target_pending','turn_active','turn_yaw','speed','turn_target_yaw']
    available={b for name in boundaries for b in bits(name)}
    available.update(b for pin in child_outputs for b in bits(conns[pin]))
    selected=set()
    def resolve(bit):
        if bit in available:return
        assert bit in drivers,('Unresolved actual parent input',bit)
        i=drivers[bit]
        if i in selected:return
        row=instances[i]
        assert row['kind'].startswith('LUT') or row['kind'] in ('ALU','VCC','GND'),('Unexpected sequential boundary',bit,row['name'])
        selected.add(i)
        for pin,expr in row['ports'].items():
            if pin not in row['outpins']:
                for b in bits(expr):resolve(b)
    for pin,expr in conns.items():
        if pin not in child_outputs:
            for bit in bits(expr):resolve(bit)
    DEST.mkdir(parents=True,exist_ok=True)
    defs=[]
    for i in sorted(selected):
        row=instances[i];defs.append(row['code'])
        defs.extend(re.findall(r'^defparam\s+'+re.escape(row['name'])+r'\.\w+\s*=.*?;',parent,re.M))
    declared='\n'.join(f'wire {width} {name} ;' for name,width in declarations.items())
    wrapper='''module mapped_approach(input clk,rst,tick,enable,inverted_i,input signed[15:0]yaw,target,input[7:0]maxspeed,output[2:0]command,output[15:0]velocity);
'''+declared+'''
assign clk_50m_i_d=clk;assign n177_5=!rst;assign sample_tick_d=tick;
assign inverted=inverted_i;assign target_pending=0;assign turn_active=enable;
assign turn_yaw=yaw;assign turn_target_yaw=target;assign speed=maxspeed[3:0];
assign command=enable?command_q:0;assign velocity=command==0?0:{12'd0,speed_q};
'''+ '\n'.join(defs)+'\n'+actual+'\nendmodule\n'
    child=child.replace('module heading_approach_control (','module r9_system_approach (',1)
    wrapper=wrapper.replace('heading_approach_control \\g_approach.u_approach','r9_system_approach \\g_approach.u_approach')
    (DEST/'mapped.v').write_text(child+'\n'+wrapper)
    bench='''`timescale 1ns/1ps
module tb;
GSR GSR(.GSRI(1'b1));
reg clk=0;always #5 clk=~clk;
reg rst=0,tick=0,en=0,inv=0;reg signed[15:0]yaw=0,target=12868;reg[7:0]maxspeed=12;
wire signed[16:0]diff=$signed({target[15],target})-$signed({yaw[15],yaw});
wire signed[16:0]err=diff>25736?diff-17'sd51472:diff< -25736?diff+17'sd51472:diff;
wire[2:0]a,b;wire[15:0]sa,sb;wire reference_stable;
mapped_approach dut(clk,rst,tick,en,inv,yaw,target,maxspeed,a,sa);
heading_approach_control reference(clk,rst,tick,en,inv,yaw,err,maxspeed,b,sb,reference_stable);
integer k,yy,seed=99371,v=0,drive;
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(k=0;k<5000;k=k+1)begin
   @(negedge clk);
   if(k%500==0)begin en=0;inv=(k/500)%2;target=k%1000==0?24500:-24500;maxspeed=k%1000==0?8:12;end
   else if(k%500==8)en=1;
   drive=b==5?sb*16:b==6?-sb*16:0;if(inv)drive=-drive;
   v=(v*3+drive)/4;yy=$signed(yaw)+v;
   if(k%137==0)yy=$signed(yaw)+($random(seed)%400);
   if(yy>25736)yy=yy-51472;if(yy< -25736)yy=yy+51472;yaw=yy;
   tick=1;@(negedge clk);tick=0;repeat(10)@(negedge clk);
   if(a!==b || sa!==sb)$fatal(1,"Actual mapped approach mismatch sample=%d cmd=%d/%d speed=%d/%d",k,a,b,sa,sb);
 end
 $display("R9_FULL_SYSTEM_MAPPED_APPROACH_PARENT_CONE_5000_PASS");$finish;
end
endmodule
'''
    (DEST/'tb.sv').write_text(bench)
    lib=DEST.as_posix()+'/sim';log=OUT/'r9_full_system_mapped_approach.log'
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {DEST.as_posix()}/mapped.v fpga/motor_bt_drive/heading_approach_control.v
vlog -sv -work {lib} {DEST.as_posix()}/tb.sv
vsim -c {lib}.tb
run -all
quit -f
'''
    (DEST/'run.do').write_text(do)
    result=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=120)
    t=log.read_text(errors='replace')
    assert result.returncode==0 and 'R9_FULL_SYSTEM_MAPPED_APPROACH_PARENT_CONE_5000_PASS' in t and '** Fatal' not in t,result.stdout+result.stderr
    report=dict(passed=True,samples=5000,parent_cone_primitives=len(selected),internal_forces=False,hardware_access=False,
                scope='actual independent-turn mapped approach and real hoisted parent arithmetic/enable LUT cone; nav specialization structurally inspected',
                full_system_signoff=False,netlist_sha256=hashlib.sha256(net.read_bytes()).hexdigest())
    (OUT/'SIN12_R9_MAPPED_APPROACH_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print(f'Actual mapped approach + {len(selected)} parent primitives: 5000 PASS')

if __name__=='__main__':main()
