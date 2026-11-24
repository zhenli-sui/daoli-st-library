#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""audit_r46.py —— R46 轮 20 件编码窗口专用机检（只扫本轮清单，不碰 check_r46.py）

口径来源：
  G1~G6 直接复用 compile_gate_v0.gate_file（R45/R46 已固化口径，不另立第二套正则）
  F1~F8 为 R46 本轮新增口径：
    F1 CRLF 行尾（禁孤立 LF）
    F2 头注释必备字段（组件/功能/边界/v1.0.0/2026-11-19）
    F3 声明行同行双语注释（VAR..END_VAR 内每条声明必须有 //）
    F4 ENUM 成员必须带 ":=" 赋值（历史教训：单冒号）
    F5 CASE 必须含 ELSE（红线 6）
    F6 禁省字（同上/见上/同前/略）
    F7 TON/R_TRIG 实例数 > 0 时须有段 0 无条件调用痕迹（实例名后跟 "("）
    F8 名称与文件名一致（首行 component 名 == 文件名）
用法： python audit_r46.py 1 5    # 扫清单第 1~5 件
       python audit_r46.py 0 20   # 全扫
"""
import io, os, re, sys, json
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
OUTDIR = os.path.join(ROOT, "_Staging_Raw", "2026-11-19")

MANIFEST = [
    ("FB_DL_AxisLoadEncoderLossMonitor", "DL_Motion"),
    ("FB_DL_AxisEncoderPulseLostScore", "DL_Motion"),
    ("FC_DL_IntCeilDiv", "DL_Base"),
    ("FB_DL_WatchdogPulseMon", "DL_Base"),
    ("FC_DL_StdDevOnline", "DL_MathData"),
    ("FB_DL_AxisFeedbackFailoverSeq", "DL_Motion"),
    ("FB_DL_GantrySkewMonitor", "DL_Motion"),
    ("FB_DL_StribeckFrictionComp", "DL_Algo"),
    ("FB_DL_LoadCellTareDrift", "DL_Device"),
    ("FB_DL_TabWeldingMonitor", "DL_Process"),
    ("FB_DL_CamFollowerLagMonitor", "DL_Motion"),
    ("FB_DL_LuenbergerObserver", "DL_Algo"),
    ("FB_DL_TcChannelScanDiag", "DL_Device"),
    ("FB_DL_CellSortingBin", "DL_Process"),
    ("FC_DL_MedianAbsDev", "DL_MathData"),
    ("FB_DL_RlsEstimator", "DL_Algo"),
    ("FB_DL_AdaptiveLeadLag", "DL_Algo"),
    ("FB_DL_GripperForceVerify", "DL_Device"),
    ("FB_DL_ModulePottingVac", "DL_Process"),
    ("FB_DL_PackHousingTighten", "DL_Process"),
]

VAR_OPEN = re.compile(r"^VAR(\s+CONSTANT|\s+(INPUT|OUTPUT|IN_OUT|TEMP|STAT))?\s*$", re.I)
DECL = re.compile(r"^[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*:\s*\S.*$")


def check_file(path, name):
    iss = []
    raw = io.open(path, "rb").read()
    src = raw.decode("utf-8", "replace")
    # ---- F1 CRLF ----
    if re.search(rb"(?<!\r)\n", raw):
        iss.append("F1 行尾非 CRLF（存在孤立 LF）")
    if not src.strip():
        return ["F0 空文件"], src

    lines = src.split("\r\n") if "\r\n" in src else src.split("\n")

    # ---- F2 头注释 ----
    head = "\n".join(lines[:60])
    for key, tag in (("组件名称", "组件名称"), ("功能描述", "功能描述"),
                     ("边界", "边界"), ("v1.0.0", "版本 v1.0.0"), ("2026-11-19", "日期")):
        if key not in head:
            iss.append("F2 头注释缺字段：%s" % tag)

    # ---- F3 声明行同行注释 ----
    in_var, bad_decl = False, []
    for i, ln in enumerate(lines, 1):
        t = ln.strip()
        if VAR_OPEN.match(t):
            in_var = True
            continue
        if t.upper().startswith("END_VAR"):
            in_var = False
            continue
        if not in_var or not t or t.startswith("//") or t.startswith("(*"):
            continue
        if DECL.match(t) and "//" not in t:
            bad_decl.append(i)
    if bad_decl:
        iss.append("F3 声明缺同行注释，行号 %s" % ",".join(map(str, bad_decl[:10])))

    # ---- F4 ENUM 成员带 := ----
    in_type, bad_enum = False, []
    for i, ln in enumerate(lines, 1):
        t = ln.strip()
        if re.match(r"^TYPE\b", t, re.I):
            in_type = True
            continue
        if re.match(r"^END_TYPE\b", t, re.I):
            in_type = False
            continue
        if in_type and re.match(r"^[A-Za-z_]\w*\s*$", t):
            if t.upper() in ("STRUCT", "END_STRUCT", "UNION", "END_UNION"):
                continue          # 结构体关键字非枚举成员，不计入
            bad_enum.append(i)
    if bad_enum:
        iss.append("F4 枚举成员缺 := 赋值，行号 %s" % ",".join(map(str, bad_enum[:10])))

    # ---- F5 CASE 含 ELSE ----
    ncase = 0
    for i, ln in enumerate(lines):
        if re.match(r"^CASE\b", ln.strip(), re.I):
            ncase += 1
            has_else = False
            for j in range(i + 1, len(lines)):
                s = lines[j].strip()
                if re.match(r"^END_CASE\b", s, re.I):
                    break
                if re.match(r"^ELSE\b", s, re.I):
                    has_else = True
            if not has_else:
                iss.append("F5 CASE 缺 ELSE 兜底，行号 %d" % (i + 1))

    # ---- F6 禁省字 ----
    for w in ("同上", "见上", "同前", "略。"):
        if w in src:
            iss.append("F6 出现省字表述：%s" % w)

    # ---- F7 实例无条件调用痕迹 ----
    for inst in set(re.findall(r"^\s{4}((?:ton|tof|rt|ft)[A-Z]\w*)\s*:\s*(?:TON|TOF|R_TRIG|F_TRIG);",
                               src, re.M)):
        if not re.search(r"\b%s\s*\(" % re.escape(inst), src):
            iss.append("F7 实例 %s 声明后未见调用" % inst)

    # ---- F8 名称与文件一致 ----
    m = re.search(r"组件名称 \(Component\)\s*:\s*([A-Za-z0-9_]+)", head)
    if m and m.group(1) != name:
        iss.append("F8 头注释组件名 %s 与文件名 %s 不一致" % (m.group(1), name))

    # ---- G1~G6 复用既有闸 ----
    _s, giss = gate_file(path)
    iss.extend(giss)
    return iss, src


def main():
    a = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    b = int(sys.argv[2]) if len(sys.argv) > 2 else len(MANIFEST)
    rows, npass, tot_lines = [], 0, 0
    for idx in range(a, min(b, len(MANIFEST))):
        name, cat = MANIFEST[idx]
        path = os.path.join(ROOT, cat, name + ".st")
        if not os.path.exists(path):
            rows.append({"n": idx + 1, "name": name, "cat": cat, "path": path,
                         "lines": 0, "issues": ["F0 文件不存在"], "pass": False})
            continue
        iss, src = check_file(path, name)
        nl = len(src.strip().splitlines())
        tot_lines += nl
        ok = not iss
        npass += 1 if ok else 0
        rows.append({"n": idx + 1, "name": name, "cat": cat, "path": path,
                     "lines": nl, "issues": iss, "pass": ok})
    for r in rows:
        print("[%s] %2d %-36s %-12s %4d 行" % ("PASS" if r["pass"] else "FAIL",
                                               r["n"], r["name"], r["cat"], r["lines"]))
        for x in r["issues"]:
            print("      - %s" % x)
    print("\n== 批次 %d~%d：PASS %d/%d ，行数合计 %d ==" % (a + 1, min(b, len(MANIFEST)),
                                                          npass, len(rows), tot_lines))
    fp = os.path.join(OUTDIR, "_audit_r46_%02d_%02d.json" % (a + 1, min(b, len(MANIFEST))))
    try:
        json.dump(rows, io.open(fp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    except Exception as e:
        print("(json 落盘跳过：%s)" % e)
    return 0 if npass == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
