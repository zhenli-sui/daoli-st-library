#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""docs_r60.py —— R60 文档增量（README 徽章 / CHANGELOG / 六子库 VERSION），全程追加式，禁整篇重写。"""
import io, os, re

ROOT = r"C:\Library"
SUB = {"DL_Base": 126, "DL_MathData": 248, "DL_Algo": 127,
       "DL_Device": 194, "DL_Motion": 118, "DL_Process": 272}
TOTAL, SFT, VER = 1085, 1086, "v2.52.0"
BASEVER = {"DL_Base": "1.31", "DL_MathData": "1.32", "DL_Algo": "1.27",
           "DL_Device": "1.25", "DL_Motion": "1.24", "DL_Process": "1.30"}
NEW = {
 "DL_Base": ["FB_DL_RolloverCounterUdint（UDINT 回绕安全累计）", "FB_DL_ReqAckHandshake（请求-应答握手原子）",
             "FC_DL_BitFieldExtractLword（64 位位域提取）"],
 "DL_MathData": ["FC_DL_SearchMinMaxDint / FC_DL_SearchMinMaxUdint（DINT/UDINT 极值检索对）",
                 "FC_DL_Affine2DChain（二维仿射链复合）", "FC_DL_ThdCalc（总谐波失真率）",
                 "FC_DL_InterpolateTable3D（三维表三线性插值）"],
 "DL_Algo": ["FB_DL_InputShaperZv（ZV 双脉冲输入整形）"],
 "DL_Device": ["FB_DL_ValveTerminalDiag（阀岛在位诊断）"],
 "DL_Motion": ["FB_DL_AxisCmdArbiter（轴命令源优先级仲裁）"],
 "DL_Process": ["FB_DL_ShiftHandoverCheck（班次交接检查）"],
}

# ---- README 徽章（就地替换数字，不动版式）----
p = os.path.join(ROOT, "README.md")
s = io.open(p, encoding="utf-8").read()
before = s
s = re.sub(r"(Total%20Components-)\d+(%20%2F%2010%2C000)",
           lambda m: m.group(1) + str(TOTAL) + m.group(2), s, count=1)
for k, v in (("DL--Base", SUB["DL_Base"]), ("DL--Algo", SUB["DL_Algo"]),
             ("DL--Device", SUB["DL_Device"]), ("DL--Motion", SUB["DL_Motion"]),
             ("DL--Process", SUB["DL_Process"])):
    pat = "(Level%20\\d%20" + re.escape(k) + "-)\\d+(%20open)"
    s = re.sub(pat, lambda m, v=v: m.group(1) + str(v) + m.group(2), s, count=1)
s = re.sub(r"(SFT%20Corpus-)\d+(%20records)", lambda m: m.group(1) + str(SFT) + m.group(2), s, count=1)
assert s != before, "README 徽章未变更（格式漂移）"
# DL_MathData 徽章若存在则一并更新（README 目前无该行，存在则改）
s = re.sub(r"(MathData-)\d+(%20open)", lambda m: m.group(1) + str(SUB["DL_MathData"]) + m.group(2), s, count=1)
io.open(p, "w", encoding="utf-8").write(s)
print("README 徽章：Total=%d SFT=%d 各子库已同步" % (TOTAL, SFT))

# ---- CHANGELOG 追加节（插在首个 ## 之前，保持时间倒序）----
p = os.path.join(ROOT, "CHANGELOG.md")
s = io.open(p, encoding="utf-8").read()
sec = """## v2.52.0 — 2026-11-21（R60 十二件入册 + P0 返修 + **FB-51 固化批次**）

### Added（12 件，DL_Base 3 / DL_MathData 5 / DL_Algo 1 / DL_Device 1 / DL_Motion 1 / DL_Process 1）
- DL_Base：`FB_DL_RolloverCounterUdint`（UDINT 回绕安全累计）、`FB_DL_ReqAckHandshake`（请求-应答握手原子）、`FC_DL_BitFieldExtractLword`（64 位位域提取）
- DL_MathData：`FC_DL_SearchMinMaxDint` / `FC_DL_SearchMinMaxUdint`（极值检索 DINT/UDINT 对称对）、`FC_DL_Affine2DChain`（仿射链复合）、`FC_DL_ThdCalc`（THD）、`FC_DL_InterpolateTable3D`（三线性插值）
- DL_Algo：`FB_DL_InputShaperZv`（ZV 输入整形）｜ DL_Device：`FB_DL_ValveTerminalDiag`（阀岛诊断）
- DL_Motion：`FB_DL_AxisCmdArbiter`（命令源仲裁）｜ DL_Process：`FB_DL_ShiftHandoverCheck`（班次交接）

### Fixed
- `FB_DL_TwoStepConfirm` v1.0.1（DL_Base）：修 **R275 同拍竞态** —— 段序改为「段 3 先消化本拍二按沿、段 4 才做超时迁移」，窗口到期拍恰有确认沿时按确认成立，不再吞掉合法二按；对外引脚与语义未变。

### Changed（内部规范，不涉接口）
- **固化批次 FB-51**：R252~R280 共 16 条可判定规则并入 `plc-st-templates/01-coding-standard.md`（+48 行，+14.33%）与 `daoli-st-standard/coding-standard.md`（+34 行，+11.45%）；人格文件微调 10.00% / 4.20%。R271 三族开闭词配对、R272 闸参数覆盖、R275 同拍竞态三项同步进机检闸。

"""
i = s.find("\n## ")
s = s[:i + 1] + sec + s[i + 1:]
io.open(p, "w", encoding="utf-8").write(s)
print("CHANGELOG 追加 v2.52.0 节")

# ---- 六子库 VERSION（全部本轮触及）----
for cat, ver in BASEVER.items():
    p = os.path.join(ROOT, cat, "VERSION.md")
    s = io.open(p, encoding="utf-8").read() if os.path.exists(p) else "# VERSION\n"
    sec = "\n## v%s — 2026-11-21（R60 追加）\n- 新增 %d 件：%s\n- 子库累计 %d 件。\n" % (
        ver, len(NEW[cat]), " / ".join(NEW[cat]), SUB[cat])
    io.open(p, "w", encoding="utf-8").write(s.rstrip("\n") + "\n" + sec)
    print("%s VERSION → v%s（累计 %d）" % (cat, ver, SUB[cat]))
print("DONE")
