# R32 轮规划 · 20 件目标组件（2026-11-18，零检索轮）

> 统计口径：总库 558/10000（5.58%）；今日 39/200（R31 已贡献，缺口 161）；500 计划已超额（558−500 = +58）；源矩阵 ☐ 行已全部开组，◐ 行占比约 92%（✔ 4 行 / ◐ 24 行 / ☐ 0 行粗估）。本轮回归常态节奏，20 件配额。
> 选题优先级执行：T0 快车道 8 件 > ROADMAP/§24 欠账 4 件 > 源矩阵 ◐ 行待挖子项 3 件 > 行业池空位 5 件。查重：全部 20 名已对 INDEX_REGISTRY.json 全 558 名与同义邻件双查（R148/R160 口径），零同名、零同义撞车（`FB_DL_EnthalpyPrioritySwitchover` 因与存量 `FB_DL_EnthalpyChangeover` 同义被剔除换件）。
> 修订件（SplicerAutoJoint 超时 / VavBoxCtrl 非有限闸 / RoomClimateCtrl bDewDegraded / InertPurgeSeq NaN 门禁 / eFault CASE 标签 6 件 / MotionCmdQueue 去重语义）不占本轮 20 件新件配额，作为批内附带修复。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_StringToUpperEx | DL_MathData | FC | 字符串大写转换（ASCII 域内映射，域外字符保持原值 + 长度守卫） | T0-6 字符串族未覆盖原子 | 低 | 1 |
| 2 | FC_DL_StringStripCharsEx | DL_MathData | FC | 去除字符串两侧自定义字符集（区别于 StringTrim 仅空格，支持空集恒等） | T0-6 字符串族未覆盖原子 | 低 | 1 |
| 3 | FC_DL_BytesToHexString | DL_MathData | FC | 字节数组→定宽大写十六进制串（防溢出 + 空数组返回空串；与 DwordToHexString 互补） | T0-6 字符串族未覆盖原子 | 低 | 1 |
| 4 | FC_DL_HexStringToLword | DL_MathData | FC | 十六进制串→LWORD 解析（奇偶长度/非法字符/溢出三闸，与 HexStringToBytes 互补） | T0-6 字符串族未覆盖原子 | 低 | 1 |
| 5 | FC_DL_ReverseBitsWord | DL_MathData | FC | WORD 位反转（LSB/MSB 序适配，服务 LSB-first CRC 与 LED 点阵；ShlEx/ShrEx 族未覆盖原子） | T0-2 位串族未覆盖原子 | 低 | 1 |
| 6 | FC_DL_DtAddSecondsSat | DL_MathData | FC | DT 加秒饱和运算（超 Y2038/DATE 上限饱和 + 故障级；补日历族「DT 域加法」缺口） | T0-5 时间日期族未覆盖原子 | 低 | 2 |
| 7 | FC_DL_DivDintSafeChk | DL_MathData | FC | DINT 安全除（除零→哨兵 + bError；整数域对偶 DivLrealSafe） | T0-4 数学安全包装未覆盖原子 | 低 | 2 |
| 8 | FC_DL_ModLrealSafe | DL_MathData | FC | LREAL 安全取模（除零/非有限双闸，防 NaN 扩散；与 DivLrealSafe 组成除/模对） | T0-4 数学安全包装未覆盖原子 | 低 | 2 |
| 9 | FB_DL_SteamTrapDiagTrend | DL_Process | FB | 疏水阀诊断趋势件（蒸汽损失趋势累积 + 泄漏等级判定，前置 SteamTrapMonitor 已落地） | ROADMAP §24.2 P1 欠账 | 中 | 2 |
| 10 | FB_DL_ColumnDpSteadyWatch | DL_Process | FB | 精馏塔差压稳态监视（稳态窗学习 + 液泛/漏液预判，前置 ColumnDpCtrl 已落地） | ROADMAP §24.2 P1 欠账 | 中 | 2 |
| 11 | FC_DL_BitArrayReverse | DL_MathData | FC | 位数组段镜像反转（BitArray 族 Extract/Insert/Rotate/SegCopy 后未覆盖原子） | T2-1 LGF Bit Logic ◐ 待挖 | 低 | 3 |
| 12 | FB_DL_VavCouplingFeedforward | DL_Process | FB | 变风量耦合前馈（送风温度-风量耦合前馈补偿，ROOM_CONTROL 子族三项待挖之一） | T1-2 OSCAT Building ◐ 待挖 | 中 | 3 |
| 13 | FB_DL_BlindPositionCtrl | DL_Process | FB | 电动遮阳帘位置控制（光照目标 + 风雨/结冰联锁 + 行程时间标定，借 OSCAT BLIND 行为定义） | T1-2 OSCAT Building ◐ 待挖 | 中 | 3 |
| 14 | FB_DL_CompressorFleetStaging | DL_Process | FB | 空压机群站加卸载编排（母管压力带 + 台数 TRUNC 进位点 + 最短运行/停止轮值，防同时启停浪涌） | 行业池·公用工程空位 | 高 | 3 |
| 15 | FB_DL_AhuSupplyAirReset | DL_Process | FB | 空调送风温度再设定（末端需求加权 → 送风设定串级重置，区分 cooling/heating 模式带） | 行业池·暖通空位 | 中 | 4 |
| 16 | FB_DL_BatteryModuleBalanceMonitor | DL_Process | FB | 电池模组压差均衡监视（单体压差趋势 + 均衡需求分级 + 哨兵可区分性，呼应 R25 P2 纪律） | 行业池·锂电空位 | 中 | 4 |
| 17 | FB_DL_WaferThermalBudgetAccum | DL_Process | FB | 晶圆热预算累计（温度-时间 Arrhenius 加权积分 + 工艺窗口超限告警，R123/R131 量纲链模板载体） | 行业池·半导体空位 | 中 | 4 |
| 18 | FB_DL_CaseSealerFlapFoldSeq | DL_Process | FB | 封箱机折盖顺控（前后盖折页时序 + 卡箱超时 + 胶带/热熔双模式抽象） | 行业池·包装空位 | 中 | 4 |
| 19 | FB_DL_NitrideFurnaceAmmoniaPurge | DL_Process | FB | 氮化炉氨吹扫顺控（氨分解率判据 + 残氨排放联锁 + 吹扫段两段化中止） | ROADMAP R24 增补挂账 | 高 | 4 |
| 20 | FB_DL_BusbarWeldMonitor | DL_Process | FB | Busbar 超声焊接能量包络监视（功率-振幅-时间三维窗口，与 LaserTabWeldTrack 机制异构不撞名） | ROADMAP R24 增补挂账（R26 认领） | 中 | 4 |

## 码位分配（R61：派单为规划值，编码前主控必须当场复测游标）

- **02_3（DL_MathData）**：实测游标 16#33，本轮 9 件 FC（序号 1~8、11）每件独占 3 槽，自 **16#34** 起顺序推进至 16#4E（34/37/3A/3D/40/43/46/49/4C 各起）。已避开 16#00~33 全部历史占用段。
- **03 组（DL_Algo）**：本轮零占用。03_0 已至 16#FC 临界，游标处置维持主控裁定（新件从 03_1_00 起或 03_0_FD 续），本轮无 03 件，该风险顺延至下轮立项时一并解决。
- **06_0（DL_Process）**：主控本轮未交接实测游标，按 R61 铁律**不给虚构绝对码**——11 件 FB（序号 9、10、12~20）自「收口后实测游标 + 1」起，每件独占 4 槽按表序推进（合计 44 槽）；编码派单前由主控复测填入起始绝对值。
- 信息级 04xx 子带 / 故障级 03xx 子带纪律延续 R83；新段首用前机检交叉复扫一次并留痕（R173）。

## 批内附带修复（不占 20 件配额）

1. `FB_DL_SplicerAutoJoint` tSyncMax 超时收口（R25 P0/R145 双查）
2. `FB_DL_VavBoxCtrl` fFbTolPct 非有限闸（R127 口径）
3. `FB_DL_RoomClimateCtrl` bDewDegraded 可观测（MINOR）
4. `FB_DL_InertPurgeSeq` NaN 门禁显式化（R135 口径）
5. eFault CASE 标签 6 件（R128 口径：ParticleCounterStat / CoolingTowerApproachCalc / InverterGridSync / HeatPumpDefrost / DuctStaticReset / DewpointReset）
6. `FB_DL_MotionCmdQueue` 去重语义复核留痕（§24.2 P1，二选一裁定）

*R32 规划线 ｜ 2026-11-18 ｜ WebSearch 0 次（零检索轮）*
