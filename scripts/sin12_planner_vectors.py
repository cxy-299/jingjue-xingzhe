"""Independent CPU BFS oracle for HDL planner acceptance (48 fixed cases)."""
from collections import deque
from pathlib import Path
import random


def oracle(blocked, edges, start, goal):
    if blocked >> start & 1 or blocked >> goal & 1:
        return 511, 511
    parent={start:start};q=deque([start])
    while q and goal not in parent:
        cur=q.popleft();x,y=cur%20,cur//20
        for direction,nxt,valid in ((0,cur+20,y<19),(1,cur-1,x>0),(2,cur-20,y>0),(3,cur+1,x<19)):
            if valid and not (edges>>(cur*4+direction)&1) and not (blocked>>nxt&1) and nxt not in parent:
                parent[nxt]=cur;q.append(nxt)
    if goal not in parent:return 511,511
    length=0;nxt=goal;cur=goal
    while cur!=start:
        nxt=cur;cur=parent[cur];length+=1
    return length,nxt


def main():
    rng=random.Random(2612)
    cases=[(0,0,0,399),(0,0,399,0),(0,0,5,5),(1,0,0,399),
           (1<<399,0,0,399),((1<<400)-1,0,10,20),(0,(1<<1600)-1,5,6),
           (0,1<<(0*4),0,20)]
    for _ in range(40):
        blocked=sum((rng.random()<.25)<<i for i in range(400))
        edges=sum((rng.random()<.1)<<i for i in range(1600))
        cases.append((blocked,edges,rng.randrange(400),rng.randrange(400)))
    rows=[]
    for blocked,edges,start,goal in cases:
        length,nxt=oracle(blocked,edges,start,goal)
        value=blocked|(edges<<400)|(start<<2000)|(goal<<2009)|(length<<2018)|(nxt<<2027)
        rows.append(f'{value:0512x}\n')
    root=Path(__file__).resolve().parents[1]
    (root/'fpga/motor_bt_drive/sin12_planner_vectors.mem').write_text(''.join(rows),encoding='ascii')
    print(f'{len(rows)} deterministic planner oracle vectors')


if __name__=='__main__':main()
