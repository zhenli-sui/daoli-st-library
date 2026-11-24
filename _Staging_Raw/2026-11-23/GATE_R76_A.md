# GATE_R76_A —— 批次 A（36 简单件）编译闸正式裁决
- 裁决席: dlf-compile-verifier（独立复裁决，主控预筛不采信）
- 时间: 2026-11-23 | 工具: _tools/l2_check.py（RuSTy plc.exe --check, **严格串行 jobs=1**）
- 依赖: 接口降级桩预筛 缓存命中（可用 22 / 排除 0）；无编码席自检结论采信，全部独立编译
- 过程留痕: 首跑因闸席自身以相对路径调用致 36 假 FAIL（file-not-found，非代码缺陷），
  已用绝对路径重跑为准；另对 FC_DL_BitMaskRange 直调 rusty 独立复核 RC=0，交叉一致
- 原始数据: _Staging_Raw/2026-11-23/_L2_R76_A.json（36 items, rc=0, first_error 全空, dep_rounds=0）

## 裁决表（36/36）

| 件名 | 判定 | 错误码 | 依据 |
|---|---|---|---|
| FC_DL_BitMaskRange | PASS | — | rc=0；另直调 rusty 复核 RC=0 |
| FC_DL_BitReverse8 | PASS | — | rc=0 |
| FC_DL_BitReverse16 | PASS | — | rc=0 |
| FC_DL_BitRunLength | PASS | — | rc=0 |
| FC_DL_BitLowestSet | PASS | — | rc=0 |
| FC_DL_BitSwapPairs | PASS | — | rc=0 |
| FC_DL_BitCountTransitions | PASS | — | rc=0 |
| FC_DL_BitFillLowestZero | PASS | — | rc=0 |
| FC_DL_AngleDiffDeg | PASS | — | rc=0 |
| FC_DL_AngleLerpShort | PASS | — | rc=0 |
| FC_DL_AngleQuadrant | PASS | — | rc=0 |
| FC_DL_AngleBisector | PASS | — | rc=0 |
| FC_DL_AngleToCompass | PASS | — | rc=0 |
| FC_DL_AngleTolInside | PASS | — | rc=0 |
| FC_DL_AngleReflect | PASS | — | rc=0 |
| FC_DL_AngleUnwrapStep | PASS | — | rc=0 |
| FC_DL_BytesToWord | PASS | — | rc=0 |
| FC_DL_DwordToWords | PASS | — | rc=0 |
| FC_DL_WordsToDword | PASS | — | rc=0 |
| FC_DL_EndianProbe | PASS | — | rc=0 |
| FC_DL_LwordToDwords | PASS | — | rc=0 |
| FC_DL_DwordsToLword | PASS | — | rc=0 |
| FC_DL_SinDeg | PASS | — | rc=0 |
| FC_DL_CosDeg | PASS | — | rc=0 |
| FC_DL_TanDegChk | PASS | — | rc=0 |
| FC_DL_AsinDegChk | PASS | — | rc=0 |
| FC_DL_AcosDegChk | PASS | — | rc=0 |
| FC_DL_Atan2Deg | PASS | — | rc=0 |
| FC_DL_SincSafe | PASS | — | rc=0 |
| FC_DL_HypotChk | PASS | — | rc=0 |
| FC_DL_HystWindow3 | PASS | — | rc=0 |
| FC_DL_HystLatchAlarm | PASS | — | rc=0 |
| FC_DL_HystCounterStep | PASS | — | rc=0 |
| FC_DL_HystTimeQualified | PASS | — | rc=0 |
| FC_DL_ClampDintChk | PASS | — | rc=0 |
| FC_DL_WrapToRange | PASS | — | rc=0 |

## 汇总
- PASS 36 / FAIL 0 / EXEMPT 0，通过率 100%（36/36）
- 无豁免 → 无连续 3 轮豁免 P0 风险；无回派编码席事项
- 裁决：**批次 A 36 件全部通过 L2 真编译闸，放行进入审校阶段**
- 复现命令：`python C:\Library\_tools\l2_check.py <36件绝对路径> --out _Staging_Raw\2026-11-23\_L2_R76_A.json`
- 备注：本轮仅 L2 编译门；L3 向量门（_TESTS/*.json 边界用例）尚未铺开至本批，审校后逐件补建

## 批次 B（4 复杂件）裁决
- 执行方式：本地 L2 真编译闸 `l2_check.py`，严格串行 jobs=1，逐件独立复编译（编码席自检 4/4 PASS 不采信，全部重跑）
- 复现命令：`python C:\Library\_tools\l2_check.py <file>`（下表逐件命令可直接复制）

| 件 | 裁决 | 明细 | 复现要点 |
|---|---|---|---|
| DL_Motion/FB_DL_BrakeReleaseInterlock.st | PASS | — | 接口预筛 22/22 可用，排除 0；rc=0 |
| DL_Device/FB_DL_HeaterBankLoadBalance.st | PASS | — | 接口预筛 22/22 可用，排除 0；rc=0 |
| DL_Device/FB_DL_AnalogDriftWatch.st | PASS | — | 接口预筛 22/22 可用，排除 0；rc=0 |
| DL_Process/FB_DL_ChillerDoorPurgeSeq.st | PASS | — | 接口预筛 22/22 可用，排除 0；rc=0 |

## 汇总（批次 B）
- PASS 4 / FAIL 0 / EXEMPT 0，通过率 100%（4/4）
- 无编码笔误需回派；无编译器覆盖面缺口豁免（PROPERTY 排除数为 0，未触发 EXEMPT 判据）
- 裁决：**批次 B 4 件全部通过 L2 真编译闸，放行进入审校+入库**
- 备注：本机 L2 为唯一执行门（无 MatIEC 二进制、CI 未触发本批）；L3 向量门未铺开，与批次 A 同口径挂账
