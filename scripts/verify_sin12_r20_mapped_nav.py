"""Actual R20 500-count navigation cone from original parent producers.
No force, synthetic lifted input guesses, constants changes or RTL replacement.
"""
from pathlib import Path
import json,hashlib,sys,subprocess,re
from mapped_cone import MappedCone
from verify_sin12_r20_mapped_tof import verify_current_netlist
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board';DEST=ROOT/'tmp/sin12_r20_mapped_nav'
def main():
    digest=verify_current_netlist()
    if '--run-prepared' in sys.argv:
        report=json.loads((DEST/'extraction.json').read_text())
        assert report['netlist_sha256']==digest and not report['internal_forces']
    else:
        graph=MappedCone((ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg').read_text(),'acg720_motor_bt_drive')
        inputs={
          'clk':'clk_50m_i_d','reset':'n177_5','key_n':'key_s0_n_i_d','tick':'sample_tick_d',
          'request':'auto_request','seq':r'\g_autonav.seq','sx':r'\g_autonav.sx','sy':r'\g_autonav.sy',
          'gx':r'\g_autonav.gx','gy':r'\g_autonav.gy','counts':r'\g_autonav.counts',
          'setback':r'\g_autonav.setback','flags':r'\g_autonav.flags','velocity':r'\g_autonav.velocity',
          'yaw':'turn_yaw','yawvalid':'heading_yaw_valid','tofvalid':'tof_valid','distance':'tof0_distance_mm','ds':'tof_sample',
          'hard':'tof_hard_stop_q','fault':'fault_flags','ascii':'bt_data','av':'bt_valid','err':'bt_framing_error','manual':'command',
          'missionactive':'mission_active','visionactive':'vision_active','turnactive':'turn_active','navactive':'nav_active',
          'missionrequest':'mission_request','turnrequest':'turn_request','navrequest':'nav_goal_pulse',
          'avoidrequest':'avoid_request','avoidcapture':'avoid_capture','avoidseq':'avoid_sequence',
          'p0':r'\wheel_position[0]','p1':r'\wheel_position[1]','p2':r'\wheel_position[2]','p3':r'\wheel_position[3]',
        }
        outputs={'active':'auto_active','faultout':'auto_fault','state':'auto_state','reason':'auto_reason',
          'sequence':'auto_sequence','x':'auto_x','y':'auto_y','goalx':'auto_gx','goaly':'auto_gy',
          'ox':'auto_ox','oy':'auto_oy','replans':'auto_replans','localmode':'auto_local','command':'selected_command_raw'}
        # The synthesized parent exposes coordinate bits0..4 and7 only.
        # Bits5/6 are pruned, not observable and must never be invented.
        coordinate_bits=[0,1,2,3,4,7]
        for pin in ('x','y','ox','oy'):
            actual=graph.root[outputs[pin]]
            graph.root[outputs[pin]+'_observed']=[actual[i] for i in coordinate_bits]
            outputs[pin]+='_observed'
        inactive={p:0 for p in ('missionactive','visionactive','turnactive','navactive','missionrequest','turnrequest','navrequest','avoidrequest','avoidcapture')}
        code,cells=graph.extract(inputs,outputs,inactive)
        code+='\nalways @(posedge clk) if (!reset && ('+' || '.join(p+"!==1'b0" for p in inactive)+')) $fatal(1,"inactive navigation owner contract violated");\n'
        decl=[];widths={}
        for direction,mapping in [('input',inputs),('output',outputs)]:
            for pin,n in mapping.items():
                w=len(graph.root[n]);widths[pin]=w
                decl.append(direction+(' ['+str(w-1)+':0]' if w>1 else '')+' '+pin+';')
        wrapper='module r20_actual_nav('+','.join([*inputs,*outputs])+');\n'+'\n'.join(decl)+'\n'+code+'\nendmodule\n'
        DEST.mkdir(parents=True,exist_ok=True);(DEST/'mapped.v').write_text(wrapper)
        report=dict(passed=False,netlist_sha256=digest,hardware_access=False,internal_forces=False,altered_mapped_constants=False,
          original_interface_cut_points=inputs,observation_points=outputs,interface_widths=widths,primitive_count=len(cells),
          coordinate_observation_bits=coordinate_bits,unobserved_coordinate_bits=[5,6],
          inactive_owner_constraints=inactive,lut_independence_proofs=graph.pruning_proof,
          scope='Full-system mapped navigation/decoder/owner cone with original packet/sensor/position producers; functional sampling contract, NOT whole routed SDF or physical calibration',
          cell_kinds={k:sum(c['kind']==k for c in cells) for k in sorted({c['kind'] for c in cells})},instances=[c['path'] for c in cells])
        (DEST/'extraction.json').write_text(json.dumps(report,indent=2))
        print('Actual navigation cone prepared:',len(cells),'primitives',flush=True)
        if '--prepare-only' in sys.argv:return
    bench=ROOT/'fpga/motor_bt_drive/tb_sin12_r20_mapped_nav.sv'
    report['mapped_wrapper_sha256']=hashlib.sha256((DEST/'mapped.v').read_bytes()).hexdigest()
    report['testbench_sha256']=hashlib.sha256(bench.read_bytes()).hexdigest()
    lib=DEST.as_posix()+'/sim';log=OUT/'r20_full_system_mapped_nav_validation.log'
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {DEST.as_posix()}/mapped.v
vlog -sv -work {lib} {bench.as_posix()}
vsim -c {lib}.tb_sin12_r20_mapped_nav
run -all
quit -f
'''
    (DEST/'run.do').write_text(do)
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=1800)
    result=log.read_text()
    assert p.returncode==0 and 'R20_ACTUAL_MAPPED_NAV_PASS' in result and '** Fatal' not in result,p.stdout[-4000:]+p.stderr[-4000:]
    summary=re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',result)
    assert summary and summary[-1][0]=='0' and int(summary[-1][1]) in (0,4)
    warnings=re.findall(r'^# \*\* Warning:.*$',result,re.M)
    assert all('vopt-2697' in w and 'prim_sim.v(' in w and any('('+str(n)+')' in w
               for n in (2127,2131,2140,2144)) for w in warnings),warnings
    report['final_errors']=int(summary[-1][0]);report['final_warnings']=int(summary[-1][1])
    report['retained_official_primitive_warnings']=warnings
    assert verify_current_netlist()==digest
    report['passed']=True;report['scenario_markers']=re.findall(r'^# (R20_MAPPED_NAV_\S+PASS)',result,re.M)
    (OUT/'SIN12_R20_MAPPED_NAV_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('R20 actual mapped navigation PASS')
if __name__=='__main__':main()
