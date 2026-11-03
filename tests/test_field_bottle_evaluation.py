from scripts.evaluate_field_bottle import score_frame, summarize


def pred(box,confidence=.9):return dict(box=box,confidence=confidence)


def test_duplicate_prediction_and_wrong_position_do_not_inflate_recall():
    r=score_frame([pred([10,10,30,40]),pred([10,10,30,40],.8),pred([60,60,80,90])],
                  [[10,10,30,40],[70,10,90,40]],100)
    assert (r['tp'],r['fp'],r['fn'])==(1,2,1)


def test_confidence_order_and_one_to_one_matching_center_error():
    r=score_frame([pred([12,10,32,40]),pred([70,10,90,40])],[[10,10,30,40],[70,10,90,40]],100)
    assert (r['tp'],r['fp'],r['fn'])==(2,0,0)
    assert r['center_abs_error_fraction']==[.02,0]


def test_empty_frame_metrics_and_missing_bottle_frame():
    neg=dict(truth=[],predictions=[pred([1,1,2,2])],inference_ms=2,
             **score_frame([pred([1,1,2,2])],[],100))
    pos=dict(truth=[[1,1,2,2]],predictions=[],inference_ms=4,**score_frame([],[[1,1,2,2]],100))
    s=summarize([neg,pos])
    assert s['negative_images']==1 and s['negative_images_with_false_positive']==1
    assert s['positive_frames_without_any_bottle']==1 and s['recall']==0
    assert s['host_median_inference_ms']==3
