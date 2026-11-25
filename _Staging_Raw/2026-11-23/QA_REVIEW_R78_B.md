# QA_REVIEW_R78_B（审校去重席 · 2026-11-23）

## 一、抽检清单与分级（13 件全量扫查，超 3~5 件抽样下限）
| 件 | 12 项扫查 | 去重 | 结论 |
|---|---|---|---|
| FC_DL_RampStepReal | 无缺陷 | 独立 | PASS |
| FC_DL_SlewLimitLreal | 无缺陷 | 精度变体·已声明(L6,26) | PASS |
| FC_DL_DeltaClampReal | 无缺陷 | 独立 | PASS |
| FC_DL_AccelUnitConvert | 无缺陷（A1/A2 方向核对✓） | 独立 | PASS |
| FC_DL_DynViscosityUnitConvert | 无缺陷 | 与 ViscosityUnitConvert 物理量不同(η vs ν)·有效变体 | PASS |
| FC_DL_FlowMassUnitConvert | 无缺陷（0.45359237/1000 方向✓） | 与 FlowUnitConvert 分工清晰 | PASS |
| FC_DL_RateLimitReal | M1 | FB/FC 形态差·可接受 | MINOR |
| FC_DL_SaturateIncr | M2 | 与 SaturateAdd 不同域(DINT 两操作数 vs LREAL 原地±1) | MINOR |
| FC_DL_SaturateDecr | M3,M4 | 同上·对称件 | MINOR |
| FB_DL_MultiZoneSetpointScheduler | J1+M5 | 独立 | MAJOR |
| FB_DL_PalletizerLayerBuildSeq | J1 | 与 PalletizerLayerSeq 分工已声明 | MAJOR |
| FB_DL_WinderTensionTaperCalc | J1+M6 | 与 WinderTensionTaperCtrl 曲线形状不同·已声明 | MAJOR |
| FB_DL_AnalogSensorHealthClassify | J1+M7 | 与 AnalogSignalHealth 电平/统计分野清晰 | MAJOR |

统计：BLOCK 0 ｜ MAJOR 4 处（1 型系统性，4 文件）｜ MINOR 7 处 ｜ PASS 6 件。

## 二、MAJOR（挂账下轮，不就地修——非零行为变更）
- **J1（系统性，4/4 FB）**：四处头注均声明 bReset 为「上升沿」「仅 bReset 沿清除」，实现全部为电平判据、无 R_TRIG：
  MZS:276 `IF bReset AND (NOT bEnable)`（声明 :108/:125）｜PLB:248 `IF bReset AND (NOT bStart)`（声明 :108/:130）｜WTT:231（声明 :83/:103）｜ASC:302（声明 :112/:135）。
  后果：常闭式复位（电平保持 TRUE）时新故障下拍即被自动清除，bError 2 拍振荡，故障锁存名存实亡；安全侧出口本身不受影响（故障相仍撤出/冻结），故 MAJOR 非 BLOCK。逐件补 bReset 沿检测（R_TRIG 实例 + CASE 外无条件刷新）。

## 三、MINOR
- M1 RateLimitReal:28-29 分工声明只列 FB_DL_RampGenerator，未声明与在库 FB_DL_RateLimiter（同语义斜率限幅，DL_Algo）的 FB/FC 形态差——主控明确要求头注声明，补一句。
- M2 SaturateIncr:116 验收向量 A4（fX=-1,fMin=0）落等值边界：_fNext=0.0 不满足 `< fMin`，实走段 6 eIncremented/bSaturated=FALSE，与声明 eSatLow/TRUE 不符（输出值巧合相同，标志语义不符）。
- M3 SaturateDecr:102 向量 A4 同病：fX=10.5−1=9.5 不满足 `> fMax`，实为 eIncremented/fX=9.5，声明称 10.0/eSatHigh。正确向量应为 fX=11.5。
- M4 SaturateDecr:25 分工声明引用 FC_DL_BcdDecrementByte——registry 0 命中、磁盘不存在，悬空引用。
- M5 MZS:164/167 信息码 eMinuteClamped 在段 2 写入后，被 eApply 成功路径 :247 `eCause := eNone` 同拍覆盖——eApply 相内 V4 不可复现（仅 eHold/eIdle 相残留）。
- M6 WTT:147 注释「R272 全量枚举九个浮点引脚」，实际仅 7 个 REAL 入参。
- M7 ASC:256-262 _fMeanCalc/_fVarCalc 及窄化出口 fMean/fVar 无非有限复检（同批单位换算族均有四段式第四段）；REAL 平方和 1.16E76 窄化可溢出为 Inf，安全侧仍判 eNoisy，故 MINOR。

## 四、就地修记录
无。本轮无编译阻断/安全侧且零行为变更的 R333 例外情形，全部挂账。

## 五、挂账清单（下轮优先级）
1. J1 四 FB 补 bReset 沿检测（MAJOR，修后重验 V3/V4 类向量）。
2. M2/M3 修正 SaturateIncr/Decr 头注验收向量（改向量不改码）。
3. M1 RateLimitReal 补 FB_DL_RateLimiter 形态差声明；M4 删除/替换悬空引用。
4. M5 MZS eApply 成功路径保留钳位信息码（如 `IF eCause = eNone THEN eCause := ...` 反向或钳位码专用单拍位）。
5. M6/M7 注释修正 + ASC 补结果复检。

## 六、去重结果（三道比对，对照 registry 1369 条 + _dedup_fingerprints.json）
- 名称：13/13 全库无命中（含同义词根分搜 Rate/Ramp/Slew/Delta/Saturate/Clamp/Visc/Flow/Accel/Palletizer/Winder/Analog/Sensor/Health）。
- 指纹：_dedup_fingerprints.json 0 命中。
- 语义：**拒收 0 件**。4 件确认有效变体：SlewLimitLreal（LREAL 域+窄化出口）、DynViscosity（η vs ν）、SaturateIncr/Decr（LREAL 原地游标 vs DINT 两操作数算术）、RateLimitReal（FC 无状态 vs FB 有状态+跟踪回投，形态差）。RampStepReal 与 RateLimitReal 非同义：目标制步长（fXTarget，无时间量纲）vs 斜率制（fRateMax×fDt，时间量纲），口径不同，保留两件并各自已声明。
- 存疑放行：0 件（RateLimitReal 的声明缺失已列为 M1 非判重问题）。

## 七、系统性缺陷上报（§三.6 → 触发扩面复审）
J1 同型 ≥3（4/4）：「声明沿、实现电平」疑似族模板级缺陷。建议总监安排对本轮之前入库的全部含 bReset 锁存 FB 扩面 grep `bReset AND (NOT` 核查。

## 八、批外备注（信息级）
- registry 漂移：FC_DL_ForceUnitConvert 磁盘存在（DL_MathData）而 registry 0 条，交总监核对入库链。
