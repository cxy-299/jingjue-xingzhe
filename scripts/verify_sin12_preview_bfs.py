"""Compare final GUI ordering against production RTL BFS for all 400 goals."""
from pathlib import Path
import hashlib,json,subprocess
from scripts.build_nav_map import occupied_cells,shortest_path_from,FPGA_NEIGHBOR_ORDER
ROOT=Path(__file__).resolve().parents[1];DEST=ROOT/'tmp/sin12_preview_bfs';OUT=ROOT/'output/board'
def main():
    DEST.mkdir(exist_ok=True)
    spec=json.loads((ROOT/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    cells=occupied_cells(spec);occupied=sum(v<<i for i,v in enumerate(cells));lines=[]
    for gy in range(20):
        for gx in range(20):
            path=shortest_path_from(spec,cells,(17,2),(gx,gy),neighbor_order=FPGA_NEIGHBOR_ORDER)
            length=len(path)-1 if path else 511
            nxt=path[min(1,len(path)-1)] if path else (0,0)
            value=occupied|((2*20+17)<<2000)|((gy*20+gx)<<2009)|(length<<2018)|((nxt[1]*20+nxt[0])<<2027)
            lines.append(f'{value:0512x}')
    (DEST/'cases.mem').write_text('\n'.join(lines))
    old=(ROOT/'fpga/motor_bt_drive/tb_sin12_bfs.sv').read_text()
    bench=old.replace('tb_sin12_bfs','tb_sin12_preview_bfs').replace('[0:47]','[0:399]').replace('i<48','i<400')
    bench=bench.replace('sin12_planner_vectors.mem',(DEST/'cases.mem').as_posix()).replace('SIN12_BFS_48_CPU_ORACLE_CASES_PASS','SIN12_PREVIEW_PRODUCTION_BFS_400_GOALS_PASS')
    (DEST/'tb.sv').write_text(bench)
    lib=DEST.as_posix()+'/sim';do=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -work {lib} fpga/nav/grid_bfs_dynamic.v
vlog -sv -work {lib} {DEST.as_posix()}/tb.sv
vsim -c {lib}.tb_sin12_preview_bfs
run -all
quit -f
'''
    (DEST/'run.do').write_text(do);log=OUT/'sin12_preview_bfs_400.log'
    p=subprocess.run(['D:/software/modelism/win64/vsim.exe','-c','-do',str(DEST/'run.do'),'-l',str(log)],cwd=ROOT,capture_output=True,text=True,timeout=120)
    result=log.read_text();assert p.returncode==0 and 'SIN12_PREVIEW_PRODUCTION_BFS_400_GOALS_PASS' in result and '** Fatal' not in result,p.stdout+p.stderr
    report=dict(passed=True,goals=400,hardware_access=False,internal_forces=False,start=[17,2],neighbor_order=FPGA_NEIGHBOR_ORDER,
                occupancy=hex(occupied),bfs_sha256=hashlib.sha256((ROOT/'fpga/nav/grid_bfs_dynamic.v').read_bytes()).hexdigest(),
                scope='production RTL first-hop/no-path/length vs GUI planner for all goal cells; static map and zero denied edges')
    (OUT/'SIN12_PREVIEW_BFS_400_VALIDATION.json').write_text(json.dumps(report,indent=2))
    print('Actual production BFS vs corrected preview: 400 goals PASS')
if __name__=='__main__':main()
