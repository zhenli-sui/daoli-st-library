# BATTLE_REPORT_R28（2026-11-17 · 500 件里程碑收口轮）

## 1 结论一句话

**17/17 四批全部交付，机检 `check_r28.py` fail=0（4,085 → 4,140 行）；终审 4 件高风险抽 4 修全部升 v1.0.1；registry 483 → 500，JSONL 500 条 —— 总库 500 / 10,000 里程碑达成，R29 起回归 20 件/轮常态。**

## 2 四批完成情况（17/17）

| 批 | 件数 | 落盘 | 机检 |
|---|---|---|---|
| B1 | 5 | FanLawMultiExpCalc / StepperXyzGantry / StepperFeederBelt / CheckweighZeroTrack / EfEmDoorInterlockPlus | PASS |
| B2 | 4 | LaserTabWeldTrack / NotchAlignSeq / EdgeTrimTraverse / NtcChannelHealth | PASS |
| B3 | 4 | WaferCassetteSlot / LamCtrlDualZone / LaminatorVacLeakTrend / **PumpDownEnvelopeMonitor**(改名) | PASS |
| B4 | 4 | SealJawDwellTrim / **BatchDeviationTierAlarm**(改名) / InlineCheckweighGauge / ChillerStagingCurve | PASS |

## 3 终审 4 件（抽 4 中 4，全部契约零变更 → v1.0.1）

| 件 | 缺陷 | 定级 | 处置 |
|---|---|---|---|
| ChillerStagingCurve | ①`TRUNC(x)+1` 在正好整除时多投一台（2.0→4 台）②负荷率/死区未入域闸，超界经实数转整数溢出会**翻转加减机方向** ③故障解除判据 `(NOT bEnable) AND (NOT _bFaultLatch)` 恒假 → 组态故障永久不可恢复 | 中等×3 | 修（余量进位 + 双钳制 + 失能即解锁/码回放） |
| PumpDownEnvelopeMonitor | ①`bSlowWarn` 置位后无同拍清理点，新循环仍留幽灵建议 ②故障码按当下输入重推，组态故障错报成压强故障 | 轻微×2 | 修（锁存派生 + 锁存码回放） |
| LaserTabWeldTrack | ①`fStallVel_mmS` 漏入域闸，负值/NaN 使停滞门限失效、bit2 判据静默关闭 ②焊点位置锁存无位置有限前置（NaN 入出口） | 轻微×2 | 修 |
| StepperXyzGantry | 空闲相不发就绪码（头注释声明 0327 覆盖空闲，实现输出 0） | 注释级 | 修 |

**观察项（未改，挂账 R29 编译验证）**：Gantry 到位判定依赖轴实现「MoveRelative 受理即置非空闲」，契约语义已明确但未经三平台实测。
**已识别限制（不改语义）**：Pump 分段合格按**末次采样斜率**判定而非段均值，属算法精度取舍，HMI 侧建议标注。

## 4 撞名事件 3 起（查重流程失效，已立 R148）

| 规划名 | 处置 | 检出方 |
|---|---|---|
| `FB_DL_ChamberPumpDownProfile` | 另立 `FB_DL_PumpDownEnvelopeMonitor`（存量件为包络上界口径，引脚不兼容） | 编码侧 |
| `FB_DL_BatchDeviationAlarm` | 另立 `FB_DL_BatchDeviationTierAlarm` | 编码侧 |
| `FC_DL_FanLawRootCalc` | 另立 `FC_DL_FanLawMultiExpCalc` —— 与 **DL_MathData 存量同名件（06:02 注册）跨子库同名**，CODESYS 编译期重复标识符，**编译阻断级** | **收口注册时**（本报告新增披露） |

## 5 规格偏离裁定（编码侧 5 项 + 本报告新增 1 项）

①序10 `uSlotMask` WORD→**DWORD**（25 位需 16#01FFFFFF）→ **准**，属规格算术错，回写规格。②序3/7/10/11 无预留槽、规格码达 4+ → **准**（机检 2~6 槽已覆盖）。③10 件无 `bError` 引脚、故障由 `eErr≠0` 表达 → **准**（R45 铁律为 `bError=TRUE 必对应码`，未要求反向）。④序8 未复用 `SoftLimitGuard`（契约不匹配）改内联预检 → **准**，但须在 MANUAL 注明未委托。⑤序2 `fAccel` 仅门禁不转发、序7 角度按 1mm=1° 标定 → **准**（接口契约与标定假设已入头注释）。⑥（新）`FC_` 件因撞名改名为 `FC_DL_FanLawMultiExpCalc` → 总监裁定，registry/JSONL/ROADMAP 三处已同步。

## 6 里程碑与节奏

- **总库 500 / 10,000 达成**（counts 74 / 158 / 53 / 93 / 48 / 74 = 500，三数自洽）；**JSONL 500 条**（改名件采用替换行，行数不变）。
- 今日件数：registry `registered_at` 实际计数 **约 119**（99 + 17 + 3 存疑项）→ **以 registry 为准**，本报告不锁定该数。
- **节奏声明**：R29 起**停止件数冲刺**，回归 **20 件/轮**常态，≥30% 预算给存量修订与债务清偿；新增「族完整性审计」季度项（Motion 48 最低，Algo 53 次低）。

## 7 源与召唤模式

- WebSearch **0 次**：全部取自 `ROADMAP.md` 候选池 + `SOURCE_HUNTING_MATRIX.md` 已收口组深化（T1-1 / T1-2 / T1-6 / T1-8 / T2-1 / T2-2 / T2-4 / T2-6 / T2-7 / T2-8 十组，矩阵第 5 节回写 9 行）。**本批无 T0 件。**
- 召唤模式：**原生召唤连续第 15 轮**。

## 8 预算执行（如实披露：超时违规）

| 段 | 实耗 | 预算 |
|---|---|---|
| 规划 | 9 min | 15 min |
| 编码（单调用 4 批 17 件） | **68 min** | ~20 min |
| 终审 + 收口 | ~40 min | ~15 min |
| 合计 | **≈117 min** | **50 min** |

**违规归因**：①撞名改立 ×3（含收口期发现的编译阻断级同名）；②规格偏离裁定 ×5；③编码单调用负载过重（17 件含 4 件状态机同批）。→ 已立 **R150**：单调用按「件数×平均复杂度」配额，>15 件必须拆两次调用。

## 9 专家进化固化（P0，R27 挂账清偿）

- **固化批次 R28 完成**：PLC 线 R139~R147 + R151~R153 → `plc-programming-expert/.../01-coding-standard.md` 第五部分（9 小节，去重合并）；总监线 R139~R143 + R148~R150 → `daoli-st-standard/references/coding-standard.md` 附录 A、`doc-templates.md` 附录 B；两份人格文件各微调 ≤6%（追加式，未重写）。
- **本轮新增经验 6 条**：总监线 R148（选题双查）/ R149（终审两式）/ R150（预算配额）；PLC 线 R151（域闸覆盖断言）/ R152（锁存解除与码回放）/ R153（取整余量进位）。全局号段连续无重复。

## 10 遗留债清单（下轮排程首位）

1. **VERSION/MANUAL 补录债（R138）**：6 子库 `VERSION.md` / `MANUAL_DL_*.md` 未补 R27~R28 两轮，本轮**明确不做**，如实列债（连欠 2 轮，触及冻结线）。
2. **编译验证债**：连欠 **24 轮**（含本轮 2 件时间转换链：LaserTabWeldTrack / PumpDownEnvelopeMonitor）。
3. **R128 eFault 批量修**：6 件存量件 `eFault` 缺 CASE 标签未修。
4. Gantry 到位判定三平台实测（观察项）。
5. 机检规则待修：槽数按 POU 分型（R124）、输入集合差断言（R110/R151）。

## 11 下轮计划（R29）

①回归 **20 件/轮**常态，Motion / Algo 优先；②**编译验证债首偿**（三平台各一轮）；③VERSION/MANUAL 批量补录 R27~R28；④R128 eFault 批量修 6 件；⑤机检新增「同名断言 + 域闸集合差」两条并全库回归。
