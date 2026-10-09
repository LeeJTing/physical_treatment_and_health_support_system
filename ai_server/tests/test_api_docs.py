"""docs/openapi.json is the API contract shared with the app and with Jun Ting's modules: it must match
the code (run export_openapi.py after changing an endpoint)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import export_openapi  # noqa: E402


def test_openapi_file_is_up_to_date():
    assert export_openapi.OUT.read_text(encoding="utf-8") == export_openapi.spec_text(), \
        "docs/openapi.json is out of date: run  python export_openapi.py"
