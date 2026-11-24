# MANUAL — DL_Process 行业工艺与工站模板子库使用手册

> **Sublibrary**：`DL_Process` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：2 ｜ **Components**：30（功能块 30，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
> **Depends**：`Standard.library`（`TON` / `R_TRIG` / `SHR`）；框架件零库内依赖；R6 行业示范件复用 Level 0~1——`FB_DL_EnthalpyCompareCtrl` 引用 `FC_DL_HumidAirEnthalpy`（DL_Algo），`FB_DL_OccScheduleWindow` 引用 `FB_DL_TimeWindowCheck` / `FC_DL_DayOfWeekCalc`（DL_Base）
> **故障码段 / Error Code Family**：`16#0005_xxxx`（信息级 `01xx` ｜ 故障级 `02xx` 起段；信息级不置任何故障位）
> 配套版本记录见 `DL_Process/VERSION.md`；全库导航见 `C:\Library\README.md`。**引脚级细节以 `.st` 源码声明区为准**，本手册接口表逐字取自源码。

---

## 0. 使用前必读 / Before You Start

1. **纯状态机框架**：`FB_DL_PackMlStateMachine` 不编排任何具体工艺动作——动作由调用方按 `eState` 派发（Level 2 依赖注入原则），配方/节拍/OEE 由上层组件承接。
2. **命令单发化**：命令经 `FB_DL_PackMlCmdDecoder` 防抖单发后供给状态机；解码器先于状态机调用即可保证命令当拍到达，不产生额外拍延迟。
3. **安全侧「不猜」**：解码器同拍多命令 → 冲突位 + 全部丢弃；状态机非法态 → 强制走 Aborting 路径。执行层拒绝是状态机的职责，解码器不做跃迁判断。
4. **acting 态自动推进**：`eClearing` / `eStarting` / `eStopping` 等 acting 态由 `bStateComplete` 输入自动推进到下一态；wait 态（如 `eExecute`）只响应命令。
5. **模式切换窗口**：`eMode` 变更仅允许在 `eStopped` / `eIdle` / `eCompleted` 稳态受理，其余态被拒并置信息级 `0005_0101`。

---

## 1. 组件索引 / Component Index

| 组件 / Component | 类型 / Kind | 用途 / Purpose | 依赖 / Depends On |
|---|---|---|---|
| `FB_DL_PackMlStateMachine` | 功能块 | PackML 十七态状态机框架 / PackML state machine framework | `E_DL_PackMlState` / `E_DL_PackMlCmd` / `E_DL_UnitMode`（随文件发布） |
| `FB_DL_PackMlCmdDecoder` | 功能块 | PackML 命令解码器 / Command decoder | `E_DL_PackMlCmd`（随 #1 发布，全局可见） |
| `FB_DL_EnthalpyCompareCtrl` | 功能块 | 焓差经济器执行块（R6）/ Differential-enthalpy economizer | `FC_DL_HumidAirEnthalpy`（DL_Algo） |
| `FB_DL_OccScheduleWindow` | 功能块 | 多窗作息排程（R6）/ Occupancy schedule | `FB_DL_TimeWindowCheck`、`FC_DL_DayOfWeekCalc`（DL_Base） |
| `FB_DL_OeeCalculator` | 功能块 | OEE 班次统计引擎（R7）/ OEE shift statistics | 无（根因位引脚注入，禁读 CPU 钟） |
| `FB_DL_ConveyorZone` | 功能块 | 输送线积放单区 ZPA（R7）/ ZPA conveyor zone | `I_DL_VfdDrive`（接口引用注入） |
| `FB_DL_BatchDosingControl` | 功能块 | 配料称重控制器（R7）/ Batch dosing weighing | 无（秤重量引脚注入，标定在称重层） |

---

## 2. FB_DL_PackMlStateMachine ｜ PackML 状态机框架

**功能**：PackML / ISA-TR88.00.02 十七态（+ Undefined 占位）状态机 clean-room 框架实现。命令驱动 + acting 态由 `bStateComplete` 自动推进；Aborting 为最高优先级出口（`bProcessAbort` 或非法态均入 `eAborting`）；Clearing 完成后必经 `eStopped`（abort 后强制去污步）；`eExecute` 中 `bInterlockOk` 失失自动转 `eHolding`（机内保持），与 `eSuspended`（机外挂起）区分指示，保 OEE 根因数据质量。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 2.1 随文件枚举 / Shipped Enums

**`E_DL_PackMlState`**（18 项，编号严格对齐 OMAC PackML 公开规范，acting/wait 分类）：

| 枚举项 | 值 | 类别 / Class | 说明 / Description |
|---|---|---|---|
| `eUndefined` | 0 | 占位 | 上电占位态，首扫迁移至 `eStopped` / Power-up placeholder |
| `eClearing` | 1 | acting | 清除中（自动推进）：abort 后强制去污步 / Mandatory cleanup after abort |
| `eStopped` | 2 | wait | 已停止：复位/启动/急停出口 / Stopped |
| `eStarting` | 3 | acting | 启动中（自动推进）：预热/自检等启动子工序 / Starting |
| `eIdle` | 4 | wait | 空闲：就绪待命，Start 进入生产 / Idle |
| `eSuspended` | 5 | wait | 已挂起：机外原因暂停（线体/供料）/ Suspended by external reason |
| `eExecute` | 6 | wait | 执行中（生产主态）：工艺动作派发与 OEE 计时态 / Main production state |
| `eStopping` | 7 | acting | 停止中（自动推进）：受控停机子工序 / Controlled stop |
| `eAborting` | 8 | acting | 急停中（自动跃迁）：最高优先级出口 / Highest-priority exit |
| `eAborted` | 9 | wait | 已急停：仅 Clear/Reset 可退 / Aborted |
| `eHolding` | 10 | acting | 保持中（自动推进）：机内原因保持过渡 / Machine-internal hold |
| `eHeld` | 11 | wait | 已保持：机内原因暂停，Unhold 恢复 / Held by machine |
| `eUnholding` | 12 | acting | 恢复中（自动推进）：从保持回到执行 / Resuming from held |
| `eSuspending` | 13 | acting | 挂起中（自动推进）：机外暂停过渡 / External suspend |
| `eUnsuspending` | 14 | acting | 解挂中（自动推进）：从挂起回到执行 / Resuming from suspended |
| `eResetting` | 15 | acting | 复位中（自动推进）：回 Idle 的复位子工序 / Resetting to idle |
| `eCompleting` | 16 | acting | 完成中（自动推进）：完工收尾子工序 / Completion |
| `eCompleted` | 17 | wait | 已完成：批次完成，Reset/Clear 退出 / Batch done |

**`E_DL_PackMlCmd`**（11 项）：`eUndefined=0 / eReset=1 / eStart=2 / eStop=3 / eHold=4 / eUnhold=5 / eSuspend=6 / eUnsuspend=7 / eAbort=8 / eClear=9 / eComplete=10 / eStateComplete=11`（子工序完成命令形态的 SC）。

**`E_DL_UnitMode`**（16 项）：`eInvalid=0 / eProduction=1 / eMaintenance=2 / eManual=3 / eUser4=4 … eUser15=15`。

### 2.2 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `eMode` | `E_DL_UnitMode` | IN | `eInvalid` | 单元模式，仅稳态（eStopped/eIdle/eCompleted）可切换 / Unit mode, switched in stable states only |
| `eCmd` | `E_DL_PackMlCmd` | IN | `eUndefined` | 标准命令，由 `FB_DL_PackMlCmdDecoder` 单发供给 / Standard command, one-shot from decoder |
| `bStateComplete` | `BOOL` | IN | `FALSE` | 子工序完成信号，acting 态推进用 / State complete, advances acting states |
| `bInterlockOk` | `BOOL` | IN | `TRUE` | 工艺联锁，Execute 态保持条件，失失转机内保持 / Process interlock, loss → Holding |
| `bProcessAbort` | `BOOL` | IN | `FALSE` | 工艺级急停触发（安全门/急停链），电平生效 / Process abort trigger, level effective |
| `bTrack` | `BOOL` | IN | `FALSE` | 跟踪脉冲，首扫/跟踪同步（公约 0.1），运行中插入不扰动已建立状态 / Track pulse |
| `eState` | `E_DL_PackMlState` | OUT | `eUndefined` | 当前状态 / Current state |
| `ePrevState` | `E_DL_PackMlState` | OUT | `eUndefined` | 前一状态，仅在真实跃迁时刷新，Abort 路径复盘用 / Previous state for post-mortem |
| `bInExecute` | `BOOL` | OUT | `FALSE` | Execute 态指示，OEE 计时用 / In-execute indicator for OEE |
| `bHeldByMachine` | `BOOL` | OUT | `FALSE` | 机内保持指示，OEE 根因：机内原因 / Held by machine, OEE root cause |
| `bSuspendedByLine` | `BOOL` | OUT | `FALSE` | 机外挂起指示，OEE 根因：机外原因 / Suspended by line, OEE root cause |
| `uErrorId` | `UDINT` | OUT | `0` | 末次事件码，信息级码不构成故障 / Last event code |

### 2.3 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0005_0201` | 故障级 / Fault | 非法状态兜底（强制走 `eAborting` 路径）/ Illegal state, forced into Aborting | Clear→Reset 全恢复链 |
| `16#0005_0101` | 信息级 / Info | 非稳态模式切换被拒 / Mode switch rejected outside stable states | 回到 eStopped/eIdle/eCompleted 再切换 |

### 2.4 核心跃迁链 / Key Transition Chains

- **正常生产链**：`eIdle` → Start → `eStarting` →(SC)→ `eExecute` → Complete → `eCompleting` →(SC)→ `eCompleted` → Reset → `eResetting` →(SC)→ `eIdle`
- **急停恢复链**：任意态 `bProcessAbort` → `eAborting` → `eAborted` → Clear → `eClearing` →(SC)→ `eStopped` → Reset → `eIdle`
- **机内保持链**：`eExecute` 中 `bInterlockOk=FALSE` → `eHolding` → `eHeld` → Unhold → `eUnholding` →(SC)→ `eExecute`

### 2.5 调用示例 / Call Example

```iecst
VAR
    fbPml : FB_DL_PackMlStateMachine;    // 状态机 / State machine
    fbDec : FB_DL_PackMlCmdDecoder;      // 命令解码器 / Command decoder
    fbStep : FB_DL_StepSequencer;        // 子工序引擎（DL_Base）/ Sub-step engine
END_VAR

fbPml.eMode := E_DL_UnitMode.eProduction;   // 稳态期切换 / Switch in stable state
fbDec(bCmdStart := bHmiStart, bCmdStop := bHmiStop,
      bCmdAbort := bEstopChain, uCmdWord := wMesCmdWord,
      tMinPulse := T#100MS);                // 先调用解码器 / Decode first
fbPml.eCmd := fbDec.eCmd;                   // 命令单发供给 / One-shot command

fbPml(bStateComplete := fbStep.bSeqDone,    // acting 态推进 / Advance acting states
      bInterlockOk := bSafeChain,
      bProcessAbort := bEstopChain);

// 工艺派发：按态执行动作，状态机本身不含工艺 / Dispatch by state
IF fbPml.eState = E_DL_PackMlState.eExecute THEN
    fbStep();                                // 运行子工序 / Run sub-steps
END_IF

// OEE 采集：bInExecute 计时长；bHeldByMachine / bSuspendedByLine 分归因 / OEE capture
```

---

## 3. FB_DL_PackMlCmdDecoder ｜ PackML 命令解码器

**功能**：PackML 标准命令解码器：十个离散命令源（HMI/MES/联锁均可接）与可选命令字入口（bit0..bit9 一一对应）双通道收口，统一仲裁、防抖与单发化后输出 `eCmd`（持续一拍）供 `FB_DL_PackMlStateMachine` 消费。离散源任一为 TRUE 时命令字被忽略（现场按钮永远压过 MES 报文）；同拍多命令 → 冲突位 + 全部丢弃（安全侧「不猜」）；单发化经 `TON(tMinPulse)` 展宽 + `R_TRIG` 取沿——命令电平须持续 `tMinPulse` 才发单拍脉冲，同一次按下只发一拍。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 3.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `bCmdReset` | `BOOL` | IN | `FALSE` | 复位命令源，电平生效 / Reset command source |
| `bCmdStart` | `BOOL` | IN | `FALSE` | 启动命令源，电平生效 / Start command source |
| `bCmdStop` | `BOOL` | IN | `FALSE` | 停止命令源，电平生效 / Stop command source |
| `bCmdHold` | `BOOL` | IN | `FALSE` | 保持命令源，电平生效 / Hold command source |
| `bCmdUnhold` | `BOOL` | IN | `FALSE` | 解除保持命令源，电平生效 / Unhold command source |
| `bCmdSuspend` | `BOOL` | IN | `FALSE` | 挂起命令源，电平生效 / Suspend command source |
| `bCmdUnsuspend` | `BOOL` | IN | `FALSE` | 解除挂起命令源，电平生效 / Unsuspend command source |
| `bCmdAbort` | `BOOL` | IN | `FALSE` | 急停命令源，电平生效 / Abort command source |
| `bCmdClear` | `BOOL` | IN | `FALSE` | 清除命令源，电平生效 / Clear command source |
| `bCmdComplete` | `BOOL` | IN | `FALSE` | 完工命令源，电平生效 / Complete command source |
| `uCmdWord` | `WORD` | IN | `16#0000` | 可选命令字入口，bit0..bit9 对应十命令；离散源任一为 TRUE 时被忽略 / Optional command word, ignored when any discrete source TRUE |
| `tMinPulse` | `TIME` | IN | `T#100MS` | 最小命令脉宽，防抖动误触发 / Min command pulse for debounce |
| `eCmd` | `E_DL_PackMlCmd` | OUT | `eUndefined` | 单发化命令输出，持续一拍 / One-shot command, one scan |
| `bCmdConflict` | `BOOL` | OUT | `FALSE` | 命令冲突指示，同拍多命令（瞬态位，锁存由调用方自理）/ Command conflict, transient |
| `uLastCmd` | `E_DL_PackMlCmd` | OUT | `eUndefined` | 末次有效命令，冲突拍不更新 / Last accepted command |
| `uErrorId` | `UDINT` | OUT | `0` | 末次信息级事件码（规格外补充引脚，R11 留档）/ Last info code |

> **命令字位域 / Command word bitfield**：bit0=Reset bit1=Start bit2=Stop bit3=Hold bit4=Unhold bit5=Suspend bit6=Unsuspend bit7=Abort bit8=Clear bit9=Complete；bit10..15 保留（掩码 `16#03FF` 截取，置位不影响解码）。

### 3.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0005_0102` | 信息级 / Info | 同拍多命令冲突，全部丢弃（安全侧「不猜」）/ Multi-command conflict, all dropped | 检查 HMI/MES 并发命令源 |

### 3.3 调用示例 / Call Example

```iecst
VAR
    fbDec : FB_DL_PackMlCmdDecoder;      // 解码器 / Decoder
END_VAR

// 每周期调用：离散源 + MES 命令字双通道 / Discrete sources + MES word
fbDec(bCmdStart  := bHmiStart,           // HMI 按钮 / HMI buttons
      bCmdStop   := bHmiStop,
      bCmdAbort  := bGuardOpen,
      uCmdWord   := wMesCmd,              // MES 下发命令字 / MES command word
      tMinPulse  := T#100MS);

IF fbDec.bCmdConflict THEN
    bConflictLatch := TRUE;              // 冲突位为瞬态，需要提示请自行锁存 / Latch if needed
END_IF
wLastAccepted := WORD(fbDec.uLastCmd);   // 屏上回显末次受理命令 / Show last accepted
```

---

## 4. FB_DL_EnthalpyCompareCtrl ｜ 焓差经济器执行块（R6，v1.0.1）

**功能 / 中文**：焓差比较控制执行块，行业池 9.5 节 P0 链路闭环示范。新风/回风温湿度 → 每拍内部直接调用 `FC_DL_HumidAirEnthalpy` 计算双侧焓值 → 差分焓值判据（施密特迟滞，开侧「新风焓 < 回风焓 − 死区」、关侧「新风焓 > 回风焓 + 死区」）→ 新风阀位指令输出；最小新风位硬下限（卫生通风底线）、ASHRAE 90.1 焓值高限停机（可选）、输入失效安全侧冻结。连续量组件，设首扫标志（R19）。
**Function**: Differential-enthalpy economizer block consuming `FC_DL_HumidAirEnthalpy` twice per scan, with Schmitt hysteresis, minimum-position hard floor, ASHRAE 90.1 high-limit trip and safe-side freeze on input failure.

### 4.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `fOaTempC` | `REAL` | IN | — | 摄氏度 | 新风干球温度，有效域 -30..60，越域按输入失效处理 / Outdoor air dry-bulb temp |
| `fOaRelHum` | `REAL` | IN | — | 百分数 | 新风相对湿度，有效域 1..100，越域按输入失效处理 / Outdoor air relative humidity |
| `fRaTempC` | `REAL` | IN | — | 摄氏度 | 回风干球温度，有效域 0..100（与焓值 FC 计算域一致）/ Return air dry-bulb temp |
| `fRaRelHum` | `REAL` | IN | — | 百分数 | 回风相对湿度，有效域 1..100 / Return air relative humidity |
| `fAtmPress` | `REAL` | IN | `101.325` | kPa | 大气压，透传焓值 FC，非有限值按输入失效处理 / Atmospheric pressure |
| `fEnthalpyDeadband` | `REAL` | IN | `2.0` | kJ/kg | 焓差切换死区（施密特迟滞半宽），负值防御钳位为 0 / Changeover deadband |
| `fMinOaPos` | `REAL` | IN | `30.0` | 百分数 | 最小新风阀位（卫生通风硬下限），域 0..100 / Minimum damper position |
| `fFreeCoolOaPos` | `REAL` | IN | `100.0` | 百分数 | 经济器全开阀位，域 0..100 / Free-cooling damper position |
| `fEnthalpyHighLimit` | `REAL` | IN | `0.0` | kJ/kg | 新风焓值高限停机门限，默认 0=禁用（ASHRAE 90.1 高限语义）/ Enthalpy high-limit trip |
| `bEnableCooling` | `BOOL` | IN | `FALSE` | 1 | 供冷需求使能，FALSE 时阀位恒回最小新风位 / Cooling demand enable |
| `bReset` | `BOOL` | IN | `FALSE` | 1 | 复位，上升沿：输入失效锁存码仅在输入已恢复且本沿到达时清除 / Reset |
| `bTrack` | `BOOL` | IN | `FALSE` | 1 | 跟踪重同步，TRUE 时阀位回最小新风位并重建迟滞态（R19 必测）/ Track resync |
| `fOaEnthalpy` | `REAL` | OUT | — | kJ/kg 干空气 | 新风比焓，供 HMI/诊断；输入失效拍冻结末次有效值 / Outdoor air enthalpy |
| `fRaEnthalpy` | `REAL` | OUT | — | kJ/kg 干空气 | 回风比焓，输入失效拍冻结末次有效值 / Return air enthalpy |
| `bEconomizerActive` | `BOOL` | OUT | — | 1 | 经济器激活，差分焓值判据通过且迟滞态为开侧 / Economizer active |
| `fOaDamperCmd` | `REAL` | OUT | — | 百分数 | 新风阀位指令，量纲=阀位域 0..100，硬下限恒 ≥ `fMinOaPos` / Damper command |
| `bHighLimitTrip` | `BOOL` | OUT | — | 1 | 焓值高限停机，激活中 / High-limit trip |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码；0 = 无 / Error code |

### 4.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0103` | 信息级 | 下游算法函数钳位码透传归并（温度/湿度/大气压钳位提示） |
| `0005_0201` | 故障级 | 非法状态兜底（与 PackML 同码同义复用，终审裁定留档） |
| `0005_0202` | 故障级 | 焓值计算输入失效（非有限值/越引脚域，锁存，安全侧冻结） |

> D4 专项裁定：负干球温度经焓值计算链钳位至 0 摄氏度——新风焓偏高估计，误差方向恒为保守安全侧（经济器少开、不引入高焓空气），维持现状 PASS；高精度冷量计量需求另行立项。

### 4.3 调用示例 / Call Example

```iecst
fbEco(fOaTempC := fOaT, fOaRelHum := fOaH,
      fRaTempC := fRaT, fRaRelHum := fRaH,
      fAtmPress := 101.325, fEnthalpyDeadband := 2.5,
      fMinOaPos := 25.0, fFreeCoolOaPos := 100.0,
      bEnableCooling := bCoolDemand);
fbDampValve.fPosSetpoint := fbEco.fOaDamperCmd;   // 直连模拟量阀整形块 / chain to AnalogValve
```

---

## 5. FB_DL_OccScheduleWindow ｜ 多窗作息排程（R6）

**功能 / 中文**：多窗作息排程块，行业池 9.5 节 P0 链路闭环示范。内部 4 实例复用 `FB_DL_TimeWindowCheck` + `FC_DL_DayOfWeekCalc`（日期→星期），每日窗矩阵 + 星期使能 + 节假日覆盖位，输出占用/预启动占位/占用开始沿；支持跨零点窗与预启动回绕、多窗最小号仲裁。事件型 + 日切换沿，免首扫（R23）。
**Function**: Multi-window occupancy schedule composing four `FB_DL_TimeWindowCheck` instances and `FC_DL_DayOfWeekCalc`, with holiday overrides, midnight-crossing pre-start wrap and smallest-active-window arbitration.

### 5.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `uYear` | `UINT` | IN | — | 年 | 日期注入-年，有效域 1980..2099，越界返回非法（透传 `FC_DL_DayOfWeekCalc`）/ Injected date year |
| `uMonth` | `USINT` | IN | — | 月 | 日期注入-月，有效域 1..12 / Injected month |
| `uDay` | `USINT` | IN | — | 日 | 日期注入-日，1..当月天数（含闰年）/ Injected day |
| `uHourNow` | `USINT` | IN | — | h | 当前时刻注入-时，0..23，越界按不在窗处理（禁读控制器时钟）/ Injected hour |
| `uMinNow` | `USINT` | IN | — | min | 当前时刻注入-分，0..59 / Injected minute |
| `aWinEnable` | `ARRAY[1..4] OF BOOL` | IN | — | 1 | 各窗使能，FALSE 时该窗恒不在窗 / Window enables |
| `aHourOn` | `ARRAY[1..4] OF USINT` | IN | — | h | 各窗开启时刻-时，0..23 / Window on hours |
| `aMinOn` | `ARRAY[1..4] OF USINT` | IN | — | min | 各窗开启时刻-分，0..59 / Window on minutes |
| `aHourOff` | `ARRAY[1..4] OF USINT` | IN | — | h | 各窗关闭时刻-时，支持跨零点窗 / Window off hours |
| `aMinOff` | `ARRAY[1..4] OF USINT` | IN | — | min | 各窗关闭时刻-分 / Window off minutes |
| `aWeekdayWin` | `ARRAY[1..4, 1..7] OF BOOL` | IN | — | 1 | 各窗星期使能矩阵，第二维 1=周一..7=周日（ISO 序）/ Per-window weekday matrix |
| `aHolidayOverride` | `ARRAY[1..4] OF BOOL` | IN | — | 1 | 节假日覆盖位，TRUE=当日该窗强制关闭 / Holiday overrides |
| `tPreLeadTime` | `TIME` | IN | `T#30M` | — | 预启动提前量，防御钳位 ≤ T#12H，占用开始前输出预启动占位 / Pre-start lead time |
| `bReset` | `BOOL` | IN | `FALSE` | 1 | 复位，上升沿清除当拍信息级码（不影响窗判定）/ Reset |
| `bOccupied` | `BOOL` | OUT | — | 1 | 占用中，任一有效窗在窗内 / Occupied |
| `bPreStart` | `BOOL` | OUT | — | 1 | 预启动占位，未占用且距某有效窗开始 ≤ 提前量 / Pre-start placeholder |
| `bPulseOnOccupy` | `BOOL` | OUT | — | 1 | 占用开始沿单发，TRUE 持续一拍 / Occupancy start edge |
| `uActiveWin` | `USINT` | OUT | — | — | 当前活动窗号 1..4，0=无，多窗同开取最小号 / Active window index |
| `uErrorId` | `UDINT` | OUT | — | — | 信息级码；0 = 无 / Info code |

### 5.2 信息级码 / Info Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_0210` | 信息级 | 日期参数越界（年/月/日，星期换算返回非法，全窗按不在窗降级） |
| `0005_0211` | 信息级 | 窗时刻参数越界（各窗实例码不透传，本块归并自身码） |

> 本块信息级码占用 `02xx` 段为有意裁定：日历排程块全部事件均为信息级（无安全联锁），故障级段整体保留给后续工艺联锁件，头注释显式声明（终审维持 PASS）。本块无故障锁存位。

### 5.3 调用示例 / Call Example

```iecst
fbSched(uYear := uY, uMonth := uM, uDay := uD,
        uHourNow := uH, uMinNow := uMin,          // 由上位时钟链路注入 / injected
        aWinEnable := abWinEn, aHourOn := auHOn, aMinOn := auMOn,
        aHourOff := auHOff, aMinOff := auMOff,
        aWeekdayWin := abWd, aHolidayOverride := abHol,
        tPreLeadTime := T#30M);
bAHUPrewarm := fbSched.bPreStart;                 // 提前启机预热 / pre-start
bAHURun := fbSched.bOccupied;
```

---

## 6. FB_DL_OeeCalculator ｜ OEE 班次统计引擎（R7，v1.0.1）

**功能**：设备综合效率班次级统计引擎（oee.com / ISO 22400-2 公开口径）。OEE = 时间开动率 × 性能开动率 × 合格品率；停机时间经 PackML 根因位语义分账（计划 vs 计划外，双真歧义入计划外保守侧）；时间累计为扫描周期累加式，周期基准经 `tCycleTime` 引脚注入（禁读 CPU 钟）；性能率超 100 封顶并置信级（负损失提示）。

### 6.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bMachineRunning` | BOOL | 输入 | — | — | 设备运行中，TRUE=运行时间累加 |
| `bPlannedDown` | BOOL | 输入 | — | — | 计划停机中（换型/休息/保养） |
| `bUnplannedDown` | BOOL | 输入 | — | — | 计划外停机中；与 bPlannedDown 同真 → 信息级（分账歧义） |
| `bHeldByMachine` | BOOL | 输入 | — | — | 设备侧保持根因位（PackML Held 语义） |
| `bSuspendedByLine` | BOOL | 输入 | — | — | 产线侧暂停根因位（PackML Suspended 语义） |
| `bPartFinished` / `bPartRejected` | BOOL | 输入 | — | — | 完工/不合格计数脉冲，R_TRIG 上升沿 +1 |
| `fIdealCycleTime` | REAL | 输入 | 10.0 | s | 理想节拍，域 >0 |
| `tShiftLength` | TIME | 输入 | T#8H | ms | 班次总时长（本轮预留引脚，未参与计算，v1.0.1 标注） |
| `tCycleTime` | TIME | 输入 | T#10MS | ms | 扫描周期基准，由调用方注入（FB_DL_CycleTimeMeasure 语义） |
| `bShiftStart` / `bShiftEnd` / `bReset` | BOOL | 输入 | — | — | 班次开始（清零启动）/ 结束（冻结三因子）/ 复位故障 |
| `fAvailability` / `fPerformance` / `fQuality` / `fOee` | REAL | 输出 | — | % | 三因子与 OEE（0~100，Performance 封顶 100） |
| `nTotalCount` / `nGoodCount` / `nRejectCount` | UDINT | 输出 | — | 件 | 总数/合格数/不合格数 |
| `tPlannedTime` / `tRunTime` / `tDownTime` | TIME | 输出 | — | ms | 计划生产/运行/停机时间累计 |
| `nUnplannedByHold` / `nUnplannedBySuspend` | UDINT | 输出 | — | 次 | 计划外停机中机内保持/产线挂起次数 |
| `bFault` / `uErrorId` | BOOL / UDINT | 输出 | — | — | 故障标志 / 故障码 `16#0005_xxxx` 段 |

### 6.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0005_0110` / `0111` / `0112` | 信息级 | 双停机根因同真 / 性能率超 100 封顶 / 零计划时间 |
| `16#0005_0200` | 故障级 | 理想节拍非法（非有限值/非正值，锁存） |

### 6.3 调用示例 / Example

```iecst
fbOee(bMachineRunning := stPackML.bInExecute AND NOT bDown,
      bPlannedDown := bChangeover, bUnplannedDown := bFaultDown,
      bHeldByMachine := stPackML.bHeldByMachine,
      bSuspendedByLine := stPackML.bSuspendedByLine,
      bPartFinished := fbPartDone.Q, bPartRejected := bNgPulse,
      fIdealCycleTime := 1.2, tCycleTime := fbCycMeas.fAvgTime,
      bShiftStart := bShiftOn, bShiftEnd := bShiftOff);
// HMI 直读 fAvailability/fPerformance/fQuality/fOee
```

---

## 7. FB_DL_ConveyorZone ｜ 输送线积放单区（R7，v1.0.1）

**功能**：单段皮带/滚筒输送线积放控制器（Zero-Pressure Accumulation）。积放单句规则「有料且下游允许才走」；卡料窗判定；run-on 清区；级联放行信号 `bZoneReady`；浪涌防护（使能沿后延迟发运行指令）；驱动控制经 `I_DL_VfdDrive` 接口引用注入（每拍至多一次方法调用）。

### 7.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bPEEntry` | BOOL | 输入 | — | — | 入口光电，TRUE=有料进入本区 |
| `bPEDischarge` | BOOL | 输入 | — | — | 出口光电，TRUE=料仍在出口未清 |
| `bDownstreamReady` | BOOL | 输入 | — | — | 下游允许放行；末区接工序就绪，中区接下区 bZoneReady |
| `bZoneEnable` | BOOL | 输入 | — | — | 本区使能，FALSE=驱动停止且请求清零 |
| `bUpstreamOcc` | BOOL | 输入 | — | — | 上区有料（可选过渡联动），本区为空也补跑合拢 |
| `tRunOn` | TIME | 输入 | T#1S | ms | 清区延续时间，出口光电清空后再运行此窗 |
| `tJamWindow` | TIME | 输入 | T#8S | ms | 卡料判定窗，按区长度/带速整定 |
| `tStartDelay` | TIME | 输入 | T#500MS | ms | 启动确认延迟，兼作使能沿浪涌延迟 |
| `bCmdRelease` | BOOL | 输入 | — | — | 手动放行（调试用），上升沿短时放行（仅绕过下游条件） |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位卡料与故障 |
| `bZoneReady` | BOOL | 输出 | — | — | 本区就绪，可接收上游来料 |
| `bOccupied` / `bJam` / `bFault` | BOOL | 输出 | — | — | 本区有料 / 卡料锁存（仅 bReset 清）/ 故障 |
| `uErrorId` | UDINT | 输出 | — | — | 故障码 `16#0005_xxxx` 段 |
| `iDrive` | I_DL_VfdDrive | IN_OUT | — | — | 本区驱动接口引用，上层注入实例 |

### 7.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0005_0113` | 信息级 | 卡料预警（计时中未到窗） |
| `16#0005_0212` | 故障级 | 驱动指令-反馈失配（超 tStartDelay） |
| `16#0005_0213` | 故障级 | 下游驱动故障透传 |
| `16#0005_0214` | 故障级 | 非法状态兜底 |

### 7.3 调用示例 / Example

```iecst
fbZone1(bPEEntry := bPE1, bPEDischarge := bPE2,
        bDownstreamReady := fbZone2.bZoneReady,   // 中区级联
        bZoneEnable := bAutoMode, tJamWindow := T#8S,
        iDrive := iVfd1);
bVfd1Run := fbZone1.bZoneReady AND bAutoMode;      // 驱动使能侧
```

### 7.4 要点 / Notes

- 末区特殊语义由接线决定（`bDownstreamReady` 接下游工序就绪），本块不内判末区。
- v1.0.1 修复：手动放行曾以覆盖式赋值绕过使能/卡料/故障/浪涌门控（禁用区被发运行指令），现仅绕过下游条件；run-on 清区延续窗（清空沿 + tRunOn）按契约 V1 补齐。

---

## 8. FB_DL_BatchDosingControl ｜ 配料称重控制器（R7，v1.0.1）

**功能**：多原料单通道自动配料称重控制器（ISA-88 批次相 Phase 语义）。三段给料顺控（快加→慢加→落定结算）+ 空中落差自学习（误差/2 更新防振荡，钳位 ±fCompLimit 触限置信级）+ 超差 NG 判定（锁存 + 卸料禁止）+ 断流诊断；执行机构抽象为三离散输出（与给料机/闸门类型解耦）；Abort 电平最高优先（CASE 首分支，立即关全部输出）。

### 8.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bCmdBatchStart` | BOOL | 输入 | — | — | 批次启动指令，上升沿进入快加 |
| `bCmdAbort` | BOOL | 输入 | — | — | 批次中止，电平生效，立即关全部输出 |
| `fWeight` | REAL | 输入 | — | kg | 秤实时重量，非有限值防御；标定由称重层完成 |
| `fTareOffset` | REAL | 输入 | 0.0 | kg | 皮重偏移，净重 = fWeight − fTareOffset（v1.0.1 补非数防御） |
| `fSetpoint` | REAL | 输入 | — | kg | 批次目标净重，域 >0 |
| `fSwitchCoarse` | REAL | 输入 | 0.0 | kg | 快加切换点，0=默认 85% 设定值 |
| `fInflightComp` | REAL | 输入 | — | kg | 空中落差补偿，学习值跨批次保持（v1.0.1 补非数防御） |
| `fCompLimit` | REAL | 输入 | 0.0 | kg | 补偿学习限幅，0=默认 10% 设定值 |
| `bLearnEnable` | BOOL | 输入 | — | — | 落差自学习使能，每批结算后按误差/2 更新 |
| `tSettleWindow` | TIME | 输入 | T#1S | ms | 落定稳窗，域 500MS~5S 钳位 |
| `fTolerance` | REAL | 输入 | 0.0 | kg | 批次公差，0=默认 0.5% 设定值 |
| `tFlowWatch` | TIME | 输入 | T#10S | ms | 断流监视窗 |
| `fFlowDeadband` | REAL | 输入 | 0.05 | kg | 断流判据死区 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障 |
| `bOutCoarse` / `bOutFine` / `bOutDischarge` | BOOL | 输出 | — | — | 快加/慢加/卸料输出 |
| `fNetWeight` / `fFinalWeight` | REAL | 输出 | — | kg | 当前净重 / 上批次结算净重（锁存） |
| `bBatchOk` | BOOL | 输出 | — | — | 批次合格判定 |
| `bFault` / `uErrorId` | BOOL / UDINT | 输出 | — | — | 故障标志 / 故障码 `16#0005_xxxx` 段 |

### 8.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0005_0114` / `0115` | 信息级 | 稳窗超时按当前值结算 / 补偿学习触限 |
| `16#0005_0220` | 故障级 | 断流/堵料（监视窗内重量零进给，锁存） |
| `16#0005_0221` | 故障级 | 秤信号无效（非有限值，批次中止全断） |
| `16#0005_0222` | 故障级 | 非法状态兜底 |
| `16#0005_0223` | 故障级 | 配方参数非法（fSetpoint 域外） |

### 8.3 要点 / Notes

- 截断点公式：慢加关断重量 = fSetpoint − fInflightComp；补偿初值 0 → 首批必然过冲 → 学习链逐批收敛（Δ 减半）。
- **v1.0.1 致命修复**：稳窗/断流监视的单拍重启标志永不自清 → 稳窗 TON 永久失效（eSettling 永久挂起、判稳死锁）+ 断流诊断一次后失效；已按 R25「实例调用后自清」修复。

---

## 9. 典型组态与联调要点 / Field Notes

1. **调用顺序**：解码器先于状态机调用，`eCmd` 当拍直达；顺序颠倒会引入一拍延迟（多数场景无害，高节拍机台建议保持先解码）。
2. **MES 联调先查离散源**：命令字「不生效」九成是某按钮卡住或联锁位常 TRUE——离散源优先是设计语义不是缺陷。
3. **冲突位瞬态**：`bCmdConflict` 只在与多命令同拍的扫描周期为 TRUE，HMI 弹窗需自行锁存；本块刻意不锁存以免故障码污染。
4. **脉宽与任务周期匹配**：`tMinPulse` 小于任务周期时命令可能跨拍不足被吞；默认 `T#100MS` 在 10ms 任务下有 10 拍裕量。
5. **Abort 后复盘**：`ePrevState` 保留跃迁前状态，HMI 复盘「急停前在干什么」直接读它；正常跃迁也会刷新，勿当历史记录用。
6. **OEE 根因勿混用**：`bHeldByMachine`（机内：联锁失失、Hold 命令）与 `bSuspendedByLine`（机外：线体/供料 Suspend）是两个独立指示，OEE 根因统计混用会让停机归因失真。

---

## 10. FB_DL_ConveyorLineLink ｜ 线体级联握手协调器（R8，v1.0.1）

**功能 / Function**：相邻机台/线体段之间的 SMEMA 式级联握手——「上游有料 BA」「下游可收 MR」「强制抑制 INH」三类干接点抽象为与供应商无关的状态机：三路消抖、一行布尔式握手判据（同拍冲突保守侧不放行）、传递看门狗（小于消抖窗两倍自动提升）、维护直通（须审计）、质量 NG 透传。只做握手编排，不驱动执行机构。
/ SMEMA-style inter-machine handshake coordinator: debounced BA/MR/INH dry-contact semantics, one-line handshake verdict with conservative conflict handling, transfer watchdog, audited maintenance bypass and NG pass-through.

**接口表 / Interface**（逐字取自声明区 / verbatim from the declaration area）：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 本链使能，FALSE=全部输出置安全侧（不放行、不请求） |
| `bUpBoardAvailable` | BOOL | IN | 上游有料（BA 干接点，电平） |
| `bDownMachineReady` | BOOL | IN | 下游可接收（MR 干接点，电平） |
| `bDownInhibit` | BOOL | IN | 下游强制抑制（INH 干接点，TRUE=禁止放行） |
| `bBoardAtEntry` / `bBoardAtExit` | BOOL | IN | 本段入口 / 出口光电 |
| `bBoardQualityNg` | BOOL | IN | 来料质量 NG 标志（可选，仅透传供下游分选） |
| `bUpstreamRequest` | BOOL | IN | 上游请求放料（可选，与 BA 二选一接线） |
| `tDebounce` | TIME | IN | 输入消抖时间，T#0MS=零消抖直通；经验值 20~30 ms |
| `tTransferTimeout` | TIME | IN | 传递看门狗，小于消抖窗两倍自动提升（0005_0133） |
| `bBypass` | BOOL | IN | 维护直通，TRUE=恒放行且不报卡料，须审计 |
| `bReset` | BOOL | IN | 复位超时锁存（上升沿） |
| `bBoardAvailableOut` | BOOL | OUT | 向下游宣告有料（BA out） |
| `bMachineReadyOut` | BOOL | OUT | 向上游宣告可收（MR out） |
| `bRequestBoard` | BOOL | OUT | 向上游请求送料（Request out） |
| `bInhibitUpstream` | BOOL | OUT | 抑制上游（INH out，卡料锁存期为 TRUE） |
| `bTransferring` / `bTransferDone` | BOOL | OUT | 传递中 / 传递完成单拍脉冲（R25 三律） |
| `bTransferTimeout` | BOOL | OUT | 传递超时（卡料锁存保持期为 TRUE） |
| `bQualityNgOut` | BOOL | OUT | 质量 NG 透传（受理后保持至传递完成） |
| `bFault` / `uErrorId` / `nTransferCount` | BOOL / UDINT / UDINT | OUT | 故障标志（排除信息级）/ 故障码 / 累计传递次数 |
| `E_DL_LineLinkState` | 枚举 | DUT | 链状态机（随文件发布） |

**故障码 / Codes**：信息级 0005_0130~0133；故障级 0005_0230（传递超时卡料，锁存）、0231。

**与 ConveyorZone 衔接 / Zoning hook**：本块 `bMachineReadyOut` → 下游区块 `bDownstreamReady`；下游区块 `bZoneReady` → 本块 `bDownMachineReady`（头注释声明，不引实例）。

**调用示例 / Example**：

```iecst
fbLink(bEnable := TRUE, bReset := bResetCmd,
       bUpBoardAvailable := iUpBA, bDownMachineReady := iDownMR,
       bDownInhibit := iDownINH,
       bBoardAtEntry := iEyeEntry, bBoardAtExit := iEyeExit,
       tDebounce := T#30MS, tTransferTimeout := T#5S);
iToDownstream := fbLink.bBoardAvailableOut;     // 向下游干接点输出
```

**现场要点 / Field notes**：纯事件型免首扫（R23）；维护直通会绕过卡料保护，仅供维护调试且 HMI 须审计 0131；看门狗被自动提升时查 0133——说明消抖窗整定过大。

---

## 11. FB_DL_RecipeManager ｜ 通用配方管理器（R8，v1.0.1）

**功能 / Function**：以「参数清单 + 值集 + 32 位滚动异或校验和」承载多品种配方：选择 → 校验链六层（域→启用→个数→非有限值→上下限→校验和）→ 应用（单拍全量写入防半套参数生效）→ 复核（回读重算校验和比对）→ 写回（校验和清零，本块不伪造，调用方持久化前重算）；机台稳态切换防呆、Load/Save 同拍冲突双丢弃、变更审计。零文件 I/O——配方库与运行参数均为引脚注入数组。CODESYS Forge 公开示例组织分类 clean-room（许可未显式声明，按最严口径只借结构）。
/ Recipe manager with a six-layer validation chain, one-scan full-apply, post-apply verify, teach-back with checksum cleared for the caller to recompute; zero file I/O.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=中止操作并保持运行参数不变 |
| `bLoad` / `bSave` / `bValidate` | BOOL | IN | 加载到运行参数 / 写回配方 / 仅校验（均上升沿受理） |
| `bMachineStopped` | BOOL | IN | 机台稳态确认，FALSE 时拒绝加载（0005_0141，切换防呆） |
| `bReset` | BOOL | IN | 复位故障（上升沿） |
| `nSelectRecipe` | UINT | IN | 选中配方号 [-]，域 0..31 |
| `nParamCount` | UINT | IN | 本机参数个数，域 1..16，越界钳位（0005_0143） |
| `afParamMin` / `afParamMax` | ARRAY[0..15] OF REAL | IN | 参数下/上限（min ≥ max 视为该参数未启用校验） |
| `tNow` | TIME | IN | 时间戳注入 [ms]（禁读 CPU 钟，审计用） |
| `bLoaded` / `bSaved` / `bValid` | BOOL | OUT | 加载完成 / 写回完成 / 校验通过（保持到下次操作） |
| `bParamOutOfRange` / `nOutOfRangeIndex` | BOOL / UINT | OUT | 存在越界参数（瞬时型每拍重算）/ 首个越界参数索引 |
| `nActiveRecipe` / `uActiveChecksum` | UINT / UDINT | OUT | 当前生效配方号 / 运行参数校验和（每拍重算供比对） |
| `uChangeCount` / `tLastChange` | UDINT / TIME | OUT | 变更次数 / 末次变更时间戳 |
| `bBusy` / `bDone` | BOOL | OUT | 执行中 / 操作完成单拍脉冲（R25 三律） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `astRecipe` | ARRAY[0..31] OF ST_DL_RecipeEntry | IN_OUT | 配方库（维度 32，调用方持有与持久化） |
| `afParamActual` | ARRAY[0..15] OF REAL | IN_OUT | 当前运行参数（Save 被读 / Load 被写） |
| `E_DL_RecipeState` + `ST_DL_RecipeEntry` | DUT | 枚举+结构体 | 随文件发布 |

**故障码 / Codes**：信息级 0005_0140~0143；故障级 0005_0240~0246（配方号/个数/非有限值/越界/校验和不匹配/复核失败/兜底）。

**调用示例 / Example**：

```iecst
fbRecipe.bMachineStopped := fbPackML.bStopped;  // 稳态联锁来自状态机
fbRecipe(bEnable := TRUE, bLoad := bLoadCmd, bReset := bResetCmd,
         nSelectRecipe := 3, nParamCount := 8, tNow := tSysTick);
IF fbRecipe.bDone AND fbRecipe.bLoaded THEN
    // 应用成功；uActiveChecksum 可与 HMI 显示比对
END_IF
```

**现场要点 / Field notes**：持久化由调用方完成——写回后校验和已清零（0005_0140 提示未启用），保存前必须重算并回填；`bParamOutOfRange` 是瞬时型复核位，报警须上层锁存；切换配方务必接 `bMachineStopped`，半套参数生效是现场配方事故的头号来源。

---

## 12. FB_DL_LeakTestStation ｜ 气密泄漏测试工站（R8，v1.0.1）

**功能 / Function**：压降法气密测试五相位：夹具确认 → 充气（最小保持时长 + 超时）→ 稳压 → 隔离测量（温度补偿按开尔文温比，泄漏率 = ΔP × 容积 / 时间，kPa·mL/min 工艺约定口径）→ 安全排气。大漏快判（测量窗内压降超阈提前 NG）；设备异常进故障锁存、工件 NG 只出判定，严格分离。
/ Five-phase pressure-decay leak test with temperature compensation by the kelvin ratio, gross-leak quick judge, and strict separation of equipment faults from part NG verdicts.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 工站使能，FALSE=安全排气并清判定输出 |
| `bStart` / `bAbort` / `bReset` | BOOL | IN | 启动（上升沿）/ 中止（电平最高优先）/ 复位 |
| `bFixtureClosed` | BOOL | IN | 夹具闭合确认（FALSE 禁止充气） |
| `bTempCompEnable` | BOOL | IN | 温度补偿使能（FALSE 按原始压降计算，0005_0152） |
| `fTestPressure` / `fPressureTol` | REAL | IN | 目标测试压力 [kPa] / 稳压结束容差 [kPa]（超容差判设备异常 0252） |
| `fActPressure` / `fActTemp` / `fRefTemp` | REAL | IN | 实际压力 [kPa] / 实际温度 [℃] / 基准温度 [℃] |
| `fChamberVolume` / `fLeakLimit` | REAL | IN | 被测腔容积 [mL] / 泄漏率上限 [mL/min]（≤ 此值 PASS） |
| `fGrossLeakDrop` | REAL | IN | 大漏快判压降 [kPa]，0=禁用快判 |
| `tFill` / `tStabilize` / `tMeasure` | TIME | IN | 最小充气保持 / 稳压时长 / 测量时长（T#0S 判故障） |
| `tFillTimeout` / `tVentTimeout` / `tCycle` | TIME | IN | 充气超时 / 排气超时 / 任务扫描周期（换算基准） |
| `bCmdFillValve` / `bCmdIsolateValve` / `bCmdVentValve` | BOOL | OUT | 充气阀 / 隔离阀（测量期 TRUE）/ 排气阀指令 |
| `ePhase` / `bBusy` / `bDone` | 枚举 / BOOL | OUT | 当前相位 / 执行中 / 周期结束单拍 |
| `bPass` / `bFail` | BOOL | OUT | 判定合格 / 不合格（保持态） |
| `fLeakRate` / `fDeltaP` | REAL | OUT | 泄漏率 [mL/min]（锁存）/ 测量窗压降 [kPa]（锁存） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 设备故障锁存（工件 NG 不置位）/ 故障码 |
| `nPartCount` / `nRejectCount` | UDINT | OUT | 测试件数 / 不合格件数 |
| `E_DL_LeakPhase` | 枚举 | DUT | 五相位状态机（随文件发布） |

**故障码 / Codes**：信息级 0005_0150~0153；故障级 0005_0250~0257。

**调用示例 / Example**：

```iecst
fbLeak.fActPressure := iPressSensor;            // 压力变送器注入
fbLeak(bEnable := TRUE, bStart := bTestCmd, bReset := bResetCmd,
       bFixtureClosed := bClampClosed,
       fTestPressure := 300.0, fLeakLimit := 5.0,
       fChamberVolume := 250.0, tMeasure := T#10S);
IF fbLeak.bDone AND fbLeak.bFail THEN nRejectCount := nRejectCount + 1; END_IF
```

**现场要点 / Field notes**：泄漏率量纲为压降法工艺约定（kPa·mL/min 口径），与流量计体积累纲不同——跨族比对时先统一口径（观察项留档 v1.1）；稳压时长过短「既藏漏又造漏」，按工件热平衡实测整定；测量期间隔离阀必须关闭（气源直漏会伪装成工件泄漏）。

---

## 13. FB_DL_MixRecipeControl ｜ 搅拌配方控制（R8，v1.0.1）

**功能 / Function**：ISA-88 相语义搅拌控制，驱动经 `I_DL_VfdDrive` 接口引用注入：前置确认（投料就绪 + 出料阀关闭）→ 转速建立确认窗（90% 设定）→ 混合计时（正反交替换向带停转间隔防混液）→ 终点判据（目标时间 / 扭矩上升二选一）→ 出料 → 停转。最长混合时间超时判 NG。
/ ISA-88 mixer recipe control consuming I_DL_VfdDrive: precheck, speed-establish window, timed mixing with anti-cross-contamination direction alternation, time/torque-rise end criterion, discharge, spin-down; max-mix-time expiry = NG.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=停转清输出 |
| `bStart` / `bAbort` / `bReset` | BOOL | IN | 启动（上升沿）/ 中止（电平最高优先：停转禁出料）/ 复位 |
| `bMaterialReady` / `bOutletClosed` | BOOL | IN | 投料就绪 / 出料阀关闭确认（前置确认项） |
| `bDischargeDone` | BOOL | IN | 出料完成反馈（出料相退出条件） |
| `fSpeedSetpoint` | REAL | IN | 搅拌转速设定 [rpm]，域 1..3000，越界钳位（0005_0160） |
| `fActSpeed` / `fActTorque` | REAL | IN | 实际转速 [rpm] / 实际扭矩 [% 额定]（适配层注入） |
| `fTorqueLimit` | REAL | IN | 扭矩保护上限 [%]，超限即停 + 故障（0005_0263） |
| `bEndByTorque` / `fTorqueRiseTarget` | BOOL / REAL | IN | 以扭矩上升为终点判据 / 终点扭矩 [%] |
| `tMixTime` / `tMixTimeMax` | TIME | IN | 目标混合时间 / 最长混合时间（写反对调自修复 0161；超时判 NG 0162） |
| `bAlternate` / `tAlternateTime` | BOOL / TIME | IN | 正反交替使能 / 交替周期（被提升至两倍确认窗提示 0164） |
| `tSpeedCheck` / `tDischargeTimeout` / `tCycle` | TIME | IN | 转速确认窗 / 出料超时 / 任务扫描周期 |
| `fSpeedCmd` | REAL | OUT | 转速指令 [rpm]，0=停 |
| `bDirForward` / `bDirReverse` | BOOL | OUT | 正/反转指令（互斥） |
| `ePhase` / `bBusy` / `bDone` | 枚举 / BOOL | OUT | 当前相位 / 执行中 / 完成（OK/NG 进入时各一次）单拍 |
| `bOk` / `bNg` | BOOL | OUT | 混合合格 / 不合格（完成保持态内保持，R27 输出保持语义） |
| `fProgress` / `tElapsed` | REAL / TIME | OUT | 进度 0.0..1.0 / 已混合时长（确认通过后累计） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `iDrive` | I_DL_VfdDrive | IN_OUT | 搅拌驱动接口引用（既有契约注入） |
| `E_DL_MixPhase` | 枚举 | DUT | ISA-88 相状态机（随文件发布） |

**故障码 / Codes**：信息级 0005_0160~0164；故障级 0005_0260~0265。

**终审修复（v1.0.1）/ Final-review fixes**：致命——`_bNg` 输出符号未声明即赋值（编译阻断）；严重——eNg 终态不可达（超时分支死代码，NG 判定永不落地）；严重——bOk/bNg 仅脉冲非保持，判定保持语义失效（R27 首例素材）；中等——孤立分号空语句。

**调用示例 / Example**：

```iecst
fbMix.iDrive := iAgitatorVfd;                   // 变频器实例经接口注入
fbMix(bEnable := TRUE, bStart := bMixCmd, bReset := bResetCmd,
      bMaterialReady := bLoaded, bOutletClosed := bValveClosed,
      fSpeedSetpoint := 450.0, tMixTime := T#8M,
      bEndByTorque := TRUE, fTorqueRiseTarget := 60.0);
IF fbMix.bDone AND fbMix.bNg THEN bRejectBatch := TRUE; END_IF
```

**现场要点 / Field notes**：交替换向的停转间隔防混液，勿把 `tAlternateTime` 压到确认窗两倍以下（块内自动提升并提示 0164）；扭矩终点判据适合粘度渐变工艺（膏体/胶），时间终点适合定粘度配方；出料完成反馈缺失会吃满 `tDischargeTimeout` 才判故障。

---

## 14. FB_DL_CipCleaningSeq ｜ CIP 六相清洗序列（R8，v1.0.1）

**功能 / Function**：CIP 六相序（预冲/碱洗/中冲/酸洗/终冲/消毒，可按相启用）：各相 TACT（温度/电导率/流量）三路联锁——未达标时段计时暂停（脏水不凑时长）、暂停超上限判该相失败；终冲以回液电导率到达终点为退出条件（超时兜底）；各相启用数组启动快照（中途改写不生效）；CIP 完成许可 `bCipComplete` 供上层放行生产。
/ CIP six-phase sequence with per-phase TACT interlocks pausing the timer, final-rinse conductivity end target with timeout fallback, enable-array snapshot at start, and a clean-status permission output.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=停泵停止加药（不主动排空） |
| `bStart` / `bAbort` / `bReset` | BOOL | IN | 启动（上升沿）/ 中止（电平最高：停泵+开排空+隔离）/ 复位 |
| `bCircuitReady` | BOOL | IN | 回路就绪（供/回液阀位确认），FALSE 禁止启泵（强行启动锁存 0273） |
| `abPhaseEnable` | ARRAY[0..5] OF BOOL | IN | 各相启用：0 预冲 / 1 碱 / 2 中冲 / 3 酸 / 4 终冲 / 5 消毒 |
| `atPhaseTime` | ARRAY[0..5] OF TIME | IN | 各相目标计时（仅达标时段累计，终冲豁免） |
| `afPhaseTempMin` / `afPhaseCondMin` / `afPhaseFlowMin` | ARRAY[0..5] OF REAL | IN | 各相温度下限 [℃] / 电导率下限 [mS/cm] / 流量下限 [m³/h]（0=不校验） |
| `fActTemp` / `fActCond` / `fActFlow` | REAL | IN | 实际温度 / 电导率（供液或回液接点由调用方选）/ 流量 |
| `fRinseCondTarget` | REAL | IN | 终冲回液电导率终点 [mS/cm] |
| `tHoldLimit` / `tRinseMax` / `tDrainTime` | TIME | IN | 单相联锁暂停上限（超时判相失败）/ 终冲最长延时兜底 / 中止后排空时长 |
| `tTempSetDelay` / `tCycle` | TIME | IN | 升降温等待窗（相开始先等待不计时）/ 任务扫描周期 |
| `ePhase` / `bBusy` / `bDone` | 枚举 / BOOL | OUT | 当前相位 / 执行中 / 周期完成单拍 |
| `bOk` / `bPhaseHold` / `bPhaseFail` | BOOL | OUT | 全相完成且零偏差 / 相位暂停中 / 当前相失败（锁存至复位） |
| `bCipComplete` | BOOL | OUT | CIP 完成许可（供上层放行生产；中止/复位清除） |
| `bCmdSupplyPump` / `bCmdReturnPump` / `bCmdDosing` / `bCmdHeat` / `bCmdDrain` | BOOL | OUT | 供液泵 / 回液泵 / 加药泵（电导低于下限脉冲请求）/ 加热 / 排空阀指令 |
| `fTempSetpoint` | REAL | OUT | 温度设定 [℃]（当前相下限 + 2.0 ℃ 裕量，工艺经验值） |
| `tPhaseElapsed` / `nDeviationCount` | TIME / UDINT | OUT | 当前相已累计计时（仅达标时段）/ 偏差计数（审计） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `E_DL_CipPhase` | 枚举 | DUT | 六相状态机（随文件发布） |

**故障码 / Codes**：信息级 0005_0170~0173；故障级 0005_0270~0274。

**调用示例 / Example**：

```iecst
fbCip.fActTemp := iTempSensor;  fbCip.fActCond := iCondSensor;
fbCip.fActFlow  := iFlowSensor;
fbCip.abPhaseEnable[1] := TRUE;                 // 碱洗启用（其余按工艺组态）
fbCip.atPhaseTime[1]   := T#20M;
fbCip(bEnable := TRUE, bStart := bCipCmd, bReset := bResetCmd,
      bCircuitReady := bValvesInPosition);
bAllowProduction := fbCip.bCipComplete;         // 清洁许可放行
```

**现场要点 / Field notes**：TACT 未达标时计时冻结是本块核心语义——相时长按「合格时间」累计而非墙钟，勿用外部计时器并联旁路；换相停泵间隔（0173）防酸碱混液；终冲电导终点按工艺水质整定，`tRinseMax` 是防呆兜底不是目标值。

---

## 15. FB_DL_BufferMagazine ｜ 缓冲料仓三策略选层（R8，v1.0.1）

**功能 / Function**：缓冲料仓升降调度：三策略选层（自动按请求类型选首空/首满槽位、手动指定层、NG 料优先隔离位）→ 升降目标层换算 → 到位消抖确认 → 取放动作 → 槽位状态回写（`E_DL_SlotState` 数组由本块维护）；双超时护栏（升降/取放）、全满/全空/NG 计数每拍重算。
/ Buffer magazine lift scheduling with three selection strategies (auto/manual/NG-isolation), debounced in-position confirmation, slot-state bookkeeping and dual timeout guards.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=停止升降输出并清请求 |
| `bReset` | BOOL | IN | 复位故障（上升沿） |
| `bReqFetch` / `bReqStore` / `bReqStoreNg` | BOOL | IN | 取料请求 / 存料请求（上升沿）/ 存 NG 料（与存料同沿生效） |
| `nManualLayer` | UINT | IN | 手动指定层，0=自动选层，1..层数=指定（与请求类型不匹配提示 0183） |
| `nLayerCount` | UINT | IN | 层数，域 1..16，越界钳位（0184） |
| `nLiftAtLayer` / `bLiftInPosition` | UINT / BOOL | IN | 升降当前层位置（限位/编码器注入，0=未知）/ 到位确认 |
| `bHandlingDone` | BOOL | IN | 取放动作完成反馈 |
| `tMoveTimeout` / `tHandlingTimeout` / `tDebounce` | TIME | IN | 升降超时 / 取放超时 / 到位信号消抖 |
| `bMoveUp` / `bMoveDown` | BOOL | OUT | 上升 / 下降指令 |
| `nTargetLayer` | UINT | OUT | 目标层（1 基层号，0=无目标） |
| `eState` / `bBusy` / `bDone` | 枚举 / BOOL | OUT | 主状态 / 调度中 / 存取完成单拍 |
| `bMagFull` / `bMagEmpty` | BOOL | OUT | 料仓全满 / 全空（瞬态型每拍重算） |
| `nFullCount` / `nEmptyCount` / `nNgCount` | UINT | OUT | 满槽 / 空槽 / NG 槽数（每拍重算） |
| `bFault` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `aeSlot` | ARRAY[0..15] OF E_DL_SlotState | IN_OUT | 各层槽位状态（索引 0 = 第 1 层，本块维护） |
| `E_DL_MagState` + `E_DL_SlotState` | DUT | 枚举×2 | 随文件发布 |

**故障码 / Codes**：信息级 0005_0180~0186；故障级 0005_0280（升降超时）、0281（取放超时）、0282（层位置越界）、0283。

**调用示例 / Example**：

```iecst
fbMag.nLiftAtLayer := uLiftLayer;               // 升降层位置编码器注入
fbMag(bEnable := TRUE, bReset := bResetCmd,
      bReqStore := bStoreCmd, bReqStoreNg := bPartNg,
      nLayerCount := 8, bLiftInPosition := bLiftOk,
      bHandlingDone := bRobotDone);
IF fbMag.bMagFull THEN bStopFeeding := TRUE; END_IF
```

**现场要点 / Field notes**：取/存请求同拍冲突双丢弃（0186，不猜原则）；NG 隔离位不可用时回退普通空槽并存入（0182 提示，追踪由上层 MES 承担）；运行中改手动层下周期生效（0185），切换层号在料仓空闲时操作。

---

## 16. FB_DL_ModbusPollMaster ｜ Modbus RTU 轮询主站调度器（R9，传输抽象层）

**定位 / Positioning**：多从站轮询主站调度器：按站表顺序轮询、单事务响应超时重试、成功/异常双计数台账、全跳过节流空转。**只做调度抽象层**——帧构造、CRC 校验、字节收发全部由传输层承载：集成者 EXTENDS 本块并覆盖 `DoTransaction`（异步传输必须覆写它，`_stTxn` 为私有成员外部不可回填——O-04 留档），亦可只覆盖 SendFrame/RecvFrame 两个帧级原语。基类桩返回 FALSE 并锁 0005_0290，杜绝静默假成功。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 调度使能，FALSE 时队列暂停并保持现场（站索引/计数不清零，恢复从原站继续） / Pause and keep context |
| `uStationCount` | UINT | IN | 轮询站数 [站]，1~16 越界钳位，默认 4 / Station count, clamped |
| `tRespTimeout` | TIME | IN | 单事务响应超时 [ms]，默认 T#500MS（必须大于最慢从站最长应答） / Response timeout |
| `uMaxRetry` | UINT | IN | 超时重试上限 [次]，0 = 不重试，默认 3 / Retry limit |
| `tPollInterval` | TIME | IN | 相邻事务最小间隔 [ms]，0 = 不节流，默认 T#100MS（RTU 帧间静默工程近似） / Minimum poll interval |
| `bBusy` | BOOL | OUT | 有事务执行中 / Transaction in progress |
| `uActiveStation` | UINT | OUT | 当前轮询站索引 [0~15] / Active station index |
| `uActiveRetry` | UINT | OUT | 当前站累计重试数 [次]，切站清零 / Active retry count |
| `bDone` | BOOL | OUT | 单站事务完成单拍脉冲（R25） / One-scan done pulse |
| `bError` | BOOL | OUT | 故障保持型（排除信息级码） / Fault latched |
| `uErrorId` | UDINT | OUT | 故障码 / Error code |
| `aPollTable` | ARRAY[0..15] OF ST_DL_PollItem | IN_OUT | 轮询站表，调用方持有（uStatOk/uStatErr 由本块维护，跨班累计由调用方清零） / Caller-owned poll table |

**配套 DUT / DUTs（随文件发布）**：`ST_DL_PollItem`（站表项：从站地址/功能码/起始地址/数量均透传 + 双计数 + bSkip）、`ST_DL_ModbusTxn`（事务上下文，含 256 字节应答缓冲）、`E_DL_PollState`（六态）、`E_DL_MbTxnResult`（ePending/eDone/eTimeout/eFailed）。

**故障码 / Codes**：信息级 0005_0190 站数钳位 / 0191 全跳过节流空转 / 0192 单站重试耗尽记账 / 0193 时间参数兜底；故障级 0005_0290 传输层未实现 / 0291 站表索引越界 / 0292 非法状态兜底。

### 调用示例 / Example

```iecst
VAR
    fbPoll : FB_MyRtuMaster;                // 派生块（覆盖 DoTransaction）/ Derived block
    aTable : ARRAY[0..15] OF ST_DL_PollItem;// 轮询站表 / Poll table
END_VAR

aTable[0].uSlaveAddr := 1;  aTable[0].uFuncCode := 3;
aTable[0].uStartAddr := 0;  aTable[0].uQuantity := 16;
fbPoll(uStationCount := 4, tRespTimeout := T#500MS, uMaxRetry := 3,
       tPollInterval := T#100MS, aPollTable := aTable);
// 读台账：aTable[i].uStatOk / uStatErr 由本块维护，HMI 直接读结构体
```

**现场要点 / Field notes**：调度层零触碰帧内容（不解析功能码、不做 CRC——CRC-16/Modbus 公开算法定义见库内 `FC_DL_Crc16Modbus`，本块仅在注释说明可用）；单站重试耗尽只记账继续轮询（不因一站坏总线全线停摆）；站表全跳时空转且 bBusy FALSE，检修期整线隔离勿误判为故障；同一物理链路禁止挂两个实例（不做总线抢占仲裁）。

---

## 17. FB_DL_AndonCallSystem ｜ 安灯四级呼叫系统（R9）

**定位 / Positioning**：车间安灯（Andon）四级呼叫：缺料 / 品质 / 设备 / 维修四路呼叫源，按固定优先级（维修 > 设备 > 品质 > 缺料）显式 IF 链仲裁（不依赖枚举数值序——后续插新级别不改仲裁）；生命周期「呼叫（未应答）→ 已应答（未解除）→ 解除」；未应答超阈值升级上报；应答时长最近值 + 增量式滚动均值统计（防长班次溢出）；班次清零只清统计台账不动激活呼叫。灯色/闪频由既有 `FB_DL_SignalTower` 承载，二者正交可配套。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bCallMat` | BOOL | IN | 缺料呼叫（优先级 4，最低）/ Material call |
| `bCallQual` | BOOL | IN | 品质呼叫（优先级 3）/ Quality call |
| `bCallDev` | BOOL | IN | 设备呼叫（优先级 2）/ Device call |
| `bCallMaint` | BOOL | IN | 维修呼叫（优先级 1，最高）/ Maintenance call |
| `bAcknowledge` | BOOL | IN | 呼叫应答（上升沿对当前激活呼叫应答）/ Acknowledge, rising edge |
| `bClear` | BOOL | IN | 呼叫解除（上升沿清除激活呼叫）/ Clear call, rising edge |
| `bShiftReset` | BOOL | IN | 班次清零（上升沿清统计台账，不清激活呼叫）/ Shift statistics reset |
| `tEscalate` | TIME | IN | 升级上报阈值 [ms]，0 = 不升级，默认 T#120S / Escalation threshold |
| `eActiveCall` | E_DL_AndonLevel | OUT | 当前激活呼叫级别（eNone/eMaterial/eQuality/eDevice/eMaint，数值即对外仲裁权重）/ Active call level |
| `bCallActive` | BOOL | OUT | 有未应答激活呼叫 / Unacknowledged call pending |
| `bAcked` | BOOL | OUT | 已应答未解除（保持型）/ Acknowledged, held |
| `bEscalate` | BOOL | OUT | 升级上报（保持型直到应答或解除）/ Escalation raised, held |
| `tAckLast` | TIME | OUT | 最近一次应答耗时 [ms] / Last acknowledgement time |
| `tAckAvg` | TIME | OUT | 平均应答耗时 [ms]（滚动均值） / Rolling average |
| `uAckCount` | UDINT | OUT | 累计应答笔数 [笔] / Acknowledgement count |
| `uErrorId` | UDINT | OUT | 故障码 / Error code |

**故障码 / Codes**：信息级 0005_01A0 未应答即解除（不计应答统计）/ 01A1 多源同拍或抢占重锁；故障级 0005_02A0 激活级别非法 / 02A1 非法状态兜底。

### 调用示例 / Example

```iecst
VAR
    fbAndon : FB_DL_AndonCallSystem;        // 安灯实例 / Andon instance
END_VAR

fbAndon(bCallMat := bBtnMaterial, bCallQual := bBtnQuality,
        bCallDev := bBtnDevice, bCallMaint := bBtnMaintenance,
        bAcknowledge := bBtnAck, bClear := bBtnClear,
        bShiftReset := bShiftStartPulse, tEscalate := T#120S);
// 灯柱联动：eActiveCall 映射灯色（维修红常亮/设备红闪/品质黄/缺料蓝），
// bEscalate 映射蜂鸣升级
```

**现场要点 / Field notes**：呼叫位是电平输入，松手不消呼叫（激活呼叫在状态机内锁存，安灯基本语义）；应答后必须显式 bClear 才回空闲（提醒问题未处理完）；升级位不改变状态机（只是「催一下」）；抢占时未应答呼叫不计应答笔数（防均值被「没人来」污染）；应答时长按「呼叫发起到按键应答」计量，不含处理时间。

---

## 18. FB_DL_PickAndPlaceStation ｜ 通用拾放上下料工站模板（R10，v1.0.1 · D-01 致命修复件）

**定位 / Positioning**：标准「**取 → 升 → 移 → 放**」上下料工站模板：注入 X/Y/Z 三轴（`I_DL_MotionAxis`）与真空发生器（`I_DL_VacuumGenerator`），按**九步序**执行单件搬运，含真空建立超时、就位确认、节拍统计与安灯级联出口。用于电芯上料、电池片搬移、包装装箱、半导体载具转运等「三轴 + 吸盘」最小工站。

**状态机规模 / Scope**：本块只做工站内工序的**七态最小子集**（`eIdle` / `eStarting` / `eExecute` / `eHolding` / `eHeld` / `eAborting` / `eFault`）。完整的十七态包装机状态机由 `FB_DL_PackMlStateMachine` 承载，本块**不重复实现**，避免两套全状态机在同一工站内打架。

**九步序 / Nine steps**：① 确认原点就绪 → ② 移到取料位 → ③ 下降取料 → ④ 吸取确认 → ⑤ 抬升到安全位 → ⑥ 横移到放料位 → ⑦ 下降放料 → ⑧ 破真空 → ⑨ 抬升回原点。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 工站使能 [−] / Station enable |
| `bStart` | BOOL | IN | — | 启动单件循环，**上升沿**，已保持态下无效 [−] / Start one cycle on a rising edge |
| `bHold` | BOOL | IN | — | 保持，电平：当前步完成后停在已保持态 [−] / Hold, park after the current step completes |
| `bAbort` | BOOL | IN | — | 中止，电平：任何态转中止收尾 [−] / Abort, any state goes to the abort sequence |
| `bReset` | BOOL | IN | — | 复位故障，上升沿 [−] / Reset the fault |
| `bPartPresent` | BOOL | IN | — | 取料位工件在位（光电）[−] / Part present at the pick position |
| `bPlaceClear` | BOOL | IN | — | 放料位空闲，允许放料 [−] / Place position clear |
| `bVacuumOk` | BOOL | IN | — | 真空建立确认（真空开关）[−] / Vacuum established confirmation |
| `bZHomeOk` | BOOL | IN | — | Z 轴原点或上限位就绪 [−] / Z axis home or upper limit ready |
| `fPickZ` | LREAL | IN | 0.0 | 取料位下降目标 [毫米] / Pick position Z target |
| `fPlaceZ` | LREAL | IN | 0.0 | 放料位下降目标 [毫米] / Place position Z target |
| `fSafeZ` | LREAL | IN | 50.0 | 安全抬升位，用于抬升与中止 [毫米] / Safe lift height |
| `fTravelX` | LREAL | IN | 100.0 | 取到放的横向行程 [毫米] / Horizontal travel |
| `fSpeed` | LREAL | IN | 200.0 | 运动速度，域 ≥ 1 [毫米每秒] / Motion speed |
| `fAccel` | LREAL | IN | 1000.0 | 加减速度，域 ≥ 10 [毫米每二次方秒] / Acceleration |
| `fPosTol` | LREAL | IN | 0.5 | 到位判定容差窗口 [毫米] / In-position tolerance window |
| `tGripTime` | TIME | IN | T#200MS | 吸盘吸附建立时间 [毫秒] / Suction build-up time |
| `tBlowTime` | TIME | IN | T#150MS | 破真空吹气时间 [毫秒] / Blow-off time |
| `tStepTimeout` | TIME | IN | T#5S | 单步超时 [毫秒] / Per-step timeout |
| `tCycleTimeout` | TIME | IN | T#30S | 整循环超时，**同时用作节拍秒表** [毫秒] / Whole-cycle timeout, also the stopwatch |
| `iAxisX` | I_DL_MotionAxis | IN_OUT | — | X 轴接口引用，横向搬运 [−] / X axis reference |
| `iAxisY` | I_DL_MotionAxis | IN_OUT | — | Y 轴接口引用，**可选**，未用时传同一实例 [−] / Y axis reference, optional |
| `iAxisZ` | I_DL_MotionAxis | IN_OUT | — | Z 轴接口引用，升降 [−] / Z axis reference |
| `iVacuum` | I_DL_VacuumGenerator | IN_OUT | — | 真空发生器接口引用 [−] / Vacuum generator reference |
| `eState` | E_DL_SpState | OUT | — | 七态（观测用）[−] / Station state |
| `nStepNo` | INT | OUT | — | 当前步号 1~9，0 为无常驻步 [步] / Current step number |
| `bCycleDone` | BOOL | OUT | — | 单件循环完成，**单拍脉冲** [−] / Cycle finished, one-scan pulse |
| `bCycleOk` | BOOL | OUT | — | 本件合格，**保持到下一件开始** [−] / Part accepted, held |
| `bPartLost` | BOOL | OUT | — | 搬运中真空丢失，保持 [−] / Part lost during transport |
| `bError` | BOOL | OUT | — | 故障锁存 [−] / Fault latch |
| `uErrorId` | UDINT | OUT | — | 事件码（见下表）/ Event code |
| `tCycleTime` | TIME | OUT | — | 上一件节拍 [毫秒] / Cycle time of the last part |
| `tCycleTimeAvg` | TIME | OUT | — | 节拍移动平均，八件窗 [毫秒] / Moving average over an eight-part window |
| `nOkCnt` | UDINT | OUT | — | 合格计数 [件] / Accepted part counter |
| `nNgCnt` | UDINT | OUT | — | 不合格计数 [件] / Rejected part counter |
| `bCallAndon` | BOOL | OUT | — | 需人工介入，供安灯系统消费 [−] / Manual intervention request |

**故障码 / Codes**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0005_01B0` | 信息级 | Z 轴原点未就绪超时（保持本步重试） |
| `0005_01B1` | 信息级 | 真空未建立，本件判 NG |
| `0005_01B2` | 信息级 | 前置条件不满足（缺料或放料位占用），业务态加安灯 |
| `0005_01B3` | 信息级 | 正常中止完成 |
| `0005_01B4` | 信息级 | 节拍统计窗重建 |
| `0005_02B0~02B6` | 故障级 | 依次为 X 取料超时 / Z 下降取料超时 / Z 抬升超时 / X 横移超时 / 搬运中掉件 / 破真空超时 / 回原点超时 |
| `0005_02B7` | 故障级 | 非法状态或非法步号兜底（**兼循环超时兜底**，见 O-2） |

### 调用示例 / Example

```iecst
VAR
    fbPickPlace : FB_DL_PickAndPlaceStation;   // 工站实例 / Station instance
    fbAxisX     : FB_DL_SingleAxis;            // X 轴实现 / X axis implementation
    fbAxisZ     : FB_DL_SingleAxis;            // Z 轴实现 / Z axis implementation
    fbVac       : FB_DL_VacuumEjector;         // 真空发生器实现 / Vacuum generator
    bCycleDone  : BOOL;                        // 完成单拍 / Cycle done pulse
    nNgTotal    : UDINT;                       // NG 累计 / Rejected total
END_VAR

// 每周期无条件调用；三轴与真空实例注入（Y 轴可复用 X 实例占位）
fbPickPlace(bEnable := bStationOn, bStart := bStartCycle, bHold := bHoldCycle,
            bAbort := bAbortCycle, bReset := bResetFault,
            bPartPresent := bPartAtPick, bPlaceClear := bPlaceFree,
            bVacuumOk := fbVac.bVacuumOk, bZHomeOk := fbAxisZ.bHomed,
            fPickZ := -120.0, fPlaceZ := -95.0, fSafeZ := 50.0, fTravelX := 320.0,
            fSpeed := 200.0, fAccel := 1000.0, fPosTol := 0.5,
            tGripTime := T#200MS, tBlowTime := T#150MS,
            tStepTimeout := T#5S, tCycleTimeout := T#30S,
            iAxisX := fbAxisX, iAxisY := fbAxisX, iAxisZ := fbAxisZ,
            iVacuum := fbVac,
            bCycleDone => bCycleDone, nNgCnt => nNgTotal);

// 每周期必须调用被注入的轴与真空实现（否则接口方法不收指令）
fbAxisX(); fbAxisZ(); fbVac();
```

**要点 / Notes**：
- **v1.0.1 致命修复（D-01）——「CASE 漏标签，执行态被兜底判非法」**：枚举定义七值，主 CASE 只列六标签**漏掉 `eExecute`**；动作逻辑写在 CASE 之外以 `IF _eState = eExecute` 处理，编码者据此认为「不需标签」。实际执行流：`CASE` 先跑 → `eExecute` 命中 `ELSE` 兜底 → 判非法并置 `02B0`、转 `eFault` → 随后段 8~11 的 `IF _eState = eExecute` 因状态已被改写而整段跳过。**后果：工站从 `eStarting` 推进到 `eExecute` 的当拍即自杀，九步序一行不执行。** 修法：显式加 `eExecute` 标签分支，**体内只写注释不写动作**，并在注释中固化「为何必须显式列出」防后续维护者再删。**沉淀 R31「枚举→CASE 双向映射完备性」**。
- **v1.0.1 严重修复（D-03）——空引用停机**：原故障停机 `IF bAxisValid THEN iAxisX.Stop(); iAxisY.Stop(); ...`，而 `bAxisValid` 只覆盖 X/Z/真空三路，Y 轴为可选注入（可为 0），两轴模板下故障拍执行 `0.Stop()` → CODESYS/TwinCAT 行为未定义，汇川报访问违例——**恰在最需要安全停机的时刻把 PLC 打死**。修法：四路逐个 `IF iX <> 0 THEN … END_IF`，不再依赖聚合布尔量。
- **v1.0.1 修复（D-06）**：步 1 下发分支原有一句 `uErrorId := 16#0000_0000;`，覆盖同拍段 8 刚置的 `01B0`（超时码置位当拍被抹掉，HMI 永远看不到）。修法：删除该清零语句，**错误码清零只在段 13 单点出口执行**（单点写纪律）。
- **接口适配（总监裁定采纳）**：① `fSafeZ` / `fPosTol` 提为引脚（规格只以文字描述，按「无魔法数」红线提为带默认值的引脚）；② **到位判据 = 轴 `eStandstill` + 位置落在容差窗内**（`I_DL_MotionAxis` 无「到位位」属性，此实现语义等价且更严格：静止但偏差异常仍判未到位）；③ 真空侧映射到既有 `CmdEvacuate` / `CmdBlowOff` 方法。
- **单步三段式**：下发（**只发一次**）→ 等条件 → 单拍推进；动作指令绝不每拍重发（同步耦合族「每拍至多一次接口方法调用」的同一纪律）。
- **保持态不重发运动指令**，释放后从当前步继续、已完成步不重做；中止收尾逐拍推进一步（抬 Z → 破真空）。
- **观察项 O-2**：循环超时复用兜底码 `02B7`（`01B0~01B4` 与 `02B0~02B7` 已满，按 R30 不得跨块取 `02B8`），HMI 无法区分「循环超时」与「非法状态」；下一 MAJOR 为本族扩块（`02C0~02CF`）并拆分。

---

## 19. FB_DL_PressFitStation ｜ 伺服精密压装工站（R11，v1.0.0）

**定位 / Positioning**：伺服精密压装八态工站（`eIdle` 0 / `eApproach` 10 / `ePress` 20 / `eDwell` 30 / `eRetract` 40 / `eEvaluate` 50 / `eFinish` 60 / `eFault` 99）。压入过程逐拍做**位移-压力包络窗口校验**（上下限按位移节点线性插值），提取**接触点 / 屈服点 / 峰值点 / 终点**四特征点，一个循环给出合格结论与 NG 原因位。用于轴承压装、衬套压入、电芯封口、接插件插针压入等。

**采样口径 / Sampling**：接近 / 压入 / 保压三段逐拍采样；包络校验**只在压入与保压段执行**——接近段压力天然低于下限，一并判会误报。斜率按相邻两拍差分，位移增量小于保护阈值时沿用上一拍，杜绝除零。

**屈服判据 / Yield criterion**：取「斜率回落至峰值斜率的指定比例」（`fYieldSlopeRatio`），**不以压力绝对过峰为前提**。现场屈服段多为斜率软化而非压力下降（铝壳 / 塑料件尤甚），强求过峰则单调上升曲线永远判不出；压力过峰另有独立标志 `_bPeakPassed`。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 回待机并复位输出 / Enable; FALSE resets to idle |
| `bStart` | BOOL | IN | — | — | 启动一个压装循环，**上升沿**受理 / Start one cycle on a rising edge |
| `bAbort` | BOOL | IN | — | — | 中止并立即请求回退，上升沿受理 / Abort and retract |
| `bReset` | BOOL | IN | — | — | 复位故障锁存，上升沿受理 / Reset latched fault |
| `fActPos` | REAL | IN | — | 毫米 | 压头实际位移，量程 0.0~1000.0 / Ram position |
| `fActForce` | REAL | IN | — | 千牛 | 压力传感器实测压力，量程 0.0~500.0 / Measured force |
| `fContactForceThr` | REAL | IN | `0.05` | 千牛 | 接触判定压力阈值，0 表示禁用接触点提取 / Contact threshold |
| `fYieldSlopeRatio` | REAL | IN | `0.50` | — | 屈服判据斜率比例，域 0.05~0.99 / Yield slope ratio |
| `fPeakDropForce` | REAL | IN | `0.30` | 千牛 | 峰值后压降判定量，0 表示不判 / Force drop after peak |
| `fEndPosTarget` | REAL | IN | `10.0` | 毫米 | 终点位移目标 / Target end position |
| `tStageTimeout` | TIME | IN | `T#5S` | 毫秒 | 单段动作超时，0 表示不监控 / Per-stage timeout |
| `tDwell` | TIME | IN | `T#500MS` | 毫秒 | 保压时间，0 表示跳过保压 / Dwell time |
| `fForceUpperLimit` | REAL | IN | `180.0` | 千牛 | 压力硬上限，达限立即转保压 / Hard force limit |
| `eState` | E_DL_PressFitState | OUT | — | — | 八态之一 / Current state |
| `bBusy` | BOOL | OUT | — | — | 循环进行中（接近至回退为真）/ Cycle in progress |
| `bDone` | BOOL | OUT | — | — | 循环结束**单拍**脉冲 / One-shot done pulse |
| `bOk` | BOOL | OUT | — | — | 判定合格，保持到下次启动 / Verdict OK, held |
| `bNg` | BOOL | OUT | — | — | 判定不合格，保持到下次启动 / Verdict NG, held |
| `bError` | BOOL | OUT | — | — | 故障级锁存，需复位清除 / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码或故障码，0 = 无 / Event or fault code |
| `uNgReason` | WORD | OUT | — | 位串 | NG 原因位：bit0 上包络越界 / bit1 下包络越界 / bit2 终点未达 / bit3 接触未建立 / bit4 保压压降超限（按位或累计）/ NG reason bits |
| `stResult` | ST_DL_PressFitResult | OUT | — | — | 四特征点：`fContactPos/Force`、`fYieldPos/Force`、`fPeakPos/Force`、`fEndPos/Force`；未提取到保持 0.0 / Curve feature result |
| `fEnvDevMax` | REAL | OUT | — | 千牛 | 全程包络最大偏差，趋势分析用 / Max envelope deviation |
| `nSampleCnt` | UDINT | OUT | — | 点 | 本循环有效采样点数 / Valid sample count |
| `stEnv` | ST_DL_PressFitEnvelope | IN_OUT | — | — | 包络表：`nPoints`（2~32）/ `afPos[1..32]`（毫米，**严格单调递增**）/ `afUpper[1..32]` / `afLower[1..32]`（千牛），**块内只读** / Envelope table, read only |
| `stStat` | ST_DL_PressFitStat | IN_OUT | — | — | 跨周期统计：`nCycleCount` / `nOkCount` / `nNgCount`，调用方持有 / Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_01C0` | 信息级 | 包络表点数超上限已钳位为 32 | 工艺组态超 32 节点需拆表或降低分辨率 |
| `0005_01C1` | 信息级 | 包络上下限对调已在块内镜像修复 | 组态表 `afUpper` / `afLower` 写反；本件自动纠正，仍建议改表 |
| `0005_02C0` | 故障级 | 非法状态兜底 | 枚举被外部强制写入未定义值；复位退出 |
| `0005_02C1` | 故障级 | 包络表非法（节点数 < 2、或位移非严格单调递增） | 修包络表；启动拍校验不通过即锁故障、不出完成脉冲 |
| `0005_02C2` | 故障级 | 阶段超时（接近 / 压入 / 保压三段共用） | 查伺服使能、机械卡滞；三段共用一码时按 `eState` 判断卡在哪段 |
| `0005_02C3` | 故障级 | 采样非有限值（当拍拒绝更新并转故障） | 查压力/位移通道是否掉线或除零 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_BearingPressFit
VAR
    fbPress        : FB_DL_PressFitStation;      // 压装工站实例 / Press-fit station
    stEnv          : ST_DL_PressFitEnvelope;     // 位移-压力包络表 / Envelope table
    stFitStat      : ST_DL_PressFitStat;         // 跨周期统计 / Persistent statistics
    bPressStart    : BOOL;                       // 启动压装 / Start a cycle
    bPressAbort    : BOOL;                       // 中止 / Abort
    bPressReset    : BOOL;                       // 故障复位 / Fault reset
    fRamPos        : REAL;                       // 压头位移 [毫米] / Ram position
    fRamForce      : REAL;                       // 压装压力 [千牛] / Press force
    ePressState    : E_DL_PressFitState;         // 状态观测 / State
    bPressBusy     : BOOL;                       // 循环中 / Busy
    bPressDone     : BOOL;                       // 完成单拍 / Done pulse
    bPressOk       : BOOL;                       // 合格 / OK
    bPressNg       : BOOL;                       // 不合格 / NG
    uPressNgReason : WORD;                       // NG 原因位 / NG reason bits
    stPressResult  : ST_DL_PressFitResult;       // 四特征点 / Feature points
    fEnvDevMax     : REAL;                       // 包络最大偏差 [千牛] / Max deviation
    uPressSampleCnt: UDINT;                      // 采样点数 / Sample count
    bPressErr      : BOOL;                       // 故障 / Fault
    uPressErrId    : UDINT;                      // 事件码 / Event code
    bEnvInit       : BOOL := FALSE;              // 包络表初始化完成 / Envelope initialised
    bStationAuto   : BOOL := TRUE;               // 工站自动模式 / Station in auto
    bTraceWriteReq : BOOL := FALSE;              // 追溯写请求 / Trace write request
    nTraceNgBits   : INT;                        // 追溯 NG 原因位 / NG bits for trace
END_VAR

// 包络表一次性组态：0 毫米（0~0）、10 毫米（2~10）千牛，位移严格递增
IF NOT bEnvInit THEN
    stEnv.nPoints     := 2;
    stEnv.afPos[1]    := 0.0;
    stEnv.afUpper[1]  := 0.0;
    stEnv.afLower[1]  := 0.0;
    stEnv.afPos[2]    := 10.0;
    stEnv.afUpper[2]  := 10.0;
    stEnv.afLower[2]  := 2.0;
    bEnvInit := TRUE;
END_IF

// 每周期无条件调用：压力硬上限 180 千牛、单段超时 5 秒、保压 500 毫秒
fbPress(bEnable := bStationAuto, bStart := bPressStart, bAbort := bPressAbort, bReset := bPressReset,
        fActPos := fRamPos, fActForce := fRamForce,
        fContactForceThr := 0.05, fYieldSlopeRatio := 0.50, fPeakDropForce := 0.30,
        fEndPosTarget := 10.0, tStageTimeout := T#5S, tDwell := T#500MS,
        fForceUpperLimit := 180.0,
        eState => ePressState, bBusy => bPressBusy, bDone => bPressDone,
        bOk => bPressOk, bNg => bPressNg, bError => bPressErr, uErrorId => uPressErrId,
        uNgReason => uPressNgReason, stResult => stPressResult,
        fEnvDevMax => fEnvDevMax, nSampleCnt => uPressSampleCnt,
        stEnv := stEnv, stStat := stFitStat);

// 完成脉冲把结论与特征点送追溯；NG 时按原因位分组提示
IF bPressDone THEN
    bTraceWriteReq := TRUE;
    nTraceNgBits   := WORD_TO_INT(uPressNgReason);
END_IF
END_PROGRAM
```

**要点 / Notes**

- **包络表只读**：注入的表一律不改写；上下限对调在块内**镜像纠正**并置 `01C1`，不偷偷改调用方数据。
- **单拍三律**：`bDone` 每拍预清零、`eFinish` 唯一置位、转出拍不再置位；合格与不合格在 `eEvaluate` 一次锁存，同循环闭环。
- **回退快照**：进回退态首拍取终点特征，位置最多滞后一个扫描周期。
- **非有限值防御**：位移或压力非有限时**当拍拒绝采样**并转故障（`02C3`），绝不把 NaN 带进包络插值。
- **不套通用步序基类**：压装态与监控量强耦合，套基类会出现两套状态机并存；也不重复包装机十七态全集（那由 `FB_DL_PackMlStateMachine` 承担）。

---

## 20. FB_DL_RotaryIndexTable ｜ 多工位分度盘节拍调度（R11，v1.0.0）

**定位 / Positioning**：管理「分度请求 → 到位确认 → 稳定等待 → 工位工艺放行」的节拍链，维护工位启用表与工艺号映射，支持空跑（清洗）模式逐位走完。五态：`eIdle` 0 / `eDwell` 10 / `eIndexing` 20 / `eSettling` 30 / `eFault` 99。

**为什么 `eSettling` 单独成态**：用于隔离「到位后抖动」的诊断窗口，避免把机械抖动混进分度超时计数——否则现场只会看到「偶发超时」，永远查不到松动。

**抖动诊断不自动重试**：稳定窗内到位信号掉沿即判硬件问题并**直接锁故障**。自动重试会把机械松动掩盖成偶发超时，现场极难定位。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 撤销分度请求并回待机 / Enable; withdraws the request |
| `bStart` | BOOL | IN | — | — | 启动节拍循环，上升沿受理 / Start the cycle |
| `bStop` | BOOL | IN | — | — | 完成当前工位后停止，上升沿受理 / Stop after the current station |
| `bReset` | BOOL | IN | — | — | 复位故障，上升沿受理 / Reset fault |
| `nStationCount` | INT | IN | — | 个 | 工位总数，有效域 2~24，越界钳位 / Station count |
| `nAtStation` | INT | IN | — | — | 机械到位工位号 1~工位数，0 = 未定位 / Mechanical station number |
| `bIndexInPos` | BOOL | IN | — | — | 分度到位开关信号 / Indexer in-position switch |
| `abStationEnable` | ARRAY[1..24] OF BOOL | IN | — | — | 工位启用表，`FALSE` 视为空位 / Station enable table |
| `anStationRecipe` | ARRAY[1..24] OF INT | IN | — | — | 工位工艺号表，**仅透传不校验** / Per-station recipe number |
| `tDwellTime` | TIME | IN | `T#1S` | 毫秒 | 每工位停留时间，0 表示不停留 / Dwell per station |
| `tSettleTime` | TIME | IN | `T#100MS` | 毫秒 | 到位后稳定确认时间，滤机械抖动 / Settling time |
| `tIndexTimeout` | TIME | IN | `T#3S` | 毫秒 | 分度超时，0 表示不监控 / Indexing timeout |
| `bDryRun` | BOOL | IN | — | — | 空跑（清洗）模式：忽略启用表逐位走完，**不计循环数** / Dry-run mode |
| `tCycle` | TIME | IN | `T#10MS` | 毫秒 | 任务扫描周期，累计运行时长基准（设计偏离 D1）/ Task cycle time |
| `bIndexReq` | BOOL | OUT | — | — | 分度请求**单拍**脉冲 / Index request pulse |
| `nActiveStation` | INT | OUT | — | — | 当前作业工位号，0 = 无效 / Active station |
| `bStationReady` | BOOL | OUT | — | — | 当前工位允许工艺动作 / Station ready |
| `nRecipeAtStation` | INT | OUT | — | — | 当前工位工艺号（透传，越界给 0）/ Recipe at station |
| `uStationMask` | DWORD | OUT | — | 位串 | 工位启用镜像，**第 n 位对应第 n 工位** / Station enable mirror |
| `bCycleDone` | BOOL | OUT | — | — | 整圈走完**单拍**脉冲 / Full-revolution pulse |
| `tDwellRemain` | TIME | OUT | — | 毫秒 | 当前工位剩余停留时间 / Remaining dwell |
| `eState` | E_DL_IndexTableState | OUT | — | — | 五态之一 / Current state |
| `bError` | BOOL | OUT | — | — | 故障锁存，需复位清除 / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码或故障码，0 = 无 / Event or fault code |
| `stStat` | ST_DL_IndexTableStat | IN_OUT | — | — | 跨周期统计：`nIndexCount`（成功分度次数）/ `nCycleCount`（整圈数）/ `tRunTime`（累计运行时长）/ Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_01C2` | 信息级 | 工位数量越界已钳位至 2~24 | 改 `nStationCount`；少于 2 工位的设备不适用本件 |
| `0005_02D0` | 故障级 | 分度超时（到位信号未在监控窗内建立） | 查分度电机、到位开关、`tIndexTimeout` 是否过短 |
| `0005_02D1` | 故障级 | 到位信号抖动或丢失（稳定窗内掉沿） | **查机械松动与开关安装**；本件不自动重试 |
| `0005_02D2` | 故障级 | 工位号越界（机械到位反馈不可信） | 到位信号编码与 `nStationCount` 不符 |
| `0005_02D3` | 故障级 | 非法状态兜底 | 复位退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_EightStationIndexer
VAR
    fbIndex        : FB_DL_RotaryIndexTable;     // 分度盘实例 / Index table
    stIdxStat      : ST_DL_IndexTableStat;       // 跨周期统计 / Persistent statistics
    bIdxStart      : BOOL;                       // 启动节拍 / Start
    bIdxStop       : BOOL;                       // 完成当前工位后停 / Stop
    bIdxReset      : BOOL;                       // 故障复位 / Reset
    nAtStation     : INT;                        // 机械到位工位号 / Mechanical station
    bIndexInPos    : BOOL;                       // 分度到位开关 / In-position switch
    abEnable       : ARRAY[1..24] OF BOOL;       // 工位启用表 / Station enable
    anRecipe       : ARRAY[1..24] OF INT;        // 工位工艺号表 / Station recipe
    bIndexReq      : BOOL;                       // 分度请求单拍 / Index request
    nActiveSta     : INT;                        // 当前作业工位 / Active station
    bStationReady  : BOOL;                       // 工位放行 / Station ready
    nRecipeHere    : INT;                        // 当前工位工艺号 / Recipe here
    uStationMask   : DWORD;                      // 工位启用镜像 / Enable mirror
    bCycleDone     : BOOL;                       // 整圈完成单拍 / Revolution done
    tDwellRemain   : TIME;                       // 剩余停留 / Remaining dwell
    eIdxPhase      : E_DL_IndexTableState;       // 状态观测 / Phase
    bIdxErr        : BOOL;                       // 故障 / Fault
    uIdxErrId      : UDINT;                      // 事件码 / Event code
    bIdxInit       : BOOL := FALSE;              // 工位表初始化完成 / Stations initialised
    bLineAuto      : BOOL := TRUE;               // 产线自动 / Line in auto
    bCleanMode     : BOOL := FALSE;              // 空跑清洗模式 / Dry-run cleaning
    bStationProcessEnable : BOOL;                // 工位工艺允许 / Station process enabled
END_VAR

// 工位表一次性组态：8 工位，前 5 个启用，工艺号 10~14
IF NOT bIdxInit THEN
    abEnable[1] := TRUE;  abEnable[2] := TRUE;  abEnable[3] := TRUE;
    abEnable[4] := TRUE;  abEnable[5] := TRUE;
    abEnable[6] := FALSE; abEnable[7] := FALSE; abEnable[8] := FALSE;
    anRecipe[1] := 10; anRecipe[2] := 11; anRecipe[3] := 12;
    anRecipe[4] := 13; anRecipe[5] := 14;
    bIdxInit := TRUE;
END_IF

// 每周期无条件调用：停留 1 秒、稳定 100 毫秒、分度超时 3 秒、任务周期 10 毫秒
fbIndex(bEnable := bLineAuto, bStart := bIdxStart, bStop := bIdxStop, bReset := bIdxReset,
        nStationCount := 8, nAtStation := nAtStation, bIndexInPos := bIndexInPos,
        abStationEnable := abEnable, anStationRecipe := anRecipe,
        tDwellTime := T#1S, tSettleTime := T#100MS, tIndexTimeout := T#3S,
        bDryRun := bCleanMode, tCycle := T#10MS,
        bIndexReq => bIndexReq, nActiveStation => nActiveSta,
        bStationReady => bStationReady, nRecipeAtStation => nRecipeHere,
        uStationMask => uStationMask, bCycleDone => bCycleDone,
        tDwellRemain => tDwellRemain, eState => eIdxPhase,
        bError => bIdxErr, uErrorId => uIdxErrId,
        stStat := stIdxStat);

// 工位放行期间才允许该工位动作；分度请求脉冲送驱动
bStationProcessEnable := bStationReady AND (NOT bIdxErr);
END_PROGRAM
```

**要点 / Notes**

- **分度计数只在「到位确认通过」拍累加**（设计偏离 D2）：超时未到位属失败分度，不计入成功次数。
- **掩码每拍重建**：由启用表逐位左移或运算构造，不拼累计量，规避位宽边界；工位上限定 24，恒在安全域内。
- **空跑模式不计循环数**：工艺放行恒假、分度链照走，用于清洗与调试；此时 `bCycleDone` 仍会出脉冲，上层判开机统计时需排除空跑。
- **`tCycle` 是新增引脚（默认 10 毫秒）**：统计结构体内含累计运行时长，块内无时间基准则无法累加；以任务扫描周期为基准，有默认值故向后兼容，不改变任何既有引脚语义。

---

## 21. FB_DL_AgvDockingHandshake ｜ 移动载体对接交接握手（R11，v1.0.1）

> **修订记录 / Revision**：**v1.0.1（2026-11-16，R13 存量 R39 修复）**——使能撤销分支原先把 `_eState` 无条件改写为 `eIdle`，而故障复位沿的消化位于其后 CASE 的 `eFault` 分支：禁用期间按下的复位沿当拍被抹掉，`_bFaultLatch` 与故障码留存至操作员补按第二次复位，期间使能回升也被「有锁存」判据挡在待机（出现 `eState` 报 `eIdle` 而 `bError = TRUE` 的自相矛盾态）。修复后 **`eFault` 态不被禁用覆盖**，其余状态行为不变；接口表与故障码表零变化。

**定位 / Positioning**：把「到位检测 → 双侧就绪握手 → 交接放行 → 完成确认」做成带超时与失序诊断的七态交接状态机（`eIdle` 0 / `eWaitArrive` 10 / `eDockConfirm` 20 / `ePermitTransfer` 30 / `eTransferMonitor` 40 / `eComplete` 50 / `eFault` 99），屏蔽移动载体与固定工站两侧的信号时序差异，产出单一放行位与握手成功单拍脉冲。

**与线体级联的边界**：`FB_DL_ConveyorLineLink` 处理固定段之间的**连续物流**握手（长连接）；本件面向移动载体与固定工站的**临时对接**（会话式、一次性），握手条件含「物料在位」与「双侧就绪」双约束，语义与生命周期都不同。

**物料一致性快照**：进入交接监视时快照物料在位位；过程中该位由真转假且完成确认尚未到达，即判**物料丢失或错位**（`02E2`）——因为这属于「该在的时候不在」。

**失序诊断**：完成确认在到位或握手阶段提前到达属**非法请求序列**（`02E3`），直接锁故障而**不吞掉**，否则上游误接线会被解释成「一次成功交接」。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 撤回全部放行位 / Enable; withdraws all permits |
| `bReset` | BOOL | IN | — | — | 复位故障，上升沿受理 / Reset fault |
| `bAbort` | BOOL | IN | — | — | 中止本次交接，上升沿受理，**不置故障** / Abort without a fault |
| `bAgvArrived` | BOOL | IN | — | — | 载体到位光电（粗定位）/ Carrier presence sensor |
| `bAgvDockReady` | BOOL | IN | — | — | 载体侧对接机构就绪 / Carrier-side dock ready |
| `bStationReady` | BOOL | IN | — | — | 工站侧可收料或可放料 / Station-side ready |
| `bMaterialOnAgv` | BOOL | IN | — | — | 物料在位（交接前为载侧、交接后为站侧）/ Material present |
| `bTransferDone` | BOOL | IN | — | — | 下游完成接收确认 / Downstream receipt confirmation |
| `tArriveTimeout` | TIME | IN | `T#10S` | 毫秒 | 到位确认超时，0 表示不监控 / Arrival timeout |
| `tHandshakeTimeout` | TIME | IN | `T#5S` | 毫秒 | 双侧就绪握手超时 / Handshake timeout |
| `tTransferTimeout` | TIME | IN | `T#30S` | 毫秒 | 交接过程超时 / Transfer timeout |
| `bDockLamp` | BOOL | OUT | — | — | 对接允许指示灯（载体可进入）/ Dock-permitted lamp |
| `bTransferPermit` | BOOL | OUT | — | — | 放行交接（可放料或可接料）/ Transfer permit |
| `bHandshakeOk` | BOOL | OUT | — | — | 握手成功**单拍**脉冲（进入放行态那一拍）/ Handshake success pulse |
| `bTransferComplete` | BOOL | OUT | — | — | 交接完成，保持到下次启动 / Transfer complete, held |
| `eState` | E_DL_AgvDockState | OUT | — | — | 七态之一 / Current state |
| `bError` | BOOL | OUT | — | — | 故障锁存，需复位清除 / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码或故障码，0 = 无 / Event or fault code |
| `tElapsed` | TIME | OUT | — | 毫秒 | 当前态已耗时，现场判读卡在哪个阶段 / Elapsed in current state |
| `stStat` | ST_DL_AgvDockStat | IN_OUT | — | — | 跨周期统计：`nDockCount` / `tTotalTransfer` / `tLastCycle` / Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_01C3` | 信息级 | 超时参数越界已钳位 | 检查三个 `t*Timeout` 是否为 0 或负值写入 |
| `0005_02E0` | 故障级 | 到位确认超时 | 查载体定位与到位光电；`tElapsed` 可确认卡在 `eWaitArrive` |
| `0005_02E1` | 故障级 | 握手或交接超时（两处共用） | 按 `eState` 区分是 `eDockConfirm` 还是 `eTransferMonitor` |
| `0005_02E2` | 故障级 | 物料在位信号丢失 | 查物料是否在交接中滑落或信号线脱落；本件同时撤放行 |
| `0005_02E3` | 故障级 | 非法请求序列（完成确认提前到达） | 查上游误接线；**不会静默吞掉**，避免被当成成功交接 |
| `0005_02E4` | 故障级 | 非法状态兜底 | 复位退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_AgvDockHandshake
VAR
    fbDock          : FB_DL_AgvDockingHandshake;  // 对接握手实例 / Docking handshake
    stDockStat      : ST_DL_AgvDockStat;          // 跨周期统计 / Persistent statistics
    bDockReset      : BOOL;                       // 故障复位 / Reset
    bDockAbort      : BOOL;                       // 中止交接 / Abort
    bAgvArrived     : BOOL;                       // 载体到位 / Carrier arrived
    bAgvDockReady   : BOOL;                       // 载侧就绪 / Carrier ready
    bStaReady       : BOOL;                       // 站侧就绪 / Station ready
    bMaterialHere   : BOOL;                       // 物料在位 / Material present
    bTransferDone   : BOOL;                       // 完成确认 / Transfer done
    bDockLamp       : BOOL;                       // 对接允许灯 / Dock lamp
    bTransferPermit : BOOL;                       // 放行交接 / Transfer permit
    bHandshakeOk    : BOOL;                       // 握手成功单拍 / Handshake pulse
    bTransferCplt   : BOOL;                       // 交接完成保持 / Transfer complete
    eDockState      : E_DL_AgvDockState;          // 状态观测 / State
    bDockErr        : BOOL;                       // 故障 / Fault
    uDockErrId      : UDINT;                      // 事件码 / Event code
    tDockElapsed    : TIME;                       // 当前态耗时 / Elapsed
    bStationAuto    : BOOL := TRUE;               // 工站自动 / Station in auto
    nDockTraceCount : INT;                        // 握手次数记账 / Handshake trace count
END_VAR

// 每周期无条件调用：到位 10 秒、握手 5 秒、交接 30 秒
fbDock(bEnable := bStationAuto, bReset := bDockReset, bAbort := bDockAbort,
       bAgvArrived := bAgvArrived, bAgvDockReady := bAgvDockReady,
       bStationReady := bStaReady, bMaterialOnAgv := bMaterialHere,
       bTransferDone := bTransferDone,
       tArriveTimeout := T#10S, tHandshakeTimeout := T#5S, tTransferTimeout := T#30S,
       bDockLamp => bDockLamp, bTransferPermit => bTransferPermit,
       bHandshakeOk => bHandshakeOk, bTransferComplete => bTransferCplt,
       eState => eDockState, bError => bDockErr, uErrorId => uDockErrId,
       tElapsed => tDockElapsed, stStat := stDockStat);

// 放行位与指示灯直连现场执行机构；握手单拍送 MES 记账
IF bHandshakeOk THEN
    nDockTraceCount := nDockTraceCount + 1;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **到位与双侧就绪都要求「连续两拍」**（设计偏离 D2）：等价于「沿后与门」，但不需要额外边沿实例，拍序更易推演。
- **`bHandshakeOk` 取「握手成功」口径**（设计偏离 D1）：脉冲发生在**进入放行态**那一拍；完成确认只负责置 `bTransferComplete` 保持位。
- **一键灯语义**：`bDockLamp` 表示「载体可进入」，`bTransferPermit` 表示「现在可搬」；两者不是同一个信号，HMI 不要混用。
- **超时参数为 0 表示不监控**：调试期可临时关闭，但量产的到位超时必须开启（否则失联载体永远挂在那里）。

---

## 22. FB_DL_EnergySavingMode ｜ 整线空闲节能编排（R11，v1.0.0）

**定位 / Positioning**：以「空闲确认延时 → 节能态（降压 / 停热 / 伺服休眠）→ 唤醒缓冲」三段编排节能与生产，四态 `eRun` 0 / `eIdleCount` 10 / `eEco` 20 / `eWake` 30（+ `eFault` 99）。输出可解释的节能标志与累计时长，杜绝「唤醒即放行」造成的低压启动。

**进入与退出必须有序 / Staged in, reverse out**：进入固定「先降压 → 再停热 → 最后伺服休眠」，每步间隔一个台阶（默认 500 毫秒）——因为伺服休眠时若气源仍为工作压力，**抱闸释放瞬间会顶件**。退出严格反序（先撤休眠 → 再撤停热 → 最后恢复压力），保证伺服再上电时气源已在工作压力附近。

**唤醒门控三条与门 / Gated wake**：① 压力达节能目标 + 裕量；② 压力低位请求已撤；③ 唤醒缓冲走完。三条全真才放行，防压力表冲高瞬放行。

**三出口无锁存 / Stateless outlets**：`bAirPressureLow` / `bHeatStandby` / `bServoSleep` 全部为状态派生式（每拍先清零再按所在阶段置位），任何异常路径（故障、使能撤销）都会在下一拍自然复位，不需要额外撤除分支。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 立即回运行态并撤节能请求 / Enable; FALSE returns to run |
| `bReset` | BOOL | IN | — | — | 复位故障，上升沿受理 / Reset fault |
| `bLineIdle` | BOOL | IN | — | — | 产线空闲判据（无料且无作业）/ Line idle criterion |
| `bWakeRequest` | BOOL | IN | — | — | 唤醒请求（来料 / 操作员 / 上位机）/ Wake-up request |
| `fAirPressureAct` | REAL | IN | — | 巴 | 实际气源压力，量程 0.0~10.0 / Actual air pressure |
| `fAirPressureEco` | REAL | IN | `4.0` | 巴 | 节能目标压力，域 0.0~10.0 / Eco target pressure |
| `fWakeMargin` | REAL | IN | `0.2` | 巴 | 唤醒压力裕量，须达目标加裕量 / Wake margin |
| `tIdleDelay` | TIME | IN | `T#120S` | 毫秒 | 空闲确认延时，0 表示立即节能 / Idle confirm delay |
| `tWakeRamp` | TIME | IN | `T#3S` | 毫秒 | 唤醒缓冲（压力恢复等待上限）/ Wake ramp allowance |
| `bServoSleepPermit` | BOOL | IN | — | — | 允许伺服休眠，**由工艺侧给出** / Servo sleep permitted |
| `bHeatStandbyPermit` | BOOL | IN | — | — | 允许加热转保温或关闭 / Heater standby permitted |
| `bEcoActive` | BOOL | OUT | — | — | 节能模式生效（**节能与唤醒期间均为真**）/ Eco mode engaged |
| `bAirPressureLow` | BOOL | OUT | — | — | 请求降压（送气源比例阀）/ Request reduced pressure |
| `bHeatStandby` | BOOL | OUT | — | — | 请求加热转保温或关闭 / Request heater standby |
| `bServoSleep` | BOOL | OUT | — | — | 请求伺服休眠 / Request servo sleep |
| `bReadyToRun` | BOOL | OUT | — | — | 唤醒完成，可放行生产 / Ready to run |
| `eState` | E_DL_EcoModeState | OUT | — | — | 五态之一 / Current state |
| `bError` | BOOL | OUT | — | — | 故障锁存，需复位清除 / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码或故障码，0 = 无 / Event or fault code |
| `tIdleElapsed` | TIME | OUT | — | 毫秒 | 空闲累计已计时长 / Idle elapsed |
| `tEcoElapsed` | TIME | OUT | — | 毫秒 | 本次节能已持续时长 / Eco elapsed |
| `stStat` | ST_DL_EcoStat | IN_OUT | — | — | 跨周期统计：`tTotalEco` / `nSwitchCount` / `tLastEco` / Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_01C4` | 信息级 | 延时或压力参数越界已钳位 | 检查 `fAirPressureEco` 是否高于工作压力（目标必须低于工作压力） |
| `0005_02F0` | 故障级 | 唤醒超时（超过两倍唤醒缓冲仍未达压） | 查气源供气能力、比例阀是否卡在低压位 |
| `0005_02F1` | 故障级 | 气源压力反馈缺失（读数为零或非有限值） | 查压力传感器；**无反馈时无法确认压力恢复，一律禁止放行** |
| `0005_02F2` | 故障级 | 非法状态兜底 | 复位退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_LineEnergySaving
VAR
    fbEco           : FB_DL_EnergySavingMode;     // 节能编排实例 / Eco orchestrator
    stEcoStat       : ST_DL_EcoStat;              // 跨周期统计 / Persistent statistics
    bEcoReset       : BOOL;                       // 故障复位 / Reset
    bLineIdle       : BOOL;                       // 产线空闲 / Line idle
    bWakeRequest    : BOOL;                       // 唤醒请求 / Wake request
    fAirPressure    : REAL;                       // 实际气源压力 [巴] / Actual air pressure
    bServoSleepOk   : BOOL := TRUE;               // 工艺允许伺服休眠 / Servo sleep permitted
    bHeatStandbyOk  : BOOL := TRUE;               // 工艺允许加热保温 / Heater standby permitted
    bEcoActive      : BOOL;                       // 节能生效 / Eco active
    bPressureLow    : BOOL;                       // 请求降压 / Request low pressure
    bHeatStandby    : BOOL;                       // 请求加热保温 / Request standby
    bServoSleep     : BOOL;                       // 请求伺服休眠 / Request sleep
    bReadyToRun     : BOOL;                       // 可放行生产 / Ready to run
    eEcoState       : E_DL_EcoModeState;          // 状态观测 / State
    bEcoErr         : BOOL;                       // 故障 / Fault
    uEcoErrId       : UDINT;                      // 事件码 / Event code
    tIdleElapsed    : TIME;                       // 空闲已计时 / Idle elapsed
    tEcoElapsed     : TIME;                       // 节能已持续 / Eco elapsed
    bLinePowerOn    : BOOL := TRUE;               // 整线上电 / Line powered
    bProductionEnable : BOOL;                     // 生产放行 / Production enabled
END_VAR

// 每周期无条件调用：空闲 120 秒确认、目标 4.0 巴、裕量 0.2 巴、唤醒缓冲 3 秒
fbEco(bEnable := bLinePowerOn, bReset := bEcoReset,
      bLineIdle := bLineIdle, bWakeRequest := bWakeRequest,
      fAirPressureAct := fAirPressure, fAirPressureEco := 4.0, fWakeMargin := 0.2,
      tIdleDelay := T#120S, tWakeRamp := T#3S,
      bServoSleepPermit := bServoSleepOk, bHeatStandbyPermit := bHeatStandbyOk,
      bEcoActive => bEcoActive, bAirPressureLow => bPressureLow,
      bHeatStandby => bHeatStandby, bServoSleep => bServoSleep,
      bReadyToRun => bReadyToRun, eState => eEcoState,
      bError => bEcoErr, uErrorId => uEcoErrId,
      tIdleElapsed => tIdleElapsed, tEcoElapsed => tEcoElapsed,
      stStat := stEcoStat);

// 生产放行 = 唤醒门控通过且无故障；三个节能请求送对应执行侧
bProductionEnable := bReadyToRun AND (NOT bEcoErr);
END_PROGRAM
```

**要点 / Notes**

- **节能目标压力必须低于工作压力、且高于夹具最低夹持压力**：低于夹持压力会导致待机期间工件松脱。请先按气动原理图核算最低夹持压力再定目标值。
- **唤醒裕量不宜小于传感器重复精度**：否则门控会在阈值上下反复抖动；现场经验值是传感器精度的 3~5 倍。
- **伺服休眠许可由工艺侧给出**：本块不判断伺服是否已停稳；需要停机确认时请把停稳反馈串进许可位，**不要在块内加延时猜测**。
- **唤醒缓冲只保证「压力恢复后才放行」**，不保证「工件已就位」；来料检测与就位确认仍由上游工站负责。
- **`bEcoActive` 在唤醒期间仍为真**：它是「处于节能模式」的语义，不是「已经省电」；HMI 若需区分「正在节能」与「正在唤醒」，读 `eState`。

---

## 23. FB_DL_BatchPhaseBase ｜ ISA-88 相状态底座（R12，v1.0.1）

**定位 / Positioning**：按 ISA-88 / IEC 61512 的相状态模型提供 11 态相底座：本件**不编排任何具体工艺动作**，只输出「相状态 + 当前步骤号 + 单拍执行请求」，动作由调用方按 `bRequestStep` 派发。服务对象是配料、反应、清洗、灭菌这类「有明确步骤序列、要记录相耗时、暂停后不能重头」的批次工艺。

**三条不可妥协的语义 / Three non-negotiables**：① **暂停在步骤边界生效**（不在步骤中途），这是「暂停后物料半投」事故的根因；② **恢复不重头**（步骤号不变，重发当前步请求）；③ **已终止态（完成 / 已停 / 已中止）只接受复位**，不接受启动与中止。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时冻结状态与输出且**不清零** / Enable, freezes the phase without clearing it |
| `bStart` | `BOOL` | IN | — | — | 启动，上升沿有效，**仅空闲态受理**（终止态须先复位）/ Rising edge starts the phase in idle only |
| `bHold` | `BOOL` | IN | — | — | 请求暂停，上升沿有效，在步骤边界生效 / Requests a hold at a step boundary |
| `bRestart` | `BOOL` | IN | — | — | 从已暂停恢复，上升沿有效，继续当前步骤 / Resumes the current step |
| `bStop` | `BOOL` | IN | — | — | 请求停止，上升沿有效，在当前步骤完成后停 / Requests a controlled stop |
| `bAbort` | `BOOL` | IN | — | — | 请求中止，上升沿有效，立即跳出步骤 / Aborts immediately |
| `bReset` | `BOOL` | IN | — | — | 复位，上升沿有效，从终止态回空闲 / Returns the phase to idle |
| `bStepDone` | `BOOL` | IN | — | — | 步骤完成反馈（相内动作成功）/ Step completion feedback |
| `bStepFail` | `BOOL` | IN | — | — | 步骤失败反馈（相内动作失败）/ Step failure feedback |
| `nStepCount` | `INT` | IN | `1` | 步 | 相内步骤数，有效域 1~32 / Steps in the phase |
| `tStepTimeout` | `TIME` | IN | `T#60S` | 毫秒 | 单步超时，**`T#0S` = 不监控** / Per-step timeout, zero disables the watchdog |
| `tHoldTimeout` | `TIME` | IN | `T#600S` | 毫秒 | 暂停超时，**`T#0S` = 不监控** / Hold timeout, zero disables the watchdog |
| `ePhase` | `E_DL_BatchPhaseState` | OUT | — | — | 相状态，对外唯一状态出口 / Phase state |
| `nStepNo` | `INT` | OUT | — | 步 | 当前步骤号 1 起，0 = 未进入 / Current step number |
| `bPhaseActive` | `BOOL` | OUT | — | — | 相处于活动族（执行 / 暂停族 / 收尾 / 停止 / 中止中）/ Phase is active |
| `bPhaseComplete` | `BOOL` | OUT | — | — | 相正常完成（完成相保持）/ Phase completed normally |
| `bRequestStep` | `BOOL` | OUT | — | — | **单拍**：请执行当前步的动作 / One-scan request to execute the step |
| `bRequestAbort` | `BOOL` | OUT | — | — | **单拍**：请执行中止动作 / One-scan request to run the abort action |
| `uPhaseElapsed` | `UDINT` | OUT | — | 秒 | 相净运行累计时间（不含暂停）/ Accumulated running seconds |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0203`~`0206` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |

状态枚举：`E_DL_BatchPhaseState`（`eIdle` 0 ／ `eRunning` 10 ／ `eCompleting` 20 ／ `eComplete` 30 ／ `eHolding` 40 ／ `eHeld` 50 ／ `eRestarting` 60 ／ `eStopping` 70 ／ `eStopped` 80 ／ `eAborting` 90 ／ `eAborted` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_0104` | 信息级 | 相内步骤数越界，已钳到 1~32 | 步骤数应等于实际相内动作数；填 0 会被钳成 1 |
| `0005_0105` | 信息级 | 同拍多命令，低优先命令已丢弃（**不排队**） | 命令优先级：中止 > 停止 > 暂停 > 恢复 > 启动；复位独立通道 |
| `0005_0106` | 信息级 | 从暂停恢复，步骤号不重置（继续当前步） | 正常路径；若期望重头，请用复位后重新启动 |
| `0005_0107` | 信息级 | 单步或暂停超时监控被关闭（时间参数为 0） | 调试期可关；生产必须开，否则卡步无人知 |
| `0005_0203` | 故障级 | 单步超时，相中止 | 查该步动作的完成反馈是否丢失；超时值是否小于最坏工艺时间 |
| `0005_0204` | 故障级 | 步骤失败反馈，相中止（与完成反馈同拍时**失败优先**） | 定位到具体步做工艺排查；失败优先是安全侧设计 |
| `0005_0205` | 故障级 | 暂停超时，相中止 | 暂停过久意味着物料可能已变质；按工艺上限设定 |
| `0005_0206` | 故障级 | 非法状态兜底（直接进已中止，**不回空闲**） | 检查在线修改与库版本；须复位才能回空闲 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_DosingPhase
VAR
    fbPhase       : FB_DL_BatchPhaseBase;    // 相实例 / Phase instance
    bPhaseRun     : BOOL := TRUE;            // 相使能 / Phase enabled
    bPhaseStart   : BOOL;                    // 启动 / Start
    bPhaseHold    : BOOL;                    // 暂停请求 / Hold request
    bPhaseRestart : BOOL;                    // 恢复 / Restart
    bPhaseStop    : BOOL;                    // 停止 / Stop
    bPhaseAbort   : BOOL;                    // 中止 / Abort
    bPhaseReset   : BOOL;                    // 复位 / Reset
    bStepDoneFb   : BOOL;                    // 步完成反馈 / Step done
    bStepFailFb   : BOOL;                    // 步失败反馈 / Step fail
    ePhaseNow     : E_DL_BatchPhaseState;    // 相状态 / Phase state
    nStepNow      : INT;                     // 当前步号 / Current step
    bPhaseBusy    : BOOL;                    // 相活动 / Phase active
    bPhaseFinished: BOOL;                    // 相完成 / Phase complete
    bDoStep       : BOOL;                    // 单拍执行请求 / Step request
    bDoAbort      : BOOL;                    // 单拍中止请求 / Abort request
    uPhaseSec     : UDINT;                   // 相净运行秒 / Net running seconds
    bPhaseFault   : BOOL;                    // 故障 / Fault
    uPhaseErr     : UDINT;                   // 事件码 / Event code
    bValveOpen    : BOOL;                    // 进料阀 / Feed valve
    bAgitator     : BOOL;                    // 搅拌 / Agitator
END_VAR

fbPhase(bEnable := bPhaseRun, bStart := bPhaseStart, bHold := bPhaseHold,
        bRestart := bPhaseRestart, bStop := bPhaseStop, bAbort := bPhaseAbort,
        bReset := bPhaseReset, bStepDone := bStepDoneFb, bStepFail := bStepFailFb,
        nStepCount := 3, tStepTimeout := T#90S, tHoldTimeout := T#10M,
        ePhase => ePhaseNow, nStepNo => nStepNow, bPhaseActive => bPhaseBusy,
        bPhaseComplete => bPhaseFinished, bRequestStep => bDoStep,
        bRequestAbort => bDoAbort, uPhaseElapsed => uPhaseSec,
        bError => bPhaseFault, uErrorId => uPhaseErr);

// 动作按步号派发：bRequestStep 是单拍脉冲，必须在同一拍内消费
IF bDoStep AND (NOT bPhaseFault) THEN
    CASE nStepNow OF
        1: bValveOpen := TRUE;                    // 进料
        2: bAgitator  := TRUE;                    // 搅拌
        3: bValveOpen := FALSE; bAgitator := TRUE; // 收尾（保搅拌）
    END_CASE
END_IF
IF bDoAbort THEN
    bValveOpen := FALSE;
    bAgitator  := FALSE;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **单步超时必须按步重计时**：v1.0.1 修的正是这条（范式 R40）。原实现在执行 / 收尾 / 停止三相之间定时器 `IN` 连续为真，步骤推进从不断输入，`ET` 跨步累加——「单步超时」退化为「相内累计超时」，3 步各 30 s 的完全合规批次会在第 3 步被误判 `0203` 中止。现在步骤边界断输入一拍，按步重新计时。
- **`bRequestStep` 是单拍脉冲**：必须**当拍**消费。若把动作写在 `IF bPhaseActive` 里，会在整个步骤期间每拍重复触发。
- **暂停在步骤边界**：给 `bHold` 后相先进入 `eHolding`，当前步完成反馈到达才进 `eHeld`。这是为了不让物料在「半投」状态下停住；急着停请用 `bAbort`。
- **掉使能不清零**：`bEnable = FALSE` 冻结状态与全部输出但**保留相状态**——批次报表需要看到最后相状态。要清零只能复位。
- **`uPhaseElapsed` 只在执行相累加**：暂停与其余相不计入，故它是「相净运行时间」，MES 用它算相耗时与产能。

---

## 24. FB_DL_PollTempBank ｜ 温控器轮询采集行（R12，v1.0.0）

**定位 / Positioning**：一条温控器采集行——对最多 8 台温控器轮询采过程值与设定值，做工程量换算、有效域判定、逐通道滑动均值、偏差与最差通道定位，输出通道质量掩码与在线台数；连续失败通道自动摘除并在恢复后自动复位。服务对象是多区热流道、烘箱、锂电烘烤线、注塑机料筒等「一堆温控表挂在同一条 485 总线上」的场合。

**分层 / Layering**：调度归既有轮询主站件（本件内嵌其一个实例，只注入站表与节拍参数，不重写调度、重试与超时逻辑）；滤波归既有滑动均值件（八通道各持一个实例）；本件只做「行级编排 + 通道质量」，**不做温控闭环**——设定值下发、自整定、超温切断属温控器内部或工艺层职责。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时暂停轮询并保持输出 / Enable, polling paused and outputs held |
| `bReset` | `BOOL` | IN | — | — | 上升沿复位故障与摘除状态 / Rising edge clears the fault and the drop state |
| `nDeviceCount` | `INT` | IN | `4` | 台 | 温控器台数，有效域 1~8 / Device count, 1..8 |
| `anSlaveAddr` | `ARRAY[1..8] OF USINT` | IN | — | — | 各台从站地址（1~247）/ Slave address per device |
| `auPvRaw` | `ARRAY[1..8] OF INT` | IN | — | 原始码 | 各台过程值原始寄存器（由传输层写入）/ Raw process values |
| `auSvRaw` | `ARRAY[1..8] OF INT` | IN | — | 原始码 | 各台设定值原始寄存器 / Raw setpoints |
| `abPollOk` | `ARRAY[1..8] OF BOOL` | IN | — | — | 各台本次轮询成功标志 / Per-device poll success flags |
| `fScaleGain` | `REAL` | IN | `0.1` | ℃/码 | 原始码到温度的比例，域 > 0 / Raw to temperature gain |
| `fScaleOffset` | `REAL` | IN | `0.0` | ℃ | 零点偏移 / Zero offset |
| `fRangeMin` | `REAL` | IN | `-50.0` | ℃ | 有效温度下限 / Valid temperature lower bound |
| `fRangeMax` | `REAL` | IN | `200.0` | ℃ | 有效温度上限 / Valid temperature upper bound |
| `nFilterLen` | `INT` | IN | `8` | 拍 | 滑动均值窗口长度，有效域 1~32 / Moving average window |
| `nDropAfterFails` | `INT` | IN | `3` | 次 | 连续失败多少次摘除通道，有效域 1~10 / Failures before dropping a channel |
| `aPollTable` | `ARRAY[0..15] OF ST_DL_PollItem` | IN_OUT | — | — | 轮询站表，由内嵌调度实例持有并更新统计 / Poll table |
| `afTempC` | `ARRAY[1..8] OF REAL` | OUT | — | ℃ | 各台温度，坏通道保持上次有效值 / Temperature per device |
| `afSetpointC` | `ARRAY[1..8] OF REAL` | OUT | — | ℃ | 各台设定值 / Setpoint per device |
| `afDeviation` | `ARRAY[1..8] OF REAL` | OUT | — | ℃ | 各台偏差（过程值 − 设定值）/ Deviation |
| `afTempAvg` | `ARRAY[1..8] OF REAL` | OUT | — | ℃ | 各台滑动均值 / Per-device moving average |
| `auCommFailCnt` | `ARRAY[1..8] OF UINT` | OUT | — | 次 | 各台连续失败次数，饱和到 9999 / Consecutive failures |
| `uQualityMask` | `WORD` | OUT | — | 位串 | 通道坏质量掩码，位 n−1 对应第 n 台 / Bad channel mask |
| `nOnlineCount` | `INT` | OUT | — | 台 | 在线台数 / Online device count |
| `nWorstIdx` | `INT` | OUT | — | 通道号 | 偏差绝对值最大的在线通道号，0 = 无 / Channel with the largest deviation |
| `fWorstDev` | `REAL` | OUT | — | ℃ | 该通道的有符号偏差 / Signed deviation of that channel |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0207`~`0209` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_TempBankPhase` | OUT | — | — | `eIdle` 0 ／ `ePolling` 10 ／ `eFault` 99 / Current phase |

状态枚举：`E_DL_TempBankPhase`（`eIdle` 0 ／ `ePolling` 10 ／ `eFault` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0005_0108` | 信息级 | 台数、窗口长度或摘除阈值越界已钳位 | 台数 1~8、窗口 1~32、阈值 1~10 |
| `0005_0109` | 信息级 | 通道连续失败达阈值已摘除（**仍继续轮询以便自动恢复**） | 查该台通讯线、地址设置与波特率 |
| `0005_010A` | 信息级 | 滤波窗口为 1，均值等于瞬时值（无滤波能力） | 窗口 1 只适合快速验证；生产建议 4~8 |
| `0005_0207` | 故障级 | 换算比例非正（量纲错，含零乘隐患） | `fScaleGain` 必须 > 0；改正后复位 |
| `0005_0208` | 故障级 | 有效温度域为空（上限 ≤ 下限），任何读数都会被判无效 | 下限必须小于上限 |
| `0005_0209` | 故障级 | 非法状态兜底（终端安全态） | 检查在线修改与库版本 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_HotRunnerBank
VAR
    fbTempBank   : FB_DL_PollTempBank;      // 采集行实例 / Bank instance
    aPollTable   : ARRAY[0..15] OF ST_DL_PollItem;  // 轮询站表 / Poll table
    aSlave       : ARRAY[1..8] OF USINT := [1, 2, 3, 4, 5, 6, 7, 8];  // 从站地址
    aPvRaw       : ARRAY[1..8] OF INT;      // 过程值原始码 / Raw PV
    aSvRaw       : ARRAY[1..8] OF INT;      // 设定值原始码 / Raw SV
    aPollOk      : ARRAY[1..8] OF BOOL;     // 轮询成功标志 / Poll OK flags
    aTemp        : ARRAY[1..8] OF REAL;     // 温度 [℃] / Temperatures
    aSetpoint    : ARRAY[1..8] OF REAL;     // 设定值 [℃] / Setpoints
    aDeviation   : ARRAY[1..8] OF REAL;     // 偏差 [℃] / Deviations
    aTempAvg     : ARRAY[1..8] OF REAL;     // 滑动均值 [℃] / Averages
    aFailCnt     : ARRAY[1..8] OF UINT;     // 连续失败次数 / Failure counters
    wQuality     : WORD;                    // 坏通道掩码 / Bad mask
    nOnline      : INT;                     // 在线台数 / Online count
    nWorstCh     : INT;                     // 最差通道 / Worst channel
    fWorstDev    : REAL;                    // 最差偏差 / Worst deviation
    bBankFault   : BOOL;                    // 故障 / Fault
    uBankErr     : UDINT;                   // 事件码 / Event code
    eBankPhase   : E_DL_TempBankPhase;      // 相位观测 / Phase
    bBankRun     : BOOL := TRUE;            // 采集使能 / Acquisition enabled
    bBankReset   : BOOL;                    // 复位 / Reset
    bZonePermit  : BOOL;                    // 全区放行 / Zone permit
END_VAR

fbTempBank(bEnable := bBankRun, bReset := bBankReset, nDeviceCount := 8,
           anSlaveAddr := aSlave, auPvRaw := aPvRaw, auSvRaw := aSvRaw,
           abPollOk := aPollOk, fScaleGain := 0.1, fScaleOffset := 0.0,
           fRangeMin := -50.0, fRangeMax := 200.0,
           nFilterLen := 8, nDropAfterFails := 3, aPollTable := aPollTable,
           afTempC => aTemp, afSetpointC => aSetpoint, afDeviation => aDeviation,
           afTempAvg => aTempAvg, auCommFailCnt => aFailCnt, uQualityMask => wQuality,
           nOnlineCount => nOnline, nWorstIdx => nWorstCh, fWorstDev => fWorstDev,
           bError => bBankFault, uErrorId => uBankErr, eState => eBankPhase);

// 全部通道在线且质量掩码为零才放行全区加热
bZonePermit := (NOT bBankFault) AND (wQuality = 16#0000) AND (nOnline = 8);
END_PROGRAM
```

**要点 / Notes**

- **摘除后必须继续轮询**：摘除与恢复是**一对**。若摘除后停止轮询，被摘除的通道永远拿不到有效数据、也就永远无法恢复。本件摘除后仍继续轮询，连续两拍有效即自动复位。
- **坏通道保持上次值**：绝不用零或上限填充——零摄氏度在锂箱、冷库等场景是合法工况值，用零填充会掩盖真实故障。改看 `uQualityMask` 与 `auCommFailCnt`。
- **传输层必须替换**：内嵌调度实例以库内基类形态声明，帧收发为抽象桩。生产部署须由具备真实串口 / 网口收发的派生块替换声明，否则调度会锁「传输层未实现」故障、全部通道逐台摘除。该失败是**可观测的**（质量掩码全置位、在线台数为零），不会静默给出假温度。
- **换算参数与有效域必须成对**：`fScaleGain` / `fScaleOffset` 决定量纲，`fRangeMin` / `fRangeMax` 决定「什么算有效」。只改量纲不改域，会让超量程读数被判为合法。
- **只读不写**：设定值下发不在本件范围。需要写设定值时请另起写通道，并与本件的 `afSetpointC` 做一致性核对。

---
---

## 25. FB_DL_CapperTorqueTrend ｜ 旋盖扭矩曲线特征与 NG 判别（R13，v1.0.1）

**定位**：单次拧紧周期的扭矩曲线特征提取 + 五类 NG 判别。特征：峰值 `fPeak`、上升斜率 `fSlope`、稳态段均值 `fSteadyMean`、上升段/总段面积比；判别：低扭 / 高扭 / 滑牙 / 歪盖 / 曲线异常，输出 NG 原因位图（可多位并置）与单一主判定（优先级 = **滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常**，按安全/功能严重度降序）。

**边界纪律**：① **不内联分位排序**——批次分位由 `FC_DL_PercentileLReal` 在批次层算好，以 `fBatchP10` / `fBatchP90` 引脚注入；② **不内联滤波**——曲线平滑由上游 `FB_DL_MedianFilter` / `FB_DL_MovingAverage` 完成，本件输入视为已平滑曲线；③ 不做拧紧轴运动控制；④ 不做 SPC 与合格率统计。**NG 属工件不良，不置 bError**。

### 25.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` / `bReset` | `BOOL` | IN | — | — | 使能 / 复位（上升沿清判定、保持量与计数）/ Enable and reset |
| `bCycleStart` | `BOOL` | IN | — | — | 单次拧紧开始，**上升沿受理**；eSampling 内保持 TRUE 两拍不二次触发（R24/R25）/ One-shot cycle start |
| `afCurve` | `ARRAY[1..200] OF REAL` | IN | — | N·m | 扭矩采样曲线，0~50，有效点由 `nPoints` 指定 / Torque curve |
| `nPoints` | `INT` | IN | — | 个 | 有效点数，域 2~200；超上限判 02F3，不足置 01C5 不评级 / Valid sample count |
| `fSpeed` | `REAL` | IN | — | rpm | 拧紧转速，域 1~2000；采样间距 Δt = 60/fSpeed（偏离留档②） / Tightening speed |
| `fPeakMin` / `fPeakMax` | `REAL` | IN | — | N·m | 峰值合格下/上限，域 0~1E4 / Peak limits |
| `fSlopeMin` / `fSlopeMax` | `REAL` | IN | — | N·m/s | 上升斜率合格下/上限，域 −1E6~1E6 / Slope limits |
| `fSteadyTol` | `REAL` | IN | `5.0` | % | 稳态段相对峰值容差，域 0.1~100 / Steady band tolerance |
| `fSlipDropRatio` | `REAL` | IN | `0.20` | — | 滑牙判据：峰值后跌落比例，域 0.02~0.95 / Slip drop ratio |
| `fCrossRatio` | `REAL` | IN | `0.40` | — | 歪盖判据：上升段面积占比下限，域 0.05~0.95 / Cross-thread ratio |
| `fBatchP10` / `fBatchP90` | `REAL` | IN | `0.0` | N·m | 批次 P10/P90 基线，0 = 未下发（01C6 只走绝对阈值）/ Batch percentiles |
| `nBatchMin` | `INT` | IN | `30` | 件 | 分位可用所需最小样本，< 1 视为分位不可用 / Minimum batch size |
| `fPeak` / `fSlope` / `fSteadyMean` | `REAL` | OUT | — | N·m / N·m/s / N·m | 峰值 / 上升斜率 / 稳态均值（保持语义）/ Features, held |
| `eVerdict` | `E_DL_CapperVerdict` | OUT | — | — | `eOk(0)` / `eNgLow(10)` / `eNgHigh(20)` / `eNgSlip(30)` / `eNgCross(40)` / `eNgCurve(50)`（保持语义）/ Main verdict |
| `uNgMask` | `WORD` | OUT | — | — | NG 原因位图：bit0 低扭 / bit1 高扭 / bit2 滑牙 / bit3 歪盖 / bit4 曲线异常 / NG bitmap |
| `bVerdictValid` | `BOOL` | OUT | — | — | 判定有效，保持到下次 `bCycleStart`（R27）/ Verdict valid, held |
| `nTotal` / `nNg` | `UDINT` | OUT | — | 件 | 已判周期总数 / 不合格周期数 / Counters |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |

**状态机**（`E_DL_CapTrendState`）：`eIdle(0)` → `eSampling(10)`（点数连续两拍不变才就绪，偏离留档③）→ `eEvaluate(20)`（单拍特征提取与判定）→ `eVerdict(30)`（保持）→ `eFault(99)`。

### 25.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0005_01C5` | 点数不足未评级（**不等于不合格**）/ Insufficient points, no verdict | 否 | `bVerdictValid = FALSE`，`eVerdict` 保持上次值，不得强置 eNgCurve |
| `16#0005_01C6` | 批次分位未下发，仅用绝对阈值 / Baseline unavailable | 否 | 检查 `nBatchMin` 与 P10/P90 注入 |
| `16#0005_01C7` | 曲线噪声大（峰前差分变号 ≥ 3），斜率可信度低 / Noisy curve | 否 | 查上游滤波与采集节拍 |
| `16#0005_02F3` | 曲线点数超上限（> 200）/ Point count overflow | **是** | 检查 `nPoints` 来源；绝不越界读数组 |
| `16#0005_02F4` | 曲线含非有限值 / Non-finite sample | **是** | 查采集链路；需复位退出（v1.0.1 后正确进故障态） |
| `16#0005_02F5` | 非法状态兜底 / Illegal state | **是** | 复现后上报 |

### 25.3 调用示例 / Example

```iecst
PROGRAM PRG_CapperQC
VAR
    fbCap      : FB_DL_CapperTorqueTrend;   // 旋盖判定 / Capper verdict
    afTq       : ARRAY[1..200] OF REAL;     // 扭矩曲线 [N m] / Torque curve
    nPts       : INT;                       // 有效点数 / Point count
    fSpd       : REAL := 120.0;             // 转速 [rpm] / Speed
    bCapEn     : BOOL;                      // 使能 / Enable
    bNewBottle : BOOL;                      // 单瓶启动沿 / Cycle start
    bCapReset  : BOOL;                      // 复位 / Reset
    bCapOk     : BOOL;                      // 合格结论 / Verdict OK
    uReasons   : WORD;                      // NG 原因位图 / NG bitmap
END_VAR

fbCap(
    bEnable    := bCapEn,
    bReset     := bCapReset,
    bCycleStart:= bNewBottle,
    afCurve    := afTq,
    nPoints    := nPts,
    fSpeed     := fSpd,
    fPeakMin   := 8.0,
    fPeakMax   := 16.0,
    fSlopeMin  := 10.0,
    fSlopeMax  := 60.0);

// 结论是保持位不是脉冲：上位机迟几拍读仍有效（R27）
bCapOk  := fbCap.bVerdictValid AND (fbCap.eVerdict = E_DL_CapperVerdict.eOk);
uReasons := fbCap.uNgMask;      // 位图可多位并置（如滑牙+歪盖）
END_PROGRAM
```

### 25.4 要点 / Notes

- **v1.0.1 修复（状态机迁移违规格，D-C3-1）**：评估相检出非有限样本（02F4）后原先**无条件**转 `eVerdict`——规格要求「任何态--非有限--> eFault(99)」；实际停在判定相会让下一 `bCycleStart` 绕过复位直接开新周期，故障锁存语义失效。修复后按 `_bFaultCond` 分流转 `eFault` 等复位。
- **滑牙判据**：峰值后短窗内跌落超 `fSlipDropRatio`（如峰值 12 → 6，跌落 50% > 20%）；位图允许滑牙与歪盖并置。
- **无结论 ≠ 不合格**：`nPoints = 0` 时 `bVerdictValid = FALSE` 且 `eVerdict` 保持上次值——把「没测到」强判「曲线异常」会把整批好盖误杀。
- **曲线就绪 = 点数连续两拍不变**：不用显式握手引脚，以稳定性判据代替，避免读到半写入的曲线（偏离留档③，终审采纳）。

---

## 26. FB_DL_EscHeLeakCheck ｜ 静电吸盘氦背冷泄漏率判定（R13，v1.0.1）

**定位**：静电吸盘（ESC）氦背冷回路的**三段式**泄漏率判定——升压段（斜率监视 + 达压确认）→ 稳压段（窗内极差稳定判据，可延长一次）→ 测量段（压降率 → 漏率换算 + 温漂修正）→ OK / Warn / NG 三级判定。

**与 `FB_DL_LeakTestStation` 的分工（禁止合并）**：后者是通用压降法工站（充气-稳压-保压-压降换算-排气，面向工件腔体，压力区间宽、带排气相与夹具确认）；本件是 ESC 专用——氦侧压力区间窄（1~100 kPa）、必须做温漂修正、判定带 Warn 三级、且单独识别「氦源串漏方向」（测量段压力上升 = 阀未关或源侧串漏）。合并会把两套压力量纲与判定门限塞进一个方式参数——历史库反复交学费的老毛病（一套 MODE 管两种物理过程）。

### 26.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能，FALSE 中止当前检测并回空闲（eResult = eAborted，bDone 保持）/ Enable, FALSE aborts |
| `bReset` | `BOOL` | IN | — | — | 复位：清故障、结果与保持量 / Rising edge reset |
| `bStart` | `BOOL` | IN | — | — | 启动一次检测，上升沿受理（R24）/ One-shot start |
| `fHePressure` | `REAL` | IN | — | kPa | 氦侧压力，域 0~500（每拍锁存快照，R38）/ Helium pressure |
| `fHeFlow` | `REAL` | IN | — | sccm | 氦侧流量，域 0~5000，用于与漏率交叉校验 / Helium flow |
| `fChuckTemp` | `REAL` | IN | — | ℃ | 卡盘温度，域 0~200，温漂修正用 / Chuck temperature |
| `tPressurizeMax` | `TIME` | IN | `T#20S` | — | 升压段超时 / Pressurise timeout |
| `tStabilize` | `TIME` | IN | `T#10S` | — | 稳压段时长 / Stabilisation time |
| `tMeasure` | `TIME` | IN | `T#30S` | — | 测量段时长 / Measurement time |
| `fPressTarget` | `REAL` | IN | `15.0` | kPa | 目标背压，域 1~100 / Target back pressure |
| `fPressTol` | `REAL` | IN | `0.5` | kPa | 达压容差，域 0.01~50 / Pressure tolerance |
| `fLeakWarn` | `REAL` | IN | `3.0` | sccm | 漏率 Warn 阈，域 0~1E4 / Warn limit |
| `fLeakNg` | `REAL` | IN | `5.0` | sccm | 漏率 NG 队，域 0~1E4 且 ≥ Warn / Reject limit |
| `fPressRiseMax` | `REAL` | IN | `2.0` | kPa/s | 升压速率基准——**不做拦截阈值**（氦侧有机械减压阀，超压风险不成立），当供气健康基准用：速率持续 ≥ 1 s 低于其 2% 且远未达压时判供气异常 02F6（偏离留档②）/ Rate reference, not an interceptor |
| `fTempCoeff` | `REAL` | IN | `0.003` | 1/K | 压力温漂修正系数，域 −0.05~0.05 / Temperature coefficient |
| `fStabTol` | `REAL` | IN | `0.2` | kPa | 稳压判据：窗内极差上限，域 0.001~50 / Stabilisation tolerance |
| `fLeakRate` | `REAL` | OUT | — | sccm | 换算漏率（温漂修正后，夹 ≥ 0）/ Corrected leak rate |
| `fPressDecay` | `REAL` | OUT | — | kPa/s | 测量段压降率（有符号，夹域）/ Pressure decay rate |
| `eResult` | `E_DL_LeakResult` | OUT | — | — | `eOk(0)` / `eWarn(10)` / `eNg(20)` / `eAborted(30)`（保持语义）/ Result, held |
| `bDone` / `bPass` | `BOOL` | OUT | — | — | 检测完成 / 合格（保持语义，新启动沿与复位沿清除）/ Done and pass, held |
| `nTestCount` / `nNgCount` | `UDINT` | OUT | — | 次 | 检测次数 / 不合格次数 / Counters |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |

**状态机**（`E_DL_EscLeakPhase`）：`eIdle(0)` → `ePressurize(10)` → `eStabilize(20)`（可延长一次）→ `eMeasure(30)` → `eVerdict(40)`（结算一次后回空闲）→ `eFault(99)`；三段各一个 TON，**每段切换断输入一拍**（R40 核心纪律）。

### 26.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0005_01C8` | 稳压未达判据已延长一次 / Stabilisation extended once | 否 | 延长后仍不稳则进测量但 eOk 降为 eWarn（不确定性上升，偏离留档④） |
| `16#0005_01C9` | 温漂修正已启用（温差 ≥ 1 K）/ Correction active | 否 | 提示修正参与了结算 |
| `16#0005_01CA` | 漏率落在 Warn 带 / Inside warn band | 否 | 排查计划；复测确认 |
| `16#0005_02F6` | 升压超时或供气异常 / Pressurisation failed | **是** | 查氦源、减压阀与管路 |
| `16#0005_02F7` | 测量段压力上升（源侧串漏或阀未关）/ Pressure rising in measure | **是** | 查隔离阀密封与气路 |
| `16#0005_02F8` | 非有限输入或非法状态兜底 / Non-finite input | **是** | 查传感器；需复位退出；漏率保持上次值绝不写 NaN |

### 26.3 调用示例 / Example

```iecst
PROGRAM PRG_EscLeak
VAR
    fbEscLeak : FB_DL_EscHeLeakCheck;   // ESC 检漏 / ESC leak check
    bEscEn    : BOOL;                   // 使能 / Enable
    bEscStart : BOOL;                   // 启动沿 / Start edge
    bEscReset : BOOL;                   // 复位 / Reset
    fPHe      : REAL;                   // 氦压 [kPa] / Helium pressure
    fQHe      : REAL;                   // 氦流 [sccm] / Helium flow
    fTChk     : REAL;                   // 卡盘温度 [degC] / Chuck temp
    fLeak     : REAL;                   // 漏率 [sccm] / Leak rate
    bEscPass  : BOOL;                   // 合格 / Pass
END_VAR

fbEscLeak(
    bEnable      := bEscEn,
    bReset       := bEscReset,
    bStart       := bEscStart,
    fHePressure  := fPHe,
    fHeFlow      := fQHe,
    fChuckTemp   := fTChk,
    fPressTarget := 15.0,
    fLeakWarn    := 3.0,
    fLeakNg      := 5.0);

fLeak    := fbEscLeak.fLeakRate;
bEscPass := fbEscLeak.bDone AND fbEscLeak.bPass;   // 保持语义 / held
END_PROGRAM
```

### 26.4 要点 / Notes

- **v1.0.1 修复（中高·功能失效，D-C4-1）**：稳压延长窗裁决条件原为 `_fbTonStab.Q OR _fbTonStabExt.Q`——延长置位后主稳压定时器 IN 未断、Q 保持 TRUE，**下一拍**即被提前判「延长后仍不稳」进测量；`_fbTonStabExt` 全程未计时，01C8「已延长一次」名存实亡，测量起点压力取在延长窗开始而非结束时刻，弱稳定降级也提前触发。修复后以 `_bStabExtended` 区分两窗：延长窗内仅由 `_fbTonStabExt.Q` 裁决，主稳压定时器不再参与；收敛路径显式清 `_bStabWeak`。
- **V3 用向量区分实现**：升压 10 s + 稳压 10 s + 测量 30 s，三段各用一个 TON 且每段切换断输入一拍——若误写三段共用一个 TON 且 IN 跨段恒真，50 s 时测量段会被提前判超时。
- **漏率换算系数 1500 sccm/(kPa/s) 是标定常量**：由背冷腔容积与标定工装决定，调用方按腔体台账整定（值误差只影响绝对量程，不影响 OK/Warn/NG 判定结构）。
- **中止恢复**（R41）：测量段掉使能 → `eAborted` + `bDone` 保持；重新 `bStart` 后三段计时从 0 开始（断输入拍保证 ET 清零）。
- **稳压延长仅一次**：延长后仍不稳则进测量但 `eOk` 降为 `eWarn`——绝不因稳定判据未过而丢弃整次检测。

---

## 27. FB_DL_ChamberSeasoningTrack ｜ 腔体 seasoning 台账与放行判定（R13，v1.0.0）

**定位**：seasoning（腔体调机）片数 + 膜厚台账 + 放行判定。每片完成后累计片数、累计工艺时长、膜厚均值与趋势；**双判据（片数达标 ∧ 时长达标）**才放行；连续越窗自动降级 `eNotReady`；配方名只作标签与校验键。

**边界**：① **不做配方存储**——`sRecipeName` 只作标签与校验键，配方本体归 `FB_DL_RecipeManager`；② **不做膜厚测量**——膜厚与均匀性由量测机台引脚注入；③ 不做 SPC 判异（只做越窗计数与连续计数）；④ 不做 MES 上报。

### 27.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` / `bReset` | `BOOL` | IN | — | — | 使能 / 复位（上升沿清台账并**重开新一轮**：nCount=0、tAccum=0、nRoundId+1）/ Enable and reset |
| `bWaferDone` | `BOOL` | IN | — | — | 单片完成，上升沿受理（R24）/ One-shot wafer done |
| `fThickness` | `REAL` | IN | — | nm | 本片膜厚，域 0~10000（不可信时不入账）/ Wafer thickness |
| `fUniformity` | `REAL` | IN | — | % | 本片均匀性，域 0~100 / Uniformity |
| `sRecipeName` | `STRING(80)` | IN | — | — | 配方名标签，非空必填；超 32 字符显式截断并置 01CE（R37，偏离留档①）/ Recipe tag, truncated explicitly |
| `fThickTarget` | `REAL` | IN | — | nm | 膜厚目标，域 > 0 / Thickness target |
| `fThickTol` | `REAL` | IN | `5.0` | % | 膜厚相对容差，域 0.5~50 / Thickness tolerance |
| `fUnifLimit` | `REAL` | IN | `3.0` | % | 均匀性上限，域 0.1~20 / Uniformity limit |
| `nCountTarget` | `INT` | IN | `25` | 片 | 片数目标，域 1~10000 / Wafer count target |
| `tTimeTarget` | `TIME` | IN | `T#10H` | — | 工艺时长目标，域 1 min~1000 h / Process time target |
| `nConsecNgLimit` | `INT` | IN | `2` | 片 | 连续越窗降级阈值，域 1~10 / Consecutive limit |
| `tProcessTime` | `TIME` | IN | — | — | 本片工艺耗时（上层注入）——**台账用引脚累加不用墙钟**：一台上位机可能同时跟踪多条腔体，墙钟会把等待/待机算进 seasoning 时长（偏离留档②）/ Process time injected by the caller |
| `nCount` / `nNgCount` | `INT` | OUT | — | 片 | 已 seasoning 片数 / 越窗片数（逐拍重写）/ Counts |
| `tAccum` | `TIME` | OUT | — | — | 累计工艺时长（逐片累加）/ Accumulated time |
| `fThickAvg` / `fThickSlope` | `REAL` | OUT | — | nm / nm/片 | 膜厚均值 / 趋势（首末差 ÷ 片数差）/ Mean and trend |
| `bRelease` | `BOOL` | OUT | — | — | 放行（保持语义）；**安全侧**：配方键缺失或台账故障时强制 FALSE / Release, held, fail-safe |
| `eQualify` | `E_DL_SeasonState` | OUT | — | — | `eIdle(0)` / `eTracking(10)` / `eQualified(20)` / `eNotReady(30)` / `eFault(99)` / State |
| `nRoundId` | `UINT` | OUT | — | — | 本轮编号，复位递增（供 MES 对齐）/ Round id |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |

### 27.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0005_01CB` | 单片越窗但未连续 / Single out-of-window | 否 | 关注；连续计数 +1 |
| `16#0005_01CC` | 连续越窗达阈值降级 eNotReady / Consecutive limit reached | 否 | 膜质未稳，继续 seasoning |
| `16#0005_01CD` | 片数达标但时长未达标 / Count met, time pending | 否 | 双判据未齐，继续投片 |
| `16#0005_01CE` | 配方名超 32 字符已显式截断 / Tag truncated explicitly | 否 | 登记缓冲仍为 32 字符；建议缩短命名 |
| `16#0005_02F9` | 配方名为空或膜厚目标非正 / Missing key or target | **是** | **bRelease 强制 FALSE**（台账不可信不得放行）；需复位退出 |
| `16#0005_02FA` | 片数/时长台账溢出（30000 片 / 40 天）或量测值非有限/越域 / Overflow or bad measurement | **是** | 本片不入账、不放行；查量测链路与台账轮换 |
| `16#0005_02FB` | 非法状态兜底 / Illegal state | **是** | 复现后上报 |

### 27.3 调用示例 / Example

```iecst
PROGRAM PRG_SeasonLedger
VAR
    fbSeason  : FB_DL_ChamberSeasoningTrack;   // 台账 / Ledger
    bChEn     : BOOL;                          // 使能 / Enable
    bWaferEnd : BOOL;                          // 单片完成沿 / Wafer done edge
    bChReset  : BOOL;                          // 复位 / Reset
    fThkMeas  : REAL;                          // 膜厚 [nm] / Thickness
    fUnifMeas : REAL;                          // 均匀性 [%] / Uniformity
    tStepTime : TIME;                          // 本片耗时 / Step time
    bCanRun   : BOOL;                          // 放行 / Release
END_VAR

fbSeason(
    bEnable       := bChEn,
    bReset        := bChReset,
    bWaferDone    := bWaferEnd,
    fThickness    := fThkMeas,
    fUniformity   := fUnifMeas,
    sRecipeName   := 'OXI-PROC-A',
    fThickTarget  := 100.0,
    tTimeTarget   := T#10H,
    nCountTarget  := 25,
    tProcessTime  := tStepTime);

bCanRun := fbSeason.bRelease;   // 双判据达标才 TRUE / both criteria met
END_PROGRAM
```

### 27.4 要点 / Notes

- **双判据是「且」不是「或」**：25 片但每片 10 min（总 4.17 h < 10 h 目标）不放行，置 01CD 继续投片——片数凑够不等于膜质稳定。
- **越窗判据取并集**：膜厚相对偏差 > `fThickTol` **或** 均匀性 > `fUnifLimit` 都算越窗——只盯膜厚会漏掉「厚度对但均匀性崩」的片子（偏离留档③）。
- **复位即新一轮**：`bReset` 后 nCount = 0、tAccum = T#0S、nRoundId + 1，**不保留上一轮的趋势基准**（R41：恢复不重头）。
- **量测值不可信并入 02FA**：与本片不入账绑定——「台账数据源坏了」与「计数溢出」同属「台账不可继续累加」的语义（偏离留档④）。

---

## 28. FB_DL_ReactorJacketDeltaT ｜ 釜温-夹套温差约束与冷热分程（R13，v1.0.0）

**定位**：放热反应的釜温-夹套温差抑制——以 ΔT = 釜温 − 夹套温 为约束量，对升温侧做**温差上限约束**与**温差变化率约束**，并把上层 PID 输出分程为冷/热两路阀位给定；超温强制冷却带回差；分程带死区防冷热同开。

**边界纪律**：① **不内联 PID**——温度闭环由 `FB_DL_CascadePid` 承担，PID 输出以 `fPidOut` 引脚注入；② 不新增轴/相状态枚举——`E_DL_JacketState` 只描述「冷热分程的当前执行方向」，不是批次相状态（相状态归 `FB_DL_BatchPhaseBase`）；③ 两路输出**互斥**（状态机与目标量赋值保证）+ `fDeadband` 死区，禁止冷热同开；④ 限速能力**组合调用** `FB_DL_RateLimiter`（DL_Algo），绝不内联限速算法。

### 28.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` / `bReset` | `BOOL` | IN | — | — | 使能（FALSE 两路归零回空闲）/ 复位（上升沿） / Enable and reset |
| `fReactorTemp` / `fJacketTemp` | `REAL` | IN | — | ℃ | 釜温 / 夹套温，域 −50~400 / Temperatures |
| `fPidOut` | `REAL` | IN | — | % | 上层 PID 输出，域 −100~100；**须已过跟踪首拍**（R36，见 28.4）/ PID output |
| `fDeltaTMax` | `REAL` | IN | `30.0` | K | 允许最大温差，域 5~150；达上限带 0.5 K 回差锁存、升温侧冻结 / Max allowed delta-T |
| `fDeltaTRate` | `REAL` | IN | `5.0` | K/min | 温差变化率上限，域 0.1~50（超阈只报警不拦截）/ Delta-T rate limit |
| `fOverTempMargin` | `REAL` | IN | `5.0` | K | 超温强制冷却裕量，域 0.5~50 / Over-temperature margin |
| `fTempSetpoint` | `REAL` | IN | — | ℃ | 釜温设定，超温判据用 / Reactor setpoint |
| `tRateWindow` | `TIME` | IN | `T#1M` | — | 变化率统计窗，域 5 s~10 min / Rate window |
| `fDeadband` | `REAL` | IN | `2.0` | % | 冷热分程死区，域 0~10 / Split-range deadband |
| `fOutMin` / `fOutMax` | `REAL` | IN | `0.0` / `100.0` | % | 输出下/上限 / Output limits |
| `tCycle` | `TIME` | IN | `T#10MS` | ms | 任务扫描周期——限速步长折算基准（增补引脚，偏离留档①）/ Task cycle time |
| `fHeatOut` / `fCoolOut` | `REAL` | OUT | — | % | 热路 / 冷路阀位给定（0~100，保持语义，**互斥**）/ Valve commands, held, mutually exclusive |
| `fDeltaT` | `REAL` | OUT | — | K | 实测温差（有符号 = 釜温 − 夹套温）/ Measured delta-T |
| `fDeltaTRateMeas` | `REAL` | OUT | — | K/min | 实测温差变化率（窗内斜率）/ Measured rate |
| `bDeltaTLimited` | `BOOL` | OUT | — | — | 温差达上限、升温侧被限（保持语义）/ Limiting active |
| `bOverTemp` | `BOOL` | OUT | — | — | 釜温超设定加裕量（保持语义）/ Over temperature |
| `eVerdict` | `E_DL_JacketState` | OUT | — | — | `eIdle(0)` / `eHeat(10)` / `eCool(20)` / `eHold(30)` / `eFault(99)` / Actuation direction |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |

### 28.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0005_01CF` | 温差达上限升温侧冻结 / Delta-T limit reached | 否 | 热路按 `fDeltaTRate` 折算速率斜坡回 0（限速非限幅）；回差 0.5 K 防边界抖动 |
| `16#0005_01D0` | 釜温超设定加裕量强制冷却 / Over temperature | 否 | 强制冷却态 + 回差 |
| `16#0005_01D1` | 分程重叠区被死区分离 / Overlap separated | 否 | 两路均 0（eHold）；离开死区时提示 |
| `16#0005_02FC` | 温度或 PID 输出非有限 / Non-finite input | **是** | 快照置零 + 故障锁存；坏值不进控制律、不达联锁出口 |
| `16#0005_02FD` | 温差为负且要求升温（**传感器反装**）/ Reversed sensor | **是** | 本件最有价值的判据：反装的热电偶会被这条抓住 |
| `16#0005_02FE` | 非法状态兜底 / Illegal state | **是** | 复现后上报 |

### 28.3 调用示例 / Example

```iecst
PROGRAM PRG_JacketLimit
VAR
    fbJacket  : FB_DL_ReactorJacketDeltaT;   // 温差约束 / Jacket constraint
    fbTempPid : FB_DL_CascadePid;            // 温度闭环（上层）/ Temperature loop
    fTrxTemp  : REAL;                        // 釜温 [degC] / Reactor temp
    fJktTemp  : REAL;                        // 夹套温 [degC] / Jacket temp
    bRxEn     : BOOL;                        // 使能 / Enable
    bRxReset  : BOOL;                        // 复位 / Reset
    fHeatCmd  : REAL;                        // 热路阀位 [%] / Heat command
    fCoolCmd  : REAL;                        // 冷路阀位 [%] / Cool command
END_VAR

fbJacket(
    bEnable       := bRxEn,
    bReset        := bRxReset,
    fReactorTemp  := fTrxTemp,
    fJacketTemp   := fJktTemp,
    fPidOut       := fbTempPid.fOut,     // 须已过无扰切换首拍 / after bumpless transfer
    fDeltaTMax    := 30.0,
    fDeltaTRate   := 5.0,
    fTempSetpoint := 85.0,
    tCycle        := T#10MS);

fHeatCmd := fbJacket.fHeatOut;
fCoolCmd := fbJacket.fCoolOut;    // 两路互斥 + 死区，不会同开 / exclusive
END_PROGRAM
```

### 28.4 要点 / Notes

- **R36 跟踪首拍（调用方责任，手算示例已写进头注释）**：上层 PID 从手动跟踪切自动时，若未做无扰切换，首拍 `fPidOut` 可能从 fTrack 跳到 fP+fI+fD（示例：跳变 42%）。本件对该阶跃**不做补偿**（补偿属 PID 无扰切换职责），只保证首拍大跳不会误报 01CF——01CF 判据绑定实测温差而非指令跳变。
- **常态直通 / 受限限速双工况（偏离留档②）**：未触限时不限速直接跟随（V1）；温差触限、超温强制冷却及恢复全程走 `FB_DL_RateLimiter` 限速路径（限速**非限幅**），用 `bTrack` 引脚完成无扰切换、退出跟踪从当前值起限速不回跳。
- **速率折算披露（偏离留档③）**：以常量 `DL_JKT_K_PER_PCT`（0.5 K/%，工艺整定值）把 K/min 折算为 %/s，折算关系在头注释显式披露，不做隐藏假设。
- **传感器反装判据**：釜 80 ℃、夹套 95 ℃且要求升温（ΔT = −15）→ 02FD 锁存——放热反应里这条能第一时间抓住装反的热电偶。
- **码位修正（偏离留档④）**：规格 V2 正文写 01CE，但码位表定为 01CF 且 01CE 已被 C5（配方名截断）占用——按**码位表**执行，避免跨件撞号。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_ChangeoverSequence` | 五步可确认换产顺控，每步独立超时、步内重装 | `bStart` / `tStepTimeout` / `bReadyForProduction` |
| `FB_DL_DowntimeClassifier` | 停转时抓首个动作的原因源，输出停机原因序号与时长 | `bEnable` / `uReasonNo` / `tDuration` |

> 用法要点：`ChangeoverSequence` 超时只置信息码并记录阻塞步号（人等确认是正常生产行为），绝不自动跳步；`bReadyForProduction` 在失能当拍清零（安全侧，v1.0.1 修复项）。


---

---

## R19 批次补录接口表（2026-11-16，本子库 2 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录。两件均只消费外部给定、输出给定值与判据标志，不内联闭环算法（PID 输出一律引脚注入，R19 同族纪律）。

### `FB_DL_DrumLevelThreeElem`
- **功能**：锅炉汽包三冲量给水：水位偏差（正作用）− 蒸汽流量前馈 + 给水流量反馈，三路增益分别可调，输出经上下限钳位；水位高 / 低触限锁存并置联锁跳闸出口。
- **输入引脚**：`bEnable`、`bReset`、`fLevel`、`fLevelSp`、`fSteamFlow`、`fFeedFlow`、`fLevelGain`、`fSteamGain`、`fFeedGain`、`fLevelLow`、`fLevelHigh`、`fOutMin`、`fOutMax`
- **输出引脚**：`fFeedSp`、`bLevelLow`、`bLevelHigh`、`bInterlockTrip`、`bLimited`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0005_01D6` / `01D7` ｜ 故障 `16#0005_0305`~`0307`
- **用法要点**：v1.0.1 已修水位项符号构成正反馈的缺陷（R19 终审）——**升级前版本不得用于真实汽包**；量程单位由组态注释约定（mm 或 %），三路增益量纲不同，禁止互相借用数值。

### `FB_DL_VacCupRingCtrl`
- **功能**：真空吸盘环（多吸盘）取放控制：逐只真空确认（`auVacuumOk` + `afVacuum` 阈值 `fVacMin`，确认时长 `tConfirmTime`），最小吸盘数 `uMinCupsRequired` 判成功；`bAllowDegrade` 决定少吸时降级放行还是判 `bPickFailed`；释放可配置外圈优先（`bReleaseOuterFirst`）逐只泄真空。
- **输入引脚**：`bEnable`、`bReset`、`bCmdPick`、`bCmdRelease`、`auVacuumOk[0..7]`、`afVacuum[0..7]`、`uCupCount`、`uMinCupsRequired`、`fVacMin`、`tConfirmTime`、`bAllowDegrade`、`bReleaseOuterFirst`
- **输出引脚**：`auValveOut[0..7]`、`bPicked`、`bReleased`、`uOkCups`、`bDegraded`、`bPickFailed`、`uPickCount`、`eErr`、`bError`
- **码位**：信息 `16#0005_01D8` / `01D9` ｜ 故障 `16#0005_0308`~`030A`
- **用法要点**：`auValveOut` 只是阀指令，物理点由上层映射；膜片老化表现为「确认时长变长」而非「真空值突变」，`tConfirmTime` 按新膜片实测值的 1.5 倍设。

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Process` 余下 R1~R18 历史件（约 28 件）接口表**下轮续补**。
---

## R22 批次接口表（R22 追加 · 4 件）

### FB_DL_CompressorSurgeGuard ｜ 压缩机防喘振（DL_Process / ProcessSafety）
- **输入引脚**：`fSuctionPress`/`fDischargePress`（kPa abs）、`fFlow`（Nm3/h）、`fFlowMinLine`（Nm3/h 缺省 500.0）、`fSurgeMargin`（倍 缺省 0.10）、`fOpenRamp`（%/s 缺省 20.0）、`fCloseRamp`（%/s 缺省 1.0）、`tConfirm`（缺省 T#200MS）、`tSample`（缺省 T#100MS）、`bEnable`
- **输出引脚**：`fBlowoffValve`（% 0~100）、`bSurgeRisk`、`bBlowoffActive`、`fPressureRatio`（倍）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DA`（低于危险线已开放空阀）/ `01DB`（出回差带退出放空）｜ 故障 `030B`（参数非法阀全开）/ `030C`（非有限保持末值）/ `030D`（兜底）
- **要点**：两条相反安全方向并列——参数非法阀全开、坏值保持末值；R41 回差退出，eRiskBlowoff 不得被 eNormal 直接抢占。

### FB_DL_ColumnDpCtrl ｜ 精馏塔压差控制（DL_Process / ProcessControl）
- **输入引脚**：`fDpMeas`（kPa）、`fDpSp`（缺省 5.0）、`fDpDeadband`（缺省 0.2）、`fOutMin`/`fOutMax`（%）、`fDpHighLimit`（缺省 8.0）、`fStep`（% 缺省 1.0）、`tConfirm`、`bEnable`
- **输出引脚**：`fRefluxOut`（%）、`fReboilOut`（%）、`bDpHigh`、`bLimited`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DC`（死区内不调节 或 已退出防冲塔，复用）/ `01DD`（ΔP 越上限已按防冲塔分配）｜ 故障 `030E`（参数非法双输出置 fOutMin）/ `030F`（非有限保持末值）/ `0310`（兜底）

### FB_DL_InertPurgeSeq ｜ 氮气置换顺控（DL_Process / Sequence）
- **输入引脚**：`bStart`、`bAbort`、`fO2Meas`（%）、`bO2SensorOk`、`fO2Target`（% 缺省 2.0）、`uMaxCycles`（次 缺省 3）、`tEvac`/`tFill`/`tHold`（缺省 60/60/30 s）、`fVacOk`（kPa g 缺省 -80.0）、`fVacMeas`（kPa g，抽真空读数由调用方注入）
- **输出引脚**：`bVacValveCmd`、`bN2ValveCmd`、`bVentValveCmd`（三相阀互斥先清后置）、`uCycleDone`（次）、`bDone`、`bFailed`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01DE`（单循环未达标进下一循环）/ `01DF`（氧含量达标）｜ 故障 `0311`（参数非法）/ `0312`（分析仪无效禁止放行）/ `0313`（循环耗尽，含兜底复用）

### FB_DL_BatchTransferSeq ｜ 批次物料转移顺控（DL_Process / Sequence）
- **输入引脚**：`bStart`、`bAbort`、`bSrcValveFb`、`bDstValveFb`、`fTransferred`（m3，调用方积分器注入）、`fVolumeTarget`（m3 缺省 5.0）、`fFlow`（m3/h）、`fDrainFlow`（m3/h 缺省 0.05）、`tDrainVerify`（缺省 T#10S）、`tValveFb`（缺省 T#5S）、`tTimeout`（缺省 T#30M）
- **输出引脚**：`bPumpCmd`、`bSrcValveCmd`、`bDstValveCmd`、`bDrained`、`bDone`、`bFailed`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0005_01E0`（累计量外部注入口径声明）/ `01E1`（排空验证完成）｜ 故障 `0314`（阀位反馈超时不启泵）/ `0315`（超时或参数非法）/ `0316`（兜底）
- **要点（v1.0.1）**：0315 超时分支补置 bError；泵必须在双阀到位后启；bAbort 先停泵后关阀（物理时序分隔 R23 立项，见 ROADMAP §24.1）。

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Process` 余下 R1~R21 历史件（约 28 件）接口表继续按「每轮 ≤10 件」补录。


*Last updated: 2026-11-16（R22 追加接口表 4 件）｜ 道莅工控代码库产品总监*

---

## R23 批次接口表（R23 追加 · 7 件 · 行业工艺站（锂电/光伏/公用工程/锅炉/暖通，ROADMAP P1） ｜ 子库 v0.12.0→v0.13.0）

### FB_DL_ElectrolyteDosingSeq ｜ 电解液定量注液 ISA-88 节拍链（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bStart` | IN | `BOOL` | 启动请求 [—]，上升沿生效 |
| `bAbort` | IN | `BOOL` | 中止请求 [—]，任意拍生效 |
| `bReset` | IN | `BOOL` | 故障复位 [—]，上升沿清秤异常锁存 |
| `fTargetMassG` | IN | `LREAL` | 目标注液量 [克]，须 > 0 |
| `fCoarseFineKg` | IN | `LREAL := 0.95` | 粗 |
| `fScaleMassG` | IN | `LREAL` | 电子秤实时读数 [克]，注液目标侧质量 |
| `tSettleTime` | IN | `TIME  := T#2S` | 静置浸润计时 [ms]，兼作称重稳定窗 |
| `xCoastAbort` | IN | `BOOL  := TRUE` | TRUE = 中止走惰转两段化（推荐） |
| `tCoastTime` | IN | `TIME  := T#2S` | 泵惰转时间 [ms]：断使能到关阀的物理时序分隔窗 |
| `ePhase` | OUT | `E_DL_ElyteDosingPhase` | 注液相位 [—] |
| `fDosedMassG` | OUT | `LREAL` | 已注量 [克] = 读数 − 基线 |
| `bDosingOut` | OUT | `BOOL` | 注液阀输出 [—] |
| `bPumpOut` | OUT | `BOOL` | 泵输出 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_NailMachineSeq ｜ 打钉机送钉-打钉顺控站（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bStart` | IN | `BOOL` | 启动请求 [—]，上升沿生效 |
| `bStop` | IN | `BOOL` | 停止请求 [—]，电平有效，立即断裁切输出 |
| `bUnwinderReady` | IN | `BOOL` | 放卷就绪反馈 [—] |
| `bCutterHome` | IN | `BOOL` | 裁切原点反馈 [—] |
| `bCollectorReady` | IN | `BOOL` | 收料就绪反馈 [—] |
| `bCutDone` | IN | `BOOL` | 切完反馈 [—]，每片一拍 |
| `uBatchCount` | IN | `UDINT` | 批量目标 [片]，0 = 连续模式 |
| `tCutCycleMax` | IN | `TIME := T#3S` | 单拍节拍上限 [ms]，须 > 0 |
| `bReset` | IN | `BOOL` | 故障复位 [—]，上升沿退出 eFault |
| `eSeqState` | OUT | `E_DL_NailSeqState` | 顺控相位 [—] |
| `uCutDone` | OUT | `UDINT` | 已切计数 [片]，饱和不回绕 |
| `uNotReadyMask` | OUT | `UINT` | 就绪诊断掩码 [位]，位0放卷 |
| `bUnwindRun` | OUT | `BOOL` | 放卷运行输出 [—] |
| `bCutTrig` | OUT | `BOOL` | 裁切触发输出 [—] |
| `bCollectRun` | OUT | `BOOL` | 收料运行输出 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_LamHeaterZoneSync ｜ 层压机加热板多温区同步跟随（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `aZoneTempC` | IN | `ARRAY[1..8] OF LREAL` | 各温区实测 [摄氏度]，下标 1..8，超编路填 0 且不计 |
| `uZoneCount` | IN | `UINT` | 实际温区数 [区]，有效域 0..8，> 8 钳位 |
| `fZoneDiffMaxK` | IN | `LREAL := 5.0` | 区差阈值 [K]，须 > 0 |
| `fBeltSpeedMmS` | IN | `LREAL` | 链速 [毫米 |
| `bEnable` | IN | `BOOL` | 使能 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—]，清除确认窗 |
| `fMaxZoneDiffK` | OUT | `LREAL` | 当拍最大区差 [K] |
| `bSyncOk` | OUT | `BOOL` | 同步正常 [—] |
| `uWorstPairA` | OUT | `UINT` | 最大温差对 A 区下标 [区] |
| `uWorstPairB` | OUT | `UINT` | 最大温差对 B 区下标 [区] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_SteamCondensatePot ｜ 凝液罐液位-排放顺控（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fLevelPct` | IN | `LREAL` | 液位实测 [百分数]，有效域 0..100，域外钳位 |
| `fPumpLevelHiPct` | IN | `LREAL := 80.0` | 排放启位液位 [百分数] |
| `fPumpLevelLoPct` | IN | `LREAL := 30.0` | 排放停位液位 [百分数]，须 < 启位 |
| `bDrainValveFb` | IN | `BOOL` | 排水阀开反馈 [—] |
| `tDrainMax` | IN | `TIME  := T#30S` | 单次排放上限 [ms] |
| `bEnable` | IN | `BOOL` | 使能 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—]，清除超时态 |
| `bDrainOut` | OUT | `BOOL` | 排水阀输出 [—] |
| `ePotState` | OUT | `E_DL_CondPotState` | 排放相位 [—] |
| `uDrainCount` | OUT | `UDINT` | 排放计数 [次]，饱和不回绕 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_AirCompDutyN2 ｜ 空压机/制氮机组联产轮值（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fN2DemandNm3H` | IN | `LREAL` | 制氮需求 [标立方米 |
| `aN2SupplyNm3H` | IN | `ARRAY[1..4] OF LREAL` | 各机组能力 [标立方米 |
| `abUnitReady` | IN | `ARRAY[1..4] OF BOOL` | 各机组就绪 [—] |
| `abUnitRunFb` | IN | `ARRAY[1..4] OF BOOL` | 各机组运行反馈 [—] |
| `tStartFbDelay` | IN | `TIME := T#10S` | 启动反馈确认延时 [ms] |
| `bEnable` | IN | `BOOL` | 调度使能 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—]，清除剔除锁存 |
| `abUnitCmd` | OUT | `ARRAY[1..4] OF BOOL` | 各机组投运指令 [—] |
| `uUnitsNeeded` | OUT | `UINT` | 需投台数 [台] |
| `fSupplyMarginNm3H` | OUT | `LREAL` | 供 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_BoilerThreeElement ｜ 锅炉三冲量给水控制（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fDrumLevelPct` | IN | `LREAL` | 汽包水位实测 [百分数] |
| `fSteamFlowTh` | IN | `LREAL` | 蒸汽流量 [吨 |
| `fFeedFlowTh` | IN | `LREAL` | 给水流量 [吨 |
| `fLevelSpPct` | IN | `LREAL := 50.0` | 水位设定 [百分数] |
| `fFwdGainSteam` | IN | `LREAL := 1.0` | 蒸汽前馈增益 [（吨 |
| `fLevelKp` | IN | `LREAL := 2.0` | 水位主回比例增益 [1] |
| `tLevelTi` | IN | `TIME  := T#30S` | 水位主回积分时间 [s]，T#0S = 纯 PD |
| `tLevelTd` | IN | `TIME  := T#0S` | 水位主回微分时间 [s]，T#0S = 关闭 |
| `bAutoMode` | IN | `BOOL` | 自动模式请求 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—] |
| `fFeedSpTh` | OUT | `LREAL` | 给水流量给定 [吨 |
| `bAuto` | OUT | `BOOL` | 实际自动态 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_HumidityOverride ｜ 除湿优先模式仲裁（DL_Process ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fRhPct` | IN | `LREAL` | 实测湿度 [百分数RH] |
| `fRhOverridePct` | IN | `LREAL := 70.0` | 覆盖触发阈值 [百分数RH] |
| `fRhReleasePct` | IN | `LREAL := 60.0` | 释放阈值 [百分数RH]，须 < 触发阈值 |
| `bTempCtrlActive` | IN | `BOOL` | 温控在投 [—]（诊断参考，不参与仲裁） |
| `tConfirmDelay` | IN | `TIME  := T#30S` | 触发 |
| `bReset` | IN | `BOOL` | 故障复位 [—] |
| `bOverrideActive` | OUT | `BOOL` | 除湿优先生效 [—] |
| `eOverrideState` | OUT | `E_DL_HumOverrideState` | 仲裁相位 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### 续补说明 / Remaining（R23 更新）

> 本节为 R23 新增件接口表（引脚取自 .st 声明区实测抽取，脚本 pins_r23.json 留档）；R23 终审修复件以修订历史为准（v1.0.1 引脚契约零变更）；历史件补录按 R88 节奏（每轮 ≤10 件）继续。

## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 6 件 + 修复件 1 件）

### FB_DL_StringIVTrace（功能块 FB，）｜ v1.0.0

- **功能**：光伏组串 IV 扫描顺控——恒压步进扫描（fVCmdV 由 0 按步距
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bStart` | BOOL | 启动请求 [—]，上升沿生效 |
| INPUT | `bAbort` | BOOL | 中止请求 [—]，任意拍生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清故障态 |
| INPUT | `fMeasV` | LREAL | 测量电压回读 [V] |
| INPUT | `fMeasI` | LREAL | 测量电流回读 [A] |
| INPUT | `bMeasReady` | BOOL | 测量就绪握手 [—]（每步采样条件） |
| INPUT | `fVStepV` | LREAL := 0.5 | 电压步距 [V]，须 > 0 |
| INPUT | `fVMaxV` | LREAL := 50.0 | 扫描电压上限 [V]，须 > 步距 |
| INPUT | `fIocThreshA` | LREAL := 0.002 | 开路阈值电流 [A]，电流低于此判 Voc，须 > 0 |
| INPUT | `tStepDwell` | TIME  := T#50MS | 每步驻留窗 [ms]，须 > 0 |
| INPUT | `tMeasTimeout` | TIME  := T#1S | 测量超时窗 [ms]，须 > 驻留窗（R100 配比） |
| OUTPUT | `fVCmdV` | LREAL | 扫描命令电压 [V]（给电子负载/扫频源） |
| OUTPUT | `fVocV` | LREAL | 开路电压特征点 [V]，未捕获为 0 |
| OUTPUT | `fIscA` | LREAL | 短路电流特征点 [A]，未捕获为 0 |
| OUTPUT | `fPmaxW` | LREAL | 最大功率点功率 [W] |
| OUTPUT | `fVmpV` | LREAL | 最大功率点电压 [V] |
| OUTPUT | `fImpA` | LREAL | 最大功率点电流 [A] |
| OUTPUT | `fFillFactor` | LREAL | 填充因子 [无量纲]，Voc·Isc 无效时置 0 |
| OUTPUT | `ePhase` | E_DL_IvTracePhase | 扫描相位 [—] |
| OUTPUT | `bTraceDone` | BOOL | 扫描完成 [—]（完成态电平） |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01F0 起信息级、16#0005_032D 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_ChamberPumpDownProfile（功能块 FB，）｜ v1.0.0

- **功能**：真空腔体抽气过程包络监视——启动时锁定基线压力，以指数衰减
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bStart` | BOOL | 启动请求 [—]，上升沿生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `fPressPa` | LREAL | 腔压实测 [帕]（绝对压力） |
| INPUT | `fTargetPa` | LREAL := 10.0 | 目标真空 [帕]，须 > 0 |
| INPUT | `fTauEnvS` | LREAL := 60.0 | 包络时间常数 [秒]，须 > 0 |
| INPUT | `fStagThreshPa` | LREAL := 0.5 | 停滞阈 [帕]（窗极差低于此判停滞） |
| INPUT | `fSlopeMargin` | LREAL := 1.2 | 包络预警带倍数 [倍]（须 >= 1） |
| INPUT | `tSlopeTimeout` | TIME  := T#30S | 抽速异常确认窗 [ms]，须 > 0 |
| INPUT | `fCycleTimeS` | LREAL := 0.01 | 任务扫描周期 [秒]，须 > 0（R95 代理阈值） |
| OUTPUT | `bPumpAbortReq` | BOOL | 抽速异常早停请求 [—]（锁存保持） |
| OUTPUT | `bPumpDownDone` | BOOL | 抽气完成 [—]（完成态电平） |
| OUTPUT | `fEnvPressPa` | LREAL | 包络上界 [帕]（诊断出口） |
| OUTPUT | `eState` | E_DL_PumpDownState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01F2 起信息级、16#0005_0330 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_CartonErectorStation（功能块 FB，）｜ v1.0.1　**注**：v1.0.0→v1.0.1（R24 终审修复：步进器复位死锁）

- **功能**：开箱工站七态九步骨架——七态 = 就绪/送箱坯/开箱/折底/插底/
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bStart` | BOOL | 启动请求 [—]，上升沿生效 |
| INPUT | `bAbort` | BOOL | 中止请求 [—]，任意拍生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `bBlankPresent` | BOOL | 箱坯在位 [—] |
| INPUT | `bVacuumFb` | BOOL | 吸持真空反馈 [—] |
| INPUT | `bLiftFb` | BOOL | 提升到位反馈 [—] |
| INPUT | `bOpenFb` | BOOL | 开箱到位反馈 [—] |
| INPUT | `bFoldFb` | BOOL | 折翼到位反馈 [—] |
| INPUT | `bTuckFb` | BOOL | 插底到位反馈 [—] |
| INPUT | `bPressFb` | BOOL | 压底到位反馈 [—] |
| INPUT | `bEjectFb` | BOOL | 推出到位反馈 [—] |
| INPUT | `tDwell` | TIME  := T#200MS | 无反馈步驻留兜底 [ms]，须 > 0 |
| OUTPUT | `ePhase` | E_DL_CartonPhase | 工站相位 [—] |
| OUTPUT | `bVacuumOn` | BOOL | 吸持真空输出 [—] |
| OUTPUT | `bFeedOut` | BOOL | 送箱坯下降输出 [—] |
| OUTPUT | `bOpenOut` | BOOL | 开箱缸输出 [—] |
| OUTPUT | `bFoldOut` | BOOL | 折翼缸输出 [—] |
| OUTPUT | `bTuckOut` | BOOL | 插底缸输出 [—] |
| OUTPUT | `bPressOut` | BOOL | 压底缸输出 [—] |
| OUTPUT | `bEjectOut` | BOOL | 推出缸输出 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01F4 起信息级、16#0005_0333 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_TrackBarcodeTrace（功能块 FB，）｜ v1.0.0

- **功能**：托盘条码扫码路由——触发沿进扫码态，扫码枪以「bScanDone +
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bTrigger` | BOOL | 触发扫码 [—]，上升沿生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清故障态 |
| INPUT | `sBarcode` | STRING(32) | 扫码枪回读码 [字符]，超 32 字符截断（截断判定先于钳长，R49） |
| INPUT | `bScanDone` | BOOL | 扫码完成握手 [—]（单次有效） |
| INPUT | `sRoutePrefixA` | STRING(8) := 'A' | A 道前缀 [字符]，两前缀不得均空 |
| INPUT | `sRoutePrefixB` | STRING(8) := 'B' | B 道前缀 [字符] |
| INPUT | `tScanTimeout` | TIME  := T#2S | 扫码超时窗 [ms]，须 > 0 |
| OUTPUT | `eRoute` | E_DL_LaneRoute | 分道判定 [—] |
| OUTPUT | `bLaneA` | BOOL | A 道输出 [—] |
| OUTPUT | `bLaneB` | BOOL | B 道输出 [—] |
| OUTPUT | `bReject` | BOOL | 拒收道输出 [—] |
| OUTPUT | `sTraceCode` | STRING(32) | 追溯码 [字符]（路由结果锁存随行） |
| OUTPUT | `eState` | E_DL_BarcodeRouteState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01F6 起信息级、16#0005_0336 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_TankDosingMulti（功能块 FB，）｜ v1.0.0

- **功能**：多罐（2~4 罐）轮流定量投加——轮值指针在可用罐间循环推进
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bStart` | BOOL | 启动请求 [—]，上升沿生效 |
| INPUT | `bAbort` | BOOL | 中止请求 [—]，任意拍生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `nTankCount` | USINT | 罐数 [罐]，有效域 2..4 |
| INPUT | `afTankAvail` | ARRAY[0..3] OF BOOL | 各罐可用 [—]（false = 备用/故障罐跳过） |
| INPUT | `afScaleG` | ARRAY[0..3] OF LREAL | 各罐秤读数 [克]（投加目标侧） |
| INPUT | `fTargetG` | LREAL := 1000.0 | 单罐目标量 [克]，须 > 0 |
| INPUT | `tSettleTime` | TIME  := T#2S | 稳定窗 [ms]，须 > 0 |
| INPUT | `tDoseTimeout` | TIME  := T#120S | 单罐定量超时窗 [ms]，须 > 稳定窗（R100 配比） |
| INPUT | `fScaleTolG` | LREAL := 0.5 | 秤稳定/回退容差 [克] |
| OUTPUT | `ePhase` | E_DL_TankDosingPhase | 投加相位 [—] |
| OUTPUT | `nActiveTank` | USINT | 当前投加罐号 [罐]，0 基 |
| OUTPUT | `fDosedG` | LREAL | 已投量 [克] = 读数 - 基线 |
| OUTPUT | `bDosingOut` | BOOL | 投加阀输出 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01F8 起信息级、16#0005_0339 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_BatchDeviationAlarm（功能块 FB，）｜ v1.0.0

- **功能**：批次偏差四档分级监视——|测量 - 设定| 越档判定：预警档
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 分级监视使能 [—] |
| INPUT | `bReset` | BOOL | 故障/首出复位 [—]，上升沿清首出锁存 |
| INPUT | `fValueMeas` | LREAL | 批次实测值 [工艺量纲] |
| INPUT | `fValueSp` | LREAL | 批次设定值 [工艺量纲] |
| INPUT | `fBandWarn` | LREAL := 1.0 | 预警带宽 [工艺量纲]，须 > 0 |
| INPUT | `fBandMinor` | LREAL := 2.0 | 次要带宽 [工艺量纲]，须 > 预警带宽 |
| INPUT | `fBandMajor` | LREAL := 5.0 | 严重带宽 [工艺量纲]，须 > 次要带宽 |
| INPUT | `tDebounce` | TIME  := T#2S | 越限去抖窗 [ms]，须 > 0 |
| OUTPUT | `eDevLevel` | E_DL_BatchDevLevel | 当前偏差档位 [—] |
| OUTPUT | `fDeviation` | LREAL | 当前偏差 [工艺量纲]（带符号，诊断出口） |
| OUTPUT | `bFirstOut` | BOOL | 首出锁存有效 [—]（bReset 才清） |
| OUTPUT | `eFirstOut` | E_DL_BatchDevLevel | 首出档位 [—] |
| OUTPUT | `bFirstHigh` | BOOL | 首出方向 [—]，TRUE = 高向 |
| OUTPUT | `eState` | E_DL_BatchDevState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01FA 起信息级、16#0005_033C 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_RollCompressForceBalance（功能块 FB，）｜ v1.0.0

- **功能**：辊压机两侧轧制力差动平衡——压差 = 左力 - 右力，压差绝对值
- **码位带**：16#0005_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 平衡使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `fForceLeftKn` | LREAL | 左侧轧制力 [千牛] |
| INPUT | `fForceRightKn` | LREAL | 右侧轧制力 [千牛] |
| INPUT | `fDiffLimitKn` | LREAL := 10.0 | 压差窗 [千牛]，须 > 0 |
| INPUT | `fTrimGainPctPerKn` | LREAL := 1.0 | 修调增益 [百分数每千牛] |
| INPUT | `fTrimRatePctS` | LREAL := 5.0 | 修调限速 [百分数每秒]，须 > 0 |
| INPUT | `fCycleTimeS` | LREAL := 0.01 | 任务扫描周期 [秒]，须 > 0（R95 代理阈值） |
| INPUT | `tDiffDebounce` | TIME  := T#2S | 压差去抖窗 [ms]，须 > 0 |
| INPUT | `tSatTimeout` | TIME  := T#30S | 饱和确认窗 [ms]，须 > 去抖窗（R100 配比） |
| OUTPUT | `fTrimPct` | LREAL | 差动修调输出 [百分数]，-100..100（正 = 增左向） |
| OUTPUT | `bBalanceOk` | BOOL | 压差在窗内 [—] |
| OUTPUT | `bTrimSaturated` | BOOL | 修调饱和 [—] |
| OUTPUT | `eState` | E_DL_RollBalanceState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0005_01FC 起信息级、16#0005_033F 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |


## R27 新增接口表（6 件 · 2026-11-17）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_FillWeightCtrl` | FB | IN `fGrossWeight_g`/`fTargetNet_g`/`fCoarsePct`/`tFineMax`/`tSettle`/`bStart`/`bReset`；OUT `bCoarseValve`/`bFineValve`/`bFillDone`/`fAdvance_g`/`fNetWeight_g`/`eErr` | 五相灌装；去皮内部锁存，落差学习仅完成相一次，超重即中止（v1.0.1），两阀互斥后置校验 |
| `FB_DL_VffsBagLength` | FB | IN `bMarkDetect`/`bEncPulse`/`fBagLenSet_mm`/`uEncPpr`/`fCorrLimit_mm`/`tMarkDeb`/`bReset`；OUT `fBagLenAct_mm`/`fCorr_mm`/`bMarkLost`/`bCutPhaseOk`/`nPhaseDiag`/`eErr` | 立式制袋袋长，偏差限幅 5 mm，相位取正余数委托 ModPos，连续丢标退化定长 |
| `FB_DL_CartonErectSeq` | FB | IN `bVacuumOk`/`bBoxFormed`/`bFlapClosed`/`tStepMax`/`bStart`/`bReset`；OUT `ePhase`/`bDone`/`bJam`/`eJamPhase`/`bVacuumCmd`/`bConveyorCmd`/`eErr` | 开箱四相顺控，转相只认反馈不认时间，超时进 ERR 并锁存卡箱相号 |
| `FB_DL_LoadPortSeq` | FB | IN `bFoupPresent`/`bDoorOpenOk`/`bValveAck`/`aMapExpect`/`aMapRead`/`tDoorMax`/`tHandMax`/`bStart`/`bReset`；OUT `ePhase`/`bMapMatch`/`bReleaseOk`/`nMapDiff`/`bDoorOpenCmd`/`bDoorCloseCmd`/`eErr` | 七相 LoadPort；25 位固定界逐位比对只计数不中断，差异非零走拒收相；超时安全收拢 |
| `FB_DL_PumpChangeoverSeq` | FB | IN `fDeltaT_C`/`fDeltaTSet_C`/`aNRunHrs`/`uPumpTotal`/`tMinRun`/`tMinStop`；OUT `auPumpCmd`/`uRunCount`/`eErr` | 水泵加减机：死区 ±0.5 ℃ 保持、级数下限 1（不保备机），温差无效只报码不切换 |
| `FB_DL_MachineGuardAudit` | FB | IN `bGuardOpen`/`bBatchActive`/`sOperId`/`tMaxOpen`/`bManualConfirm`/`bReset`；OUT `eState`/`bLockBatch`/`uOpenCnt`/`sLastOper`/`eErr` | 防护门审计五态：锁定/已锁分相，恢复三条件，超时升级违规，空标识复位被拒 |

## R30 新增接口表（Process 8 件 · 2026-11-18）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_WaferScanRouter` | FB | IN `bScanTrigger`/`sBarcode`/`bReadOk`/`uStationMod`/`abRouteEn`〔ARRAY[1..8]〕/`tScanTimeout`；OUT `uRouteSel`〔0=拒收〕/`bRouteOk`/`uSlotIdx`/`eErr` | 扫码分道路由；取模索引用条件减法（不用 MOD 规避负数歧义）；空串与读码失败分列两码；码位 0467~046B |
| `FB_DL_SiloLevelInterlock` | FB | IN `bHighLevel`/`bLowLevel`/`bConvRun`/`bRunDemand`/`tJamWin`/`bReset`；OUT `bConvPermit`〔安全侧 FALSE〕/`bOverflowTrip`/`bEmptyTrip`/`bJamDet`/`eErr` | 高料位停进料不停输送；低料位停输送防空跑；双开关同真判组态矛盾；4 锁存位解除式均可达；码位 046C~0470 |
| `FB_DL_PalletZoneMerge` | FB | IN `abZiOcc`〔ARRAY[1..4]〕/`bMergeReq`/`tZiGapMin`/`uMergeMode`〔1=顺序 2=先到先走〕；OUT `abZiRelease`/`bMergeBusy`/`uReleaseSeq`/`eErr` | 合流仲裁同拍至多释放一区、多区请求取最小区号；非法模式 ELSE 冻结 + 码；码位 0471~0475 |
| `FB_DL_WeightClassifySort` | FB | IN `bPartInZone`/`fWeight_g`/`fTh_LL_g`~`fTh_HH_g`〔四阈值单调闸〕/`bRejectArm`；OUT `eClass`〔E_DL_WeightClass〕/`bRejectOut`/`uOkCount`/`uNgCount`/`eErr` | 判档委托 `FC_DL_LimitClassify` 不重写分级律；非有限重量 NG 安全分流 + 传感器故障码；码位 0476~047A |
| `FB_DL_EmoAndonFab` | FB | IN `abEmo`〔ARRAY[1..6]〕/`bDoorOpenMask:WORD`/`bAck`/`bReset`；OUT `eAndonLevel`〔E_DL_AndonLevel 属主引用〕/`bLampRed`/`bBuzzer`/`uFirstEmo`/`eErr` | EMO 优先于普通呼叫（同拍取高）；仲裁律消费 `FB_DL_AndonCallSystem`；首出定位到按钮号；码位 047B~047F |
| `FB_DL_FillWeightCheckweigher` | FB | IN `bWeightValid`/`fWeight_g`/`fNominal_g`/`fTolPct`/`fStableBand_g`/`tStableWin`/`tRejectPulse`/`bRejectArm`；OUT `eClass`（属主=WeightClassifySort 文件）/`bRejectOut`/`uRejectCount`/`eErr` | 动态称重稳定窗内波动 < 门槛才判；去皮负值独立故障码；`fTolPct=0` 退化为 ±1E-6 g 判等；码位 0480~0484 |
| `FB_DL_FilmSpliceDetect` | FB | IN `bMarkLatchValid`/`fMarkLatchPos_m`/`fConvDist_m`/`bConvRun`/`fConvSpeed_mmin`/`fApproachDist_m`/`fMinFilmLen_m`/`tSlowWin`；OUT `bSpliceApproach`/`bSlowPermit`/`uSpliceCount`/`eErr` | 接膜计数只在降速窗完成放行时递增；停机后位置锁存不触发放行（run-on）；速度非有限/负值闸；码位 0485~0489 |
| `FB_DL_CoatingGapMeasure` | FB | IN `afPixEdge1`/`afPixEdge2`/`fPixToMm`〔mm/px，>0〕/`afGapLo_mm`/`afGapHi_mm`/`fWinTolPct`/`uWinSize`/`fWinMean_mm`/`fWinRange_mm`/`bWinStatValid`；OUT `fGap_mm`/`bGapOk`/`bWindowConsist`/`eErr` | 窗口一致性统计经引脚注入（消费 SignalStatistics 范式不重写）；带判定闭/开归属声明，向量含「恰好落在带端点」；码位 048A~048E |
