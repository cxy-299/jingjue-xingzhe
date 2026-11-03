from src.core.messages import TargetObservation
from src.comm.protocol import pack_target,parse_frame
o=TargetObservation(123456,True,0,'person',.92,5200,4800,1800,4200); f=pack_target(7,o)
print(f.hex(' ')); print(parse_frame(f))
