"""Architecture check of lib/ (9 Oct). Rules from CLAUDE.md, the software architecture diagram and the
Chapter 4 class tables:
  * View: no repositories, shared client, Supabase or http; it may use the result types that live in a
    service folder (ChatReply, Recommendation, PlanIssue) but never calls a service.
  * ViewModel: no views, no concrete repositories, no shared client, no BuildContext. Repository
    interfaces are allowed: the class tables give ViewModels repository fields (Table 4.44 authRepo,
    4.50 repo, 4.52 repo) and Chapter 4 says "TreatmentViewModel calls ITreatmentRepository".
  * Service: no views, ViewModels or concrete repositories.
  * Repository interface: entities only. Only main.dart names a concrete repository.
  * Services and repositories return Future<Result<T>> and never throw; LocalNotificationService and
    PoseEstimationService.validateVideo keep the return types of Tables 4.75 and 4.76.
  * provider + ChangeNotifier only; every folder under lib/ has a desc.txt.
The "forbidden layer import" list therefore shows the allowed ViewModel -> repository interface and
View -> service result type imports too; anything else in it is a real problem.

    python tool/check_architecture.py
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
PKG = "package:physical_treatment_and_health_support_system/"


def layer(rel: str) -> str:
    if rel == "main.dart":
        return "main"
    if rel.startswith("view/"):
        return "view"
    if rel.startswith("viewmodel/"):
        return "viewmodel"
    if rel.startswith("model/business_logic/"):
        return "service"
    if rel.startswith("model/repository/"):
        name = rel.rsplit("/", 1)[-1]
        if name.startswith("i_"):
            return "repo_iface"
        return "repo_impl"
    if rel.startswith("model/"):
        return "entity"
    if rel.startswith("shared_client/"):
        return "shared_client"
    if rel.startswith("device_platform/"):
        return "device"
    if rel.startswith("core/"):
        return "core"
    return "other"


FORBIDDEN = {
    "view": {"service", "repo_iface", "repo_impl", "shared_client"},
    "viewmodel": {"view", "repo_iface", "repo_impl", "shared_client"},
    "service": {"view", "viewmodel", "repo_impl"},
    "repo_iface": {"view", "viewmodel", "service", "repo_impl", "shared_client", "device"},
    "repo_impl": {"view", "viewmodel", "service"},
    "entity": {"view", "viewmodel", "service", "repo_iface", "repo_impl", "shared_client", "device"},
    "shared_client": {"view", "viewmodel", "service", "repo_iface", "repo_impl", "device"},
    "device": {"view", "viewmodel", "repo_iface", "repo_impl", "shared_client"},
    "core": {"viewmodel", "service", "repo_iface", "repo_impl", "shared_client"},
}
FORBIDDEN_PKGS = {
    "view": ["package:supabase_flutter", "package:http/"],
    "viewmodel": ["package:supabase_flutter", "package:http/"],
    "service": ["package:supabase_flutter"],
    "repo_iface": ["package:supabase_flutter", "package:http/"],
    "entity": ["package:supabase_flutter", "package:http/", "package:flutter/material.dart"],
}

files = sorted(LIB.rglob("*.dart"))
problems = defaultdict(list)
counts = defaultdict(int)
for f in files:
    rel = f.relative_to(LIB).as_posix()
    lay = layer(rel)
    counts[lay] += 1
    src = f.read_text(encoding="utf-8")
    for m in re.finditer(r"^\s*(?:import|export)\s+'([^']+)'", src, re.M):
        target = m.group(1)
        if target.startswith(PKG):
            tl = layer(target[len(PKG):])
        elif target.startswith("package:") or target.startswith("dart:"):
            for bad in FORBIDDEN_PKGS.get(lay, []):
                if target.startswith(bad):
                    problems["forbidden package"].append(f"{rel} ({lay}) imports {target}")
            continue
        else:
            tl = layer((f.parent / target).resolve().relative_to(LIB.resolve()).as_posix())
        if tl in FORBIDDEN.get(lay, set()):
            problems["forbidden layer import"].append(f"{rel} ({lay}) -> {target} ({tl})")
    if lay == "viewmodel" and re.search(r"\bBuildContext\b", src):
        problems["BuildContext in ViewModel"].append(rel)
    if lay in ("service", "repo_impl", "repo_iface") and rel.split("/")[-1] != "supabase_guard.dart":
        for m in re.finditer(r"^\s*(?!return\b)(Future<(?!Result<)[^\n]*?>)\s+([a-z]\w*)\s*\(", src, re.M):
            problems["Future not Result"].append(f"{rel}: {m.group(1)} {m.group(2)}(")
        for m in re.finditer(r"^\s*(?:Stream<[^\n]*?>)\s+([a-z]\w*)\s*\(", src, re.M):
            problems["Stream method (check)"].append(f"{rel}: {m.group(0).strip()[:80]}")
        for i, line in enumerate(src.splitlines(), 1):
            if re.search(r"\bthrow\b", line) and not line.strip().startswith("//") and "rethrow" not in line:
                problems["throw in service/repository"].append(f"{rel}:{i}: {line.strip()[:90]}")
    if lay != "main":
        for m in re.finditer(r"\b((?:Supabase|Fake)\w+Repository)\b", src):
            name = m.group(1)
            own = rel.split("/")[-1].replace(".dart", "").replace("_", "")
            if name.lower() != own.lower():
                problems["concrete repository named outside main.dart"].append(f"{rel}: {name}")

pub = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
for bad in ("riverpod", "flutter_bloc", "bloc:", "freezed", "json_serializable", "build_runner", "get_it", "getx"):
    if bad in pub:
        problems["forbidden dependency"].append(bad)

for d in sorted(p for p in LIB.rglob("*") if p.is_dir()):
    rel = d.relative_to(LIB).as_posix()
    if rel.count("/") >= 1 and not (d / "desc.txt").exists() and not rel.endswith("widgets") and not rel.startswith("l10n"):
        problems["folder without desc.txt"].append(rel)

print("files per layer:", dict(counts))
for k, v in problems.items():
    uniq = sorted(set(v))
    print(f"\n## {k}: {len(uniq)}")
    for x in uniq[:40]:
        print("  ", x)
if not problems:
    print("no problems found")
