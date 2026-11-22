# RAW_NOTES_R72 —— 第 R72 轮选题原始笔记（零检索轮）

> 2026-11-23 ｜ 阶段二选题过程记录 ｜ 配套文档：`ROUND_PLAN_R72.md`

## 1. 零检索轮声明

**本轮 WebSearch 使用 0 次**（连续第 9 轮零检索）。全部选题取材复用既有台账与库内实测：

- `SOURCE_HUNTING_MATRIX.md`（§5 挖掘状态台账 + §1 源分级），零新开组、零整组收口；
- `ROADMAP.md` 遗留口径（仅取 T0-2 日历变体线一条，未勾选、未回写）；
- `INDEX_REGISTRY.json` v2.63.0 实测（python 提取 1,206 个 name 落临时名单 `_tmp_names_R72.txt`，供撞名三查与词根属主探测）。

## 2. 复用的源组清单（从矩阵 §5 摘录，组名 + 状态 + 行号）

| 组名 | 状态 | 矩阵行号 | 本轮取材 |
|---|---|---|---|
| T0-2 定时器（500 快车道） | ✔（收口警示：日历内建链平台口径未实测） | 146 | FC_DL_HmsToTodChk / FC_DL_DaysInMonthChk（变体线，纯整数算术，零内建链依赖） |
| T0-4 数学函数（500 快车道） | ✔ R15 收口（变体扩族多轮） | 148 | FC_DL_IntModChk / FC_DL_FiniteClassify |
| T0-6 字符串（500 快车道） | ✔ R15 收口（R20 字符串化 2 件） | 150 | FC_DL_CharCodeConvert / FC_DL_WordToBinString |
| T2-1 LGF · Math | ◐ R18 深化 | 157 | FC_DL_ArrayCumSumLreal（统计线，邻件 ArraySumLreal） |
| T1-1 OSCAT Basic | ◐ | 170 | FB_DL_BlinkOutput（BLINK 行为定义，OSCAT 许可需致谢，零代码行） |
| T2-6 Rockwell AOI | ◐ R18 深化 | 166 | FB_DL_OilLevelWatch / FB_DL_ToolChangerSeq（设备级粗粒度 + 伺服外围件方向） |
| T2-2 LBP 基础工艺 | ◐ | 163 | FB_DL_SipLineSterilSeq（命令→监视→判定三段骨架） |
| s9-conv（自研输送线） | 自研线（R7 先例） | — | FB_DL_RejectBlowCtrl（剔除执行时序） |

**未触碰**（避免重复挖掘已收口组）：T0-1/T0-3/T0-5/T0-7/T0-8、T1-3 OSCAT Network（✔ R22）、T2-1 LGF 其余已收口子族（仿射/定宽字段/区间关系/位旋转与掩码比较/字符串解析）。

## 3. 规划期探测台账（词根属主实测，R327 留痕口径）

规划期共 5 轮 python 词根批量探测（对 registry 1,206 名 contains 匹配），要点：

1. **第 1 轮（拟题）**：ModChk / AngleUnitConvert / DhmsToTime / DintMsToTod / PadString / RoundToMultiple 等 12 候选 → 其中 AngleUnitConvert、DintMsToTod 已注册，其余进入复核；
2. **第 2 轮（广域）**：Concat/Len/Mid/Find（StringEx 族全覆盖）、Gray/Parity/Hamming（校验域覆盖）、Mean/StdDev/Percentile（统计域覆盖）、Slew/Deadband/Hysteresis（整形域覆盖）→ 确认 Level 0 信号/统计/校验域基本无真空，选题收敛到「取模、非有限分类、前缀累计、字符码、二进制文本、TOD 组态、月天数」七个真实缺口；
3. **第 3 轮（分组域）**：Ne107 聚合 → HealthAggregator/HealthStatusArbiter/DeviceHealthArbiter 三属主在册（矩阵 T2-8「仲裁件待挖」备注滞后）；CamDynTrim 等 4 凸轮修调件在册（矩阵 T1-6「凸轮动态修调待挖」备注滞后）→ 两组「待挖」改判已覆盖，**矩阵备注列滞后于 registry 的现象记入进化账本**；
4. **第 4 轮（Device/Process）**：Sorter/RejectGate/EjectorGate/Centrifuge/Extruder/Baghouse 为真空 → 采纳 RejectBlowCtrl（与 WeightCheckReject/VisionResultGate 邻接分工可共存）与 SipLineSterilSeq；SorterDiverterCtrl 因 LaneDivertCtrl 邻接被拒；
5. **第 5 轮（终查）**：12 正选名逐一 EXACT 匹配 = 全部零命中；日历/时间/刀塔既有件 category 实测（LeapYearChk/DayOfWeekCalc/WeekOfYearCalc/DurationFormat → DL_Base；TodToDintMs/DintMsToTod/DwordToHexString/ModLrealSafe/ArraySumLreal → DL_MathData；TurretToolSelect → DL_Motion v1.0.1）。

## 4. 批 0 点修对账实测摘录

- `FC_DL_AirSpecificVolume.st` 段 5（162~166 行）：调用 `FC_DL_VaporPressureSat(fTempC := …, fPvSat => _fPws, bClamped => _bPwsClmp, eErr => _uPwsCode, bError => _bPwsErr)` —— 6 形参缺 `bValid` 回执，挂账属实；
- `FC_DL_VaporPressureSat.st` 形参表 6 项（fTempC + fPvSat/bClamped/eErr/bError/bValid），`bValid` 段 1 预置 FALSE / 段 5 成功出口置 TRUE；
- 结论：挂账描述与源码事实一致；修法补 `bValid => _bPwsVld`（命名按 `_bPws*` 前缀族一致性裁定，战报原名 `_bAsvOk` 在计划 §3 留痕）；契约完整性修复，无行为变更。

## 5. 留给编码专家的三条硬提醒

1. 12 件均须过 L2 闸（RuSTy），输出形参**全回执**（E032 首条即 R71 点修的教训同型）；
2. `FC_DL_FiniteClassify` 判据禁近似阈值（1.79E308 只可作注释旁证）；`FC_DL_IntModChk` 必拦 DINT_MIN/−1 组合；
3. `FB_DL_BlinkOutput` 的 tOn/tOff 零值组态必须锁存出码（fGain=0 报警静默教训 R386 同型），禁静默全灭。
