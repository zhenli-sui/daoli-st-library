# ROUND_PLAN_R4 — Round 04 可编码级规格（DL_Algo · 16 组件）

> 日期：2026-11-15 ｜ 制定人：道莅工控代码库产品总监
> 范围（已锁定，不得改动）：Level 1 首库 `DL_Algo`，16 个组件，全部落 `C:\Library\DL_Algo\`
> 编码者须知：本文为唯一规格来源；引脚名、类型、默认值、单位必须逐字对齐；实现行数目标 200~340 行/文件（含头注释），零占位符；禁止出现带模式参数的巨无霸块，每个组件单一职责。

---

## 0 通用编码约定（16 个组件共同强制）

1. **采样周期**：一律 `tSampleTime : TIME := T#100MS` 输入引脚，内部换算为秒 `fDt := TIME_TO_REAL(tSampleTime) / 1000.0`；严禁依赖隐式扫描周期做积分/微分。`tSampleTime < T#10MS` 时钳位为 `T#10MS` 并置码 `16#0002_0002`。
2. **限幅**：所有输出限幅用 REAL 型 `rOutMin / rOutMax`；`rOutMin > rOutMax` 时二者对调并置码 `16#0002_0001`，不中断扫描。
3. **非有限值防御**：输入满足 `fX <> fX`（NaN）或 `ABS(fX) > 1.0E30`（Inf）时拒绝本拍更新、保持上一拍输出，置码 `16#0002_0004`。
4. **故障码段**：DL_Algo 统一使用 `16#0002_xxxx`；0 = 无故障。公共码：
   | 码 | 语义 | 处理 |
   |---|---|---|
   | 16#0002_0000 | 无故障 | — |
   | 16#0002_0001 | 参数越界已钳位 | 修正参数后自动恢复 |
   | 16#0002_0002 | 采样周期非法已钳位为 T#10MS | 修正 tSampleTime |
   | 16#0002_0004 | 输入非有限值已拒绝 | 检查上游信号链 |
   | 16#0002_0005 | 非法状态兜底（CASE ELSE） | 复位或断电重启 |
5. **状态机**：所有 FB 必须 ENUM + CASE + ELSE 兜底（ELSE 置故障态与 16#0002_0005）。滤波/调节类允许 MedianFilter 式「状态派生 + CASE 覆盖 + ELSE」结构。
6. **初始化无扰**：所有含积分/滤波历史的 FB 必须提供 `bTrack : BOOL` + `fTrackValue : REAL`（跟踪使能时输出立即跟随 fTrackValue、内部状态同步置位，保证投切无扰动）与首扫 `bInit` 自动跟踪。
7. **依赖红线**：本轮组件互相引用仅允许 `DL_Algo` 内部 + Level 0（`DL_Base` / `DL_MathData`）；禁止依赖 `DL_Device` / `DL_Motion` / `DL_Process`。
8. **禁用记号**：.st 全文（含注释）零命中禁用记号集合（机检按全文命中 = 0），一律用语义描述替代。

---

## 1 FB_DL_PidController — 单回路通用 PID 控制器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 8
- **function_tags**：`pid`, `mod-pid-control`, `oscat-basic`, `lgf-technology`, `anti-windup`, `bumpless-transfer`
- **功能语义**：单回路离散 PID，位置式与增量式由独立布尔 `bIncremental` 选择（不搞模式枚举堆功能）；含死区、积分分离、两级抗积分饱和（触限停积分 + 限幅反算回填）、手自动无扰切换。现场用途：温度/压力/流量单闭环调节主块，`DL_Device` 温控区与后续串级块的基石。
- **算法核心**：
  - 偏差 `fErr := fSetpoint - fActual`（fKp 为负即反作用，沿 OSCAT/西门子惯例）；死区：`ABS(fErr) < fDeadband` 时按 0 处理。
  - 位置式：`fInt += fKp * fErr * fDt / tTi(秒)`（Ti=T#0S 表示纯 PD，跳过积分）；微分项对偏差做一阶预滤波后 `fD := fKp * tTd / fDt * (fErrF - fErrFPrev)`（tTd=T#0S 关闭）。
  - 增量式：`fDelta := fKp*(fErr - fErrPrev1 + fErr*fDt/tTi + tTd/fDt*(fErr - 2*fErrPrev1 + fErrPrev2))`，`fOut += fDelta` 后限幅。
  - 抗饱和两级：输出触限 → 停止本拍积分（条件积分）；仍超限 → 反算 `fInt := fLim - fP - fD`（OSCAT FT_PIWL 思想，clean-room）。
  - 手动无扰：`bManual=TRUE` 时输出 `fManualValue`（钳位），同时令 `fInt := fManualOut - fP - fD`，恢复自动瞬间输出连续。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（总使能，FALSE 输出回 rOutMin）；`bManual: BOOL := FALSE`（TRUE=手动）；`fManualValue: REAL := 0.0`（手动输出值 [%]）；`fSetpoint: REAL := 0.0`（设定值 [EU]）；`fActual: REAL := 0.0`（过程值 [EU]）；`fKp: REAL := 1.0`（比例增益 [1]，负值=反作用）；`tTi: TIME := T#2S`（积分时间 [s]，0=无积分）；`tTd: TIME := T#0S`（微分时间 [s]，0=关闭微分）；`fDeadband: REAL := 0.0`（控制死区 [EU]，≥0）；`bIncremental: BOOL := FALSE`（TRUE=增量式）；`rOutMin: REAL := 0.0`（输出下限 [%]）；`rOutMax: REAL := 100.0`（输出上限 [%]）；`tSampleTime: TIME := T#100MS`；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`（跟踪值 [EU]）；`bReset: BOOL := FALSE`（上升沿清积分与故障）。
  - VAR_OUTPUT：`fOut: REAL`（控制输出 [%]）；`fErr: REAL`（偏差 [EU]）；`fIntPart: REAL`（积分分量 [%]，诊断用）；`bLimitHigh: BOOL`（触上限）；`bLimitLow: BOOL`（触下限）；`bActive: BOOL`（自动调节中）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fErrPrev1/fErrPrev2: REAL`（增量式历史偏差 [EU]）；`fErrF/fErrFPrev: REAL`（微分滤波偏差 [EU]）；`fbTrigReset: R_TRIG`；`eState: E_DL_PidState`；常量 `DL_PID_ERR_MAX: REAL := 1.0E10`（积分钳位上限 [EU·s]）。
- **ENUM 状态集** `E_DL_PidState`：`eIdle:=0`（使能关，输出=rOutMin）｜ `eAuto:=10`（自动调节）｜ `eManual:=20`（手动，积分同步跟踪）｜ `eFault:=99`（非法状态兜底进入，输出安全值）。CASE 覆盖四态 + ELSE。
- **边界防错**：tTi/tTd 为 0 时跳过对应项（合法，不置故障）；fDeadband 负值钳 0 置 0002_0001；fInt 绝对值超 DL_PID_ERR_MAX 强制钳位防 REAL 溢出；fErr 非 1E-6 判等；dt 防零走公共钳位。
- **故障码表**（组件特有）：`16#0002_0101` 输出饱和提示（信息级，逐拍重算）；`16#0002_0102` 手动值超限已钳位；公共码 0001/0002/0004/0005。
- **依赖**：无 DL_ 内部依赖（Level 0 允许）。

## 2 FB_DL_CascadePid — 主副双回路串级 PID

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 8
- **function_tags**：`pid`, `cascade-control`, `mod-pid-control`, `lgf-technology`, `bumpless-transfer`
- **功能语义**：主回路 PID 输出经限幅后作为副回路设定值，副回路输出驱动执行器；适用温控（主温度/副加热功率）、张力（主张力/副速度）。内部组合两个 `FB_DL_PidController` 实例，不自写 PID 律。
- **算法核心**：`fbPidMaster(fSetpoint=fSpMaster, fActual=fPvMaster)` → 主输出钳位到副设定域 → `fbPidSlave(fSetpoint=fSpSlave, fActual=fPvSlave)` → `fOut`。手动时副回路直接手动输出，主回路经 bTrack/fTrackValue 跟随 fSpSlave，回自动无跳变。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`bManual: BOOL := FALSE`；`fManualSlaveValue: REAL := 0.0`（副回路手动输出 [%]）；`fSpMaster: REAL := 0.0`（主设定 [EU]）；`fPvMaster: REAL := 0.0`（主过程值 [EU]）；`fPvSlave: REAL := 0.0`（副过程值 [EU]）；`fKpM: REAL := 1.0`（主回路增益 [1]）；`tTiM: TIME := T#5S`；`tTdM: TIME := T#0S`；`fKpS: REAL := 2.0`（副回路增益 [1]，默认更硬）；`tTiS: TIME := T#1S`；`tTdS: TIME := T#0S`；`rSpSlaveMin: REAL := 0.0`（副设定下限 [EU]）；`rSpSlaveMax: REAL := 100.0`；`rOutMin: REAL := 0.0`；`rOutMax: REAL := 100.0`；`tSampleTime: TIME := T#100MS`；`bReset: BOOL := FALSE`。
  - VAR_OUTPUT：`fOut: REAL`（副回路输出 [%]）；`fSpSlave: REAL`（副设定值 [EU]，诊断）；`fErrMaster: REAL`（主偏差 [EU]）；`bLimitHigh/bLimitLow: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fbPidMaster : FB_DL_PidController`（主回路实例）；`fbPidSlave : FB_DL_PidController`（副回路实例）；`eState: E_DL_CascadeState`。
- **ENUM 状态集** `E_DL_CascadeState`：`eIdle:=0` ｜ `eCascade:=10`（双回路自动）｜ `eManual:=20` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：rSpSlaveMin>Max 时对调置 0002_0001；两个实例的 tSampleTime/rOutMin/rOutMax 统一由本块注入，禁止调用方双份配置产生不一致；主回路输出钳位到副设定域再进副回路（防副设定飞出量程）。
- **故障码表**：`16#0002_0201` 副设定超域已钳位（信息级）；公共码同上。
- **依赖**：`FB_DL_PidController`（DL_Algo 内部）。

## 3 FB_DL_SplitRangeControl — 分程输出分配

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 5
- **function_tags**：`split-range`, `mod-pid-control`, `output-allocation`, `lgf-technology`
- **功能语义**：把单一控制器输出（-100~100%）分配为两路执行器信号：正半区→加热通道、负半区→冷却通道（或开/关阀对），含中央死区间隙防双阀同开。现场用途：温控冷热双执行器、蒸汽/冷水阀对。
- **算法核心**：`fCtrlIn > fGap` → `fOutHeat := fCtrlIn / fCtrlMax * 100.0`，`fOutCool := 0`；`fCtrlIn < -fGap` → 冷却通道取幅值映射；中间 → 两路均为 0。输出各自按 rOutHeatMin..Max / rOutCoolMin..Max 二次映射（分程阀量程不同场景）。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fCtrlIn: REAL := 0.0`（控制器输出 [%]，-100..100）；`fGap: REAL := 2.0`（中央死区 [%]，≥0）；`rCtrlMax: REAL := 100.0`（输入满量程幅值 [%]，>0）；`rOutHeatMin: REAL := 0.0`（加热通道输出下限 [%]）；`rOutHeatMax: REAL := 100.0`；`rOutCoolMin: REAL := 0.0`；`rOutCoolMax: REAL := 100.0`；`bInvertHeat: BOOL := FALSE`（加热通道反相输出 100-x）；`tSampleTime: TIME := T#100MS`（仅用于一致性与未来扩展）。
  - VAR_OUTPUT：`fOutHeat: REAL`（加热通道输出 [%]）；`fOutCool: REAL`（冷却通道输出 [%]）；`bHeatActive: BOOL`；`bCoolActive: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fHeatRaw/fCoolRaw: REAL`（映射中间量 [%]）；`eState: E_DL_SplitState`。
- **ENUM 状态集** `E_DL_SplitState`：`eIdle:=0` ｜ `eHeatZone:=10` ｜ `eDeadband:=20` ｜ `eCoolZone:=30` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：rCtrlMax ≤ 1E-6 钳位 100.0 置 0002_0003；fGap 负值钳 0；输入超 ±rCtrlMax 钳位；通道量程 Min>Max 对调置 0002_0001。
- **故障码表**：`16#0002_0301` 输入满量程非法已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 4 FB_DL_FeedforwardComp — 静态+动态前馈补偿器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 6
- **function_tags**：`feedforward`, `lgf-technology`, `disturbance-compensation`, `dead-time`
- **功能语义**：对可测扰动量做前馈补偿：静态增益项即时响应 + 一阶惯性/超前滞后动态整形 + 可选纯滞后（延时队列），输出叠加到 PID 反馈通道，提升抗负载扰动速度。现场用途：配料设定突变、蒸汽压力波动的前馈。
- **算法核心**：静态项 `fStatic := fFfGain * fDisturbance`；动态项为一阶超前/滞后离散差分：`fDyn += (fLeadFactor * fDisturbance - fDyn) * fDt / max(tLagTime, fDt)`，`fLeadFactor := 1.0 + tLeadTime/fDt`；纯滞后项 `fDelayed := 队列(tDelayTime)` 取扰动历史；输出 `fFfOut := fStatic + fFfGain*(fDyn - fDelayed)` 后限幅。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fDisturbance: REAL := 0.0`（扰动量 [EU]）；`fFfGain: REAL := 1.0`（前馈增益 [1]）；`tLeadTime: TIME := T#0S`（超前时间 [s]，0=纯静态）；`tLagTime: TIME := T#0S`（惯性时间 [s]，0=直通）；`tDelayTime: TIME := T#0S`（纯滞后 [s]，0=无滞后队列）；`rOutMin: REAL := -100.0`；`rOutMax: REAL := 100.0`；`tSampleTime: TIME := T#100MS`；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`。
  - VAR_OUTPUT：`fFfOut: REAL`（前馈输出 [%]）；`fStaticPart: REAL`；`fDynPart: REAL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fDyn: REAL`（惯性环节状态 [EU]）；`fDynPrev: REAL`；`afDelayBuf: ARRAY[0..9] OF REAL`（滞后队列 [EU]，固定 10 槽）；`nDelaySteps: INT`（队列深度，tDelayTime/tSampleTime，0..10）；`nWriteIdx: INT`；`eState: E_DL_FfState`；常量 `DL_FF_DELAY_MAX: INT := 10`。
- **ENUM 状态集** `E_DL_FfState`：`eIdle:=0` ｜ `eStatic:=10`（仅静态）｜ `eDynamic:=20`（动态+滞后）｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：tLagTime<tSampleTime 时按一拍直通处理；tDelayTime 折算队列深度 > DL_FF_DELAY_MAX 时钳位并置 0002_0402；tLeadTime 负值钳 0；fFfGain 非 1E-6 判等。
- **故障码表**：`16#0002_0401` 动态时间非法已钳位；`16#0002_0402` 滞后队列深度超上限已截断；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 5 FB_DL_SmithPredictor — 纯滞后补偿（史密斯预估器）

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 9
- **function_tags**：`smith-predictor`, `dead-time-compensation`, `lgf-technology`, `mod-pid-control`, `pid`
- **功能语义**：大滞后对象（长管道加热、烘箱）专用：内部按一阶+纯滞后模型实时仿真「若无滞后过程会如何响应」，用补偿后误差驱动内嵌 PID，等效消除纯滞后对环路稳定性的破坏。内含 `FB_DL_PidController` 实例 + 模型延时队列。
- **算法核心**：模型 `fModelNoDelay += (fCtrlIn - fModelNoDelay) * fDt / max(tModelT, fDt)`（一阶惯性，增益折算 `* fModelK`）；经延时队列得 `fModelDelayed`；补偿误差 `fErrComp := fPv - (fModelDelayed + fModelBias)`（fModelBias 为模型静态偏差在线自适应校正：`fModelBias += fKb * (fPv - fModelDelayed - fModelBias) * fDt`，fKb 小增益）；内嵌 PID 用 fErrComp 做闭环。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`bManual: BOOL := FALSE`；`fManualValue: REAL := 0.0`；`fSetpoint: REAL := 0.0`（设定 [EU]）；`fPv: REAL := 0.0`（过程值 [EU]）；`fKp: REAL := 1.0`；`tTi: TIME := T#2S`；`tTd: TIME := T#0S`；`fModelK: REAL := 1.0`（对象模型增益 [EU/EU]）；`tModelT: TIME := T#5S`（模型惯性时间 [s]）；`tModelLag: TIME := T#1S`（模型纯滞后 [s]）；`rOutMin: REAL := 0.0`；`rOutMax: REAL := 100.0`；`tSampleTime: TIME := T#100MS`；`bReset: BOOL := FALSE`。
  - VAR_OUTPUT：`fCtrlOut: REAL`（控制器输出 [%]）；`fModelOut: REAL`（模型无滞后输出 [EU]，诊断）；`fErrComp: REAL`（补偿后偏差 [EU]，诊断）；`fModelBias: REAL`（模型自适应偏差 [EU]）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fbPid : FB_DL_PidController`（内嵌 PID）；`fModelState: REAL`（一阶模型状态 [EU]）；`afLagBuf: ARRAY[0..19] OF REAL`（模型滞后队列 [EU]，20 槽）；`nLagSteps: INT`；`nWriteIdx: INT`；`eState: E_DL_SmithState`；常量 `DL_SMITH_LAG_MAX: INT := 20`、`DL_SMITH_KB: REAL := 0.02`（偏差自适应增益 [1/s]）。
- **ENUM 状态集** `E_DL_SmithState`：`eIdle:=0` ｜ `eLearning:=10`（上电后队列填充、模型未闭合，输出 PID 用原始误差）｜ `eCompensating:=20`（队列满，全补偿）｜ `eManual:=30` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：fModelK=0 时模型输出恒 0 并置 0002_0501（不致闭环发散）；tModelT<tSampleTime 按一拍直通；tModelLag 折算深度超 20 钳位置 0002_0502；队列填充期自动退化为普通 PID（学习态），不阻塞控制。
- **故障码表**：`16#0002_0501` 模型增益非法；`16#0002_0502` 模型滞后超队列上限已截断；公共码同上。
- **依赖**：`FB_DL_PidController`（DL_Algo 内部）。

## 6 FB_DL_RampGenerator — 线性设定值斜坡发生器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 5
- **function_tags**：`ramp`, `setpoint-profiling`, `lgf-signalgen`, `lgf-technology`, `rate-limit`
- **功能语义**：把阶跃设定值变为按独立上升/下降速率（EU/s）平滑逼近的斜坡，支持暂停保持与跟踪回投。现场用途：烘箱程序升温、电机软给定、防操作员大阶跃冲击执行器。
- **算法核心**：`fDelta := fTarget - fOut`；上坡 `fStepMax := fRateUp * fDt`，下坡 `fStepMax := fRateDown * fDt`；`fOut += MIN(ABS(fDelta), fStepMax) * SIGN(fDelta)`；到达容差 `ABS(fDelta) <= DL_FLOAT_EPS` 置 bDone。斜率为 0 表示该方向冻结（不直通，防误操作）。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fTarget: REAL := 0.0`（目标值 [EU]）；`fRateUp: REAL := 10.0`（上升速率 [EU/s]，>0）；`fRateDown: REAL := 10.0`（下降速率 [EU/s]，>0）；`bHold: BOOL := FALSE`（TRUE 暂停在当前值）；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`；`rOutMin: REAL := -1.0E10`；`rOutMax: REAL := 1.0E10`；`tSampleTime: TIME := T#100MS`。
  - VAR_OUTPUT：`fOut: REAL`（斜坡输出 [EU]）；`bDone: BOOL`（到达目标）；`bMoving: BOOL`（斜坡进行中）；`fRemain: REAL`（距目标余量 [EU]）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fRateUpEff/fRateDownEff: REAL`（钳位后速率 [EU/s]）；`eState: E_DL_RampState`。
- **ENUM 状态集** `E_DL_RampState`：`eIdle:=0` ｜ `eHold:=10` ｜ `eRampUp:=20` ｜ `eRampDown:=30` ｜ `eDone:=40` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：速率 ≤0 钳位（≤0 视为非法）置 0002_0601 并保持上一拍输出；速率 > 1E10 钳位；目标越 rOutMin/rOutMax 时输出仍限幅、fTarget 不截断（到达判定以限幅后实际值为准防死等）；非有限值目标拒绝更新。
- **故障码表**：`16#0002_0601` 速率非法已钳位（信息级）；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 7 FB_DL_SCurveGenerator — 七段式 S 型加减速规划器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 9
- **function_tags**：`s-curve`, `trajectory-planning`, `jerk-limited`, `lgf-signalgen`, `lgf-technology`
- **功能语义**：限制加加速度 Jerk 的 S 型点到点轨迹：jerk→加速度→速度→位移四级积分链，七段相变控制，消除柔性冲击。现场用途：伺服点位给定前级、升降机构、注液泵平滑启停。
- **状态机状态表**（ENUM `E_DL_SCurveState`，CASE + ELSE）：
  | 状态 | 值 | 迁移条件 | 输出动作 |
  |---|---|---|---|
  | eIdle | 0 | bEnable && |fDist|>容差 → eAccJerkUp | 全部清零，输出保持 |
  | eAccJerkUp | 10 | fAcc ≥ fMaxAcc → eAccConst；剩余距离不足 → eDecJerkUp | jerk=+fMaxJerk 积分 |
  | eAccConst | 20 | fAcc 到达峰值时长满 → eAccJerkDown；距离不足 → 提前转减速段 | jerk=0，acc=fMaxAcc |
  | eAccJerkDown | 30 | fAcc ≤ 0 → eCruise 或直接 eDecJerkUp | jerk=-fMaxJerk 至 acc=0 |
  | eCruise | 40 | 剩余距离 ≤ fVel²/(2fMaxAcc)+裕量 → eDecJerkUp | vel=fMaxVel 匀速 |
  | eDecJerkUp | 50 | fDec ≥ fMaxAcc → eDecConst | jerk 使减速度线性增大 |
  | eDecConst | 60 | 剩余距离耗尽 → eDecJerkDown | 恒定减速度 |
  | eDecJerkDown | 70 | fAcc 回 0 && fVel ≤ 容差 → eDone | jerk 归零 |
  | eDone | 80 | 新目标 → eAccJerkUp | 输出=目标，bDone=TRUE |
  | eFault | 99 | — | CASE ELSE 进入，置 0002_0005 |
  - 工程化披露：段间精确对称闭式解（OSCAT/S 形标准推导）在 340 行内不可全量展开时，采用「每拍按剩余距离估算所需减速行程、不足即提前进入减速段」的自适应截断法，最大速度/加速度/Jerk 三约束仍全部满足；头注释必须披露此近似。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fTarget: REAL := 0.0`（目标位置 [EU]）；`fMaxVel: REAL := 100.0`（最大速度 [EU/s]）；`fMaxAcc: REAL := 200.0`（最大加速度 [EU/s²]）；`fMaxJerk: REAL := 1000.0`（最大加加速度 [EU/s³]）；`bAbort: BOOL := FALSE`（TRUE 立即按最大减速停车）；`tSampleTime: TIME := T#10MS`（默认 10ms，轨迹精度要求高）。
  - VAR_OUTPUT：`fOut: REAL`（输出位置 [EU]）；`fVel: REAL`（当前速度 [EU/s]）；`fAcc: REAL`（当前加速度 [EU/s²]）；`bDone: BOOL`；`bMoving: BOOL`；`bError: BOOL`；`uErrorId: UDINT`；`eState: E_DL_SCurveState`。
  - VAR：`fJerk: REAL`（当前 jerk [EU/s³]）；`fDist: REAL`（剩余距离 [EU]）；`eStateInt: E_DL_SCurveState`；常量 `DL_SC_EPS: REAL := 1.0E-6`、`DL_SC_BRK_MARGIN: REAL := 1.05`（减速行程裕量系数 [1]）。
- **边界防错**：fMaxJerk ≤0 钳位 fMaxAcc/tSampleTime 置 0002_0701；fMaxAcc ≤0 钳位 fMaxVel/tSampleTime；fMaxVel ≤0 钳位 1.0；bAbort 从任意运行态进最大减速路径（安全优先）；目标非有限值拒绝。
- **故障码表**：`16#0002_0701` 动态参数非法已钳位；`16#0002_0702` 相位卡死兜底（同一段持续超 1E4 拍强制进 eFault）；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 8 FB_DL_PwmDutyController — 时间比例慢速 PWM 控制器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 6
- **function_tags**：`pwm`, `time-proportional`, `ssr-drive`, `lgf-signalgen`, `mod-pid-control`
- **功能语义**：把 0~100% 占空比调制成周期级慢速 PWM 布尔输出，驱动固态继电器/接触器做加热功率调节；含最短开/关时间与不足脉冲跨周期累加补偿（PID_Compact 语义）。
- **算法核心**：周期内相位累加 `fPhase += fDt / tPeriod`，`fPhase ≥ 1.0` 回卷并结算本周期配额；`bPwmOut := fPhaseElapsed < fDutyEff/100.0`；最小开关时间不足的脉冲差额记入 `fDutyDebt`，下周期叠加。输出可与 PID 输出直连（0~100%）。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fDuty: REAL := 0.0`（占空比输入 [%]，0..100）；`tPeriod: TIME := T#10S`（PWM 周期 [s]，≥T#1S）；`tMinOn: TIME := T#500MS`（最短导通时间 [s]）；`tMinOff: TIME := T#500MS`（最短关断时间 [s]，两者之和须 < tPeriod）；`bInvert: BOOL := FALSE`（反相输出）。
  - VAR_OUTPUT：`bPwmOut: BOOL`（PWM 布尔输出）；`fDutyEff: REAL`（本周期实际有效占空比 [%]，含补偿）；`nCycleCount: UDINT`（已完成周期计数 [个]）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fPhase: REAL`（周期相位 [0..1]）；`fDutyEffInt: REAL`；`fDebt: REAL`（欠脉冲债务 [0..1]）；`bOnState: BOOL`；`eState: E_DL_PwmState`；常量 `DL_PWM_DUTY_MAX: REAL := 100.0`。
- **ENUM 状态集** `E_DL_PwmState`：`eIdle:=0` ｜ `eOnPhase:=10`（导通段）｜ `eOffPhase:=20`（关断段）｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：fDuty 越界钳位 0..100 置 0002_0001；tPeriod < tMinOn+tMinOff 时钳位 tPeriod := tMinOn+tMinOff 置 0002_0801；fDebt 钳位 0..1 防无限累积；使能跌落立即输出 FALSE 且债务清零。
- **故障码表**：`16#0002_0801` 周期小于最短开关时间和已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 9 FB_DL_RateLimiter — 变化率限制器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 4
- **function_tags**：`rate-limiter`, `slew-rate`, `lgf-technology`, `lgf-signalgen`
- **功能语义**：限制信号变化速率（对应 LGF LimRateOfChange 语义）：输入阶跃时输出以最大速率跟随，保护加热元件/执行器免受给定值阶跃冲击；上升与下降速率独立。
- **算法核心**：`fDeltaMax := fRate * fDt`；`fOut := fOut + MIN(ABS(fIn - fOut), fDeltaMax) * SIGN(fIn - fOut)`；fRateUp ≤0 表示上升方向不限速直通（LGF 惯例），负值非法按 0 处理置码。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（FALSE 直通）；`fIn: REAL := 0.0`（输入 [EU]）；`fRateUp: REAL := 0.0`（最大上升速率 [EU/s]，0=不限）；`fRateDown: REAL := 0.0`（最大下降速率 [EU/s]，0=不限）；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`。
  - VAR_OUTPUT：`fOut: REAL`（限速后输出 [EU]）；`bLimiting: BOOL`（限速进行中）；`fRateActual: REAL`（本拍实际变化率 [EU/s]）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`eState: E_DL_RateState`。
- **ENUM 状态集** `E_DL_RateState`：`eIdle:=0` ｜ `eFollow:=10`（不限速直通）｜ `eLimitUp:=20` ｜ `eLimitDown:=30` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：负速率置 0002_0001；fIn 非有限值拒绝（保持上拍）；两速率同为 0 时全直通（eFollow）。
- **故障码表**：公共码 0001/0002/0004/0005（无组件特有码）。
- **依赖**：无 DL_ 内部依赖。

## 10 FB_DL_LowPassFilter — 一阶低通数字滤波器（PT1）

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 5
- **function_tags**：`low-pass-filter`, `pt1`, `lgf-measurement`, `signal-conditioning`, `bumpless-transfer`
- **功能语义**：一阶惯性低通：`fAlpha = fDt / (fTf + fDt)`，`fOut += fAlpha * (fIn - fOut)`；时间常数运行中可调、变更即时重算 fAlpha；首扫与 bTrack 跟踪无滞后。现场用途：温度/压力模拟量采集降噪（LGF PT1 语义）。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（FALSE 直通）；`fIn: REAL := 0.0`（原始采样 [EU]）；`tTimeConst: TIME := T#1S`（滤波时间常数 [s]，0=直通）；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`。
  - VAR_OUTPUT：`fOut: REAL`（滤波输出 [EU]）；`fAlpha: REAL`（当前滤波系数 [0..1]，诊断）；`bValid: BOOL`（输出有效）；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fTfEff: REAL`（生效时间常数 [s]）；`eState: E_DL_LpfState`；常量 `DL_LPF_TF_MAX: REAL := 3600.0`（时间常数上限 [s]）。
- **ENUM 状态集** `E_DL_LpfState`：`eInit:=0`（首扫采样直通，bValid=FALSE）｜ `eRun:=10` ｜ `eTrack:=20` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：tTimeConst 负值或超 1h 钳位置 0002_1001；fAlpha ∈(0,1) 显式 MIN/MAX；非有限值输入拒绝；首扫 bInit 直接 fOut:=fIn。
- **故障码表**：`16#0002_1001` 时间常数非法已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 11 FB_DL_SecondOrderFilter — 二阶巴特沃斯低通滤波器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 7
- **function_tags**：`butterworth`, `second-order-filter`, `biquad`, `lgf-measurement`, `signal-conditioning`
- **功能语义**：二阶 Butterworth 低通（双二阶直接 II 型离散实现），较一阶更陡峭的高频衰减（-40dB/dec）；截止频率与采样周期变化时重算双线性变换系数。
- **算法核心**：双线性变换预计算（参数变更拍执行）：`fWc := 2*PI*fCutoff*fDt`；预畸变 `fK := TAN(fWc/2)`；归一化系数 `fNorm := 1 + SQRT2*fK + fK*fK`；`fB0 := fK*fK/fNorm`、`fB1 := 2*fB0`、`fB2 := fB0`、`fA1 := 2*(fK*fK - 1)/fNorm`、`fA2 := (1 - SQRT2*fK + fK*fK)/fNorm`；递推 `fOut := fB0*fIn + fB1*fIn1 + fB2*fIn2 - fA1*fW1 - fA2*fW2`。SQRT2 为常量 1.4142136。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`；`fIn: REAL := 0.0`（采样 [EU]）；`fCutoffFreq: REAL := 5.0`（截止频率 [Hz]，>0 且 < 1/(4*fDt)）；`bTrack: BOOL := FALSE`；`fTrackValue: REAL := 0.0`；`tSampleTime: TIME := T#100MS`。
  - VAR_OUTPUT：`fOut: REAL`；`bCoeffValid: BOOL`（系数就绪）；`bValid: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fB0/fB1/fB2/fA1/fA2: REAL`（滤波器系数 [1]）；`fIn1/fIn2: REAL`（输入历史 [EU]）；`fW1/fW2: REAL`（II 型状态 [EU]）；`bCoeffDirty: BOOL`（参数变更标记）；`eState: E_DL_SofState`；常量 `DL_SOF_SQRT2: REAL := 1.4142136`、`DL_SOF_PI: REAL := 3.1415927`。
- **ENUM 状态集** `E_DL_SofState`：`eInit:=0` ｜ `eCoeffCalc:=10`（参数变更拍重算系数）｜ `eRun:=20` ｜ `eTrack:=30` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：fCutoffFreq ≥ 采样频率/2 时钳位到 0.45*fSample 置 0002_1101（防奈奎斯特发散）；fCutoff ≤0 钳位 1 Hz；fA2 组合项接近 0 时（fK 极小）退化为直通；TAN 自变量钳位 <1.55 rad。
- **故障码表**：`16#0002_1101` 截止频率超奈奎斯特已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 12 FB_DL_HighPassFilter — 一阶高通滤波器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 5
- **function_tags**：`high-pass-filter`, `hp1`, `lgf-measurement`, `vibration-monitoring`, `signal-conditioning`
- **功能语义**：一阶高通：提取信号动态分量、隔离静态偏置；`fAlpha := tTf/(tTf+fDt)`，`fOut := fAlpha * (fOutPrev + fIn - fInPrev)`。现场用途：振动/位移传感器趋势分量剥离、皮带秤动态分量提取。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（FALSE 输出置 0）；`fIn: REAL := 0.0`（采样 [EU]）；`tTimeConst: TIME := T#1S`（高通时间常数 [s]，越大截止频率越低；0=全通差分）；`bTrack: BOOL := FALSE`（跟踪时 fOut 清零并同步历史）。
  - VAR_OUTPUT：`fOut: REAL`（动态分量输出 [EU]）；`fAlpha: REAL`（系数 [0..1]）；`bValid: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fInPrev: REAL`（上拍输入 [EU]）；`fTfEff: REAL`；`eState: E_DL_HpfState`；常量 `DL_HPF_TF_MAX: REAL := 3600.0`。
- **ENUM 状态集** `E_DL_HpfState`：`eInit:=0` ｜ `eRun:=10` ｜ `eTrack:=20` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：tTimeConst 越界钳位置 0002_1201；首扫 fInPrev:=fIn、fOut:=0（防上电脉冲）；非有限值拒绝并复位历史。
- **故障码表**：`16#0002_1201` 时间常数非法已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 13 FB_DL_Integrator — 梯形法离散积分器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 5
- **function_tags**：`integrator`, `trapezoidal`, `totalizer`, `oscat-basic`, `lgf-math`
- **功能语义**：梯形法高精度积分 `fOut += (fIn + fInPrev)/2 * fDt`；带上下限限幅、保持与复位。内部以 LREAL 累加（OSCAT FT_INT2 双精度防长时累积误差思想，输出转 REAL）。现场用途：流量累计、速度→位移、电量累计。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（FALSE 保持）；`fIn: REAL := 0.0`（被积量 [EU]）；`rOutMin: REAL := 0.0`（积分下限 [EU·s]）；`rOutMax: REAL := 1.0E12`（积分上限 [EU·s]）；`bHold: BOOL := FALSE`（TRUE 冻结）；`bReset: BOOL := FALSE`（电平清零）。
  - VAR_OUTPUT：`fOut: REAL`（积分结果 [EU·s]）；`bLimitHigh/bLimitLow: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fSumLReal: LREAL`（双精度累加器 [EU·s]）；`fInPrev: REAL`；`eState: E_DL_IntState`。
- **ENUM 状态集** `E_DL_IntState`：`eIdle:=0` ｜ `eHold:=10` ｜ `eIntegrating:=20` ｜ `eLimited:=30`（触限保持）｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：rOutMin>rOutMax 对调置 0002_0001；复位优先于积分（先判 bReset）；bReset 电平触发且保持期不积分；fSumLReal 超 1E30 钳位防溢出。
- **故障码表**：公共码 0001/0002/0004/0005。
- **依赖**：无 DL_ 内部依赖。

## 14 FB_DL_Differentiator — 带低通滤波的实用微分器

- **类型/目录/复杂度**：FB ｜ DL_Algo ｜ 6
- **function_tags**：`differentiator`, `rate-of-change`, `oscat-basic`, `lgf-measurement`, `noise-suppression`
- **功能语义**：差分商 `(fIn - fInPrev)/fDt` 计算变化率，后接一阶低通抑制高频噪声放大（对应 LGF DifferenceQuotientFB + PT1 组合语义）。现场用途：温度变化速率监控（趋势报警）、压装速度计算。
- **算法核心**：`fRawRate := (fIn - fInPrev) / fDt`；低通 `fRateOut += fAlpha*(fRawRate - fRateOut)`，`fAlpha := fDt/(fTf + fDt)`；rRateMin/rRateMax 限幅。
- **VAR 清单**：
  - VAR_INPUT：`bEnable: BOOL := FALSE`（FALSE 输出 0）；`fIn: REAL := 0.0`（被微分量 [EU]）；`tFiltTime: TIME := T#500MS`（速率低通时间常数 [s]，0=原始差分）；`rRateMin: REAL := -1.0E10`（速率下限 [EU/s]）；`rRateMax: REAL := 1.0E10`；`bTrack: BOOL := FALSE`。
  - VAR_OUTPUT：`fRateOut: REAL`（变化率输出 [EU/s]）；`fRawRate: REAL`（未滤波速率 [EU/s]，诊断）；`bValid: BOOL`；`bError: BOOL`；`uErrorId: UDINT`。
  - VAR：`fInPrev: REAL`；`fTfEff: REAL`；`eState: E_DL_DiffState`；常量 `DL_DIFF_TF_MAX: REAL := 60.0`。
- **ENUM 状态集** `E_DL_DiffState`：`eInit:=0`（首扫同步历史，输出 0）｜ `eRun:=10` ｜ `eTrack:=20` ｜ `eFault:=99`；CASE + ELSE。
- **边界防错**：dt 走公共钳位防除零；tFiltTime 越界钳位置 0002_1401；首扫 fInPrev:=fIn（防上电尖峰）；非有限值拒绝且清历史。
- **故障码表**：`16#0002_1401` 滤波时间常数非法已钳位；公共码同上。
- **依赖**：无 DL_ 内部依赖。

## 15 FC_DL_DewPointCalc — Magnus-Tetens 露点温度计算

- **类型/目录/复杂度**：FC（返回值 REAL = 露点温度 [°C]）｜ DL_Algo ｜ 4
- **function_tags**：`dew-point`, `magnus-tetens`, `hvac`, `oscat-basic`, `psychrometrics`
- **功能语义**：由干球温度与相对湿度计算露点温度（Magnus-Tetens/Stull 近似），用于洁净室/干燥房环控、冷面结露风险判断（表面温度低于露点即结露）。输出另附水汽压供焓值类后续组件复用。
- **公式**：`fGamma := LN(fRh/100.0) + 17.625*fTempC/(243.04 + fTempC)`；`FC_DL_DewPointCalc := 243.04*fGamma/(17.625 - fGamma)`；水汽压 `fVaporPa := 611.2 * EXP(17.625*fTempC/(243.04 + fTempC)) * fRh/100.0`。
- **VAR 清单**：
  - VAR_INPUT：`fTempC: REAL`（干球温度 [°C]，有效域 -40..60）；`fRhPct: REAL`（相对湿度 [%]，有效域 1..100）。
  - VAR_OUTPUT：`uErrorId: UDINT`（0=无故障）；`fVaporPa: REAL`（实际水汽压 [Pa]，诊断/复用）；`bInRange: BOOL`（输入是否处于公式有效域）。
  - VAR：`fGamma: REAL`（中间量 [1]）；`fRhEff: REAL`（钳位后湿度 [%]）；`fTempEff: REAL`（钳位后温度 [°C]）；常量 `DL_DEW_A: REAL := 17.625`、`DL_DEW_C: REAL := 243.04`（[°C]）、`DL_DEW_E0: REAL := 611.2`（[Pa]）、`DL_DEW_T_MIN/MAX: REAL := -40.0/60.0`、`DL_DEW_RH_MIN: REAL := 0.1`（[%，防 LN(0) 发散的工程下限]）、`DL_DEW_EPS: REAL := 1.0E-6`。
- **出口默认值（IEC 61131-3 强制）**：入口即赋 `FC_DL_DewPointCalc := -40.0`（安全下限哨兵）、`uErrorId := 0`、`fVaporPa := 0.0`、`bInRange := TRUE`，任何提前 RETURN 前已保证输出确定。
- **边界防错**：分母 `243.04 + fTempEff` ≤ 1E-6 时不计算直接返回哨兵（数学上 T>-40 已保证，防御性双检）；fRhPct ≤0 钳位 DL_DEW_RH_MIN 置 `16#0002_1501`；fRhPct >100 钳 100 同码；fTempC 越域钳位到 -40..60 置 `16#0002_1502` 且 bInRange:=FALSE；LN 输入恒 >0（RH 下限保证）。
- **故障码表**：`16#0002_1501` 湿度越界已钳位；`16#0002_1502` 温度越域已钳位（含冰面霜点未计算提示）。
- **依赖**：无 DL_ 内部依赖；仅标准 LN/EXP。

## 16 FC_DL_FlowCompensate — 气体流量温压补偿

- **类型/目录/复杂度**：FC（返回值 REAL = 标准状态流量 [Nm³/h]）｜ DL_Algo ｜ 5
- **function_tags**：`flow-compensation`, `standard-volume`, `oscat-basic`, `gas-metering`, `ideal-gas`
- **功能语义**：按理想气体定律把工况体积流量换算为标准状态流量：`Qs = Qa * (Pa/Ps) * (Ts/Ta)`（Zs/Za=1，中低压适用）；绝压=表压+大气压，温度开尔文化。现场用途：涡街/孔板气体计量贸易交接、能耗统计（Nm³/h 为标况体积，非工况体积）。
- **公式**：`fPaAbs := fPressGauge + fAtmPress`；`fTaK := fTempC + 273.15`；`fTsK := rNormTempTs + 273.15`；`FC_DL_FlowCompensate := fFlowActual * fPaAbs / rNormPressPs * fTsK / fTaK`。
- **VAR 清单**：
  - VAR_INPUT：`fFlowActual: REAL`（工况体积流量 [m³/h]）；`fPressGauge: REAL`（管线表压 [kPa]，≥0）；`fAtmPress: REAL := 101.325`（当地大气压 [kPa]）；`fTempC: REAL`（介质温度 [°C]，有效域 -40..300）；`rNormPressPs: REAL := 101.325`（标准状态压力 [kPa]）；`rNormTempTs: REAL := 0.0`（标准状态温度 [°C]，0=NTP 口径，20=STP 口径）。
  - VAR_OUTPUT：`uErrorId: UDINT`；`fPaAbs: REAL`（绝压 [kPa]，诊断）；`bInRange: BOOL`。
  - VAR：常量 `DL_FLOW_T0K: REAL := 273.15`（绝对零度换算 [K]）、`DL_FLOW_T_MIN/MAX: REAL := -40.0/300.0`、`DL_FLOW_TA_MIN: REAL := 50.0`（绝压温度防御下限 [K]）、`DL_FLOW_EPS: REAL := 1.0E-6`、`DL_FLOW_PRESS_MIN: REAL := 1.0`（绝压防御下限 [kPa]）。
- **出口默认值**：入口即赋 `FC_DL_FlowCompensate := 0.0`、`uErrorId := 0`、`fPaAbs := 0.0`、`bInRange := TRUE`。
- **边界防错**：`fTaK < DL_FLOW_TA_MIN`（含 T≤-273 非物理输入）时返回 0 置 `16#0002_1602`；绝压 fPaAbs < DL_FLOW_PRESS_MIN 返回 0 置 `16#0002_1601`；fPressGauge 负值钳 0；rNormPressPs ≤0 钳 101.325 置 0002_0001；fTempC 越域置 bInRange:=FALSE 并提示（不阻断，按钳位口径说明）。
- **故障码表**：`16#0002_1601` 绝压低于防御下限（返回 0）；`16#0002_1602` 温度非物理或越域已钳位。
- **依赖**：无 DL_ 内部依赖；仅标准算术。

---

## 17 依赖关系总图（本轮内）

```
FB_DL_PidController ←── FB_DL_CascadePid（内部实例 fbPidMaster/fbPidSlave）
FB_DL_PidController ←── FB_DL_SmithPredictor（内部实例 fbPid）
其余 13 个组件：零 DL_ 内部依赖（仅 Level 0 / Standard.library）
无任何组件依赖 DL_Device / DL_Motion / DL_Process（反向依赖 = 0）✔
```

## 18 行数预算与验收向量机制

| 组件 | 预估行数 | 组件 | 预估行数 |
|---|---|---|---|
| PidController | 330 | RateLimiter | 210 |
| CascadePid | 300 | LowPassFilter | 230 |
| SplitRangeControl | 250 | SecondOrderFilter | 300 |
| FeedforwardComp | 310 | HighPassFilter | 230 |
| SmithPredictor | 340 | Integrator | 230 |
| RampGenerator | 250 | Differentiator | 270 |
| SCurveGenerator | 340 | DewPointCalc (FC) | 210 |
| PwmDutyController | 300 | FlowCompensate (FC) | 230 |

- 全部落在 200~340 行预算内；零占位符；参照 MedianFilter 惯例，每个 FB/FC 头注释尾部附**验收向量**（V1..V6 式可执行断言），对 PidController（阶跃→稳态→抗饱和回填）、SecondOrderFilter（系数守恒 fB0+fB1+fB2−fA1−fA2≈1）、DewPointCalc（20 °C/50% → 9.3 °C）、FlowCompensate（500 m³/h @ 3.5 barg/35 °C → ≈1974 Nm³/h）等关键行为提供机检断言素材。
- 机检禁用记号全文命中 = 0；八条红线逐条自检（红线清单见 coding-standard.md 第九节）。

## 19 编码顺序建议（编码者执行时）

1. 第一批（零依赖，可并行）：RateLimiter → RampGenerator → LowPassFilter → HighPassFilter → Integrator → SplitRangeControl
2. 第二批：PwmDutyController → Differentiator → SecondOrderFilter → FeedforwardComp
3. 第三批（有依赖）：PidController → CascadePid → SmithPredictor
4. 第四批（FC）：DewPointCalc → FlowCompensate
5. 每完成一批做一次禁用记号机检与红线自检，全部完成后统一走终审与文档同步（INDEX_REGISTRY / VERSION / MANUAL / CHANGELOG / ROADMAP 属终审阶段动作，本轮不执行）。
