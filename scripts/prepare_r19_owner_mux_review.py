"""Review-only balanced owner mux; never changes a production hardware source."""
from pathlib import Path
import difflib,hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board/r19_owner_mux_review'
SOURCE=ROOT/'fpga/motor_bt_drive/acg720_motor_bt_drive.v'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    before=sha(SOURCE);text=SOURCE.read_text(encoding='utf-8')
    old_target='    wire [15:0] selected_target_raw = auto_active ? auto_speed : mission_active ? mission_speed : turn_active ? turn_speed : vision_active ? vision_target : target_counts;'
    old_command='    wire [2:0] selected_command_raw = auto_active ? auto_command : mission_active ? mission_command : turn_active ? turn_command : vision_active ? vision_command : (NAV_ENABLE && nav_active) ? nav_command : command;'
    assert text.count(old_target)==text.count(old_command)==1
    new_target='''    // The owners retain their original priority. Decode once, then balance
    // the data selection without inserting a cycle into command or stop gates.
    wire owner_auto = auto_active;
    wire owner_mission = !auto_active && mission_active;
    wire owner_turn = !(auto_active || mission_active) && turn_active;
    wire owner_vision = !(auto_active || mission_active || turn_active) && vision_active;
    wire owner_manual = !(auto_active || mission_active || turn_active || vision_active);
    wire owner_nav = owner_manual && NAV_ENABLE && nav_active;
    wire owner_bt = owner_manual && !(NAV_ENABLE && nav_active);
    wire [15:0] selected_target_raw =
        ({16{owner_auto}} & auto_speed) |
        ({16{owner_mission}} & mission_speed) |
        ({16{owner_turn}} & turn_speed) |
        ({16{owner_vision}} & vision_target) |
        ({16{owner_manual}} & target_counts);'''
    new_command='''    wire [2:0] selected_command_raw =
        ({3{owner_auto}} & auto_command) |
        ({3{owner_mission}} & mission_command) |
        ({3{owner_turn}} & turn_command) |
        ({3{owner_vision}} & vision_command) |
        ({3{owner_nav}} & nav_command) |
        ({3{owner_bt}} & command);'''
    candidate=text.replace(old_target,new_target).replace(old_command,new_command)
    OUT.mkdir(exist_ok=False)
    candidate_path=OUT/'acg720_motor_bt_drive_candidate.v';candidate_path.write_text(candidate,encoding='utf-8')
    (OUT/'candidate.diff').write_text(''.join(difflib.unified_diff(text.splitlines(True),candidate.splitlines(True),fromfile='production/acg720_motor_bt_drive.v',tofile='review-only/acg720_motor_bt_drive.v')))
    bench='''`timescale 1ns/1ps
module tb_owner_mux;
reg auto_active,mission_active,turn_active,vision_active,nav_active,NAV_ENABLE;
reg [15:0] auto_speed,mission_speed,turn_speed,vision_target,target_counts;
reg [2:0] auto_command,mission_command,turn_command,vision_command,nav_command,command;
'''+old_target.replace('selected_target_raw','legacy_target')+'\n'+old_command.replace('selected_command_raw','legacy_command')+'\n'+new_target+'\n'+new_command+'''
integer c,d,n;
initial begin
 // Every Boolean control combination, including simultaneous active owners,
 // and every independent data-bit combination. The mux is bitwise uniform.
 for(c=0;c<64;c=c+1)begin
  {NAV_ENABLE,nav_active,vision_active,turn_active,mission_active,auto_active}=c;
  for(d=0;d<64;d=d+1)begin
   auto_speed={16{d[0]}};mission_speed={16{d[1]}};turn_speed={16{d[2]}};
   vision_target={16{d[3]}};target_counts={16{d[4]}};
   auto_command={3{d[0]}};mission_command={3{d[1]}};turn_command={3{d[2]}};
   vision_command={3{d[3]}};nav_command={3{d[4]}};command={3{d[5]}};
   #1;if(legacy_target!==selected_target_raw || legacy_command!==selected_command_raw)
    $fatal(1,"owner truth table mismatch control=%d data=%d",c,d);
  end
 end
 for(n=0;n<16384;n=n+1)begin
  {NAV_ENABLE,nav_active,vision_active,turn_active,mission_active,auto_active}=$random;
  auto_speed=$random;mission_speed=$random;turn_speed=$random;
  vision_target=$random;target_counts=$random;
  auto_command=$random;mission_command=$random;turn_command=$random;
  vision_command=$random;nav_command=$random;command=$random;
  #1;if(legacy_target!==selected_target_raw || legacy_command!==selected_command_raw)
   $fatal(1,"full bus owner mismatch %d",n);
 end
 $display("R19_OWNER_MUX_ALL4096_BITWISE_CASES_AND16384_BUS_VECTORS_PASS");$finish;
end
endmodule
'''
    (OUT/'tb_owner_mux.sv').write_text(bench)
    lib=(ROOT/'tmp/r19_owner_mux_review_truth').as_posix()
    do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -sv -work {lib} {(OUT/'tb_owner_mux.sv').as_posix()}
vsim -c {lib}.tb_owner_mux
run -all
quit -f
'''
    (OUT/'truth.do').write_text(do)
    vsim='D:/software/modelism/win64/vsim.exe'
    def run(name,do,cwd):
        p=subprocess.run([vsim,'-c','-do',str(do),'-l',str(OUT/(name+'.log'))],cwd=cwd,capture_output=True,text=True,timeout=180)
        (OUT/(name+'_stdout.log')).write_text(p.stdout);(OUT/(name+'_stderr.log')).write_text(p.stderr)
        log=(OUT/(name+'.log')).read_text()
        assert p.returncode==0 and '** Fatal' not in log and re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)',log)[-1]==('0','0'),p.stdout[-3000:]+p.stderr
        return log
    assert 'R19_OWNER_MUX_ALL4096_BITWISE_CASES_AND16384_BUS_VECTORS_PASS' in run('truth',OUT/'truth.do',ROOT)
    full=(ROOT/'fpga/motor_bt_drive/run_modelsim_sin12_r19_full.do').read_text()
    full=full.replace('sim_sin12_r19_full',(ROOT/'tmp/r19_owner_mux_review_full').as_posix())
    full=full.replace(' acg720_motor_bt_drive.v ',' '+candidate_path.as_posix()+' ')
    assert candidate_path.as_posix() in full
    (OUT/'full.do').write_text(full)
    log=run('full_uart',OUT/'full.do',ROOT/'fpga/motor_bt_drive')
    markers=re.findall(r'^# ([^\r\n]*PASS[^\r\n]*)',log,re.M)
    assert markers,log[-3000:]
    assert sha(SOURCE)==before,'Production must stay unchanged'
    report=dict(passed=True,review_only=True,production_modified=False,source_sha256=before,
        candidate_sha256=sha(candidate_path),exhaustive_owner_control_data_bit_cases=4096,
        randomized_full_bus_cases=16384,scope='Boolean owner controls; full bus bitwise proof; no four-state X control equivalence claim',
        full_uart_markers=markers,full_uart_errors=0,full_uart_warnings=0,
        not_proven=['No Gowin mapping or routed STA improvement yet','Not physical vehicle or full-system SDF'],
        preserved='Owner priority/latency, all raw stop gates and all mission/PID/SDC/CST files unchanged')
    (OUT/'PROOF.json').write_text(json.dumps(report,indent=2))
    hashes={p.relative_to(OUT).as_posix():sha(p) for p in OUT.rglob('*') if p.is_file()}
    (OUT/'SHA256.json').write_text(json.dumps(hashes,indent=2));assert all(sha(OUT/n)==v for n,v in hashes.items())
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
