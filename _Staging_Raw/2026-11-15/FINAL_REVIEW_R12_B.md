# R12 终审报告 · B 线（9 件）

> 角色：道莅工业代码库产品总监（兜底模式：专家子代理不可用，按既定兜底流程以本身份执行，拥有终审裁定权与定点修复权）
> 日期：2026-11-15　｜　规格依据：`_Staging_Raw/2026-11-15/ROUND_PLAN_R12.md` §1.2 码位表 + §3.10~3.18 逐件规格
> 机检基线：`audit_library_r12.py` 送审前 9 件 **fail=0**（12 项全 PASS）；修复后复核 **fail=0**

---

## 1 终审范围与结论

### 1.1 范围

B 线 9 件，均为状态机密集件（9 件里 8 件含 `CASE`，共 10 个枚举声明 / 48 个枚举成员、22 个定时器与边沿实例、3 个跨周期结构体）：

| # | 组件 | 目录 | 型 | 枚举成员 | A3 审计重点（状态量） |
|---|---|---|---|---|---|
| 1 | `FC_DL_WaterEnthalpy` | DL_Algo | FC | — | 无状态（仅 4 个中间量，段内单次写） |
| 2 | `FB_DL_ValveCharacteristic` | DL_Algo | FB | 3 + 3 | ePhase / fLast / fTravel / bClampLo·Hi |
| 3 | `FB_DL_DeviceParamVerify` | DL_Device | FB | 6 | ePhase / 明细出口 / stVerify 五字段 / bInit |
| 4 | `FB_DL_PortDiagBoard` | DL_Device | FB | 3 | ePhase / 首出锁存四元组 / 掩码基准 / bFaultLatch |
| 5 | `FB_DL_EnergyMeterAccum` | DL_Device | FB | 4 | ePhase / fImport·ExportAcc / 窗口累加与拍数 / bInitSync |
| 6 | `FB_DL_VacuumGaugeMux` | DL_Device | FB | 3 + 4 | ePhase / eSel / 双锁存 / fLast |
| 7 | `FB_DL_LineInterp2Axis` | DL_Motion | FB | 8 | ePhase / fS / fV / bDoneLatch / fPeak·fAccDist |
| 8 | `FB_DL_BatchPhaseBase` | DL_Process | FB | 11 | eState / nStep / bStepIssued·Acked / bHoldArmed·bStopArmed |
| 9 | `FB_DL_PollTempBank` | DL_Process | FB | 3 | ePhase / abDropped / anRecover / auCommFailCnt |

### 1.2 结论

**PASS with fixes**：9 件全部可入库，其中 **3 件判定 PASS 零修改**（WaterEnthalpy、PortDiagBoard、PollTempBank），**6 件修复后 PASS**（全部升 `v1.0.1`）。

- 缺陷 **8 条**：致命 **2** ／严重 **3** ／中等 **1** ／轻微 **2**，**全部当场定点修复**。
- 规格勘误 **10 处**（3 处本轮新发现，7 处经独立复核确认编码者留档成立）。
- 码位：9 件 48 个 `16#XXXX_XXXX` 字面量与 §1.2 分配块**逐一对齐**；全库 584 个码求差，**跨文件重叠 0、段外自创码 0、缺失 0**。
- 修复 **23 处定点编辑 / 6 个文件**（含 6 段修订留痕），无重构、无码位改动、无引脚契约变更。

### 1.3 本轮机检盲区定位（为什么 12 项全绿仍有 8 条缺陷）

| 缺陷 | 机检为何失明 | 只有人工能抓的原因 |
|---|---|---|
| B-D01 | 「实例在 CASE 之外调用」完全合规 | 机检无数据流分析，看不出 `IN` 表达式在三个相之间**连续为真**，即 ET 跨段累加 |
| B-D02 | 两个分支各自都写对了（判可用 / 取原值） | 缺陷在**跨拍**：判可用与取原值相隔一拍，机检不做跨扫描可达性推理 |
| B-D03 | 一行减法，两侧变量都已声明且都用过 | 缺陷是**量纲归属错**：`ET` 属于 `tPtUse` 而非 `tWinUse` |
| B-D04 | 判据 `fS >= fAccDist` 语法与语义在初始加速下都正确 | 只有构造「运行中途暂停再恢复」向量才能复现（R19 细则 3 的同族） |
| B-D05 | 两条赋值都合法，且「初值合法」 | 与头注释的**契约条款**冲突，属文档-代码一致性，机检只查注释存在性 |
| B-D06 | 清码点缺失不是语法错误 | 需推演「第二轮核对」的码优先级链 |
| B-D07 | 两个分支各自都对 | 是**覆盖次序**问题（段 9 覆盖 eDone 的赋值） |
| B-D08 | 注释双语齐全、格式合规 | 注释与实现语义相反，机检无法判定语义 |

---

## 2 逐件审计结论表（A1~A12）

图例：✔ 通过｜✘ 不通过（已修）｜N/A 本件不适用｜✔* 通过但附观察项

| 组件 | A1 | A2 | A3 | A4 | A5 | A6 | A7 | A8 | A9 | A10 | A11 | A12 | 缺陷数 | 版本 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `FC_DL_WaterEnthalpy` | N/A | ✔ | N/A | N/A | N/A | N/A | ✔ | N/A | ✔ | ✔ | N/A | ✔ | 0 | 1.0.0 |
| `FB_DL_ValveCharacteristic` | ✔3+3 | ✔ | ✔ | N/A | ✔ | N/A | ✔ | ✔ | ✔ | ✔ | N/A | ✔ | 1 | **1.0.1** |
| `FB_DL_DeviceParamVerify` | ✔6 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔* | ✔ | ✔ | N/A | ✔ | 1 | **1.0.1** |
| `FB_DL_PortDiagBoard` | ✔3 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 0 | 1.0.0 |
| `FB_DL_EnergyMeterAccum` | ✔4 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 1 | **1.0.1** |
| `FB_DL_VacuumGaugeMux` | ✔3+4 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 1 | **1.0.1** |
| `FB_DL_LineInterp2Axis` | ✔8 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 2 | **1.0.1** |
| `FB_DL_BatchPhaseBase` | ✔11 | ✔ | ✔ | ✔ | ✔ | ✔ | N/A | ✔ | ✔ | ✔ | ✔ | ✔ | 2 | **1.0.1** |
| `FB_DL_PollTempBank` | ✔3 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 0 | 1.0.0 |

### 2.1 A1 枚举→CASE 双向映射表（逐成员抄录，逐个在 CASE 里找标签）

| 枚举（宿主） | 成员（编号） | CASE 标签 | 判定 |
|---|---|---|---|
| `E_DL_ValveCharState`（Valve） | eIdle(0) / eActive(10) / eFault(99) | 3/3 显式 + ELSE | ✔ |
| `E_DL_ValveCharKind`（Valve） | eLinear(0) / eEqualPercent(10) / eQuickOpen(20) | 3/3 显式 + ELSE | ✔ |
| `E_DL_ParamVerifyPhase`（ParamVerify） | eIdle(0) / eWaiting(10) / eComparing(20) / eMatch(30) / eMismatch(40) / eFault(99) | 6/6 显式 + ELSE | ✔ |
| `E_DL_BoardPhase`（PortDiag） | eIdle(0) / eScanning(10) / eFault(99) | 3/3 显式 + ELSE | ✔ |
| `E_DL_MeterPhase`（Energy） | eIdle(0) / eSampling(10) / eHeld(20) / eFault(99) | 4/4 显式 + ELSE | ✔ |
| `E_DL_GaugePhase`（Vacuum） | eIdle(0) / eSelect(10) / eOverlapCheck(20) / eFault(99) | 4/4 显式 + ELSE | ✔ |
| `E_DL_GaugeSel`（Vacuum） | eNone(0) / ePirani(10) / eCapacitance(20) | 3/3 显式 + ELSE（取值 CASE 保留，未因修复被删） | ✔ |
| `E_DL_LineInterpPhase`（Interp） | eIdle(0)/ePrep(10)/eAccel(20)/eCruise(30)/eDecel(40)/eDone(50)/eHeld(60)/eFault(99) | 8/8 显式 + ELSE | ✔ |
| `E_DL_BatchPhaseState`（Batch） | eIdle(0)/eRunning(10)/eCompleting(20)/eComplete(30)/eHolding(40)/eHeld(50)/eRestarting(60)/eStopping(70)/eStopped(80)/eAborting(90)/eAborted(99) | **11/11** 显式 + ELSE | ✔ |
| `E_DL_TempBankPhase`（PollTemp） | eIdle(0) / ePolling(10) / eFault(99) | 3/3 显式 + ELSE | ✔ |

结论：本轮 **无 R31 型缺标签**（连续两轮零复发）。所有 `ELSE` 兜底均落「终端安全态 + 本件码段末码」（2012 / 030C / 0312 / 0315 / 0207 / 0206 / 0209），无段外哨兵值。

### 2.2 A2 输出全路径赋值（含早退、ELSE、故障、超时、掉使能）

- 唯一**早退**件：`FC_DL_WaterEnthalpy` 段 2 的 `RETURN`（域外），4 个 `VAR_OUTPUT` + 函数返回值在段 1 已全部预置 ✔（这是本批唯一需要该检查的件）。
- `FB_DL_DeviceParamVerify` 首扫 `RETURN`：仅 `eState` 被赋值，其余出口停在上电默认值 0/FALSE。裁定 **可接受**（默认值即安全值），列入观察项 O-6。
- 掉使能路径：Valve 走 `fTravel := fLast` ✔、Energy 走 `eHeld` ✔、Batch 整体冻结 ✔、Vacuum/Interp/PortDiag/PollTemp 均由相保持 ✔。
- 故障分支：全部 5 个带故障相件在 `eFault` 内显式重写保持型出口（`fTravel := fLast` / `bVerified := FALSE` / `eQuality := eQualBad` / `bAnyFault := ...` / `fV := 0.0`）✔。

### 2.3 A3 状态量写入点排序（R32）

逐件列出「本拍全部写入点」并排序后，**1 处越序**（B-D05：eIdle 内以清零式赋值冒充初始化，压住保持语义）；其余各件满足「唯一位移点 + 互斥分支」，典型如下：

- PortDiag `ePhase`：eIdle 内 4 个互斥出口（保持待机 / 0309 / 030A / 转扫描）+ eScanning 回待机 + ELSE 兜底 + 段 6 复位 + 首扫 = 8 个写入点，同拍至多命中 1 个 ✔；
- Energy `fImportAcc`：首拍装载 → 换表重载 / 抖动不写 / 正常递推（三选一）→ 复位重装（`bInitSync := FALSE` 后由首拍分支重载），互斥 ✔；
- Batch `nStep`：eIdle 清 0、启动置 1、边界推进 +1、复位清 0、段 4 负值防御——五处分布在不同相/不同分支，互斥 ✔；
- Interp `fS`：加速/匀速/减速三段各自积分、eDone 钳位、eIdle 与 eHeld 保持、复位清零，互斥 ✔（修复后 eHeld 新增分支不写 `fS`，仍互斥）。

### 2.4 A4 首扫标志范式（R19）

7 件带 `bInit`：PortDiag / Energy / Vacuum / Interp / Batch / PollTemp / ParamVerify 全部为 `IF NOT bInit THEN … bInit := TRUE; END_IF`（ParamVerify 为「显式首扫分支 + RETURN」，属 R19 允许的第二种合法形态）。**未出现 `IF bInit OR bTrack THEN` 反向范式**。

### 2.5 A5 定时器/边沿实例

22 个实例（`R_TRIG ×17` / `TON ×5`）全部在 CASE 之外无条件调用；`Q` 一律在调用之后读取；自清语句一律在调用之后（`bWinBreak` / `bSecDone` / 新增 `bStepWatchBreak`）。修复 B-D01 时严格遵守该次序（自清置于 `bStepTo` 取值之后）。

### 2.6 A6 单拍标志生命周期（R25/R34）

逐标志指认清除点：`bMeterReset`(段1预清) / `bUpdateOut`(段1) / `bRequestStep`·`bRequestAbort`(段1) / `bDropEvent`(段1) / `bWinBreak`(调用后自清) / `bDoneLatch`(启动沿清) / `bAckUse`(每拍取沿)。**无只置不销**。修复新增的 `bStepWatchBreak` 采用「置位点唯一 + 调用后自清」，满足四律。

### 2.7 A7 边界防错真实性

| 件 | 除零面 | 判界 | 浮点比较 | 非有限值 |
|---|---|---|---|---|
| WaterEnthalpy | `fH/fT` 前 `ABS(fT) > 1.0` ✔ | 无数组 | 域判用区间不用判等 ✔ | NaN 由「正向区间取反」拦 ✔ |
| Valve | `100.0` 常量 / `fR ≥ 2` / `LN(fR)` 二次守卫 ✔ | 无数组 | 死区用容差 ✔ | 流量 NaN 被 `NOT(x>=0)` 拦；`fR` NaN 落上限 ✔ |
| ParamVerify | 无除法 | 上界取钳位后 `nCountUse`、WHILE 双守卫 ✔ | 偏差用 `>` 容差 ✔ | `±DL_ABS_MAX` 双向拦 ✔ |
| PortDiag | 无除法 | 全部 `1..4`/`1..8`/`1..16` 常量化 + 守卫 EXIT ✔ | 位判用 `<> 0` ✔ | 无浮点 |
| Energy | `fWinSec ≥ 1.0`、`fLsbUse` 非正落兜底 ✔ | 无数组 | 回退判据用比例阈值 ✔ | 功率 NaN 自身比较 + 幅值上下界 ✔ |
| Vacuum | `LN` 前 `≥ 1e-9` 三道闸 ✔ | 无数组 | 十倍程差用 `>` 容差 ✔ | 读数有限性双闸 ✔（门限参数 NaN 未拦，观察项 O-5） |
| Interp | `fLen` 判零闸 + `fAccUse > 0` ✔ | 无数组 | 三角判据用 `>` 临界同支 ✔ | 8 个入参 NaN + 4 个幅值界 ✔ |
| Batch | 无除法 | 无数组 | 时间用 TIME 整数比较 ✔ | 无浮点 |
| PollTemp | 无除法（增益只乘） | `i ≤ nDevUse`、`k+1 ≤ nDevUse`、全部 FOR 带守卫 ✔ | 有效域用区间 ✔ | `fVal` 有限判定 ✔ |

### 2.8 A8 饱和判据同向（R35）与终态可达性

- 唯一饱和计数器族：PollTemp `auCommFailCnt`（守卫 `< 9999`、判据 `>= nDropUse`、阈值 ≤10）——**三元一致、方向同向** ✔；PortDiag `nTotal`/`nBitScan` 为上界受控计数 ✔。
- 终态可达性：7 件的 `eFault` 均「bReset 上升沿 → eIdle」可达 ✔；Batch 三终态（Complete/Stopped/Aborted）**均可复位回 eIdle 再启动** ✔（无终态死锁）；Interp `eDone → bStart → ePrep` ✔。
- 唯一「单向终态」：ParamVerify `eMatch` 仅复位可出（观察项 O-1，不阻塞）。
- 超时分支死代码检查：Energy `fbTimeout` 类无；Batch `fbStepWatch` **修复前非死代码但口径错**（B-D01），修复后按步重计时；ParamVerify `tVerifyTimeout = 0` 分支显式放行 ✔。

### 2.9 A9 验收向量独立复算

见 §4，9 件共复算 **22 组**（每件 ≥2 组），全部与实现一致；**未发现「公式对、向量错」型勘误**（规格向量本轮全对，错的是实现）。

### 2.10 A10 码位一致性

§1.2 分配 vs 文件字面量，逐码比对：**48/48 一致**；全库 584 码求差无重叠、无越段、无自创。特判 `0003_0105`（禁占）/`0003_0116`（预留）/`0003_0281`（预留）三处本轮零触碰。

### 2.11 A11 运动/工艺时序专项

| 检查点 | Interp | Batch | PollTemp | PortDiag |
|---|---|---|---|---|
| 剩余距离/速度归一化分母 | `fTmpX=fMaxSpeedX/\|fUx\|`，先与 `fPathSpeed` 取 MIN 的顺序正确 ✔ | N/A | N/A | N/A |
| 段/步切换末段残差 | 减速出口 `fS := fLen` 残差恒 0、进度强制 100 ✔ | 步骤边界单拍请求，nStep 不重复推进 ✔ | N/A | 组/端口双循环回绕靠常量化上界 ✔ |
| 反馈常高卡死 | N/A | `bStepAcked` + 完成上升沿双保险，常高不卡 ✔ | `abPollOk` 为电平，无沿依赖 ✔ | 掩码为电平，无沿依赖 ✔ |
| 索引回绕 / 通道数为 0 除零 | N/A | N/A | `nDevUse ≥ 1`、`i ≤ nDevUse`、`k+1` 判在界内 ✔ | 端口数 `<1` 先钳后扫 ✔ |
| 端口号越界钳位 | N/A | N/A | N/A | 位 `p > auPortCntUse[g]` 逐位清零 + 014B ✔ |

### 2.12 A12 量纲与单位注释一致性（R20）

逐件核对「注释单位 = 赋值表达式量纲推导」：全部一致；`TIME` 类统一注 `[毫秒]`（IEC TIME 基准为 ms，跨平台一致）；`fCycleEst [秒]` 与 `fWinSec [秒]`、`DL_MS_PER_SEC` 换算链路闭合。**未发现 ms/s 混写**（R20 家族本轮零复发）。

---

## 3 缺陷清单

| 编号 | 组件 | 严重度 | 现象 | 根因 | 修法 | 已修 |
|---|---|---|---|---|---|---|
| **B-D01** | `FB_DL_BatchPhaseBase` | **致命** | 3 步各 30 s、`tStepTimeout=60S` 的**完全合规批次**在第 3 步被判 0203 中止；进入收尾相时定时器往往已接近或超过 PT，收尾「进相即超时」 | `fbStepWatch` 的 `IN` 在执行/收尾/停止三相之间**连续为真**，步骤推进（`nStep+1`）与相迁移都不曾断输入，`ET` 跨步累加——「单步超时」退化为「相内累计超时」 | 新增 `bStepWatchBreak`：步骤边界（消费本次完成反馈处）置位；段 6 以 `NOT bStepWatchBreak` 串入 `IN`，并在 `bStepTo` 取值后自清，实现「断输入一拍、按步重计时」（R14 范式） | ✔ v1.0.1 |
| **B-D02** | `FB_DL_VacuumGaugeMux` | **致命** | 采信表在两相之间掉线时，`fPressurePa` 仍被写入该表原值（可能 0 或负）——工艺联锁据此可能判「已到真空」；与头注释「不死用任一表，避免坏表值直接进工艺联锁」正相反 | `eSelect`（判可用）与 `eOverlapCheck`（取值）相隔一拍；取值分支只在重叠区验 `bCapOk`，非重叠区按 `eSel` **直取原值**，未做本拍可用性复验 | 非重叠取值后以「取值表的本拍可用性」门控 `bUpdateOut`（电容取 `bCapOk`、其余取 `bPirOk`）；不可用则本拍不发布、`fPressurePa` 保持上次值，并回 `eSelect` 下拍重裁 | ✔ v1.0.1 |
| **B-D03** | `FB_DL_EnergyMeterAccum` | 严重 | 15 min 需量窗内暂停两次，实际窗口被拉长到约 1300 s，平均需量偏低约 31%（月结电量不受影响，**峰值需量与平均需量失真**） | 剩余时间按「整窗 `tWinUse` − `ET`」计算，但恢复后定时器预置值已是 `tRemain`，`ET` 属于该**剩余窗**；二次暂停把两个不同基准相减 | `tRemain := tPtUse - fbWindow.ET`（按本拍实际预置值求差，两种模式通吃） | ✔ v1.0.1 |
| **B-D04** | `FB_DL_LineInterp2Axis` | 严重 | 暂停恢复后第一个扫描周期速度由 0 直接跳到 `fPeak`（V1 工况 100 mm/s）；位置连续但速度阶跃，伺服按位置给定跟随会报跟随误差 | 加速段出口只看 `fS >= fAccDist`；恢复时 `fS` 早已超过 `fAccDist`，加速段当拍即被判完成，`eCruise` 下一拍把 `fV` 赋成峰值 | 出口改 `(fS >= fAccDist) AND (fV >= fPeak)`；恢复时按剩余量分流（剩余 ≤ `fAccDist` 直接进 `eDecel`，避免再加速冲过终点） | ✔ v1.0.1 |
| **B-D05** | `FB_DL_ValveCharacteristic` | 严重 | 故障复位或首次投运当拍，阀位由上次值**直跳行程下限**（默认 0%）——调节阀突跳（水锤/批量扰动）；冷启动时 `fTravel` 还可能低于 `fMinTravel`（域外值），与出口契约「域为生效行程之间」矛盾 | `eIdle` 成功分支用 `fLast := fLoTravel; fTravel := fLoTravel` 做「初始化」，把清零式赋值挂在状态迁移路径上（R32 家族），且与本件「不做阀位回零、突跳比保持更危险」条款自相矛盾 | 改为 `fLast := MIN(MAX(fLast, fLoTravel), fHiTravel); fTravel := fLast`：保持上次阀位并夹进有效行程 | ✔ v1.0.1 |
| **B-D06** | `FB_DL_DeviceParamVerify` | 中等 | 第一轮一致（014E）后 `uErrorId` 永久驻留 014E：后续轮次的 014D/014F 因「仅当 `uErrorId=0` 才置码」被**永久压住**；不一致轮次出现「码说一致、结论说不一致」 | 信息级码只在复位沿清除，而复位同时清结论；核对周期本身没有清码点（R21 的「信息码只进趋势」被实现成「只进不清」） | 进入新一轮核对（`eIdle → eWaiting`）时清 `uErrorId` | ✔ v1.0.1 |
| **B-D07** | `FB_DL_LineInterp2Axis` | 轻微 | 零长度路径完成时 `fPathProgress` 输出 0，与头注释验收 V3「进度 100」及 `eDone` 分支的显式赋值矛盾（画面在「已完成」与「0%」间打架） | 段 9 的 `fLen <= DL_LEN_MIN` 分支无条件写 0，覆盖了 `eDone` 的赋值 | 该分支补「完成相满值」判定（`ELSIF ePhase = eDone THEN 100`） | ✔ v1.0.1 |
| **B-D08** | `FB_DL_BatchPhaseBase` | 轻微 | `bStart` 引脚注释写「仅空闲与已终止态受理」，实现只在 `eIdle` 受理（终止态须先 `bReset`），与语义要点 ④ 相反；按注释接线会在终止态反复给启动沿而毫无响应 | 注释按早期草稿写入，未随实现收敛 | 注释更正为「仅空闲态受理（已终止态须先复位）」 | ✔ v1.0.1 |

### 3.1 规格勘误（10 处）

| 编号 | 规格位置 | 规格原文 | 矛盾/错误 | 裁定 |
|---|---|---|---|---|
| E-01 | §3.11 算法要点 | 输入钳位置 2004/2005/2006 | §1.2 只给本件 2001~2003 与 2010~2012，三个码不存在 | **规格错**：按码位表为准，流量越界并入 2001/2002，可调比与死区只钳位不置码（代码已如此，留档成立） |
| E-02 | §3.10 边界与防错 | 2102 =「`bUseMeanCp=TRUE` 但温度为 0」 | 同节 V3 未要求 `bUseMeanCp` | **规格错**：2102 应为「温度落在零度点即置码」；代码取此口径 ✔ |
| E-03 | §3.12 边界与防错 | 「`nDiffCount` / `fMaxDev` 每拍重算」 | 与同节状态机「`eComparing` 单拍一次遍历」互斥（每拍重算即每拍遍历） | **规格错**：取单拍遍历、结论相保持；代码无偏离留档，本轮补记（观察项 O-2） |
| E-04 | §3.13 算法要点 vs 边界 | 端口数 >8 → 014A；端口数越界 → 030A | 同节两处口径冲突 | **规格含糊**：按语义拆分（>8 组态多填→014A 信息级；<1 无有效端口→030A 故障级），与 V5 一致 ✔ |
| E-05 | §3.14 算法要点 | 换表判据「低于累计值 − 回退比例 × 32 位满量程 × 标定系数」 | 1% × 4.29 亿 kWh ≈ 4.29e6 kWh，远大于 V3 的 10000.1，**换表永远判不出**，向量与公式互斥 | **规格错**：改为按累计值比例（`acc × (1−ratio)`），与 V3 一致 ✔ |
| E-06 | §3.14 窗口积分 | 「周期取窗口秒数 ÷ 拍数」 | 首窗拍数未知（循环定义） | **规格错**：首窗用常量化标称周期，结算时用实测拍数刷新 ✔ |
| E-07 | §3.15 算法要点 | 「仅重叠区内交叉校验」 | V2（100 与 1，明显在重叠区外）仍要求判不一致 | **规格错**：只要两表均可用即校验（更保守），重叠区标志仅用于融合与画面 ✔ |
| E-08 | §3.17 要点 7 | 「`eCompleting` 也发 `bRequestStep`」+「收尾动作由调用方以 `ePhase = eCompleting` 触发」 | 两句互斥；且收尾相 `nStepNo` 仍是最后一步，再发请求会诱导调用方**重跑最后一步** | **规格错**：取后者（收尾不由 `bRequestStep` 触发）；代码未留档，本轮补记 |
| E-09 | §3.18 正文 | 提到「评估相」 | §2.1 枚举只有三成员 | **规格错**：评估并入轮询相 ✔ |
| E-10 | §3.14 拼装 | 「`eBadc` 等非 `eAbcd` 时先交换两字」 | 复用枚举中 `eBadc` = 寄存器内字节互换、`eDcba` = 四字节全反序，与「字间交换」是三种不同变换；折叠成一个行为会让这两个成员的用户**静默拿到错值** | **规格设计缺陷**（本轮新发现）：建议 v1.1 只接受 `eAbcd` / `eCdab`，其余落信息码；本轮不改码位，列观察项 O-4 |

---

## 4 验收向量独立复算表

复算口径：不采信规格给出的结果，按实现表达式独立计算（脚本 + 手算双轨），误差按规格容差判定。

| # | 组件 | 向量（输入） | 独立复算 | 规格期望 | 判定 |
|---|---|---|---|---|---|
| 1 | WaterEnthalpy | T=100 °C | 421.76 − 7.18 + 4.7333 = **419.3133**；cp=419.3133/100=**4.1931** | 419.31±0.05 / 4.1931±0.002 | ✔ |
| 2 | WaterEnthalpy | T=20 °C | 84.352 − 0.2872 + 0.03787 = **84.1027** | 84.10±0.05 | ✔ |
| 3 | WaterEnthalpy | T=50 °C | 210.88 − 1.795 + 0.59166 = **209.6767** | 209.68±0.05 | ✔ |
| 4 | WaterEnthalpy | T=0 °C | h=0，cp 退化为 C1=**4.2176**，码 2102 | 同 | ✔ |
| 5 | Valve | 等百分比 R=30，Q=50% | q=0.5 > 1/30；100×(1−0.693147/3.401197)=**79.6205** | 79.6±0.1 | ✔ |
| 6 | Valve | 快开 Q=75% | 100×(1−√0.25)=**50.0** | 50.0 | ✔ |
| 7 | Valve | 等百分比 Q=2% | q=0.02 < 0.03333 → raw=**0.0**，bSaturated=TRUE、2001 | 同 | ✔ |
| 8 | Valve | 边界自加：Q=5%（q=0.05>1/30） | 100×(1+ln0.05/ln30)=**11.9212**（未在规格内，验证下限切换不跳变：0→11.92 连续段起点） | — | ✔ 自算 |
| 9 | ParamVerify | 三项全等 | dev=0 → diff=0、first=0、maxDev=0、maxIdx=0 | 同 | ✔ |
| 10 | ParamVerify | 第 2 项 0.62 vs 0.5，tol 0.01 | dev=**0.12** > 0.01 → diff=1、first=2、maxDev=0.12、maxIdx=2 | 同 | ✔ |
| 11 | ParamVerify | tol[2]=0 回落 0.2 | 0.12 ≤ 0.2 → diff=0、bVerified=TRUE | 同 | ✔ |
| 12 | PortDiag | 1 组 8 端口、掩码 16#0101 | bit8=端口 9 超界 → 屏蔽为 **16#0001**、total=1、1/1、014B | 同 | ✔ |
| 13 | PortDiag | 2 组、掩码 16#0004 / 16#0003 | total=**3**、首出 1/3、Top=**[13,21,22]** | 同 | ✔ |
| 14 | PortDiag | 组数 0 | 钳 1、bGroupShort → 0309、bError=TRUE | 同 | ✔ |
| 15 | Energy | Hi=1、Lo=16#86A0 | raw=65536+34464=**100000** → 100000×0.1=**10000.0** kWh | 10000.0 | ✔ |
| 16 | Energy | 下拍 Lo+1 | raw=100001 → **10000.1**，增量 0.1；阈值 10000.1×0.99=**9900.099** < 10000.1 → 非换表 | 同 | ✔ |
| 17 | Energy | Lo=5（0.5 kWh） | 0.5 < 9900.099 → 换表单拍、count=1、acc=**0.5**、无负增量 | 同 | ✔ |
| 18 | Energy | 100 kW × 900 s | E=**25.0** kWh；需量=25/900×3600=**100.0** kW；峰值 100.0 | 同 | ✔ |
| 19 | Vacuum | SW=10、重叠 1 decade | lo=10/10^0.5=**3.1623**、hi=10；15>10 → 不重叠、选皮拉尼、输出 15.0 | 同 | ✔ |
| 20 | Vacuum | 6 Pa vs 4 Pa | Δ=log10(6)−log10(4)=**0.1761** ≤ 0.5 → 一致；6∈[3.162,10] → 取电容 **4.0**、eGood | 同 | ✔ |
| 21 | Vacuum | 100 Pa vs 1 Pa | Δ=**2.0000** > 0.5 → 锁不一致、0314、输出保持 | 同 | ✔ |
| 22 | Interp | L=500、v=100、a=200 | 单轴折算 1000/0.6=1666.7、1000/0.8=1250 均>100 → vEff=100；accDist=**25**；2×25<500 → 梯形、peak=100；中点 X=**150**、Y=**200**、进度 50 | 同 | ✔ |
| 23 | Interp | fMaxSpeedX=50 | **83.3333**；X 分量 83.3333×0.6=**50.0000** 恰不超限；accDist=17.36 | 83.33±0.01 | ✔ |
| 24 | Interp | L=40（三角） | 2×25>40 → 三角：peak=√(200×40)=**89.443**、accDist=**20** | 89.44±0.05 | ✔ |
| 25 | Interp | L=50（临界） | 2×25=50 **不 >** 50 → 梯形、peak=100（临界同支，注释口径正确） | 同 | ✔ |
| 26 | Batch | 3 步、每步一次完成 | 1→2→3→Completing→Complete；**修复后**单步超时按步重计时，60 s/步的批次不再误中止 | 同 | ✔（修复后） |
| 27 | Batch | 第 2 步 `bHold` | Holding（`bStepIssued=TRUE`）→ 该步完成后 Held；`bRestart` → Restarting → Running，`nStepNo` 仍 2 | 同 | ✔ |
| 28 | Batch | 1 步、2 s 无完成 | TON 到点 → 0203、bError=TRUE | 同 | ✔ |
| 29 | Batch | done 与 fail 同拍 | 失败优先分支在前 → 0204 | 同 | ✔ |
| 30 | PollTemp | 253 / 250，gain 0.1 | **25.3 / 25.0**，dev **0.30**，mask 0，online 1 | 同 | ✔ |
| 31 | PollTemp | 3200 → 320 °C | 320 > 200 → 无效，mask **16#0002**，failCnt=1，温度保持 | 同 | ✔ |
| 32 | PollTemp | 3 拍连续失败 | 第 3 拍 failCnt=3 ≥ 3 → 摘除、mask **16#0004**、online−1、0109 | 同 | ✔ |

**自算新向量 3 组**（规格未给、由本轮补）：#8 阀门下限切换连续性、#17 换表后基准重载的零负增量、#26 修复后多步超时不误触发（这一组正是 B-D01 的复现向量）。

---

## 5 可沉淀新范式（建议 R37~R41）

### R37 分段监控定时器必须按段断输入一拍

> **规则**：凡「单步 / 单段 / 单相」语义的监控定时器，其 `IN` 不得跨段持续为真。段边界必须置「断输入一拍」标志（`bXxxBreak`），在实例调用**之后**自清；`IN` 表达式中必须串入 `NOT bXxxBreak`。
> **判据**：同一 `TON` 的 `IN` 在枚举的一个**连续态集合**内恒为真，且集合内存在段推进写入（计数器 +1、步骤号 +1），即判可疑——「累计超时」正在冒充「单段超时」。
> **来源**：本轮 B-D01（BatchPhaseBase 单步超时跨步累加，合规批次被误中止）。与 R14「定时器语义参数变化须断输入一拍」同族，但触发条件不同：R14 管**参数换相**，R37 管**逻辑跨段**。
> **验收**：必须含「N 段 × 每段耗时 < 超时 < N 段总耗时」向量——本条缺陷只有该向量能复现。

### R38 多相流水线的取值相必须在本拍复验数据源可用性

> **规则**：当「判可用性」与「取值/发布」被拆到两个相位（跨拍）时，取值前必须按**本拍**的可用性标志再验一次；「上一相已验过」不构成发布许可。跨相窗口 = 1 个扫描周期，足以让读数掉线。
> **判据**：取值语句所在分支内，若找不到与取值源一一对应的本拍可用性判断，即判可疑。
> **来源**：本轮 B-D02（VacuumGaugeMux 跨相失效把 0 Pa 写进融合压力）。与 R36「跨件调用必须手算退出跟踪首拍」同源：**跨时间点的状态假设都要重验**，只是 R36 跨件、R38 跨相。

### R39 以「保持」替代「回零」时，保持值必须落在有效域内

> **规则**：把「强制赋初值」改成「保持上次值」时，必须同时对保持值做域钳位（`MIN/MAX`）。否则冷启动首拍会输出域外值（阀位低于最小行程、压力为 0、给定为 0），反而制造新的安全问题。
> **判据**：出口引脚注释声明了「域 fMin~fMax」的件，其每条不参与计算的出口赋值路径都必须能追到一次钳位。
> **来源**：本轮 B-D05（ValveCharacteristic 复位归零；修法同时补齐冷启动域外值）。与 R27「输出保持语义」互补：R27 管**保持多久**，R39 管**保持什么值**。

### R40 恢复相的转出判据不得只看「已完成量」

> **规则**：暂停/中断恢复后回到某一段时，该段的转出判据若只比较「已完成量（位移 / 步数 / 计数）」与「该段的绝对终点」，恢复后必然当拍命中，导致该段被**整段跳过**；必须同时校验该段的过程量（速度 / 斜率 / 增量），或按剩余量分流到正确的段。
> **来源**：本轮 B-D04（LineInterp2Axis 恢复后速度由 0 跳到峰值）。R19 讲首扫判据反向，R40 讲**分段判据在恢复点失效**，两者同属「判据写成了标志的同义反复」。

### R41 周期型核对件的信息级码必须按核对周期清除

> **规则**：周期性核对（每轮产出一次结论）的件，信息级码若只在复位沿清除，首轮结论码会永久驻留：既压住后续轮次的码（因为「仅在码为零时置码」），又与后续结论矛盾。清码点必须与「新一轮开始」绑定。
> **来源**：本轮 B-D06（DeviceParamVerify 014E 永久驻留，与 bMismatch 结论矛盾）。R21 只规定「信息码不置 bError」，未规定**生命周期**，本条补齐。

---

## 6 观察项（不阻塞入库）

| 编号 | 组件 | 观察 | 建议 |
|---|---|---|---|
| O-1 | DeviceParamVerify | `eMatch` 仅复位可退出：上电核对一次后**不再复核**，「参数被误改」只能靠人工复位发现，与本件立项动机有张力 | v1.1 增设 `bReverify` 或允许确认沿触发复裁（引脚变更走 MINOR，需规格裁定） |
| O-2 | DeviceParamVerify | 头注释无「偏离留档」段，但实现与 §3.12「明细每拍重算」相左（E-03） | 随下轮文档线补偏离段 |
| O-3 | PortDiagBoard | `eIdle`/`eScanning` 交替推进，看板数据**每两拍刷新一次**；0149/014A/014B/030B 只在扫描拍出现（隔拍闪断） | 若 HMI 按单拍采样做趋势，需在文档中给出「两拍周期」提示 |
| O-4 | EnergyMeterAccum | 字序入参把 `eBadc`（寄存器内字节互换）/`eDcba`（四字节全反序）一并当作「交换两字」（E-10） | v1.1 收窄为只接受 `eAbcd`/`eCdab`，其余落信息码；本轮不改码位 |
| O-5 | VacuumGaugeMux | `fSwitchPa` / `fOverlapDecades` 为 NaN 时，门限变成 NaN（比较恒假）→ 永不切换且不报码 | 补有限性闸门（复用 `DL_P_MAX` 判据） |
| O-6 | DeviceParamVerify | 首扫 `RETURN` 只写 `eState`，其余出口停在上电默认值 | 可接受；若要求「首拍即定值」需补预置段 |
| O-7 | WaterEnthalpy | 2102 在 `0 < T ≤ 1.0` 也会置码（注释写「零度点」）；`bUseMeanCp` 的符号复核分支在域内恒不可达（死分支） | 注释改为「|T| ≤ 1 °C 的除法保护区」；死分支可保留下轮清理 |
| O-8 | BatchPhaseBase | `eHolding` 无超时（规格亦如此）：暂停请求已受理但步骤永不完成时，相永久停留，只能靠 `bAbort` 解除 | 可考虑把 `fbStepWatch` 的监视集合扩到 `eHolding` |
| O-9 | PollTempBank | `bEnable=FALSE` 期间评估整段跳过：质量掩码、最差通道、偏差全部保持旧值（掉使能不清诊断证据，属设计） | 文档写明「掉使能期间掩码不代表当前状态」 |
| O-10 | LineInterp2Axis | 恢复分流后，剩余距离落在 `(fAccDist, 2·fAccDist]` 带内仍可能在到点时被钳位硬停（残余局限，已写入偏离留档 ①） | v1.1 可做恢复重规划（按剩余量重算 `fPeak/fAccDist`） |

---

## 7 落盘清单

| 文件 | 版本 | 改动 |
|---|---|---|
| `DL_Algo/FB_DL_ValveCharacteristic.st` | 1.0.0 → **1.0.1** | eIdle 保持语义 + 行程域钳位；头注释依赖与修订 |
| `DL_Device/FB_DL_DeviceParamVerify.st` | 1.0.0 → **1.0.1** | eIdle 清信息级码；修订留痕 |
| `DL_Device/FB_DL_EnergyMeterAccum.st` | 1.0.0 → **1.0.1** | `tRemain` 基准修正；修订留痕 |
| `DL_Device/FB_DL_VacuumGaugeMux.st` | 1.0.0 → **1.0.1** | 跨相失效门控；修订留痕 |
| `DL_Motion/FB_DL_LineInterp2Axis.st` | 1.0.0 → **1.0.1** | 加速出口双条件 + 恢复分流 + 零长度进度；修订留痕 |
| `DL_Process/FB_DL_BatchPhaseBase.st` | 1.0.0 → **1.0.1** | `bStepWatchBreak` 新增并接线；`bStart` 注释更正；修订留痕 |
| `DL_Algo/FC_DL_WaterEnthalpy.st` | 1.0.0（未改） | — |
| `DL_Device/FB_DL_PortDiagBoard.st` | 1.0.0（未改） | — |
| `DL_Process/FB_DL_PollTempBank.st` | 1.0.0（未改） | — |

未触碰：`INDEX_REGISTRY.json`、JSONL、`ROADMAP.md`、任何 `.md`（除本报告）、其他泳道 `.st`、码位字面量。

**修后机检**：`python _Staging_Raw/2026-11-15/audit_library_r12.py --files <6 件>` → **files=6 fail=0**（12 项全 PASS，banned_hits=0，未声明标识符=0）；9 件合并复跑 → **files=9 fail=0**。
