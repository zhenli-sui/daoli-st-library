# -*- coding: utf-8 -*-
import io, re

def rd(p): return io.open(p, encoding='utf-8').read()
def wr(p, s): io.open(p, 'w', encoding='utf-8', newline='\n').write(s)

# ---------------- README：徽章 + 轮次区块（追加式） ----------------
s = rd('README.md')
rep = [
 ("Total%20Components-483%20%2F%2010%2C000", "Total%20Components-500%20%2F%2010%2C000"),
 ("Level%200-230%20%2F%2040%20closed", "Level%200-232%20%2F%2040%20closed"),
 ("Level%201%20DL--Algo-49%20open", "Level%201%20DL--Algo-53%20open"),
 ("Level%201%20DL--Device-83%20open", "Level%201%20DL--Device-93%20open"),
 ("Level%201%20DL--Motion-40%20open", "Level%201%20DL--Motion-48%20open"),
 ("Level%202%20DL--Process-62%20open", "Level%202%20DL--Process-74%20open"),
 ("SFT%20Corpus-483%20records", "SFT%20Corpus-500%20records"),
]
for a, b in rep: s = s.replace(a, b)
s = s.replace("> **Total Components: 483 / 10,000** ｜ **Phase 1: 198 / 200（99.0%，2026-11-16 开账）** ｜ **Version: v2.16.0** ｜ **SFT 语料: 483 条** ｜ **全库约 85,048 行**",
 "> **Total Components: 500 / 10,000（里程碑达成）** ｜ **Phase 2: 常态节奏 20 件/轮（2026-11-17 R28 起）** ｜ **Version: v2.17.0** ｜ **SFT 语料: 500 条** ｜ **全库约 89,200 行**")

R28 = ("> **Round 28（2026-11-17）：500 件里程碑收口轮——半导体/锂电/层压/公用工程 17 件（4 批）**——"
 "DL_Algo 1（FanLawMultiExpCalc 三量指数可组态换算）｜DL_Motion 5（StepperXyzGantry 三轴开环龙门 / StepperFeederBelt 色标补偿送料 / LaserTabWeldTrack 焊缝三类缺陷窗 / NotchAlignSeq 缺口六相顺控 / EdgeTrimTraverse 修边横动）｜"
 "DL_Device 5（CheckweighZeroTrack 零点跟踪温漂 / EfEmDoorInterlockPlus 三门域首因 / NtcChannelHealth 通道健康评分 / WaferCassetteSlot 25 槽双向计数 / LamCtrlDualZone 双腔差压）｜"
 "DL_Process 6（LaminatorVacLeakTrend 泄漏率趋势 / PumpDownEnvelopeMonitor 抽气段界包络 / SealJawDwellTrim 驻留自整定 / BatchDeviationTierAlarm 四档分级 / InlineCheckweighGauge σ 控制图 / ChillerStagingCurve 冷机台数曲线）；"
 "合计 **4,085 行**（终审修复后 **4,140 行**），机检 check_r28.py **17/17 PASS fail=0**；**R28 终审 4 件高风险抽 4 修，全部升 v1.0.1**（"
 "冷机台数在「正好整除」点多投一台 / 冷机故障解除判据恒假致组态故障永久不可恢复 / 抽气早停建议位永不清理留幽灵建议 / 焊件停滞速度漏入域闸致 bit2 判据静默关闭）；"
 "**撞名 3 起**：ChamberPumpDownProfile→PumpDownEnvelopeMonitor、BatchDeviationAlarm→BatchDeviationTierAlarm 由编码侧另立名，FanLawRootCalc 与 DL_MathData 存量件跨子库同名（编译阻断级）于收口注册时发现并改名 FanLawMultiExpCalc，立新红线 R148「选题双查制」；"
 "registry 483→**500**（v2.17.0，counts 74/158/53/93/48/74），JSONL **500 条**；码位 0002_3715~3719 / 0003_03A7~03BF / 0004_0327~033F / 0005_0430~044D，CLASH=NONE；"
 "专家进化固化批次 R28（PLC 线 R139~R147+R151~R153、总监线 R139~R143+R148~R150 合并入规范）；**总库 500 / 10,000 里程碑达成，R29 起回归 20 件/轮常态节奏**。")

anchor = "> **Round 27"
i = s.find(anchor)
j = s.find("\n", i)
s = s[:j+1] + R28 + "\n" + s[j+1:]
wr('README.md', s)

# ---------------- CHANGELOG：v2.17.0 ----------------
CL = """## v2.17.0 — 2026-11-17（R28）

**新增组件**：17（`DL_Algo` 1 ｜ `DL_Motion` 5 ｜ `DL_Device` 5 ｜ `DL_Process` 6，合计 **4,085 行**；终审修复后 **4,140 行**）｜ **修订**：4 件升 **v1.0.1**（`FB_DL_StepperXyzGantry` / `FB_DL_LaserTabWeldTrack` / `FB_DL_PumpDownEnvelopeMonitor` / `FB_DL_ChillerStagingCurve`）｜ **累计**：**500 / 10,000（里程碑达成）**

**码位**：Algo `0002_3715~3719` ｜ Device `0003_03A7~03BF` ｜ Motion `0004_0327~033F` ｜ Process `0005_0430~044D`；轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：`check_r28.py` 17/17 PASS fail=0（含枚举-CASE 完备性、5 槽码位、嵌套注释剥离）

**改名（撞名事件）**：`FB_DL_ChamberPumpDownProfile` → **`FB_DL_PumpDownEnvelopeMonitor`**（存量件为包络上界口径，引脚不兼容）｜`FB_DL_BatchDeviationAlarm` → **`FB_DL_BatchDeviationTierAlarm`**（存量件撞名）｜`FC_DL_FanLawRootCalc` → **`FC_DL_FanLawMultiExpCalc`**（与 DL_MathData 存量件**跨子库同名，编译阻断级**，收口注册时发现）

**终审**：4 件高风险抽 4 修（100% 命中），全部契约零变更：
- `FB_DL_ChillerStagingCurve` v1.0.1：需求台数 `TRUNC(x)+1` 在**正好整除**时多算一台（2.0→4 台而非 3 台）；补负荷率/死区域钳制（超界负荷经实数转整数溢出会翻转加减机方向）；故障解除判据 `(NOT bEnable) AND (NOT _bFaultLatch)` 恒假，组态故障永久不可恢复 → 改失能即解除 + 锁存码回放。
- `FB_DL_PumpDownEnvelopeMonitor` v1.0.1：早停建议位（`bSlowWarn`）置位后无同拍清理点，新循环仍向上位留幽灵建议 → 改段内锁存派生输出；故障码改由锁存码回放，原写法会把组态故障错报成压强故障。
- `FB_DL_LaserTabWeldTrack` v1.0.1：补 `fStallVel_mmS` 组态域闸（负值/NaN 使停滞距离门限失效、bit2 判据静默关闭）；焊点位置与停滞窗起点锁存加位置有限前置（防 NaN 写出口）。
- `FB_DL_StepperXyzGantry` v1.0.1：空闲无事件相补发就绪码，消除「头注释声明 0327 覆盖空闲、实现输出 0」的口径不一致。

**数据**：registry 483→500（counts 74/158/53/93/48/74）｜ JSONL **500 条**（改名件采用**替换行**而非追加）

**红线新增**：R148 选题双查制（全库同名 + 同义，跨子库同名按编译阻断级）｜ R149 终审必查两式（锁存解除可达 / 整数进位点）｜ R150 编码单调用负载配额 ｜ R151 域闸覆盖断言 ｜ R152 锁存解除与码回放 ｜ R153 取整余量进位

**专家进化**：固化批次 **R28**——PLC 线 R139~R147 + R151~R153 合并入 `01-coding-standard.md` 第五部分；总监线 R139~R143 + R148~R150 合并入 `daoli-st-standard` 附录 A/B；两份人格文件各微调 ≤ 6 %

"""
s = rd('CHANGELOG.md')
i = s.find("## v2.16.0 — 2026-11-17（R27）")
wr('CHANGELOG.md', s[:i] + CL + s[i:])

# ---------------- AGENT_EVOLUTION_LOG：R28 节 ----------------
AEL = """
## R28（2026-11-17 21:00~22:40）· 500 件里程碑收口轮

**动作摘要**：17 新件终审收口（4 件高风险抽查全部命中并修）+ 元数据 17 条 + registry/JSONL 冲 500 + 专家进化固化批次 R28 + 五件套增量文档。

**架构师视角（本轮沉淀）
1. 「锁存解除条件恒假」是锁存机制最常见的半成品形态：`IF (NOT bEnable) AND (NOT _bFaultLatch)` 看起来像「失能且未锁存就恢复」，实际锁存位只置不清，条件永不成立 → 组态类故障永久不可恢复、只能重启 PLC。写锁存时先把解除式单独写出来自证可满足（R149/R152）。
2. 整数进位点的错误只出现在「正好整除」：`TRUNC(x)+1` 对小数正确、对整数多算一个单位。这类缺陷在工艺上表现为多投设备/多耗能，不报错不停机，是验收向量最容易绕开的位置（R153）。
3. 组态域闸要按「参与换算的每个引脚」判，不是按「主判据引脚」判：漏一个次要引脚不会报错，只会让某个判据静默关闭（停滞速度 NaN → bit2 永不置）（R151）。
4. 派生式输出优于双写：建议位/警告位如果既在分支里置 TRUE 又指望别处清，必然出现「置位后永不清」；改 `bWarn := _bLatch` 派生 + 循环起点同拍清锁存，只留一个写点。

**产品经理视角（缺口与排程）**
1. 500 里程碑达成后**立即停冲刺**：R29 起回归 20 件/轮常态，≥30% 预算给存量修订与债务清偿，否则件数增长会掩盖手册/编译债（债务：VERSION/MANUAL 补录 R138、编译验证 23 轮、R128 eFault 批量修）。
2. 选题查重流程必须工具化：本轮 3 起撞名全靠人眼与编码侧发现，其中 1 起是编译阻断级。下轮派单脚本内置「文件名集合 + registry name 集合 + 跨子库同名断言」，输出到派单书查重行。
3. 族完整性：Motion 仍是最低库（48），R29 优先补多轴组合与凸轮族；Algo(53) 池内 P1 仅余个位数，需启动新一轮狩猎。
"""
s = rd('AGENT_EVOLUTION_LOG.md')
wr('AGENT_EVOLUTION_LOG.md', s.rstrip() + "\n" + AEL)

# ---------------- SOURCE_HUNTING_MATRIX：第 5 节回写 ----------------
s = rd('SOURCE_HUNTING_MATRIX.md')
a = s.find("## 5 ")
b = s.find("## 6 ")
head, sec, tail = s[:a], s[a:b], s[b:]
tags = ["T1-1", "T1-2", "T1-6", "T1-8", "T2-1", "T2-2", "T2-4", "T2-6", "T2-7", "T2-8"]
lines = sec.split("\n")
hit = []
for k, ln in enumerate(lines):
    if not ln.startswith("- "):
        continue
    for t in tags:
        if t in ln:
            if "☐" in ln and "R28" not in ln:
                lines[k] = ln.replace("☐", "◐", 1) + " ｜ R28 回写：本轮触及（+件已入库，子族未满）"
                hit.append(t); break
            elif "◐" in ln and "R28" not in ln:
                lines[k] = ln + " ｜ R28 回写：继续深化（本轮仍有件落此组）"
                hit.append(t); break
wr('SOURCE_HUNTING_MATRIX.md', head + "\n".join(lines) + tail)
print("matrix rows touched:", sorted(set(hit)))

# ---------------- ROADMAP：勾选 + 改名注记 ----------------
s = rd('ROADMAP.md')
doned = []
ren = {"FB_DL_ChamberPumpDownProfile": "FB_DL_PumpDownEnvelopeMonitor",
       "FB_DL_BatchDeviationAlarm": "FB_DL_BatchDeviationTierAlarm",
       "FC_DL_FanLawRootCalc": "FC_DL_FanLawMultiExpCalc"}
names = ["FC_DL_FanLawRootCalc", "FB_DL_StepperXyzGantry", "FB_DL_StepperFeederBelt",
         "FB_DL_CheckweighZeroTrack", "FB_DL_EfEmDoorInterlockPlus", "FB_DL_LaserTabWeldTrack",
         "FB_DL_NotchAlignSeq", "FB_DL_EdgeTrimTraverse", "FB_DL_NtcChannelHealth",
         "FB_DL_WaferCassetteSlot", "FB_DL_LamCtrlDualZone", "FB_DL_LaminatorVacLeakTrend",
         "FB_DL_ChamberPumpDownProfile", "FB_DL_SealJawDwellTrim", "FB_DL_BatchDeviationAlarm",
         "FB_DL_InlineCheckweighGauge", "FB_DL_ChillerStagingCurve"]
for n in names:
    old = "- [ ] `" + n + "`"
    if old in s:
        note = ""
        if n in ren:
            note = " ✔ R28 入库（撞名另立名：`%s`）" % ren[n]
        else:
            note = " ✔ R28 入库"
        s = s.replace(old, "- [x] `" + n + "`" + note, 1)
        doned.append(n)
wr('ROADMAP.md', s)
print("roadmap checked:", len(doned), "/", len(names))
