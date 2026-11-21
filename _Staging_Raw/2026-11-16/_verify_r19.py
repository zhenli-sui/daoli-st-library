#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
_verify_r19.py —— R19 派单前码位 / 重名实测校验（R58/R61 纪律：源码为唯一事实源）

用法：python _verify_r19.py
判据：
  1) 20 个候选码位在既有 304 个 .st 中 CLASH 必须为空
  2) 20 个新组件名与 INDEX_REGISTRY.json 的 name + 物理文件名交集必须为空
  3) 打印各段游标实测（信息级 / 故障级下一可用）
"""
import json
import os
import re
import glob
import collections

ROOT = r"C:\Library"

# R19 锁定的 20 件 × 5 槽（信息2 + 故障3），按 ROUND_PLAN_R19 §4 总账
PLAN = {
    "FC_DL_DintMsToTod":         ("0001", ["0400", "0401", "031E", "031F", "0320"]),
    "FC_DL_TimeRatioCalc":       ("0001", ["0402", "0403", "0321", "0322", "0323"]),
    "FC_DL_RatioToPwrDb":        ("0001", ["0404", "0405", "0324", "0325", "0326"]),
    "FC_DL_LintToUdintSat":      ("0001", ["0406", "0407", "0327", "0328", "0329"]),
    "FB_DL_BitShiftRegister":    ("0001", ["0408", "0409", "032A", "032B", "032C"]),
    "FC_DL_ModbusRtuFrameCheck": ("0001", ["040A", "040B", "032D", "032E", "032F"]),
    "FB_DL_FlowSqrtExtract":     ("0002", ["2701", "2702", "2710", "2711", "2712"]),
    "FB_DL_RatioController":     ("0002", ["2801", "2802", "2810", "2811", "2812"]),
    "FB_DL_LeadLagCompensator":  ("0002", ["2901", "2902", "2910", "2911", "2912"]),
    "FB_DL_AutoTuneRelay":       ("0002", ["2A01", "2A02", "2A10", "2A11", "2A12"]),
    "FB_DL_DeviceHealthArbiter": ("0003", ["016A", "016B", "0330", "0331", "0332"]),
    "FB_DL_ProfinetAlarmDiag":   ("0003", ["016C", "016D", "0333", "0334", "0335"]),
    "FB_DL_EscChuckCurrentMonitor": ("0003", ["016E", "016F", "0336", "0337", "0338"]),
    "FB_DL_DeviceParamWrite":    ("0003", ["0170", "0171", "0339", "033A", "033B"]),
    "FB_DL_ExternalEncoderScaler": ("0004", ["01CD", "01CE", "02DE", "02DF", "02E0"]),
    "FB_DL_CamPhaseTrim":        ("0004", ["01CF", "01D0", "02E1", "02E2", "02E3"]),
    "FB_DL_FilmWebCenter":       ("0004", ["01D1", "01D2", "02E4", "02E5", "02E6"]),
    "FB_DL_WindingLayerCounter": ("0004", ["01D3", "01D4", "02E7", "02E8", "02E9"]),
    "FB_DL_DrumLevelThreeElem":  ("0005", ["01D6", "01D7", "0305", "0306", "0307"]),
    "FB_DL_VacCupRingCtrl":      ("0005", ["01D8", "01D9", "0308", "0309", "030A"]),
}

CODE_RE = re.compile(r"16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})")


def scan_codes():
    occ = collections.defaultdict(lambda: collections.defaultdict(set))
    files = sorted(glob.glob(os.path.join(ROOT, "DL_*", "*.st")))
    for f in files:
        txt = open(f, encoding="utf-8", errors="ignore").read()
        base = os.path.basename(f)
        for seg, code in CODE_RE.findall(txt):
            occ[seg.upper()][int(code, 16)].add(base)
    return occ, files


def main():
    occ, files = scan_codes()
    print("physical .st files = %d" % len(files))

    # 1) 码位 CLASH
    clash_all = []
    per_seg = collections.defaultdict(list)
    for name, (seg, codes) in PLAN.items():
        for c in codes:
            per_seg[seg].append(c)
            v = int(c, 16)
            if v in occ.get(seg, {}):
                clash_all.append((name, seg, c, sorted(occ[seg][v])))
    for seg in sorted(per_seg):
        cs = per_seg[seg]
        print("seg %s n=%d unique=%d CLASH=%s"
              % (seg, len(cs), len(set(cs)),
                 [x for x in clash_all if x[1] == seg]))
    print("TOTAL CLASH =", len(clash_all))

    # 2) 段游标实测
    for seg in ("0001", "0002", "0003", "0004", "0005"):
        v = sorted(occ.get(seg, {}))
        if not v:
            print("seg %s : EMPTY" % seg)
            continue
        info = [x for x in v if x < 0x300]
        fault = [x for x in v if x >= 0x300]
        print("seg %s : info max=%s fault max=%s"
              % (seg, "%04X" % max(info) if info else "----",
                 "%04X" % max(fault) if fault else "----"))

    # 3) 0001 信息级 02xx 满溢实测（R65 依据）
    v1 = occ.get("0001", {})
    band02 = sorted(x for x in v1 if 0x200 <= x <= 0x2FF)
    holes = [x for x in range(0x245, 0x290) if x not in v1]
    print("0001 band02 count=%d max=%04X ; holes in 0245~028F = %d"
          % (len(band02), max(band02) if band02 else 0, len(holes)))

    # 4) 名称查重
    reg = json.load(open(os.path.join(ROOT, "INDEX_REGISTRY.json"), encoding="utf-8"))
    reg_names = {c["name"] for c in reg["components"]}
    file_names = {os.path.splitext(os.path.basename(f))[0] for f in files}
    dup_reg = sorted(set(PLAN) & reg_names)
    dup_file = sorted(set(PLAN) & file_names)
    print("name dup vs registry: %s" % dup_reg)
    print("name dup vs files: %s" % dup_file)
    print("registry total=%d version=%s" % (reg["total_components"], reg["version"]))

    ok = (not clash_all) and (not dup_reg) and (not dup_file)
    print("RESULT =", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
