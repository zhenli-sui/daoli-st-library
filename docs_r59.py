#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""docs_r59.py —— R59 文档增量（追加式，严禁整篇重写）：README 徽章/摘要行、CHANGELOG、六子库 VERSION.md。"""
import io, os, re

ROOT = r"C:\Library"
TOT, SFT, VER, LINES = 1073, 1074, "v2.51.0", "220,978"
CNT = {"Base": 123, "Algo": 126, "Device": 193, "Motion": 117, "Process": 271}
SUB = {"Base": "1.30", "MathData": "1.31", "Algo": "1.26", "Device": "1.24", "Motion": "1.23", "Process": "1.29"}

# ---- README ----
p = os.path.join(ROOT, "README.md")
t = io.open(p, encoding="utf-8").read()
t = re.sub(r"(Total%20Components-)\d+(%20%2F%2010%2C000)", r"\g<1>%d\g<2>" % TOT, t)
for k in ("Base", "Algo", "Device", "Motion", "Process"):
    t = re.sub(r"(DL--%s-)\d+(%%20open)" % k, r"\g<1>%d\g<2>" % CNT[k], t)
t = re.sub(r"(SFT%20Corpus-)\d+(%20records)", r"\g<1>%d\g<2>" % SFT, t)
t = re.sub(r"\*\*Total Components: [\d,]+ / 10,000\*\*", "**Total Components: %d / 10,000**" % TOT, t)
t = re.sub(r"\*\*Version: v[\d.]+\*\*", "**Version: %s**" % VER, t)
t = re.sub(r"\*\*SFT 语料: [\d,]+ 条\*\*", "**SFT 语料: %d 条**" % SFT, t)
t = re.sub(r"\*\*全库约 [\d,]+ 行\*\*", "**全库约 %s 行**" % LINES, t)
line = ("> **R59（2026-11-21）**：20 新件（Base 3 / MathData 8 / Algo 3 / Device 3 / Motion 3 / Process 3，"
        "看门狗·两步确认·多段定时·度分秒·二次求根·DTL 串·ASCII 帧·重采样·喷嘴组·拐角过渡·MRAC·防摇·"
        "主轴暖机·脉冲喷吹·上锁挂牌·基2 FFT·电导温补·视觉闸门·刀具预算·批次谱系）+ 3 件 v1.0.1 返修；"
        "总库 1053→**1073**，SFT 1074，机检 23/23 PASS；零检索轮，撞名拒 9 件（R214 三查留痕）；"
        "收口机检出 LotGenealogyLink 循环配对编译阻断并就地修复（R333 例外）。")
if "R59（2026-11-21）" not in t:
    t = t.replace("\n> **R58（2026-11-21）**", "\n" + line + "\n>\n> **R58（2026-11-21）**", 1)
io.open(p, "w", encoding="utf-8", newline="").write(t)
print("README updated:", "R59" in t)

# ---- CHANGELOG ----
p = os.path.join(ROOT, "CHANGELOG.md")
t = io.open(p, encoding="utf-8").read()
if "## v2.51.0" not in t:
    sec = """## v2.51.0 — 2026-11-21（R59 二十件入册 + 三件 P0 返修）

### Added（20 件，DL_Base 3 / DL_MathData 8 / DL_Algo 3 / DL_Device 3 / DL_Motion 3 / DL_Process 3）
- DL_Base：`FB_DL_TimerFailSafe`（看门狗失效安全）、`FB_DL_TwoStepConfirm`（两步确认）、`FB_DL_MultiSegmentTimer`（多段时序）
- DL_MathData：`FC_DL_DmsAngleConvert`、`FC_DL_QuadraticSolve`、`FC_DL_DtlStringConv`、`FC_DL_AsciiFrameParse`、`FB_DL_DataResampler`、`FC_DL_FftRadix2`（基 2 原地 FFT）、`FC_DL_ConductivityTempComp`
- DL_Algo：`FB_DL_MracAdaptiveCtrl`（模型参考自适应）、`FB_DL_CraneAntiSway`（输入整形防摇）
- DL_Device：`FB_DL_SprayNozzleBank`、`FB_DL_DustCollectorPulse`
- DL_Motion：`FB_DL_PathCornerBlend`、`FB_DL_SpindleWarmupSeq`、`FB_DL_ToolLifeBudget`
- DL_Process：`FB_DL_LotoSequence`（上锁挂牌五步链）、`FB_DL_VisionResultGate`、`FB_DL_LotGenealogyLink`

### Fixed（v1.0.1）
- `FC_DL_PmvComfortIndex`：段 6 补 `fPpdPct` 非有限复检三件套（R258 口径，防负底数 EXPT NaN 穿透）
- `FB_DL_SoftStarterDrive`：复位沿前置故障相位门；删 3 处自赋值死语句（R261）
- `FB_DL_PeriodicDisturbComp`：头注释补环块双清同步声明；`DL_PDC_SKIPMAX` → `DL_PDC_CNTMAX` 名实对齐
- `FB_DL_LotGenealogyLink`：`END_FOR` → `END_WHILE` 循环配对修复（收口机检捕获，编译阻断，行为零变更）

### Meta
- registry 1053 → **1073**（counts 123/243/126/193/117/271，sum 断言通过）；SFT 语料 1054 → **1074**（badjson=0）
- 机检增量 23/23 PASS fail=0；ROADMAP 勾 0 条（20 名零在册），待办维持 33
- 专家进化 +9 条（PLC R271~R275 / 总监 R276~R280）

"""
    t = t.replace("## v2.49.0", sec + "## v2.49.0", 1) if "## v2.49.0" in t else t
    if "## v2.51.0" not in t:  # 兜底：插在首个版本节前
        m = re.search(r"^## v", t, re.M)
        if m:
            t = t[:m.start()] + sec + t[m.start():]
io.open(p, "w", encoding="utf-8", newline="").write(t)
print("CHANGELOG v2.51.0:", "## v2.51.0" in t)

# ---- 六子库 VERSION.md 追加节 ----
NOTE = {
 "Base": "R59 新增 TimerFailSafe / TwoStepConfirm / MultiSegmentTimer 三件（看门狗失效安全、两步确认、多段时序），补足基础控制时序家族。",
 "MathData": "R59 新增 8 件：DmsAngleConvert / QuadraticSolve / DtlStringConv / AsciiFrameParse / DataResampler / FftRadix2 / ConductivityTempComp 等，覆盖单位换算、代数求解、时间串、帧解析、重采样与频域。",
 "Algo": "R59 新增 MracAdaptiveCtrl / CraneAntiSway；PmvComfortIndex 与 PeriodicDisturbComp 升 v1.0.1（非有限复检、环块双清声明、常量名实对齐）。",
 "Device": "R59 新增 SprayNozzleBank / DustCollectorPulse；SoftStarterDrive 升 v1.0.1（复位故障相位门、删自赋值死语句）。",
 "Motion": "R59 新增 PathCornerBlend / SpindleWarmupSeq / ToolLifeBudget，覆盖拐角过渡、热机顺控与刀具寿命预算。",
 "Process": "R59 新增 LotoSequence / VisionResultGate / LotGenealogyLink；LotGenealogyLink 修循环配对编译阻断。",
}
for k, v in SUB.items():
    p = os.path.join(ROOT, "DL_" + k, "VERSION.md")
    if not os.path.exists(p):
        print("  MISS VERSION", k); continue
    t = io.open(p, encoding="utf-8").read()
    head = "## v%s — 2026-11-21（R59）\n\n%s\n\n" % (v, NOTE[k])
    if "（R59）" in t:
        print("  skip (already)", k); continue
    m = re.search(r"^## ", t, re.M)
    t = (t[:m.start()] + head + t[m.start():]) if m else (t.rstrip() + "\n\n" + head)
    io.open(p, "w", encoding="utf-8", newline="").write(t)
    print("  VERSION %s -> v%s" % (k, v))
print("DOCS DONE")
