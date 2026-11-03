"""Printed, single-digit PORTRAIT A4 targets. Perception only, never motion.
Physical A4 dimensions are an operator setup contract, not inferred from pixels.
Reject unrecognised pages; never label an arbitrary white rectangle as a digit.
"""
import base64
import json
from pathlib import Path
import time
import zlib
import cv2
import numpy as np
from src.core.messages import Detection
from src.core.a4_targets import CLASS_BASE,NAMES,is_a4_category

def normalize_glyph(mask):
    ys,xs=np.nonzero(mask)
    if not len(xs): return None
    crop=mask[ys.min():ys.max()+1,xs.min():xs.max()+1]
    h,w=crop.shape
    scale=min(28/w,40/h)
    small=cv2.resize(crop,(max(1,round(w*scale)),max(1,round(h*scale))),interpolation=cv2.INTER_AREA)
    out=np.zeros((48,36),np.uint8)
    y,x=(48-small.shape[0])//2,(36-small.shape[1])//2
    out[y:y+small.shape[0],x:x+small.shape[1]]=small
    return out

class DigitTemplates:
    def __init__(self,path=None,min_score=.86,min_margin=.045):
        path=Path(path) if path else Path(__file__).resolve().parents[2]/'assets/a4_digits_templates.json'
        doc=json.loads(path.read_text(encoding='utf8'))
        self.samples=[]
        for item in doc['samples']:
            image=np.frombuffer(zlib.decompress(base64.b64decode(item['pixels'])),np.uint8).reshape(48,36)
            self.samples.append((int(item['digit']),image))
        if set(n for n,_ in self.samples)!=set(range(10)): raise ValueError('Incomplete digit template bank')
        self.min_score,self.min_margin=float(min_score),float(min_margin)
        if not .8<=self.min_score<=1 or not .02<=self.min_margin<=.3: raise ValueError('Unsafe digit thresholds')

    def classify(self,mask):
        glyph=normalize_glyph(mask)
        if glyph is None: return None
        # Small alignment tolerance, not a learned confidence probability.
        padded=cv2.copyMakeBorder(glyph,2,2,2,2,cv2.BORDER_CONSTANT,value=0)
        scores=[-1.]*10
        for digit,template in self.samples:
            score=float(cv2.matchTemplate(padded,template,cv2.TM_CCOEFF_NORMED).max())
            scores[digit]=max(scores[digit],score)
        order=np.argsort(scores)
        best,runner=int(order[-1]),int(order[-2])
        if scores[best]<self.min_score or scores[best]-scores[runner]<self.min_margin: return None
        return best,scores[best],scores[best]-scores[runner]

class A4DigitDetector:
    names=NAMES
    label='A4 printed digit / full-page + anchored intact-digit v2'
    def __init__(self,settings=None):
        cfg=settings or {}
        self.reader=DigitTemplates(cfg.get('templates'),cfg.get('min_score',.86),cfg.get('min_margin',.045))
        self.status={}
        self.pages=[]
        self.anchors={}

    @staticmethod
    def ordered_quad(points):
        p=np.asarray(points,np.float32).reshape(4,2)
        by_y=p[np.argsort(p[:,1])]
        top=by_y[:2][np.argsort(by_y[:2,0])]
        bottom=by_y[2:][np.argsort(by_y[2:,0])]
        return np.array([top[0],top[1],bottom[1],bottom[0]],np.float32)

    @staticmethod
    def corner_mark(gray, x0, y0):
        """Locate an actual square in a small corner REGION, not six pixels.

        Mild paper curl and polygon approximation move marks after warping.
        Still require a compact dark component at BOTH top corners; a dark
        border, large patch or missing mark is not an orientation certificate.
        """
        roi=(gray[y0:y0+27,x0:x0+30]<115).astype(np.uint8)
        _,_,stats,_=cv2.connectedComponentsWithStats(roi)
        matches=[s for s in stats[1:] if 24<=s[4]<=260 and 4<=s[2]<=18
                 and 4<=s[3]<=20 and .45<=s[2]/s[3]<=2.0
                 and s[4]/(s[2]*s[3])>=.55]
        return len(matches)==1

    @staticmethod
    def page_overlap(a,b):
        intersection=max(0,min(a.x2,b.x2)-max(a.x1,b.x1))*max(0,min(a.y2,b.y2)-max(a.y1,b.y1))
        union=(a.x2-a.x1)*(a.y2-a.y1)+(b.x2-b.x1)*(b.y2-b.y1)-intersection
        return intersection/max(1,union)

    @staticmethod
    def registered_edge_quads(gray,edges):
        """Weak top edge: two printed marks AND observed left/right/bottom.

        Recover only the top margin from the known marker layout; require
        independent long side lines and a bottom line, and a wholly in-frame
        resulting quad. Two spots or a cached digit box alone are insufficient.
        This is a paper-layout hypothesis, NEVER a calibrated physical range.
        """
        _,_,stats,centers=cv2.connectedComponentsWithStats((gray<105).astype(np.uint8))
        marks=[];height,width=gray.shape
        for s,p in zip(stats[1:],centers[1:]):
            x,y,w,h,area=map(int,s)
            if not (8<=area<=500 and 2<=w<=25 and 2<=h<=25
                    and .5<=w/h<=2 and area/(w*h)>.6):continue
            patch=gray[max(0,y-3):y+h+3,max(0,x-3):x+w+3]
            if np.median(patch)<125:continue
            marks.append((np.asarray(p,np.float32),area))
        if len(marks)<2:return []
        lines=cv2.HoughLinesP(edges,1,np.pi/180,30,minLineLength=40,maxLineGap=12)
        if lines is None:return []
        lines=np.asarray(lines,np.float32).reshape(-1,2,2)
        pairs=[]
        for i,(p,area) in enumerate(marks[:32]):
            for q,other in marks[i+1:32]:
                if q[0]<p[0]:p0,p1=q,p
                else:p0,p1=p,q
                span=float(np.linalg.norm(p1-p0))
                if 45<span<width*.8 and abs(p1[1]-p0[1])<span*.2 and .4<area/other<2.5:
                    pairs.append((abs(p1[1]-p0[1])/span+abs(np.log(area/other))*.1,p0,p1,span))
        candidates=[]
        for _,p,q,span in sorted(pairs,key=lambda v:v[0])[:24]:
            u=(q-p)/span;v=np.float32([-u[1],u[0]])
            xy=np.stack(((lines-p)@u,(lines-p)@v),axis=-1)
            sides=[[],[]];bottoms=[]
            for ends in xy:
                (x0,y0),(x1,y1)=ends
                if abs(y1-y0)>=span*.45:
                    a=float((x1-x0)/(y1-y0));b=float(x0-a*y0)
                    if abs(a)>.3:continue
                    # Collinear segments may be broken by a crease. Require
                    # measured edge support both near the top and lower down.
                    close=np.all(np.abs(xy[:,:,0]-a*xy[:,:,1]-b)<6,axis=1)
                    support=xy[close,:,1]
                    if not support.size or support.min()>span*.5 or support.max()<span*.9:continue
                    for side,expected in enumerate((-span/12,span*13/12)):
                        error=abs(b-expected)/span
                        if error<.18:sides[side].append((error+abs(a)*.1,a,b))
                if abs(x1-x0)>=span*.4:
                    a=float((y1-y0)/(x1-x0));b=float(y0-a*x0)
                    if (abs(a)<.2 and span<b<span*2.2 and min(x0,x1)>-span*.25
                            and max(x0,x1)<span*1.3 and min(x0,x1)<span*.9
                            and max(x0,x1)>span*.35):
                        bottoms.append((abs(b/span-282/180),a,b))
            for le,la,lb in sorted(sides[0])[:2]:
                for re,ra,rb in sorted(sides[1])[:2]:
                    for be,ba,bb in sorted(bottoms)[:2]:
                        top=-span/12
                        ly=(ba*lb+bb)/(1-ba*la);ry=(ba*rb+bb)/(1-ba*ra)
                        quad=np.float32([[la*top+lb,top],[ra*top+rb,top],
                                         [ra*ry+rb,ry],[la*ly+lb,ly]])
                        actual=p+quad[:,0:1]*u+quad[:,1:2]*v
                        if (np.any(actual[:,0]<3) or np.any(actual[:,0]>=width-3)
                                or np.any(actual[:,1]<3) or np.any(actual[:,1]>=height-3)):continue
                        candidates.append((le+re+be,actual.reshape(4,1,2)))
        return [q for _,q in sorted(candidates,key=lambda v:v[0])[:24]]

    def read_page(self,page):
        gray=cv2.cvtColor(page,cv2.COLOR_BGR2GRAY)
        # Two TOP corner registration squares are mandatory in the printable
        # target. Reject upside-down cards (6/9 ambiguity), background rectangles
        # and arbitrary documents. These are not a proof of physical A4 size.
        for x in (2,179):
            if not self.corner_mark(gray,x,3): return None
            if self.corner_mark(gray,x,267): return None
        # Drop edge/border. Require one big, isolated, central printed glyph.
        crop=gray[30:267,21:189]
        if float(np.std(crop))<18: return None
        _,ink=cv2.threshold(crop,0,255,cv2.THRESH_BINARY_INV+cv2.THRESH_OTSU)
        count,labels,stats,_=cv2.connectedComponentsWithStats(ink)
        components=[s for s in stats[1:] if s[4]>=max(24,ink.size*.0015)]
        if len(components)!=1: return None
        x,y,w,h,area=components[0]
        if not (75<=h<=220 and 8<=w<=150 and .10<=area/(w*h)<=.85): return None
        if abs((x+w/2)-ink.shape[1]/2)>42 or abs((y+h/2)-ink.shape[0]/2)>65: return None
        # Significant border touching means partial glyph, not a number.
        if min(x,y)<2 or x+w>ink.shape[1]-2 or y+h>ink.shape[0]-2: return None
        cleaned=np.zeros_like(ink)
        cleaned[y:y+h,x:x+w]=ink[y:y+h,x:x+w]
        result=self.reader.classify(cleaned)
        return None if result is None else (*result,(x+21,y+30,w,h))

    def partial_from_anchor(self,frame,contours,anchor,now):
        if now-anchor['at']>.75: return None
        height,width=frame.shape[:2]
        previous=anchor['glyph']
        found=[]
        for contour in contours:
            x,y,w,h=cv2.boundingRect(contour)
            # Only a genuinely frame-clipped white surface is a near-mode
            # candidate. Complete pages must go through orientation/quad checks.
            if not (x<=2 or y<=2 or x+w>=width-2 or y+h>=height-2): continue
            if w<60 or h<100 or cv2.contourArea(contour)<.04*width*height: continue
            gray=cv2.cvtColor(frame[y:y+h,x:x+w],cv2.COLOR_BGR2GRAY)
            if np.std(gray)<18: continue
            _,ink=cv2.threshold(gray,0,255,cv2.THRESH_BINARY_INV+cv2.THRESH_OTSU)
            n,labels,stats,_=cv2.connectedComponentsWithStats(ink)
            for index,s in enumerate(stats[1:],1):
                gx,gy,gw,gh,area=map(int,s)
                if gh<45 or gw<7 or not .10<=area/max(1,gw*gh)<=.85: continue
                # Reject a cut-off DIGIT, even when the paper itself is cut off.
                if min(gx,gy)<6 or gx+gw>w-6 or gy+gh>h-6: continue
                cx,cy=x+gx+gw/2,y+gy+gh/2
                px,py,pw,ph=previous
                if abs(cx-(px+pw/2))>width*.16 or abs(cy-(py+ph/2))>height*.16: continue
                if not .65<gh/ph<1.65 or not .65<gw/pw<1.65: continue
                mask=np.where(labels==index,255,0).astype(np.uint8)
                result=self.reader.classify(mask)
                if result is None or result[0]!=anchor['digit']: continue
                # A current intact same digit is evidence. The last paper box
                # alone is never an observation, range, or permission to move.
                found.append((result,(x+gx,y+gy,gw,gh)))
        if len(found)!=1: return None
        result,glyph=found[0];gx,gy,gw,gh=glyph
        d=Detection(CLASS_BASE+anchor['digit'],NAMES[CLASS_BASE+anchor['digit']],result[1],
                    float(gx),float(gy),float(gx+gw),float(gy+gh),width,height,'a4_partial_digit')
        d.a4_glyph_bbox=glyph
        d.a4_metric_height_mm=anchor['glyph_height_mm']
        d.a4_anchor_digit=anchor['digit']
        return d,glyph,result

    def detect(self,frame_bgr,target_class=None):
        started=time.monotonic()
        self.pages=[]
        if frame_bgr is None or frame_bgr.ndim!=3: return []
        height,width=frame_bgr.shape[:2]
        hsv=cv2.cvtColor(frame_bgr,cv2.COLOR_BGR2HSV)
        white=cv2.inRange(hsv,np.array([0,0,135]),np.array([179,95,255]))
        white=cv2.morphologyEx(white,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
        contours,_=cv2.findContours(white,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        # A white wall can merge with the white paper in the colour mask. Add
        # gray-edge contours after local contrast enhancement. A weak top edge
        # also has a bounded printed-marker + three observed-edge fallback;
        # never create a page from a digit or cached rectangle alone.
        gray=cv2.cvtColor(frame_bgr,cv2.COLOR_BGR2GRAY)
        contrast=cv2.createCLAHE(clipLimit=3.,tileGridSize=(8,8)).apply(gray)
        edges=cv2.Canny(cv2.GaussianBlur(contrast,(3,3),.6),20,60)
        edges=cv2.morphologyEx(edges,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
        edge_contours,_=cv2.findContours(edges,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE)
        proposals=(sorted(contours,key=cv2.contourArea,reverse=True)[:12]
                   +sorted(edge_contours,key=cv2.contourArea,reverse=True)[:32]
                   +self.registered_edge_quads(gray,edges))
        full_candidates=[]
        for contour in proposals:
            area=cv2.contourArea(contour)
            if not .012*width*height<=area<=.80*width*height: continue
            poly=cv2.approxPolyDP(contour,.025*cv2.arcLength(contour,True),True)
            if len(poly)!=4 or not cv2.isContourConvex(poly): continue
            quad=self.ordered_quad(poly)
            if np.any(quad[:,0]<3) or np.any(quad[:,0]>=width-3) or np.any(quad[:,1]<3) or np.any(quad[:,1]>=height-3): continue
            top,bottom=np.linalg.norm(quad[1]-quad[0]),np.linalg.norm(quad[2]-quad[3])
            left,right=np.linalg.norm(quad[3]-quad[0]),np.linalg.norm(quad[2]-quad[1])
            ratio=(top+bottom)/max(1,left+right)
            if not .48<=ratio<=.93 or min(top,bottom)<45 or min(left,right)<85: continue
            if max(top,bottom)/min(top,bottom)>1.65 or max(left,right)/min(left,right)>1.65: continue
            transform=cv2.getPerspectiveTransform(quad,np.float32([[0,0],[209,0],[209,296],[0,296]]))
            page=cv2.warpPerspective(frame_bgr,transform,(210,297))
            result=self.read_page(page)
            if result is None: continue
            digit,score,margin,canonical_glyph=result
            x1,y1=quad.min(axis=0);x2,y2=quad.max(axis=0)
            gx,gy,gw,gh=canonical_glyph
            glyph_points=cv2.perspectiveTransform(np.float32([[[gx,gy],[gx+gw,gy],[gx+gw,gy+gh],[gx,gy+gh]]]),np.linalg.inv(transform))[0]
            lo,hi=glyph_points.min(axis=0),glyph_points.max(axis=0)
            glyph=(float(lo[0]),float(lo[1]),float(hi[0]-lo[0]),float(hi[1]-lo[1]))
            d=Detection(CLASS_BASE+digit,NAMES[CLASS_BASE+digit],score,float(x1),float(y1),float(x2),float(y2),width,height,'a4_digit_template')
            d.a4_glyph_bbox=glyph
            d.a4_metric_height_mm=297.
            full_candidates.append((d,dict(digit=digit,class_id=CLASS_BASE+digit,quad=quad.tolist(),score=score,margin=margin,
                paper_width_mm=210,paper_height_mm=297,physical_size_verified=False,
                visibility='full_page',glyph_height_mm=float(gh),glyph_bbox=glyph)))
        # Colour and inner/outer edge contours can describe the SAME paper.
        # Count it once, but reject disagreeing identities instead of choosing
        # a more convenient digit. Separate duplicate-number cards stay separate.
        groups=[]
        for candidate in full_candidates:
            group=next((g for g in groups if any(self.page_overlap(candidate[0],p[0])>.65 for p in g)),None)
            if group is None:groups.append([candidate])
            else:group.append(candidate)
        out=[];disputed=set()
        for group in groups:
            identities={p[0].class_id for p in group}
            if len(identities)!=1:
                disputed.update(n-CLASS_BASE for n in identities)
                continue
            d,page=max(group,key=lambda p:p[0].confidence)
            out.append(d);self.pages.append(page)
        for n in disputed:self.anchors.pop(n,None)
        # Refresh anchors ONLY from unique complete pages or a current matching
        # intact digit. Duplicate IDs remove the association instead of guessing.
        seen_counts={n:sum(d.class_id==CLASS_BASE+n for d in out) for n in range(10)}
        now=time.monotonic()
        for p in self.pages:
            n=p['digit']
            if seen_counts[n]==1:
                self.anchors[n]=dict(digit=n,at=now,glyph=p['glyph_bbox'],glyph_height_mm=p['glyph_height_mm'])
            else:self.anchors.pop(n,None)
        for n,anchor in list(self.anchors.items()):
            if seen_counts[n]: continue
            partial=self.partial_from_anchor(frame_bgr,contours,anchor,now)
            if partial is None:
                if now-anchor['at']>.75:self.anchors.pop(n,None)
                continue
            d,glyph,result=partial;out.append(d)
            anchor.update(at=now,glyph=glyph)
            self.pages.append(dict(digit=n,class_id=CLASS_BASE+n,score=result[1],margin=result[2],
                visibility='partial_paper_intact_digit',glyph_bbox=glyph,
                glyph_height_mm=anchor['glyph_height_mm'],physical_size_verified=False,
                range_basis='previous full A4 anchor, CURRENT intact same digit only'))
        self.status=dict(detector_backend='a4_digits',detector_revision='a4-digit-v3-whitewall-20261031',
            detector_ms=round((time.monotonic()-started)*1000,1),detector_passes=1,
            near_bottle_mode=False,a4_pages=self.pages,a4_scope='portrait A4, one central black printed digit0-9; template score is not probability')
        return out

