# MANUAL — DL_Device 标准物理设备 OOP 抽象子库使用手册

> **Sublibrary**：`DL_Device` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：1 ｜ **Components**：57（接口 17 ｜ 功能块 40，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert
> **Depends**：`Standard.library`（`TON` / `R_TRIG`）+ `DL_Base/FB_DL_SignalDebounce`（气缸消抖）+ `DL_Algo`（仅 `FB_DL_HeatCoolZone` 注入消费 PID/PWM）
> **故障码段 / Error Code Family**：`16#0003_xxxx`（信息级 `01xx` ｜ 故障级 `02xx` 与 `030x` 扩展块；**R12 本批占用 `0149`~`0155` 与 `0309`~`0315`，故障码上界提至 `0315`**。`02FA~02FF` 六码仍封存禁填）
> 配套版本记录见 `DL_Device/VERSION.md`；全库导航见 `C:\Library\README.md`。**引脚级细节以 `.st` 源码声明区为准**，本手册接口表逐字取自源码。
> **R6 组深化说明**：第 11~20 节为阀门三分法（比例阀 / 电动阀 / 真空与气缸）+ 星三角 + 变频器族共 10 个新组件；接口方法故障态一律拒绝并返回 FALSE。

---

## 0. 使用前必读 / Before You Start

1. **契约/实现分离**：上层工艺块只依赖 `I_DL_*` 接口编程（依赖倒置）；接口方法全部为非阻塞单发语义——方法内只置请求标志，动作由实现块主体状态机在扫描周期内执行。故障态下任何动作方法一律拒绝并返回 FALSE。
2. **每周期无条件调用**：全部 `FB_*` 实现块必须在主任务每个扫描周期调用一次，严禁把实例调用塞进 `IF`（丢沿、状态机冻结）。
3. **同名成员的属性实现**：凡规格 OUT 列与接口属性同名的成员，实现块以只读 `PROPERTY GET` 形式暴露（IEC 命名空间约束，R11 留档）；属性即输出引脚语义，HMI 读法一致。
4. **信息级与故障级**：信息级码（钳位、对调修复、次数超限拒绝等）只写 `uErrorId`，不置 `bFault`/`bError`；故障级码锁存，仅复位可清。HMI 报警分组应同时读 `bFault` 与 `uErrorId`。
5. **接口成员落地纪律**：任何新增实现块不得增删接口方法签名、不得重定义随接口发布的枚举，否则破坏依赖本接口的全部上层块（MAJOR 变更走版本迁移指引）。

---

## 1. 组件索引 / Component Index

| 组件 / Component | 类型 / Kind | 用途 / Purpose | 依赖 / Depends On |
|---|---|---|---|
| `I_DL_Cylinder` | 接口 | 双电控气缸标准契约 / Cylinder contract | 无 |
| `FB_DL_PneumaticCylinder` | 功能块 | 气缸驱动实现 / Cylinder driver | `I_DL_Cylinder`、`FB_DL_SignalDebounce` |
| `I_DL_MotorDriver` | 接口 | DOL 电机驱动契约 / Motor driver contract | 无 |
| `FB_DL_DolMotor` | 功能块 | DOL 电机控制实现 / Motor controller | `I_DL_MotorDriver` |
| `I_DL_AnalogSensor` | 接口 | 模拟量变送器契约（NE43）/ Analog sensor contract | 无 |
| `FB_DL_AnalogTransmitter` | 功能块 | NE43 变送器处理实现 / Transmitter block | `I_DL_AnalogSensor` |
| `I_DL_TemperatureZone` | 接口 | 温控区契约 / Temperature zone contract | 无 |
| `FB_DL_HeatCoolZone` | 功能块 | 双通道温控区实现 / Zone controller | `I_DL_TemperatureZone`、`I_DL_AnalogSensor`、`FB_DL_PidController`、`FB_DL_PwmDutyController` |
| `FB_DL_SingleSolenoidCyl` | 功能块 | 单电控弹簧复位气缸（R6）/ Single-solenoid cylinder | `I_DL_Cylinder` |
| `I_DL_VacuumGenerator` | 接口 | 真空发生器契约（R6）/ Vacuum generator contract | 无 |
| `FB_DL_VacuumEjector` | 功能块 | 真空发生器驱动（R6）/ Vacuum ejector | `I_DL_VacuumGenerator` |
| `FB_DL_StarDeltaMotor` | 功能块 | 星三角降压启动（R6）/ Star-delta starter | `E_DL_MotorState` |
| `I_DL_VfdDrive` | 接口 | 通用变频器契约（R6）/ Generic VFD contract | 无 |
| `FB_DL_VfdGeneric` | 功能块 | 通用端子型变频器驱动（R6）/ Terminal-type VFD driver | `I_DL_VfdDrive` |
| `I_DL_ProportionalValve` | 接口 | 比例调节阀契约（R6）/ Proportional valve contract | 无 |
| `FB_DL_AnalogValve` | 功能块 | 模拟量调节阀指令整形（R6）/ Analog valve shaping | `I_DL_ProportionalValve` |
| `I_DL_MotorizedValve` | 接口 | 电动调节阀契约（R6）/ Motorized valve contract | 无 |
| `FB_DL_ThreePointValve` | 功能块 | 三点浮点电动阀控制（R6）/ Three-point floating valve | `I_DL_MotorizedValve` |

---

## 2. I_DL_Cylinder ｜ 双电控气缸标准接口

**功能**：定义双电控气缸的状态读取属性组（GET）与动作指令方法组，供 DL_Process 机站动作层依赖注入；具体电磁阀输出与传感器采集由实现块完成，接口层不做任何过程映像读写。
**随文件枚举**：`E_DL_CylinderState`（`eIdle=0 / eExtending=10 / eExtended=20 / eRetracting=30 / eRetracted=40 / eFault=99`，步长 10 预留插态位）。

### 2.1 属性 / Properties（全部只读 GET）

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `eState` | `E_DL_CylinderState` | GET | 当前状态机状态 / Current state |
| `bExtended` | `BOOL` | GET | 伸出到位磁开反馈，TRUE=伸出到位 / Extended reed feedback, TRUE = in extended position |
| `bRetracted` | `BOOL` | GET | 缩回到位磁开反馈，TRUE=缩回到位 / Retracted reed feedback, TRUE = in retracted position |
| `bFault` | `BOOL` | GET | 故障锁存中，TRUE=存在未复位故障 / Fault latched, TRUE = fault pending reset |
| `uErrorId` | `UDINT` | GET | 末次故障码，0=无故障，段位 `16#0003_xxxx` / Last error code, 0 = none |

### 2.2 方法 / Methods

| 方法 / Method | 返回 / Return | 说明 / Description |
|---|---|---|
| `CmdExtend() : BOOL` | 受理结果 / accepted | 伸出指令，单发；故障态拒绝返回 FALSE / Extend command, one-shot, rejected in fault state |
| `CmdRetract() : BOOL` | 受理结果 / accepted | 缩回指令，单发；故障态拒绝返回 FALSE / Retract command, one-shot |
| `CmdStop() : BOOL` | 受理结果 / accepted | 双线圈全断、保持当前位置；故障态拒绝 / Stop command: both coils off, hold position |
| `CmdReset() : BOOL` | 可复位 / resettable | 复位故障，返回是否可复位（存在故障时 TRUE）/ Reset, returns TRUE only when a latch exists |

### 2.3 调用示例 / Call Example

```iecst
// 面向接口编程：上层只持有引用，不关心实现品牌 / Program against the interface
VAR
    iCyl : I_DL_Cylinder;               // 接口引用 / Interface reference
    fbCyl : FB_DL_PneumaticCylinder;    // 实现块实例 / Implementation instance
END_VAR

iCyl := fbCyl;                          // 注入实现块实例 / Inject implementation
IF bAutoStart THEN
    iCyl.CmdExtend();                   // 伸出指令（单发）/ Issue extend command
END_IF

IF iCyl.bFault THEN
    IF iCyl.CmdReset() THEN ; END_IF    // 复位 / Attempt reset when latched
END_IF

fbCyl(bCmdExtend := bBtnExt,            // 每周期无条件调用 / Unconditional cycle call
      bCmdRetract := bBtnRet,
      bSnsExtended := xExtReed,
      bSnsRetracted := xRetReed,
      bInterlock := bCellSafe);
```

---

## 3. FB_DL_PneumaticCylinder ｜ 双电控气缸驱动功能块

**功能**：标准双电控（双线圈）气缸控制。含磁开信号双通道消抖、伸/缩超时自检、双传感器位置冲突锁存、双线圈互斥出口断言、联锁失电保位、行程计数；状态机 `ENUM + CASE + ELSE` 兜底。实现 `I_DL_Cylinder`（属性/方法在文件尾部落地）。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 3.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `bCmdExtend` | `BOOL` | IN | — | 伸出指令，上升沿生效 / Extend command, rising edge effective |
| `bCmdRetract` | `BOOL` | IN | — | 缩回指令，上升沿生效 / Retract command, rising edge effective |
| `bSnsExtended` | `BOOL` | IN | — | 伸出到位磁性开关，TRUE=到位 / Extended reed switch, TRUE = in position |
| `bSnsRetracted` | `BOOL` | IN | — | 缩回到位磁性开关，TRUE=到位 / Retracted reed switch, TRUE = in position |
| `bInterlock` | `BOOL` | IN | FALSE | 允许动作联锁，TRUE=允许动作，默认 FALSE 双线圈保持断开；行程中途撤除=线圈断、保位、不判故障 / Motion interlock, mid-stroke drop = coils off, hold, no fault |
| `tTimeoutExt` | `TIME` | IN | `T#2S` | 伸出到位超时，`T#0S`=禁用自检 / Extend timeout, 0 disables |
| `tTimeoutRet` | `TIME` | IN | `T#2S` | 缩回到位超时，`T#0S`=禁用自检 / Retract timeout, 0 disables |
| `tDebounce` | `TIME` | IN | `T#20MS` | 磁开防抖窗口，`T#0S`=直通 / Sensor debounce window, 0 = pass-through |
| `bReset` | `BOOL` | IN | — | 故障复位，上升沿生效 / Fault reset, rising edge effective |
| `bSolenoidExt` | `BOOL` | OUT | — | 伸出线圈输出，TRUE=得电（与缩回互斥，出口断言）/ Extend solenoid coil, exclusive with retract |
| `bSolenoidRet` | `BOOL` | OUT | — | 缩回线圈输出，TRUE=得电 / Retract solenoid coil |
| `eState` | `E_DL_CylinderState` | OUT/PROP | — | 当前状态机状态（属性 + 引脚双形式）/ Current state |
| `bExtended` | `BOOL` | OUT/PROP | — | 伸出到位反馈（消抖后）/ Debounced extended feedback |
| `bRetracted` | `BOOL` | OUT/PROP | — | 缩回到位反馈（消抖后）/ Debounced retracted feedback |
| `bMoving` | `BOOL` | OUT | — | 运动中指示，TRUE=伸/缩动作中 / Moving indicator |
| `bFault` | `BOOL` | OUT/PROP | — | 故障锁存中，TRUE=需复位 / Fault latched |
| `uErrorId` | `UDINT` | OUT/PROP | — | 末次故障码 / Last error code |
| `uCycleCount` | `UDINT` | OUT | — | 行程计数，缩回到位上升沿 +1 / Stroke count, +1 per retracted edge |

### 3.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0201` | 故障级 / Fault | 非法状态兜底（CASE ELSE）/ Illegal state fallback | 复位后观察；复现上报 |
| `16#0003_0202` | 故障级 / Fault | 伸出到位超时 / Extend timeout | 检查气源、伸出磁开与 `tTimeoutExt` |
| `16#0003_0203` | 故障级 / Fault | 缩回到位超时 / Retract timeout | 检查气源、缩回磁开与 `tTimeoutRet` |
| `16#0003_0204` | 故障级 / Fault | 双传感器同时动作（位置冲突）/ Both reed switches active | 检查磁开接线与机械位置，复位 |

### 3.3 调用示例 / Call Example

```iecst
VAR
    fbCyl : FB_DL_PneumaticCylinder;      // 气缸实例 / Cylinder instance
END_VAR

// 每周期无条件调用（主周期）/ Unconditional call in cyclic task
fbCyl(bCmdExtend    := bAutoExt OR bManExt,     // 引脚指令通道 / Pin command channel
      bCmdRetract   := bAutoRet,
      bSnsExtended  := xSnsExt,                 // 磁开 DI / Reed DI
      bSnsRetracted := xSnsRet,
      bInterlock    := bZoneSafe,
      tTimeoutExt   := T#2S, tTimeoutRet := T#2S, tDebounce := T#20MS);

xSolenoidExt := fbCyl.bSolenoidExt;             // 线圈 DO / Coil DO
xSolenoidRet := fbCyl.bSolenoidRet;

IF fbCyl.bFault THEN
    IF bOpAck THEN fbCyl.bReset := TRUE; END_IF // 现场复位 / Operator reset
END_IF
```

---

## 4. I_DL_MotorDriver ｜ DOL 电机驱动器标准接口

**功能**：直接启动（DOL）电机驱动器标准抽象契约：状态读取属性组（含重启抑制指示）与启停/复位方法组；接触器线圈驱动与反馈采集由实现块完成。
**随文件枚举**：`E_DL_MotorState`（`eIdle=0 / eStarting=10 / eRunning=20 / eStopping=30 / eTripOverload=40 / eFault=99`）。

### 4.1 属性 / Properties（全部只读 GET）

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `eState` | `E_DL_MotorState` | GET | 当前状态机状态 / Current state |
| `bRunning` | `BOOL` | GET | 运行反馈，TRUE=触点吸合确认运行中 / Running confirmed by contactor feedback |
| `bFault` | `BOOL` | GET | 故障锁存中（含过载脱扣）/ Fault latched incl. overload trip |
| `uErrorId` | `UDINT` | GET | 末次故障码，0=无故障，段位 `16#0003_xxxx` / Last error code |
| `bRestartInhibit` | `BOOL` | GET | 重启抑制激活中，TRUE=冷却期内拒绝启动 / Restart inhibit active |

### 4.2 方法 / Methods

| 方法 / Method | 返回 / Return | 说明 / Description |
|---|---|---|
| `CmdStart() : BOOL` | 受理结果 / accepted | 启动指令，单发；被抑制/故障态返回 FALSE / Start, rejected when inhibited or faulty |
| `CmdStop()` | — | 停止指令，无条件安全动作 / Unconditional safe stop |
| `CmdReset() : BOOL` | 可复位 / resettable | 复位过载/故障，返回是否可复位 / Reset overload and fault |

### 4.3 调用示例 / Call Example

```iecst
VAR
    iMot : I_DL_MotorDriver;             // 接口引用 / Interface reference
    fbMot : FB_DL_DolMotor;              // 实现块实例 / Implementation
END_VAR

iMot := fbMot;
IF bAutoRun THEN bAccepted := iMot.CmdStart(); END_IF   // 受理结果判断 / Check acceptance
IF bEStopChain THEN iMot.CmdStop(); END_IF
```

---

## 5. FB_DL_DolMotor ｜ DOL 电机控制功能块

**功能**：直接启动（DOL）电机控制。含指令-反馈校验窗（拒动保护）、运行失反馈脱扣、热继电器过载锁存、最短运行时间监视、60 分钟桶滑窗每小时启动次数限制与停机后重启抑制冷却。实现 `I_DL_MotorDriver`。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 5.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `bCmdStart` | `BOOL` | IN | — | 启动指令，上升沿生效 / Start command, rising edge |
| `bCmdStop` | `BOOL` | IN | — | 停止指令，电平生效 / Stop command, level effective |
| `bFbContactor` | `BOOL` | IN | — | 接触器辅助触点反馈，TRUE=吸合 / Contactor feedback, TRUE = picked up |
| `bThermalOverload` | `BOOL` | IN | — | 热继电器过载信号，TRUE=过载 / Thermal overload trip |
| `bPermitStart` | `BOOL` | IN | — | 启动允许联锁，TRUE=允许 / Start permit interlock |
| `tFbWindow` | `TIME` | IN | `T#500MS` | 指令-反馈校验窗口，`T#0S`=免校验 / Feedback check window, 0 disables |
| `tMinRunTime` | `TIME` | IN | `T#5S` | 最短运行时间，`T#0S`=免监视 / Min run time, 0 disables |
| `tRestartInhibit` | `TIME` | IN | `T#60S` | 重启抑制冷却时间（停机后）/ Restart inhibit cooling after stop |
| `uMaxStartsPerHour` | `USINT` | IN | `6` | 每小时最大启动次数（滑动小时窗上限）/ Max starts per sliding hour window |
| `bReset` | `BOOL` | IN | — | 故障复位，上升沿生效 / Fault reset, rising edge |
| `bContactorCmd` | `BOOL` | OUT | — | 接触器线圈输出，TRUE=得电 / Contactor coil command |
| `eState` | `E_DL_MotorState` | OUT/PROP | — | 当前状态机状态 / Current state |
| `bRunning` | `BOOL` | OUT/PROP | — | 运行反馈（运行态且触点吸合确认）/ Running feedback |
| `bFault` | `BOOL` | OUT/PROP | — | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | OUT/PROP | — | 末次故障码（含信息级码）/ Last error code incl. info codes |
| `bRestartInhibit` | `BOOL` | OUT/PROP | — | 重启抑制激活中 / Restart inhibit active |
| `uStartCount` | `UDINT` | OUT | — | 累计启动次数，每次受理启动 +1 / Total accepted start count |

### 5.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0205` | 故障级 / Fault | 接触器拒动（校验窗内未吸合）/ Contactor refused within window | 检查接触器线圈与反馈触点 |
| `16#0003_0206` | 故障级 / Fault | 运行中失反馈脱扣 / Feedback loss while running | 检查反馈触点与主回路 |
| `16#0003_0209` | 故障级 / Fault | 热继电器过载锁存 / Thermal overload latched | 排除过载原因，过载信号消失后复位 |
| `16#0003_0201` | 故障级 / Fault | 非法状态兜底 / Illegal state fallback | 复位后观察 |
| `16#0003_0207` | 信息级 / Info | 每小时启动次数超限拒绝启动 / Hourly start limit exceeded, start refused | 等滑窗回落或调大 `uMaxStartsPerHour` |
| `16#0003_0208` | 信息级 / Info | 重启抑制期内拒绝启动 / Start refused during restart inhibit | 等待冷却结束 |
| `16#0003_020A` | 信息级 / Info | 运行时间不足 `tMinRunTime` 重复启停 / Chattering below min run time | 检查控制逻辑抖动源 |

### 5.3 调用示例 / Call Example

```iecst
VAR
    fbMot : FB_DL_DolMotor;              // 电机实例 / Motor instance
END_VAR

fbMot(bCmdStart        := bPumpStart,    // 每周期无条件调用 / Unconditional call
      bCmdStop         := bPumpStop OR bEStop,
      bFbContactor     := xKmFb,         // 接触器辅助触点 / Contactor aux contact
      bThermalOverload := xOlTrip,       // 热继电器 95-96 / Overload trip
      bPermitStart     := bSuctionOk,
      uMaxStartsPerHour := 6);

xKmCoil := fbMot.bContactorCmd;          // 接触器线圈 / Contactor coil
IF fbMot.bFault AND bOpAck THEN fbMot.bReset := TRUE; END_IF
```

---

## 6. I_DL_AnalogSensor ｜ 模拟量变送器标准接口（NAMUR NE43 语义域）

**功能**：模拟量变送器标准抽象契约：工程量当前值、信号质量分级、HH/H/L/LL 四级报警位与故障码的只读属性组，供温控区等上层工艺块依赖注入。实现块承诺 `fValue` 经非有限值防御，故障态保持末次有效值——调用方无需再做空值判护。
**随文件枚举**：`E_DL_SignalQuality`（`eGood=0 / eUnderRange=10 / eOverRange=20 / eWireBreakLow=30 / eWireBreakHigh=40 / eOpenLoop=50`）。

### 6.1 属性 / Properties（全部只读 GET）

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fValue` | `REAL` | GET | 工程量当前值，单位由调用方标定组态约定，故障态保持末次有效值 / Engineering value, holds last good value in fault |
| `eQuality` | `E_DL_SignalQuality` | GET | NE43 信号质量分级 / NE43 diagnostic grade |
| `bAlarmHH` | `BOOL` | GET | 上上限报警 / High-high alarm |
| `bAlarmH` | `BOOL` | GET | 上限报警 / High alarm |
| `bAlarmL` | `BOOL` | GET | 下限报警 / Low alarm |
| `bAlarmLL` | `BOOL` | GET | 下下限报警 / Low-low alarm |
| `uErrorId` | `UDINT` | GET | 末次故障码，0=无故障，段位 `16#0003_xxxx` / Last error code |

### 6.2 调用示例 / Call Example

```iecst
VAR
    iSensor : I_DL_AnalogSensor;         // 接口引用 / Interface reference
END_VAR

IF (iSensor.eQuality = E_DL_SignalQuality.eWireBreakLow)
   OR (iSensor.eQuality = E_DL_SignalQuality.eOpenLoop) THEN
    bSensorFault := TRUE;                // 断线联锁 / Wire-break interlock
END_IF
fProcessValue := iSensor.fValue;         // 故障态已是保持值 / Hold value in fault
```

---

## 7. FB_DL_AnalogTransmitter ｜ NE43 变送器处理功能块

**功能**：NAMUR NE43 语义模拟量变送器处理块。在原始物理域（mA / 0..10V，由调用方约定）执行四段诊断：故障门限外断线（方向可配置）、欠量程段、有效测量域、超量程段，0 域附近判回路开路；内嵌滑动平均滤波与线性标定；故障态保持末次有效工程量；HH/H/L/LL 四级报警在有效与欠/超量程段照常计算、故障态全部保持。实现 `I_DL_AnalogSensor`。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 7.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `fRawInput` | `REAL` | IN | — | 原始输入，已线性化的 mA/0..10V 物理域值，单位由调用方约定 / Raw physical-domain input |
| `fRawLow` | `REAL` | IN | — | 原始域量程下限（如 4.0 mA），Min>Max 对调自修复 / Raw span low, swap self-repair |
| `fRawHigh` | `REAL` | IN | — | 原始域量程上限（如 20.0 mA）/ Raw span high |
| `fEuLow` | `REAL` | IN | — | 工程量程下限（如 0.0 [%] 或 [kPa]）/ Engineering span low |
| `fEuHigh` | `REAL` | IN | — | 工程量程上限 / Engineering span high |
| `eBreakDirection` | `E_DL_BreakDir` | IN | `eLow` | 断线故障方向：`eLow`=低断（Downscale）/ `eHigh`=高通（Upscale），按变送器组态；只判配置方向不误报 / Break direction per transmitter config |
| `fFaultLow` | `REAL` | IN | `3.6` | NE43 故障下门限（原始域）/ NE43 low fault threshold |
| `fFaultHigh` | `REAL` | IN | `21.0` | NE43 故障上门限（原始域）/ NE43 high fault threshold |
| `uFilterWindow` | `USINT` | IN | `8` | 滑动平均窗口，1=直通（上限 128）/ Moving-average window, 1 = bypass |
| `bEnableFilter` | `BOOL` | IN | `TRUE` | 使能滑动平均滤波，FALSE=直通 / Enable moving-average filter |
| `fAlarmHH` | `REAL` | IN | — | 上上限报警门限，量纲=工程量，非数=禁用 / High-high limit in EU, NaN disables |
| `fAlarmH` | `REAL` | IN | — | 上限报警门限，非数=禁用 / High limit, NaN disables |
| `fAlarmL` | `REAL` | IN | — | 下限报警门限，非数=禁用 / Low limit, NaN disables |
| `fAlarmLL` | `REAL` | IN | — | 下下限报警门限，非数=禁用 / Low-low limit, NaN disables |
| `bTrack` | `BOOL` | IN | — | 跟踪脉冲：TRUE 拍重置滤波缓冲与保持值（R11 偏离新增，首扫/跟踪范式 0.1）/ Track pulse re-primes filter and hold value |
| `fValue` | `REAL` | OUT/PROP | — | 工程量当前值，故障态保持末次有效值 / Holds last good value in fault |
| `eQuality` | `E_DL_SignalQuality` | OUT/PROP | — | 信号质量分级 / NE43 diagnostic grade |
| `bAlarmHH` | `BOOL` | OUT/PROP | — | 上上限报警（有效及欠/超量程段照常计算）/ High-high alarm |
| `bAlarmH` | `BOOL` | OUT/PROP | — | 上限报警 / High alarm |
| `bAlarmL` | `BOOL` | OUT/PROP | — | 下限报警 / Low alarm |
| `bAlarmLL` | `BOOL` | OUT/PROP | — | 下下限报警 / Low-low alarm |
| `uErrorId` | `UDINT` | OUT/PROP | — | 末次故障码 / Last error code |
| `bWireBreak` | `BOOL` | OUT | — | 断线/开路合并位 / Wire break merged flag |
| `bRangeViol` | `BOOL` | OUT | — | 欠/超量程合并位 / Range violation merged flag |

> **枚举** `E_DL_BreakDir`（随本文件发布）：`eLow=0` 低断方向（原始值低于故障下门限判断线）/ `eHigh=1` 高断方向。

### 7.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0210` | 故障级 / Fault | NE43 故障态：断线/开路/非有限输入（质量位持续标注，原始恢复后自动解除并重新跟随）/ NE43 fault state | 检查回路接线与变送器供电 |
| `16#0003_0102` | 信息级 / Info | 量程对调自修复（fRawLow > fRawHigh）/ Span swap self-repair | 核对组态量程 |
| `16#0003_0103` | 信息级 / Info | 欠/超量程提示（信号在 NE43 过渡段）/ Under/over range | 信号可用，检查量程裕量 |
| `16#0003_0104` | 信息级 / Info | 原始量程跨度退化回退（近零或非有限）/ Degenerate raw span | 核对 `fRawLow/High` 组态 |

> 欠/超量程门限按量程比例中点内插（故障门限与量程端点的中点），适配任意原始量程；与 NAMUR 原文固定 3.8/20.5 mA 口径的差异见 `VERSION.md` 已知限制。

### 7.3 调用示例 / Call Example

```iecst
VAR
    fbTx : FB_DL_AnalogTransmitter;      // 变送器实例 / Transmitter instance
END_VAR

fbTx(fRawInput      := xAiRaw * 16.0 + 4.0,   // 原始域换算示例 / Raw domain example
     fRawLow        := 4.0, fRawHigh  := 20.0, // mA 量程 / mA span
     fEuLow         := 0.0, fEuHigh   := 100.0,// 工程量程 [kPa] / EU span
     eBreakDirection := E_DL_BreakDir.eLow,
     fAlarmHH       := 95.0, fAlarmH := 90.0,
     fAlarmL        := 10.0, fAlarmLL := 5.0,
     uFilterWindow  := 8, bEnableFilter := TRUE);

fPressure := fbTx.fValue;                // 故障态自动保持 / Auto hold in fault
bSnsFail  := fbTx.bWireBreak;            // 断线联锁源 / Wire-break interlock source
```

---

## 8. I_DL_TemperatureZone ｜ 加热/冷却温控区标准接口

**功能**：加热/冷却温控区标准抽象契约（炉区、恒温室、模温机、老化房）。上层工艺层只依赖本接口编程，与具体温控实现彻底解耦。
**随文件枚举**：`E_DL_TempZoneState`（`eIdle=0 / eHeating=10 / eCooling=20 / eHolding=30 / eSensorBreak=40 / eFault=99`）。

### 8.1 属性 / Properties（全部只读 GET）

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fTempActual` | `REAL` | GET | 实测温度 [°C]，取自注入的传感器接口 / Actual temperature in degC |
| `fPowerOut` | `REAL` | GET | 输出功率 [-100..100 %]，正=加热 / 负=冷却 / Power output, positive = heating |
| `eState` | `E_DL_TempZoneState` | GET | 当前状态机状态 / Current zone state |
| `bFault` | `BOOL` | GET | 故障锁存中，仅故障级状态置位 / Fault latched, fault-level states only |
| `uErrorId` | `UDINT` | GET | 末次故障/信息码，0=无 / Last error/info code |

### 8.2 方法 / Methods

| 方法 / Method | 返回 / Return | 说明 / Description |
|---|---|---|
| `SetSetpoint(fTemp : REAL) : BOOL` | 合法性 / valid | 设定目标温度 [°C]，非有限值拒绝，越界由实现块钳位 / Set setpoint, non-finite rejected, bounds clamped |
| `CmdEnable(bOn : BOOL)` | — | TRUE=投运，FALSE=退出并切断双通道 / Commission on/off |
| `CmdReset() : BOOL` | 可复位 / resettable | 复位故障；断偶态要求信号质量恢复后方可成功 / Reset, requires good quality on sensor break |

### 8.3 调用示例 / Call Example

```iecst
VAR
    iZone : I_DL_TemperatureZone;        // 接口引用 / Interface reference
END_VAR

iZone.SetSetpoint(85.0);                 // 设定 [°C] / Set target
iZone.CmdEnable(bZoneAuto);              // 投运 / Commission
IF iZone.eState = E_DL_TempZoneState.eSensorBreak THEN
    // 断偶联锁：按对象安全策略处理 / Sensor-break interlock
END_IF
```

---

## 9. FB_DL_HeatCoolZone ｜ 双通道温控区控制功能块

**功能**：双通道（加热/冷却）温控区控制器，R4 算法族首个上层消费者。控制链：`FB_DL_PidController`（实例经引脚注入，参数外置组态）→ 分程分配（Split-range）→ `FB_DL_PwmDutyController` × 2（加热/冷却 SSR 驱动）。断偶保护：传感器质量进入断线/开路域时按 `eBreakAction` 切断对应通道并锁存 `eSensorBreak` 态，退出需 `CmdReset` 且质量恢复 `eGood`；锁存期间双通道全断为最终安全态。设定值经 `fTempMin/Max` 钳位（信息级）。实现 `I_DL_TemperatureZone`。
**分程约定**：PID 输出 [0..100 %]；低于 `fSplitLow` → 加热段（配合 `fKp` 负值反作用）；高于 `fSplitHigh` → 冷却段；两点之间为中性带（双通道全关热平衡保持）。`fSplitLow=0` 加热通道自动禁用、`fSplitHigh=100` 冷却通道自动禁用（防除零）。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 9.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `fTempSetpoint` | `REAL` | IN | `0.0` | 目标温度 [°C]，经 `fTempMin/Max` 钳位后生效 / Setpoint, clamped by bounds |
| `fTempMin` | `REAL` | IN | `0.0` | 设定值下边界 [°C] / Setpoint lower bound |
| `fTempMax` | `REAL` | IN | `300.0` | 设定值上边界 [°C] / Setpoint upper bound |
| `fSplitLow` | `REAL` | IN | `50.0` | 分程下切换点 [%]，PID 输出低于此点进入加热段 / Split-range low crossover |
| `fSplitHigh` | `REAL` | IN | `50.0` | 分程上切换点 [%]，高于此点进入冷却段 / Split-range high crossover |
| `eBreakAction` | `E_DL_BreakAction` | IN | `eHeatOff` | 断偶动作方向：`eHeatOff`=切断加热 / `eCoolOff`=切断冷却，按对象安全策略 / Break action per safety policy |
| `bEnable` | `BOOL` | IN | `FALSE` | 投运使能，与 `CmdEnable` 方法锁存值取与 / Zone enable, ANDed with method latch |
| `tSampleTime` | `TIME` | IN | `T#100MS` | 采样周期，下传注入的 PID 与两路 PWM（公约 0.5）/ Sample time passed to injected instances |
| `bTrack` | `BOOL` | IN | `FALSE` | 跟踪使能，TRUE 时输出跟随 `fTrackValue` 无扰接管 / Track enable for bumpless takeover |
| `fTrackValue` | `REAL` | IN | `0.0` | 跟踪值 [-100..100 %] / Track value |
| `iTempSensor` | `I_DL_AnalogSensor` | IN_OUT | — | 温度信号源接口引用，上层注入 `FB_DL_AnalogTransmitter` 实例 / Sensor interface reference |
| `fbPid` | `FB_DL_PidController` | IN_OUT | — | 温度 PID 实例，增益/积分/限幅由调用方组态 / Injected PID instance |
| `fbPwmHeat` | `FB_DL_PwmDutyController` | IN_OUT | — | 加热 SSR PWM 实例 / Injected heat PWM instance |
| `fbPwmCool` | `FB_DL_PwmDutyController` | IN_OUT | — | 冷却 SSR PWM 实例 / Injected cool PWM instance |
| `bHeaterOut` | `BOOL` | OUT | — | 加热执行通道镜像（等于加热 PWM 布尔输出）/ Heater channel mirror |
| `bCoolerOut` | `BOOL` | OUT | — | 冷却执行通道镜像 / Cooler channel mirror |
| `fTempActual` / `fPowerOut` / `eState` / `bFault` / `uErrorId` | 见 §8.1 | GET 属性 | — | 接口属性映射（属性即输出引脚语义，R11 留档 D1）/ Interface property mapping |

> **枚举** `E_DL_BreakAction`（随本文件发布）：`eHeatOff=0` 断偶切断加热（超温风险侧）/ `eCoolOff=1` 断偶切断冷却（防脆断工艺侧）。

### 9.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0211` | 故障级 / Fault | 传感器断线/开路锁存 / Sensor break latched | `CmdReset` 且质量恢复 `eGood` 后方可清 |
| `16#0003_0212` | 故障级 / Fault | 非法状态兜底（CASE ELSE 落点）/ Illegal state fallback | `CmdReset` 可清 |
| `16#0003_0213` | 故障级 / Fault | 温度传感器接口引用未注入/无效 / Sensor interface reference invalid | 注入 `iTempSensor` 后复位 |
| `16#0003_0101` | 信息级 / Info | 参数钳位/对调修复/设定值钳位提示（不置故障）/ Parameter clamp or swap repair | 核对组态参数 |

### 9.3 调用示例 / Call Example

```iecst
VAR
    fbPidZone   : FB_DL_PidController;    // PID 实例（组态 fKp 负值反作用）/ PID instance
    fbPwmH      : FB_DL_PwmDutyController;// 加热 PWM / Heat PWM
    fbPwmC      : FB_DL_PwmDutyController;// 冷却 PWM / Cool PWM
    fbZone      : FB_DL_HeatCoolZone;     // 温控区 / Zone controller
END_VAR

// 组态期：fTempSetpoint 经 fTempMin/Max 钳位；PID/PWM 参数在实例上组态
fbZone(fTempSetpoint := 85.0,
       fTempMin := 20.0, fTempMax := 150.0,
       fSplitLow := 50.0, fSplitHigh := 50.0,
       eBreakAction := E_DL_BreakAction.eHeatOff,
       bEnable := bZoneAuto,
       tSampleTime := T#100MS,
       iTempSensor := fbTx,              // fbTx : FB_DL_AnalogTransmitter / Inject sensor
       fbPid := fbPidZone,
       fbPwmHeat := fbPwmH, fbPwmCool := fbPwmC);

xSSRHeat := fbZone.bHeaterOut;           // SSR 驱动通道 / SSR channels
xSSRCool := fbZone.bCoolerOut;
```

---

## 10. 典型组态与联调要点 / Field Notes

1. **气源与磁开先于状态机**：气缸故障多为「超时」类——先查气源压力与磁开安装间隙，再怀疑状态机；`tTimeoutExt/Ret = T#0S` 会关闭自检，调试期不要长期置零。
2. **双传感器冲突是物理不可能事件**：`0003_0204` 一旦出现，优先排查磁开误接线/误信号（如光耦干扰），不要盲目复位循环。
3. **DOL 防频繁启停是保护不是故障**：`0003_0207/0208/020A` 全部为信息级，接触器本体无恙；HMI 上建议与故障级分色显示。
4. **变送器诊断在原始域判定**：断线判断永远看 `fRawInput`（mA/V 域），不要在工程量域重算一遍——工程量域判断线是 NE43 落地的常见错误。
5. **温控区三实例必须先组态后投运**：`fbPid` 增益为 0 或 PWM 周期为 0 的区投运 = 恒温失效；建议先 `bTrack` 无扰接管手动输出验证通道极性，再闭环。
6. **断偶安全方向按对象定**：升温超温风险对象配 `eHeatOff`；骤冷致脆断的工艺（如玻璃退火）配 `eCoolOff`——选错方向会把保护变成事故。

---

## 11. FB_DL_SingleSolenoidCyl ｜ 单电控弹簧复位气缸驱动功能块（R6）

**功能 / 中文**：单电控（单线圈）弹簧复位气缸驱动，复用既有 `I_DL_Cylinder` 契约。得电伸出、失电弹簧缩回；支持「纯时间模式」（无传感器，按行程时间判定到位）与「反馈校验模式」（时间 + 磁性开关双重校验）。联锁失电保位、行程计数。
**Function**: Single-solenoid spring-return cylinder driver reusing the `I_DL_Cylinder` contract. Energize to extend, spring return on drop; pure time mode or dual time+reed check mode.

### 11.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 说明 / Description |
|---|---|---|---|---|
| `bCmdExtend` | `BOOL` | IN | — | 伸出指令，电平 OR 上升沿双通道受理；失电即弹簧缩回 / Extend command, coil drop means spring return |
| `bSnsExtended` | `BOOL` | IN | — | 可选伸出到位磁性开关，TRUE=到位；未接时恒 FALSE / Optional extended reed switch |
| `bSnsRetracted` | `BOOL` | IN | — | 可选缩回到位磁性开关，TRUE=到位 / Optional retracted reed switch |
| `bUseSensorCheck` | `BOOL` | IN | — | 反馈校验使能，TRUE=时间+磁开双重校验；FALSE=纯时间模式 / Sensor check enable |
| `bInterlock` | `BOOL` | IN | — | 允许动作联锁，TRUE=允许伸出，默认 FALSE 线圈保持断开 / Motion interlock |
| `tStrokeTimeExt` | `TIME` | IN | `T#1S` | 伸出行程时间，纯时间模式据此判定到位 / Extend stroke time |
| `tStrokeTimeRet` | `TIME` | IN | `T#1S` | 弹簧缩回行程时间 / Spring return stroke time |
| `tTimeoutExt` | `TIME` | IN | `T#3S` | 伸出到位超时（磁开确认窗口），T#0S=禁用自检 / Extend timeout, T#0S disables |
| `tDebounce` | `TIME` | IN | `T#20MS` | 磁开防抖窗口，T#0S=直通 / Reed debounce window |
| `bReset` | `BOOL` | IN | — | 故障复位，上升沿生效 / Fault reset |
| `bSolenoidExt` | `BOOL` | OUT | — | 伸出线圈输出，得电伸出 / 失电弹簧缩回 / Extend solenoid coil |
| `bMoving` | `BOOL` | OUT | — | 运动中指示 / Moving indicator |
| `uCycleCount` | `UDINT` | OUT | — | 行程计数，缩回判定沿 +1 / Stroke count |

接口属性（`I_DL_Cylinder`，只读 PROPERTY GET）：`eState : E_DL_CylinderState`、`bExtended : BOOL`、`bRetracted : BOOL`、`bFault : BOOL`、`uErrorId : UDINT`；方法：`CmdExtend / CmdRetract / CmdStop / CmdReset`（故障态拒绝）。方法请求与引脚指令并存时方法请求优先（单发语义）。

### 11.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0220` | 故障级 | 伸出到位超时（磁开窗内未确认） |
| `0003_0221` | 故障级 | 反馈校验失败（缩回时间到位但磁开超窗未确认） |
| `0003_0222` | 故障级 | 非法状态兜底 |

### 11.3 调用示例 / Call Example

```iecst
fbCyl1(bCmdExtend := bGoDown, bSnsExtended := xLimDown, bSnsRetracted := xLimUp,
       bUseSensorCheck := TRUE, bInterlock := NOT bDoorOpen,
       tStrokeTimeExt := T#800MS, tStrokeTimeRet := T#500MS);
```

---

## 12. I_DL_VacuumGenerator ｜ 真空发生器标准接口（R6）

**功能 / 中文**：真空发生器（负压吸盘供气）标准抽象契约。状态枚举 `E_DL_VacuumState` 随本文件发布：`eIdle(0) / eEvacuating(10) / eVacuumOk(20) / eBlowing(30) / eFault(99)`。DL_Process 拾放工站的依赖注入件。
**Function**: Standard vacuum generator contract with `E_DL_VacuumState` shipped in the same file; the injection point for pick-and-place stations.

### 12.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 成员 | 类型 | 说明 / Description |
|---|---|---|
| `eState` | `E_DL_VacuumState` | 当前状态机状态 / Current state |
| `bVacuumOk` | `BOOL` | 真空建立确认，TRUE=吸附保持中 / Vacuum established and holding |
| `fPressure` | `REAL` | 负压反馈值 [kPa]，0=大气压，负值=真空度 / Pressure feedback [kPa] |
| `bFault` | `BOOL` | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | 末次故障码，0=无故障，段位 `16#0003_xxxx` / Last error code |

### 12.2 方法 / Methods

| 方法 | 返回 | 说明 / Description |
|---|---|---|
| `CmdEvacuate() : BOOL` | 受理结果 | 建立真空指令，单发；故障态拒绝返回 FALSE / Evacuate command |
| `CmdBlowOff() : BOOL` | 受理结果 | 破真空吹气指令，单发，实现块输出定宽脉冲 / One-shot blow-off |
| `CmdStop() : BOOL` | 受理结果 | 双阀全断保持现状；故障态拒绝 / Stop, both valves off |
| `CmdReset() : BOOL` | 受理结果 | 复位指令，返回是否可复位 / Reset command |

---

## 13. FB_DL_VacuumEjector ｜ 真空发生器驱动功能块（R6，v1.0.1）

**功能 / 中文**：真空发生器驱动（实现 `I_DL_VacuumGenerator`）。负压域施密特迟滞判定（建立判据 ≤ 设定值、保持判据放宽迟滞量）、建立超时、破真空 TP 定宽吹气脉冲（吹气期间强制真空阀断）、可选真空开关双确认、反馈失效保持末次有效值。
**Function**: Vacuum ejector implementing `I_DL_VacuumGenerator`, with negative-pressure hysteresis, establish timeout, fixed-width TP blow-off pulse and optional dual confirmation.

### 13.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bCmdEvacuate` | `BOOL` | IN | — | — | 建立真空指令，上升沿生效 / Evacuate command |
| `bCmdBlowOff` | `BOOL` | IN | — | — | 破真空吹气指令，上升沿生效，输出 `tBlowPulse` 定宽脉冲 / Blow-off command |
| `fPressureFeedback` | `REAL` | IN | — | kPa | 负压表反馈，0=大气，负值=真空度；非有限值防御 / Pressure feedback |
| `bFbVacuumSwitch` | `BOOL` | IN | — | — | 可选真空开关反馈，TRUE=真空确认 / Optional vacuum switch feedback |
| `bUseSensorCheck` | `BOOL` | IN | — | — | 开关反馈校验使能，TRUE=负压阈值+开关双确认 / Sensor check enable |
| `fVacuumSetpoint` | `REAL` | IN | `-60.0` | kPa | 真空建立阈值（负压域）/ Vacuum setpoint |
| `fVacuumHysteresis` | `REAL` | IN | `5.0` | kPa | 真空判定迟滞（保持判据放宽量，负值防御钳零）/ Hysteresis band |
| `tEstablishTimeout` | `TIME` | IN | `T#5S` | — | 真空建立超时，T#0S=禁用 / Establish timeout |
| `tBlowPulse` | `TIME` | IN | `T#500MS` | — | 破真空吹气脉冲宽度 / Blow-off pulse width |
| `tDebounce` | `TIME` | IN | `T#20MS` | — | 开关反馈防抖，T#0S=直通 / Switch debounce |
| `bReset` | `BOOL` | IN | — | — | 故障复位，上升沿生效 / Fault reset |
| `bVacuumValve` | `BOOL` | OUT | — | — | 真空电磁阀输出，TRUE=抽真空 / Vacuum solenoid valve |
| `bBlowValve` | `BOOL` | OUT | — | — | 破真空吹气阀输出，定宽脉冲 / Blow-off solenoid valve |
| `bHolding` | `BOOL` | OUT | — | — | 吸附保持中指示，真空确认态为 TRUE / Holding indicator |

接口属性（只读 PROPERTY GET）：`eState / bVacuumOk / fPressure / bFault / uErrorId`；方法：`CmdEvacuate / CmdBlowOff / CmdStop / CmdReset`。

### 13.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0230` | 故障级 | 负压反馈信号无效（非有限值/失效） |
| `0003_0231` | 故障级 | 真空建立超时 / 反馈校验失败 |
| `0003_0232` | 故障级 | 非法状态兜底 |

### 13.3 调用示例 / Call Example

```iecst
fbVacuum(bCmdEvacuate := bPickReq, bCmdBlowOff := bDropReq,
         fPressureFeedback := fVacKpa, bFbVacuumSwitch := xVacSw, bUseSensorCheck := TRUE,
         fVacuumSetpoint := -65.0, fVacuumHysteresis := 8.0, tBlowPulse := T#300MS);
IF fbVacuum.bVacuumOk THEN bGripperClose := TRUE; END_IF
```

---

## 14. FB_DL_StarDeltaMotor ｜ 星三角降压启动电机控制功能块（R6，v1.0.1）

**功能 / 中文**：星三角降压启动（三接触器）。星角切换死区时间互锁（星线圈分断 → 死区计时（此窗角线圈严禁输出）→ 星反馈确认分断 → 角指令 → 角反馈窗）；三路接触器反馈校验；星角互斥出口断言；热继过载锁存；重启抑制冷却（复用 DOL 电机范式）。复用既有 `E_DL_MotorState` 枚举。
**Function**: Star-delta starter with dead-time interlock, three-contactor feedback checks, exclusivity assertion, overload latch and restart inhibit. Reuses `E_DL_MotorState`.

### 14.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 说明 / Description |
|---|---|---|---|---|
| `bCmdStart` | `BOOL` | IN | — | 启动指令，上升沿生效 / Start command |
| `bCmdStop` | `BOOL` | IN | — | 停止指令，电平生效 / Stop command |
| `bFbMain` | `BOOL` | IN | — | 主接触器反馈，TRUE=吸合 / Main contactor feedback |
| `bFbStar` | `BOOL` | IN | — | 星形接触器反馈 / Star contactor feedback |
| `bFbDelta` | `BOOL` | IN | — | 三角形接触器反馈 / Delta contactor feedback |
| `bThermalOverload` | `BOOL` | IN | — | 热继电器过载信号，TRUE=过载 / Thermal overload trip |
| `bPermitStart` | `BOOL` | IN | — | 启动允许联锁，TRUE=允许 / Start permit |
| `tStarTime` | `TIME` | IN | `T#5S` | 星形运行时间，按负载实测加速时间整定 / Star run time |
| `tDeadTime` | `TIME` | IN | `T#100MS` | 星角转换死区时间，域 50~200MS，星分断后角方可吸合 / Transition dead time |
| `tFbWindow` | `TIME` | IN | `T#500MS` | 指令-反馈校验窗口，T#0S=免校验 / Feedback check window |
| `tRestartInhibit` | `TIME` | IN | `T#60S` | 重启抑制冷却时间 / Restart inhibit |
| `bReset` | `BOOL` | IN | — | 故障复位，上升沿生效 / Fault reset |
| `bMainContactor` | `BOOL` | OUT | — | 主接触器线圈输出，星形与运行期全程吸合 / Main contactor coil |
| `bStarContactor` | `BOOL` | OUT | — | 星形接触器线圈输出，仅星形降压段吸合 / Star contactor coil |
| `bDeltaContactor` | `BOOL` | OUT | — | 三角形接触器线圈输出，死区满后吸合 / Delta contactor coil |
| `eState` | `E_DL_MotorState` | OUT | — | 当前状态机状态（复用既有枚举）/ Current state |
| `bRunning` | `BOOL` | OUT | — | 运行反馈，角接触器吸合确认 / Running feedback |
| `bFault` | `BOOL` | OUT | — | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | OUT | — | 末次故障码，段位 `16#0003_xxxx` / Last error code |
| `bRestartInhibit` | `BOOL` | OUT | — | 重启抑制激活中，TRUE=冷却期拒绝启动 / Restart inhibit active |
| `bStarPhase` | `BOOL` | OUT | — | 星形阶段指示，调试/HMI 用 / Star phase indicator |
| `uStartCount` | `UDINT` | OUT | — | 累计启动次数 / Start count |

### 14.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0208` | 信息级 | 重启抑制期启动拒绝（与 `FB_DL_DolMotor` 同码同义共用，终审归一裁定） |
| `0003_0240` | 故障级 | 主接触器拒动（校验窗内未吸合） |
| `0003_0241` | 故障级 | 星接触器拒动 |
| `0003_0242` | 故障级 | 星接触器分断失败（死区满仍吸合） |
| `0003_0243` | 故障级 | 星角互斥冲突（出口断言对触发） |
| `0003_0244` | 故障级 | 运行中反馈意外断开（失反馈脱扣） |
| `0003_0245` | 故障级 | 热继电器过载脱扣（锁存） |
| `0003_0246` | 故障级 | 星角转换失败（角接触器窗内未吸合） |

### 14.3 调用示例 / Call Example

```iecst
fbPumpSD(bCmdStart := bStartPump, bCmdStop := bStopPump,
         bFbMain := xKm1, bFbStar := xKmY, bFbDelta := xKmD,
         bThermalOverload := xF49, bPermitStart := bNoFault,
         tStarTime := T#6S, tDeadTime := T#80MS);
bKm1 := fbPumpSD.bMainContactor;
bKmY := fbPumpSD.bStarContactor;
bKmD := fbPumpSD.bDeltaContactor;
```

---

## 15. I_DL_VfdDrive ｜ 通用变频器标准接口（R6）

**功能 / 中文**：通用变频器抽象契约（端子型/通信型均可适配），风机泵类与输送线的驱动底座。状态枚举 `E_DL_VfdState` 随本文件发布：`eDisabled(0) / eReady(10) / eRunningFwd(20) / eRunningRev(30) / eJogging(40) / eFault(99)`。
**Function**: Generic VFD contract for terminal-type and bus-type drives; the base of fan/pump and conveyor drivers. `E_DL_VfdState` shipped in the same file.

### 15.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 成员 | 类型 | 说明 / Description |
|---|---|---|
| `eState` | `E_DL_VfdState` | 当前状态机状态 / Current state |
| `fFreqSetpoint` | `REAL` | 频率设定 [Hz]，钳位后生效值 / Effective frequency setpoint [Hz] |
| `fFreqActual` | `REAL` | 频率反馈 [Hz]，非有限值时保持末次有效值 / Frequency feedback [Hz] |
| `bRunning` | `BOOL` | 运行反馈，正转/反转/点动态输出运行中 / Running feedback |
| `bFault` | `BOOL` | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | 末次故障码，0=无故障，段位 `16#0003_xxxx` / Last error code |

### 15.2 方法 / Methods（共 6 个，达 ≤6 红线临界）

| 方法 | 返回 | 说明 / Description |
|---|---|---|
| `CmdRun(bFwd : BOOL) : BOOL` | 受理结果 | 正/反转运行指令（TRUE 正转 / FALSE 反转），电平语义受理为保持锁存；故障态拒绝 / Run command |
| `CmdStop() : BOOL` | 受理结果 | 撤销运行/点动锁存；无条件受理 / Stop command |
| `CmdJog(bFwd : BOOL) : BOOL` | 受理结果 | 点动指令，优先级高于运行；故障态拒绝 / Jog command |
| `SetFrequency(fHz : REAL) : BOOL` | 合法性 | 频率设定 [Hz]，越界/非有限值拒绝返回 FALSE / Frequency set |
| `SelectPresetSpeed(nIdx : USINT) : BOOL` | 合法性 | 多段速选择，0=模拟量给定、1..7=段速；越界拒绝 / Preset select |
| `CmdReset() : BOOL` | 受理结果 | 复位指令 / Reset command |

---

## 16. FB_DL_VfdGeneric ｜ 通用端子型变频器驱动功能块（R6，v1.0.1）

**功能 / 中文**：通用端子型变频器驱动（实现 `I_DL_VfdDrive`）。正反转端子互斥（同拍冲突安全侧停止）、点动优先、多段速选择（段速表引脚注入）、频率模拟量给定 0~100% 线性映射、故障复位端子定宽脉冲（R24 修后时序）。
**Function**: Terminal-type VFD driver implementing `I_DL_VfdDrive` with forward/reverse interlock, jog priority, preset-speed table and a fixed-width fault-reset pulse.

### 16.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bDriveEnable` | `BOOL` | IN | — | — | 驱动使能/上电，FALSE → 未使能态全部输出切断 / Drive enable |
| `bCmdRunFwd` | `BOOL` | IN | — | — | 正转运行指令，电平生效 / Run forward command |
| `bCmdRunRev` | `BOOL` | IN | — | — | 反转运行指令，与正转同拍为真 → 冲突安全侧停止 / Run reverse command |
| `bCmdJogFwd` | `BOOL` | IN | — | — | 正向点动指令，电平生效，优先级高于运行指令；点动频率不切换通道（可现场将段速 1 整定为点动频率域）/ Jog forward command |
| `bFbRunning` | `BOOL` | IN | — | — | 运行反馈，TRUE=驱动输出运行中 / Running feedback |
| `bFbFault` | `BOOL` | IN | — | — | 驱动故障反馈，TRUE=故障 / Drive fault feedback |
| `bFbAtSpeed` | `BOOL` | IN | — | — | 频率到达反馈 / At-speed feedback |
| `fFreqCmd` | `REAL` | IN | — | Hz | 频率设定，0..`fFreqMax`，越界钳位信息级 / Frequency command [Hz] |
| `fFreqActual` | `REAL` | IN | — | Hz | 频率反馈，非有限值防御 / Frequency feedback [Hz] |
| `aPresetFreq` | `ARRAY[1..7] OF REAL` | IN | — | Hz | 多段速频率表，段速值由现场整定注入 / Preset speed table [Hz] |
| `nPresetSel` | `USINT` | IN | — | — | 段速选择，0=模拟量给定、1..7=段速，越界按 0 处理并置码 / Preset select |
| `fFreqMax` | `REAL` | IN | `50.0` | Hz | 频率上限 / Maximum frequency [Hz] |
| `tFbWindow` | `TIME` | IN | `T#1S` | — | 指令-反馈校验窗口，T#0S=免校验 / Feedback check window |
| `tFaultResetPulse` | `TIME` | IN | `T#500MS` | — | 故障复位脉冲宽度 / Fault reset pulse width |
| `bReset` | `BOOL` | IN | — | — | 故障复位请求，上升沿生效 / Fault reset request |
| `bRunFwdOut` | `BOOL` | OUT | — | — | 正转端子输出 / Run forward terminal |
| `bRunRevOut` | `BOOL` | OUT | — | — | 反转端子输出 / Run reverse terminal |
| `bJogOut` | `BOOL` | OUT | — | — | 点动端子输出 / Jog terminal |
| `bFaultResetOut` | `BOOL` | OUT | — | — | 故障复位端子输出，`tFaultResetPulse` 定宽单发 / Fault reset terminal |
| `fFreqRefPercent` | `REAL` | OUT | — | % | 频率给定模拟量输出，0~100 线性映射 `fFreqMax` / Analog frequency reference [%] |
| `uPresetCode` | `USINT` | OUT | — | — | 段速选择码输出，映射 DI 多段速端子组合 0..7 / Preset speed code |

接口属性（只读 PROPERTY GET）：`eState / fFreqSetpoint / fFreqActual / bRunning / bFault / uErrorId`；方法：`CmdRun / CmdStop / CmdJog / SetFrequency / SelectPresetSpeed / CmdReset`。

### 16.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0106` | 信息级 | 正反转指令冲突（冲突安全侧停止） |
| `0003_0107` | 信息级 | 频率设定钳位 / 段速选择越界（按 0 处理） |
| `0003_0250` | 故障级 | 驱动故障（反馈锁存） |
| `0003_0251` | 故障级 | 启动反馈超时 |
| `0003_0252` | 故障级 | 非法状态兜底 |

### 16.3 调用示例 / Call Example

```iecst
fbFanVfd(bDriveEnable := bPwrOK, bCmdRunFwd := bRunFan,
         bFbRunning := xRunFb, bFbFault := xVfdFault, bFbAtSpeed := xAtSpd,
         fFreqCmd := fSpeedCmd, fFreqActual := fFbHz, nPresetSel := 0,
         fFreqMax := 50.0, tFbWindow := T#1S);
fFanPct := fbFanVfd.fFreqRefPercent;   // 模拟量给定域 / Analog reference domain
```

---

## 17. I_DL_ProportionalValve ｜ 比例调节阀标准接口（R6）

**功能 / 中文**：模拟量比例阀/调节阀（开度指令-反馈型）抽象契约。状态枚举 `E_DL_ValveState` 随本文件发布：`eIdle(0) / eModulating(10) / eFault(99)`。
**Function**: Proportional valve contract with `E_DL_ValveState` shipped in the same file.

### 17.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 成员 | 类型 | 说明 / Description |
|---|---|---|
| `eState` | `E_DL_ValveState` | 当前状态机状态 / Current state |
| `fPosCmd` | `REAL` | 当前阀位指令 [%]，整形钳位后生效值 / Effective position command [%] |
| `fPosFeedback` | `REAL` | 阀位反馈 [%]，非有限值时保持末次有效值 / Position feedback [%] |
| `bDeviationAlarm` | `BOOL` | 偏差报警激活中，瞬时型每拍重算 / Transient deviation alarm |
| `bFault` | `BOOL` | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | 末次事件码，0=无，段位 `16#0003_xxxx` / Last event code |

### 17.2 方法 / Methods

| 方法 | 返回 | 说明 / Description |
|---|---|---|
| `SetPosition(fPos : REAL) : BOOL` | 合法性 | 阀位指令设定 [%]，越界/非有限值拒绝返回 FALSE / Position set [%] |
| `CmdStop() : BOOL` | 受理结果 | 冻结输出保持当前阀位，直至下次设定或使能撤除；故障态拒绝 / Freeze output |
| `CmdReset() : BOOL` | 受理结果 | 复位指令，返回是否可复位 / Reset command |

---

## 18. FB_DL_AnalogValve ｜ 模拟量调节阀指令整形功能块（R6，v1.0.1）

**功能 / 中文**：模拟量调节阀指令整形层（实现 `I_DL_ProportionalValve`）。透传 + 补偿链：设定钳位 [0,100] → 零点死区补偿 → 限幅域映射（对调自修复）→ 阀位指令输出；偏差延时报警；反馈失效保持末次有效值。**不含阀位闭环**（闭环由驱动器/上层 PID 完成，本块为指令整形与诊断层）。
**Function**: Analog valve command-shaping layer implementing `I_DL_ProportionalValve`; shaping chain without closed-loop position control.

### 18.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `fPosSetpoint` | `REAL` | IN | — | % | 阀位设定，0..100，越界钳位信息级 / Position setpoint [%] |
| `fPosFeedback` | `REAL` | IN | — | % | 阀位反馈，来自阀位变送器；非有限值防御 / Position feedback [%] |
| `fZeroDeadband` | `REAL` | IN | `0.5` | % | 零点死区补偿，输出小于此值钳为 0 防阀芯微抖 / Zero deadband [%] |
| `fDeviationLimit` | `REAL` | IN | `5.0` | % | 偏差报警门限 / Deviation alarm limit [%] |
| `tDeviationDelay` | `TIME` | IN | `T#10S` | — | 偏差报警确认延时，防动态调节过程误报 / Deviation delay |
| `fOutMin` | `REAL` | IN | `0.0` | % | 输出限幅域下端点，对调自修复 / Output span low endpoint [%] |
| `fOutMax` | `REAL` | IN | `100.0` | % | 输出限幅域上端点，对调自修复 / Output span high endpoint [%] |
| `bEnable` | `BOOL` | IN | — | — | 调节使能，FALSE 时输出冻结保持 / Modulating enable |
| `bReset` | `BOOL` | IN | — | — | 故障复位，上升沿生效 / Fault reset |
| `fPosOutput` | `REAL` | OUT | — | % | 阀位指令输出，死区补偿+限幅域映射后，量纲=限幅域 / Shaped position output [%] |

接口属性（只读 PROPERTY GET）：`eState / fPosCmd / fPosFeedback / bDeviationAlarm / bFault / uErrorId`；方法：`SetPosition / CmdStop / CmdReset`。

### 18.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0108` | 信息级 | 设定值钳位 |
| `0003_0109` | 信息级 | 输出限幅域对调自修复 |
| `0003_0112` | 信息级 | 偏差报警激活（瞬时型每拍重算） |
| `0003_0260` | 故障级 | 阀位反馈信号无效 |
| `0003_0261` | 故障级 | 非法状态兜底 |

### 18.3 调用示例 / Call Example

```iecst
fbDampValve(fPosSetpoint := fbEco.fOaDamperCmd,   // 可直接接焓差块输出 / chain to economizer
            fPosFeedback := fPosFbPct, fZeroDeadband := 0.8,
            fDeviationLimit := 6.0, tDeviationDelay := T#15S, bEnable := bAuto);
fDamperCmd := fbDampValve.fPosOutput;
```

---

## 19. I_DL_MotorizedValve ｜ 电动调节阀标准接口（R6）

**功能 / 中文**：电动调节阀（开/关脉冲输出、无阀位变送器）抽象契约。状态枚举 `E_DL_MotorValveState` 随本文件发布：`eIdle(0) / eOpening(10) / eClosing(20) / eOpened(30) / eClosed(40) / eFault(99)`。
**Function**: Motorized valve contract (pulse outputs, no transmitter) with `E_DL_MotorValveState` shipped in the same file.

### 19.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 成员 | 类型 | 说明 / Description |
|---|---|---|
| `eState` | `E_DL_MotorValveState` | 当前状态机状态 / Current state |
| `fPosEstimate` | `REAL` | 估算开度 [%]，0~100，由行程时间积分自动估算 / Estimated position [%] |
| `bLimOpen` | `BOOL` | 全开限位反馈，TRUE=已到全开端点 / Open limit feedback |
| `bLimClosed` | `BOOL` | 全关限位反馈，TRUE=已到全关端点 / Closed limit feedback |
| `bFault` | `BOOL` | 故障锁存中 / Fault latched |
| `uErrorId` | `UDINT` | 末次事件码，0=无，段位 `16#0003_xxxx` / Last event code |

### 19.2 方法 / Methods

| 方法 | 返回 | 说明 / Description |
|---|---|---|
| `CmdOpen() : BOOL` | 受理结果 | 开阀指令，电平语义受理为保持锁存；故障态拒绝 / Open command |
| `CmdClose() : BOOL` | 受理结果 | 关阀指令，电平语义受理为保持锁存；故障态拒绝 / Close command |
| `CmdStop() : BOOL` | 受理结果 | 双脉冲全断保持；无条件受理 / Stop command |
| `CmdReset() : BOOL` | 受理结果 | 复位指令，返回是否可复位 / Reset command |

> 已在端点（限位确认）的指令受理但由实现块拒绝执行并置信息级——「端点指令拒绝」语义。

---

## 20. FB_DL_ThreePointValve ｜ 三点浮点式电动阀控制功能块（R6，v1.0.1）

**功能 / 中文**：三点浮点式电动调节阀控制器（实现 `I_DL_MotorizedValve`）。开/关双脉冲输出；按行程时间积分自动估算当前开度百分比；端点双保险（限位锚定 + 无限位端点拒绝）；估算-限位一致性监视；双向冲突拒绝；跟踪重同步。开度估算为连续量，设首扫标志（R19 范式）。
**Function**: Three-point floating valve controller implementing `I_DL_MotorizedValve`, with stroke-time position estimation, dual endpoint protection and consistency monitoring.

### 20.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bCmdOpen` | `BOOL` | IN | — | — | 开阀指令，电平生效 / Open command |
| `bCmdClose` | `BOOL` | IN | — | — | 关阀指令，与开同拍为真 → 停止 + 信息级 / Close command |
| `bLimOpen` | `BOOL` | IN | — | — | 全开限位开关，TRUE=已到全开端点 / Open limit switch |
| `bLimClosed` | `BOOL` | IN | — | — | 全关限位开关，TRUE=已到全关端点 / Closed limit switch |
| `tStrokeOpen` | `TIME` | IN | `T#60S` | — | 全行程开启时间，现场实测注入 / Full-open stroke time |
| `tStrokeClose` | `TIME` | IN | `T#60S` | — | 全行程关闭时间，现场实测注入 / Full-close stroke time |
| `fEstimateTol` | `REAL` | IN | `10.0` | % | 估算-限位一致性容差 / Estimate tolerance [%] |
| `bEnable` | `BOOL` | IN | — | — | 允许动作联锁，TRUE=允许发脉冲 / Motion interlock |
| `bReset` | `BOOL` | IN | — | — | 故障复位，上升沿生效 / Fault reset |
| `bTrack` | `BOOL` | IN | — | — | 跟踪重同步，TRUE 拍按限位状态重推初值 / Track resync |
| `bOpenPulse` | `BOOL` | OUT | — | — | 开阀脉冲输出 / Open pulse output |
| `bClosePulse` | `BOOL` | OUT | — | — | 关阀脉冲输出 / Close pulse output |
| `fPosEstimate` | `REAL` | OUT | — | % | 估算开度，0~100，行程时间积分 / Estimated position [%] |
| `bOpened` | `BOOL` | OUT | — | — | 全开确认，限位优先 / Fully opened |
| `bClosed` | `BOOL` | OUT | — | — | 全关确认，限位优先 / Fully closed |
| `uTravelCount` | `UDINT` | OUT | — | — | 全行程计数，全关确认沿 +1 / Travel count |

接口属性（只读 PROPERTY GET）：`eState / fPosEstimate / bLimOpen / bLimClosed / bFault / uErrorId`；方法：`CmdOpen / CmdClose / CmdStop / CmdReset`。

### 20.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0110` | 信息级 | 端点指令拒绝（限位确认端点 / 无限位端点双保险②） |
| `0003_0111` | 信息级 | 开/关双向指令冲突（双脉冲全断） |
| `0003_0270` | 故障级 | 行程估算失准（估算与限位矛盾超容差） |
| `0003_0271` | 故障级 | 双限位冲突（物理不可能） |
| `0003_0272` | 故障级 | 非法状态兜底 |

### 20.3 调用示例 / Call Example

```iecst
fbMixValve(bCmdOpen := bOpenMix, bCmdClose := bCloseMix,
           bLimOpen := xLimOpen, bLimClosed := xLimClose,
           tStrokeOpen := T#90S, tStrokeClose := T#90S, bEnable := bAuto);
fMixPosPct := fbMixValve.fPosEstimate;   // HMI 开度显示 / HMI position display
```

---

## 21. R6 阀门/变频族选型与联调要点 / R6 Valve & VFD Field Notes

1. **阀门三分法选型口诀**：有阀位变送器/定位器 → `FB_DL_AnalogValve`（指令整形，闭环外置）；只有开/关脉冲与双限位 → `FB_DL_ThreePointValve`（开度积分估算）；真空吸附 → `FB_DL_VacuumEjector`。
2. **行程时间必须现场实测**：`tStrokeOpen/Close` 默认值 60 s 仅为占位——估算开度的全部精度都建立在实测行程时间上；整定错误的表现是 `0003_0270` 行程估算失准。
3. **变频器正反转冲突是安全侧停止**：`0003_0106` 出现时输出已全断，先查指令源互锁再复位；`tFaultResetPulse` 复位脉冲是自动重试手段，反复复位说明驱动器本体有故障。
4. **真空负压域注意符号**：`fPressureFeedback` 负值=真空度，设定值默认 -60 kPa——把正压值填进设定域会立即「建立成功」假象，接线/变送器方向先确认。
5. **R24 定宽脉冲纪律**：`FB_DL_VacuumEjector` 吹气与 `FB_DL_VfdGeneric` 复位端子的定宽脉冲均按「触发请求置位在前、实例调用在中、自清在后」时序实现——自研同类脉冲时必须遵守同一范式（R24），否则脉冲永不触发。

---

## 22. I_DL_BarcodeScanner ｜ 固定式扫码枪标准接口（R7）

**功能**：工业固定式扫码枪标准抽象契约，路由分拣、批次追溯、上下料校验等 DL_Process 模板的依赖注入件。定义状态读取属性组（GET）与触发/应答/复位方法组；串口/总线收发与数据本体由实现块经 IN_OUT 引脚注入，接口层不做任何串口收发与过程映像读写。

### 22.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 属性 | 类型 | 说明 |
|---|---|---|
| `eState` | E_DL_ScannerState | 当前握手状态（eIdle/eTriggered/eReading/eOk/eNoRead/eFault） |
| `bReady` | BOOL | 就绪可触发，TRUE=处于可受理触发的状态 |
| `bReadOk` | BOOL | 解码成功且结果有效，TRUE=sBarcode 有效待消费 |
| `bNoRead` | BOOL | 未读到，TRUE=重试耗尽未获得有效条码 |
| `sBarcode` | STRING(255) | 最近有效条码字符串，bReadOk=TRUE 时有效 |
| `nReadCount` | UDINT | 累计成功解码次数，复位不清零（追溯口径） |
| `bFault` / `uErrorId` | BOOL / UDINT | 故障锁存 / 末次故障码 `16#0003_xxxx` 段 |

### 22.2 方法 / Methods（共 3 个）

| 方法 | 受理条件 | 说明 |
|---|---|---|
| `CmdTrigger : BOOL` | 仅空闲态 | 触发一次解码；非空闲/故障态拒绝返回 FALSE |
| `CmdAck : BOOL` | eOk/eNoRead 态 | 应答清除结果保持位，为下一次解码前提 |
| `CmdReset : BOOL` | 仅故障态 | 复位故障 |

---

## 23. FB_DL_SerialScanner ｜ 扫码枪握手状态机实现（R7，v1.0.1）

**功能**：扫码枪触发-结果握手状态机（实现 `I_DL_BarcodeScanner`）。一次 NoRead 自动重试、二次升级故障；结果按长度校验收纳，先剥离 CR/LF 终止符再锁存；触发输出以 TP 定宽脉冲承载（R24 范式）。

### 23.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bCmdTrigger` | BOOL | 输入 | — | — | 触发指令，R_TRIG 上升沿单发 |
| `bCmdAck` | BOOL | 输入 | — | — | 应答指令，上升沿清除结果保持位 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障 |
| `bDataNew` | BOOL | 输入 | — | — | 新数据标志，接收层置位、本块消费后经 bDataAck 清除 |
| `bDevReady` | BOOL | 输入 | — | — | 扫码枪就绪反馈（可选）；恒 FALSE 时跳过就绪门控（信息级提示一次） |
| `sNoReadMark` | STRING(31) | 输入 | 'NOREAD' | — | NoRead 标记字符串，空=按超时判定 |
| `tResultWindow` | TIME | 输入 | T#1S | ms | 结果等待窗口，域 100MS~10S 越界钳位 |
| `nRetryMax` | USINT | 输入 | 1 | 次 | 最大自动重试次数，域 0~5；0=不重试 |
| `bDataAck` | BOOL | 输出 | — | — | 新数据消费应答，接收层据此清 bDataNew，置位一拍 |
| `bTriggerOut` | BOOL | 输出 | — | — | 扫码枪触发输出，TP 定宽单拍脉冲（R24） |
| `sRawData` | STRING(255) | IN_OUT | — | — | 原始接收字符串（含 CR/LF），接收层写入、本块只读 |

### 23.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0003_0117` / `0119` / `0120` | 信息级 | 单次 NoRead 提示 / 条码超长截断 / 无就绪门控跳过 |
| `16#0003_0280` | 故障级 | 连续 NoRead 超限（阈值常量 DL_CONSEC_NOREAD_MAX=3） |
| `16#0003_0281` | 故障级 | 设备长时间无就绪 |
| `16#0003_0282` | 故障级 | 非法状态兜底 |

### 23.3 调用示例 / Example

```iecst
fbScanner(bCmdTrigger := bPartAtReadPoint, bDataNew := bRxNew,
          sRawData := sRxBuffer, tResultWindow := T#1S, nRetryMax := 1);
bTxTrigger := fbScanner.bTriggerOut;    // 触发端子
IF fbScanner.bDataAck THEN bRxNew := FALSE; END_IF  // 接收层清标志
IF fbScanner.bReadOk THEN sBatchCode := fbScanner.sBarcode; fbScanner.CmdAck(); END_IF
```

### 23.4 要点 / Notes

- **v1.0.1 修复 2 处**：重试计数曾在过渡态被清零导致重试链断裂（致命——无限重发、升级故障永不触发，已移至受理处清零）；`bDataAck` 回落判据与置位同拍导致应答恒不可见（已对齐接收层握手）。
- R24 纪律：触发脉冲请求置位在前、TP 实例调用在中、自清在后——自研同类脉冲必须遵守同一范式。

---

## 24. I_DL_SafetyDoor ｜ 电磁锁扣安全门标准接口（R7）

**功能**：安全门联锁标准抽象契约。定义解锁时序状态读取属性组（GET）与请求解锁/重新闭锁/复位/审计清除方法组；电磁铁输出、反馈采集与物理输出全部由实现块完成。定位声明（公约 0.13）：逻辑编排与诊断镜像层，不构成 ISO 13849 / IEC 62061 认证安全功能。

### 24.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 属性 | 类型 | 说明 |
|---|---|---|
| `eState` | E_DL_SafetyDoorState | 解锁时序状态（eIdle/eLocked/eStopRequested/eStandstillConfirmed/eUnlocked/eOpened/eFault） |
| `bClosed` / `bLocked` / `bOpened` | BOOL | 门关闭/锁闭锁/门开启反馈镜像 |
| `bUnlockPermitted` | BOOL | 允许解锁：无故障、无重启抑制且门锁全确认 |
| `bFault` / `uErrorId` | BOOL / UDINT | 故障锁存 / 末次故障码 |

### 24.2 方法 / Methods（共 4 个）

| 方法 | 受理条件 |
|---|---|
| `CmdRequestUnlock : BOOL` | 非故障、非门开态；发起停机请求并进入解锁时序 |
| `CmdRelock : BOOL` | 门开态下关门确认后受理 |
| `CmdReset : BOOL` | 仅故障态 |
| `CmdAuditClear : BOOL` | 清除开门审计记录；故障态拒绝 |

---

## 25. FB_DL_GuardLockDoor ｜ 安全门联锁控制器（R7）

**功能**：带电磁锁扣安全门联锁（实现 `I_DL_SafetyDoor`）。时序骨架（ISO 14119 公开语义 clean-room）：请求解锁 → 停机请求输出 → 静止确认（零速反馈或 run-down 计时二选一）→ 解锁输出 → 开门审计 → 关门再锁定确认窗 → 复位后才允许重启（禁止自动重启）；防篡改冲突全局监视、解锁电磁铁出口断言式硬约束。

### 25.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bCmdUnlock` | BOOL | 输入 | — | — | 解锁请求，上升沿发起解锁时序 |
| `bCmdRelock` | BOOL | 输入 | — | — | 重新闭锁指令，电平生效 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障与重启抑制 |
| `bDoorClosed` | BOOL | 输入 | — | — | 门关闭反馈（NC 语义由接线层保证） |
| `bLockEngaged` | BOOL | 输入 | — | — | 锁闭反馈，TRUE=机械锁扣已闭 |
| `bStandstill` | BOOL | 输入 | — | — | 静止确认反馈（可选零速信号） |
| `bUseStandstillFb` | BOOL | 输入 | — | — | TRUE=用零速反馈判静止；FALSE=用 run-down 计时器 |
| `tRunDown` | TIME | 输入 | T#5S | ms | 停机走完计时；按实测最差停机时间整定，制动维护后重测 |
| `bUnlockCoil` | BOOL | 输出 | — | — | 解锁电磁铁输出（失电解锁方向，弹簧锁语义） |
| `bStopRequest` | BOOL | 输出 | — | — | 停机请求，解锁时序中置位直到静止确认 |
| `uOpenCount` | UDINT | 输出 | — | 次 | 开门次数审计，CmdAuditClear 清零 |

### 25.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0003_0121` | 信息级 | run-down 计时器模式提示（非零速实测） |
| `16#0003_0290` | 故障级 | 静止确认超时（解锁链未达成，30 s 超时） |
| `16#0003_0291` | 故障级 | 门锁不合理组合（防篡改冲突，任意态生效） |
| `16#0003_0292` | 故障级 | 再锁定超时（2 s 确认窗） |
| `16#0003_0293` | 故障级 | 非法状态兜底 |

### 25.3 要点 / Notes

- 解锁链硬约束：`bUnlockCoil` 置位前提 =（bStandstill 或 tRunDown 计满）AND bDoorClosed AND bLockEngaged，三条件不满足恒断。
- 门开 + 锁闭反馈同真是物理不可能组合，任意态立即故障锁存；复位前提是冲突源消失。
- 无任何自动重启路径：开门事件后必须 bReset 且门锁全确认才回待机/闭锁态。

---

## 26. I_DL_LightCurtain ｜ 安全光幕标准接口（R7）

**功能**：安全光幕监控与屏蔽（Muting）标准契约。OSSD 采集与屏蔽传感器接线由实现块完成，接口层不读物理输入。核心安全镜像位 `bSafeStop` 永不因屏蔽/override 置假（屏蔽态下断言恒 FALSE）。定位声明（公约 0.13）同安全门族。

### 26.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 属性 | 类型 | 说明 |
|---|---|---|
| `eState` | E_DL_CurtainState | 光幕状态（eClear/eBlocked/eMuting/eOverride/eFault） |
| `bClear` | BOOL | OSSD 双通道全通光 |
| `bMutingActive` / `bOverrideActive` | BOOL | 屏蔽进行中 / 滞留清除进行中 |
| `bSafeStop` | BOOL | 应停机输出：光幕被遮挡且未屏蔽——核心安全镜像位 |
| `bFault` / `uErrorId` | BOOL / UDINT | 故障锁存 / 末次故障码 |

### 26.2 方法 / Methods（共 3 个）

| 方法 | 受理条件 |
|---|---|
| `CmdOverride : BOOL` | 至少一个屏蔽传感器仍遮挡，否则拒绝 |
| `CmdAck : BOOL` | 屏蔽序列中止后回评估态受理 |
| `CmdReset : BOOL` | 仅故障态 |

---

## 27. FB_DL_SafetyLightCurtain ｜ 序列式屏蔽光幕控制器（R7，v1.0.1）

**功能**：光幕 OSSD 监控 + 2/4 传感器序列屏蔽状态机（SICK mut_p / 西门子 Sequential Muting 公开语义 clean-room）。序列错乱立即退出屏蔽 + 故障；屏蔽总时长超时、滞留清除 override 硬帽、OSSD 双通道容差窗、屏蔽灯（屏蔽常亮/override 闪烁）。

### 27.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bOssd1` / `bOssd2` | BOOL | 输入 | — | — | 光幕 OSSD 通道 1/2，TRUE=通光 |
| `bMutSens1..4` | BOOL | 输入 | — | — | 屏蔽传感器 1~4，TRUE=被遮挡（2 传感器模式用 1/2，4 传感器用全部） |
| `bFourSensorMode` | BOOL | 输入 | — | — | TRUE=序列式 4 传感器；FALSE=2 传感器 |
| `bEnableMuting` | BOOL | 输入 | — | — | 屏蔽总使能，FALSE=任何屏蔽条件不生效（纯防护模式） |
| `bOverrideKey` | BOOL | 输入 | — | — | 滞留清除钥匙开关，电平保持式 |
| `bReset` | BOOL | 输入 | — | — | 复位按钮，上升沿复位故障与重启联锁 |
| `tMutingTimeout` | TIME | 输入 | T#30S | ms | 屏蔽总时长上限，域 1S~600S 钳位 |
| `tDiscrepancy` | TIME | 输入 | T#3S | ms | OSSD 双通道容差窗，域 100MS~10S 钳位 |
| `tOverrideMax` | TIME | 输入 | T#30S | ms | 滞留清除硬帽，域 1S~60S 钳位 |
| `bMutingLamp` | BOOL | 输出 | — | — | 屏蔽灯：屏蔽常亮、override 闪烁 |

### 27.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0003_0118` / `0122` | 信息级 | override 硬帽到期退出 / override 准入拒绝（无遮挡） |
| `16#0003_02A0` | 故障级 | 屏蔽传感器序列错误 |
| `16#0003_02A1` | 故障级 | 屏蔽超时 |
| `16#0003_02A2` | 故障级 | OSSD 双通道不一致 |

### 27.3 要点 / Notes

- 序列语义：2 传感器 M1→M2 进入、M1→M2 清离退出；4 传感器正向 M1→M2 进入、M3→M4 离开、全清退出，反向全程镜像。方向由「首遮挡传感器」判定（M2/M4 先遮挡=反向），一经判定锁定至本序列结束（v1.0.1 修正判向死代码）。
- `bSafeStop` 出口断言：屏蔽/override 态恒 FALSE（光幕正常），永不因屏蔽置假。

---

## 28. I_DL_FlowMeter ｜ 流量计标准接口（R7）

**功能**：流量计标准抽象契约（脉冲型/模拟型均可适配）。定义瞬时流量/累计总量读取属性组与总量清零/预置/复位方法组；脉冲采集与频率估计由实现块完成。

### 28.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 属性 | 类型 | 说明 |
|---|---|---|
| `eState` | E_DL_FlowMeterState | 计量状态（eIdle/eMeasuring/eFlowOk/eLowCutoff/eFault） |
| `fFlowRate` | REAL | 瞬时流量 [L/min]，按 K 系数域换算 |
| `fTotal` | LREAL | 累计总量 [L]，LREAL 防累计精度丢失 |
| `nPulseCount` | UDINT | 窗口内脉冲计数原始值 |
| `bFault` / `uErrorId` | BOOL / UDINT | 故障锁存 / 末次故障码 |

### 28.2 方法 / Methods（共 3 个）

| 方法 | 说明 |
|---|---|
| `CmdTotalReset : BOOL` | 总量清零（批控切换零点）；故障态拒绝 |
| `CmdTotalPreset(fPreset : LREAL) : BOOL` | 总量预置，非有限值/负值拒绝 |
| `CmdReset : BOOL` | 复位故障，仅故障态受理 |

---

## 29. FB_DL_PulseFlowMeter ｜ 脉冲流量计计量块（R7）

**功能**：脉冲型流量计瞬时流量与累计总量计量（实现 `I_DL_FlowMeter`）。脉冲沿计数 → 自重触发采样窗频率估计 → K 系数换算 [L/min]；总量按脉冲计数法累计（精度优于流量积分法）+ 双缓冲读侧永不撕裂；低流量截止、脉冲丢失超时、频率超量程提示、K 系数防除零。

### 29.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bPulseIn` | BOOL | 输入 | — | — | 脉冲输入，R_TRIG 上升沿计数；硬件滤波由输入层保证 |
| `bCmdTotalReset` | BOOL | 输入 | — | — | 总量清零指令，上升沿生效 |
| `fKFactor` | REAL | 输入 | 100.0 | pulses/L | 流量计 K 系数，域 >0，标定证书值 |
| `tSampleWindow` | TIME | 输入 | T#1S | ms | 频率估计采样窗，域 100MS~10S 钳位；低流量场景增大 |
| `fLowCutoff` | REAL | 输入 | 0.5 | L/min | 低流量截止阈值，低于阈值输出置零 |
| `tPulseTimeout` | TIME | 输入 | T#5S | ms | 脉冲丢失超时，超时无脉冲流量置零 + 信息级 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障 |
| `bTotalNearLimit` | BOOL | 输出 | — | — | 总量接近溢出预警（fTotal > 9.0E15，LREAL 整数精度边界） |

### 29.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0003_0113` / `0114` / `0115` | 信息级 | 低流量截止激活 / 脉冲丢失超时 / 窗内频率超量程 |
| `16#0003_02B0` | 故障级 | K 系数非法（非有限值/趋零，锁存） |

### 29.3 要点 / Notes

- 验收向量口径：窗 1S 内 100 脉冲、K=100 → 1.0 L/min；总量 = 窗脉冲数 / K 累加。
- 双缓冲：窗运行期脉冲进计数缓冲，窗沿整窗交换到读出缓冲，读侧永不撕裂。

---

## 30. I_DL_LevelSwitch ｜ 料位开关标准接口（R7）

**功能**：料位开关标准抽象契约（振动叉/阻旋/电容等点式通用）。高点溢流与低点干转联锁的统一契约；检测本体在传感器内部，接口层不做检测算法。

### 30.1 属性 / Properties（全部只读 GET，逐字取自源码）

| 属性 | 类型 | 说明 |
|---|---|---|
| `eState` | E_DL_LevelState | 诊断状态（eNoMaterial/eMaterial/eSensorLoss/eFault） |
| `bMaterial` | BOOL | 有料判定输出，已按失效安全方向归一 |
| `bHighAlarm` | BOOL | 高点溢流联锁（fail-safe HIGH 语义：归一有料即报警） |
| `bLowAlarm` | BOOL | 低点干转联锁（fail-safe LOW 语义：归一无料即报警） |
| `bFault` / `uErrorId` | BOOL / UDINT | 故障锁存 / 末次故障码 |

### 30.2 方法与枚举 / Methods & Enums

- 方法 2 个：`CmdReset : BOOL`（仅故障态）、`CmdTest : BOOL`（功能测试，输出镜像测试态一拍）。
- 随文件枚举 2 个：`E_DL_LevelState`、`E_DL_FailSafeMode`（`eHigh`=失效报有料防溢流 ｜ `eLow`=失效报无料防干转）。

---

## 31. FB_DL_LevelSwitchVib ｜ 振动叉料位开关处理块（R7，v1.0.1）

**功能**：振动叉式料位开关信号处理（实现 `I_DL_LevelSwitch`）。原始开关防抖 → 失效安全方向归一 → 覆盖/裸露双延迟确认 → 有料/无料双联锁输出；使能切断或故障时输出强制镜像到安全侧。

### 31.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `bRawSwitch` | BOOL | 输入 | — | — | 传感器原始开关信号，TRUE=触点动作（极性按传感器定义） |
| `eFailSafeMode` | E_DL_FailSafeMode | 输入 | eHigh | — | 失效安全模式：eHigh=失效报有料（防溢流）/ eLow=失效报无料（防干转） |
| `tDebounce` | TIME | 输入 | T#200MS | ms | 防抖窗口 |
| `tCoverDelay` | TIME | 输入 | T#1S | ms | 覆盖确认延迟，防液面波动误翻转 |
| `tBareDelay` | TIME | 输入 | T#1S | ms | 裸露确认延迟 |
| `bEnable` | BOOL | 输入 | — | — | 处理使能，FALSE=输出按失效安全方向强制镜像 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障 |
| `bSensorTest` | BOOL | 输出 | — | — | 传感器测试态镜像，CmdTest 期间一拍 |

### 31.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0003_0116` | 信息级 | 传感器信号静默提示（预留码位，本轮仅登记不触发） |
| `16#0003_02C0` | 故障级 | 失效安全模式枚举越界（锁存） |

### 31.3 要点 / Notes

- 归一核心：eLow 组态约定传感器原始信号极性为 TRUE=无料/裸露（出厂反相接线，接线层保证），取反后统一为 TRUE=有料，防现场接反；归一式用 IF 显式写，禁 XOR 技巧裸用。
- v1.0.1 修复：测试沿曾误接 bEnable（正常开机沿误置测试镜像一拍），已删除误接实例。

---

## 32. R7 设备件十件套选型与联调要点 / R7 Device Set Field Notes

1. **握手类（扫码枪）**：上层只依赖 `I_DL_BarcodeScanner` 三方法编程；串口/总线收发在调用方接收层完成，`bDataNew/bDataAck` 是与接收层的握手对——`bDataAck` 置位一拍后接收层清 `bDataNew`，不要用扫描顺序隐式同步。
2. **安全件（门/光幕）定位**：两族均为逻辑编排与诊断镜像层（公约 0.13），安全回路必须在认证安全控制器；解锁时序里的 `tRunDown` 必须按实测最差停机时间整定，制动器维护后重测。
3. **计量件（流量计）**：K 系数取标定证书值；低流量工况把 `tSampleWindow` 调大（上限 10 s）换取分辨率；`bTotalNearLimit` 置位后批控侧应规划总量清零点。
4. **点式开关（料位）**：先确认传感器原始极性与 `E_DL_FailSafeMode` 组态一致（eLow 约定 raw TRUE=无料），再上电；双延迟（防抖 + 确认）按介质波动特性整定。
5. **码位冲突顺延惯例**：本轮 5 处规格建议码位与既有组件冲突，全部依公约 0.8「核对结果优先」顺延并在头注释留档——新组件分配码位前必须先检索子库码表。

---

## 33. I_DL_TowerLight ｜ 安灯塔标准接口（R8）

**功能 / Function**：工业安灯塔（三/四色塔灯 + 蜂鸣）标准抽象契约。接口三段式：随文件发布三枚举（`E_DL_TowerColor` 六色、`E_DL_TowerPattern` 五模式、`E_DL_TowerState` 七显示态）+ 只读属性 10 个 + 方法 3 个。上层按接口编程可适配直驱型（每色一路 DO）、模块化集束型与 IO-Link 总线型三类实现。TcOpen stack-light 分层惯例 clean-room（MIT，零代码复制）。
/ Andon tower-light interface contract: three enums shipped with the file, 10 read-only properties and 3 methods; portable across discrete, modular and IO-Link implementations.

**契约成员 / Contract members**（逐字取自声明区 / verbatim from the declaration area）：

| 成员 / Member | 类型 / Type | 类别 / Kind | 说明 / Description |
|---|---|---|---|
| `eState` | E_DL_TowerState | 属性 GET | 当前显示状态（仲裁结果语义分类） |
| `eRed` / `eAmber` / `eGreen` / `eBlue` / `eWhite` | E_DL_TowerPattern | 属性 GET | 各色通道当前模式（eOff=不亮） |
| `bBuzzer` | BOOL | 属性 GET | 蜂鸣器当前输出 |
| `bSilenced` | BOOL | 属性 GET | 已消音（保持窗内为 TRUE） |
| `bError` / `uErrorId` | BOOL / UDINT | 属性 GET | 故障锁存 / 错误码（段位 16#0003_xxxx） |
| `SetColor(eColor, ePattern) : BOOL` | 方法 | METHOD | 请求置某色某模式；被更高优先级占用/故障锁存时返回 FALSE |
| `SilenceBuzzer() : BOOL` | 方法 | METHOD | 消音一次性受理；安全事件期返回 FALSE（安全事件不受消音约束） |
| `Reset() : BOOL` | 方法 | METHOD | 复位故障锁存（仅存在锁存故障时返回 TRUE） |
| `E_DL_TowerColor` / `E_DL_TowerPattern` / `E_DL_TowerState` | 枚举×3 | DUT | 随本文件发布（取值步长 10 预留扩展） |

**调用示例 / Example**：

```iecst
iTower : I_DL_TowerLight;                       // 上层只持有接口引用
...
IF iTower.SetColor(eColor := E_DL_TowerColor.eAmber,
                   ePattern := E_DL_TowerPattern.eFlashSlow) THEN
    // 人工预警覆盖受理成功
END_IF
IF iTower.bBuzzer AND NOT iTower.bSilenced THEN bBuzzAudible := TRUE; END_IF
```

**现场要点 / Field notes**：方法返回值仅表示「请求是否被受理」，实际灯效以属性为准；接口层不做电平输出、不读现场输入（物理通道与状态位由实现块承载）；消音权限与次数限制属上层 HMI 职责，不在契约内。

---

## 34. FB_DL_SignalTower ｜ 安灯塔参考实现（R8）

**功能 / Function**：`IMPLEMENTS I_DL_TowerLight` 的参考实现：七级主级仲裁（安全事件 > 故障未确认 > 故障已确认 > 预警 > 求助 > 手动 > 自动）+ 人工覆盖（SetColor，被更高主级压制时拒绝）+ 消音保持窗（到期自动恢复蜂鸣 0124）+ 慢/快闪半周期可调（T#0S 退化常亮 0123）+ 红绿互斥出口断言；五路灯电平与蜂鸣输出引脚直驱。
/ Reference tower-light implementation with 7-level arbitration, override, silence hold window, flash half-period parameters and red/green mutual-exclusion assertion; direct lamp and buzzer outputs.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=全灯灭且蜂鸣停 |
| `bSafetyEvent` | BOOL | IN | 安全事件镜像（急停/安全门/光幕），最高优先，不受消音约束 |
| `bFaultActive` / `bFaultAck` | BOOL | IN | 故障存在 / 故障已确认（TRUE=红常亮不鸣） |
| `bWarnActive` / `bWarnAck` | BOOL | IN | 预警存在 / 预警已确认（TRUE=黄常亮） |
| `bManualMode` / `bAutoRunning` / `bOperatorCall` / `bStandbyIndicate` | BOOL | IN | 手动（蓝常亮）/ 自动运行（绿常亮）/ 求助（蓝快闪）/ 待机（白常亮） |
| `bBuzzerEnable` | BOOL | IN | 蜂鸣允许，FALSE=永不鸣 |
| `bSilenceCmd` | BOOL | IN | 消音指令（上升沿受理） |
| `tSilenceTime` | TIME | IN | 消音保持时长，T#0S=消音永续（0003_0125） |
| `tFlashSlow` / `tFlashFast` | TIME | IN | 慢/快闪半周期，T#0S=退化常亮（0003_0123） |
| `bReset` | BOOL | IN | 故障复位（上升沿生效） |
| `bRed` / `bAmber` / `bGreen` / `bBlue` / `bWhite` | BOOL | OUT | 五路灯电平输出（TRUE=亮） |
| `bFault` | BOOL | OUT | 故障锁存指示（仅故障级码置位） |
| 接口属性 10 个 / 方法 3 个 | I_DL_TowerLight | IMPLEMENTS | 逐一兑现（R22 以 PROPERTY GET 承载，终审逐项核验） |

**故障码 / Codes**：信息级 0003_0123~0126；故障级 0003_02D0（红绿同亮断言冲突，防御性锁存）、02D1（非法显示状态）。

**调用示例 / Example**：

```iecst
fbTower(bEnable := TRUE, bReset := bResetCmd,
        bSafetyEvent := bEstopActive,           // 急停镜像直连（最高优先）
        bFaultActive := bAnyFault, bFaultAck := bFaultAcked,
        bAutoRunning := fbPackML.bExecute,      // 自动态绿色常亮
        tFlashSlow := T#500MS, tFlashFast := T#250MS);
oLampRed   := fbTower.bRed;                     // 物理通道直驱
oLampGreen := fbTower.bGreen;
oBuzzer    := fbTower.bBuzzer AND NOT fbTower.bSilenced;
```

**现场要点 / Field notes**：手动与自动同真时手动优先（0003_0126）；安全事件引发的红快闪 + 蜂鸣无法被消音——消音按钮在急停场景失效属设计语义不是缺陷；闪频时基由引脚给定禁读 CPU 钟；直驱型通道数量不足时低优先色通道由调用方取舍，仲裁表优先级已在头注释固化。

---

## 35. I_DL_StepperOpenLoop ｜ 开环步进电机标准接口（R9）

**定位 / Positioning**：开环步进电机（脉冲 + 方向型）抽象契约——只声明能力，不做实现；上层工站 / 手动调试页 / HMI 适配层仅依赖本接口引用，即可适配脉冲方向型驱动器、总线型闭环步进（降级使用）与仿真步进轴。方法数 6（恰在 ≤6 红线临界）。

**契约要点 / Contract**：fPosition 是指令推算值（开环），禁止当编码器反馈；限位触发后 MoveRelative 拒绝同方向（电平判据持续生效）；方法返回 FALSE 必伴随 GetErrorId 非零码（禁静默失败）；方法全部非阻塞单发语义。

**配套结构体 / Config struct（随接口同文件发布）**：

| 字段 / Field | 类型 / Type | 说明 / Description |
|---|---|---|
| `uStepsPerMm` | UINT | 脉冲当量 [脉冲/mm]，域 > 0，默认 400 |
| `uMicrostep` | UINT | 驱动器细分数 [细分]，域 >= 1，默认 1（有效当量 = 当量 × 细分） |
| `fMaxSpeed` | LREAL | 最大运行速度 [mm/s]，域 > 0，默认 50.0 |
| `fAccel` | LREAL | 加/减速度 [mm/s²]（对称），域 > 0，默认 500.0 |
| `tStallTimeout` | TIME | 堵转判据附加裕度 [ms]，叠加在理论耗时之上，默认 T#500MS |
| `fTaskCycle` | LREAL | 任务周期 [s]，频率求导与脉冲翻步基准，默认 0.01 |

### 接口 / Interface

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bReady` | BOOL | PROPERTY GET | 就绪（已初始化 + 已使能 + 无故障 + 空闲） / Ready |
| `fPosition` | LREAL | PROPERTY GET | 指令位置累计 [mm]（开环推算，非编码器反馈） / Open-loop derived position |
| `uAlarmWord` | WORD | PROPERTY GET | 报警字：bit0 正限位 / bit1 负限位 / bit2 驱动器报警 / bit3 堵转超时 / bit4~15 保留 / Alarm word |
| `Init(stCfg)` | BOOL | METHOD | 初始化：注入组态并校验参数域 / Initialize with configuration |
| `Enable(bEnable)` | BOOL | METHOD | 使能/去使能（电平语义，FALSE 本拍冻结脉冲无半脉冲） / Enable or disable |
| `MoveRelative(fDistance, fSpeed)` | BOOL | METHOD | 相对位移指令 [mm]，正负双向，速度 > 0 超上限钳位 / Move relative |
| `Stop()` | BOOL | METHOD | 受控停车：按减速度斜坡降频至零并清除当前指令 / Controlled stop |
| `Reset()` | BOOL | METHOD | 故障复位（驱动器报警源未消失时不解除） / Fault reset |
| `GetErrorId()` | UDINT | METHOD | 故障码查询，0 = 无故障 / Error code query |

**调用示例 / Example**：见第 36 节 `FB_DL_PulseDirStepper`（唯一内置实现块）。

**现场要点 / Field notes**：方法返回 FALSE ≠ 受理失败无后果——GetErrorId 必有非零码，调试先查码；回原、点动、绝对定位职责不入本接口，由上层工艺块以 MoveRelative 组合实现（O-11：空 VAR 块与无 END_PROPERTY 属库内导出惯例，本轮不改）。

---

## 36. FB_DL_PulseDirStepper ｜ 脉冲 + 方向开环步进控制器（R9，v1.0.1 · D-02 致命修复件）

**定位 / Positioning**：脉冲 + 方向型开环步进控制器，实现 `I_DL_StepperOpenLoop` 全部属性与方法：梯形加减速脉冲频率规划（短行程退化三角型）、限位保护（同向停发锁故障、电平判据持续拒同向）、堵转超时判据（理论耗时 × 1.5 + 附加裕度）、定宽一拍脉冲（R24）。物理脉冲经 bPulse/bDir 输出引脚交由上层映射（零硬编码地址）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bLimitPos` / `bLimitNeg` | BOOL | IN | 正 / 负限位开关输入（TRUE = 触发，常闭型由调用方反相） / Limit switch inputs |
| `bAlarmIn` | BOOL | IN | 驱动器报警输入（TRUE = 报警） / Drive alarm input |
| `fJogSpeed` | LREAL | IN | 点动速度预留 [mm/s]，本版不启用 / Reserved jog speed |
| `bPulse` | BOOL | OUT | 脉冲输出（定宽一拍，R24）/ Pulse output, one-scan wide |
| `bDir` | BOOL | OUT | 方向输出（TRUE = 正向）/ Direction output |
| `bEnableOut` | BOOL | OUT | 使能输出（透传指令，故障期保持力矩防垂直轴溜车） / Enable output, held during faults |
| `fFreqNow` | LREAL | OUT | 当前脉冲频率 [Hz]（诊断用）/ Current pulse frequency |
| `bError` | BOOL | OUT | 故障保持型 / Fault latched |
| `uErrorId` | UDINT | OUT | 故障码，0 = 无故障 / Error code |
| 接口属性 3 / 方法 6 | I_DL_StepperOpenLoop | IMPLEMENTS | 逐一兑现（R22 以 PROPERTY GET 承载） / Full interface implementation |

**故障码 / Codes**：信息级 0003_0130~0137（速度/频率钳位、位移不足、指令拒绝、限位方向禁止、去使能冻结、周期兜底、**0137 减速残差不足一脉冲按到位处理**——v1.0.1 新增）；故障级 0003_02E0~02E4（组态非法 / 限位入侵 / 驱动器报警 / 堵转超时 / 非法状态兜底）。

### 调用示例 / Example

```iecst
VAR
    stCfg  : ST_DL_StepperCfg;              // 步进组态（调用方持有）/ Stepper config, caller-owned
    fbStep : FB_DL_PulseDirStepper;         // 步进控制器实例 / Stepper instance
    bOk    : BOOL;                          // 方法受理返回 / Method acceptance
END_VAR

stCfg.uStepsPerMm := 400;  stCfg.uMicrostep := 8;  stCfg.fMaxSpeed := 30.0;
stCfg.fAccel := 400.0;     stCfg.tStallTimeout := T#300MS;  stCfg.fTaskCycle := 0.01;
bOk := fbStep.Init(stCfg := stCfg);         // 注入组态 / Inject configuration
bOk := fbStep.Enable(bEnable := TRUE);      // 上使能（保持力矩）/ Enable
fbStep(bLimitPos := bDiPos, bLimitNeg := bDiNeg, bAlarmIn := bDiAlm);  // 每周期无条件调用
bOk := fbStep.MoveRelative(fDistance := 25.0, fSpeed := 15.0);
// 物理通道映射 / Physical channel mapping:
// bDoPulse := fbStep.bPulse;  bDoDir := fbStep.bDir;
```

**现场要点 / Field notes**：① 脉宽硬下限——10 ms 任务最高 50 Hz，更高频率必须换更快的任务（0003_0131 钳位提示）；② 开环会丢步，fPosition 禁止当反馈做闭环；③ 有效当量 = 当量 × 细分，改细分必须同步改字段；④ 堵转判据识别卡滞不识别打滑；⑤ **v1.0.1 致命修复（D-02）**：eDecel 出口改双条件——频率归零即数学上不可能再发脉冲，一律按到位收尾（0003_0137 记录），原版残差为小数时永久停在 eDecel（轴不动、不报警、不能接新指令）；⑥ 本块不构成认证安全功能，急停与安全门必须由认证安全回路在输出侧直接切断。

---

## 37. I_DL_RfidReader ｜ RFID 读写头标准接口（R10，v1.0.0）

**定位 / Positioning**：载具 / 托盘 / 料箱 RFID 读写头的标准契约。**T2-6 Rockwell AOI 首次开组**的落地件：把 AOI 的参数四分段范式（`In` 指令 / `Out` 状态 / `InOut` 调用方内存别名 / `Local` 不对外中间量）映射为「**方法（In 段） + 只读属性（Out 段） + 诊断结构整体回读（InOut 段等价物） + VAR 内部量（Local）**」，接口方法数 4（远低于 ≤6 红线临界）。

**接口 / 实现分离**：本文件同时发布四个 DUT（契约优先，实现块只 `IMPLEMENTS`，不得重复声明）。私有协议 / IO-Link / 串口三种物理形态由不同实现块承载，上层工站只依赖本契约。

### 接口 / Interface

| 成员 / Member | 类型 / Type | 段位 / Segment | 说明 / Description |
|---|---|---|---|
| `State` | PROPERTY → `E_DL_RfidState` | Out（只读） | 当前状态，映射规则由实现块逐条写死（HMI 直接读）/ Current state, mapping fixed by the implementer |
| `Tag` | PROPERTY → `ST_DL_RfidTag` | Out（只读） | 当前标签快照，**读到后保持**（R27），直到下次成功读取覆盖 / Tag snapshot, held after a successful read |
| `Diag` | PROPERTY → `ST_DL_RfidDiag` | Out（只读） | 诊断结构整体回读（AOI `InOut` 段的对外等价物）/ Whole diagnostic structure read back at once |
| `Init` | METHOD → BOOL | In（单发） | 初始化，组态经 `VAR_IN_OUT stCfg` 注入，**只登记不阻塞** / Initialise, configuration injected by reference |
| `ReadTag` | METHOD → BOOL | In（单发） | 发起读标签（唯一号与数据区），忙时拒绝 / Start a tag read, rejected while busy |
| `WriteTag` | METHOD → BOOL | In（单发） | 发起写数据区，内容经 `VAR_IN_OUT stTagIn` 注入，忙时拒绝，实现块须锁存副本 / Start a data write, payload latched |
| `Reset` | METHOD → BOOL | In（单发） | 清故障回就绪态，**故障态下唯一受理的方法** / Clear the fault, the only method served while faulted |

**随文件发布的 DUT / Bundled DUTs**：

| DUT | 字段 / 取值 | 说明 / Description |
|---|---|---|
| `E_DL_RfidState` | `eOffline(0)` / `eReady(10)` / `eBusy(20)` / `eError(90)` / `eNoTag(95)` | 步长 10 留空位，新增状态不破坏已有 HMI 数值映射；`eNoTag` 是**业务态非故障** |
| `ST_DL_RfidTag` | `sTagId STRING(64)` / `sData STRING(64)` / `uPage UINT` / `nRssi INT` / `bValid BOOL` | 一次读写的标签快照；`nRssi` 域 −90~0 dBm |
| `ST_DL_RfidDiag` | `uLastErrorId UDINT` / `nCommRetry INT` / `nReadTotal DINT` / `nWriteTotal DINT` / `bAntennaOk BOOL` / `tLastComm TIME` | 诊断与统计；累计计数**跨班不清零** |
| `ST_DL_RfidCfg` | `sAntennaNo STRING(8)` / `nPowerDbm INT`(0~30) / `tTimeout TIME`(50 ms~5 s) / `nMaxRetry INT`(0~5) / `bDupFilterEn BOOL` / `tDupWindow TIME`(100 ms~60 s) | 组态参数，调用方持有，接口侧只读 |

### 调用示例 / Example

```iecst
VAR
    iReader  : I_DL_RfidReader;   // 接口引用，由具体实现块实例注入 / Reference injected by a concrete implementation
    stTagNow : ST_DL_RfidTag;     // 标签快照 / Tag snapshot
    eState   : E_DL_RfidState;    // 状态 / State
    bAccepted: BOOL;              // 方法受理值 / Method accepted
END_VAR

// 上层只依赖契约：读一个载具标签，成功后取快照
IF bTriggerRead THEN
    bAccepted := iReader.ReadTag();          // 忙时返回 FALSE 且不排队
END_IF
IF iReader.State = E_DL_RfidState.eReady AND bAccepted THEN
    stTagNow := iReader.Tag;                 // 保持型快照，不会下一拍消失
END_IF
```

**要点 / Notes**：所有方法返回 **BOOL 受理值**（拒绝也要能看见，禁静默失败——R24 家族）；忙时拒绝不排队（单发语义，队列由调用方按工站节拍组织）；接口文件头固化「**实现块不得自造码段**」纪律；本接口保留 CODESYS 内联 METHOD 成员写法（全库 152 件一致，非缺陷，总监已裁定维持）。

---

## 38. FB_DL_RfidTagHandler ｜ RFID 读写实现（R10，v1.0.1）

**定位 / Positioning**：`I_DL_RfidReader` 的参考实现（`IMPLEMENTS`）。五态握手（`eIdle` / `eWaitHw` / `eVerify` / `eRetry` / `eFault`）+ 写后回读校验 + 超时重试链 + 同标签重复读抑制 + 硬件原始错误码透传。私有协议帧 / 串口收发由 IO 层外置，本块只出「请求电平 + 方向电平」。

**关键设计 / Key design**：
- **写后回读校验（`eVerify`）**：写完立刻回读比对，不一致即判 `02F3`，**不轻信「写成功」反馈**（RFID 工业现场头号问题是「以为写进去了」）。
- **重复读抑制**：同标签在 `tDupWindow` 内重复读到只置 `0138` 信息码，不重复上报 `bReadDoneOk`——载具在读写头前停留 3 秒不该产生 30 次业务事件。
- **双类故障分离（AOI ProgFault / OperFault）**：`02F0~02F1` 组态类（未初始化、忙时重入、超时重试耗尽）/ `02F2~02F3` 工艺类（读写头报错、校验不符），HMI 可按类分组过滤。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能，FALSE 转离线并拒绝全部方法 [−] / Enable, FALSE goes offline |
| `bHwReady` | BOOL | IN | — | 读写头就绪反馈，由协议层或 IO 层注入 [−] / Reader ready feedback |
| `bHwDone` | BOOL | IN | — | 本次指令执行完成，单拍或电平，内部取上升沿 [−] / Command done, edge detected internally |
| `bHwError` | BOOL | IN | — | 读写头报错反馈 [−] / Reader error feedback |
| `sHwTagId` | STRING(64) | IN | — | 读回的标签唯一号，空串表示视野内无标签 [ASCII] / Tag id read back |
| `sHwData` | STRING(64) | IN | — | 读回的数据区内容 [ASCII 或十六进制] / Data area content |
| `uHwErrorCode` | UDINT | IN | — | 读写头**原始错误码**，透传进诊断不改语义 [代码] / Raw reader error code forwarded |
| `tCmdTimeout` | TIME | IN | T#500MS | 单指令超时，域 50 ms~5 s [毫秒] / Per-command timeout |
| `nMaxRetry` | INT | IN | 2 | 重试次数，域 0~5 [次] / Retry count |
| `bDupFilterEn` | BOOL | IN | TRUE | 同标签重复读抑制使能 [−] / Duplicate suppression enable |
| `tDupWindow` | TIME | IN | T#2S | 重复读抑制窗，域 100 ms~60 s [毫秒] / Suppression window |
| `stCfg` | ST_DL_RfidCfg | IN_OUT | — | 组态，调用方持有，本块只读使用 [结构] / Configuration owned by the caller |
| `bReadDoneOk` | BOOL | OUT | — | 读成功，**单拍脉冲** [−] / Read succeeded, one-scan pulse |
| `bWriteDoneOk` | BOOL | OUT | — | 写成功，**单拍脉冲** [−] / Write succeeded, one-scan pulse |
| `bNoTag` | BOOL | OUT | — | 视野内无标签，**保持型业务态** [−] / No tag in field, holding business state |
| `bBusy` | BOOL | OUT | — | 指令执行中 [−] / Command in progress |
| `bError` | BOOL | OUT | — | 故障锁存，组态类与工艺类同置，**码区分** [−] / Fault latch, the code tells the class apart |
| `uErrorId` | UDINT | OUT | — | 事件码（见下表）/ Event code |
| `nRetryCnt` | INT | OUT | — | 本次指令已重试次数 [次] / Retries spent on the current command |
| `bHwReq` | BOOL | OUT | — | 硬件请求电平，送协议层或 IO 层 [−] / Hardware request level |
| `bHwWr` | BOOL | OUT | — | 硬件读写方向，FALSE 读 / TRUE 写 [−] / Direction towards the hardware |

**故障码 / Codes**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_0138` | 信息级 | 同标签重复读被抑制窗拦下 |
| `0003_0139` | 信息级 | 指令超时或抑制窗参数越界被钳位 |
| `0003_013A` | 信息级 | 重试次数越界被钳位 |
| `0003_02F0` | 故障级·组态使用类 | 未初始化、忙时重入或写入内容非法 |
| `0003_02F1` | 故障级·组态类 | 超时重试耗尽 |
| `0003_02F2` | 故障级·工艺类 | 读写头报错重试耗尽 |
| `0003_02F3` | 故障级·工艺类 | 写后回读校验不符或非法状态兜底 |

### 调用示例 / Example

```iecst
VAR
    fbRfid   : FB_DL_RfidTagHandler;   // RFID 实例 / RFID handler instance
    stCfg    : ST_DL_RfidCfg;         // 组态，调用方持有 / Configuration held by the caller
    stTag    : ST_DL_RfidTag;         // 标签快照 / Tag snapshot
    bInitOk  : BOOL;                  // 初始化受理 / Init accepted
END_VAR

// 1) 初始化（只登记不阻塞）/ Initialise once
IF bFirstScan THEN
    bInitOk := fbRfid.Init(stCfg := stCfg);
END_IF

// 2) 每周期无条件调用主块（IO 层信号注入）/ Call unconditionally every scan
fbRfid(bEnable := bLineRunning, bHwReady := bReaderReady, bHwDone := bCmdDone,
       bHwError := bCmdError, sHwTagId := sRawTagId, sHwData := sRawTagData,
       uHwErrorCode := uReaderErrCode, tCmdTimeout := T#500MS, nMaxRetry := 2,
       bDupFilterEn := TRUE, tDupWindow := T#2S, stCfg := stCfg);

// 3) 触发读（上升沿单发）/ Trigger one read
IF bRequestRead THEN
    fbRfid.ReadTag();
END_IF

// 4) 消费结果 / Consume the result
IF fbRfid.bReadDoneOk THEN
    stTag := fbRfid.Tag;
END_IF
IF fbRfid.bError THEN
    // 先看 uErrorId 判类：02F0/02F1 组态类→查组态；02F2/02F3 工艺类→查读写头与标签
END_IF
```

**要点 / Notes**：
- **v1.0.1 修复（D-11）**：`uHwErrorCode` 原先声明后零引用 → 现在 `bHwError` 分支写 `stDiag.uLastErrorId := uHwErrorCode`；段 9 诊断刷新改为**条件刷新**（仅块级码非零时覆盖）——否则每拍会把透传的厂家原始码清 0，现场拿到 `02xx` 类块级码后无法再到厂家手册查具体原因。
- **v1.0.1 修复（D-14）**：头注释补「硬件原始码 vs 块级码」优先级规则（**硬件报错拍写原始码，块级码非零时才覆盖**）。
- **观察项 O-4**：`Init` 形参 `stCfg` 与块级引脚同名遮蔽（方法体不引用形参，实际组态以块级引脚为准）；同一实例同时接引脚与 `Init` 调用时，以引脚为准。下一 MAJOR 把形参改名 `stInitCfg`。
- **`bHwReq` / `bHwWr` 提为输出**（D2 裁定采纳）：这是送协议 / IO 层的指令电平，必须可外部观测与接线，属向后兼容的可见性扩展。

---

## 39. FB_DL_AxiolineDiagLatch ｜ 总线模块诊断解析与首出锁存（R10，v1.0.1）

**定位 / Positioning**：**T1-7 PLCnext Community 首次开组**的代表件。解析 Axioline F 系列模块的「诊断状态寄存器 + 诊断参数寄存器 + 扩展参数寄存器」三源信息，输出结构化诊断等级与**首出故障（first-out）**记录。位语义借官方公开文档，**位序、枚举、码位 100% 本库自有**，不绑定任何厂商系统变量名（三源一律经引脚注入）。

**现场价值 / Field value**：总线诊断的痛点是「灯红了，但不知道是哪个槽、什么码」。本块把「状态位 → 四级等级 → 首出槽号 + 首出码」串成一条可 HMI 显示的链，并处理 **128 特例（无法定位的接口错误）——不得伪装成 128 号槽**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能，FALSE 清实时诊断位但**保留锁存** [−] / Enable, FALSE clears live bits but keeps the latch |
| `uStatusWord` | WORD | IN | — | 诊断状态寄存器位域，字节拼接由 IO 层完成 [位串] / Diagnostic status register |
| `uErrCode` | WORD | IN | — | 诊断参数寄存器：错误码 [代码] / Diagnostic parameter register |
| `uErrSlot` | USINT | IN | — | 扩展参数寄存器：错误位置槽号，**0 与 128 为特例** [槽] / Error location slot |
| `bModuleReady` | BOOL | IN | — | 总线就绪反馈（与 RDY 位等效，冗余校验用）[−] / Bus ready feedback |
| `bAckDiag` | BOOL | IN | — | 诊断确认，上升沿清显示位但**不清锁存** [−] / Acknowledge, clears display bits only |
| `bReset` | BOOL | IN | — | 复位锁存与首出，上升沿有效 [−] / Reset the latch and the first-out record |
| `bBusError` | BOOL | OUT | — | 总线级故障（BUS 位）[−] / Bus level fault |
| `bPeriphFault` | BOOL | OUT | — | 外围故障（PF 位），模块或通道硬件错 [−] / Peripheral fault |
| `bPeriphWarn` | BOOL | OUT | — | 外围警告（PW 位）[−] / Peripheral warning |
| `bSysFail` | BOOL | OUT | — | 系统故障（SYSFAIL 位）[−] / System failure |
| `bDiagActive` | BOOL | OUT | — | 任一诊断有效，聚合位供 HMI 单点使用 [−] / Any diagnostic active |
| `eLevel` | E_DL_DiagLevel | OUT | — | 四级等级：`eNone(0)` / `eWarn(10)` / `eFault(20)` / `eFatal(30)` [−] / Diagnostic level |
| `nFirstSlot` | INT | OUT | -1 | 首出故障槽号，−1 无、**128 表示无法定位** [槽] / First-out slot |
| `uFirstCode` | WORD | OUT | — | 首出故障错误码，与槽号同拍锁存 [代码] / First-out error code |
| `nEventCnt` | UDINT | OUT | — | 诊断事件累计次数（去抖后计数，**复位不清**）[次] / Debounced event counter |
| `bLatchFull` | BOOL | OUT | — | 锁存已占用（首出保持，需复位）[−] / Latch occupied, needs a reset |
| `uErrorId` | UDINT | OUT | — | 事件码（见下表）/ Event code |

**位序常量（本库自有）**：PF `16#0001` / PW `16#0002` / BUS `16#0004` / RUN `16#0008` / ACT `16#0010` / RDY `16#0020` / SYSFAIL `16#0040`。**IO 层必须按实际字节序映射后注入**，本块不猜字节序。

**故障码 / Codes**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_013B` | 信息级 | 槽号非法（> 127 且 ≠ 128），按无位置处理 |
| `0003_013C` | 信息级 | 诊断块未使能，实时位已清零、锁存保留 |
| `0003_02F4` | 故障级 | 诊断位有效但错误码为 0（状态与参数寄存器不自洽） |
| `0003_02F5` | 故障级 | 非法状态兜底 |
| `0003_02F6` | 故障级 | 总线就绪丢失超时（诊断有效而模块就绪长期为假） |

### 调用示例 / Example

```iecst
VAR
    fbDiag     : FB_DL_AxiolineDiagLatch;   // 诊断解析实例 / Diagnostics parser
    eDiagLevel : E_DL_DiagLevel;            // 四级等级 / Four-level grade
    nBadSlot   : INT;                        // 首出槽号 / First-out slot
    wBadCode   : WORD;                       // 首出错误码 / First-out error code
    bAnyDiag   : BOOL;                       // 任一诊断 / Any diagnostic
END_VAR

// 每周期无条件调用：三源寄存器由总线 IO 层映射后注入
fbDiag(bEnable := bStationRunning, uStatusWord := wAxioStatus, uErrCode := wAxioErrCode,
       uErrSlot := uAxioErrSlot, bModuleReady := bBusReady,
       bAckDiag := bHmiAckDiag, bReset := bHmiResetDiag,
       eLevel => eDiagLevel, nFirstSlot => nBadSlot, uFirstCode => wBadCode,
       bDiagActive => bAnyDiag);

IF fbDiag.bDiagActive AND (eDiagLevel >= E_DL_DiagLevel.eFault) THEN
    // HMI 显示：槽 nBadSlot、码 wBadCode；若 nBadSlot = 128 表示无法定位，查接口/背板
END_IF
```

**要点 / Notes**：
- **v1.0.1 修复（D-05，严重）**：原实现「确认拍先装载 `nAckMute := DL_ACK_MUTE`，紧接着同拍无条件递减」→ 屏蔽窗口只有 0 拍，`bAckDiag` **形同虚设**（现场表现「怎么按都消不掉」）。修法：装载拍不递减，仅非确认拍递减：
  ```iecst
  IF fbTrigAck.Q THEN
      nAckMute := DL_ACK_MUTE;      // 确认拍：装载屏蔽长度，当拍不清零
  ELSIF nAckMute > 0 THEN
      nAckMute := nAckMute - 1;     // 非确认拍才递减
  END_IF
  ```
  这是**同拍读写次序缺陷**的典型样本（`R32` 素材）。
- **v1.0.1 修复（D-09）**：锁存条件补 `bEnable` —— 块未使能（设备未投运）时不应锁存故障并累加事件，否则停机检修期间会产生虚假事件堆积。
- **v1.0.1 修复（D-12）**：`nEventCnt` 语义由「故障发生了多少次」改正为「**锁存事件次数**（锁存后不覆盖、复位前不再加一）」，与代码逐拍对齐。
- **128 特例**：无法定位的接口错误在扩展参数寄存器里表现为 128（bit7 置位）；本块把 `nFirstSlot = 128` 原样上报，**不得**当成第 128 号槽去查模块表。

---

## 40. FB_DL_PdiReadScheduler ｜ PDI 异步读取调度器（R10，v1.0.1）

**定位 / Positioning**：按 PDI（**P**arameters / **D**iagnostics / **I**nformation）参数域读取设备对象。四元参数域 `Slot`（设备号）/ `Subslot`（子设备号）/ `Index`（对象索引）/ `Subindex`（对象子索引），结果双码域 `ErrorCode` + `AddInfo` 打包为一个 UDINT。**调度与传输分层**：本块只管「何时发、发几次、结果怎么记」，真实收发由传输层（服务就绪 / 完成 / 错误码 / 长度四路反馈）注入。

**工程纪律（来自官方文档的公开约束，本库自有实现）**：RSC/PDI 服务执行耗时长，**禁止在实时任务里连续调用** → 本块落为「**单拍只发一条 + 忙时拒绝不排队**」，并统计拒绝次数供现场判断任务负载。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能 [−] / Enable |
| `bStart` | BOOL | IN | — | 启动单次读取，上升沿；**忙时忽略并计一次拒绝** [−] / Start a single read on a rising edge |
| `uSlot` | UINT | IN | 0 | 设备号（槽），域 0~4095 [号] / Device slot |
| `uSubslot` | UINT | IN | 1 | 子设备号（子槽），域 0~255 [号] / Sub-device subslot |
| `uIndex` | UINT | IN | 0 | 对象索引，域 0~65535 [索引] / Object index |
| `uSubindex` | USINT | IN | 0 | 对象子索引，域 0~255 [子索引] / Object subindex |
| `nExpLen` | INT | IN | 0 | 期望数据长度，域 0~1024，**0 表示不限** [字节] / Expected length, 0 unrestricted |
| `tTimeout` | TIME | IN | T#1S | 单次超时，域 100 ms~10 s（越界钳位）[毫秒] / Request timeout |
| `nMaxRetry` | INT | IN | 0 | 重试次数，域 0~3，**PDI 重试须保守** [次] / Retry count |
| `bSrvReady` | BOOL | IN | — | 传输层服务就绪 [−] / Transport service ready |
| `bSrvDone` | BOOL | IN | — | 传输层服务完成，电平或单拍，内部取沿 [−] / Transport service done |
| `uSrvError` | WORD | IN | — | 服务错误码（低 16 位）[代码] / Service error code |
| `uSrvAddInfo` | WORD | IN | — | 服务附加信息（高 16 位）[代码] / Service additional information |
| `uSrvLen` | UINT | IN | — | 实际返回数据长度 [字节] / Actual returned length |
| `bReqActive` | BOOL | OUT | — | 请求已下发，送传输层的启动信号 [−] / Request asserted towards the transport |
| `bDone` | BOOL | OUT | — | 本次读取完成，**单拍**（成功或失败均置）[−] / Request finished, one-scan pulse |
| `bSuccess` | BOOL | OUT | — | 本次读取成功，与完成同拍有效 [−] / TRUE when the request succeeded |
| `uErrCode` | UDINT | OUT | — | **双层打包**：高 16 位 `AddInfo`，低 16 位 `ErrorCode` [代码] / Packed dual-layer error code |
| `uActLen` | UINT | OUT | — | 实际数据长度 [字节] / Actual data length |
| `nRejectCnt` | UDINT | OUT | — | 忙时拒绝启动次数，跨班不清零 [次] / Busy rejection counter |
| `nOkCnt` | UDINT | OUT | — | 成功次数 [次] / Successful request counter |
| `nFailCnt` | UDINT | OUT | — | 失败次数（含重试耗尽）[次] / Failed request counter |
| `uErrorId` | UDINT | OUT | — | 事件码（见下表）/ Event code |
| `bError` | BOOL | OUT | — | 故障锁存，仅故障级码置位 [−] / Fault latch |

**故障码 / Codes**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0003_013D` | 信息级 | 槽号或子槽号越界被钳位 |
| `0003_013E` | 信息级 | 索引或子索引越界被钳位 |
| `0003_013F` | 信息级 | **期望长度或单次超时**越界被钳位 |
| `0003_02F7` | 故障级 | 本次读取失败或超时且重试耗尽 |
| `0003_02F8` | 故障级 | 非法状态兜底 |
| `0003_02F9` | 故障级 | 同一请求连续三轮失败，锁定 |

### 调用示例 / Example

```iecst
VAR
    fbPdi     : FB_DL_PdiReadScheduler;   // PDI 调度实例 / PDI scheduler
    uPacked   : UDINT;                    // 打包错误码 / Packed error code
    uLen      : UINT;                     // 实际长度 / Actual length
    uErrWord  : WORD;                     // 低 16 位错误码 / Error code low word
    uAddWord  : WORD;                     // 高 16 位附加信息 / Add info high word
END_VAR

// 每周期无条件调用；一次只读一个对象
fbPdi(bEnable := TRUE, bStart := bReadObjectReq,
      uSlot := 3, uSubslot := 1, uIndex := 16#AFF0, uSubindex := 0,
      nExpLen := 4, tTimeout := T#1S, nMaxRetry := 1,
      bSrvReady := bRscReady, bSrvDone := bRscDone,
      uSrvError := wRscErr, uSrvAddInfo := wRscAddInfo, uSrvLen := uRscLen,
      uErrCode => uPacked, uActLen => uLen);

IF fbPdi.bDone THEN
    uErrWord := UDINT_TO_WORD(uPacked AND 16#0000_FFFF);   // 低 16 位
    uAddWord := UDINT_TO_WORD(SHR(uPacked, 16));           // 高 16 位
END_IF
```

**要点 / Notes**：
- **v1.0.1 修复（D-10，中等）**：`tTimeout` 原先直接喂给 TON 的 `PT`；`tTimeout = T#0S` 时 TON 每拍立即 `Q = TRUE` → 重试计数每拍 +1 → **瞬间打满重试上限并报错，同时向从站发起高频请求（重试风暴）**。修法：新增内部量 `tTmoUse : TIME := T#1S`，参数校验段 `tTmoUse := LIMIT(DL_TMO_MIN, tTimeout, DL_TMO_MAX)`，定时器改用 `PT := tTmoUse`，越界并入 `013F`。**教训：声明了 MIN/MAX 常量却从不使用，本身就是「参数未钳位」的静态信号**（机检未覆盖此信号）。
- **v1.0.1 修复（D-13）**：码表 `013F` 语义由「期望长度越界」扩写为「**期望长度或单次超时越界被钳位**」。
- **双码打包**：不要只取低 16 位——`AddInfo` 常给出「哪个子索引 / 哪个通道」的附加定位信息，现场排障的主要线索在高层。
- **重试保守**：`nMaxRetry` 上限 3；PDI/RSC 服务耗时以百毫秒计，激进重试会把总线拖死。

---

## 41. FB_DL_PortDiagAggregator ｜ 端口级诊断聚合与首出仲裁（R11，v1.0.0）

**定位 / Positioning**：把最多 8 个现场总线**通讯端口**的链路状态、端口诊断码、CRC 错误累计计数，聚合成一个故障掩码 + 首出端口号 + 首出诊断码 + 错误风暴标志。解决现场最常见的抱怨——「三个端口同时报警，HMI 上只看到最后一条」。

**首出语义 / First-out**：只在**未锁存**时仲裁，同拍多端口故障取**端口号最小者**（低号端口更靠近主站，符合现场排故的默认因果顺序）；锁存后不再更新，只有复位上升沿可清。复位处理放在仲裁**之后**，保证复位当拍首出为空、下一拍重新仲裁。

**拍序纪律 / Cycle order（硬约束）**：窗口差分必须在装载**之前**算出并转出——先转出上一段增量快照，再装载下一段基准计数；顺序颠倒会让窗口结束拍的增量恒为 0。

**风暴语义 / Burst**：风暴是**趋势事件**，不锁存；`eBurst` 只停留一拍，该拍置 `bBurstDetected` 单拍标志，供上层做趋势记录或降低总线负载，**不参与 `bError` 判定**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 时掩码清零、首出保持 / Enable; clears the mask, holds first-out |
| `bReset` | BOOL | IN | — | — | 复位首出锁存，上升沿有效 / Reset the first-out latch |
| `nPortCount` | INT | IN | — | 个 | 实际端口数，有效域 1~8，超上限钳位 / Port count, 1 to 8 |
| `abPortLinkOk` | ARRAY[1..8] OF BOOL | IN | — | — | 各端口链路正常标志 / Per-port link-up flags |
| `auPortErrCode` | ARRAY[1..8] OF UDINT | IN | — | 代码 | 各端口诊断码，0 = 正常 / Per-port diagnostic code |
| `auPortCrcErrCnt` | ARRAY[1..8] OF UDINT | IN | — | 次 | 各端口 CRC 错误**累计**计数（回绕安全）/ Per-port cumulative CRC counter |
| `nBurstThreshold` | UDINT | IN | `10` | 次 | 窗口内增量阈值，0 表示不判风暴 / Burst threshold, 0 disables |
| `tBurstWindow` | TIME | IN | `T#1S` | 毫秒 | 风暴统计窗口长度 / Burst window |
| `tDebounce` | TIME | IN | `T#200MS` | 毫秒 | 端口故障确认去抖，0 表示不去抖 / Port fault debounce |
| `bAnyPortFault` | BOOL | OUT | — | — | 任一端口故障，等价掩码非零 / Any port faulted |
| `bBurstDetected` | BOOL | OUT | — | — | 风暴**单拍**标志，仅 `eBurst` 拍为真 / Burst one-shot flag |
| `uPortFaultMask` | WORD | OUT | — | 位串 | 端口故障掩码，**位 n 对应端口 n+1** / Fault mask, bit n is port n+1 |
| `nFirstFaultPort` | INT | OUT | — | — | 首出故障端口号 1~8，0 = 无 / First-out port |
| `uFirstFaultCode` | UDINT | OUT | — | 代码 | 首出端口诊断码，与端口号**同拍**锁存 / First-out code |
| `auPortDelta` | ARRAY[1..8] OF UDINT | OUT | — | 次 | 本窗口各端口错误增量 / Per-port delta of this window |
| `eState` | E_DL_PortDiagPhase | OUT | — | — | `eIdle` 0 / `eMonitor` 10 / `eBurst` 20 / `eFault` 99 |
| `bError` | BOOL | OUT | — | — | 故障级锁存，**仅 `0300`/`0301`/`0307` 置位** / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无 / Event code |
| `stState` | ST_DL_PortDiagState | IN_OUT | — | — | 跨周期状态：`auPrevCnt` 基准计数 / `nLatchPort` / `uLatchCode` / `bLatchValid`，调用方持有 / Persistent state |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0140` | 信息级 | 端口数超上限已钳位（只进码与趋势，不置故障位） | 校验站的端口配置；把 `nPortCount` 改到 1~8 |
| `0003_0141` | 信息级 | 统计窗口参数越界已钳位 | 检查 `tBurstWindow` 是否为 0 |
| `0003_0300` | 故障级 | 端口故障锁存（伴随故障掩码非零） | 按 `nFirstFaultPort` / `uFirstFaultCode` 查首出端口；修好后给 `bReset` |
| `0003_0301` | 故障级 | 诊断源未注入（`nPortCount < 1`） | 端口表未组态；本件拒绝在无数据源时静默运行 |
| `0003_0307` | 故障级 | 非法状态兜底 | 枚举被外部强制写入未定义值；复位退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_FieldbusPortDiag
VAR
    fbPortDiag      : FB_DL_PortDiagAggregator;   // 端口诊断聚合实例 / Port diagnostic aggregator
    stPortState     : ST_DL_PortDiagState;        // 跨周期状态 / Persistent state
    abLinkOk        : ARRAY[1..8] OF BOOL;        // 各端口链路正常 / Link flags
    auErrCode       : ARRAY[1..8] OF UDINT;       // 各端口诊断码 / Diagnostic codes
    auCrcCnt        : ARRAY[1..8] OF UDINT;       // 各端口 CRC 累计计数 / CRC counters
    bDiagReset      : BOOL;                       // 首出复位 / Reset first-out
    bAnyPortFault   : BOOL;                       // 任一端口故障 / Any port faulted
    uFaultMask      : WORD;                       // 端口故障掩码 / Fault mask
    nFirstPort      : INT;                        // 首出端口号 / First-out port
    uFirstCode      : UDINT;                      // 首出诊断码 / First-out code
    bBurst          : BOOL;                       // 错误风暴单拍 / Burst flag
    auDelta         : ARRAY[1..8] OF UDINT;       // 各端口增量 / Per-port delta
    uPortDiagErr    : UDINT;                      // 事件码 / Event code
    bDiagErr        : BOOL;                       // 故障位 / Fault flag
    bStationAuto    : BOOL := TRUE;               // 工站自动模式 / Station in auto
    nHmiFirstFaultPort : INT;                     // 送 HMI 的首出端口号 / First-out port to HMI
    uHmiFirstFaultCode : UDINT;                   // 送 HMI 的首出诊断码 / First-out code to HMI
END_VAR

// 每周期无条件调用；三个数组由 IO 映射层按实际端口填入（未用端口填 TRUE/0）
fbPortDiag(bEnable := bStationAuto, bReset := bDiagReset, nPortCount := 4,
           abPortLinkOk := abLinkOk, auPortErrCode := auErrCode, auPortCrcErrCnt := auCrcCnt,
           nBurstThreshold := 10, tBurstWindow := T#1S, tDebounce := T#200MS,
           bAnyPortFault => bAnyPortFault, bBurstDetected => bBurst,
           uPortFaultMask => uFaultMask, nFirstFaultPort => nFirstPort,
           uFirstFaultCode => uFirstCode, auPortDelta => auDelta,
           bError => bDiagErr, uErrorId => uPortDiagErr,
           stState := stPortState);

// 首出端口号直接送 HMI 排故页；风暴标志只做趋势记录，不参与停机
IF bAnyPortFault AND (nFirstPort > 0) THEN
    nHmiFirstFaultPort := nFirstPort;
    uHmiFirstFaultCode := uFirstCode;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **三者数据源不同、码段不共享**：`FB_DL_AxiolineDiagLatch`（本地总线**模块级**：槽号 + 位域）/ `FB_DL_PdiReadScheduler`（参数对象**读取调度**）/ 本件（**端口级**：链路位 + 端口码 + CRC 计数），互不可替。
- **CRC 计数回绕按归零处理**：当前值小于基准时增量取当前值（绝不出巨大正数假风暴），`16#FFFF_FFFF → 3` 的增量为 3。
- **掩码位序**：`uPortFaultMask` 的 bit0 是 1 号端口，不是 0 号——与库内「索引 0 = bit0」的位序惯例一致（数组索引 1 对应 bit0）。
- **首出不是"最严重"**：本件按端口号排序而非按故障等级排序（端口码语义由设备厂商定义，块内不解释）；需要按等级排序时在上层映射。

---

## 42. FB_DL_StatusWordSegDecoder ｜ 段表驱动的状态字批量解码（R11，v1.0.0）

**定位 / Positioning**：用一张段描述表（≤16 段，每段 = 位偏移 + 位宽 + 名称）把设备状态字一次性解码成右对齐的值数组，**同一拍**给出越界 / 重叠 / 段数三类组态诊断与段状态位。替代「每个字段调一次单段提取」的碎片写法：一次调用拿全部字段，且组态错误在投运首日就被拦下。

**双宽域 / Width domain**：入口统一为 **64 位宽字**（`LWORD`），DWORD 调用方把高位补零即可。宽度是**参数域**而非语义差异，故不拆 32 位与 64 位两块。

**掩码构造纪律 / Mask discipline**：宽度 = 64 时**直接取全 1 常量，绝不做 64 位移位**（对 64 位字移位 64 属未定义行为，跨平台结果不一致）；其余宽度按「低位连续 1 左移偏移」两步构造，且宽度与偏移都在**段级校验通过之后**才参与移位（先校验后运算）。

**重叠策略 / Overlap policy**：用 64 位占位掩码逐段求与，非零即重叠。`bRejectOnOverlap = TRUE` 时后到段整段作废（值写 0、不计入有效段）；`FALSE` 时后到段生效（取后段值）并合并占位。**两种模式都置段状态位与 `0142`**，组态问题不会被静默吞掉。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 时值数组清零 / Enable; clears the value array |
| `bReset` | BOOL | IN | — | — | 清组态诊断，上升沿有效 / Clears configuration diagnostics |
| `uWord` | LWORD | IN | — | 位串 | 被解码状态字，64 位宽（DWORD 高位补零）/ Source word, 64 bits |
| `nSegCount` | INT | IN | — | 段 | 有效段数，有效域 1~16 / Valid segment count |
| `bRejectOnOverlap` | BOOL | IN | — | — | 重叠策略：真 = 整段拒绝，假 = 后段覆盖 / Overlap policy |
| `auValue` | ARRAY[1..16] OF UDINT | OUT | — | 值 | 各段解码值，右对齐；未定义段与作废段为 0 / Decoded values |
| `nValidCount` | INT | OUT | — | 段 | 实际成功解码的段数 / Segments decoded |
| `uSegStatusMask` | WORD | OUT | — | 位串 | 段状态位：置位表示该段越界或重叠被拒 / Segment status bits |
| `eState` | E_DL_SegDecodePhase | OUT | — | — | `eIdle` 0 / `eDecode` 10 / `eReject` 20 / `eFault` 99 |
| `bConfigFault` | BOOL | OUT | — | — | 段表组态故障（整表无可用段）/ Configuration fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无 / Event code |
| `stSegs` | ST_DL_BitSegTable | IN_OUT | — | — | 段描述表（`aSeg[1..16] OF ST_DL_BitSeg{nOffset, nWidth, sName}` + `nReserved`），**块内只读，禁止就地改写** / Segment table, read only here |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0142` | 信息级 | 段间重叠（拒绝模式下该段作废，覆盖模式下取后段值） | 有意重叠（冗余旧字段）用覆盖模式；无意重叠改段表偏移 |
| `0003_0143` | 信息级 | 段越界已拒绝（宽度 0 / 宽度超字宽 / 偏移加宽超字宽） | 该段值写 0，其余段照常解码；核对设备手册的位位置 |
| `0003_0144` | 信息级 | 段数越界已钳位（小于 1 或大于 16） | 段表实际填写数须与 `nSegCount` 一致 |
| `0003_0302` | 故障级 | 段表整体非法（无任何段可用）或非法状态兜底 | 至少一个合法段；改表后给 `bReset` 沿退回待机 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_VfdStatusDecode
VAR
    fbDecode      : FB_DL_StatusWordSegDecoder;  // 段表解码实例 / Segment decoder
    stSegTable    : ST_DL_BitSegTable;           // 段描述表 / Segment table
    uVfdStatus    : LWORD;                       // 变频器状态字（64 位入口）/ VFD status word
    auField       : ARRAY[1..16] OF UDINT;       // 解出的字段值 / Decoded fields
    nValidCnt     : INT;                         // 有效段数 / Valid segments
    uSegStatus    : WORD;                        // 段状态位 / Segment status bits
    eDecPhase     : E_DL_SegDecodePhase;         // 相位观测 / Phase
    bCfgFault     : BOOL;                        // 组态故障 / Configuration fault
    uDecErr       : UDINT;                       // 事件码 / Event code
    bDecInit      : BOOL := FALSE;               // 段表初始化完成 / Table initialised
    bDecReset     : BOOL;                        // 组态诊断复位 / Configuration reset
    nVfdState     : INT;                         // 解出的状态码 / Decoded state
    nVfdSpeed     : INT;                         // 解出的转速 [转每分] / Decoded speed
END_VAR

// 段表一次性组态（投运首日执行一次）：0~3 状态、4~7 报警、8~23 实际转速
IF NOT bDecInit THEN
    stSegTable.aSeg[1].nOffset := 0;
    stSegTable.aSeg[1].nWidth  := 4;
    stSegTable.aSeg[1].sName   := 'STATE';
    stSegTable.aSeg[2].nOffset := 4;
    stSegTable.aSeg[2].nWidth  := 4;
    stSegTable.aSeg[2].sName   := 'ALARM';
    stSegTable.aSeg[3].nOffset := 8;
    stSegTable.aSeg[3].nWidth  := 16;
    stSegTable.aSeg[3].sName   := 'SPEED';
    stSegTable.nReserved := 0;
    bDecInit := TRUE;
END_IF

// 每周期解码：一次调用拿全部字段，重叠按拒绝模式
fbDecode(bEnable := TRUE, bReset := bDecReset, uWord := uVfdStatus, nSegCount := 3,
         bRejectOnOverlap := TRUE,
         auValue => auField, nValidCount => nValidCnt, uSegStatusMask => uSegStatus,
         eState => eDecPhase, bConfigFault => bCfgFault, uErrorId => uDecErr,
         stSegs := stSegTable);

// 字段语义由调用方解释：STATE = 低 4 位、SPEED = bit8 起 16 位
nVfdState  := UDINT_TO_INT(auField[1]);
nVfdSpeed  := UDINT_TO_INT(auField[3]);
END_PROGRAM
```

**要点 / Notes**

- **投运五条检查**：① 段数与表内实际填写数一致（多填的段不解码）；② 偏移无需递增，但重叠必须是有意为之；③ 宽度 = 64 的段只允许一段且偏移必须为 0；④ 段名建议写设备手册原文缩写（排故时逐条对照）；⑤ **字节序不要用两个半字节段拼整字**（会触发重叠诊断），高低字节交换应在 IO 映射层完成。
- **`eReject` 不自动恢复**：组态问题必须人工确认后复位，避免「表错但偶发可用」时反复跳变；`eDecode` 允许逐拍重解，源字变化立即反映到值数组。
- **本族唯一的「组态级」件**：`FC_DL_BitGet`（单个位）/ `FB_DL_UnpackWordToBits`（固定 16 位）/ `FC_DL_BitFieldExtract`（单段）/ `FC_DL_WordBitPack`（单段打包）四件均为单点件，且本块内自写段提取、不调用任何单段件（避免二次越界检查与语义叠加）。

---

## 43. FB_DL_NtcTempScan ｜ 多通道 NTC 温度巡检（R11，v1.0.1）

**定位 / Positioning**：一块覆盖 1~16 路 NTC 热敏电阻的**完整设备对象**：B 值公式换算摄氏温度、逐通道断线与短路诊断、高温与低温判定、最热通道定位、超温累计次数与通道故障掩码。替代「每通道一个温控块」的堆叠写法——降低单拍负载与程序块数量，并把「哪一路最热」直接算好给 HMI。

**与相邻件的边界 / Boundary**：`FB_DL_AnalogTransmitter` 处理**直流电流/电压**变送器（线性标定 + 断线诊断，输入量纲 mA/V）；本块处理**电阻型**热敏电阻（非线性 B 值 + 阻值域诊断，输入量纲 Ω），两者不可互替。`FB_DL_HeatCoolZone` 是控温**执行**块（含调节输出）；本块**只测量与判定，不产生任何控制输出**。

**前置守卫 / Guards**：除法之前必须先判零——B 常数、标称阻值、基准温度、阻值比、算出的倒数温度，任一为零即本通道不参与换算并保持上一次温度。**绝不允许「先算后判」**（浮点除零在部分平台直接产生异常值）。

**扫描调度 / Scheduling**：`tScanPeriod > 0` 按节拍**轮询**，每拍只算一路（通道多时单拍负载恒定）；`= 0` 全通道每拍扫描（通道少、要求最快响应）。两种模式的输出数组都跨拍保持，未扫到的通道沿用上一拍结果。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 时保持上次温度 / Enable; holds the last temperatures |
| `bReset` | BOOL | IN | — | — | 复位通道故障锁存，上升沿有效 / Clears the channel fault latch |
| `nChannelCount` | INT | IN | — | 路 | 通道数，有效域 1~16，越界钳位 / Channel count, 1 to 16 |
| `afResistance` | ARRAY[1..16] OF REAL | IN | — | 欧姆 | 各通道阻值，量程 10~1.0E6 / Per-channel resistance |
| `fBeta` | REAL | IN | `3950.0` | 开尔文 | B 常数，典型 3435 / 3950 / Beta constant |
| `fR25` | REAL | IN | `10000.0` | 欧姆 | 25 ℃ 标称阻值 / Nominal resistance at 25 ℃ |
| `fT25` | REAL | IN | `298.15` | 开尔文 | 基准绝对温度 / Reference absolute temperature |
| `afTempHigh` | ARRAY[1..16] OF REAL | IN | — | 摄氏度 | 各通道高温阈值 / High temperature limit |
| `afTempLow` | ARRAY[1..16] OF REAL | IN | — | 摄氏度 | 各通道低温阈值 / Low temperature limit |
| `tScanPeriod` | TIME | IN | `T#100MS` | 毫秒 | 轮询节拍，0 = 全通道每拍扫描 / Scan period, 0 scans all |
| `afTempC` | ARRAY[1..16] OF REAL | OUT | — | 摄氏度 | 各通道温度，换算失败拍**保持不写零** / Per-channel temperature |
| `nHottestCh` | INT | OUT | — | — | 最热通道号 1~16，0 = 无有效通道（平局取小号）/ Hottest channel |
| `fHottestTemp` | REAL | OUT | — | 摄氏度 | 最热通道温度 / Hottest temperature |
| `bAnyOverTemp` | BOOL | OUT | — | — | 任一有效通道超高温阈值 / Any over temperature |
| `bAnyUnderTemp` | BOOL | OUT | — | — | 任一有效通道低于低温阈值 / Any under temperature |
| `uChannelFaultMask` | WORD | OUT | — | 位串 | 通道故障掩码，**位 n 对应通道 n+1**，锁存只增不减 / Channel fault mask |
| `eState` | E_DL_NtcScanPhase | OUT | — | — | `eIdle` 0 / `eScan` 10 / `eAllFail` 20 / `eFault` 99 |
| `bError` | BOOL | OUT | — | — | 故障级锁存，**仅 `0303`/`0304` 置位** / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无 / Event code |
| `stStat` | ST_DL_NtcStat | IN_OUT | — | — | 跨周期统计：`anOverTempCnt[1..16]`（上升沿计数）/ `anOpenCnt[1..16]`（进故障沿计数）/ `nScanRounds`（完整轮询圈数）/ Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0145` | 信息级 | 通道数越界已钳位（小于 1 或大于 16） | 改 `nChannelCount`；多余通道不参与判定 |
| `0003_0146` | 信息级 | 单通道断线或短路已跳过（保持上次温度） | 查接线与探头；整机可降级运行，不置故障位 |
| `0003_0303` | 故障级 | 全通道失效（有效通道数为零） | 检查公共接线或模块供电；**接线修复后自动退回巡检态，无需复位** |
| `0003_0304` | 故障级 | 换算参数非法已锁存（B 常数 / 标称阻值 / 基准温度） | 修好参数后仍需复位沿才退出（避免组态抖动反复进出故障） |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_FurnaceNtcScan
VAR
    fbNtc          : FB_DL_NtcTempScan;           // NTC 巡检实例 / NTC scanner
    stNtcStat      : ST_DL_NtcStat;               // 跨周期统计 / Persistent statistics
    afR            : ARRAY[1..16] OF REAL;        // 各通道阻值 [欧姆] / Resistances
    afTemp         : ARRAY[1..16] OF REAL;        // 各通道温度 [摄氏度] / Temperatures
    afHi           : ARRAY[1..16] OF REAL;        // 高温阈值 [摄氏度] / High limits
    afLo           : ARRAY[1..16] OF REAL;        // 低温阈值 [摄氏度] / Low limits
    nHottest       : INT;                         // 最热通道 / Hottest channel
    fHottest       : REAL;                        // 最热温度 / Hottest temperature
    bOverTemp      : BOOL;                        // 超温 / Over temperature
    bUnderTemp     : BOOL;                        // 低温 / Under temperature
    uChFaultMask   : WORD;                        // 通道故障掩码 / Channel fault mask
    bNtcErr        : BOOL;                        // 故障 / Fault
    uNtcErrId      : UDINT;                       // 事件码 / Event code
    bNtcReset      : BOOL;                        // 通道锁存复位 / Latch reset
    bFurnaceOn     : BOOL := TRUE;                // 炉体运行 / Furnace running
    bThermalAlarm  : BOOL := FALSE;               // 热工告警 / Thermal alarm
    nHmiHottestChannel : INT;                     // 送 HMI 的最热通道 / Hottest channel to HMI
END_VAR

// 每周期无条件调用：8 路 NTC，10 毫秒轮询一路，阈值 80/5 摄氏度
fbNtc(bEnable := bFurnaceOn, bReset := bNtcReset, nChannelCount := 8,
      afResistance := afR, fBeta := 3950.0, fR25 := 10000.0, fT25 := 298.15,
      afTempHigh := afHi, afTempLow := afLo, tScanPeriod := T#100MS,
      afTempC => afTemp, nHottestCh => nHottest, fHottestTemp => fHottest,
      bAnyOverTemp => bOverTemp, bAnyUnderTemp => bUnderTemp,
      uChannelFaultMask => uChFaultMask,
      bError => bNtcErr, uErrorId => uNtcErrId,
      stStat := stNtcStat);

// 超温或任一通道故障即时告警；最热通道号直接送 HMI
IF bOverTemp OR (uChFaultMask <> 16#0000) THEN
    bThermalAlarm := TRUE;
END_IF
nHmiHottestChannel := nHottest;
END_PROGRAM
```

**要点 / Notes**

- **锁存策略是刻意的**：单路探头损坏只置通道掩码与信息码（现场常见，整机降级运行）；只有「有效通道为零」（`0303`，可自恢复）与「换算参数非法」（`0304`，需复位）才置故障位。
- **v1.0.1 修复**：全扫模式的扫描圈数累加缺饱和守卫（与轮询分支不一致），长期运行会在 2³² 处回绕；已对两条分支统一加「小于上限」守卫。
- **B 值公式的适用域**：标称点附近误差最小，适合设备级巡检；高精度场合请改用分段查表并在上层标定（本件不承担计量级精度）。
- **最热通道平局取小号**：避免逐拍在两个同温通道之间来回跳变；全部通道无效时输出 0 并置 `0303`。

---

## 44. FB_DL_RollerGapAdjust ｜ 辊距微调背隙补偿（R11，v1.0.0）

**定位 / Positioning**：把「目标辊距 → 单向越程逼近（吃掉背隙）→ 反向精定位 → 到位窗口判定 → 偏差记账」封装成一个设备对象，输出电动缸位置指令与到位状态。解决电动缸双向逼近时背隙导致的重复定位偏差——让**每次调整都从同一侧逼近目标**。

**为什么必须两段 / Why two phases**：单向越程是背隙补偿的本体。把两段压成「一次赋值 + 到位判定」会丢掉「先越程再回退」的动作序列，重复定位精度退化到双向逼近水平——那正是普通定位块已有的能力，本件也就没有存在价值。故 `eApproach` 与 `eFine` **不可合并**。

**反馈丢失纪律 / Feedback loss**：位移反馈无效时指令**保持上一拍值，绝不清零**——对辊距来说指令清零等于辊缝全开，属危险侧动作。同时撤回到位标志（位置不可信）并置 `0306`，等待人工确认。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | — | — | 使能，`FALSE` 时指令保持、撤回到位标志 / Enable; holds the command, drops in-position |
| `bReset` | BOOL | IN | — | — | 复位故障，上升沿有效 / Clears the fault |
| `bAdjustStart` | BOOL | IN | — | — | 执行一次调整，上升沿触发 / Triggers one adjustment |
| `fGapSetpoint` | REAL | IN | — | 毫米 | 目标辊距，量程 0.0~20.0 / Target roller gap |
| `fGapActual` | REAL | IN | — | 毫米 | 位移传感器实测辊距 / Measured roller gap |
| `fGapTol` | REAL | IN | `0.02` | 毫米 | 到位容差，0 表示必须完全相等 / In-position tolerance |
| `fBacklash` | REAL | IN | `0.05` | 毫米 | 反向背隙补偿量，0 表示不补偿 / Backlash compensation |
| `fCmdMin` | REAL | IN | `0.0` | 毫米 | 指令下限 / Command lower limit |
| `fCmdMax` | REAL | IN | `20.0` | 毫米 | 指令上限 / Command upper limit |
| `bFeedbackValid` | BOOL | IN | — | — | 位移反馈有效（传感器自诊断汇总）/ Position feedback valid |
| `tMoveTimeout` | TIME | IN | `T#10S` | 毫秒 | 单次调整限时，0 表示不监控 / Adjustment timeout |
| `fGapCmd` | REAL | OUT | — | 毫米 | 电动缸位置指令，**故障时保持不写** / Actuator command |
| `bAdjusting` | BOOL | OUT | — | — | 调整进行中（逼近或精定位）/ Adjustment in progress |
| `bInPosition` | BOOL | OUT | — | — | 到位，保持到下次调整 / In position |
| `eState` | E_DL_GapPhase | OUT | — | — | `eIdle` 0 / `eApproach` 10 / `eFine` 20 / `eHold` 30 / `eFault` 99 |
| `bError` | BOOL | OUT | — | — | 故障级锁存，**仅 `0305`/`0306`/`0308` 置位** / Latched fault |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无 / Event code |
| `fLastDeviation` | REAL | OUT | — | 毫米 | 上次调整结束时的残余偏差 / Residual deviation |
| `nAdjustCount` | UDINT | OUT | — | 次 | 累计调整次数，**仅到位时累加**，饱和 / Adjustment counter |
| `stTrim` | ST_DL_GapTrimStat | IN_OUT | — | — | 跨周期统计：`fDevAvg`（残余偏差低通均值）/ `tLastMove`（上次耗时）/ `nOverTolCnt`（超容差次数，饱和）/ Persistent trim statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0147` | 信息级 | 目标间隙越界已钳位（含上下限颠倒时的自动换位） | 查配方辊距是否超机械行程；本件已钳位，不会把指令推出行程 |
| `0003_0148` | 信息级 | 背隙补偿量越界已钳位（负值或超上限） | 背隙应取实测值（正数）；负值说明标定符号反了 |
| `0003_0305` | 故障级 | 到位超时（限时内偏差始终未进入容差带） | 查机械卡滞、传感器漂移、背隙是否远大于设定 |
| `0003_0306` | 故障级 | 位移反馈无效或丢失（指令保持，撤回到位标志） | 查传感器供电与接线；**指令保持不动，禁止手动清零** |
| `0003_0308` | 故障级 | 非法相位兜底 | 枚举被外部强制写入未定义值；复位退出 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_RollerGapTrim
VAR
    fbGap          : FB_DL_RollerGapAdjust;      // 辊距微调实例 / Gap trim instance
    stTrimStat     : ST_DL_GapTrimStat;          // 跨周期统计 / Persistent statistics
    bGapStart      : BOOL;                       // 触发一次调整 / Start one adjustment
    bGapReset      : BOOL;                       // 故障复位 / Fault reset
    fGapTarget     : REAL := 2.500;              // 目标辊距 [毫米] / Target gap
    fGapMeas       : REAL := 2.515;              // 实测辊距 [毫米] / Measured gap
    fGapCmdOut     : REAL;                       // 电动缸指令 [毫米] / Actuator command
    bGapAdjusting  : BOOL;                       // 调整中 / Adjusting
    bGapInPos      : BOOL;                       // 到位 / In position
    eGapPhase      : E_DL_GapPhase;              // 相位观测 / Phase
    bGapErr        : BOOL;                       // 故障 / Fault
    uGapErrId      : UDINT;                      // 事件码 / Event code
    fGapDev        : REAL;                       // 残余偏差 [毫米] / Residual deviation
    nGapAdjustCnt  : UDINT;                      // 累计调整次数 / Adjustment counter
    bGapFbValid    : BOOL := TRUE;               // 传感器反馈有效 / Feedback valid
    bLineAuto      : BOOL := TRUE;               // 产线自动 / Line in auto
    fActuatorCmdMm : REAL;                       // 送电动缸的指令 [毫米] / Actuator command
    bGapMaintainHint : BOOL := FALSE;            // 保养提示 / Maintenance hint
END_VAR

// 每周期无条件调用：容差 0.02 毫米、背隙 0.05 毫米、限时 10 秒
fbGap(bEnable := bLineAuto, bReset := bGapReset, bAdjustStart := bGapStart,
      fGapSetpoint := fGapTarget, fGapActual := fGapMeas,
      fGapTol := 0.02, fBacklash := 0.05, fCmdMin := 0.0, fCmdMax := 20.0,
      bFeedbackValid := bGapFbValid, tMoveTimeout := T#10S,
      fGapCmd => fGapCmdOut, bAdjusting => bGapAdjusting, bInPosition => bGapInPos,
      eState => eGapPhase, bError => bGapErr, uErrorId => uGapErrId,
      fLastDeviation => fGapDev, nAdjustCount => nGapAdjustCnt,
      stTrim := stTrimStat);

// 指令送电动缸；反馈丢失时本件已保持指令不动，此处不做任何清零兜底
fActuatorCmdMm := fGapCmdOut;

// 偏差均值持续超容差说明机械磨损加速，提示保养
IF stTrimStat.nOverTolCnt > 20 THEN
    bGapMaintainHint := TRUE;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **不注入轴接口（刻意）**：辊距调整多为独立电动缸加位移传感器，注入轴接口会把设备层拖到运动层，破坏分层依赖方向。
- **指令写点极少**：只在相位跃迁拍写（进逼近写越程值、进精定位写目标值），其余拍一律不写——这天然满足「故障时指令保持」，不需要额外的保持逻辑。
- **两阶段算术**：阶段 A 指令 = 目标 − 背隙（逼近符号为负，先退到目标下方一个背隙）；反馈越程过半后进入阶段 B，指令回目标值，反向逼近吃掉整段背隙。两阶段都把指令钳在 `fCmdMin ~ fCmdMax` 内。
- **统计口径**：到位拍才写残余偏差、更新低通均值、更新耗时并对超容差累加；未到位不计入台账（超时件的 `nAdjustCount` 不累加）。

---

## 45. FB_DL_DeviceParamVerify ｜ 设备参数回读核对（R12，v1.0.1）

**定位 / Positioning**：把「组态期望参数块」与「设备回读参数块」按逐项容差比对，单拍内完成全项遍历，给出「一致 / 不一致」锁存结论、超差项数、首个超差下标与最大偏差。服务对象是驱动器参数下发后的回读确认、变频器多参数批量校验、智能仪表组态核对。

**为什么不能只判等 / Why not equality**：设备回读值经定点化与量纲换算，与组态值几乎总差最后几位。用等号判等会得到「永远不一致」，用统一容差又会让小量程项全被放过——故本件**按项给容差**，缺省项回落默认容差。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时结论与相位冻结 / Enable, freezes the verdict when FALSE |
| `bReset` | `BOOL` | IN | — | — | 上升沿复位故障与结论锁存 / Rising edge clears fault and verdict latch |
| `bAcknowledge` | `BOOL` | IN | — | — | 上升沿确认「不一致」结论 / Rising edge acknowledges a mismatch |
| `nItemCount` | `INT` | IN | `1` | 项 | 比对本数，域 1~64，越界钳位 / Item count, 1..64 |
| `afExpected` | `ARRAY[1..64] OF REAL` | IN | — | 工程单位 | 组态期望参数块 / Configured expectation block |
| `afActual` | `ARRAY[1..64] OF REAL` | IN | — | 工程单位 | 设备回读参数块 / Device readback block |
| `afTolerance` | `ARRAY[1..64] OF REAL` | IN | — | 工程单位 | 逐项容差，0 或负值回落默认容差 / Per item tolerance |
| `fDefaultTol` | `REAL` | IN | `0.01` | 工程单位 | 默认容差，不小于 1E-6 / Default tolerance |
| `tVerifyTimeout` | `TIME` | IN | `T#5S` | 毫秒 | 回读超时，**`T#0S` = 不监控** / Readback timeout, zero disables it |
| `stVerify` | `ST_DL_ParamVerifyState` | IN_OUT | — | — | 跨周期状态：上次结论与累计核对次数 / Persistent state bag |
| `bVerified` | `BOOL` | OUT | — | — | 本轮全部项在容差内 / All items within tolerance |
| `bMismatch` | `BOOL` | OUT | — | — | 不一致结论**锁存**，需确认 / Mismatch latched until acknowledged |
| `nDiffCount` | `INT` | OUT | — | 项 | 超差项数 / Out of tolerance item count |
| `nFirstDiffIdx` | `INT` | OUT | — | 索引 | 首个超差项下标，0 = 无 / First offending index |
| `fMaxDev` | `REAL` | OUT | — | 工程单位 | 最大绝对偏差 / Maximum absolute deviation |
| `nMaxDevIdx` | `INT` | OUT | — | 索引 | 最大偏差下标，0 = 无 / Index of the maximum deviation |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `030D`~`030F` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_ParamVerifyPhase` | OUT | — | — | 相位，见下 / Current phase |

状态枚举：`E_DL_ParamVerifyPhase`（`eIdle` 0 空闲 ／ `eWaiting` 10 等回读 ／ `eComparing` 20 比对 ／ `eMatch` 30 一致 ／ `eMismatch` 40 不一致 ／ `eFault` 99 故障）。
跨周期结构：`ST_DL_ParamVerifyState`（`bLastVerdict` / `nLastDiffCount` / `nLastFirstIdx` / `fLastMaxDev` / `uVerifyCount`）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_014D` | 信息级 | 比对本数越界已钳位到 1~64 | 超 64 项请分两次核对 |
| `0003_014E` | 信息级 | 本轮核对一致 | 正常结论；每轮核对入口会清码，不会驻留 |
| `0003_014F` | 信息级 | 负容差已取绝对值 | 容差填负数几乎总是笔误 |
| `0003_030D` | 故障级 | 回读出现非有限值（NaN / 无穷），结论不可信 | 检查通讯换算是否引入除零；不要用 NaN 直接比较 |
| `0003_030E` | 故障级 | 回读超时未就绪（回读块仍为全零） | 设备未上电或未进入可读状态；核对超时是否设得过短 |
| `0003_030F` | 故障级 | 非法相位兜底 | 检查在线修改与库版本是否匹配 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_DriveParamCheck
VAR
    fbVerify      : FB_DL_DeviceParamVerify;   // 核对实例 / Verifier instance
    stVerifyState : ST_DL_ParamVerifyState;    // 跨周期状态 / Persistent state
    afExpect      : ARRAY[1..64] OF REAL;      // 组态期望 / Configured values
    afReadback    : ARRAY[1..64] OF REAL;      // 设备回读 / Device readback
    afTol         : ARRAY[1..64] OF REAL;      // 逐项容差 / Per item tolerance
    bCheckRun     : BOOL := TRUE;              // 核对使能 / Verify enabled
    bCheckReset   : BOOL;                      // 复位 / Reset
    bAckMismatch  : BOOL;                      // 确认不一致 / Acknowledge
    bAllMatch     : BOOL;                      // 全部一致 / All match
    bHasMismatch   : BOOL;                     // 不一致锁存 / Mismatch latched
    nBadItems     : INT;                       // 超差项数 / Bad items
    nFirstBadItem : INT;                       // 首个超差 / First bad
    fBiggestDev   : REAL;                      // 最大偏差 / Biggest deviation
    nBiggestIdx   : INT;                       // 最大偏差下标 / Biggest index
    bCheckFault   : BOOL;                      // 故障 / Fault
    uCheckErr     : UDINT;                     // 事件码 / Event code
    eCheckPhase   : E_DL_ParamVerifyPhase;     // 相位观测 / Phase
    bAllowRun     : BOOL;                      // 允许工艺运行 / Permit process run
END_VAR

fbVerify(bEnable := bCheckRun, bReset := bCheckReset, bAcknowledge := bAckMismatch,
         nItemCount := 12, afExpected := afExpect, afActual := afReadback,
         afTolerance := afTol, fDefaultTol := 0.01, tVerifyTimeout := T#5S,
         stVerify := stVerifyState,
         bVerified => bAllMatch, bMismatch => bHasMismatch,
         nDiffCount => nBadItems, nFirstDiffIdx => nFirstBadItem,
         fMaxDev => fBiggestDev, nMaxDevIdx => nBiggestIdx,
         bError => bCheckFault, uErrorId => uCheckErr, eState => eCheckPhase);

// 组态未确认前不放行工艺；故障与不一致都算未确认
bAllowRun := bAllMatch AND (NOT bHasMismatch) AND (NOT bCheckFault);
END_PROGRAM
```

**要点 / Notes**

- **回读就绪的判据是「回读块非全零」**：设备尚未上电或通讯未建立时回读块通常是全零，本件据此判「未就绪」并跑超时。代价是**合法参数全为零**的设备会永远等到超时——若你的设备存在这种组态，请把 `tVerifyTimeout` 设为 `T#0S` 关闭监控，或先写入一个非零参数。
- **信息码按核对周期清除**：v1.0.1 修的正是这条（范式 R44）。原实现只在复位沿清码，首轮一致（`014E`）后 `uErrorId` 永久驻留，后续轮次的 `014D` / `014F` 被「仅当码为 0 才置」的判据永久压住，出现「码说一致、结论说不一致」。现在进入新一轮核对（`eIdle → eWaiting`）即清码。
- **两种结论语义不同**：`bVerified` 是**本轮**结论（逐轮刷新）；`bMismatch` 是**锁存**结论（需 `bAcknowledge` 或复位）。用 `bVerified` 做放行、用 `bMismatch` 做报警台账。
- **超时不是结论**：超时置 `030E` 并停在本相，**不会**给出「一致」或「不一致」。处理超时应当作「没核对过」，不能用上次结论放行。

---

## 46. FB_DL_PortDiagBoard ｜ 多组端口诊断看板与首出仲裁（R12，v1.0.0）

**定位 / Positioning**：把最多 4 个端口诊断聚合组（每组最多 8 端口）汇总成一张看板：屏蔽超界位后的各组掩码、全局故障端口总数、全局首出（组号 + 端口号 + 诊断码），以及按「组号优先、端口号次之」稳定排序的**前 3 个待修端口**。它回答现场两个问题：**现在还剩几个端口坏、先修哪一个**。

**分层 / Layering**：本件是**汇总层**，只消费端口级聚合结果（掩码 + 组内首出码），不实例化上游聚合块、不重算端口明细——聚合器实例由调用方按组各自持有，重复实例化会让同一批端口被算两遍。也不读模块级状态字（模块级归本地总线诊断锁存件，三层数据源分账已在 R11 收口）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 看板使能；`FALSE` 时掩码清零而**首出保持** / Enable, masks cleared while the first-out latch is kept |
| `bReset` | `BOOL` | IN | — | — | 上升沿清首出锁存与故障 / Rising edge clears the first-out latch |
| `nGroupCount` | `INT` | IN | `1` | 组 | 聚合组数，有效域 1~4 / Group count, 1..4 |
| `anGroupFaultMask` | `ARRAY[1..4] OF WORD` | IN | — | 位串 | 各组端口故障掩码，位 n−1 对应端口 n / Per group fault mask |
| `anGroupPortCount` | `ARRAY[1..4] OF INT` | IN | — | 个 | 各组实际端口数，有效域 1~8 / Ports per group, 1..8 |
| `anGroupFirstPort` | `ARRAY[1..4] OF INT` | IN | — | 端口号 | 各组声明的首出端口，**0 = 未填不校验** / Declared first-out port, zero skips the cross check |
| `auGroupFirstCode` | `ARRAY[1..4] OF UDINT` | IN | — | 代码 | 各组组内首出诊断码，0 = 未填 / Per group first-out code |
| `stBoard` | `ST_DL_BoardState` | IN_OUT | — | — | 跨周期：首出锁存与掩码差分基准 / Persistent latch and mask baseline |
| `nTotalFaultPort` | `INT` | OUT | — | 个 | 全局故障端口总数 / Total faulted ports |
| `nFirstGroup` | `INT` | OUT | — | 组 | 全局首出组号 1~4，0 = 无 / Global first-out group |
| `nFirstPort` | `INT` | OUT | — | 端口号 | 全局首出端口号 1~8，0 = 无 / Global first-out port |
| `uFirstCode` | `UDINT` | OUT | — | 代码 | 全局首出诊断码，0 = 未填 / Global first-out code |
| `anGroupMaskOut` | `ARRAY[1..4] OF WORD` | OUT | — | 位串 | 屏蔽超界位后的各组掩码 / Sanitised per group masks |
| `anTopPortNo` | `ARRAY[1..3] OF INT` | OUT | — | 编码 | 待修端口编码 = 组号×10 + 端口号，0 = 空位 / Top repair ports encoded |
| `auTopPortCode` | `ARRAY[1..3] OF UDINT` | OUT | — | 代码 | 各待修端口的诊断码 / Diagnostic code per top port |
| `bAnyFault` | `BOOL` | OUT | — | — | 总故障数 > 0 / Any faulted port present |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0309` / `030A` / `030C` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_BoardPhase` | OUT | — | — | `eIdle` 0 ／ `eScanning` 10 ／ `eFault` 99 / Current phase |

状态枚举：`E_DL_BoardPhase`（`eIdle` 0 ／ `eScanning` 10 ／ `eFault` 99）。跨周期结构：`ST_DL_BoardState`（`nLatchedGroup` / `nLatchedPort` / `uLatchedCode` / `bLatchValid` / `anLastMask[1..4]`）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0149` | 信息级 | 组数超上限已钳位到 4（只影响显示范围，不置故障位） | 把看板拆成两张，或减少分组 |
| `0003_014A` | 信息级 | 某组端口数超上限已钳位到 8 | 组态常见，非错误；确认 8 端口以上是否需要拆分 |
| `0003_014B` | 信息级 | 掩码超界位已屏蔽（不存在的端口不计入故障数） | 组态里掩码写超了，修正后码消失 |
| `0003_014C` | 信息级 | 组内声明首出端口与掩码推导值不一致（数据源未同步） | **最值得查的一条**：通常意味着上游聚合器与看板读的不是同一拍数据 |
| `0003_0309` | 故障级 | 组数小于 1，无诊断源 | 至少给 1 组；否则看板无意义 |
| `0003_030A` | 故障级 | 某组端口数小于 1，该组掩码含义不可信 | 端口数必须 ≥ 1；填 0 会让整组故障被静默丢弃 |
| `0003_030B` | **故障段趋势码** | 单拍掩码变化位数超阈值（8 位），判为组态刷新 | **只作趋势提示，不置 `bError`**；HMI 按级别着色，勿按号段着色 |
| `0003_030C` | 故障级 | 非法状态兜底（终端安全态） | 检查在线修改与库版本 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_RackPortBoard
VAR
    fbBoard        : FB_DL_PortDiagBoard;         // 看板实例 / Board instance
    stBoardState   : ST_DL_BoardState;            // 跨周期状态 / Persistent state
    aGrpMask       : ARRAY[1..4] OF WORD;         // 各组故障掩码 / Per group masks
    aGrpPorts      : ARRAY[1..4] OF INT := [8, 8, 4, 8];  // 各组端口数 / Ports per group
    aGrpFirst      : ARRAY[1..4] OF INT;          // 声明首出端口 / Declared first port
    auGrpCode      : ARRAY[1..4] OF UDINT;        // 组内首出码 / Group first-out codes
    bBoardRun      : BOOL := TRUE;                // 看板使能 / Board enabled
    bBoardReset    : BOOL;                        // 清首出锁存 / Clear latch
    nFaultPorts    : INT;                         // 故障端口总数 / Total faulted ports
    nFirstGrp      : INT;                         // 首出组 / First group
    nFirstPrt      : INT;                         // 首出端口 / First port
    uFirstDiag     : UDINT;                       // 首出诊断码 / First code
    aMaskOut       : ARRAY[1..4] OF WORD;         // 屏蔽后掩码 / Sanitised masks
    aTopPorts      : ARRAY[1..3] OF INT;          // 待修端口编码 / Top ports
    auTopCodes     : ARRAY[1..3] OF UDINT;        // 待修端口码 / Top codes
    bAnyPortFault  : BOOL;                        // 有故障 / Any fault
    bBoardFault    : BOOL;                        // 看板故障 / Board fault
    uBoardErr      : UDINT;                       // 事件码 / Event code
    eBoardPhase    : E_DL_BoardPhase;             // 相位观测 / Phase
    nRepairHint    : INT;                         // 首个待修端口编码 / First repair hint
END_VAR

fbBoard(bEnable := bBoardRun, bReset := bBoardReset, nGroupCount := 4,
        anGroupFaultMask := aGrpMask, anGroupPortCount := aGrpPorts,
        anGroupFirstPort := aGrpFirst, auGroupFirstCode := auGrpCode,
        stBoard := stBoardState,
        nTotalFaultPort => nFaultPorts, nFirstGroup => nFirstGrp, nFirstPort => nFirstPrt,
        uFirstCode => uFirstDiag, anGroupMaskOut => aMaskOut,
        anTopPortNo => aTopPorts, auTopPortCode => auTopCodes,
        bAnyFault => bAnyPortFault, bError => bBoardFault,
        uErrorId => uBoardErr, eState => eBoardPhase);

// 待修清单第 0 位即「先修哪个」：编码 = 组号×10 + 端口号
nRepairHint := aTopPorts[1];
END_PROGRAM
```

**要点 / Notes**

- **首出取「组号最小、再端口号最小」**：组号小者更靠近主站，与现场排故的因果顺序一致。首出**只在未锁存时仲裁**，锁存后只认复位沿——多个端口同时报警时 HMI 不会在几条之间跳来跳去。
- **`014C` 是数据源未同步的信号**：声明首出端口与掩码推导值不一致，说明上层聚合器与本件读的不是同一拍（或聚合器被实例化了两次）。看到这条先把数据源对齐，不要急着改掩码。
- **`030B` 不是故障**：掩码单拍跳变超 8 位判为「组态刷新」（比如整块 IO 卡被重新组态），只给趋势提示。它与 `0309`/`030A` 同处 `03xx` 号段，但**不置 `bError`**——HMI 必须按级别着色，按号段着色会误报。
- **掉使能保留首出**：`bEnable = FALSE` 只清掩码显示，首出锁存保留，便于「停机后排查」时仍能看到第一现场。清首出只认 `bReset`。
- **待修排序只给 3 个**：前 3 个待修端口按稳定次序填 `anTopPortNo`，第 4 个起不填（0 = 空位）。这不是缺陷——维修班组一次只处理 3 个，给多了反而降低执行率。

---

## 47. FB_DL_EnergyMeterAccum ｜ 电表冻结值累计与需量统计（R12，v1.0.1）

**定位 / Positioning**：按电表**冻结寄存器**语义拼装 32 位电能累计值（正反向各一），做单调性校验、换表与清零识别，并按窗口滑算平均需量与峰值需量。输出正向 / 反向 / 净电能、换表次数与单拍换表脉冲。

**诊断分层 / Diagnosis layering**：遵循 NAMUR NE43「原始值域诊断与工程量分离」——**先判原始 32 位拼装值的单调性，再做工程量换算**。这样标定系数填错只会让数值错，不会让「换表」判定失效。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时冻结累计与窗口（窗口停在剩余时间处）/ Enable, freezing accumulation and the window |
| `bReset` | `BOOL` | IN | — | — | 上升沿复位需量窗口与统计（峰值需量清零）/ Rising edge resets the window statistics |
| `uImportHi` | `UINT` | IN | — | LSB | 正向有功电能高字 / Import energy high word |
| `uImportLo` | `UINT` | IN | — | LSB | 正向有功电能低字 / Import energy low word |
| `uExportHi` | `UINT` | IN | — | LSB | 反向有功电能高字 / Export energy high word |
| `uExportLo` | `UINT` | IN | — | LSB | 反向有功电能低字 / Export energy low word |
| `fActivePower` | `REAL` | IN | — | kW | 当前有功功率 / Active power in kilowatts |
| `eWordOrder` | `E_DL_ByteOrder` | IN | `eAbcd` | — | 字序约定，复用既有枚举（大字序 / 小字序）/ Word order, defaults to big word order |
| `fKwhPerLsb` | `REAL` | IN | `0.1` | kWh/LSB | 每 LSB 对应电能，必须 > 0 / Kilowatt hours per LSB |
| `tDemandWindow` | `TIME` | IN | `T#15M` | 毫秒 | 需量统计窗口，不小于 1 s / Demand window, at least one second |
| `fRegressRatio` | `REAL` | IN | `0.01` | — | 判为换表的回退比例，域 0~1 / Regression ratio for a meter swap |
| `bFreezePulse` | `BOOL` | IN | — | — | 冻结寄存器刷新脉冲，**仅用于显示锁存** / Freeze register update pulse, display only |
| `stMeter` | `ST_DL_MeterState` | IN_OUT | — | — | 跨周期：上次原始值、累计基准、窗口累加器 / Persistent raw values and accumulators |
| `fImportTotal` | `REAL` | OUT | — | kWh | 正向累计电能 / Accumulated import energy |
| `fExportTotal` | `REAL` | OUT | — | kWh | 反向累计电能 / Accumulated export energy |
| `fNetTotal` | `REAL` | OUT | — | kWh | 净电能（正向 − 反向）/ Net energy |
| `fDemandAvg` | `REAL` | OUT | — | kW | 本窗口平均需量 / Average demand of the window |
| `fDemandPeak` | `REAL` | OUT | — | kW | 历史峰值需量，由复位清零 / Peak demand, cleared by reset |
| `fWindowEnergy` | `REAL` | OUT | — | kWh | 本窗口累计电能 / Energy accumulated in the window |
| `bMeterReset` | `BOOL` | OUT | — | — | 检到换表或清零，单拍脉冲 / Meter swap detected |
| `uResetCount` | `UDINT` | OUT | — | 次 | 换表与清零累计次数 / Swap events counted |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0310`~`0312` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_MeterPhase` | OUT | — | — | `eIdle` 0 ／ `eSampling` 10 ／ `eHeld` 20 ／ `eFault` 99 / Current phase |

状态枚举：`E_DL_MeterPhase`（`eIdle` 0 ／ `eSampling` 10 ／ `eHeld` 20 ／ `eFault` 99）。跨周期结构：`ST_DL_MeterState`（`uImportPrev` / `uExportPrev` / `fImportAcc` / `fExportAcc` / `fWindowEnergy` / `tWindowElapsed` / `fDemandPeak` / `uResetCount`）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0150` | 信息级 | 冻结值刷新抖动（回退量在回退阈值内），保持上次累计不累加 | 正常现象：冻结寄存器在同一冻结周期内可能被重复读 |
| `0003_0151` | 信息级 | 需量窗口小于 1 s，已按 1 s 兜底 | 需量窗通常 15 min；填秒级窗口几乎没有统计意义 |
| `0003_0152` | 信息级 | 换表回退比例越界，已钳到 0~1 | 比例过大易把抖动误判为换表，过小则漏判真换表 |
| `0003_0310` | 故障级 | 每 LSB 电能非正（量纲错，含除零隐患） | 检查电表铭牌与寄存器分辨率；改正后复位 |
| `0003_0311` | 故障级 | 有功功率非有限值，本拍不积分 | 上游功率计算出现除零或开方负数；修数据源 |
| `0003_0312` | 故障级 | 非法状态兜底（终端安全态） | 检查在线修改与库版本 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_FeederEnergy
VAR
    fbMeter      : FB_DL_EnergyMeterAccum;  // 电表实例 / Meter instance
    stMeterState : ST_DL_MeterState;        // 跨周期状态 / Persistent state
    bMeterRun    : BOOL := TRUE;            // 计量使能 / Metering enabled
    bMeterReset  : BOOL;                    // 月结复位 / Monthly reset
    uImpHi       : UINT;                    // 正向高字 / Import high word
    uImpLo       : UINT;                    // 正向低字 / Import low word
    uExpHi       : UINT;                    // 反向高字 / Export high word
    uExpLo       : UINT;                    // 反向低字 / Export low word
    fPowerKw     : REAL;                    // 有功功率 [kW] / Active power
    fImportKwh   : REAL;                    // 正向累计 [kWh] / Import total
    fExportKwh   : REAL;                    // 反向累计 [kWh] / Export total
    fNetKwh      : REAL;                    // 净电能 [kWh] / Net energy
    fDemandNow   : REAL;                    // 本窗平均需量 [kW] / Window average demand
    fDemandMax   : REAL;                    // 峰值需量 [kW] / Peak demand
    fWinKwh      : REAL;                    // 本窗电能 [kWh] / Window energy
    bSwapped     : BOOL;                    // 换表脉冲 / Swap pulse
    uSwapCnt     : UDINT;                   // 换表次数 / Swap count
    bMeterFault  : BOOL;                    // 故障 / Fault
    uMeterErr    : UDINT;                   // 事件码 / Event code
    eMeterPhase  : E_DL_MeterPhase;         // 相位观测 / Phase
    bBillReady   : BOOL;                    // 结算可用 / Billing ready
END_VAR

fbMeter(bEnable := bMeterRun, bReset := bMeterReset,
        uImportHi := uImpHi, uImportLo := uImpLo,
        uExportHi := uExpHi, uExportLo := uExpLo, fActivePower := fPowerKw,
        eWordOrder := E_DL_ByteOrder.eAbcd, fKwhPerLsb := 0.1,
        tDemandWindow := T#15M, fRegressRatio := 0.01, bFreezePulse := FALSE,
        stMeter := stMeterState,
        fImportTotal => fImportKwh, fExportTotal => fExportKwh, fNetTotal => fNetKwh,
        fDemandAvg => fDemandNow, fDemandPeak => fDemandMax, fWindowEnergy => fWinKwh,
        bMeterReset => bSwapped, uResetCount => uSwapCnt,
        bError => bMeterFault, uErrorId => uMeterErr, eState => eMeterPhase);

// 换表当拍禁止出账：本拍累计基准刚重置，任何结算都不可信
bBillReady := (NOT bMeterFault) AND (NOT bSwapped);
END_PROGRAM
```

**要点 / Notes**

- **换表按「回退」识别，按保守策略处理**：原始值回退超过 `fRegressRatio` 即判换表并重置累计基准，**不做 32 位回绕的无损续接**。这是有意保守：0.1 kWh/LSB 时满量程约 4.29 亿 kWh，真实场景回绕前必然换表。
- **暂停不吞窗口**：v1.0.1 修的正是这条。剩余时间原按「整窗 `tWinUse` − `ET`」计算，而恢复后定时器预置值已是 `tRemain`、`ET` 属于该**剩余窗**，二次暂停把两个不同基准相减，窗口被拉长到 1300 s、平均需量偏低约 31%。现在按本拍实际预置值求差。
- **`bFreezePulse` 只影响显示**：不参与累计判据。累计只认原始值单调性与窗口定点，冻结脉冲丢了不会丢电量。
- **字序 ≠ 字节序**：本件处理 32 位值由两个 16 位寄存器拼装时的**字间序**；`FC_DL_SwapBytes16/32` 处理**字节内序**。层次不同，参数切换时不要互填。
- **需量峰值的清零**：`fDemandPeak` 只由 `bReset` 清。月结请用复位沿，不要指望掉使能清峰（掉使能只冻结）。

---

## 48. FB_DL_VacuumGaugeMux ｜ 真空计双表融合与交叉校验（R12，v1.0.1）

**定位 / Positioning**：把粗抽段（皮拉尼）与精抽段（电容膜片）两块真空计的读数融合为一条连续压力：按带**迟滞**的量程判定切换采信表，在重叠区做**十倍程交叉校验**并给出偏差与质量分级。服务对象是镀膜、冻干、真空热处理、半导体前驱体等「从大气抽到毫帕、单表量程不够」的场合。

**为什么必须双表 + 重叠区 / Why two gauges**：皮拉尼从大气到约 10 Pa 可靠，电容膜片从 10 Pa 到 10 mPa 可靠，单表覆盖不了全量程；重叠区既是切换区也是**互检区**——两表在重叠区读数若差太多，必有一块坏了，此时宁可不发布压力也不能把错值送进工艺联锁。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时保持上次输出 / Enable, the last output is held while FALSE |
| `bReset` | `BOOL` | IN | — | — | 上升沿清故障与不一致锁存 / Rising edge clears fault and disagreement latch |
| `bAcknowledge` | `BOOL` | IN | — | — | 上升沿确认不一致（**不清故障锁存**）/ Acknowledges a disagreement, the fault latch stays |
| `fPiraniPa` | `REAL` | IN | — | Pa | 皮拉尼读数，有效域 > 1 nPa / Pirani reading in pascals |
| `bPiraniValid` | `BOOL` | IN | — | — | 皮拉尼数据有效 / Pirani valid flag |
| `fCapacitancePa` | `REAL` | IN | — | Pa | 电容膜片读数，有效域 > 1 nPa / Capacitance reading in pascals |
| `bCapacitanceValid` | `BOOL` | IN | — | — | 电容膜片数据有效 / Capacitance valid flag |
| `fSwitchPa` | `REAL` | IN | `10.0` | Pa | 切换点（皮拉尼量程上限），域 > 0 / Switchover pressure |
| `fOverlapDecades` | `REAL` | IN | `1.0` | 十倍程 | 重叠区宽度，域 0~3 / Overlap width in decades |
| `fAgreeTolDecades` | `REAL` | IN | `0.5` | 十倍程 | 交叉校验允许偏差，域 0.05~3 / Agreement tolerance |
| `fPressurePa` | `REAL` | OUT | — | Pa | 融合后压力 / Fused pressure |
| `eActiveGauge` | `E_DL_GaugeSel` | OUT | — | — | 当前采信表：`eNone` 0 ／ `ePirani` 10 ／ `eCapacitance` 20 / Active gauge |
| `bInOverlap` | `BOOL` | OUT | — | — | 处于重叠区 / Inside the overlap band |
| `bDisagree` | `BOOL` | OUT | — | — | 双表不一致锁存 / Disagreement latched |
| `fDeltaDecades` | `REAL` | OUT | — | 十倍程 | 两表偏差，单表可用时为 0 / Deviation in decades |
| `eQuality` | `E_DL_SignalQuality` | OUT | — | — | 融合质量，复用既有枚举（良好 / 不确定 / 坏）/ Fused quality |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0313`~`0315` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_GaugePhase` | OUT | — | — | `eIdle` 0 ／ `eSelect` 10 ／ `eOverlapCheck` 20 ／ `eFault` 99 / Current phase |

状态枚举：`E_DL_GaugeSel`（`eNone` 0 ／ `ePirani` 10 ／ `eCapacitance` 20）、`E_DL_GaugePhase`（`eIdle` 0 ／ `eSelect` 10 ／ `eOverlapCheck` 20 ／ `eFault` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0003_0153` | 信息级 | 重叠区宽度越界，已钳到 0~3 个十倍程 | 重叠宽度应覆盖两表都可信的区间，通常 1 个十倍程 |
| `0003_0154` | 信息级 | 一致性容差越界，已钳到 0.05~3 个十倍程 | 容差过小会让正常漂移被判不一致，过大则漏掉真故障 |
| `0003_0155` | 信息级 | 仅单表可用，融合质量为「不确定」（不置故障位） | 降级运行：压力仍发布但打质量标记，工艺侧应据此限制联锁动作 |
| `0003_0313` | 故障级 | 切换点非正，量程划分无意义 | `fSwitchPa` 必须 > 0；改正后复位 |
| `0003_0314` | 故障级 | 双表不一致或双表均失效，输出保持 | 先看 `fDeltaDecades` 判断差多少；单表失效查该表供电与信号 |
| `0003_0315` | 故障级 | 非法状态兜底（终端安全态） | 检查在线修改与库版本 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ChamberVacuum
VAR
    fbGauge      : FB_DL_VacuumGaugeMux;    // 双表融合实例 / Gauge mux instance
    bVacRun      : BOOL := TRUE;            // 采集使能 / Acquisition enabled
    bVacReset    : BOOL;                    // 复位 / Reset
    bVacAck      : BOOL;                    // 确认不一致 / Acknowledge
    fPir         : REAL;                    // 皮拉尼读数 [Pa] / Pirani reading
    bPirOk       : BOOL;                    // 皮拉尼有效 / Pirani valid
    fCap         : REAL;                    // 电容读数 [Pa] / Capacitance reading
    bCapOk       : BOOL;                    // 电容有效 / Capacitance valid
    fPressPa     : REAL;                    // 融合压力 [Pa] / Fused pressure
    eGauge       : E_DL_GaugeSel;           // 采信表 / Active gauge
    bOverlap     : BOOL;                    // 重叠区 / In overlap
    bGaugeBad    : BOOL;                    // 不一致锁存 / Disagreement
    fDecadeDelta : REAL;                    // 偏差 [十倍程] / Deviation
    eQual        : E_DL_SignalQuality;      // 质量 / Quality
    bGaugeFault  : BOOL;                    // 故障 / Fault
    uGaugeErr    : UDINT;                   // 事件码 / Event code
    eGaugePhase  : E_DL_GaugePhase;         // 相位观测 / Phase
    bVacReady    : BOOL;                    // 真空到位可放行 / Vacuum ready
END_VAR

fbGauge(bEnable := bVacRun, bReset := bVacReset, bAcknowledge := bVacAck,
        fPiraniPa := fPir, bPiraniValid := bPirOk,
        fCapacitancePa := fCap, bCapacitanceValid := bCapOk,
        fSwitchPa := 10.0, fOverlapDecades := 1.0, fAgreeTolDecades := 0.5,
        fPressurePa => fPressPa, eActiveGauge => eGauge, bInOverlap => bOverlap,
        bDisagree => bGaugeBad, fDeltaDecades => fDecadeDelta, eQuality => eQual,
        bError => bGaugeFault, uErrorId => uGaugeErr, eState => eGaugePhase);

// 真空到位放行：压力达标 + 质量良好 + 无故障 + 无不一致
bVacReady := (NOT bGaugeFault) AND (NOT bGaugeBad)
             AND (eQual = E_DL_SignalQuality.eGood) AND (fPressPa < 1.0);
END_PROGRAM
```

**要点 / Notes**

- **取值必须本拍复验**：v1.0.1 修的正是这条（范式 R42）。原实现在非重叠区按 `eSel` **直取原值**、未复验该表本拍是否仍可用——采信表在两相之间掉线时，会把该表的 0 或负值当压力发布，工艺联锁据此可能判「已到真空」。现在取值后按「取值表本拍可用性」门控发布，不可用则保持上次值并下拍重裁。
- **迟滞下门限 = 切换点 ÷ 10^(重叠宽度/2)**：默认切换点 10 Pa、重叠 1 个十倍程 → 下门限 3.162 Pa。压力在 3.162~10 Pa 之间时保持当前采信表不变，避免在切换点附近反复跳表。
- **单表降级不是故障**：只有一块表可用时输出 `0155` 且质量置「不确定」，压力照常发布。这是有意的：抽真空过程中单表失效仍需要趋势，不能整条线停。**但工艺联锁必须看质量位**，不能只看压力。
- **质量枚举借用**：`E_DL_SignalQuality` 是既有枚举，本件用 `eGood` 表示双表一致、`eUnderRange` 表示单表降级（不确定）、`eWireBreakLow` 表示不可采信（坏）。语义映射已在头注释登记，HMI 请按「良好 / 不确定 / 坏」三档显示。
- **`bAcknowledge` 不清故障**：确认只清「不一致」锁存，故障锁存仍然只认 `bReset`。理由是：不一致可能只是短暂漂移，而故障意味着测量链已不可信。

---
---

## 49. I_DL_DeviceHealth ｜ NE107 设备健康语言契约（R13，v1.0.0 ｜ 契约件 · NE107 诊断族属主）

**定位**：定义「任何设备都能回答的三个问题」的统一健康语言——① 我现在健康吗（NE107 四态 + 功能检查 + 未知，六态）；② 我的证据是什么（诊断码 + 证据来源槽号）；③ 这个状态持续多久了（当前态时长 + 锁存位）。本契约**只定义提问方式，不定义判据**：NE107 明确把判据留给实现者（不同设备失效机理不同，统一判据反而会把正确行为判错），也不定义视觉呈现（图标与颜色属 HMI 层）。本文件同时承载枚举 `E_DL_Ne107Status` 的定义，**全库唯一属主**——其余实现块只允许引用本类型，禁止复制枚举体（跨文件同名异型禁令）。

**编号即优先级**：枚举数值即仲裁序（0 最优先，取小者为最严等级），**不等于** NE107 官方图标的排列顺序，也**严禁按图改号**——改号会让全部实现块的仲裁方向静默反转，且编译期无法发现。步长 10 留空位便于后续插入细分等级；99（eUnknown）刻意远离常规带 0~40，任何「忘记处理未知态」的取小仲裁都会自然落到正常带之外。

### 49.1 状态枚举 / State Enum（`E_DL_Ne107Status`，同文件发布）

| 成员 | 值 | 语义 / Meaning |
|---|---|---|
| `eFailure` | 0 | 失效：信号不可信，须立即处理 / Failure, signal invalid |
| `eCheckFunction` | 10 | 功能检查：回路测试/仿真/标定中，信号暂时无效 / Function check |
| `eMaintenanceReq` | 20 | 需要维护：仍有效但已劣化，排入维护计划 / Maintenance required |
| `eOutOfSpec` | 30 | 超出规格：工艺/环境越界，测量不确定度上升 / Out of specification |
| `eOk` | 40 | 正常：无诊断激活 / OK |
| `eUnknown` | 99 | 未知：尚未取得有效数据（冷启动首拍）/ Unknown, no valid data yet |

### 49.2 属性 / Properties（10 条，全部只读 GET）

| 属性 / Property | 类型 / Type | 说明 / Description |
|---|---|---|
| `eHealth` | `E_DL_Ne107Status` | 当前健康态（仲裁后最严等级）/ Current health state |
| `uDiagCode` | `UDINT` | 当前诊断码，0 = 无码，段位 `16#0003_xxxx` / Active diagnostic code |
| `uSourceId` | `UINT` | 证据来源槽号，0 = 未定义 / Evidence source slot |
| `tDuration` | `TIME` | 当前态已持续时长，态切换即清零 / Duration of the current state |
| `bLatched` | `BOOL` | 是否锁存，TRUE 时只能经 `CmdReset` 退出 / Latched flag |
| `bDataValid` | `BOOL` | 本拍数据是否可用，与健康态**正交** / Data valid this scan |
| `fQuality` | `REAL` | 数据质量因子 0.0~1.0，仅作趋势参考，**不得作为报警判据** / Quality factor |
| `nCodeHistory` | `UINT` | 历史码计数（仅计数不存表，掉电不保持）/ Code change count |
| `sDeviceClass` | `STRING(16)` | 设备类别短名（如 VALVE / METER）/ Device class tag |
| `bSimulated` | `BOOL` | 仿真或强制模式（`eCheckFunction` 的典型来源）/ Simulation or forced mode |

### 49.3 方法 / Methods（2 个，均返回 BOOL 受理值）

| 方法 / Method | 受理语义 / Acceptance | 说明 / Description |
|---|---|---|
| `CmdAck` | 仅受理 `eMaintenanceReq` 与 `eOutOfSpec`，对 `eFailure` 一律返回 FALSE | 失效不能被应答掉，只能被修复或被复位（NE107 安全底线）；功能检查与未知无需应答 |
| `CmdReset` | 仅 `bLatched = TRUE` 时受理，否则返回 FALSE | 无锁存时复位无对象，返回 TRUE 会掩盖上层逻辑错误 |

方法均为**非阻塞单发语义**：只做「受理判定 + 登记请求」，实际动作由实现块主体状态机在下一拍执行（方法内直接改状态会与主体状态机同拍写冲突）。

### 49.4 调用示例 / Example

```iecst
PROGRAM PRG_HealthBoard
VAR
    iDev1 : I_DL_DeviceHealth;             // 任一实现块的接口引用 / Interface reference
    eBoardState : E_DL_Ne107Status;        // 仲裁结果 / Arbitrated state
    bAckOk      : BOOL;                    // 应答受理 / Ack accepted
END_VAR

IF iDev1 <> 0 THEN
    eBoardState := iDev1.eHealth;          // HMI 按数值取最严等级着色 / smallest value wins

    // 失效不可应答；维护请求与越规可应答
    IF (eBoardState = E_DL_Ne107Status.eMaintenanceReq)
    OR (eBoardState = E_DL_Ne107Status.eOutOfSpec) THEN
        bAckOk := iDev1.CmdAck();
    END_IF

    // 锁存态只认复位
    IF iDev1.bLatched THEN
        bAckOk := iDev1.CmdReset();
    END_IF
END_IF
END_PROGRAM
```

### 49.5 要点 / Notes

- **bDataValid 与 eHealth 正交**：「健康但数据陈旧」是合法组合（TRUE 健康 + FALSE 数据），实现者不得用数据有效性覆盖健康态，反之亦然。
- **已知限制**：单设备单健康出口（多子部件设备由上层聚合件做等级取最严）；不含时间戳（当前态起始时刻由 `tDuration` 反推）；不含文本描述（诊断文本属 HMI 多语言资源）。
- 本契约无执行体，行为验收下沉到实现块（§51~§54）；纯契约件，无故障码。

---

## 50. I_DL_PowerMeter ｜ 三相电表读侧契约（R13，v1.0.0 ｜ 契约件）

**定位**：三相电表的**读侧契约**——电量（电压/电流/功率/功率因数/频率）、电能质量（由实现块给出）、累计电能（正反向）、需量峰值与健康出口。上层能耗看板、需量控制、电能质量监视三件只需持有本接口引用，即可适配 Modbus 表、PROFIBUS 表、脉冲表与虚拟表四类实现，无需感知寄存器排布与通信调度方式。

**分层边界**：① 不含写侧（费率切换、需量窗写入、CT/PT 变比下装属配置层另件承担——读侧契约一旦开口写侧，配置错误就会污染测量数据）；② 不含通信调度（何时读寄存器由轮询主站决定，本契约只描述「读完之后的模型」）；③ 不含累计算法（累计口径由实现块自行声明，契约只承诺「单位 kWh 与单调不减的语义」）。

### 50.1 状态枚举 / State Enum（`E_DL_PowerMeterState`，同文件发布）

| 成员 | 值 | 语义 / Meaning |
|---|---|---|
| `eIdle` | 0 | 待机：未使能或标定未通过，输出保持 / Idle |
| `eSampling` | 10 | 正常计量：数据可用，判据全部在限内 / Sampling |
| `eDegraded` | 20 | 降级：越规但数据仍可信，继续计量并提示 / Degraded（越规不改数据可信度） |
| `eFault` | 99 | 故障：数据不可信或自相矛盾，锁存待复位 / Fault（数据不可信） |

`eDegraded` 与 `eFault` 的分界是本枚举的核心语义——对应 NE107 的 S（Out of specification）与 F（Failure）之别。现场最常见误判：把「电压偏高」当故障停机、把「表掉线」当越规只做提示。

### 50.2 属性 / Properties（12 条，全部只读 GET）

| 属性 / Property | 类型 / Type | 说明 / Description |
|---|---|---|
| `eState` | `E_DL_PowerMeterState` | 计量状态 / Metering state |
| `eHealth` | `E_DL_Ne107Status` | NE107 健康态（类型**引用自** `I_DL_DeviceHealth`，本文件不重复声明枚举体）/ NE107 health |
| `uDiagCode` | `UDINT` | 诊断码，0 = 无码，段位 `16#0003_xxxx` / Diagnostic code |
| `fVoltageAvg` | `REAL` | 三相平均相电压 [V]，0~400 / Average phase voltage |
| `fCurrentAvg` | `REAL` | 三相平均电流 [A]，0~10000 / Average phase current |
| `fActivePowerTotal` | `REAL` | 三相总有功 [kW]，**有符号，负 = 反送**，实现块不得绝对值化 / Total active power, signed |
| `fReactivePowerTotal` | `REAL` | 三相总无功 [kvar]，0~30000 / Total reactive power |
| `fPowerFactorTotal` | `REAL` | 总功率因数，口径 P/S（含符号），非表内寄存器直读值 / Total power factor |
| `fFrequency` | `REAL` | 电网频率 [Hz]，45~65 / Grid frequency |
| `fEnergyImport` / `fEnergyExport` | `LREAL` | 正/反向累计电能 [kWh]，单调不减（换表除外）/ Import/export energy |
| `fDemandPeak` | `REAL` | 历史峰值需量 [kW]，**仅复位可清**，窗口切换不得清零 / Peak demand |

### 50.3 方法 / Methods（3 个）

| 方法 / Method | 受理语义 / Acceptance |
|---|---|
| `CmdResetEnergy` | 仅**无故障锁存**时受理（`bLatched` 语义由实现块等同 `bError`）——故障期清零会把「表读数」与「累计基准」同时抹掉，事后无法追溯换表真伪 |
| `CmdReset` | 仅存在锁存时返回 TRUE |
| `CmdAck` | 与 `I_DL_DeviceHealth` 对齐：仅受理维护与越规，对失效返回 FALSE |

### 50.4 调用示例 / Example

```iecst
PROGRAM PRG_MeterDashboard
VAR
    iMeter  : I_DL_PowerMeter;      // Modbus 表 / PROFIBUS 表 / 虚拟表同一契约 / Any meter implementation
    fPAvg   : REAL;                 // 平均有功 [kW] / Average active power
    fEImp   : LREAL;                // 累计正向电能 [kWh] / Import energy
    bRstOk  : BOOL;                 // 受理回执 / Acceptance
END_VAR

IF iMeter <> 0 THEN
    fPAvg := iMeter.fActivePowerTotal;   // 负值 = 反送电，看板必须显示 / signed!
    fEImp := iMeter.fEnergyImport;

    // 月结清零：故障期拒绝受理（读数与基准会一起被抹掉）
    IF iMeter.eState <> E_DL_PowerMeterState.eFault THEN
        bRstOk := iMeter.CmdResetEnergy();
    END_IF
END_IF
END_PROGRAM
```

### 50.5 要点 / Notes

- **规格偏离裁定**：规格表头写「属性段 11 条」但表体列 12 行——按**表体 12 条**实现（表体是引脚级契约，表头是笔误），已登记留档。
- 全部电气量均为**已换算的工程量**，原始寄存器与标定系数不进契约——契约层不做换算，避免「同一物理量两种单位」的双口径。
- 已知限制：单表单契约（多表并联由上层持多个引用）；不含分相功率（无分相能力的实现不被迫伪造分相值）；不含事件顺序记录。

---

## 51. FB_DL_ModbusPowerMeter ｜ Modbus 三相电表实现（R13，v1.0.1）

**定位**：`I_DL_PowerMeter` 的 Modbus 表实现（IMPLEMENTS）：三相原始值换算 + 32 位电能四字序拼装 + 功率因数复算交叉校验 + 轻载抑制 + 15 min 需量窗 + NE107 六态健康出口。与既有 `FB_DL_EnergyMeterAccum` 分层明确：口径可沿用（32 位拼装 + 单调性），码位严禁复制。

**电能单调性三段律**：大于才递推 ｜ 小幅回退保持 ｜ 大幅回退判换表并重载基准。32 位回绕（16#FFFF_FFFF → 0）在可观测信息上与换表不可区分，按换表路径处理（重载基准 + `uMeterSwapCount` + 0318 维护码）。

### 51.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能，FALSE 冻结计量与窗口 / Enable |
| `bReset` | `BOOL` | IN | — | — | 复位窗口/峰值/锁存，上升沿有效 / Rising edge reset |
| `auVoltageRaw` | `ARRAY[1..3] OF UINT` | IN | — | LSB | 三相相电压原始值，0.1 V/LSB / Raw phase voltages |
| `auCurrentRaw` | `ARRAY[1..3] OF UINT` | IN | — | LSB | 三相电流原始值，0.01 A/LSB / Raw phase currents |
| `iActivePowerRaw` | `DINT` | IN | — | LSB | 总有功原始值，0.001 kW/LSB，有符号 / Raw active power, signed |
| `uReactivePowerRaw` | `UINT` | IN | — | LSB | 总无功原始值，0.001 kvar/LSB / Raw reactive power |
| `uEnergyImportHi/Lo` | `UINT` ×2 | IN | — | LSB | 正向电能高/低字 / Import energy words |
| `uEnergyExportHi/Lo` | `UINT` ×2 | IN | — | LSB | 反向电能高/低字 / Export energy words |
| `uFreqRaw` | `UINT` | IN | — | LSB | 频率原始值，0.01 Hz/LSB / Raw frequency |
| `uThdVoltRaw` / `uThdCurrRaw` | `UINT` | IN | — | LSB | 电压/电流总谐波畸变原始值，0.1 %/LSB / Raw THD |
| `iPfRaw` | `INT` | IN | `0` | LSB | 表内功率因数原始值，0.001/LSB；0 = 表未提供（不误报） / Raw meter PF, zero means absent |
| `eWordOrder` | `E_DL_ByteOrder` | IN | `eAbcd` | — | 32 位电能字序约定（变化检测置 0158 并重载基准）/ Word order |
| `fVoltPerLsb` / `fCurrPerLsb` / `fKwhPerLsb` | `REAL` | IN | `0.1` / `0.01` / `0.1` | — | 标定系数，非正判故障 0316 / Scale factors |
| `fVoltNominal` / `fCurrentNominal` | `REAL` | IN | `220.0` / `100.0` | V / A | 额定相电压/电流；后者是轻载判据基准（补引脚，规格偏离②）/ Nominals |
| `fVoltTolRatio` | `REAL` | IN | `0.10` | — | 电压允许偏差比，域 0~0.5 / Voltage tolerance ratio |
| `fPfLimit` | `REAL` | IN | `0.85` | — | 功率因数下限（取绝对值比较），域 0.5~1.0 / PF lower limit |
| `fThdLimit` | `REAL` | IN | `5.0` | % | 谐波上限，域 1.0~50.0 / THD limit |
| `fLightLoadRatio` | `REAL` | IN | `0.02` | — | 轻载判据比例，域 0~0.5 / Light-load ratio |
| `tDemandWindow` | `TIME` | IN | `T#15M` | — | 需量窗口，域 ≥ 1 s（过小按 1 s 兜底置 0157）/ Demand window |
| `tStaleTimeout` | `TIME` | IN | `T#5S` | — | 数据陈旧超时，超时判 Failure / Stale timeout |
| `bValid` / `bError` / `uErrorId` | `BOOL` / `BOOL` / `UDINT` | OUT | — | — | 本拍有效 / 故障锁存（0318 不置位）/ 末次故障码 / Valid, fault latch, code |
| `afVoltagePhase` | `ARRAY[1..3] OF REAL` | OUT | — | V | 分相电压 / Per-phase voltages |
| `fApparentPower` | `REAL` | OUT | — | kVA | 视在功率 = √(P² + Q²) / Apparent power |
| `fEnergyNet` | `LREAL` | OUT | — | kWh | 净电能 = 正向 − 反向 / Net energy |
| `fThdVoltageMax` / `fThdCurrentMax` | `REAL` | OUT | — | % | 电压/电流 THD 最大值 / Max THD |
| `fDemandAvg` | `REAL` | OUT | — | kW | 本窗口平均需量（窗内拍算术平均，等扫描周期下与时间加权等价）/ Average demand |
| `bPhaseLoss` | `BOOL` | OUT | — | — | 缺相：一相低于 20% 额定且另两相正常 / Phase loss |
| `bReversePower` | `BOOL` | OUT | — | — | 反送电：有功为负且绝对值超 5% 额定 / Reverse power |
| `uMeterSwapCount` | `UDINT` | OUT | — | 次 | 换表或清零识别次数 / Swap counter |
| 接口属性 `eState` / `eHealth` / `uDiagCode` 等 | 见 §50 | OUT | — | — | 实现 `I_DL_PowerMeter` 12 属性 + 3 方法 / Contract properties |

**状态机**（复用 `E_DL_PowerMeterState`，不另立同构枚举）：`eIdle(0)` → `eSampling(10)` ⇄ `eDegraded(20)`（往返可达）→ `eFault(99)`（锁存，复位沿且原因消失才退出）。

### 51.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0156` | 三相电压不平衡度 > 2% 但未越限 / Unbalance advisory | 否 | 查三相负载分配 |
| `16#0003_0157` | 需量窗口 < 1 s 已按 1 s 兜底 / Window clamped to 1 s | 否 | 检查 `tDemandWindow` 组态 |
| `16#0003_0158` | 字序参数改变，首拍重载累计基准 / Word order changed | 否 | 确认表计字序配置；重载后电能从新基准累计 |
| `16#0003_0159` | 轻载下 PF/THD 越限被抑制 / Suppressed at light load | 否 | 正常抑制行为；负荷回升后恢复判据 |
| `16#0003_015A` | 复算功率因数与表值偏差 > 3% / PF mismatch | 否 | 查表内 PF 寄存器定义或接线 |
| `16#0003_015B` | 频率越限（±0.5 Hz 带） / Frequency out of band | 否 | 查电网质量 |
| `16#0003_0316` | 电压/电流/电能标定非正 / Illegal scale factor | **是** | 修正标定；需 `bReset` 退出 |
| `16#0003_0317` | 原始寄存器全零且超陈旧超时 / All-zero stale | **是** | 表掉线；恢复供数后仍需 `bReset`（锁存语义） |
| `16#0003_0318` | 电能累计回退（换表或清零）——**维护语义，不置 bError** / Meter swap | **否（裁定）** | 核对是否真的换表；误报请检查字序与标定 |
| `16#0003_0319` | 非法状态兜底 / Illegal state | **是** | 断电重启并上报 |
| `16#0003_031A` | 三相电流全零而有功非零（自相矛盾）/ Zero current with power | **是** | 查电流互感器接线 |
| `16#0003_031B` | 有功功率拼装结果非有限 / Non-finite power | **是** | 查寄存器来源 |

### 51.3 调用示例 / Example

```iecst
PROGRAM PRG_MeterRead
VAR
    fbMeter      : FB_DL_ModbusPowerMeter;   // 电表实现 / Meter implementation
    auVRaw       : ARRAY[1..3] OF UINT;      // 三相电压原始值 / Raw voltages
    auIRaw       : ARRAY[1..3] OF UINT;      // 三相电流原始值 / Raw currents
    iPRaw        : DINT;                     // 有功原始值 / Raw active power
    uImpHi, uImpLo, uExpHi, uExpLo : UINT;   // 32 位电能字 / Energy words
    bMeterEn     : BOOL;                     // 使能 / Enable
    bMeterRst    : BOOL;                     // 复位 / Reset
    fKwNow       : REAL;                     // 有功 [kW] / Active power
    fKwhImp      : LREAL;                    // 累计电能 [kWh] / Import energy
END_VAR

fbMeter(
    bEnable        := bMeterEn,
    bReset         := bMeterRst,
    auVoltageRaw   := auVRaw,
    auCurrentRaw   := auIRaw,
    iActivePowerRaw:= iPRaw,
    uEnergyImportHi:= uImpHi, uEnergyImportLo := uImpLo,
    uEnergyExportHi:= uExpHi, uEnergyExportLo := uExpLo,
    eWordOrder     := E_DL_ByteOrder.eAbcd);

fKwNow  := fbMeter.fActivePowerTotal;    // 经属性出口，有符号 / signed
fKwhImp := fbMeter.fEnergyImport;
IF fbMeter.bError THEN
    ;   // uErrorId ∈ {0316,0317,0319,031A,031B}，需复位退出
END_IF
END_PROGRAM
```

### 51.4 要点 / Notes

- **v1.0.1 修复两条**：① `_bPfMismatch` 补每拍预清零——原实现无清零点，一次 015A 即永久 `eDegraded`（`eDegraded → eSampling` 不可达，R34 违例）；② 字序枚举比较改用声明区基准量 `_eOrderAbcd`/`_eOrderCdab`，语句段禁裸类型名（与 `FB_DL_EnergyMeterAccum` 范式一致，机检 FAIL 归零）。
- **0318 不置 bError（码位级裁定）**：换表是「维护请求」不是「不可继续运行」；但同件的失效级码（0316/0317/031A/031B）置位时 `uErrorId` 必有对应码——`bError` 的每一个置位源都必须能在 `uErrorId` 找到对应码。
- **需量口径**：窗内拍算术平均；等扫描周期下与时间加权等价，扫描抖动大时有偏差（观察项留档，后续需量件加时间加权开关）。
- **首拍只装基准不判回退**（R19）：上电首拍不发布电能量判据；`eHealth` 首拍为 `eUnknown`。

---

## 52. FB_DL_ValveStictionDetect ｜ 阀门黏滞在线诊断（R13，v1.0.1）

**定位**：基于 OP/PV 反转点同指令差分的滞环估计——在准静态反转点取「同 OP 下 PV 上行与下行的差」，累积成黏滞带估计值，给出四档严重度与停滞/反转事件统计。三判据并发升级：黏滞带定档，但 Moderate 及以上必须另有停滞或反转证据佐证（缺一不升级——不因单点指标越限判重度）。

**文献反向结论（已留档）**：无单一判据 100% 可信。判据 (a)（同 OP 差分）只在准静态可信——全行程单向斜坡下无可比反转点，黏滞带恒 0、等级恒 `eNone` 是**保守盲区**而非漏判（裁定保留：任何「持续运动上取同 OP 差分」的补丁都会把纯跟随滞后误算成黏滞）。本件输出定位为**趋势判据而非计量量化**。

### 52.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能，FALSE 时窗口冻结 / Enable |
| `bReset` | `BOOL` | IN | — | — | 复位锁存与统计，上升沿有效 / Rising edge reset |
| `fCmd` | `REAL` | IN | — | % | 阀门指令 OP，0~100 / Valve command |
| `fPos` | `REAL` | IN | — | % | 阀位反馈 PV，0~100 / Valve position feedback |
| `bPosValid` | `BOOL` | IN | `TRUE` | — | 反馈有效性，FALSE 时诊断挂起（**非故障**，015D）/ Feedback validity, FALSE suspends |
| `fMoveThr` | `REAL` | IN | `0.5` | % | 判阀位在动的位移阈，域 0.1~5.0 / Movement threshold |
| `fStallThr` | `REAL` | IN | `1.0` | % | 判指令在变的变化阈，域 0.2~10.0 / Command change threshold |
| `tStallTime` | `TIME` | IN | `T#2S` | — | 停滞持续判据，域 100 ms~60 s / Stall duration |
| `tReverseTime` | `TIME` | IN | `T#1S` | — | 反转确认允许延迟，域 100 ms~30 s / Reverse confirmation delay |
| `tWindow` | `TIME` | IN | `T#60S` | — | 分析窗长，域 10 s~30 min / Analysis window |
| `nMinSamples` | `INT` | IN | `30` | 个 | 窗口最少有效样本，域 5~1000 / Minimum samples |
| `fDeadbandMax` | `REAL` | IN | `5.0` | % | 黏滞带上限（超此判 Severe），域 0.5~20.0；默认阈值下 Severe 需 ≥ 5% 滞后带 / Severe limit |
| `fDeadbandModerate` | `REAL` | IN | `2.0` | % | 黏滞带中限（超此判 Moderate），域 0.1~上限 / Moderate limit |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |
| `eStiction` | `E_DL_StictionLevel` | OUT | — | — | `eNone(0)` / `eSlight(10)` / `eModerate(20)` / `eSevere(30)`（保持语义）/ Stiction level, held |
| `fDeadbandEst` | `REAL` | OUT | — | % | 黏滞带估计，保持并钳 0~100 / Estimated band |
| `fHysteresisRatio` | `REAL` | OUT | — | — | 方向性滞后归一指标 = 黏滞带/全行程，0~1 / Normalised hysteresis |
| `nStallCount` | `UDINT` | OUT | — | 次 | 停滞事件累计，仅复位清 / Stall counter |
| `tSinceLastStall` | `TIME` | OUT | — | ms | 距上次停滞事件时长（TON 封顶 24 h 饱和）/ Time since last stall |
| `nSampleCount` | `UINT` | OUT | — | 个 | 本窗有效样本数 / Samples in window |
| `bStictionSuspect` | `BOOL` | OUT | — | — | 嫌疑位，任一判据成立即 TRUE（早期 HMI 提示）/ Suspect flag |

**状态机**（`E_DL_StictionPhase`）：`eIdle(0)` → `eCollect(10)` ⇄ `eAnalyze(20)` → `eVerdict(30)` → 回采集；`eSuspend(40)`（反馈失效，非故障，恢复后窗口重建首窗不发布）；`eFault(99)`（参数非法/非有限，锁存）。

### 52.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0003_015C` | 窗口样本不足或重建窗，未发布新等级 / Insufficient samples, nothing published | 否 | 等窗口累计；等级保持上次值 |
| `16#0003_015D` | 反馈失效诊断挂起提示 / Suspended | 否 | 查阀位反馈；恢复后窗口重建（首窗不发布） |
| `16#0003_015E` | 重建窗首窗不发布，保持上次等级 / Rebuild window | 否 | 恢复首窗只重建统计，比「不判 Severe」更严 |
| `16#0003_031D` | 指令或阀位非有限 / Non-finite input | **是** | 查信号源；需 `bReset` 退出；黏滞带保持并夹 0~100 |
| `16#0003_031E` | 阈值参数非法 / Illegal thresholds | **是** | 检查 `fDeadbandModerate < fDeadbandMax` 等 |
| `16#0003_031F` | 非法状态兜底 / Illegal state | **是** | 断电重启并上报 |

### 52.3 调用示例 / Example

```iecst
PROGRAM PRG_ValveStiction
VAR
    fbStick   : FB_DL_ValveStictionDetect;   // 黏滞诊断 / Stiction diagnosis
    fOpOut    : REAL;                        // PID 输出 OP [%] / Command
    fPvIn     : REAL;                        // 阀位反馈 PV [%] / Feedback
    bPvOk     : BOOL;                        // 反馈有效 / Feedback valid
    bValveEn  : BOOL;                        // 使能 / Enable
    bValveRst : BOOL;                        // 复位 / Reset
    eLevel    : E_DL_StictionLevel;          // 等级 / Level
    fBand     : REAL;                        // 黏滞带 [%] / Band
END_VAR

fbStick(
    bEnable    := bValveEn,
    bReset     := bValveRst,
    fCmd       := fOpOut,
    fPos       := fPvIn,
    bPosValid  := bPvOk,
    tWindow    := T#60S,
    nMinSamples:= 30);

eLevel := fbStick.eStiction;      // 保持语义 / held
fBand  := fbStick.fDeadbandEst;
IF fbStick.bStictionSuspect AND (eLevel < E_DL_StictionLevel.eModerate) THEN
    ;   // 早期提示：先于定档的嫌疑位 / early hint before grading
END_IF
END_PROGRAM
```

### 52.4 要点 / Notes

- **黏滞是退化不是失效**：等级映射 `eNone→eOk`、`eSlight/eModerate→eMaintenanceReq`、`eSevere→eOutOfSpec`；故障仅来自参数非法/非有限（`eFailure`）。
- **跨相复验（R42）**：判定拍 `bPosValid = FALSE` 时**不发布新等级**（保持 + 015D），绝不用缓存样本直接出结论。
- **恢复不重头（R41）**：挂起恢复后统计全部清零、基准重装、`_bRebuildWin` 置位——首窗只重建不发布，比规格更严。
- **默认阈值下 Severe 需 ≥ 5% 滞后带**：规格向量「3% 阶梯 → eSevere」与默认 `fDeadbandMax = 5%` 不自洽，3% 阶梯样本被封顶 `eModerate`（规格勘误已移交回写）。
- `tSinceLastStall` 由 TON 封顶 24 h，超过即饱和——不要拿它做「超过 24 h 无停滞」的精确判据。

---

## 53. FB_DL_AhuDamperStuckDiag ｜ AHU 风阀卡滞三分类诊断（R13，v1.0.1）

**定位**：AHU 风阀的**三分类失效诊断**（T2-6 Rockwell 三分类范式落地）——`eFullStall`（指令已动、位移低于阈值持续 `tStallTime`：一步未动）/ `eTransitStall`（已离位未达目标，超 `tTravelNominal × fSlowRatio` + 宽限：动了但没到）/ `eIoFault`（反馈失效超 `tIoFaultTime`：信号本身不可信），另带两工艺级 `eDeviation`（稳态偏差超限持续 `tDevDelay`）/ `eSlow`（到位但超行程倍率）。**三类判据各带独立确认窗**；把「要停机」（Full Stall / Transit Stall / IoFault）和「要排计划」（Deviation / Slow）分开，而不是一个笼统的 bAlarm。

### 53.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` / `bReset` | `BOOL` | IN | — | — | 使能 / 复位锁存（上升沿） / Enable and reset |
| `fCmd` | `REAL` | IN | — | % | 阀位指令，0~100；超域钳位并置 0161（钳位不静默）/ Damper command |
| `fPosFb` | `REAL` | IN | — | % | 阀位反馈，0~100 / Position feedback |
| `bFbValid` | `BOOL` | IN | `TRUE` | — | 反馈有效，AI 断线时为 FALSE / Feedback validity |
| `bLimitOpen` / `bLimitClose` | `BOOL` | IN | `FALSE` | — | 开/关到位限位（无此限位恒 FALSE）/ Limit switches |
| `tTravelNominal` | `TIME` | IN | `T#30S` | — | 全行程标称时间，域 1 s~10 min / Nominal travel time |
| `fTolPos` | `REAL` | IN | `3.0` | % | 到位容差，域 0.5~10.0 / In-position tolerance |
| `fDevLimit` | `REAL` | IN | `10.0` | % | 稳态偏差上限，域 1.0~50.0 / Deviation limit |
| `tDevDelay` | `TIME` | IN | `T#10S` | — | 偏差确认延时，域 0.5~300 s / Deviation delay |
| `fDriftThr` | `REAL` | IN | `0.2` | % | 判有位移的阈值，域 0.05~2.0 / Movement threshold |
| `tStallTime` | `TIME` | IN | `T#5S` | — | 停滞判据时长，域 0.5~120 s / Stall duration |
| `tIoFaultTime` | `TIME` | IN | `T#3S` | — | 反馈失效持续判据，域 0.2~60 s / Feedback loss duration |
| `fSlowRatio` | `REAL` | IN | `1.5` | — | 判 Slow 的行程倍率，域 1.1~3.0 / Slow ratio |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |
| `eDiag` | `E_DL_DamperDiag` | OUT | — | — | `eOk(0)` / `eSlow(10)` / `eDeviation(20)` / `eFullStall(30)` / `eTransitStall(40)` / `eIoFault(50)`（保持语义）/ Verdict, held |
| `fDeviation` | `REAL` | OUT | — | % | 指令 − 反馈有符号偏差（正 = 开不足），夹 −100~100 / Signed deviation |
| `tLastTravel` | `TIME` | OUT | — | ms | 末次行程实测时间 / Last travel time |
| `nStallCount` / `nTravelCount` | `UDINT` | OUT | — | 次 | 卡滞/行程次数累计，锁存 / Counters |
| `bAtOpen` / `bAtClose` | `BOOL` | OUT | — | — | 开/关到位指示（容差或限位或判）/ At-end indicators |

**状态机**（`E_DL_DamperState`）：`eIdle(0)`（偏差在容差内）→ `eMoving(10)`（指令已变且偏差超容差，进出必断行程定时器）→ `eSettling(20)`（已进容差，等确认窗）→ `eVerdict(30)`（单拍出结论后回待机，结论保持）→ `eFault(99)`。

### 53.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0160` | 无反馈运行，尚未超失效时长 / Open-loop run, within IoFault window | 否 | 短时断线仍在确认窗内，等待定性 |
| `16#0003_0161` | 行程偏慢或指令超域被钳位（一码两义）/ Slow travel or clamped command | 否 | 查机械阻力或指令来源；信息级 |
| `16#0003_0321` | 完全卡死（Full Stall） / Full stall | **是** | 停机检修：执行器/机械卡死 |
| `16#0003_0322` | 行程卡滞（Transit Stall） / Transit stall | **是** | 停机检修：执行器失去定位能力 |
| `16#0003_0323` | 稳态偏差（Deviation）——**维护语义，不置 bError** / Steady deviation | **否（裁定）** | 风阀仍能调节只是精度不够；排维护计划 |
| `16#0003_0324` | I/O 反馈失效 / Feedback lost | **是** | 查反馈回路；确认窗 `tIoFaultTime` 满才判 |
| `16#0003_0325` | 参数非法或非法状态兜底 / Illegal config or state | **是** | 检查参数域；复现后上报 |

### 53.3 调用示例 / Example

```iecst
PROGRAM PRG_DamperDiag
VAR
    fbDamper   : FB_DL_AhuDamperStuckDiag;   // 风阀诊断 / Damper diagnosis
    fDmpCmd    : REAL;                       // 风阀指令 [%] / Command
    fDmpFb     : REAL;                       // 风阀反馈 [%] / Feedback
    bDmpFbOk   : BOOL;                       // 反馈有效 / Feedback valid
    bAhuEn     : BOOL;                       // 使能 / Enable
    bAhuReset  : BOOL;                       // 复位 / Reset
    eDmpDiag   : E_DL_DamperDiag;            // 结论 / Verdict
    bDmpStop   : BOOL;                       // 建议停机 / Recommend stop
END_VAR

fbDamper(
    bEnable      := bAhuEn,
    bReset       := bAhuReset,
    fCmd         := fDmpCmd,
    fPosFb       := fDmpFb,
    bFbValid     := bDmpFbOk,
    tTravelNominal := T#30S,
    fSlowRatio   := 1.5);

eDmpDiag := fbDamper.eDiag;
// 只有三类真失效才停机；Deviation / Slow 排计划不停机
bDmpStop := (eDmpDiag = E_DL_DamperDiag.eFullStall)
         OR (eDmpDiag = E_DL_DamperDiag.eTransitStall)
         OR (eDmpDiag = E_DL_DamperDiag.eIoFault);
END_PROGRAM
```

### 53.4 要点 / Notes

- **v1.0.1 修复（确认窗缺口）**：判定相原先用 `IF NOT _bFbOk` 直接锁存 0324，绕开 `tIoFaultTime` 确认窗——「瞬时断线」被升级成不可继续运行的失效。修复后必须 `fbIoWatch.Q`（满确认窗）才判 IoFault；未满时本拍不发布结论、保持上次值。三分类确认窗完整闭合：Full Stall = `tStallTime` ｜ Transit Stall = 倍率 + 宽限 ｜ IoFault = `tIoFaultTime`。
- **V2 行程不累加**：连续两次 20 s 行程不会累加成 40 s——进移动态断行程定时器一拍，且自清放在两个共用实例调用之后（R40 双实例共用断输入拍的正解样板）。
- **Transit Stall 宽限后再定性**：超时判据点 + `tStallTime` 宽限后才判死——不在超时当拍直接判卡滞（指令还在动先判 Slow，停了才判卡滞）。
- **反馈恢复首拍只重装基准**（R41）：不判任何卡滞，避免恢复瞬间的旧偏差被算进新行程。
- **0323/0161 均不置 bError**：本件是「故障带码 + 不置 bError」组合的首例（0323），MANUAL 故障码表自本件起增列「是否置 bError」列。

---

## 54. FB_DL_PumpCavitationGuard ｜ 泵汽蚀三判据守卫（R13，v1.0.1）

**定位**：离心泵汽蚀的在线守卫——流量偏低 + 扬程跌落 +（振动超限 **或** 电流波动超限）三判据同拍成立并持续 `tConfirm` 才确认汽蚀；单判据只到嫌疑（0164，**不锁存**）。确认后只输出 `fDerateRatio` / `bDerateRequest`，**不写变频器频率**——降速执行归上层，每次确认降一步（默认 −0.10）、下限 0.3，不自动回升（回升交上层斜坡，复位也只回升一步的折中已留档）。抑制窗（`tHoldOff`）内判据被忽略（0165）但降速请求保持。

### 54.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` / `bReset` | `BOOL` | IN | — | — | 使能 / 复位锁存（上升沿） / Enable and reset |
| `bRunning` | `BOOL` | IN | — | — | 泵运行中，停泵时全部判据抑制（含急停级）/ Pump running |
| `fFlow` | `REAL` | IN | — | m³/h | 实测流量，0~100000 / Measured flow |
| `fHead` | `REAL` | IN | — | m | 实测扬程，0~1000 / Measured head |
| `fVibration` | `REAL` | IN | — | mm/s | 振动速度有效值，0~50 / Vibration RMS |
| `fCurrent` | `REAL` | IN | — | A | 电机电流，0~10000 / Motor current |
| `fFlowNominal` / `fHeadNominal` | `REAL` | IN | — | m³/h / m | 额定流量/扬程，**必须为正**；非正判 0328 且比值输出 0（不出伪比值）/ Nominals, must be positive |
| `fFlowLowRatio` | `REAL` | IN | `0.60` | — | 流量低于额定的比例，域 0.2~0.95 / Low-flow ratio |
| `fHeadDropRatio` | `REAL` | IN | `0.15` | — | 扬程跌落比例，域 0.05~0.5 / Head-drop ratio |
| `fVibLimit` | `REAL` | IN | `4.5` | mm/s | 振动上限（ISO 10816 C 区边界），域 1~20；超 2 倍判急停级 0327 / Vibration limit |
| `fCurrentRippleLimit` | `REAL` | IN | `0.15` | — | 电流波动率上限，域 0.02~0.5 / Ripple limit |
| `tRippleWindow` | `TIME` | IN | `T#2S` | — | 电流波动统计窗，域 0.5~30 s / Ripple window |
| `tConfirm` | `TIME` | IN | `T#3S` | — | 三判据同拍持续判据，域 0.5~30 s / Confirmation time |
| `tHoldOff` | `TIME` | IN | `T#30S` | — | 降速后抑制判据时长，域 5 s~10 min / Hold-off |
| `fDerateStep` | `REAL` | IN | `0.10` | — | 每次降速步长，域 0.02~0.3 / Derate step |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康出口四件 / Health outputs |
| `bCavitation` | `BOOL` | OUT | — | — | 汽蚀确认（三判据同拍成立，锁存）/ Cavitation confirmed |
| `bDerateRequest` | `BOOL` | OUT | — | — | 降速请求（保持语义，窗满撤回）/ Derate request, held |
| `fDerateRatio` | `REAL` | OUT | — | — | 降速比例 0.3~1.0，1.0 = 不降 / Derate ratio |
| `fFlowRatio` / `fHeadRatio` | `REAL` | OUT | — | — | 实测/额定比值，钳 0~2；额定非法时输出 0 / Ratios |
| `fVibRatio` | `REAL` | OUT | — | — | 振动/上限比值，钳 0~5 / Vibration ratio |
| `nEventCount` | `UDINT` | OUT | — | 次 | 汽蚀事件累计，锁存 / Event counter |
| `fRippleMeas` | `REAL` | OUT | — | — | 窗内电流波动率实测值，钳 0~10 / Measured ripple |

**状态机**（`E_DL_CavitationState`）：`eIdle(0)`（未使能或停泵）→ `eMonitor(10)` → `eSuspect(20)`（单判据）→ `eConfirm(30)` → `eDerate(40)`（窗满回监视）；`eFault(99)`（参数非法或振动急停级，锁存）。

### 54.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 置 bError | 处理建议 / Action |
|---|---|---|---|
| `16#0003_0164` | 单判据嫌疑（不锁存）/ Single criterion, suspect | 否 | 关注趋势；不触发降速 |
| `16#0003_0165` | 抑制窗内判据被忽略（整个降速相生效）/ Ignored during hold-off | 否 | 正常抑制行为；窗满后判据恢复 |
| `16#0003_0326` | 汽蚀确认（三判据同拍持续成立）/ Cavitation confirmed | **是** | 已发降速请求；查吸入侧（滤网/液位/ NPSH） |
| `16#0003_0327` | 振动超上限两倍（急停级）/ Emergency vibration | **是** | 立即停机检查；停泵时本判据同样被抑制（防邻机振动误锁存） |
| `16#0003_0328` | 额定值非正或阈值倒置 / Illegal nominals | **是** | 修正台账；比值输出 0 不出伪比值 |
| `16#0003_0329` | 非法状态兜底 / Illegal state | **是** | 断电重启并上报 |

### 54.3 调用示例 / Example

```iecst
PROGRAM PRG_PumpGuard
VAR
    fbCav      : FB_DL_PumpCavitationGuard;   // 汽蚀守卫 / Cavitation guard
    bPumpRun   : BOOL;                        // 泵运行 / Pump running
    fPumpQ     : REAL;                        // 流量 [m3/h] / Flow
    fPumpH     : REAL;                        // 扬程 [m] / Head
    fPumpVib   : REAL;                        // 振动 [mm/s] / Vibration
    fPumpI     : REAL;                        // 电流 [A] / Current
    bPumpEn    : BOOL;                        // 使能 / Enable
    bPumpRst   : BOOL;                        // 复位 / Reset
    fSpdLimit  : REAL;                        // 送变频器的频率上限 [%] / Speed ceiling
END_VAR

fbCav(
    bEnable      := bPumpEn,
    bReset       := bPumpRst,
    bRunning     := bPumpRun,
    fFlow        := fPumpQ,
    fHead        := fPumpH,
    fVibration   := fPumpVib,
    fCurrent     := fPumpI,
    fFlowNominal := 120.0,     // 台账注入 / from the datasheet
    fHeadNominal := 45.0);

// 上层按降速比例折算频率上限：本件不写变频器 / apply the ratio upstream
fSpdLimit := 100.0 * fbCav.fDerateRatio;
END_PROGRAM
```

### 54.4 要点 / Notes

- **v1.0.1 修复五条**（本泳道修复最多件，其中三条属「文本全绿、语义出错」家族，机检无法捕获只能逐拍推演）：① 抑制窗语义——`_bHoldActive` 改为「整个降速相 OR 窗满拍」，原实现 0165 仅在窗满那一拍可见、窗内判据并未真被抑制；② 兜底值只能当除数守卫不能当判据门——比值门改用原始额定值，额定非正时输出 0 而非 `流量/1.0` 的伪比值（V5 违例）；③ `bError = TRUE` 而 `uErrorId = 0` 的自相矛盾态——0326 确认时补写首出码寄存器；④ 急停级 0327 加 `bRunning AND bEnable` 门——停泵时邻近设备振动不再误锁存；⑤ 停泵分支补清 `_fRipple`——旧波动率不再跨停机存活到重启首窗。
- **确认定时器一拍滞后是有意取舍**：判据在定时器之后一拍才算，头注释「拍间依赖」段已登记（3 s 量级判据滞后一拍无实质影响，换取「所有实例同段无条件调用」的强纪律）。
- **规格向量与默认阈值不自洽（已移交勘误）**：默认 `fHeadDropRatio = 0.15` 下扬程 0.8 倍额定也成立扬程判据——V1「只成立流量判据」需把 `fHeadDropRatio` 调严，判据语义本身不改。
- **降速闭环**：`eDerate` 窗满撤请求回监视；判据仍成立则再次进嫌疑并再降一步——闭环收敛、无双写冲突。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `I_DL_Gripper` | 夹爪契约：7 只读属性 + 4 方法 | `bOpened` / `eHealth` / `uErrorId` |
| `FB_DL_ParallelGripper` | 驱动 → 到位确认 → 夹持力保持三段动作 | `bCmdClose` / `bCloseFeedback` / `fForceSetpoint` |
| `FB_DL_SsrHeaterDrive` | 0~100 % 功率需求转周期 PWM 通断指令 | `fPowerDemand` / `bSsrOut` |

> 用法要点：`ParallelGripper` 的 5 个契约量（`bOpened`/`bClosed`/`bWorkpiecePresent`/`fWidth`/`bError`）只以属性对外，**不设同名输出引脚**（R66，同名成员会阻断三平台编译）；`Close(fForceSetpoint)` 的形参优先于同名引脚给定（R73）。`bValveOut` 必须由上层映射到物理点。


---

---

## R19 批次补录接口表（2026-11-16，本子库 4 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录：R19 编 4 件入库时手册仅建骨架、未收录接口表。**引脚级细节以 `.st` 源码声明区为准**，下表逐字取自源码。

### `FB_DL_DeviceHealthArbiter`
- **功能**：16 路 NE107 健康源聚合仲裁，枚举成员编号即仲裁优先级（全库唯一属主 `E_DL_Ne107Status` 只引用不重声明）；输出聚合健康态、首出源下标与通道号、分级掩码。`bIncludeMaintenance` 决定 `eMaintenanceReq` 是否参与升级。
- **输入引脚**：`bEnable`、`bReset`、`aeHealth[0..15]`、`auChannelId[0..15]`、`uSrcCount`、`bIncludeMaintenance`
- **输出引脚**：`eAggHealth`、`uFirstIdx`、`uFirstChannel`、`auLevelMask[0..5]`、`uFaultSrcCount`、`bDegraded`、`eErr`、`bError`
- **码位**：信息 `16#0003_016A` / `016B` ｜ 故障 `16#0003_0330`~`0332`

### `FB_DL_ProfinetAlarmDiag`
- **功能**：PROFINET 诊断条目五元组（通道号 / 通道属性 / 错误类型 / 扩展错误类型 / 附加值）→ 通道故障掩码 + 首出通道 + 分类计数 + NE107 健康态；区分系统级与通道级、维护类与故障类。
- **输入引脚**：`auChannelNo` / `auChannelProp` / `auErrType` / `auExtErrType` / `audAddValue`（各 `[0..15]`）、`uEntryCount`
- **输出引脚**：`uChannelMask`、`uFirstChannel`、`uFirstErrType`、`auClassCount[0..7]`、`bMaintenanceOnly`、`bSystemLevel`、`eHealth`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0003_016C` / `016D` ｜ 故障 `16#0003_0333`~`0335`

### `FB_DL_EscChuckCurrentMonitor`
- **功能**：静电吸盘（ESC）吸附电流监视四态（idle / build / steady / release / fault）：建立段等电流落窗、稳态段持续确认、释放段等电流归零；打火判据与泄漏趋势双出口，NE107 健康映射。
- **输入引脚**：`bEnable`、`bReset`、`bChuckOn`、`fChuckCurrent`、`fChuckVoltage`、`fCurMin`、`fCurMax`、`fSparkRise`、`tBuildTime`、`tConfirmTime`、`tSampleTime`
- **输出引脚**：`bAttached`、`bSpark`、`bLeakTrend`、`bDegraded`、`eHealth`、`uAttachCount`、`eErr`、`bError`
- **码位**：信息 `16#0003_016E` / `016F` ｜ 故障 `16#0003_0336`~`0338`

### `FB_DL_DeviceParamWrite`
- **功能**：设备参数写回**事务**（R77 三要素齐备）：白名单 `abWritable` → 快照备份 → 逐项写入 → `afActual` 读回复核（容差 `fVerifyTol`）→ 失败回滚。六态机（idle/backup/write/verify/rollback/done/fault），逐项握手经 `uActiveIdx` + `bWriteNow`。
- **输入引脚**：`bEnable`、`bExecute`、`bAbort`、`bReset`、`auIndex` / `afWriteValue` / `abWritable` / `afActual`（各 `[0..15]`）、`uCount`、`fVerifyTol`、`tWriteTimeout`、`tVerifyTimeout`
- **输出引脚**：`bBusy`、`bDone`、`bRollback`、`uWritten`、`uSkipped`、`uFailedIdx`、`afReadback[0..15]`、`uActiveIdx`、`bWriteNow`、`eErr`、`bError`
- **码位**：信息 `16#0003_0170` / `0171` ｜ 故障 `16#0003_0339`~`033B`

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Device` 余下 R1~R18 历史件（约 53 件，含 16 只 `I_DL_*` 契约）接口表**下轮续补**（每轮 ≤10 件，按 R18→R17 倒序推进）。
---

## R22 批次接口表（R22 追加 · 4 件）

### FB_DL_SlitValveInterlock ｜ 真空闸阀互斥互锁（DL_Device / ValveInterlock）
- **输入引脚**：`bRequest`、`bAtmDoorClosed`、`bAtmDoorOpen`、`fChamberVac`（Pa）、`fVacThreshold`（Pa 缺省 100.0）、`bArmRetracted`、`tFbTimeout`（缺省 T#3S）、`bEnable`
- **输出引脚**：`bValveOpenCmd`、`bValveCloseCmd`（两路互斥先清后置）、`bInterlockOk`、`uBlockMask`（1 真空不足 / 2 门未关 / 4 臂未退 / 8 反馈超时）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0172`（放行开阀）/ `0173`（无位置确认保持指令）｜ 故障 `033C`（联锁拒绝）/ `033D`（门位矛盾按门未关）/ `033E`（真空非法按不足）
- **要点**：保守侧纪律——反馈矛盾按门未关、真空非法按不足；引脚契约无阀体位置反馈，tFbTimeout 语义为「指令已发无位置确认」的等待窗（收窄声明见头注释）。

### FB_DL_PressureReliefMonitor ｜ 安全阀起跳/回座监视（DL_Device / SafetyMonitor）
- **输入引脚**：`fUpPressure`（bar g）、`fDnPressure`（bar g）、`fSetPressure`（缺省 10.0）、`fBlowdown`（倍 缺省 0.90，须在 0~1 之间）、`tConfirm`、`tMinLift`（缺省 T#500MS）、`uMaintLimit`（次 缺省 50）、`bEnable`
- **输出引脚**：`bLifted`、`nLiftCount`（次）、`tOpenTotal`（ms）、`fPeakPressure`（bar g）、`eHealth`（`E_DL_Ne107Status` 引用唯一属主）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0174`（起跳已记录）/ `0175`（短起跳滤除）｜ 故障 `033F`（整定/回座比非法）/ `0340`（非有限保持台账）/ `0341`（兜底）

### FB_DL_SteamTrapMonitor ｜ 疏水阀堵塞/泄漏诊断（DL_Device / Diagnostic）
- **输入引脚**：`fTin`（°C）、`fTout`（°C）、`fDeltaNormal`（K 缺省 10.0）、`fDeltaLeak`（K 缺省 5.0）、`fTinMin`（°C 缺省 80.0）、`tConfirm`、`bEnable`
- **输出引脚**：`fDelta`（K）、`bNormal`、`bSteamLeak`、`bBlocked`、`eHealth`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0176`（正常带）/ `0177`（工况未建立冻结判定）｜ 故障 `0342`（温度非有限）/ `0343`（判据阈值自相矛盾）/ `0344`（兜底）
- **要点**：冷态（fTin < fTinMin）冻结全部故障判定——防停机全域「泄漏」误报；健康映射：泄漏→eOutOfSpec、堵塞→eMaintenanceReq。

### FB_DL_LevelRadarValidate ｜ 雷达液位回波可信度仲裁（DL_Device / SignalQuality）
- **输入引脚**：`fLevel`（m）、`fQuality`（%）、`fSnr`（dB）、`fSpan`（m 缺省 10.0）、`fQualityMin`（% 缺省 40.0）、`fSnrMin`（dB 缺省 10.0）、`fRateLimit`（m/s 缺省 0.5）、`tSample`、`tConfirm`、`bEnable`
- **输出引脚**：`fLevelOut`（m，可信则实时值否则末次可信值）、`bTrusted`、`uSuspectMask`（1 置信度 / 2 信噪比 / 4 超量程 / 8 跳变）、`eHealth`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0003_0178`（质量低于门限保持末次可信值）/ `0179`（变化率跳变单拍剔除）｜ 故障 `0345`（量程/门限非法）/ `0346`（非有限不更新发布值）/ `0347`（兜底）

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Device` 余下 R1~R21 历史件（约 53 件，含 16 只 `I_DL_*` 契约）接口表继续按「每轮 ≤10 件、最近两轮优先倒序」补录（R88 纪律）。


*Last updated: 2026-11-16（R22 追加接口表 4 件）｜ 道莅工控代码库产品总监*

---

## R23 批次接口表（R23 追加 · 6 件 · 健康联锁族（T2-8 NE107 多源聚合 + ROADMAP P1 设备保护） ｜ 子库 v0.12.0→v0.13.0）

### FB_DL_HealthAggregator ｜ 多源 NE107 健康聚合仲裁（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `aHealth` | IN | `ARRAY[1..16] OF E_DL_Ne107Status` | 各源健康态 [—]，下标 1..16，超编路填 eUnknown |
| `uSourceCount` | IN | `UINT` | 实际源数 [路]，有效域 0..16，> 16 钳位照仲裁 |
| `bArbitrate` | IN | `BOOL` | 仲裁使能 [—]，FALSE = 本拍不仲裁输出 eUnknown |
| `eOverall` | OUT | `E_DL_Ne107Status` | 聚合结果 [—]，编号最小者优先即最差者胜 |
| `uWorstIdx` | OUT | `UINT` | 最差源下标 [路]，0 = 无（未仲裁或源数为 0） |
| `uFailCount` | OUT | `UINT` | eFailure 源计数 [路] |
| `uMaintCount` | OUT | `UINT` | eMaintenanceReq 源计数 [路] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_OvenDoorInterlock ｜ 烘箱炉门-氮气-温区三联锁（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bDoorClosedFb` | IN | `BOOL` | 门已关到位反馈 [—] |
| `bN2PurgeOk` | IN | `BOOL` | 氮气置换完成 [—] |
| `fZoneTempC` | IN | `LREAL` | 温区实测温度 [摄氏度] |
| `fOpenTempMaxC` | IN | `LREAL := 45.0` | 允许开门温度上限 [摄氏度]，须 > 0 |
| `bDoorOpenCmd` | IN | `BOOL` | 开门请求 [—]，电平有效 |
| `bReset` | IN | `BOOL` | 故障复位 [—]，上升沿退出 eFault |
| `bDoorUnlock` | OUT | `BOOL` | 开锁放行 [—] |
| `eInterlockState` | OUT | `E_DL_OvenDoorState` | 联锁相位 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_ChamberGateValve ｜ 真空腔闸阀互锁互斥控制（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bOpenCmd` | IN | `BOOL` | 开阀命令 [—]，电平有效 |
| `bCloseCmd` | IN | `BOOL` | 关阀命令 [—]，电平有效 |
| `bOpenedFb` | IN | `BOOL` | 开到位反馈 [—] |
| `bClosedFb` | IN | `BOOL` | 关到位反馈 [—] |
| `bPumpingActive` | IN | `BOOL` | 抽气进行中 [—]，抽气中禁开（联锁源） |
| `tFbTimeout` | IN | `TIME := T#5S` | 移动态反馈超时 [ms] |
| `bReset` | IN | `BOOL` | 故障复位 [—]，上升沿退出 eFault |
| `bOpenOut` | OUT | `BOOL` | 开阀输出 [—] |
| `bCloseOut` | OUT | `BOOL` | 关阀输出 [—] |
| `eValveState` | OUT | `E_DL_GateValveState` | 阀相位 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_RobotGripVerify ｜ 机械手夹持确认与掉片判据（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bVacOk` | IN | `BOOL` | 真空反馈 [—] |
| `bClampOk` | IN | `BOOL` | 夹爪反馈 [—] |
| `eGripMode` | IN | `E_DL_GripMode` | 夹持模式 [—] |
| `bGripCmd` | IN | `BOOL` | 夹持命令 [—]，电平有效 |
| `bReleaseCmd` | IN | `BOOL` | 释放命令 [—]，电平有效 |
| `tConfirmTime` | IN | `TIME := T#200MS` | 确认窗 [ms]，兼作掉片 |
| `bReset` | IN | `BOOL` | 故障复位 [—]，上升沿清掉片锁存 |
| `bGripVerified` | OUT | `BOOL` | 夹持已确认 [—] |
| `bDropSuspect` | OUT | `BOOL` | 掉片疑似 [—]，已确认后反馈丢失 |
| `uDropCount` | OUT | `UDINT` | 掉片累计 [次]，饱和 4294967295 不回绕 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_FilterDpMonitor ｜ 过滤器压差寿命监视（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fDpKpa` | IN | `LREAL` | 压差实测 [千帕] |
| `fDpChangeKpa` | IN | `LREAL := 0.8` | 更换预警阈值 [千帕] |
| `fDpAlarmKpa` | IN | `LREAL := 1.5` | 堵塞报警阈值 [千帕]，须 > 预警阈值 |
| `tTrendWindow` | IN | `TIME  := T#1H` | 趋势窗时长 [ms] |
| `bReset` | IN | `BOOL` | 手动复位 [—]，清除 eOutOfSpec 锁存 |
| `eHealth` | OUT | `E_DL_Ne107Status` | 健康态 [—]，引用属主枚举（只引用不重声明，R70） |
| `fDpTrendKpaH` | OUT | `LREAL` | 趋势斜率 [千帕 |
| `bReplaceHint` | OUT | `BOOL` | 更换预警 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_TankN2BlanketCtrl ｜ 储罐氮封压力双分程（DL_Device ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fTankPressKpa` | IN | `LREAL` | 罐压实测 [千帕]，表压 |
| `fPressLoKpa` | IN | `LREAL := 0.5` | 低压分界 [千帕]，低于此补氮 |
| `fPressHiKpa` | IN | `LREAL := 2.0` | 高压分界 [千帕]，须 > 低压分界，达此泄放 |
| `fN2ValveOutFb` | IN | `BOOL` | 补氮阀开反馈 [—] |
| `bEnable` | IN | `BOOL` | 控制使能 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—] |
| `fN2ChargePct` | OUT | `LREAL` | 补氮阀位 [百分数]，0~100，仅低压段有效 |
| `bVentCmd` | OUT | `BOOL` | 泄放阀指令 [—]，开关量，仅高压段 |
| `eBlanketState` | OUT | `E_DL_N2BlanketState` | 氮封相位 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### 续补说明 / Remaining（R23 更新）

> 本节为 R23 新增件接口表（引脚取自 .st 声明区实测抽取，脚本 pins_r23.json 留档）；R23 终审修复件以修订历史为准（v1.0.1 引脚契约零变更）；历史件补录按 R88 节奏（每轮 ≤10 件）继续。

## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 4 件 + 修复件 2 件）

### FB_DL_StepperMicroFeedPulseEquiv（功能块 FB，）｜ v1.0.0

- **功能**：步进电机细分脉冲当量链换算——整步数 x 细分数 x 减速比 / 丝距
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bExecute` | BOOL | 触发计算 [—]，上升沿生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清故障态 |
| INPUT | `fStepsPerRev` | LREAL := 200.0 | 整步数 [步每转]，典型 200（1.8 度步距角） |
| INPUT | `fMicroStep` | LREAL := 16.0 | 细分数 [倍]，有效域 1..256 整数，非 2 的幂给信息级提示 |
| INPUT | `fGearRatioIn` | LREAL := 1.0 | 减速比（电机转/丝杠转）[倍]，须 > 0 |
| INPUT | `fLeadMm` | LREAL := 5.0 | 丝杠导程 [毫米每转]，须 > 0 |
| INPUT | `fBacklashMm` | LREAL := 0.0 | 反向间隙 [毫米]，>= 0，为 0 给信息级提示 |
| OUTPUT | `fPulsePerMm` | LREAL | 脉冲当量 [脉冲每毫米] |
| OUTPUT | `fMmPerPulse` | LREAL | 反向当量 [毫米每脉冲] |
| OUTPUT | `fBacklashPulse` | LREAL | 间隙补偿脉冲数 [脉冲] |
| OUTPUT | `eState` | E_DL_StepperEquivState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0003_0186 起信息级、16#0003_035A 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_PumpDryRunGuard（功能块 FB，）｜ v1.0.1　**注**：v1.0.0→v1.0.1（R24 终审修复：默认参数自违反 R100 配比）

- **功能**：泵干转保护三段式——判据（功率 < 干转阈 AND 流量 < 干转阈，
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 保护使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清跳闸锁存 |
| INPUT | `bPumpRunFb` | BOOL | 泵运行反馈 [—] |
| INPUT | `fMotorPowerKw` | LREAL | 电机功率实测 [千瓦] |
| INPUT | `fFlowM3h` | LREAL | 流量实测 [立方米每小时] |
| INPUT | `fPowerThreshKw` | LREAL := 1.0 | 干转功率阈 [千瓦]，低于此判功率命中，须 > 0 |
| INPUT | `fFlowThreshM3h` | LREAL := 0.5 | 干转流量阈 [立方米每小时]，低于此判流量命中，须 > 0 |
| INPUT | `tTripDebounce` | TIME  := T#8S | 双判据去抖窗 [ms]，须 > 0 且 > 学习窗（v1.0.1 默认 3S→8S：原默认 5S 学习窗 > 3S 去抖窗，自违反 R100 配比约束出厂即 035E 故障） |
| INPUT | `tLearnWin` | TIME  := T#5S | 启动学习窗 [ms]，起步瞬态豁免，须 > 0 且 < 去抖窗 |
| INPUT | `tRestartInh` | TIME  := T#60S | 重启抑制窗 [ms]，防频繁启停，须 > 0 且为最长窗 |
| OUTPUT | `bTripCmd` | BOOL | 跳闸指令 [—]（停泵请求，锁存态保持） |
| OUTPUT | `bRestartBlock` | BOOL | 重启抑制中 [—] |
| OUTPUT | `eState` | E_DL_PumpGuardState | 保护相位 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0003_0188 起信息级、16#0003_035D 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_CoilFrostWindow（功能块 FB，）｜ v1.0.0

- **功能**：结霜双判据窗——盘管表面温度同时满足「冻结判据」（表面温度
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 监视使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `fAirTempC` | LREAL | 空气干球温度 [摄氏度] |
| INPUT | `fRhPct` | LREAL | 空气相对湿度 [百分数]，域外钳 1..100 照算 |
| INPUT | `fCoilSurfTempC` | LREAL | 盘管表面温度 [摄氏度] |
| INPUT | `fFrostThreshC` | LREAL := 0.0 | 结霜阈值 [摄氏度]，表面低于此判冻结 |
| INPUT | `fDpMarginK` | LREAL := 1.0 | 露点裕度 [开]，表面低于露点减此值判凝露 |
| INPUT | `fThawHystK` | LREAL := 2.0 | 除霜退出回差 [开]，须 > 0 且 < 裕度 + 10 |
| INPUT | `tFrostDwell` | TIME  := T#60S | 双判据驻留窗 [ms]，须 > 0 |
| OUTPUT | `fDewPointC` | LREAL | 解算露点 [摄氏度]（诊断出口） |
| OUTPUT | `bFrostWindow` | BOOL | 结霜窗判定中 [—]（霜窗态电平） |
| OUTPUT | `bDefrostReq` | BOOL | 除霜请求 [—]（锁存保持） |
| OUTPUT | `eState` | E_DL_CoilFrostState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0003_018A 起信息级、16#0003_0360 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_ElectrolyteMoistureGuard（功能块 FB，）｜ v1.0.0

- **功能**：电解液注液间环境联锁——露点 > 露点上限 或 相对湿度 > 湿度
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 联锁使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清首因/组态锁存 |
| INPUT | `bDosingReq` | BOOL | 注液请求 [—]（联锁仅门控，不接管请求） |
| INPUT | `fRoomTempC` | LREAL | 注液间干球温度 [摄氏度] |
| INPUT | `fRhPct` | LREAL | 注液间相对湿度 [百分数]，域外钳 1..100 照算 |
| INPUT | `fDpLimitC` | LREAL := -40.0 | 露点联锁上限 [摄氏度]，高于此越限 |
| INPUT | `fRhLimitPct` | LREAL := 10.0 | 湿度联锁上限 [百分数]，高于此越限，按工艺卡组态 |
| INPUT | `fWarnBandK` | LREAL := 2.0 | 接近限值预警带宽 [开]，须 >= 0 |
| INPUT | `tDebounce` | TIME  := T#5S | 越限去抖窗 [ms]，须 > 0 |
| OUTPUT | `bDosingPermit` | BOOL | 注液放行 [—]（联锁门控输出） |
| OUTPUT | `fDewPointC` | LREAL | 解算露点 [摄氏度]（诊断出口） |
| OUTPUT | `bFirstCauseDp` | BOOL | 首因锁存：露点通道 [—]（bReset 才清除） |
| OUTPUT | `bFirstCauseRh` | BOOL | 首因锁存：湿度通道 [—]（bReset 才清除） |
| OUTPUT | `eGuardState` | E_DL_MoistGuardState | 联锁相位 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0003_018C 起信息级、16#0003_0363 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_MfcSetpointRamp（功能块 FB，）｜ v1.0.0

- **功能**：质量流量控制器（MFC）设定值斜坡——目标值先钳量程域
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bExecute` | BOOL | 触发斜坡 [—]，上升沿生效 |
| INPUT | `bHold` | BOOL | 冻结保持 [—]，电平生效 |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清故障态 |
| INPUT | `fSpTargetSccm` | LREAL | 目标设定值 [标准毫升每分钟]，域外钳量程照算 |
| INPUT | `fRangeSccm` | LREAL := 100.0 | MFC 量程 [标准毫升每分钟]，须 > 0 |
| INPUT | `fSlewRateSccmS` | LREAL := 10.0 | 斜率 [标准毫升每分钟每秒]，须 > 0 |
| INPUT | `fCycleTimeS` | LREAL := 0.01 | 任务扫描周期 [秒]，须 > 0（R95 代理阈值） |
| OUTPUT | `fSpRampedSccm` | LREAL | 斜坡后设定值 [标准毫升每分钟] |
| OUTPUT | `fSpPctOut` | LREAL | 占量程百分比 [百分数]，0..100 |
| OUTPUT | `bRampDone` | BOOL | 斜坡完成 [—]（到达态电平） |
| OUTPUT | `eState` | E_DL_MfcRampState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0003_018E 起信息级、16#0003_0366 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_TankN2BlanketCtrl（功能块 FB，）｜ v1.0.1　**注**：v1.0.0→v1.0.1（R23 P0 挂账关闭：泄放/补氮退出迟滞回差）

- **功能**：储罐氮封双分程——罐压低于低压分界按比例开补氮阀位（0~100%
- **码位带**：16#0003_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `fTankPressKpa` | LREAL | 罐压实测 [千帕]，表压 |
| INPUT | `fPressLoKpa` | LREAL := 0.5 | 低压分界 [千帕]，低于此补氮 |
| INPUT | `fPressHiKpa` | LREAL := 2.0 | 高压分界 [千帕]，须 > 低压分界，达此泄放 |
| INPUT | `fVentHystKpa` | LREAL := 0.2 | 泄放/补氮退出迟滞回差 [千帕]，有效域 (0, 分界跨度)，v1.0.1 新增 |
| INPUT | `fN2ValveOutFb` | BOOL | 补氮阀开反馈 [—] |
| INPUT | `bEnable` | BOOL | 控制使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—] |
| OUTPUT | `fN2ChargePct` | LREAL | 补氮阀位 [百分数]，0~100，仅低压段有效 |
| OUTPUT | `bVentCmd` | BOOL | 泄放阀指令 [—]，开关量，仅高压段 |
| OUTPUT | `eBlanketState` | E_DL_N2BlanketState | 氮封相位 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错 |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |


## R27 新增接口表（5 件 · 2026-11-17）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_FanArrayStageCtrl` | FB | IN `aNRunHrs`/`uStageReq`/`uFanTotal`/`tMinRun`/`tMinStop`；OUT `auFanCmd`/`uStageAct`/`eErr` | N+1 风机分级启停，级数上限=装机−1 预留备机，每拍至多切一台，运行小时极值选台 |
| `FB_DL_FrostProtectFreeze` | FB | IN `fFrostTemp_C`/`fOutdoor_C`/`bHysteresisC`/`bFrostAlarm`/`bManualReset`；OUT `bDamperCloseCmd`/`bCoilOpenCmd`/`bFanStopCmd`/`eState`/`eErr` | 五态防冻，双阈委托 Hysteresis，跳闸三输出同拍，退出需温度恢复 + 人工复位 |
| `FB_DL_MfcFlowCtrl` | FB | IN `fSetpointSlm`/`fReadbackSlm`/`fScaleMaxSlm`/`fTolPct`/`fOvershootPct`/`tStable`/`bNewSp`；OUT `bInTol`/`bOvershoot`/`tSettleMs`/`eError`/`eState` | 五态跟踪窗；峰值仅首次入窗后累积（v1.0.1），设定 0 走关断不校验 |
| `FB_DL_DateCoderSync` | FB | IN `bEncoderPulse`/`uDivRatio`/`nOffsetCounts`/`bProductDetect`/`tPulseWidth`/`tProdMax`；OUT `bPrintTrig`/`uPulseCount`/`uSkipCount`/`nPhaseDiag`/`eErr` | 编码器分频喷码，触发用 >= 比较规避负余数，产品丢失超时显式跳过 |
| `FB_DL_SealIntegrityMonitor` | FB | IN 三参数 `fSealTemp_C`/`fSealPress_N`/`tSealTime` + 六窗 `fTempWin_L/H` 等 + `uViolTrip`/`bSealDone`/`bReset`；OUT `bInSpec`/`bAlarmLatch`/`nViolCnt`/`eError` | 只判不封；封口完成沿采样，NaN 判超差，主码取首个违参（温度>压力>时间） |

## R30 新增接口表（Device 5 件 · 2026-11-18）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_AhuFilterDpBank` | FB | IN `afDp_Pa`/`afDpEarly_Pa`/`afDpChange_Pa`〔ARRAY[1..4] OF REAL，Pa〕/`fHyst_Pa`/`fDpMax_Pa`/`fFanPct`/`fFanMinPct`/`tDebounce`；OUT `aeStage`〔E_DL_FilterStage×4〕/`auMaxStage`/`bChangeReq`/`bFrozen`/`eErr` | 4 段过滤器压差四级分档；`aTonDeb: ARRAY[1..4] OF TON` 每拍无条件刷新（R40 返修范式），去抖域 T#100MS~T#120S，码位 03D9~03DD |
| `FB_DL_FoupDoorSeq` | FB | IN `bDoorClosed`/`bDoorOpen`/`bCarrierPresent`/`bUnlockCmd`/`bLockCmd`/`bVacuumOk`/`tUnlockHold`/`tRelockWin`/`bReset`；OUT `bUnlockOut`/`bLockOut`/`eState`〔E_DL_FoupDoorState〕/`bTransferPermit`/`eErr` | 六态门联锁顺控；安全侧输出全 0；故障锁存解除式 = 复位沿 + 门磁关到位 + 无矛盾反馈，码位 03DE~03E2 |
| `FB_DL_CoolantFlowAudit` | FB | IN `afFlow_Lpm`/`afMinFlow_Lpm`〔ARRAY[1..8]，L/min〕/`tConfirm`/`fHyst_Lpm`；OUT `uwUnderMask`/`uFirstOut`/`bAllOk`/`eErr` | 8 支路欠流审计；非有限/负流量判传感器故障独立于欠流；首出三律（未锁存才仲裁、最小支路号、复位在仲裁后），码位 03E3~03E7 |
| `FB_DL_ValvePdiSched` | FB | IN `auSlots`/`tPollCycle`/`astSlotCfg`〔ARRAY[1..4] OF ST_DL_PdiSlotCfg〕/`abSlotEn`/`aubSlotStat`/`auiSlotErrIn`；OUT `uActiveSlot`/`auErrSlot`/`bAllSlotsOk`/`eErr` | 阀岛 PDI 分槽轮询编排（单拍单发、越界钳位、异常照记账）；传输能力经实例注入消费，本件不实现传输，码位 03E8~03EC |
| `FB_DL_RackDiagSummary` | FB | IN `auBoardStat`〔ARRAY[1..8] OF WORD，诊断位引脚注入〕/`bReset`；OUT `uwFaultMask`/`uFirstBoard`/`uFirstCode`/`bStorm`/`eErr` | 机架诊断聚合与首出定位；回绕差分按归零处理；风暴只置 `bStorm` 不进错误锁存，码位 03ED~03F1 |

## R62 追加（Device +2 件 · 子库 v1.24→v1.25）

### FB_DL_VfdDcBusRipple ｜ 变频器直流母线健康监视（v1.0.0）

- **出口**：`fUdAvg`（窗均值 V）/ `fRipplePct`（峰峰纹波率 %）/ `bUnder` / `bOver` / `bRippleHigh`（各带迟滞）/ `nFill`。
- **用法**：`fUdNom` 填变频器额定母线电压（如 540 V DC），`nWinLen` 按载波周期 8~32 拍取；`bValid` 需窗达半满才为 TRUE，启动首段读数不可信属正常。
- **监视价值**：纹波率趋势上升 ≈ 电解电容 ESR 增大；欠压 ≈ 整流缺相/进线跌落；过压 ≈ 制动能量回灌（与 `FB_DL_BrakeResistorThermal` 联看）。
- **本版缺陷（R63 修复中）**：`fUdNom ≤ 0` 时只报组态码但不早退，除法仍执行 → 除零风险。**投运前务必确认 `fUdNom > 0` 且非 NaN**。

### FB_DL_IonFanInterlock ｜ 离子风机三判据联锁（v1.0.0）

- **判据**：`bFanRun` ∧ 风速 ≥ 下限（带迟滞）∧ |平衡电压| ≤ 上限（带迟滞），三者同时成立并持续 `tConfirm` 才置 `bPermit`。
- **非对称安全口径**：许可发放可延迟、**撤除零延时**（判据失效当拍撤许可）。下游动力回路请把 `bPermit` 串进使能链，勿用 `bAlarmXxx` 代替。
- **NE107 分级**：`bAlarmFan` = Failure 级（反馈丧失，立即停线）；`bAlarmSpeed` / `bAlarmBalance` = OutOfSpec 级（工艺调整，不必停线）。
- **本版缺陷（R63 修复中）**：`bEnable = FALSE` 时三报警位与 `bError` 未清零（与头注释边界八相反），失能 + 风机停会报假 Failure。HMI 侧请以 `bEnable` 屏蔽显示。

> 说明：本子库此前无「滤波族选型」「ESD 联锁族」专门对照段，R62 按「有结构才追加」原则只补简版；完整族对照表（含 `FB_DL_VacIonizerBalance` / `FB_DL_EsdGroundMonitor` / `FB_DL_AirShowerInterlockSeq` 四件边界）列 R63。
