# QA_REVIEW_R75（审校与去重官 · 2026-11-23）

范围：R75 新写盘 36 件 + 修复 4 件（CamTableInterp v1.0.2 / DryerExhaustHumidityCtl / WeightClassifySort / ChamberPurgeDry v1.0.1）= **40 件全量去重 + 抽检 40 件高危项**。
方法：registry 1252 名全量比对 → 结构指纹（VAR 名集 Jaccard，去注释）new×new 全组合 + new×邻件定向 → 12 项扫查压测（R6/R7/R10/R11/R1/R2/R4/占位符）。

## 1 三道去重结论：**拒收 0 件**

| 道 | 方法 | 命中 |
|---|---|---|
| 名称 | 40 名逐个对 registry 1252 名 | 4 命中，全为**修复件自身**（CamTableInterp / DryerExhaustHumidityCtl / WeightClassifySort / ChamberPurgeDry），新件 0 撞名 |
| 结构指纹 | VAR 名集 Jaccard（去注释），40×39/2 全组合 | 无 ≥0.5 对；最高 0.30（SpeedUnitConvert×TorqueUnitConvert，仅共享 `fValue/fValid/uErrorId` 体例引脚） |
| 语义同义 | 9 组高风险对逐一读实现 | 0 判重（1 件存疑放行，见 §4） |

高风险对判定依据（Jaccard + 读码）：
- `FB_DL_VocVentTrim` × RoomCo2DemandVent/VentPurgeDuty/NightPurgeCtrl = 0.05/0.07/0.02 → 非复制实现；**存疑放行**（见 §4）。
- `FB_DL_VfdStateWordMatch`(L1..87) × StatusWordSegDecoder = 0.02、`FB_DL_VfdCtrlWordBuild`(L1..97) × VfdGeneric = 0.00 → 在册件为「位段解码」，本二件为「状态号↔控制字互判/编码成对件」，职能不重叠，**有效变体**。
- `FB_DL_ManualOverride` × OverrideSelector/FeedOverrideRamp/HumidityOverride/CamOverrideTrim ≤0.07 → 在册件为「信号复用/斜坡/介质专用」，本件为「手动覆写+超时回落」，**有效变体**。
- `FC_DL_SpeedUnitConvert` × Angle/Flow/Torque 换算族 ≤0.30 → 在册**无 m/s↔km/h** 件（registry 关键词 speed/unit 零命中），**新增域**。
- `FC_DL_DwRealReinterp` × DwordToIntSat = 0.03 → 在册为整型饱和转换，本件为位级重解释，**不重叠**。
- `FC_DL_SettleTimeCalc`/`OvershootPctCalc` × LoopPerfIndex = 0.00/0.00 → 邻件为在线性能指标聚合 FB，本二件为离线阶跃响应单指标 FC，**互补**。
- `FB_DL_PeltierTempCtrl` × SplitRangeControl/GainSchedPid ≤0.10 → 本件为 TEC 双向极性+驻留泄流，**有效变体**。
- `FB_DL_SmokeDetZoneMon` × MachineGuardAudit/FreezeStatGuard ≤0.05 → 在册无多分区三态监视，**新增**。
- `FB_DL_SignalCrossbar8` × Mux2Ex/Mux4Ex ≤0.11 → 在册为选择器，本件为 8×8 路由矩阵，**新增形态**。

## 2 12 项扫查结果

- R6 CASE 无 ELSE：14 件含 CASE，**全部有 ELSE 兜底**（Peltier L181 / DeltaRobotIk L99 / Mold L231 均已核）。
- R7 TON/R_TRIG 条件调用：40 件**零命中**（全在段 0 无条件刷新，如 Peltier L92、Burner L95）。
- R1/R2 GVL·外部变量·物理地址：**零命中**。
- R10/R11 构造函数残留·分号缺失：L2 已过 + 抽读无残留；**零命中**。
- 占位符（TODO/略/...）：**零命中**。
- R4 除零：15 处「除以变量」全部核过——PowerFactor L37、GearRatio L41、MoistureContent L36、OvershootPct L45、CrankKinFwd L52（`fRodL <= fCrankR+fEps` 闸 → `fRad2>0`）、DeltaRobotIk L108/L116、Akima L82（升序闸）、CamTableInterp L71/L101 **均前置闸**。唯 Peltier 无除法。

## 3 缺陷明细

### MAJOR（1 件，必须返修）
**FB_DL_PeltierTempCtrl** — `DL_Algo/FB_DL_PeltierTempCtrl.st:130-131` + `:168-178`
判定式：`_fInt` 仅在 `L107`（复位沿）清零；`E_DL_PtcState.eSwitch`（L168-178）迁出到 eHeat/eCool 时**未清积分**。
后果：加热相累积的正积分在切到 eCool 后仍参与 `fRaw := fKp*fErr + _fInt`（L124/L133），fErr 已转负，旧正积分可压制输出符号 → 制冷极性下仍输出正向（加热）指令，直至积分反向退化完毕；限幅仅 ±fIntLim，属长时间错误极性驱动，与件内「过渡相泄流后干净起算」的边界②声明矛盾，TEC 温度控制安全侧。
建议修法：`eSwitch` 相每拍（或 `tonSw.Q` 迁出时）`_fInt := 0.0;`，并在头注释「边界②」补一条「极性切换即清积分（泄流口径）」。

### MINOR（仅记账，不返修）
1. `FB_DL_PeltierTempCtrl:124` `fRaw` 赋值后 L133 重算，死赋值。
2. `FC_DL_DwRealReinterp:97-99` 指数钳 −126：负次正规数（<2^-126）解码有量化偏差（自报 S06，属数值域口径，已在文档声明）。
3. `FC_DL_WorkdayCalendarCalc` 节假日固定表，不补调休（自报 S16，口径声明充分）。
4. `FB_DL_DeltaRobotIk` 单一装配解（肘部唯一解），头注释已声明「装配构型固定」，非缺陷。

### 编码专家自报 8 条风险复核（7 条判 PASS / 1 条升 MAJOR）
- BurnerFlameGuard 火焰丢失即时关阀：`L212-214` 主燃气阀**电平直断**（挂 `bFlameOk`），PASS。
- DeltaRobotIk 单解：`L107-116` 奇异性闸齐全，单解已声明，PASS。
- InjectionMoldClampSeq 中止不计数：`L210-232` 中止走 eOpen 撤离 → eIdle，仅 eDone 递增 `_uCycleCnt`，PASS。
- **PeltierCtrl 极性切换积分清零：自报「已处理」但代码未清 → 见 MAJOR。**
- VocVentTrim 邻件关系：见 §4 存疑放行。
- S06 次正规 / S16 节假日 / S17 锁存可达：S17（SmokeDetZoneMon 双锁存，L11-12 声明「报警至复位沿、故障至故障消失∧复位沿」双条件可达）PASS。

### 修复件 4 件合规确认
CamTableInterp v1.0.2：`uPointCnt` 入参 + `aCam` 固定上界 200 + 钳位 [2,200]（L69-74）+ 修改记录完整；调用方 `FB_DL_CamOverrideTrim:106` 已同步传 `uPointCnt`，**签名升级闭环，合规**。三件 v1.0.1 修复件抽读无新缺陷。

## 4 存疑放行（供总监复议）
`FB_DL_VocVentTrim`：与在册 `FB_DL_RoomCo2DemandVent` 控制律同构（比例 trim + 超限 boost）、I/O 形态同（模拟量入/阀门 % 出）。新增价值主张 = VOC 介质域（工业卫生限值）+ 独立 boost 出口口径 + 独立码段 16#0002_2501。结构仅 0.05，实现独立性成立。**建议放行但标记为「同构异介质第二例」，若后续出现第三例（如 PM2.5 通风）必须走族化重构而非再写新件。**

## 5 统计
| 项 | 数 |
|---|---|
| 审校件数 | 40（去重 40 + 抽检 40 高危项） |
| 拒收 | **0** |
| MAJOR | **1**（PeltierTempCtrl → 返修） |
| MINOR | 4（不返修） |
| PASS | **39 / 40** |
