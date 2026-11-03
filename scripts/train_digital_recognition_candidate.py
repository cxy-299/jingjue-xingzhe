"""Offline fine-tune the supplied lightweight digit CNN; never deploys or touches hardware."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import random
import sys
import time
import urllib.request
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import cv2
import h5py
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ZIP = Path(
    r"D:\software\wechat\information\xwechat_files\wxid_oil8wdq3ms9h22_59d1"
    r"\temp\RWTemp\2026-10\471e3b432a40825d3f3b6ca362876551\DigitalRecognition(2).zip"
)
DEFAULT_OUT = ROOT / "output/board/digital_recognition_round1_20261031"
DEFAULT_NEAR_URL = "http://192.168.137.129:8080/snapshot-raw.jpg"


class DigitNet(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 4, 3, padding=1, bias=False)
        self.conv2 = nn.Conv2d(4, 4, 3, padding=1, bias=False)
        self.conv3 = nn.Conv2d(4, 8, 3, padding=1, bias=False)
        self.conv4 = nn.Conv2d(8, 8, 3, padding=1, bias=False)
        self.conv5 = nn.Conv2d(8, 16, 3, padding=1, bias=False)
        self.conv6 = nn.Conv2d(16, 16, 3, padding=1, bias=False)
        self.dense = nn.Linear(16, 11, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = torch.relu(self.conv1(x))
        x = torch.relu(self.conv2(x))
        x = nn.functional.max_pool2d(x, 2)
        x = torch.relu(self.conv3(x))
        x = torch.relu(self.conv4(x))
        x = nn.functional.max_pool2d(x, 2)
        x = torch.relu(self.conv5(x))
        x = torch.relu(self.conv6(x))
        return self.dense(x.amax((2, 3)))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_h5_weights(model: DigitNet, data: bytes, rescaled: bool = False) -> None:
    with h5py.File(io.BytesIO(data), "r") as f:
        names = ["conv1", "conv2", "conv3", "conv4", "conv5", "conv6"]
        for name in names:
            arr = f[f"model_weights/{name}/{name}/kernel"][()]
            getattr(model, name).weight.data.copy_(
                torch.from_numpy(arr.transpose(3, 2, 0, 1).copy())
            )
        dense_name = "dense_1" if rescaled else "dense"
        arr = f[f"model_weights/{dense_name}/{dense_name}/kernel"][()]
        model.dense.weight.data.copy_(torch.from_numpy(arr.T.copy()))


def camera_preprocess(frame: np.ndarray) -> np.ndarray:
    """Match a00_common_functions.prepare_image_from_camera exactly."""
    if frame.shape[:2] != (240, 320):
        frame = cv2.resize(frame, (320, 240), interpolation=cv2.INTER_AREA)
    crop = frame[8:-8, 48:-48]
    if crop.ndim == 2:
        gray = crop.astype(np.uint8)
    else:
        b, g, r = (crop[:, :, i].astype(np.uint16) for i in range(3))
        gray = ((3 * b + 8 * g + 5 * r) // 16).astype(np.uint8)
    return np.asarray(
        [
            [int(gray[y * 8 : (y + 1) * 8, x * 8 : (x + 1) * 8].mean()) for x in range(28)]
            for y in range(28)
        ],
        dtype=np.uint8,
    )


def collect_images(zf: zipfile.ZipFile, split: str) -> tuple[list[np.ndarray], list[int]]:
    prefix = f"DigitalRecognition/dataset/{split}/"
    files = sorted(n for n in zf.namelist() if n.startswith(prefix) and n.lower().endswith(".png"))
    images: list[np.ndarray] = []
    labels: list[int] = []
    for name in files:
        label = int(name.split("/")[-2])
        image = cv2.imdecode(np.frombuffer(zf.read(name), np.uint8), cv2.IMREAD_GRAYSCALE)
        if image is None:
            raise RuntimeError(f"cannot decode {name}")
        if split == "test":
            image = camera_preprocess(image)
        elif image.shape != (28, 28):
            raise RuntimeError(f"unexpected train image shape {name}: {image.shape}")
        images.append(image)
        labels.append(label)
    if not images:
        raise RuntimeError(f"no {split} images in supplied archive")
    return images, labels


def stratified_split(labels: list[int], seed: int = 20261031) -> tuple[list[int], list[int]]:
    rng = random.Random(seed)
    by_class: dict[int, list[int]] = {}
    for i, label in enumerate(labels):
        by_class.setdefault(label, []).append(i)
    train: list[int] = []
    val: list[int] = []
    for label in sorted(by_class):
        indexes = by_class[label][:]
        rng.shuffle(indexes)
        n_val = max(1, round(0.2 * len(indexes)))
        val.extend(indexes[:n_val])
        train.extend(indexes[n_val:])
    rng.shuffle(train)
    rng.shuffle(val)
    return train, val


class AugmentedDigits(Dataset):
    def __init__(self, images: list[np.ndarray], labels: list[int], augment: bool):
        self.images = images
        self.labels = labels
        self.augment = augment

    def __len__(self) -> int:
        return len(self.labels)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, torch.Tensor]:
        image = self.images[index].copy()
        label = self.labels[index]
        if self.augment:
            angle = random.uniform(-7.0, 7.0)
            scale = random.uniform(0.88, 1.12)
            dx, dy = random.uniform(-2.0, 2.0), random.uniform(-2.0, 2.0)
            matrix = cv2.getRotationMatrix2D((13.5, 13.5), angle, scale)
            matrix[:, 2] += (dx, dy)
            image = cv2.warpAffine(
                image, matrix, (28, 28), flags=cv2.INTER_LINEAR,
                borderMode=cv2.BORDER_CONSTANT, borderValue=255,
            )
            contrast = random.uniform(0.85, 1.15)
            brightness = random.uniform(-22.0, 22.0)
            image = np.clip(image.astype(np.float32) * contrast + brightness, 0, 255)
            if random.random() < 0.18:
                image = cv2.GaussianBlur(image, (3, 3), random.uniform(0.15, 0.7))
            if random.random() < 0.2:
                image += np.random.normal(0, random.uniform(1.0, 5.0), image.shape)
            image = np.clip(image, 0, 255).astype(np.uint8)
        tensor = torch.from_numpy(image.astype(np.float32)[None] / 256.0)
        return tensor, torch.tensor(label, dtype=torch.long)


def evaluate(model: DigitNet, images: list[np.ndarray], labels: list[int], device: torch.device) -> dict:
    x = torch.from_numpy(np.stack(images).astype(np.float32)[:, None] / 256.0).to(device)
    y = np.asarray(labels, dtype=np.int64)
    model.eval()
    with torch.no_grad():
        logits = model(x)
        probs = torch.softmax(logits, dim=1).cpu().numpy()
        loss = float(nn.functional.cross_entropy(logits, torch.from_numpy(y).to(device)).item())
    pred = probs.argmax(1)
    recalls = {
        str(c): float(np.mean(pred[y == c] == c))
        for c in sorted(set(labels))
    }
    return {
        "count": len(labels),
        "accuracy": float(np.mean(pred == y)),
        "balanced_accuracy": float(np.mean(list(recalls.values()))),
        "cross_entropy": loss,
        "per_class_recall": recalls,
        "background_false_positive_count": int(np.sum((y == 10) & (pred != 10))),
        "confusions": [
            {"truth": int(a), "predicted": int(b), "count": int(n)}
            for (a, b), n in Counter((int(a), int(b)) for a, b in zip(y, pred) if a != b).most_common()
        ],
        "predictions": [
            {"truth": int(a), "predicted": int(b), "confidence": float(probs[i, b])}
            for i, (a, b) in enumerate(zip(y, pred))
        ],
    }


def fetch_near_sample(url: str | None, timeout: float) -> tuple[np.ndarray | None, bytes | None]:
    if not url:
        return None, None
    with urllib.request.urlopen(url, timeout=timeout) as response:
        raw = response.read()
        if response.status != 200:
            raise RuntimeError(f"read-only snapshot returned HTTP {response.status}")
    frame = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise RuntimeError("cannot decode read-only camera snapshot")
    return camera_preprocess(frame), raw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--near-url", default=DEFAULT_NEAR_URL)
    parser.add_argument("--near-label", type=int, default=0)
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--near-repeat", type=int, default=5,
                        help="How many copies of the one labeled near frame enter the fit split.")
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        raise RuntimeError(f"refusing to overwrite non-empty output directory: {out}")
    out.mkdir(parents=True, exist_ok=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    seed = 20261031
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(seed)
    torch.set_num_threads(1)

    zip_bytes = args.zip.read_bytes()
    zip_sha = sha256_bytes(zip_bytes)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        model_path = "DigitalRecognition/weights/keras_model_low_weights_digit_detector.h5"
        h5_bytes = zf.read(model_path)
        train_images, train_labels = collect_images(zf, "train")
        test_images, test_labels = collect_images(zf, "test")

    xfer, near_bytes = fetch_near_sample(args.near_url, 5.0)
    run_info = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "status": "RUNNING",
        "hardware_access": False,
        "production_deployment": False,
        "service_restart": False,
        "zip_path": str(args.zip),
        "zip_sha256": zip_sha,
        "base_weights_sha256": sha256_bytes(h5_bytes),
        "dataset_counts": {"train": dict(Counter(map(str, train_labels))), "test": dict(Counter(map(str, test_labels)))},
        "near_sample": None if near_bytes is None else {
            "source": "read-only snapshot-raw.jpg",
            "label": args.near_label,
            "raw_sha256": sha256_bytes(near_bytes),
            "capture_bytes": len(near_bytes),
            "annotation_basis": "user-supplied live scene visibly shows the printed 0",
        },
        "seed": seed,
        "epochs_requested": args.epochs,
        "near_repeat": args.near_repeat,
        "device": str(device),
    }
    report_path = out / "training_report.json"
    report_path.write_text(json.dumps(run_info, ensure_ascii=False, indent=2), encoding="utf-8")
    if near_bytes is not None:
        (out / "near_sample_raw.jpg").write_bytes(near_bytes)

    train_ix, val_ix = stratified_split(train_labels, seed)
    val_images = [train_images[i] for i in val_ix]
    val_labels = [train_labels[i] for i in val_ix]
    fit_images = [train_images[i] for i in train_ix]
    fit_labels = [train_labels[i] for i in train_ix]
    if xfer is not None:
        # Repeated views of one hard case are deliberately few; this is not a generalization claim.
        fit_images.extend([xfer] * max(0, args.near_repeat))
        fit_labels.extend([args.near_label] * max(0, args.near_repeat))

    counts = Counter(fit_labels)
    sample_weights = torch.DoubleTensor([1.0 / counts[label] for label in fit_labels])
    sampler = WeightedRandomSampler(sample_weights, num_samples=len(fit_labels), replacement=True)
    loader = DataLoader(
        AugmentedDigits(fit_images, fit_labels, augment=True),
        batch_size=32, sampler=sampler, num_workers=0,
    )
    model = DigitNet()
    load_h5_weights(model, h5_bytes)
    model.to(device)
    baseline_val = evaluate(model, val_images, val_labels, device)
    baseline_test = evaluate(model, test_images, test_labels, device)
    near_before = None if xfer is None else evaluate(model, [xfer], [args.near_label], device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=4e-5, weight_decay=1e-5)
    best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
    best_key = (baseline_val["balanced_accuracy"], -baseline_val["cross_entropy"])
    best_epoch = 0
    stale = 0
    history = []

    try:
        for epoch in range(1, args.epochs + 1):
            model.train()
            running_loss = 0.0
            seen = 0
            for xb, yb in loader:
                xb, yb = xb.to(device), yb.to(device)
                optimizer.zero_grad(set_to_none=True)
                loss = nn.functional.cross_entropy(model(xb), yb)
                loss.backward()
                nn.utils.clip_grad_norm_(model.parameters(), 2.0)
                optimizer.step()
                running_loss += float(loss.detach()) * len(yb)
                seen += len(yb)
            val_metrics = evaluate(model, val_images, val_labels, device)
            row = {
                "epoch": epoch,
                "train_loss": running_loss / max(seen, 1),
                "val_accuracy": val_metrics["accuracy"],
                "val_balanced_accuracy": val_metrics["balanced_accuracy"],
                "val_cross_entropy": val_metrics["cross_entropy"],
            }
            history.append(row)
            print(json.dumps(row), flush=True)
            key = (row["val_balanced_accuracy"], -row["val_cross_entropy"])
            if key > best_key:
                best_key = key
                best_epoch = epoch
                best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
                stale = 0
            else:
                stale += 1
            if stale >= 8:
                break
    except Exception as exc:
        run_info.update(status="FAILED", error=repr(exc), ended_utc=datetime.now(timezone.utc).isoformat())
        report_path.write_text(json.dumps(run_info, ensure_ascii=False, indent=2), encoding="utf-8")
        raise

    model.load_state_dict(best_state)
    # Test partition is evaluated only after choosing a checkpoint from the train-only validation split.
    candidate_test = evaluate(model, test_images, test_labels, device)
    near_after = None if xfer is None else evaluate(model, [xfer], [args.near_label], device)
    checkpoint = out / "candidate_state.pt"
    torch.save({"state_dict": best_state, "classes": list(range(11)), "input": "28x28 grayscale / 256"}, checkpoint)
    run_info.update(
        status="COMPLETE",
        ended_utc=datetime.now(timezone.utc).isoformat(),
        train_split_counts={"fit": dict(Counter(map(str, fit_labels))), "validation": dict(Counter(map(str, val_labels)))},
        best_epoch=best_epoch,
        history=history,
        baseline_validation=baseline_val,
        baseline_test=baseline_test,
        candidate_test=candidate_test,
        near_case_before=near_before,
        near_case_after_training_sample=near_after,
        candidate_state_sha256=sha256_bytes(checkpoint.read_bytes()),
        decision="REVIEW_REQUIRED_NOT_DEPLOYED",
        test_scope="153 images bundled with supplied archive; test partition not used for training or checkpoint selection",
        limitation="Only one additional live near-frame labeled 0; not evidence of generalization to other distances, digits, lighting, or Pi deployment.",
    )
    report_path.write_text(json.dumps(run_info, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "status": run_info["status"],
        "best_epoch": best_epoch,
        "baseline_test_accuracy": baseline_test["accuracy"],
        "candidate_test_accuracy": candidate_test["accuracy"],
        "baseline_near_top": near_before["predictions"][0] if near_before else None,
        "candidate_near_top": near_after["predictions"][0] if near_after else None,
        "candidate_state_sha256": run_info["candidate_state_sha256"],
        "output": str(out),
    }, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
