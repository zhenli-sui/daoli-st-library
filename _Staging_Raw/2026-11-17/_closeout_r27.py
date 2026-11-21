# -*- coding: utf-8 -*-
"""R27 阶段五+六：专家账本追加、账本游标推进、文档增量、手册接口表。全部追加式。"""
import io, os, re

ROOT = r"C:\Library"
def ap(path, text):
    with open(os.path.join(ROOT, path), "a", encoding="utf-8") as f:
        f.write(text)
def rd(path):
    with open(os.path.join(ROOT, path), "r", encoding="utf-8") as f:
        return f.read()
def wr(path, text):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as f:
        f.write(text)

# ---------------- A. PLC 专家账本 ----------------
plc = """
### R27 追加（2026-11-17 · 19 新件 + 1 修订，终审 4 抽 → 2 修 2 过）

[R144] 终审方法论 | FB_DL_MfcFlowCtrl 超调判据把跟踪窗峰值初值取「当前回读」，且只累加正向最大——降设定（20→10 slm）时回读 20 立即满足 20−10 > 超调阈，每次设定下调必误报 039A；升设定与恒设定工况完全看不出问题 | 「跟踪窗」的起点定义错误是方向不对称缺陷：只在设定下行的样本上暴露，而验收向量一律按「新设定高于当前值」编写，天然避开 | 新规则 R144：带跟踪窗/峰值/超调判据的组件，终审必做双向设定阶跃推演（上行 + 下行各一条）；峰值累积必须限定在「首次进入容差窗之后」、初值取设定量而非回读。判据：峰值赋初值行右值为设定量，且累积前置条件含入窗锁存位。
[R145] 时序 | FB_DL_SplicerAutoJoint v1.1.0 的同步看门狗以「NOT bSpeedWithin」为计时使能，本意只统计持续超容差时长；速度差在容差边界抖动时（模拟量噪声常态），看门狗与保持计时器交替复位、两者永不完成 → 相内无限滞留、8B 闸永不触发，v1.1.0 要收口的「无限滞留」在抖动输入下原样复现 | 看门狗取「故障条件的补集」作使能是反模式：故障域与被控域各靠一段计时判定，抖动域落在两者之外成为无判定死区；看门狗只有按相驻留计时，其判据才与相的存在重合 | 新规则 R145：相级看门狗计时使能只准用「相驻留」本身，禁止叠加业务条件的补集；同一相内若并存「达成计时」与「超时计时」，两者使能域之并必须覆盖全相（差集为空即 PASS）。
[R146] 防御范式 | FB_DL_FillWeightCtrl 把「净重为负」与「净重超双倍目标」并入同一 bWeightOk，粗灌相一律转细灌——对重复上料的超重容器等于继续小流量加注直至细灌超时 | 「保守动作」有方向性：降流量对信号抖动是保守，对已超限的物理量却是继续恶化；同一判据承载两类反向异常，保守动作必有一侧错 | 新规则 R146：有效性判据若合并同量纲的双向异常（负偏/正超），分派动作前必须按方向拆分；与安全侧一致的异常（超重/超压/超温）一律立即终止，只对方向不明的（信号读低）保留降级运行。判据：判据式含两个以上不等号时，后续分支须按方向分列。
[R147] 机检 | 本轮枚举解析出现 6 件误报，根因是解析器把注释内逗号当成员分隔符（未先剥注释）；而 TYPE 块种类校验（R132）本身工作正常、零假阳性 | 解析类机检的通病是「先分词再剥注释」，注释中的分隔符会撕碎语法单元；剥离必须前置于分词，且剥离器要能吃嵌套 | 新规则 R147：凡对源码做结构化解析的机检（TYPE 成员、CASE 标签、引脚集合），先经成对剥离器（R91 家族）去除注释与字符串字面量再分词，剥离器提为机检公共函数，禁止各规则自写正则；新解析规则上线前须全库回归，假阳性 > 0 即回炉。
"""
ap(r"_EXPERT_EVOLUTION\PLC_EXPERT_EVOLUTION.md", plc)

# ---------------- B. 总监账本 ----------------
dir_evo = """
## R27 追加（2026-11-17 · 19 新件 + 1 修订，终审 4 抽 2 修）

- [R139] 契约执行 | 本轮枚举解析 6 件误报，根因是机检在分词前未剥注释，注释内逗号被当成员分隔符，造成假 fail；裁定为机检规则缺陷而非代码缺陷 | 机检的可信度靠假阳性率维系，一条高误报的规则会让现场整体跳过红线清单（R91 同族再现） | 新规则 R139：结构化解析一律「先成对剥离注释与字面量、再分词」，剥离器提为机检公共函数；新规则上线前全库回归，假阳性 > 0 即回炉。
- [R140] 架构裁决 | 库内出现「同一数学内核三处各写一遍开方归一」的迹象，本轮 OrificeFlowCalc / GasFlowSqrt / UnwinderDiameterCalc 全部改为委托 FC_DL_NthRoot、FC_DL_AirDensity、FC_DL_FlowCompensate，本件只留校验与钳位 | 委托链的价值不在少写代码而在口径唯一：同一物理内核散落三处，改一处等于改三分之一，且边界语义会各自漂移 | 新规则 R140：凡库内已有内核（开方/取模/密度/滤波/限速），新件一律委托并在头注释「依赖」行列出，禁止内联重实现；判据：新增件 grep 不到 SQRT( / MOD / EXPT( 等原语即合规。
- [R141] 终审方法论 | 本轮 4 件抽查命中 2 件（50%），两件都不在正常验收向量路径上：一件只在设定下行时误报，一件只在速度差抖动时死锁；两件的验收向量都按上行/稳态编写 | 验收向量由设计者按正常工况写就，天然与缺陷暴露条件正交；抽查若只复算向量，等于把设计者的盲区复制一遍 | 新规则 R141：终审每件必推演一条「向量之外」的输入序列——方向反转、边界抖动、相内事件永不到达，三条中至少命中一条并记录推演过程，否则视为未审。
- [R142] 节律基线 | 本轮 20 件（19 新 + 1 修订）在单一召唤批内完成编码 + 机检，实测 24 分钟为整批上限；超时后缺陷密度与文档遗漏率上升，本轮文档债即因此顺延 | 单批产能有硬上限，超时不是多干一点而是多欠一点；把超时当弹性会系统性把债推到收口轮 | 新规则 R142：单召唤批 20 件为上限、24 分钟为节律基线；预计超基线时在派单阶段砍到 15 件或把文档同步拆为独立批，不允许「先编码后补文档」在同批并行。
- [R143] 债务治理 | R27 固化延期（50 分钟预算令），未固化规则累计至 R147；六库 VERSION/MANUAL 的 R26 批次仍欠，编译验证债连欠 23 轮 | 顺延若不在账本顶部显式计数，会在「这轮太忙」的叙事里无声累积成永久欠账（R138 已立规，本轮再次触发） | 新规则 R143：固化延期须同时满足三条才合规——①账本顶部「未固化轮次数」标注延期轮次与原因；②战报「债务清单」逐条列出；③下轮排程首位。缺一即视为违规，由下轮收口方强制回补。
"""
ap(r"_EXPERT_EVOLUTION\DIRECTOR_EVOLUTION.md", dir_evo)

# ---------------- C. 账本顶部游标 + 未固化计数 ----------------
p = "_EXPERT_EVOLUTION/PLC_EXPERT_EVOLUTION.md"
t = rd(p)
t = t.replace(
 "| 当前规则编号游标 | **R139**（下一个可分配编号；R26 收口占号 R132~R135（PLC 线，本账本 R26 追加节）+ R136~R138（总监线，见总监账本 R26 追加节），2026-11-17 收口推进） |",
 "| 当前规则编号游标 | **R148**（下一个可分配编号；R27 占号 R139~R143（总监线）+ R144~R147（PLC 线，本账本 R27 追加节），2026-11-17 收口推进） |", 1)
t = t.replace(
 "| 未固化轮次数 | 0（R23 固化后清零重计） |",
 "| 未固化轮次数 | **4**（R24 / R25-RESUME / R26 / R27；**R27 固化延期至 R28，原因：本轮 50 分钟预算令**，R27 新增 9 条 R139~R147 待固化） |", 1)
wr(p, t)

# ---------------- D. README ----------------
p = "README.md"
t = rd(p)
t = t.replace("Total%20Components-464%20%2F%2010%2C000", "Total%20Components-483%20%2F%2010%2C000", 1)
t = t.replace("SFT%20Corpus-464%20records", "SFT%20Corpus-483%20records", 1)
t = t.replace("> **Total Components: 464 / 10,000** ｜ **Phase 1: 198 / 200（99.0%，2026-11-16 开账）** ｜ **Version: v2.15.0** ｜ **SFT 语料: 464 条**",
              "> **Total Components: 483 / 10,000** ｜ **Phase 1: 198 / 200（99.0%，2026-11-16 开账）** ｜ **Version: v2.16.0** ｜ **SFT 语料: 483 条**", 1)
r26line = "> **Round 26（2026-11-17）：锂电/化成 + 泵阀风机诊断 + 产线治理 + 凸轮/罐区计量 20 件（4 批）**"
idx = t.find(r26line)
assert idx > 0, "R26 line not found"
eol = t.find("\n", idx)
add = ("\n> **Round 27（2026-11-17）：暖通 N+1 与防冻 · 包装灌装/制袋/开箱 · 半导体 LoadPort/MFC · 特气与孔板流量 19 新件 + 1 修订（4 批）**——DL_MathData 2（OrificeFlowCalc 孔板温压补偿 / WaferCountYield 良率分档）、DL_Algo 3（GasFlowSqrt / AirDensityFanPower / LoopWaveInject）、DL_Device 5（FanArrayStageCtrl N+1 轮值 / FrostProtectFreeze 五态防冻 / MfcFlowCtrl 跟踪窗 / DateCoderSync 分频喷码 / SealIntegrityMonitor 三参数窗）、DL_Motion 3（UnwinderDiameterCalc 卷径递推 / StringCutAlign 裁切对位 / StepperZLiftMicron 微米步进）、DL_Process 6（FillWeightCtrl 落差学习 / VffsBagLength 色标袋长 / CartonErectSeq 开箱四相 / LoadPortSeq 七相 + 25 位映射 / PumpChangeoverSeq 加减机 / MachineGuardAudit 门开审计）；`FB_DL_SplicerAutoJoint` 升 **v1.1.1**（v1.1.0 同步相 tSyncMax 欠账 R112 收口 + 终审补看门狗按相驻留）。"
       "\n> 合计 **4,214 行**，机检 **20/20 PASS** fail=0（码位 100 个零重复零撞车，含 R132 TYPE 块种类校验）；**R27 终审 4 抽 → 2 修 2 过**（MfcFlowCtrl 降设定误报超调 / SplicerAutoJoint 抖动漏窗，均升补丁版、对外引脚零变更；FillWeightCtrl 超重中止一并修；LoadPortSeq PASS）。"
       "\n> registry 464→**483**（v2.16.0）；**距离 500 件里程碑仅差 17 件**；下一步 R28：固化 R139~R147 + 17 件冲 500 + 偿还编译验证债。")
t = t[:eol] + add + t[eol:]
wr(p, t)

# ---------------- E. CHANGELOG ----------------
chg = """## v2.16.0 — 2026-11-17（R27）

**新增组件**：19（`DL_MathData` 2 ｜ `DL_Algo` 3 ｜ `DL_Device` 5 ｜ `DL_Motion` 3 ｜ `DL_Process` 6，合计 **4,186 行**；终审修复后 **4,214 行**）｜ **修订**：`FB_DL_SplicerAutoJoint` v1.1.0→**v1.1.1**（同步相超时看门狗按相驻留）｜ **累计**：**483 / 10,000**（距 500 差 17）

**码位**：MathData `0001_0471~047A` ｜ Algo `0002_3706~3714` ｜ Device `0003_038E~03A6` ｜ Motion `0004_0318~0326` ｜ Process `0005_0412~042F`；轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：20/20 PASS fail=0（含 R132 TYPE 块种类校验；枚举解析先去注释后误报清零）

**终审**：4 件高风险定向抽查 → **2 修 2 过**（MfcFlowCtrl 降设定必误报超调〔峰值初值取回读〕/ SplicerAutoJoint 速度差抖动致同步相看门狗漏窗，均对外引脚零变更；FillWeightCtrl 超重容器继续加注一并收敛；LoadPortSeq PASS）｜ **registry**：464→**483**（v2.16.0）｜ **JSONL**：483 条 ｜ **固化**：R139~R147 延期至 R28（50 分钟预算令，账本顶部已计数）

---
"""
p = "CHANGELOG.md"
t = rd(p)
anchor = "## [v2.15.0] — 2026-11-17"
assert anchor in t
t = t.replace(anchor, chg + anchor, 1)
wr(p, t)

# ---------------- F. 五本手册接口表 ----------------
def sect(name, rows):
    head = f"\n## R27 新增接口表（{len(rows)} 件 · 2026-11-17）\n\n| 名称 | 类型 | 主要引脚 | 说明 |\n|---|---|---|---|\n"
    body = "".join("| " + " | ".join(r) + " |\n" for r in rows)
    return head + body

man = {
"MANUAL_DL_MathData.md": [
 ("`FC_DL_OrificeFlowCalc`","FC","IN `fDiffPress_Pa`/`fAbsPress_Pa`/`fTemp_C`/`fKCoefficient`/`fFlowRangeMax`；OUT `fFlow_m3h`/`eError`","孔板差压流量：密度委托 AirDensity、开方委托 NthRoot(2)，越界钳制、差压负判故障"),
 ("`FC_DL_WaferCountYield`","FC","IN `uInputCnt`/`uOutputGood`/`uReworkCnt`；OUT `fYieldPct`/`eGrade`/`bValid`/`eError`","三计数良率与 A~D 分档，无符号减法先验下界防下溢，投入为 0 拒算"),
],
"MANUAL_DL_Algo.md": [
 ("`FC_DL_GasFlowSqrt`","FC","IN `fDiffPress`/`fGasDensity`/`fCompFactor`/`fScaleMax`；OUT `fFlowSlm`/`eError`","特气差压开方，委托 NthRoot + FlowCompensate，密度非法拒算、补偿比越界钳制"),
 ("`FC_DL_AirDensityFanPower`","FC","IN `fTemp_C`/`fRelHumPct`/`fPress_Pa`/`fPowerRated`；OUT `fPowerCorr`/`eError`","风机功率密度修正，密度委托 AirDensity，比率钳 [0.5,1.5]，ρ0 为带单位常量"),
 ("`FB_DL_LoopWaveInject`","FB","IN `bEnable`/`eWaveType`/`fAmplitude`/`fPeriod_s`/`fSlewLimit`/`tSampleTime`；OUT `fInjectOut`/`bActive`/`eErr`","回路调试正弦/方波/阶跃注入，相位累加器与限速器每拍无条件刷新，撤销平滑回零"),
],
"MANUAL_DL_Device.md": [
 ("`FB_DL_FanArrayStageCtrl`","FB","IN `aNRunHrs`/`uStageReq`/`uFanTotal`/`tMinRun`/`tMinStop`；OUT `auFanCmd`/`uStageAct`/`eErr`","N+1 风机分级启停，级数上限=装机−1 预留备机，每拍至多切一台，运行小时极值选台"),
 ("`FB_DL_FrostProtectFreeze`","FB","IN `fFrostTemp_C`/`fOutdoor_C`/`bHysteresisC`/`bFrostAlarm`/`bManualReset`；OUT `bDamperCloseCmd`/`bCoilOpenCmd`/`bFanStopCmd`/`eState`/`eErr`","五态防冻，双阈委托 Hysteresis，跳闸三输出同拍，退出需温度恢复 + 人工复位"),
 ("`FB_DL_MfcFlowCtrl`","FB","IN `fSetpointSlm`/`fReadbackSlm`/`fScaleMaxSlm`/`fTolPct`/`fOvershootPct`/`tStable`/`bNewSp`；OUT `bInTol`/`bOvershoot`/`tSettleMs`/`eError`/`eState`","五态跟踪窗；峰值仅首次入窗后累积（v1.0.1），设定 0 走关断不校验"),
 ("`FB_DL_DateCoderSync`","FB","IN `bEncoderPulse`/`uDivRatio`/`nOffsetCounts`/`bProductDetect`/`tPulseWidth`/`tProdMax`；OUT `bPrintTrig`/`uPulseCount`/`uSkipCount`/`nPhaseDiag`/`eErr`","编码器分频喷码，触发用 >= 比较规避负余数，产品丢失超时显式跳过"),
 ("`FB_DL_SealIntegrityMonitor`","FB","IN 三参数 `fSealTemp_C`/`fSealPress_N`/`tSealTime` + 六窗 `fTempWin_L/H` 等 + `uViolTrip`/`bSealDone`/`bReset`；OUT `bInSpec`/`bAlarmLatch`/`nViolCnt`/`eError`","只判不封；封口完成沿采样，NaN 判超差，主码取首个违参（温度>压力>时间）"),
],
"MANUAL_DL_Motion.md": [
 ("`FB_DL_UnwinderDiameterCalc`","FB","IN `fFilmThick_um`/`fDiaInit_mm`/`fWebLen_m`/`fDiaMin_mm`/`bReset`；OUT `fDiaNow_mm`/`bSpoolEnd`/`eErr`","卷径几何递推 sqrt(D0²−4tL/π)，开方委托 NthRoot(2)，根号内负值冻结不钳零"),
 ("`FB_DL_StringCutAlign`","FB","IN `fCamOffset_mm`/`fGainPct`/`fMaxCorr_mm`/`bCutCycle`/`bAxisInPos`/`tInPosMax`；OUT `fCorrCmd_mm`/`bCorrDone`/`eErr`/`eState`","裁切对位四相，偏差经 LowPassFilter，等待相双出口（在位/超时中止）"),
 ("`FB_DL_StepperZLiftMicron`","FB","IN `fUmPerStep`/`fTargetUm`/`fUpLimit_um`/`fLoLimit_um`/`fSpeedPps`/`bStartMove`/`bReset`；OUT `fPosNow_um`/`bMoving`/`bStepPulse`/`bLimitHit`/`eErr`/`eState`","微米步进：目标先取整成步数并查溢出，软限位两道，运动中越限急停"),
],
"MANUAL_DL_Process.md": [
 ("`FB_DL_FillWeightCtrl`","FB","IN `fGrossWeight_g`/`fTargetNet_g`/`fCoarsePct`/`tFineMax`/`tSettle`/`bStart`/`bReset`；OUT `bCoarseValve`/`bFineValve`/`bFillDone`/`fAdvance_g`/`fNetWeight_g`/`eErr`","五相灌装；去皮内部锁存，落差学习仅完成相一次，超重即中止（v1.0.1），两阀互斥后置校验"),
 ("`FB_DL_VffsBagLength`","FB","IN `bMarkDetect`/`bEncPulse`/`fBagLenSet_mm`/`uEncPpr`/`fCorrLimit_mm`/`tMarkDeb`/`bReset`；OUT `fBagLenAct_mm`/`fCorr_mm`/`bMarkLost`/`bCutPhaseOk`/`nPhaseDiag`/`eErr`","立式制袋袋长，偏差限幅 5 mm，相位取正余数委托 ModPos，连续丢标退化定长"),
 ("`FB_DL_CartonErectSeq`","FB","IN `bVacuumOk`/`bBoxFormed`/`bFlapClosed`/`tStepMax`/`bStart`/`bReset`；OUT `ePhase`/`bDone`/`bJam`/`eJamPhase`/`bVacuumCmd`/`bConveyorCmd`/`eErr`","开箱四相顺控，转相只认反馈不认时间，超时进 ERR 并锁存卡箱相号"),
 ("`FB_DL_LoadPortSeq`","FB","IN `bFoupPresent`/`bDoorOpenOk`/`bValveAck`/`aMapExpect`/`aMapRead`/`tDoorMax`/`tHandMax`/`bStart`/`bReset`；OUT `ePhase`/`bMapMatch`/`bReleaseOk`/`nMapDiff`/`bDoorOpenCmd`/`bDoorCloseCmd`/`eErr`","七相 LoadPort；25 位固定界逐位比对只计数不中断，差异非零走拒收相；超时安全收拢"),
 ("`FB_DL_PumpChangeoverSeq`","FB","IN `fDeltaT_C`/`fDeltaTSet_C`/`aNRunHrs`/`uPumpTotal`/`tMinRun`/`tMinStop`；OUT `auPumpCmd`/`uRunCount`/`eErr`","水泵加减机：死区 ±0.5 ℃ 保持、级数下限 1（不保备机），温差无效只报码不切换"),
 ("`FB_DL_MachineGuardAudit`","FB","IN `bGuardOpen`/`bBatchActive`/`sOperId`/`tMaxOpen`/`bManualConfirm`/`bReset`；OUT `eState`/`bLockBatch`/`uOpenCnt`/`sLastOper`/`eErr`","防护门审计五态：锁定/已锁分相，恢复三条件，超时升级违规，空标识复位被拒"),
],
}
for f, rows in man.items():
    ap(f, sect(f, rows))

# ---------------- G. AGENT_EVOLUTION_LOG ----------------
ael = """
## R27（2026-11-17）暖通 N+1/防冻 · 包装灌装制袋开箱 · 半导体 LoadPort/MFC · 特气孔板流量｜19 新件 + 1 修订

- **架构沉淀**：委托链定为一等纪律——孔板/特气/卷径三处开方全部委托 `FC_DL_NthRoot`，密度全部委托 `FC_DL_AirDensity`，本件只留校验与钳位（R140）。口径唯一比少写代码重要得多。
- **缺陷谱迁移**：本轮 4 抽 2 修，两件都不在验收向量路径上——MfcFlowCtrl 只在设定下行误报超调、SplicerAutoJoint 只在速度差抖动时漏看门狗。抽查必须推演「向量之外」的方向反转与边界抖动（R141/R144/R145）。
- **保守动作的方向性**：FillWeightCtrl 把「净重为负」与「超重」并成一个判据，导致超重容器继续加注；安全侧动作必须按异常方向拆分（R146）。
- **机检治理**：枚举解析 6 件误报根因是注释未剥离就分词，结构化解析必须先成对剥离再分词，并抽成公共函数（R139/R147）。
- **节律**：20 件单批 24 分钟为上限，超时即欠债；本轮文档同步因此顺延（R142）。
- **债务显式化**：R139~R147 共 9 条固化延期至 R28（50 分钟预算令），已在 PLC 账本顶部「未固化轮次数」记 4 轮并注明原因（R143）。
- **数字**：registry 483（v2.16.0），机检 20/20 PASS，码位 100 个 CLASH=NONE，距 500 差 17 件。
"""
ap("AGENT_EVOLUTION_LOG.md", ael)

# ---------------- H. ROADMAP 勾选（≤10 条）----------------
p = "ROADMAP.md"
lines = rd(p).split("\n")
ticks = {242:"R27", 261:"R27", 274:"R27", 277:"R27", 279:"R27", 281:"R27", 296:"R27", 298:"R27", 302:"R27", 563:"R27"}
n = 0
for ln, rnd in ticks.items():
    i = ln - 1
    if lines[i].startswith("- [ ]"):
        lines[i] = lines[i].replace("- [ ]", "- [x]", 1).rstrip() + f" ✔{rnd}"
        n += 1
lines.append("")
lines.append("> **R27 勾选记录（10/19 条）**：本轮已实现且已勾选上表 10 条；余 9 条（L249 / L270 / L275 / L282 / L645 / L660 / L672 / L712 / L845）同为 R27 已入库件，按单轮勾选上限 ≤10 条规则于 R28 批量勾选，不在本轮追加新条目。")
wr(p, "\n".join(lines))
print("ROADMAP ticked:", n)
print("done")
