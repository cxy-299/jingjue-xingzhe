"""No model/camera/serial: real CUDA forward/backward preflight."""
import json
from pathlib import Path
import torch
import ultralytics


def main():
    if not torch.cuda.is_available():raise RuntimeError('CUDA not available')
    device=torch.cuda.get_device_properties(0)
    x=torch.randn(128,128,device='cuda',requires_grad=True)
    (x@x.T).square().mean().backward()
    torch.cuda.synchronize()
    assert torch.isfinite(x.grad).all().item()
    report=dict(torch=torch.__version__,ultralytics=ultralytics.__version__,
        cuda_version=torch.version.cuda,gpu=device.name,total_bytes=device.total_memory,
        capability=torch.cuda.get_device_capability(0),arch_list=torch.cuda.get_arch_list(),
        forward_backward_passed=True)
    p=Path('output/board/bottle_training_20261030/gpu_preflight.json')
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(report,indent=2),encoding='utf8')
    print(json.dumps(report),flush=True)


if __name__=='__main__':main()
