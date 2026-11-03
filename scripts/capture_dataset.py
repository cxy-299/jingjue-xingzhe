from pathlib import Path
import time,cv2
out=Path('data/images'); out.mkdir(parents=True,exist_ok=True); cap=cv2.VideoCapture(0); count=0
print('SPACE保存图片，q退出')
while True:
    ok,frame=cap.read()
    if not ok: break
    cv2.putText(frame,f'Saved: {count}',(20,35),cv2.FONT_HERSHEY_SIMPLEX,.8,(255,255,255),2); cv2.imshow('Dataset Capture',frame)
    k=cv2.waitKey(1)&0xFF
    if k==ord('q'): break
    if k==32:
        p=out/f'img_{int(time.time()*1000)}.jpg'; cv2.imwrite(str(p),frame); count+=1; print('saved',p)
cap.release(); cv2.destroyAllWindows()
