"""Compare the actual frozen map with GUI geometry; never rebuilds or controls."""
from pathlib import Path
from collections import deque
import hashlib,json,re
from scripts.build_nav_map import occupied_cells,shortest_path_from
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def board_route(cells,start,goal):
    q=deque([start]);parent={start:None}
    while q and goal not in parent:
        x,y=q.popleft()
        for dx,dy in ((0,1),(-1,0),(0,-1),(1,0)):
            p=(x+dx,y+dy)
            if 0<=p[0]<20 and 0<=p[1]<20 and not cells[p[1]*20+p[0]] and p not in parent:
                parent[p]=(x,y);q.append(p)
    if goal not in parent:return []
    path=[];p=goal
    while p is not None:path.append(p);p=parent[p]
    return path[::-1]
def main():
    spec=json.loads((ROOT/'config/nav-map-sin12.json').read_text(encoding='utf-8'))
    cells=occupied_cells(spec);h=(ROOT/'fpga/nav/sin12_map.vh').read_text()
    value=int(re.search(r"SIN12_MAP_BITS 400'h([0-9A-F]+)",h)[1],16)
    frozen=OUT/'sin12_hdmi_r9_20261030_135330/sources/fpga/nav/sin12_map.vh'
    assert h==(frozen.read_text()), 'Current header differs from programmed archive'
    mismatch=[i for i in range(400) if cells[i]!=((value>>i)&1)]
    oldroutes={};differences=[]
    for y in range(20):
        for x in range(20):
            host=shortest_path_from(spec,cells,(17,2),(x,y))
            board=board_route(cells,(17,2),(x,y))
            assert len(host)==len(board),((x,y),len(host),len(board))
            if host!=board:differences.append(dict(goal=[x,y],host_first=host[1] if len(host)>1 else None,board_first=board[1] if len(board)>1 else None))
    examples=[]
    for goal in [(17,8),(15,15),(15,16),(9,14)]:
        a=shortest_path_from(spec,cells,(17,2),goal);b=board_route(cells,(17,2),goal)
        examples.append(dict(start=[17,2],goal=goal,host_preview=a,board_order_model=b,steps=len(b)-1))
    report=dict(map_id='2613',hardware_access=False,cells_compared=400,occupancy_mismatches=mismatch,
                frozen_header_sha256=hashlib.sha256(frozen.read_bytes()).hexdigest(),
                gui_neighbor_order=['+X','-X','+Y','-Y'],fpga_neighbor_order=['+Y','-X','-Y','+X'],
                all_goal_reachability_and_length_match=True,tie_route_differences=len(differences),examples=examples,
                scope='Actual frozen map vs GUI generated cells; Python model of observed RTL direction order, not an RTL simulation')
    (OUT/'SIN12_R9_MAP_ROUTE_AUDIT_2026-10-30.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(cells_compared=400,occupancy_mismatches=mismatch,tie_route_differences=len(differences),examples=examples),ensure_ascii=False))
if __name__=='__main__':main()
