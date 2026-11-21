# -*- coding: utf-8 -*-
"""matic_runner.py - MatIEC 编译/解析门（L2）

设计：
  - 优先用 iec2iec（MatIEC 的解析器，只需 POU 定义，不需要 PROGRAM）做语法/语义解析；
  - 有 iec2c 时可用 --compile 做代码生成级编译；
  - 两者都没有 → 明确输出 pending-ci，绝不用 L1 通过冒充 L2 通过。

用法：
    set IEC_PARSER=C:\\tools\\matiec\\iec2iec.exe
    python matic_runner.py --manifest _Staging_Raw\\2026-11-21\\_compile_R65.json
    python matic_runner.py --all --round R64-BASELINE
退出码：0 全通过（或 pending）、1 有失败
"""
import argparse, glob, io, json, os, re, subprocess, sys, datetime

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw")

def find_bin(name, env):
    p = os.environ.get(env)
    if p and os.path.exists(p): return p
    for c in (name, name + ".exe"):
        from shutil import which
        w = which(c)
        if w: return w
    return None

ERR = re.compile(r"(?:error|Error|ERROR)\s*[:\-]?\s*(.*)")

def run_one(bin_path, f, timeout=90):
    try:
        r = subprocess.run([bin_path, f], capture_output=True, text=True, timeout=timeout)
        msg = (r.stderr or "") + (r.stdout or "")
        errs = [m.group(0) for m in ERR.finditer(msg)]
        ok = (r.returncode == 0) and not errs
        return ok, errs[:5], msg[-800:]
    except subprocess.TimeoutExpired:
        return False, ["timeout %ss" % timeout], ""
    except Exception as e:
        return False, [str(e)], ""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--round", default="MANUAL")
    ap.add_argument("--compile", action="store_true", help="用 iec2c 做代码生成级编译")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    parser = find_bin("iec2iec", "IEC_PARSER")
    compiler = find_bin("iec2c", "IEC_COMPILER")
    bin_path = compiler if (a.compile and compiler) else (parser or compiler)
    if a.compile and not compiler:
        print("ie2c not found -> fallback to parser")

    files = []
    if a.manifest:
        m = json.load(open(a.manifest, encoding="utf-8"))
        files = [os.path.join(LIB, f) for f in m["files"]]
    else:
        files = sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
    if a.limit: files = files[:a.limit]

    if not bin_path:
        out = {"round": a.round, "l2": {"mode": "pending-ci", "queued": len(files),
               "reason": "本机无 iec2iec/iec2c（无 gcc/bison/docker，WSL 被策略禁用）"}}
        p = os.path.join(STG, datetime.date.today().isoformat(), "_compile_%s.json" % a.round)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        json.dump(out, io.open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("L2 SKIPPED (pending CI): %d files queued -> %s" % (len(files), p))
        return 0

    fail = []
    for i, f in enumerate(files, 1):
        ok, errs, tail = run_one(bin_path, f)
        if not ok:
            fail.append({"file": os.path.relpath(f, LIB).replace("\\", "/"), "errors": errs})
            print("  FAIL %s  %s" % (os.path.relpath(f, LIB), errs[:2]))
        if i % 100 == 0: print("  ... %d/%d" % (i, len(files)))

    out = {"round": a.round, "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "l2": {"mode": "iec2c" if (a.compile and compiler) else "iec2iec",
                  "total": len(files), "pass": len(files) - len(fail), "fail": len(fail)},
           "failing": fail}
    p = os.path.join(STG, datetime.date.today().isoformat(), "_compile_%s.json" % a.round)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(out, io.open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("L2 %s: %d/%d PASS, fail=%d -> %s" % (out["l2"]["mode"], out["l2"]["pass"], len(files), len(fail), p))
    return 1 if fail else 0

if __name__ == "__main__":
    sys.exit(main())
