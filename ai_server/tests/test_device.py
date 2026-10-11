"""TORCH_DEVICE: auto picks the GPU only when torch sees one; cpu / cuda force it."""
import torch

from app import device
from app.config import Settings


def pick(monkeypatch, value):
    monkeypatch.setattr(device, "get_settings", lambda: Settings(torch_device=value))
    device.torch_device.cache_clear()
    try:
        return device.torch_device()
    finally:
        device.torch_device.cache_clear()


def test_auto_follows_what_torch_sees(monkeypatch):
    assert pick(monkeypatch, "auto") == ("cuda" if torch.cuda.is_available() else "cpu")


def test_forced(monkeypatch):
    assert pick(monkeypatch, "CPU") == "cpu"
    assert pick(monkeypatch, "cuda") == "cuda"
