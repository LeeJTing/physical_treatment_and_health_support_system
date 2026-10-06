"""Colour and camera augmentation of the recorded clips, applied to the VIDEO before the pose
detector runs, so the training data covers other outfits, rooms and lighting.

With one person in one outfit, the classifier would otherwise only ever see landmarks that
MediaPipe found on a maroon T-shirt in one room. Each variant changes the pixels:
  * outfit: hue/saturation of the clothes only (MediaPipe multiclass selfie segmenter; skin
    and hair keep their colour),
  * room: hue/brightness of everything except the person,
  * lighting: brightness, contrast, gamma; camera noise and blur,
  * camera: mirror (left-right), small rotation and zoom.
Body points are then extracted from the changed frames and cached next to the originals:
training/data/cache/<pose_key>/aug/<clip stem>__aug<N>.npz. build_dataset.py picks them up.

    ai_server\\.venv\\Scripts\\python training\\augment.py [pose_key ...] [--variants 4] [--workers 4] [--preview]

Frames are shrunk to WORK_WIDTH first (the pose model looks at 256 px anyway and its
landmarks are normalised, so this changes nothing but speed).

--preview only writes before/after pictures to training/reports/augmentation/ (fast).
"""
import argparse
import math
import random
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

from common import CACHE, REPORTS, own_clips
from app.pose import landmarks

# Multiclass selfie segmenter: 0 background, 1 hair, 2 body skin, 3 face skin, 4 clothes, 5 other.
WORK_WIDTH = 960
SEG_MODEL = Path(landmarks.__file__).resolve().parents[2] / "models" / "weights" / "selfie_multiclass_256x256.tflite"


@dataclass
class Variant:
    person_hue: int = 0          # OpenCV hue units (0-179), added to the person
    person_sat: float = 1.0
    bg_hue: int = 0
    bg_value: float = 1.0
    brightness: float = 1.0
    contrast: float = 1.0
    gamma: float = 1.0
    mirror: bool = False
    rotate: float = 0.0          # degrees
    scale: float = 1.0
    noise: float = 0.0           # std of gaussian noise, 0-255 scale
    blur: int = 0                # kernel size (odd), 0 = none

    def describe(self) -> str:
        parts = []
        if self.person_hue or self.person_sat != 1:
            parts.append(f"outfit hue {self.person_hue * 2:+d} deg, saturation x{self.person_sat:.1f}")
        if self.bg_hue or self.bg_value != 1:
            parts.append(f"room hue {self.bg_hue * 2:+d} deg, brightness x{self.bg_value:.1f}")
        if self.brightness != 1 or self.contrast != 1 or self.gamma != 1:
            parts.append(f"light x{self.brightness:.2f}, contrast x{self.contrast:.2f}, gamma {self.gamma:.2f}")
        if self.mirror:
            parts.append("mirrored")
        if self.rotate or self.scale != 1:
            parts.append(f"rotate {self.rotate:+.1f} deg, zoom x{self.scale:.2f}")
        if self.noise or self.blur:
            parts.append(f"noise {self.noise:.0f}, blur {self.blur}")
        return "; ".join(parts) or "original"


def variants_for(clip_name: str, n: int) -> list[Variant]:
    """n fixed recipes per clip, randomised within each recipe's range (seeded by the clip name)."""
    rng = random.Random(clip_name)
    recipes = [
        lambda: Variant(person_hue=rng.choice([30, 45, 60, 75, 90, 105, 120]), person_sat=rng.uniform(0.7, 1.3),
                        bg_hue=rng.randint(-20, 20), bg_value=rng.uniform(0.75, 1.1)),
        lambda: Variant(mirror=True, person_hue=rng.choice([-60, -45, -30, 135, 150]), brightness=rng.uniform(0.6, 0.85),
                        gamma=rng.uniform(1.1, 1.4)),
        lambda: Variant(person_sat=rng.uniform(0.2, 0.5), contrast=rng.uniform(1.15, 1.35),
                        rotate=rng.uniform(-6, 6), scale=rng.uniform(0.85, 0.95), noise=rng.uniform(6, 12)),
        lambda: Variant(person_hue=rng.choice([20, 40, 140, 160]), bg_hue=rng.randint(5, 15), bg_value=rng.uniform(0.9, 1.2),
                        brightness=rng.uniform(1.05, 1.2), blur=rng.choice([3, 5]), mirror=rng.random() < 0.5),
    ]
    return [recipes[i % len(recipes)]() for i in range(n)]


class Augmenter:
    def __init__(self):
        import mediapipe as mp  # noqa: F401
        from mediapipe.tasks.python import vision
        from mediapipe.tasks.python.core.base_options import BaseOptions

        self._seg = vision.ImageSegmenter.create_from_options(vision.ImageSegmenterOptions(
            base_options=BaseOptions(model_asset_path=str(SEG_MODEL)), output_confidence_masks=True))
        self.dev = "cuda" if torch.cuda.is_available() else "cpu"
        self.gen = torch.Generator(device=self.dev).manual_seed(0)

    def masks(self, bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(clothes, room) soft masks in 0..1, each HxWx1."""
        import mediapipe as mp

        res = self._seg.segment(mp.Image(image_format=mp.ImageFormat.SRGB,
                                         data=np.ascontiguousarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))))
        m = [res.confidence_masks[i].numpy_view() for i in (0, 4)]
        m = [cv2.GaussianBlur(np.squeeze(x).astype(np.float32), (0, 0), 2)[..., None] for x in m]  # soft edge
        return m[1], m[0]

    def apply(self, bgr: np.ndarray, v: Variant) -> np.ndarray:
        return self.apply_many(bgr, [v])[0]

    def apply_many(self, bgr: np.ndarray, variants: list[Variant]) -> list[np.ndarray]:
        """All variants of one frame: segmentation once (MediaPipe, CPU only on Windows), then
        the colour and camera changes on the GPU with PyTorch."""
        if bgr.shape[1] > WORK_WIDTH:
            bgr = cv2.resize(bgr, (WORK_WIDTH, round(bgr.shape[0] * WORK_WIDTH / bgr.shape[1])), interpolation=cv2.INTER_AREA)
        clothes, room_m = (torch.from_numpy(m[..., 0]).to(self.dev) for m in self.masks(bgr))
        rest = (1 - clothes - room_m).clamp(0, 1)            # skin and hair: unchanged
        norm = (clothes + room_m + rest).clamp_min(1e-6)
        rgb = torch.from_numpy(bgr[..., ::-1].copy()).to(self.dev).permute(2, 0, 1).float() / 255
        h0, s0, v0 = _rgb_to_hsv(rgb)
        H, W = rgb.shape[1:]
        outs = []
        for v in variants:
            cloth = _hsv_to_rgb((h0 + v.person_hue / 180) % 1, (s0 * v.person_sat).clamp(0, 1), v0)
            room = _hsv_to_rgb((h0 + v.bg_hue / 180) % 1, s0, (v0 * v.bg_value).clamp(0, 1))
            out = (cloth * clothes + room * room_m + rgb * rest) / norm
            out = ((out - 0.5) * v.contrast + 0.5) * v.brightness
            out = out.clamp(0, 1)
            if v.gamma != 1:
                out = out ** v.gamma
            if v.noise:
                out = out + torch.randn(out.shape, device=self.dev, generator=self.gen) * (v.noise / 255)
            out = out.clamp(0, 1)
            if v.blur:
                out = _gaussian_blur(out, v.blur)
            if v.rotate or v.scale != 1:
                a = math.radians(v.rotate)
                c, sn = math.cos(a) / v.scale, math.sin(a) / v.scale
                theta = torch.tensor([[c, -sn * H / W, 0], [sn * W / H, c, 0]], device=self.dev, dtype=torch.float32)
                grid = F.affine_grid(theta[None], (1, 3, H, W), align_corners=False)
                out = F.grid_sample(out[None], grid, padding_mode="border", align_corners=False)[0]
            if v.mirror:
                out = out.flip(2)
            outs.append(np.ascontiguousarray((out * 255).round().byte().permute(1, 2, 0).cpu().numpy()[..., ::-1]))
        return outs


def _rgb_to_hsv(rgb):
    r, g, b = rgb
    mx, _ = rgb.max(0)
    mn, _ = rgb.min(0)
    d = mx - mn
    safe = d.clamp_min(1e-6)
    h = torch.where(mx == r, ((g - b) / safe) % 6, torch.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4))
    h = torch.where(d > 0, h / 6, h * 0)
    return h, d / mx.clamp_min(1e-6), mx


def _hsv_to_rgb(h, s, v):
    k = torch.stack([(n + h * 6) % 6 for n in (5, 3, 1)])
    return v - v * s * torch.clamp(torch.minimum(k, 4 - k), 0, 1)


def _gaussian_blur(img, k):
    sigma = 0.3 * ((k - 1) * 0.5 - 1) + 0.8                  # OpenCV's default for a k x k kernel
    x = torch.arange(k, device=img.device, dtype=img.dtype) - (k - 1) / 2
    g = torch.exp(-x ** 2 / (2 * sigma ** 2))
    g = g / g.sum()
    img = F.pad(img[None], (k // 2, k // 2, k // 2, k // 2), mode="replicate")
    img = F.conv2d(img, g.view(1, 1, 1, k).repeat(3, 1, 1, 1), groups=3)
    return F.conv2d(img, g.view(1, 1, k, 1).repeat(3, 1, 1, 1), groups=3)[0]


def aug_cache(clip, k: int) -> Path:
    return CACHE / clip.key / "aug" / f"{clip.path.stem}__aug{k}.npz"


def preview(aug: Augmenter, clips, n_variants: int):
    out = REPORTS / "augmentation"
    out.mkdir(parents=True, exist_ok=True)
    seen = set()
    for clip in clips:
        if clip.key in seen:
            continue
        seen.add(clip.key)
        cap = cv2.VideoCapture(str(clip.path))
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(cap.get(cv2.CAP_PROP_FRAME_COUNT) * 0.4))
        ok, frame = cap.read()
        cap.release()
        if not ok:
            continue
        tiles = [frame] + [aug.apply(frame, v) for v in variants_for(clip.path.name, n_variants)]
        th = 300
        tiles = [cv2.resize(t, (int(t.shape[1] * th / t.shape[0]), th)) for t in tiles]
        cols = 3 if len(tiles) > 4 else len(tiles)
        rows = math.ceil(len(tiles) / cols)
        tw = max(t.shape[1] for t in tiles)
        grid = np.full((rows * th, cols * tw, 3), 245, np.uint8)
        for i, t in enumerate(tiles):
            r, c = divmod(i, cols)
            grid[r * th:(r + 1) * th, c * tw:c * tw + t.shape[1]] = t
            cv2.putText(grid, "original" if i == 0 else f"variant {i}", (c * tw + 8, r * th + 26),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.imwrite(str(out / f"{clip.key}.jpg"), grid, [cv2.IMWRITE_JPEG_QUALITY, 85])
        print("  preview", out / f"{clip.key}.jpg")


_worker_aug = None


def _extract(job):
    """All missing variants of one clip in one pass, in a worker process (own segmenter and GPU context)."""
    global _worker_aug
    path, items = job                                  # items: [(cache path, Variant)]
    if _worker_aug is None:
        _worker_aug = Augmenter()
    seqs = landmarks.extract_many(Path(path), len(items), lambda f: _worker_aug.apply_many(f, [v for _, v in items]))
    done = []
    for (cache, v), seq in zip(items, seqs):
        Path(cache).parent.mkdir(parents=True, exist_ok=True)
        landmarks.save(seq, Path(cache))
        done.append((Path(cache).name, v, seq.detected_ratio))
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*")
    ap.add_argument("--variants", type=int, default=4)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    clips = [c for c in own_clips(a.keys or None) if c.name_ok and not c.problems]
    if a.preview:
        preview(Augmenter(), clips, a.variants)
        return
    todo = [(c, k, v) for c in clips for k, v in enumerate(variants_for(c.path.name, a.variants), 1)
            if not aug_cache(c, k).exists()]
    print(f"{len(clips)} clips x {a.variants} variants: {len(todo)} to extract")
    per_clip: dict[str, list] = {}
    for c, k, v in todo:
        per_clip.setdefault(str(c.path), []).append((str(aug_cache(c, k)), v))
    i = 0
    with ProcessPoolExecutor(a.workers) as pool:
        for fut in as_completed([pool.submit(_extract, job) for job in per_clip.items()]):
            for name, v, det in fut.result():
                i += 1
                print(f"[{i}/{len(todo)}] {name}: {v.describe()}; person found in {det:.0%} of frames", flush=True)


if __name__ == "__main__":
    main()
