#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""l2_check.py —— 道莅 L2 真编译闸（RuSTy / plc.exe 驱动）

用法:
    python l2_check.py <file.st> [file2.st ...]        # 逐件 --check
    python l2_check.py --sample 20                     # registry 随机抽 20 件
    python l2_check.py --sample 20 --seed 71 --out _gate_L2.json
    python l2_check.py --jobs 4 <files...>             # 指定并行进程数
    python l2_check.py --no-cache <files...>           # 强制重建接口预筛缓存
    python l2_check.py --batch-dir DL_Base             # 整目录批编译

原理:
    1. RuSTy 不内建 IEC 标准件声明 → 恒定附加 iec_std_stub.st（{external} 声明桩）。
    2. 组件间依赖（I_DL_* 接口 / 他件内定义的 ENUM）→ 依据报错里的
       "Unknown type: X" 自动回溯：先补全部 I_DL_*.st，再按类型名在库内定位
       定义文件追加，最多 3 轮。
    3. 只做 --check（不生成目标码），不修改任何源文件。

性能设计（v1.2，2026-11-23）:
    - 接口预筛结果按「接口文件 mtime+size 哈希」落盘缓存，命中即跳过 21 次
      试编译（原每次固定 3.1 秒开销）→ 单件 6.5 秒降到 2.25 秒，约 2.9 倍。
    - **默认串行（jobs=1）**。实测 RuSTy 多进程并发不安全：同批 40 件
      串行 30 PASS/10 FAIL，并行 14 PASS/26 FAIL，凭空产生 16 个
      「E004 Ambiguous callable symbol」假阳性（疑共享临时目录/全局缓存竞争）。
      并行仅作调试用途，且必须在报告中标注「结果不可信」。
    - 判定口径永久串行，保证 L2 结论可复现、可审计。

退出码: 0 全过 / 1 有失败 / 2 环境不可用
"""
import glob
import hashlib
import json
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed

LIB = r"C:\Library"
RUSTY = os.path.join(LIB, "_tools", "rusty", "plc.exe")
STUB = os.path.join(LIB, "_tools", "rusty", "iec_std_stub.st")
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
CACHE = os.path.join(LIB, "_tools", "rusty", ".iface_cache.json")
CACHE_VER = "v1"

# ---- 子进程工作副本（由 initializer 注入，避免每件都 pickle 整个 registry）----
_W = {"reg": None, "ifaces": None}


def _init_worker(reg, ifaces):
    _W["reg"] = reg
    _W["ifaces"] = ifaces


def load_registry():
    with open(REG, encoding="utf-8") as f:
        return json.load(f)


def _iface_fingerprint(cand):
    """接口文件集指纹：路径 + mtime + size，任一接口改动即失效。"""
    parts = []
    for fp in sorted(cand):
        try:
            st = os.stat(fp)
            parts.append("%s|%d|%d" % (os.path.basename(fp), int(st.st_mtime), st.st_size))
        except OSError:
            parts.append("%s|0|0" % os.path.basename(fp))
    raw = (CACHE_VER + "\n" + "\n".join(parts)).encode("utf-8")
    return hashlib.sha1(raw).hexdigest()


def _scan_iface_files():
    cand = []
    for root, _dirs, files in os.walk(LIB):
        if "_tools" in root or "_Staging_Raw" in root or "_archive" in root:
            continue
        for fn in files:
            if fn.startswith("I_DL_") and fn.endswith(".st"):
                cand.append(os.path.join(root, fn))
    return sorted(cand)


STUB_DIR = os.path.join(LIB, "_tools", "rusty", "_iface_stubs")
ALL_TYPES = os.path.join(STUB_DIR, "_all_types.st")


def _check_ok(paths):
    """预筛用：一组文件能否一起通过 --check。"""
    try:
        p = subprocess.run([RUSTY, "--check", STUB] + list(paths), capture_output=True,
                           text=True, timeout=120, encoding="utf-8", errors="ignore")
        return p.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def all_interfaces(use_cache=True, force=False):
    """返回 (可用依赖文件, 被排除文件)。

    优先使用 iface_stub_gen.py 生成的**降级桩**（_iface_stubs/）：
    RuSTy 不支持 INTERFACE 内 PROPERTY/METHOD，直接纳入原接口会毒化整批；
    降级桩保留全部 ENUM/TYPE 与变量语义，是唯一能让依赖接口的 FB 通过编译的路径。
    桩目录不存在时回退到「原接口逐件预筛」的旧逻辑。

    结果按指纹缓存，接口未变动时零成本。
    """
    use_stubs = os.path.isdir(STUB_DIR) and os.path.exists(ALL_TYPES)
    if use_stubs:
        cand = [ALL_TYPES] + sorted(glob.glob(os.path.join(STUB_DIR, "I_DL_*.st")))
    else:
        cand = _scan_iface_files()

    key = ("stub" if use_stubs else "raw") + ":" + _iface_fingerprint(cand)

    if use_cache and not force:
        try:
            with open(CACHE, encoding="utf-8") as f:
                c = json.load(f)
            if c.get("key") == key:
                good = [p for p in c.get("good", []) if os.path.exists(p)]
                exc = [p for p in c.get("excluded", []) if os.path.exists(p)]
                if len(good) + len(exc) == len(cand):
                    return good, exc
        except (OSError, ValueError):
            pass

    good, excluded = [], []
    if use_stubs:
        # 全局类型文件必须可用，否则整体不可信
        if not _check_ok([ALL_TYPES]):
            excluded.append(ALL_TYPES)
        else:
            good.append(ALL_TYPES)
            for fp in cand[1:]:
                (good if _check_ok([ALL_TYPES, fp]) else excluded).append(fp)
    else:
        for fp in cand:
            (good if _check_ok([fp]) else excluded).append(fp)

    if use_cache:
        try:
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w", encoding="utf-8") as f:
                json.dump({"key": key, "ver": CACHE_VER, "mode": "stub" if use_stubs else "raw",
                           "good": good, "excluded": excluded}, f, ensure_ascii=False, indent=1)
        except OSError:
            pass
    return good, excluded


def find_def_file(type_name, reg):
    """按组件名直查 registry；未命中再按 `X : TYPE` / `TYPE X` 定义形态全库扫描。"""
    for comp in reg["components"]:
        if comp.get("name") == type_name:
            fp = comp.get("file_path") or ""
            if fp.endswith(".st") and os.path.exists(fp):
                return fp
    pat = re.compile(r"(^\s*%s\s*:|TYPE\s+%s\b)" % (re.escape(type_name), re.escape(type_name)))
    for comp in reg["components"]:
        fp = comp.get("file_path") or ""
        if not fp.endswith(".st") or not os.path.exists(fp):
            continue
        try:
            with open(fp, encoding="utf-8", errors="ignore") as f:
                if pat.search(f.read()):
                    return fp
        except OSError:
            continue
    return None


def run_check(target, deps):
    cmd = [RUSTY, "--check", "--error-format", "clang", STUB] + deps + [target]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120,
                           encoding="utf-8", errors="ignore")
    except subprocess.TimeoutExpired:
        return 99, "TIMEOUT"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def check_one(target, reg, ifaces):
    # 目标自身若同时在依赖集里（如接口降级桩既作目标又作依赖），必须剔除，
    # 否则同一 FUNCTION_BLOCK 声明两次 → E004 Ambiguous callable symbol。
    ta = os.path.abspath(target)
    deps = [f for f in ifaces if os.path.abspath(f) != ta]
    rc, out = run_check(target, deps)
    rounds = 0
    while rc != 0 and rounds < 3:
        missing = set(re.findall(r"Unknown type:\s*([A-Za-z_][A-Za-z0-9_]*)", out))
        missing |= set(re.findall(r"Could not resolve reference to\s+([A-Za-z_][A-Za-z0-9_]*)", out))
        added = False
        for t in missing:
            fp = find_def_file(t, reg)
            if fp and fp not in deps and fp != target:
                deps.append(fp)
                added = True
        if not added:
            break
        rc, out = run_check(target, deps)
        rounds += 1
    first = ""
    m = re.search(r"error\[(E\d+)\]:\s*([^\n]*)", out)
    if m:
        first = "%s %s" % (m.group(1), m.group(2).strip()[:90])
    return {"file": target, "name": os.path.basename(target), "rc": rc,
            "pass": rc == 0, "first_error": first, "dep_rounds": rounds,
            "dep_count": max(0, len(deps) - len(ifaces))}


def _worker_check(target):
    """进程池入口：只传路径，registry/ifaces 由 initializer 注入。"""
    return check_one(target, _W["reg"], _W["ifaces"])


def run_batch(targets, reg, ifaces, jobs=1):
    """按 jobs 并行检查；jobs<=1 时退回串行（便于调试）。结果按输入顺序返回。"""
    if jobs <= 1 or len(targets) <= 1:
        return [check_one(t, reg, ifaces) for t in targets]

    results = {}
    with ProcessPoolExecutor(max_workers=jobs, initializer=_init_worker,
                             initargs=(reg, ifaces)) as ex:
        fut = {ex.submit(_worker_check, t): t for t in targets}
        done = 0
        for f in as_completed(fut):
            t = fut[f]
            try:
                results[t] = f.result()
            except Exception as e:  # 子进程异常不得吞掉目标
                results[t] = {"file": t, "name": os.path.basename(t), "rc": 98,
                              "pass": False, "first_error": "WORKER_%s %s" % (
                                  type(e).__name__, str(e)[:60]),
                              "dep_rounds": 0, "dep_count": 0}
            done += 1
            if len(targets) > 20 and done % 20 == 0:
                print("  ... %d/%d" % (done, len(targets)), flush=True)
    return [results[t] for t in targets]


def main():
    args = sys.argv[1:]
    if not os.path.exists(RUSTY) or not os.path.exists(STUB):
        print("L2 环境不可用: 缺 plc.exe 或 iec_std_stub.st")
        return 2
    reg = load_registry()
    targets, seed, out_path, sample = [], 0, None, 0
    jobs = 1  # 默认串行：RuSTy 并发不安全（实测产生 16 个 E004 假阳性）
    use_cache, force_cache, batch_dir = True, False, None

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sample":
            sample = int(args[i + 1]); i += 2; continue
        if a == "--seed":
            seed = int(args[i + 1]); i += 2; continue
        if a == "--out":
            out_path = args[i + 1]; i += 2; continue
        if a == "--jobs":
            jobs = max(1, int(args[i + 1])); i += 2; continue
        if a == "--no-cache":
            use_cache = False; i += 1; continue
        if a == "--refresh-cache":
            force_cache = True; i += 1; continue
        if a == "--batch-dir":
            batch_dir = args[i + 1]; i += 2; continue
        targets.append(a); i += 1

    if batch_dir:
        d = batch_dir if os.path.isabs(batch_dir) else os.path.join(LIB, batch_dir)
        targets += sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".st"))
    if sample:
        pool = [c["file_path"] for c in reg["components"]
                if (c.get("file_path") or "").endswith(".st") and os.path.exists(c.get("file_path"))]
        random.seed(seed)
        targets = random.sample(pool, min(sample, len(pool)))
    if not targets:
        print("无目标文件")
        return 2

    # 目标若是 I_DL_*.st，改用降级桩：RuSTy 不支持 INTERFACE 内 PROPERTY/METHOD，
    # 原文件必然 E006/E007（编译器缺口，非代码缺陷）。桩与源同名，报告不易混淆。
    subbed = 0
    if os.path.isdir(STUB_DIR):
        for idx, t in enumerate(targets):
            base = os.path.basename(t)
            if base.startswith("I_DL_"):
                cand = os.path.join(STUB_DIR, base)
                if os.path.exists(cand):
                    targets[idx] = cand
                    subbed += 1
    if subbed:
        print("接口目标 %d 个已切换为降级桩（INTERFACE PROPERTY/METHOD 为 RuSTy 硬缺口）"
              % subbed)

    ifaces, iface_excluded = all_interfaces(use_cache=use_cache, force=force_cache)
    print("接口预筛: 可用 %d / 排除(PROPERTY 等覆盖面缺口) %d | 并行 %d 进程 | 缓存 %s"
          % (len(ifaces), len(iface_excluded), jobs,
             "命中" if use_cache and not force_cache else "重建"))
    if jobs > 1:
        print("⚠ 警告: jobs>1 时 RuSTy 并发会产生 E004 假阳性，本批结果不可信，仅供调试。")

    res = run_batch(targets, reg, ifaces, jobs)
    npass = sum(1 for r in res if r["pass"])
    for r in res:
        if not r["pass"]:
            print("FAIL %-40s %s" % (r["name"], r["first_error"]))
    print("PASS=%d FAIL=%d TOTAL=%d" % (npass, len(res) - npass, len(res)))
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump({"total": len(res), "pass": npass, "fail": len(res) - npass,
                       "seed": seed, "jobs": jobs,
                       "iface_excluded": [os.path.basename(x) for x in iface_excluded],
                       "results": res}, f, ensure_ascii=False, indent=1)
        print("written", out_path)
    return 0 if npass == len(res) else 1


if __name__ == "__main__":
    sys.exit(main())
