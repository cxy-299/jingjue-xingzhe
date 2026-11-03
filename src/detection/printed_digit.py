"""Upright printed single-digit targets: read CURRENT ink, not paper bounds.

Compatible A400..A409 identities. No range/physical-size inference, no motion.
This template reader is not arbitrary handwriting, rotated OCR or multi-digit OCR.
"""
import time
import cv2
import numpy as np
from src.core.messages import Detection
from src.core.a4_targets import CLASS_BASE,NAMES
from src.detection.a4_digit import DigitTemplates,normalize_glyph
from src.detection.paper_digit_assist import paper_views,illumination_view


class PrintedDigitDetector:
    names=NAMES
    label='Printed digit 0-9 / current intact glyph'
    revision='printed-digit-v4-paper-assist-bounded-20261101'

    def __init__(self,settings=None):
        cfg=settings or {}
        self.reader=DigitTemplates(cfg.get('templates'),cfg.get('min_score',.86),cfg.get('min_margin',.045))
        self._paper_enabled=cfg.get('_paper_enabled',True)
        self._paper_reader=None
        self.status={};self.pages=[]

    def _classify_current(self,mask):
        """Bounded roll fallback, all ten identities compete at unchanged gates.

        Never reconstruct clipped ink or use a previous image/requested class.
        Scores are template correlations, not learned probabilities. Existing
        successful upright classifications remain on the original fast path.
        """
        result=self.reader.classify(mask)
        if result is not None:return result
        self._roll_fallbacks+=1
        h,w=mask.shape;pad=max(6,round(max(h,w)*.3))
        canvas=cv2.copyMakeBorder(mask,pad,pad,pad,pad,cv2.BORDER_CONSTANT,value=0)
        height,width=canvas.shape;scores=[-1.]*10
        for angle in (-12,-6,0,6,12):
            rotated=cv2.warpAffine(canvas,cv2.getRotationMatrix2D((width/2,height/2),angle,1),
                                   (width,height),flags=cv2.INTER_LINEAR,borderValue=0)
            glyph=normalize_glyph(rotated)
            if glyph is None:continue
            padded=cv2.copyMakeBorder(glyph,2,2,2,2,cv2.BORDER_CONSTANT,value=0)
            for digit,template in self.reader.samples:
                score=float(cv2.matchTemplate(padded,template,cv2.TM_CCOEFF_NORMED).max())
                scores[digit]=max(scores[digit],score)
        order=np.argsort(scores);best,runner=int(order[-1]),int(order[-2])
        margin=scores[best]-scores[runner]
        if scores[best]<self.reader.min_score or margin<self.reader.min_margin:return None
        return best,scores[best],margin

    @staticmethod
    def _glyph_geometry(stats, width, height, require_border=True):
        """Shared glyph geometry, with a real border for accepted targets.

        Solid/oversized background is not a second character. A visibly
        clipped neighbour can still veto a multi-digit fragment; it may
        not become an accepted target itself. No score/identity relaxation.
        """
        x,y,w,h,area=map(int,stats)
        geometry=(40<=h<=height-4 and 7<=w<=width*.65 and .08<=w/h<=1.05
                  and .10<=area/(w*h)<=.85)
        return geometry and (not require_border or
                             (min(x,y)>=2 and x+w<=width-2 and y+h<=height-2))

    def detect(self,frame_bgr,target_class=None):
        started=time.monotonic();self.pages=[];out=[];self._roll_fallbacks=0
        rejected=dict(geometry=0,neighbour=0,surround=0,template=0,ambiguous=0)
        if frame_bgr is None or frame_bgr.ndim!=3:return out
        height,width=frame_bgr.shape[:2]
        gray=cv2.cvtColor(frame_bgr,cv2.COLOR_BGR2GRAY)
        # Two photometric hypotheses; deduplicate ONLY agreeing current ink.
        # Both preserve the connected glyph and reject frame-touching strokes.
        masks=[cv2.threshold(gray,0,255,cv2.THRESH_BINARY_INV+cv2.THRESH_OTSU)[1],
               cv2.morphologyEx((gray<115).astype(np.uint8)*255,cv2.MORPH_CLOSE,
                                np.ones((3,3),np.uint8))]
        found=[]
        for ink in masks:
            count,labels,stats,_=cv2.connectedComponentsWithStats(ink)
            for index,(x,y,w,h,area) in enumerate(stats[1:],1):
                x,y,w,h,area=map(int,(x,y,w,h,area))
                # Need a real background border, not an arbitrary 6px reserve.
                # Field 500mm frame has a COMPLETE zero 4px above the edge.
                # Any ink touching the image edge is still rejected.
                if not self._glyph_geometry(stats[index],width,height):
                    rejected['geometry']+=1;continue
                # Reject multi-glyph text such as "12"; do not call its last
                # character a standalone target number. Separate cards may
                # still be read when their large glyphs are well separated.
                adjacent=False
                for j,(nx,ny,nw,nh,na) in enumerate(stats[1:],1):
                    if j==index or nh<40 or not .5<h/nh<2 or na<nh*3:continue
                    if not self._glyph_geometry(stats[j],width,height,require_border=False):continue
                    overlap=max(0,min(y+h,ny+nh)-max(y,ny))
                    gap=max(0,max(x,nx)-min(x+w,nx+nw))
                    if overlap>.5*min(h,nh) and gap<.45*max(h,nh):adjacent=True;break
                if adjacent:rejected['neighbour']+=1;continue
                # Require a light surround, not a black monitor/texture hole.
                pad=max(5,round(h*.12));x0=max(0,x-pad);x1=min(width,x+w+pad)
                y0=max(0,y-pad);y1=min(height,y+h+pad)
                patch=gray[y0:y1,x0:x1]
                surround=np.ones(patch.shape,bool)
                surround[y-y0:y-y0+h,x-x0:x-x0+w]=False
                glyph=(labels[y:y+h,x:x+w]==index).astype(np.uint8)*255
                # Exposure may put the whole readable card below130. Require
                # a genuinely lighter surround relative to CURRENT dark ink,
                # retaining the same70% spatial support, not a fixed brightness.
                foreground=gray[y:y+h,x:x+w][glyph!=0]
                threshold=float(np.median(foreground))+25
                if not surround.any() or np.mean(patch[surround]>threshold)<.70:
                    rejected['surround']+=1;continue
                result=self._classify_current(glyph)
                if result is None:rejected['template']+=1;continue
                digit,score,margin=result
                found.append((digit,score,margin,(x,y,w,h)))
        paper_quads=[];paper_reads=0
        # A clear raw glyph stays on the fast path. Expensive page recovery is
        # reserved for missing/marginal reads, keeping camera latency bounded.
        if self._paper_enabled and (not found or max(v[1] for v in found)<.91):
            for quad,page,inverse in paper_views(frame_bgr):
                paper_quads.append(quad.round(1).tolist())
                if self._paper_reader is None:
                    self._paper_reader=PrintedDigitDetector({'_paper_enabled':False})
                    self._paper_reader.reader=self.reader
                # Keep nearly the entire page, including any neighbouring
                # character; only remove the observed paper boundary itself.
                for view in (page,illumination_view(page)):
                    roi=view[5:-5,5:-5]
                    reads=self._paper_reader.detect(roi)
                    if len(reads)!=1:continue
                    d=reads[0]
                    if not (45<d.y2-d.y1<245 and 38<(d.x1+d.x2)/2<162
                            and 45<(d.y1+d.y2)/2<245):continue
                    points=np.float32([[d.x1+5,d.y1+5],[d.x2+5,d.y1+5],
                                       [d.x2+5,d.y2+5],[d.x1+5,d.y2+5]])
                    points=cv2.perspectiveTransform(points[None],inverse)[0]
                    lo=points.min(axis=0);hi=points.max(axis=0)
                    # Inverse-mapped ink also needs a true image border.
                    if min(lo)<2 or hi[0]>width-2 or hi[1]>height-2:continue
                    meta=self._paper_reader.pages[0]
                    found.append((d.class_id-CLASS_BASE,d.confidence,meta['margin'],
                                  (float(lo[0]),float(lo[1]),float(hi[0]-lo[0]),float(hi[1]-lo[1]))))
                    paper_reads+=1
        groups=[]
        for item in found:
            _,_,_,(x,y,w,h)=item
            group=None
            for g in groups:
                gx,gy,gw,gh=g[0][3]
                inter=max(0,min(x+w,gx+gw)-max(x,gx))*max(0,min(y+h,gy+gh)-max(y,gy))
                if inter/max(1,w*h+gw*gh-inter)>.65:group=g;break
            if group is None:groups.append([item])
            else:group.append(item)
        for group in groups:
            if len({g[0] for g in group})!=1:rejected['ambiguous']+=1;continue
            digit,score,margin,(x,y,w,h)=max(group,key=lambda g:g[1])
            d=Detection(CLASS_BASE+digit,NAMES[CLASS_BASE+digit],score,
                        float(x),float(y),float(x+w),float(y+h),width,height,'printed_digit_template')
            d.a4_glyph_bbox=(x,y,w,h)
            out.append(d)
            self.pages.append(dict(digit=digit,class_id=CLASS_BASE+digit,score=score,margin=margin,
                visibility='current_intact_digit',glyph_bbox=(x,y,w,h),physical_size_verified=False,
                range_basis='none; no paper dimensions or cached range'))
        self.status=dict(detector_backend='a4_digits',detector_revision=self.revision,
            detector_ms=round((time.monotonic()-started)*1000,1),detector_passes=2,
            digit_rejections=rejected,digit_roll_fallbacks=self._roll_fallbacks,
            paper_assist_quads=paper_quads,paper_assist_reads=paper_reads,
            near_bottle_mode=False,a4_pages=self.pages,
            a4_scope='CURRENT intact digits0-9; optional observed paper rectification/illumination; no required full page or range inference')
        return out
