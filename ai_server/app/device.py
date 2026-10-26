"""Where a model runs: TORCH_DEVICE in .env (config.py). "auto" uses the GPU when torch can see one
(Elwin's PC: RTX 3050, CUDA build of torch) and the CPU otherwise; "cpu" or "cuda" force it.

For new, heavier models (e.g. food recognition): model.to(torch_device()), and the inputs too.
MediaPipe always runs on the CPU (its Python package has no GPU support on Windows), and the posture
models stay on the CPU on purpose: about 5 ms per clip, the GPU would save 4 ms of a 5.6 s request and
results could differ in the last digits between machines.
"""
from functools import lru_cache

from .config import get_settings


@lru_cache
def torch_device() -> str:
    want = get_settings().torch_device.strip().lower()
    if want in ("cpu", "cuda"):
        return want
    try:
        import torch
    except ImportError:
        return "cpu"
    return "cuda" if torch.cuda.is_available() else "cpu"
