# -*- coding: utf-8 -*-
"""R24 MANUAL 增量生成：从本轮 22 件头注释/声明区提取引脚契约，追加至五本子库 MANUAL。
追加式增量，不改历史节。"""
import re, io, os

BASE = "C:/Library/"
ITEMS = {  # sublib -> [POU 名]
 "DL_MathData": ["FC_DL_Affine2DCompose", "FC_DL_Affine2Apply", "FC_DL_FanLawRootCalc"],
 "DL_Algo":     ["FB_DL_GasDensityComp", "FC_DL_WetBulbTempCalc"],
 "DL_Device":   ["FB_DL_StepperMicroFeedPulseEquiv", "FB_DL_PumpDryRunGuard",
                 "FB_DL_CoilFrostWindow", "FB_DL_ElectrolyteMoistureGuard",
                 "FB_DL_MfcSetpointRamp", "FB_DL_TankN2BlanketCtrl"],
 "DL_Motion":   ["FC_DL_TrackerBacktrackCalc", "FB_DL_WindingAlignEdge",
                 "FB_DL_SolderRibbonTension", "FB_DL_TrackerSnowShedAngle"],
 "DL_Process":  ["FB_DL_StringIVTrace", "FB_DL_ChamberPumpDownProfile",
                 "FB_DL_CartonErectorStation", "FB_DL_TrackBarcodeTrace",
                 "FB_DL_TankDosingMulti", "FB_DL_BatchDeviationAlarm",
                 "FB_DL_RollCompressForceBalance"],
}
FIXED = {"FC_DL_WetBulbTempCalc": "v1.0.1→v1.1.0（R23 P0 挂账关闭：二分法重写）",
         "FB_DL_TankN2BlanketCtrl": "v1.0.0→v1.0.1（R23 P0 挂账关闭：泄放/补氮退出迟滞回差）",
         "FB_DL_CartonErectorStation": "v1.0.0→v1.0.1（R24 终审修复：步进器复位死锁）",
         "FB_DL_PumpDryRunGuard": "v1.0.0→v1.0.1（R24 终审修复：默认参数自违反 R100 配比）"}

def zh(c):
    # 中文注释截取：取 " / " 之前
    c = c.strip()
    i = c.find(" / ")
    return (c[:i] if i > 0 else c).strip()

def parse(fp):
    t = open(fp, encoding="utf-8").read()
    m = re.search(r"FUNCTION(?:_BLOCK)?\s+((?:F[BC]|I)_DL_\w+)", t)
    name = m.group(1)
    kind = "函数 FC" if t.lstrip().startswith("// 函数") or m.group(0).startswith("FUNCTION ") and not "FUNCTION_BLOCK" in m.group(0) else "功能块 FB"
    if m.group(0).startswith("FUNCTION_BLOCK"): kind = "功能块 FB"
    else: kind = "函数 FC"
    ver = re.search(r"版本：(v[\d.]+)", t).group(1)
    cm2 = re.search(r"中名称?称?：(.*)", t)
    cn = ""
    if cm2:
        cn = cm2.group(1).strip()
        for sep in (" ｜", " |", "｜"):
            i = cn.find(sep)
            if i > 0: cn = cn[:i]
        cn = cn.strip()
    dm = re.search(r"// 功能描述：(.*)", t)
    desc = dm.group(1).strip() if dm else ""
    band = re.search(r"错误码表：?16#(\d{4})_", t)
    band = band.group(1) if band else "见头注释"
    pins = []
    for sec in ("VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT"):
        bm = re.search(sec + r"\b(.*?)END_VAR", t, re.S)
        if not bm: continue
        for line in bm.group(1).splitlines():
            pm = re.match(r"\s*(\w+)\s*:\s*([^;]+);", line)
            cm = re.search(r"//\s*(.*)", line)
            if pm:
                pins.append((sec.replace("VAR_", "").replace("_", ""), pm.group(1).strip(),
                             pm.group(2).strip(), zh(cm.group(1)) if cm else ""))
    return dict(name=name, kind=kind, ver=ver, cn=cn, desc=desc[:120], band=band, pins=pins)

def sect(sublib, items):
    out = ["", "## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 %d 件 + 修复件 %d 件）" % (
        sum(1 for n in items if n not in FIXED), sum(1 for n in items if n in FIXED)), ""]
    for n in items:
        d = parse(BASE + sublib + "/" + n + ".st")
        tag = FIXED.get(n, "")
        out.append("### %s（%s，%s）｜ %s%s" % (d["name"], d["kind"], d["cn"], d["ver"],
                    ("　**注**：" + tag) if tag else ""))
        out.append("")
        out.append("- **功能**：%s" % d["desc"])
        out.append("- **码位带**：16#%s_xxxx（信息级/故障级分带见源码头注释错误码表）" % d["band"])
        out.append("- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：")
        out.append("")
        out.append("| 方向 | 引脚 | 类型 | 说明 |")
        out.append("|---|---|---|---|")
        for drv, pn, ty, cmt in d["pins"]:
            out.append("| %s | `%s` | %s | %s |" % (drv, pn, ty, cmt))
        out.append("")
    return "\n".join(out) + "\n"

for sublib, items in ITEMS.items():
    mp = BASE + "MANUAL_" + sublib + ".md"
    txt = sect(sublib, items)
    with io.open(mp, "a", encoding="utf-8") as f:
        f.write(txt)
    print("appended %-26s +%d lines (%d 件)" % (mp, txt.count("\n"), len(items)))
