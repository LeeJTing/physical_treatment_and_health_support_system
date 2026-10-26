"""Writes docs/openapi.json, the machine-readable API contract (the same as /openapi.json and /docs
on a running server), so it can be read without starting the server. Re-run after changing an
endpoint; tests/test_api_docs.py fails while it is out of date.

    .venv\Scripts\python export_openapi.py
"""
import json
from pathlib import Path

from app.main import app

OUT = Path(__file__).with_name("docs") / "openapi.json"


def spec_text() -> str:
    return json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(spec_text(), encoding="utf-8")
    print(f"wrote {OUT}")
