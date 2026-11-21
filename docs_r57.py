#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""docs_r57.py —— R57 文档增量（README 徽章+摘要 / CHANGELOG / 六子库 VERSION / 战报 / 飞书稿），全追加式。"""
import io, os, json, re

ROOT = r"C:\Library"
STAGE = os.path.join(ROOT, "_Staging_Raw", "2026-11-21")
reg = json.load(io.open(os.path.join(ROOT, "INDEX_REGISTRY.json"), encoding="utf-8"))
total, counts = reg["total_components"], reg["counts"]
sft = sum(1 for l in io.open(os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl"), encoding="utf-8").read().splitlines() if l.strip())
lines = 0
for d in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"):
    for f in os.listdir(os.path.join(ROOT, d)):
        if f.endswith(".st"):
            lines += len(io.open(os.path.join(ROOT, d, f), encoding="utf-8", errors="ignore").read().splitlines())


def app(p, t):
    io.open(p, "a", encoding="utf-8", newline="").write(t)


# 1. README 徽章 + R57 摘要行
p = os.path.join(ROOT, "README.md")
src = io.open(p, encoding="utf-8").read()
old = re.search(r"> \*\*Total Components: [\d,]+ / 10,000\*\*.*", src).group(0)
new = ("> **Total Components: %d / 10,000** ｜ **Phase 2: 常态节奏 20 件/轮（2026-11-17 R28 起）** ｜ "
       "**Version: v2.49.0** ｜ **SFT 语料: %d 条** ｜ **全库约 %s 行**") % (total, sft, format(lines, ","))
src = src.replace(old, new, 1)
summ = ("> **R57（2026-11-21）**：20 新件（Base 5 / MathData 10 / Device 3 / Process 2，T0 Safe 族闭环 15 件——"
        "ASIN/ACOS/LN/EXP/整数幂/符号/RMS/奇偶/峰峰/最近邻阶梯插值 + 正交四倍频计数·主从沿同步·信号呆滞·掉线保持 + "
        "ESD 接地监视/离子风机风速联锁/证明试验/传递窗互锁/夜间吹扫）+ 4 件 v1.0.1 返修；总库 1017→**%d**，SFT %d，"
        "机检 24/24 PASS；零检索轮，规划拒 19 项（R214 三查）。") % (total, sft)
mark = "> **R56（2026-11-20/21）**"
src = src.replace(mark, summ + "\n" + mark, 1)
io.open(p, "w", encoding="utf-8", newline="").write(src)
print("README ok", total, sft, lines)

# 2. CHANGELOG 插入 v2.49.0
p = os.path.join(ROOT, "CHANGELOG.md")
src = io.open(p, encoding="utf-8").read()
sec = """## v2.49.0 — 2026-11-21（R57 二十件入册 + 四件 P0 返修）

### Added（20 新件，4 批 × 5，零检索轮）
- DL_Base（+5）：FB_DL_TpRetrigger / FB_DL_EdgeMasterSlaveSync / FB_DL_EncoderQuadCount / FB_DL_SignalStagnationWatch / FB_DL_SensorDropoutHold
- DL_MathData（+10）：FC_DL_AsinSafe / FC_DL_AcosSafe / FC_DL_LogSafe / FC_DL_ExpSat / FC_DL_PowIntSat / FC_DL_SignumCalc / FC_DL_RmsCalc / FC_DL_ParityCalc / FC_DL_PeakToPeakCalc / FC_DL_InterpStepNearest
- DL_Device（+3）：FB_DL_EsdGroundMonitor / FB_DL_IonizerAirflowInterlock / FB_DL_ProofTestSeq
- DL_Process（+2）：FB_DL_PassboxInterlockSeq / FB_DL_NightPurgeSeq

### Fixed（4 件 v1.0.1 返修，源自 R56 五抽终审）
- FB_DL_LossInWeightFeeder（严重，安全侧）：eIdle 相 / eDose 失能迁移 / 故障锁存三路径 fRateOut 强制归零，消除失能后螺旋继续给料。
- FB_DL_TwoDofPid（中）：手动相入口补 fManOut 有限性闸（x<>x + x-x<>x-x），无效拍冻结早退，防 NaN 直通与积分永久污染。
- FB_DL_AxisAccelFeedforward（中）：有效拍内补 eInputBad 信息级成因恢复撤销，对齐 TwoDofPid 段 10 范式。
- FB_DL_HydraulicAccumPreChg（轻）：段 3 域闸补温度上界常量 DL_HAP_TEMP_HI = 150.0 摄氏度，超界判 eSensorBad。

### Changed
- registry v2.48.0 → v2.49.0，总库 1017 → {TOTAL}（counts {COUNTS}）；JSONL 1018 → {SFT} 行（新增 20 行 badjson=0）。
- 机检 24/24 PASS（20 新 + 4 返修复检），零 GVL / 零物理地址 / 零占位符；撞名三查拦 19 项候选（同族 Ex/Sat 变体为主）。
- T0 防御性包装 15 件统一溯源「IEC 61131-3 标准语义的道莅防御性实现」，ASIN/ACOS/LN/EXP 全部委托平台内建，未重实现数学内核。

""".replace("{TOTAL}", str(total)).replace("{COUNTS}", json.dumps(counts, ensure_ascii=False)).replace("{SFT}", str(sft))
anchor = "## v2.47.0 — 2026-11-20（R55 二十件入册）"
assert anchor in src, "CHANGELOG anchor missing"
src = src.replace(anchor, sec + anchor, 1)
io.open(p, "w", encoding="utf-8", newline="").write(src)
print("CHANGELOG ok")

# 3. 六子库 VERSION 追加
vl = {
 "DL_Base": ("v1.28", "新增 5 件：FB_DL_TpRetrigger / FB_DL_EdgeMasterSlaveSync / FB_DL_EncoderQuadCount / FB_DL_SignalStagnationWatch / FB_DL_SensorDropoutHold（可重触发脉冲 / 主从沿同步 / 正交四倍频 / 信号呆滞 / 掉线保持）"),
 "DL_MathData": ("v1.29", "新增 10 件：FC_DL_AsinSafe / AcosSafe / LogSafe / ExpSat / PowIntSat / SignumCalc / RmsCalc / ParityCalc / PeakToPeakCalc / InterpStepNearest（T0 Safe 族防御性包装 + 最近邻阶梯插值）"),
 "DL_Device": ("v1.22", "新增 3 件：FB_DL_EsdGroundMonitor / FB_DL_IonizerAirflowInterlock / FB_DL_ProofTestSeq（ESD 接地连续性 / 离子风机风速联锁 / 联锁证明试验）+ FB_DL_HydraulicAccumPreChg v1.0.1"),
 "DL_Process": ("v1.27", "新增 2 件：FB_DL_PassboxInterlockSeq / FB_DL_NightPurgeSeq（传递窗三段互锁 / 夜间免费制冷吹扫）"),
 "DL_Algo": ("v1.24", "返修：FB_DL_LossInWeightFeeder v1.0.1（安全侧归零三路径）/ FB_DL_TwoDofPid v1.0.1（手动相有限性闸）"),
 "DL_Motion": ("v1.21", "返修：FB_DL_AxisAccelFeedforward v1.0.1（信息级成因恢复撤销）"),
}
for lib, (ver, desc) in vl.items():
    app(os.path.join(ROOT, lib, "VERSION.md"),
        "## %s — 2026-11-21（R57 追加）\n- %s\n- 子库累计 %d 件。\n\n" % (ver, desc, counts[lib]))
print("VERSION ok")

# 4. 战报
report = """# BATTLE REPORT — R57（2026-11-21 02:05 起）

## 一、看板
| 指标 | 值 |
|---|---|
| 总库 | **{TOTAL} / 10,000（{PCT:.2f}%）** |
| 今日（11-21） | **40 / 200**（R56 跨零点 20 + R57 20） |
| 500 计划 | 已达成，超额 **+{OVER500}** |
| 距 1,000 | 已突破，超额 +{OVER1000} |
| SFT 语料 | **{SFT} 条**（新增 20，badjson=0） |
| 全库行数 | 约 {LINES} 行 |

## 二、四批完成情况（20/20，零跳过）
| 批 | 门类 | 件数 | 内容 | 状态 |
|---|---|---|---|---|
| 1 | DL_Base | 5/5 | TpRetrigger / EdgeMasterSlaveSync / EncoderQuadCount / SignalStagnationWatch / SensorDropoutHold | PASS |
| 2 | DL_MathData | 5/5 | AsinSafe / AcosSafe / LogSafe / ExpSat / PowIntSat（全部委托内建，未重实现数学内核） | PASS |
| 3 | DL_MathData | 5/5 | SignumCalc / RmsCalc / ParityCalc / PeakToPeakCalc / InterpStepNearest | PASS |
| 4 | Device+Process | 5/5 | EsdGroundMonitor / IonizerAirflowInterlock / ProofTestSeq / PassboxInterlockSeq / NightPurgeSeq | PASS |

编码侧自纠 4 处（EdgeMasterSlaveSync 悬空引用 _bFaultGrade、NightPurge 初稿占位残段整件重写、Ionizer 冗余因子、PeakToPeak nUsed 残值预置）。

## 三、P0 闭环（R56 五抽 → 本轮返修）
- **严重（安全侧）**：FB_DL_LossInWeightFeeder —— eIdle 相不清 fRateOut，失能/完成回空闲后螺旋仍按末次 PI 值给料，与头注释矛盾 → 空闲/失能迁移/故障锁存三路径强制归零，v1.0.1。
- 中：FB_DL_TwoDofPid 手动相 fManOut NaN 直通 + 积分永久污染 → 有限性闸 + 冻结早退。
- 中：FB_DL_AxisAccelFeedforward eInputBad 恢复不撤销 → 补撤销，族内范式统一。
- 轻：FB_DL_HydraulicAccumPreChg 温度缺上界 → 补 DL_HAP_TEMP_HI=150.0 摄氏度常量闸。
- R56 五抽结论：严重 1 / 中 2 / 轻 2 / PASS 1。

## 四、本轮终审（R57 五抽：EncoderQuadCount / PowIntSat / PassboxInterlockSeq 必审 + RmsCalc / NightPurgeSeq）
- **严重 0 / 中 4 / 轻 2 / PASS 1**，无编译阻断级缺陷：
  - 中：EncoderQuadCount（首拍假步进 + _bInit 死代码）、RmsCalc（非有限兜底静默降级不置 eErr）、PassboxInterlockSeq（bReqRejected 无清零路径，单拍位永锁）、NightPurgeSeq（执行相缺夜间窗末退出判据）。
  - 轻：PowIntSat（双错同拍首事件码被覆盖）、EncoderQuadCount（丢步钳制判式）。
  - 六项按 R333 挂 **R58 首位**返修。

## 五、机检与台账
- 增量机检 **24/24 PASS fail=0**（20 新 + 4 返修复检，audit_r57.py，口径 compile_gate_v0）。
- registry v2.48.0 → **v2.49.0**，1017 → {TOTAL}；counts Base {CB} / MathData {CM} / Algo {CA} / Device {CD} / Motion {CMo} / Process {CP}（sum 断言通过）。
- ROADMAP 勾选 **0 条**（20 件名无本体行在册；未误勾任何「R57 新立」后续行，R247 生效）；待办 24 + 新补 9 = 33。
- JSONL 1018 → **{SFT}**，新增 20 行逐行 json.loads 校验通过。

## 六、来源与预算
- 源：iec-std-wrapper ×15、t1-oscat ×1、t1-oscat-building ×1、t2-lbp ×1、t2-isa-ne107 ×1、self-esc ×2。满足「≥1 T2 族或 1 T1 组」双保险。
- **WebSearch 0/3**（零检索轮，复用 SOURCE_HUNTING_MATRIX + 既有 RAW_NOTES）。
- 子代理 **3/3**：总监规划 5′ + PLC 单调用（4 批 20 件 + 4 返修）24′ + 总监五抽终审 9′；收口/文档/机检由主控脚本直跑（R335）。
- 墙钟见第八节收尾时刻，预算令逐项在限内。

## 七、专家进化
- PLC +5 条（R251~R255）：悬空引用必查 / 占位残段整件重写纪律 / 双错同拍首事件保真 / 单拍位置位须有清零路径 / 首拍向量化自检。
- 总监 +5 条（R256~R260）：单拍位出口统一清零 / 首拍零假边沿向量 / 非有限兜底三件套 / 进入-退出判据对偶 / 单源高产轮同族横向口径比对。
- 游标 **R260**；FB-50 后第 6 轮未触发固化。

## 八、风险与下轮
- 风险：R57 六件中/轻项集中于「首拍 + 单拍位 + 非有限兜底」三族，属 R193 扩面未清账；长批次（24 件）末段仍出现 1 次占位残段（已自纠）。
- R58 计划：P0 六件返修（EncoderQuadCount / RmsCalc / PassboxInterlockSeq / NightPurgeSeq / PowIntSat）→ 常态 18 件，目标约 {NEXT}。
""".replace("{TOTAL}", str(total)).replace("{PCT}", "%.2f" % (100.0 * total / 10000)) \
   .replace("{OVER500}", str(total - 500)).replace("{OVER1000}", str(total - 1000)) \
   .replace("{SFT}", str(sft)).replace("{LINES}", format(lines, ",")) \
   .replace("{CB}", str(counts["DL_Base"])).replace("{CM}", str(counts["DL_MathData"])) \
   .replace("{CA}", str(counts["DL_Algo"])).replace("{CD}", str(counts["DL_Device"])) \
   .replace("{CMo}", str(counts["DL_Motion"])).replace("{CP}", str(counts["DL_Process"])) \
   .replace("{NEXT}", str(total + 18))
io.open(os.path.join(STAGE, "BATTLE_REPORT_R57.md"), "w", encoding="utf-8", newline="").write(report)
print("report lines", len(report.splitlines()))

# 5. 飞书稿
fs = """**道莅代码库 · R57 战报**（2026-11-21）

**看板**：总库 **{TOTAL} / 10,000（{PCT}%）** ｜ 500 计划超额 **+{OVER500}** ｜ 今日 **40/200** ｜ SFT **{SFT} 条**

**本轮 4 批 20/20**：Base 5（可重触发脉冲/主从沿同步/正交四倍频/信号呆滞/掉线保持）· MathData 10（T0 Safe 族 ASIN/ACOS/LN/EXP/整数幂/符号/RMS/奇偶/峰峰/最近邻插值）· Device 3（ESD 接地监视/离子风机风速联锁/证明试验）· Process 2（传递窗三段互锁/夜间吹扫）

**返修 4 件 v1.0.1**：LossInWeightFeeder 严重安全侧（失能后螺旋仍给料 → 三路径归零）· TwoDofPid（手动相 NaN 闸）· AxisAccelFeedforward（信息级成因撤销）· HydraulicAccumPreChg（温度上界）

**机检** 24/24 PASS ｜ **registry** v2.49.0（1017→{TOTAL}）｜ **ROADMAP** 勾 0 条、补 9 条 ｜ **源** iec-std-wrapper×15 + t1-oscat×2 + t2-lbp/t2-isa-ne107/self-esc×2，WebSearch 0/3 ｜ **召唤** 原生（总监×2 + PLC×1）

**专家进化** +10 条（PLC R251~R255 / 总监 R256~R260，游标 R260）

**终审** R57 五抽：严重 0 / 中 4 / 轻 2 / PASS 1，无编译阻断；六项挂 R58 首位。

**风险**：中/轻项集中于「首拍 + 单拍位 + 非有限兜底」三族（R193 扩面未清账）；长批次末段仍有 1 次占位残段自纠。下轮 P0 六件返修 + 常态 18 件 → 约 {NEXT}。
""".replace("{TOTAL}", str(total)).replace("{PCT}", "%.2f" % (100.0 * total / 10000)) \
   .replace("{OVER500}", str(total - 500)).replace("{SFT}", str(sft)).replace("{NEXT}", str(total + 18))
io.open(os.path.join(STAGE, "Feishu_R57.md"), "w", encoding="utf-8", newline="").write(fs)
print("feishu ok")
