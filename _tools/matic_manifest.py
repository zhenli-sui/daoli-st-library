# -*- coding: utf-8 -*-
"""matic_manifest.py - 生成 MatIEC 编译清单（CI 的输入契约）

用法：
    python matic_manifest.py --all --round R65
    python matic_manifest.py --changed-only --round R65 --hours 3
输出：
    C:\\Library\\_Staging_Raw\\<日期>\\_compile_<round>.json
"""
import argparse, glob, io, json, os, datetime

# 库根目录解析：环境变量 > 脚本父目录（含 DL_Base 时）> C:\Library —— Linux CI 兼容
_here = os.path.dirname(os.path.abspath(__file__))
_parent = os.path.dirname(_here)
if os.environ.get("DAOLI_LIB"):
    LIB = os.environ["DAOLI_LIB"]
elif os.path.isdir(os.path.join(_parent, "DL_Base")):
    LIB = _parent
else:
    LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--changed-only", action="store_true")
    ap.add_argument("--hours", type=float, default=3.0)
    ap.add_argument("--round", default="MANUAL")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
    if a.changed_only:
        cut = datetime.datetime.now().timestamp() - a.hours * 3600
        files = [f for f in files if os.path.getmtime(f) >= cut]
    reg_p = os.path.join(LIB, "INDEX_REGISTRY.json")
    expected = None
    if os.path.exists(reg_p):
        expected = json.load(open(reg_p, encoding="utf-8")).get("total_components")
    out = {
        "round": a.round,
        "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "expected": expected,
        "count": len(files),
        "files": [os.path.relpath(f, LIB).replace("\\", "/") for f in files],
        "mode": "iec2iec-parse+iec2c-compile",
        "note": "本地无 gcc/bison，L2 由 GitHub Actions 执行；本清单为 CI 输入契约",
    }
    p = os.path.join(STG, datetime.date.today().isoformat(), "_compile_%s.json" % a.round)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(out, io.open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("manifest: %d files (expected %s) -> %s" % (len(files), expected, p))

if __name__ == "__main__":
    main()
