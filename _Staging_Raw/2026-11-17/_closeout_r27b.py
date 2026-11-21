# -*- coding: utf-8 -*-
"""R27 收口第二步：README / CHANGELOG / 手册 / AEL / ROADMAP（A~C 已在上一步完成，此处不重复）"""
import os
ROOT = r"C:\Library"
def ap(p, t):
    with open(os.path.join(ROOT,p),"a",encoding="utf-8") as f: f.write(t)
def rd(p):
    with open(os.path.join(ROOT,p),"r",encoding="utf-8") as f: return f.read()
def wr(p, t):
    with open(os.path.join(ROOT,p),"w",encoding="utf-8") as f: f.write(t)

# ---------------- D. README ----------------
p="README.md"; t=rd(p)
t=t.replace("Total%20Components-464%20%2F%2010%2C000","Total%20Components-483%20%2F%2010%2C000",1)
t=t.replace("SFT%20Corpus-464%20records","SFT%20Corpus-483%20records",1)
t=t.replace("> **Total Components: 464 / 10,000** ｜ **Phase 1: 198 / 200（99.0%，2026-11-16 开账）** ｜ **Version: v2.15.0** ｜ **SFT 语料: 464 条**",
            "> **Total Components: 483 / 10,000** ｜ **Phase 1: 198 / 200（99.0%，2026-11-16 开账）** ｜ **Version: v2.16.0** ｜ **SFT 语料: 483 条**",1)
anchor="**Round 26（2026-11-17）"
idx=t.find(anchor); assert idx>0, "R26 anchor missing"
eol=t.find("\n", idx)
add=("\n> **Round 27（2026-11-17）：暖通 N+1 与防冻 · 包装灌装/制袋/开箱 · 半导体 LoadPort/MFC · 特气与孔板流量 19 新件 + 1 修订（4 批）**——DL_MathData 2（OrificeFlowCalc 孔板温压补偿 / WaferCountYield 良率分档）、DL_Algo 3（GasFlowSqrt / AirDensityFanPower / LoopWaveInject）、DL_Device 5（FanArrayStageCtrl N+1 轮值 / FrostProtectFreeze 五态防冻 / MfcFlowCtrl 跟踪窗 / DateCoderSync 分频喷码 / SealIntegrityMonitor 三参数窗）、DL_Motion 3（UnwinderDiameterCalc 卷径递推 / StringCutAlign 裁切对位 / StepperZLiftMicron 微米步进）、DL_Process 6（FillWeightCtrl 落差学习 / VffsBagLength 色标袋长 / CartonErectSeq 开箱四相 / LoadPortSeq 七相 + 25 位映射 / PumpChangeoverSeq 加减机 / MachineGuardAudit 门开审计）；`FB_DL_SplicerAutoJoint` 升 **v1.1.1**（v1.1.0 同步相 tSyncMax 欠账 R112 收口 + 终审补看门狗按相驻留）。"
     "\n> 合计 **4,214 行**，机检 **20/20 PASS** fail=0（码位 100 个零重复零撞车，含 R132 TYPE 块种类校验）；**R27 终审 4 抽 → 2 修 2 过**（MfcFlowCtrl 降设定误报超调 / SplicerAutoJoint 抖动漏窗，均升补丁版、对外引脚零变更；FillWeightCtrl 超重中止一并修；LoadPortSeq PASS）。"
     "\n> registry 464→**483**（v2.16.0）；**距离 500 件里程碑仅差 17 件**；下一步 R28：固化 R139~R147 + 17 件冲 500 + 偿还编译验证债。")
t=t[:eol]+add+t[eol:]; wr(p,t)

# ---------------- E. CHANGELOG ----------------
chg="""## v2.16.0 — 2026-11-17（R27）

**新增组件**：19（`DL_MathData` 2 ｜ `DL_Algo` 3 ｜ `DL_Device` 5 ｜ `DL_Motion` 3 ｜ `DL_Process` 6，合计 **4,186 行**；终审修复后 **4,214 行**）｜ **修订**：`FB_DL_SplicerAutoJoint` v1.1.0→**v1.1.1**（同步相超时看门狗按相驻留）｜ **累计**：**483 / 10,000**（距 500 差 17）

**码位**：MathData `0001_0471~047A` ｜ Algo `0002_3706~3714` ｜ Device `0003_038E~03A6` ｜ Motion `0004_0318~0326` ｜ Process `0005_0412~042F`；轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：20/20 PASS fail=0（含 R132 TYPE 块种类校验；枚举解析先去注释后误报清零）

**终审**：4 件高风险定向抽查 → **2 修 2 过**（MfcFlowCtrl 降设定必误报超调〔峰值初值取回读〕/ SplicerAutoJoint 速度差抖动致同步相看门狗漏窗，均对外引脚零变更；FillWeightCtrl 超重容器继续加注一并收敛；LoadPortSeq PASS）｜ **registry**：464→**483**（v2.16.0）｜ **JSONL**：483 条 ｜ **固化**：R139~R147 延期至 R28（50 分钟预算令，账本顶部已计数）

---
"""
p="CHANGELOG.md"; t=rd(p)
a="## [v2.15.0] — 2026-11-17"; assert a in t
t=t.replace(a, chg+a, 1); wr(p,t)

# ---------------- F. 手册 ----------------
def sect(rows):
    h=f"\n## R27 新增接口表（{len(rows)} 件 · 2026-11-17）\n\n| 名称 | 类型 | 主要引脚 | 说明 |\n|---|---|---|---|\n"
    return h+"".join("| "+" | ".join(r)+" |\n" for r in rows)

man={
"MANUAL_DL_MathData.md":[
 ("`FC_DL_OrificeFlowCalc`","FC","IN `fDiffPress_Pa`/`fAbsPress_Pa`/`fTemp_C`/`fKCoefficient`/`fFlowRangeMax`；OUT `fFlow_m3h`/`eError`","孔板差压流量：密度委托 AirDensity、开方委托 NthRoot(2)，越界钳制、差压负判故障"),
 ("`FC_DL_WaferCountYield`","FC","IN `uInputCnt`/`uOutputGood`/`uReworkCnt`；OUT `fYieldPct`/`eGrade`/`bValid`/`eError`","三计数良率与 A~D 分档，无符号减法先验下界防下溢，投入为 0 拒算"),
],
"MANUAL_DL_Algo.md":[
 ("`FC_DL_GasFlowSqrt`","FC","IN `fDiffPress`/`fGasDensity`/`fCompFactor`/`fScaleMax`；OUT `fFlowSlm`/`eError`","特气差压开方，委托 NthRoot + FlowCompensate，密度非法拒算、补偿比越界钳制"),
 ("`FC_DL_AirDensityFanPower`","FC","IN `fTemp_C`/`fRelHumPct`/`fPress_Pa`/`fPowerRated`；OUT `fPowerCorr`/`eError`","风机功率密度修正，密度委托 AirDensity，比率钳 [0.5,1.5]，ρ0 为带单位常量"),
 ("`FB_DL_LoopWaveInject`","FB","IN `bEnable`/`eWaveType`/`fAmplitude`/`fPeriod_s`/`fSlewLimit`/`tSampleTime`；OUT `fInjectOut`/`bActive`/`eErr`","回路调试正弦/方波/阶跃注入，相位累加器与限速器每拍无条件刷新，撤销平滑回零"),
],
"MANUAL_DL_Device.md":[
 ("`FB_DL_FanArrayStageCtrl`","FB","IN `aNRunHrs`/`uStageReq`/`uFanTotal`/`tMinRun`/`tMinStop`；OUT `auFanCmd`/`uStageAct`/`eErr`","N+1 风机分级启停，级数上限=装机−1 预留备机，每拍至多切一台，运行小时极值选台"),
 ("`FB_DL_FrostProtectFreeze`","FB","IN `fFrostTemp_C`/`fOutdoor_C`/`bHysteresisC`/`bFrostAlarm`/`bManualReset`；OUT `bDamperCloseCmd`/`bCoilOpenCmd`/`bFanStopCmd`/`eState`/`eErr`","五态防冻，双阈委托 Hysteresis，跳闸三输出同拍，退出需温度恢复 + 人工复位"),
 ("`FB_DL_MfcFlowCtrl`","FB","IN `fSetpointSlm`/`fReadbackSlm`/`fScaleMaxSlm`/`fTolPct`/`fOvershootPct`/`tStable`/`bNewSp`；OUT `bInTol`/`bOvershoot`/`tSettleMs`/`eError`/`eState`","五态跟踪窗；峰值仅首次入窗后累积（v1.0.1），设定 0 走关断不校验"),
 ("`FB_DL_DateCoderSync`","FB","IN `bEncoderPulse`/`uDivRatio`/`nOffsetCounts`/`bProductDetect`/`tPulseWidth`/`tProdMax`；OUT `bPrintTrig`/`uPulseCount`/`uSkipCount`/`nPhaseDiag`/`eErr`","编码器分频喷码，触发用 >= 比较规避负余数，产品丢失超时显式跳过"),
 ("`FB_DL_SealIntegrityMonitor`","FB","IN 三参数 `fSealTemp_C`/`fSealPress_N`/`tSealTime` + 六窗 `fTempWin_L/H` 等 + `uViolTrip`/`bSealDone`/`bReset`；OUT `bInSpec`/`bAlarmLatch`/`nViolCnt`/`eError`","只判不封；封口完成沿采样，NaN 判超差，主码取首个违参（温度>压力>时间）"),
],
"MANUAL_DL_Motion.md":[
 ("`FB_DL_UnwinderDiameterCalc`","FB","IN `fFilmThick_um`/`fDiaInit_mm`/`fWebLen_m`/`fDiaMin_mm`/`bReset`；OUT `fDiaNow_mm`/`bSpoolEnd`/`eErr`","卷径几何递推 sqrt(D0²−4tL/π)，开方委托 NthRoot(2)，根号内负值冻结不钳零"),
 ("`FB_DL_StringCutAlign`","FB","IN `fCamOffset_mm`/`fGainPct`/`fMaxCorr_mm`/`bCutCycle`/`bAxisInPos`/`tInPosMax`；OUT `fCorrCmd_mm`/`bCorrDone`/`eErr`/`eState`","裁切对位四相，偏差经 LowPassFilter，等待相双出口（在位/超时中止）"),
 ("`FB_DL_StepperZLiftMicron`","FB","IN `fUmPerStep`/`fTargetUm`/`fUpLimit_um`/`fLoLimit_um`/`fSpeedPps`/`bStartMove`/`bReset`；OUT `fPosNow_um`/`bMoving`/`bStepPulse`/`bLimitHit`/`eErr`/`eState`","微米步进：目标先取整成步数并查溢出，软限位两道，运动中越限急停"),
],
"MANUAL_DL_Process.md":[
 ("`FB_DL_FillWeightCtrl`","FB","IN `fGrossWeight_g`/`fTargetNet_g`/`fCoarsePct`/`tFineMax`/`tSettle`/`bStart`/`bReset`；OUT `bCoarseValve`/`bFineValve`/`bFillDone`/`fAdvance_g`/`fNetWeight_g`/`eErr`","五相灌装；去皮内部锁存，落差学习仅完成相一次，超重即中止（v1.0.1），两阀互斥后置校验"),
 ("`FB_DL_VffsBagLength`","FB","IN `bMarkDetect`/`bEncPulse`/`fBagLenSet_mm`/`uEncPpr`/`fCorrLimit_mm`/`tMarkDeb`/`bReset`；OUT `fBagLenAct_mm`/`fCorr_mm`/`bMarkLost`/`bCutPhaseOk`/`nPhaseDiag`/`eErr`","立式制袋袋长，偏差限幅 5 mm，相位取正余数委托 ModPos，连续丢标退化定长"),
 ("`FB_DL_CartonErectSeq`","FB","IN `bVacuumOk`/`bBoxFormed`/`bFlapClosed`/`tStepMax`/`bStart`/`bReset`；OUT `ePhase`/`bDone`/`bJam`/`eJamPhase`/`bVacuumCmd`/`bConveyorCmd`/`eErr`","开箱四相顺控，转相只认反馈不认时间，超时进 ERR 并锁存卡箱相号"),
 ("`FB_DL_LoadPortSeq`","FB","IN `bFoupPresent`/`bDoorOpenOk`/`bValveAck`/`aMapExpect`/`aMapRead`/`tDoorMax`/`tHandMax`/`bStart`/`bReset`；OUT `ePhase`/`bMapMatch`/`bReleaseOk`/`nMapDiff`/`bDoorOpenCmd`/`bDoorCloseCmd`/`eErr`","七相 LoadPort；25 位固定界逐位比对只计数不中断，差异非零走拒收相；超时安全收拢"),
 ("`FB_DL_PumpChangeoverSeq`","FB","IN `fDeltaT_C`/`fDeltaTSet_C`/`aNRunHrs`/`uPumpTotal`/`tMinRun`/`tMinStop`；OUT `auPumpCmd`/`uRunCount`/`eErr`","水泵加减机：死区 ±0.5 ℃ 保持、级数下限 1（不保备机），温差无效只报码不切换"),
 ("`FB_DL_MachineGuardAudit`","FB","IN `bGuardOpen`/`bBatchActive`/`sOperId`/`tMaxOpen`/`bManualConfirm`/`bReset`；OUT `eState`/`bLockBatch`/`uOpenCnt`/`sLastOper`/`eErr`","防护门审计五态：锁定/已锁分相，恢复三条件，超时升级违规，空标识复位被拒"),
]}
for f,rows in man.items():
    if "R27 新增接口表" not in rd(f):
        ap(f, sect(rows))

# ---------------- G. AGENT_EVOLUTION_LOG ----------------
if "## R27（2026-11-17）" not in rd("AGENT_EVOLUTION_LOG.md"):
    ap("AGENT_EVOLUTION_LOG.md", """
## R27（2026-11-17）暖通 N+1/防冻 · 包装灌装制袋开箱 · 半导体 LoadPort/MFC · 特气孔板流量｜19 新件 + 1 修订

- **架构沉淀**：委托链定为一等纪律——孔板/特气/卷径三处开方全部委托 `FC_DL_NthRoot`，密度全部委托 `FC_DL_AirDensity`，本件只留校验与钳位（R140）。口径唯一比少写代码重要得多。
- **缺陷谱迁移**：4 抽 2 修，两件都不在验收向量路径上——MfcFlowCtrl 只在设定下行误报超调、SplicerAutoJoint 只在速度差抖动时漏看门狗。抽查必须推演方向反转与边界抖动（R141/R144/R145）。
- **保守动作的方向性**：FillWeightCtrl 把「净重为负」与「超重」并成一个判据，导致超重容器继续加注；安全侧动作必须按异常方向拆分（R146）。
- **机检治理**：枚举解析 6 件误报根因是注释未剥离就分词；结构化解析须先成对剥离再分词并抽成公共函数（R139/R147）。
- **节律**：20 件单批 24 分钟为上限，超时即欠债；本轮文档同步因此顺延（R142）。
- **债务显式化**：R139~R147 共 9 条固化延期至 R28（50 分钟预算令），PLC 账本顶部「未固化轮次数」记 4 轮并注明原因（R143）。
- **数字**：registry 483（v2.16.0），机检 20/20 PASS，码位 100 个 CLASH=NONE，距 500 差 17 件。
""")

# ---------------- H. ROADMAP ----------------
p="ROADMAP.md"; lines=rd(p).split("\n")
ticks=[242,261,274,277,279,281,296,298,302,563]; n=0
for ln in ticks:
    i=ln-1
    if lines[i].startswith("- [ ]"):
        lines[i]=lines[i].replace("- [ ]","- [x]",1).rstrip()+" ✔R27"; n+=1
if "R27 勾选记录" not in "\n".join(lines):
    lines.append("")
    lines.append("> **R27 勾选记录（10/19 条）**：本轮已实现且已勾选上表 10 条；余 9 条（L249 / L270 / L275 / L282 / L645 / L660 / L672 / L712 / L845）同为 R27 已入库件，按单轮勾选上限 ≤10 条规则于 R28 批量勾选，不在本轮追加新条目。")
wr(p,"\n".join(lines))
print("ROADMAP ticked:", n)
print("D~H done")
