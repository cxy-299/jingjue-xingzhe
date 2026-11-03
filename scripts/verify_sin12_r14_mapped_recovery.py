"""R14 mission recovery from the real full-system mapped primitive cone.

Cut points are named original producer interfaces (packet, sensor, decoder,
manual command and other owners), not synthetic optimized input guesses.
Shared decoder LUTs and their real parser state remain in the extracted cone.
No forced registers, altered constants, accelerated internal clocks or RTL
substitution. External 10ms sampling is tested as a strobe contract; this is
functional mapped evidence, NOT whole-system routed/SDF timing signoff.
"""
from pathlib import Path
import hashlib,json,re,subprocess,sys
from mapped_cone import MappedCone
from verify_sin12_r14_mapped_tof import verify_current_netlist
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board';DEST=ROOT/'tmp/sin12_r14_mapped_recovery'

def main():
    digest=verify_current_netlist();net=ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg'
    if '--run-prepared' in sys.argv:
        report=json.loads((DEST/'extraction.json').read_text())
        assert report['netlist_sha256']==digest and not report['internal_forces']
        assert (DEST/'mapped.v').exists()
        print('Resuming prepared actual recovery cone:',report['primitive_count'],flush=True)
    else:
        graph=MappedCone(net.read_text(),'acg720_motor_bt_drive')
        inputs={
          'clk':'clk_50m_i_d','reset':'n177_5','key_n':'key_s0_n_i_d','tick':'sample_tick_d',
          'request':'mission_request','job':r'\g_mission.rid','cls':r'\g_mission.rc','arrival':r'\g_mission.rd',
          'red':r'\g_mission.red','inv':r'\g_mission.inverted','pkt':r'\g_pi_vision.packet',
          'seq':r'\g_pi_vision.sequence_id','pjob':'pi_mission','lockid':r'\g_pi_vision.lock_id',
          'pclass':r'\g_pi_vision.class_id','pred':'pi_red','selected':r'\g_pi_vision.selected',
          'visible':r'\g_pi_vision.present','confirmed':r'\g_pi_vision.confirmed',
          'center':r'\g_pi_vision.center_error','yaw':'turn_yaw','distance':'tof0_distance_mm','ds':'tof_sample',
          'yawvalid':'heading_yaw_valid','tofvalid':'tof_valid','hard':'tof_hard_stop_q','fault':'fault_flags',
          'ascii':'bt_data','av':'bt_valid','err':'bt_framing_error','manual':'command',
          'autoactive':'auto_active','visionactive':'vision_active','turnactive':'turn_active','navactive':'nav_active',
          'autorequest':'auto_request','turnrequest':'turn_request','navrequest':'nav_goal_pulse',
          'vcommand':'vision_command','tcommand':'applied_command','ncommand':'command_q_0',
          'wheel0':r'\wheels[0].raw_speed','wheel1':r'\wheels[1].raw_speed',
          'wheel2':r'\wheels[2].raw_speed','wheel3':r'\wheels[3].raw_speed',
        }
        outputs={'active':'mission_active','state':'mission_state','id':'mission_id','locked':'mission_lock','command':'selected_command_raw'}
        inactive={p:0 for p in ['autoactive','visionactive','turnactive','navactive']}
        code,cells=graph.extract(inputs,outputs,inactive)
        # Truth-table cofactoring only removes fan-in proven irrelevant with
        # other owners inactive. Retain original LUT parameters; skipped inputs
        # are X, not guessed values. Enforce the declared interface contract.
        code+='\nalways @(posedge clk) if (reset && ('+' || '.join(p+"!==1'b0" for p in inactive)+')) $fatal(1,"inactive-owner cone constraint violated");\n'
        # Exact interface widths follow the new real declarations, no fabricated
        # high bits: current range13b, requested distance10b, fault_flags[4:3].
        decl=[]
        for direction,mapping in [('input',inputs),('output',outputs)]:
            for pin,n in mapping.items():
                w=len(graph.root[n]);decl.append(direction+(' ['+str(w-1)+':0]' if w>1 else '')+' '+pin+';')
        wrapper='module r14_actual_recovery('+','.join([*inputs,*outputs])+');\n'+'\n'.join(decl)+'\n'+code+'\nendmodule\n'
        DEST.mkdir(parents=True,exist_ok=True);(DEST/'mapped.v').write_text(wrapper)
        report=dict(passed=False,netlist_sha256=digest,hardware_access=False,internal_forces=False,altered_mapped_constants=False,
          original_interface_cut_points=inputs,observation_points=outputs,primitive_count=len(cells),
          inactive_owner_constraints=inactive,lut_independence_proofs=graph.pruning_proof,
          cell_kinds={k:sum(c['kind']==k for c in cells) for k in sorted({c['kind'] for c in cells})},
          scope='actual full-system mapped mission and shared decoder/owner primitive cone; original producer interfaces; external sample_tick contract, not whole routed SDF',
          instances=[c['path'] for c in cells])
        (DEST/'extraction.json').write_text(json.dumps(report,indent=2))
        print('Actual recovery cone prepared:',len(cells),'primitives',flush=True)
        if '--prepare-only' in sys.argv:return
    report['mapped_wrapper_sha256']=hashlib.sha256((DEST/'mapped.v').read_bytes()).hexdigest()
    lib=DEST.as_posix()+'/sim';log=OUT/'r14_full_system_mapped_recovery.log'
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} D:/software/gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v {DEST.as_posix()}/mapped.v
vlog -sv -work {lib} fpga/motor_bt_drive/tb_sin12_r14_mapped_recovery.sv
vsim -c {lib}.tb_sin12_r14_mapped_recovery
run -all
quit -f
'''
    (DEST/'run.do').write_text(do)
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=1800)
    result=log.read_text();assert p.returncode==0 and 'R14_ACTUAL_MAPPED_RECOVERY_PASS' in result and '** Fatal' not in result,p.stdout[-4000:]+p.stderr[-4000:]
    assert verify_current_netlist()==digest
    report['passed']=True;report['scenario_markers']=re.findall(r'^# (R14_MAPPED_\S+PASS)',result,re.M)
    (OUT/'SIN12_R14_MAPPED_RECOVERY_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('R14 actual full-system mapped recovery PASS')
if __name__=='__main__':main()
