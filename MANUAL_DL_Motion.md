# MANUAL — DL_Motion 运动控制 OOP 封装子库使用手册

> **Sublibrary**：`DL_Motion` ｜ **Version**：v1.14.0（子库版本以 `VERSION.md` 为准）｜ **Level**：1 ｜ **Components**：25（接口 1 ｜ 功能块 22 ｜ 函数 2，R20 按注册表实测校正；本手册接口表已覆盖至 R19 批次，R1~R18 历史件**下轮续补**）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert
> **Depends**：`Standard.library`（`TON` / `R_TRIG` / `MIN` / `MAX` / `ABS`）；主体为 Level 0、不引用其他 `DL_` 子库；**例外**：R11 起 `FB_DL_WindingTensionCtrl` 经 `VAR_IN_OUT` 注入 `DL_Algo/FB_DL_PidController` 与 `FC_DL_CoilDiameterCalc`（Motion 依赖 Algo 属允许方向），不调用任何厂商轴控功能块
> **故障码段 / Error Code Family**：`16#0004_xxxx`（信息级 `01xx` ｜ 故障级 `02xx` 起段；`uErrorId = 0` 无故障，信息级不置 `bError`）
> 配套版本记录见 `DL_Motion/VERSION.md`；全库导航见 `C:\Library\README.md`。**引脚级细节以 `.st` 源码声明区为准**，本手册接口表逐字取自源码。

---

## 0. 使用前必读 / Before You Start

1. **同一状态机适配真实与仿真**：`FB_DL_SingleAxis` 的 `bUseVirtualKinematics=TRUE` 时位置由内部梯形段积分器生成（无硬件仿真），`FALSE` 时位置直接取上层每拍注入的 `fActPosition`（真实驱动）——逻辑联调用仿真模式，现场切换真实模式不改上层代码。
2. **方法全部非阻塞单发化**：`I_DL_MotionAxis` 的 6 个方法仅置内部请求标志，跨周期动作由 FB 主体状态机执行；指令被拒时返回 FALSE 且轴状态不发生任何改变，不排队。
3. **MC_Stop 语义**：`eStopping` / `eErrorStop` 态拒绝一切运动指令；停止完成后仍拒绝新任务直至新运动指令被显式受理。
4. **`bError` 为派生式**：仅反映 `eErrorStop` 态；信息级事件码只进 `uErrorId`，HMI 报警分组应同时读两者。
5. **`bHomed` 维护链路**：回零时序由 `FB_DL_AxisHomingSeq`（第 5 节）承载；`bHomed` 属性仍由轴实现/上层联动——`FB_DL_AxisHomingSeq` 标定成功后暂存 `fHomePosition`，不直接写轴内部状态，接线按「回零完成 → 上层写坐标系 → `bHomed` 置位」执行。
6. **单位约定**：位置 [mm 或 deg]、速度 [mm/s 或 deg/s]、加速度 [mm/s²]——由组态注释约定，同一工程内保持一致。

---

## 1. 组件索引 / Component Index

| 组件 / Component | 类型 / Kind | 用途 / Purpose | 依赖 / Depends On |
|---|---|---|---|
| `I_DL_MotionAxis` | 接口 | 单轴运动控制标准契约（PLCopen 状态模型）/ Single-axis motion contract | 无 |
| `FB_DL_SingleAxis` | 功能块 | 单轴运动控制参考实现（含虚拟运动学仿真）/ Reference implementation | `I_DL_MotionAxis` |
| `FB_DL_AxisJogController` | 功能块 | 轴点动操作器（手动调试）/ Jog controller | `I_DL_MotionAxis` |
| `FB_DL_AxisHomingSeq` | 功能块 | 标准回零序列状态机（四模式，R6）/ Homing sequence | `I_DL_MotionAxis` |
| `FB_DL_AxisRelativeMove` | 功能块 | 相对定位 + 链式步进（R6）/ Relative move | `I_DL_MotionAxis` |
| `FB_DL_AxisVelocityMove` | 功能块 | 速度模式 + 动态改速（R6）/ Velocity move | `I_DL_MotionAxis` |
| `FB_DL_SoftLimitGuard` | 功能块 | 软限位电子围栏预判器（R7）/ Soft-limit guard | `I_DL_MotionAxis`（只读 fPosition/fVelocity） |

---

## 2. I_DL_MotionAxis ｜ 单轴运动控制标准接口

**功能**：单轴运动控制标准抽象契约，按接口三段式公约组织：状态枚举 + 只读属性 + 方法。上层工艺块（点动器、工站、HMI 适配层）仅依赖本接口引用，即可用同一套代码适配真实伺服驱动、虚拟运动学仿真轴与第三方轴封装。
**随文件枚举**：`E_DL_AxisState`（PLCopen 六态 + 禁用态：`eDisabled=0 / eStandstill=10 / eHoming=20 / eDiscreteMotion=30 / eContinuousMotion=40 / eStopping=50 / eErrorStop=60`，间隔 10 预留扩展位）。

### 2.1 属性 / Properties（全部只读 GET）

| 成员 / Member | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `eState` | `E_DL_AxisState` | GET | 当前轴状态 / Current axis state |
| `fPosition` | `REAL` | GET | 当前位置 [mm 或 deg，单位由实现组态注释约定] / Current position |
| `fVelocity` | `REAL` | GET | 当前速度 [mm/s 或 deg/s]，带符号，负值=负向 / Signed velocity |
| `bEnabled` | `BOOL` | GET | 使能状态，TRUE=伺服已上使能 / Servo enabled |
| `bHomed` | `BOOL` | GET | 回原完成，TRUE=坐标系已建立（当前版本恒 FALSE 占位）/ Homed status, placeholder |
| `bError` | `BOOL` | GET | 故障锁存，TRUE=处于 `eErrorStop` 态 / Error latched |
| `uErrorId` | `UDINT` | GET | 末次事件码，信息级码不置 `bError` / Last event code |

### 2.2 方法 / Methods（共 6 个，达 ≤6 红线临界）

| 方法 / Method | 返回 / Return | 说明 / Description |
|---|---|---|
| `Enable(bOn : BOOL) : BOOL` | 受理结果 / accepted | 使能请求，MC_Power 语义；故障态或驱动未就绪时上使能返回 FALSE，下使能恒受理（电平语义）/ Enable request |
| `Reset() : BOOL` | 受理结果 / accepted | 故障复位，MC_Reset 语义；仅 `eErrorStop` 态受理 / Reset, only in ErrorStop |
| `Stop()` | — | 受控停止，MC_Stop 语义：停车并拒绝新任务 / Controlled stop |
| `MoveAbsolute(fPos, fVel, fAcc : REAL) : BOOL` | 受理结果 / accepted | 绝对定位；仅 `eStandstill` 受理；参数非有限/非正值或目标位超软限位返回 FALSE 且轴状态不变 / Move absolute |
| `MoveRelative(fDist, fVel, fAcc : REAL) : BOOL` | 受理结果 / accepted | 相对定位；`fDist` 带符号，落点 = 当前位置 + fDist，落点越限拒绝 / Move relative |
| `MoveVelocity(fVel, fAcc : REAL) : BOOL` | 受理结果 / accepted | 速度模式；`eStandstill` / `eContinuousMotion` 两态受理；连续运动中调用为改速而非重启 / Move velocity |

> 回原（Homing）职责由后续轮次 `FB_DL_AxisHomingSeq` 承载，不入本接口（方法数红线）。

### 2.3 状态跃迁契约 / Transition Contract（实现块必须保证）

| 从 / From | 条件 / Condition | 到 / To |
|---|---|---|
| `eDisabled` | `Enable(TRUE)` 且驱动就绪（唯一入态） | `eStandstill` |
| `eStandstill` | 任一 Move 指令受理（唯一可收指令稳态） | `eDiscreteMotion` / `eContinuousMotion` |
| `eDiscreteMotion` / `eContinuousMotion` | `Stop()` 或到位/限位 | `eStopping` 受控减速 → `eStandstill`（禁止直接跳变） |
| `eStandstill` | `Enable(FALSE)` | `eDisabled` |
| 任意态 | `bDriveFault` / 非法状态 | `eErrorStop`（锁存，仅 `Reset` 且故障源消除后退回） |
| `eHoming` | 预留态：实现块不得自行产生运动输出 / Reserved | — |

### 2.4 调用示例 / Call Example

```iecst
VAR
    fbAxis : FB_DL_SingleAxis;           // 实现块实例 / Implementation instance
    bOk1, bOk2 : BOOL;
END_VAR

fbAxis();                                // 每周期调用驱动状态机 / Cyclic call
bOk1 := fbAxis.Enable(bOn := TRUE);      // 上使能（MC_Power 语义）/ Enable
bOk1 := fbAxis.MoveAbsolute(fPos := 120.0, fVel := 50.0, fAcc := 500.0);
IF fbAxis.bError THEN bOk2 := fbAxis.Reset(); END_IF

// 上层注入：fbJog.iAxis := fbAxis;（接口引用指向实现块实例 / Interface injection）
```

---

## 3. FB_DL_SingleAxis ｜ 单轴运动控制参考实现

**功能**：实现 `I_DL_MotionAxis` 的单轴运动控制功能块，内含 PLCopen 轴状态机语义（`eDisabled` + 六态）的 clean-room 实现。指令仲裁 Absolute > Relative > Velocity，落选者丢弃置信息级；软限位越限预判拦截；驱动故障 → `eErrorStop` 锁存仅 Reset 清；`bUseVirtualKinematics=TRUE` 时位置由内部梯形段积分器生成（仿真），`FALSE` 时直接取上层每拍注入值（真实驱动）。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 3.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `fSoftLimitPos` | `REAL` | IN | `1000000.0` | 软限位上限 [mm]，默认 +1E6 / Soft limit positive |
| `fSoftLimitNeg` | `REAL` | IN | `-1000000.0` | 软限位下限 [mm] / Soft limit negative |
| `fVelMax` | `REAL` | IN | `1000.0` | 速度物理上限 [mm/s] / Max velocity |
| `fAccMax` | `REAL` | IN | `10000.0` | 加速度物理上限 [mm/s²] / Max acceleration |
| `fDecMax` | `REAL` | IN | `10000.0` | 减速度物理上限 [mm/s²] / Max deceleration |
| `fPosTolerance` | `REAL` | IN | `0.01` | 到位容差 [mm] / Position tolerance |
| `tSampleTime` | `TIME` | IN | `T#100MS` | 虚拟积分采样周期，`<T#10MS` 钳位（公约 0.5）/ Sample time, clamped |
| `bDriveReady` | `BOOL` | IN | `FALSE` | 驱动就绪反馈，TRUE=可上使能 / Drive ready feedback |
| `bDriveFault` | `BOOL` | IN | `FALSE` | 驱动故障反馈，TRUE=故障 → `eErrorStop` 锁存 / Drive fault, latches ErrorStop |
| `fActPosition` | `REAL` | IN | `0.0` | 实际位置注入 [mm]，真实驱动由上层每拍写入 / Actual position injection |
| `bUseVirtualKinematics` | `BOOL` | IN | `TRUE` | 虚拟运动学开关，TRUE=无硬件仿真模式 / Virtual kinematics mode |
| `bTrack` | `BOOL` | IN | `FALSE` | 跟踪脉冲，电平生效重同步位置并受控停车（公约 0.1）/ Track pulse re-syncs position |
| `eState` / `fPosition` / `fVelocity` / `bEnabled` / `bHomed` / `bError` / `uErrorId` | 见 §2.1 | GET 属性 | — | 接口属性映射（接口契约映射，避免与同名输出变量重名冲突，R11 留档）/ Interface property mapping |

### 3.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0004_0201` | 故障级 / Fault | 非法状态兜底（CASE+ELSE → `eErrorStop`）/ Illegal state fallback | `Reset()` 后观察 |
| `16#0004_0202` | 故障级 / Fault | 软限位越界（目标超限拒绝为瞬态码；实际越限为锁存）/ Soft-limit violation | 核对 `fSoftLimitPos/Neg` 与目标位置 |
| `16#0004_0203` | 故障级 / Fault | 驱动故障反馈锁存 / Drive fault latched | 排除驱动侧故障后 `Reset()` |
| `16#0004_0101` | 信息级 / Info | 同拍多条 Move 指令仲裁丢弃（Absolute > Relative > Velocity）/ Command arbitration drop | 同拍只发一条 Move |
| `16#0004_0103` | 信息级 / Info | 参数对调兜底修复 / Parameter swap repair | 核对动态参数组态 |
| `16#0004_0104` | 信息级 / Info | 采样周期钳位（< 10ms 或 > 1s）/ Sample time clamped | 核对 `tSampleTime` |
| `16#0004_0105` | 信息级 / Info | 软限位预判降速停车 / Soft-limit predicted stop | 正常保护动作 |

### 3.3 调用示例 / Call Example

```iecst
VAR
    fbAxis : FB_DL_SingleAxis;           // 轴实例 / Axis instance
    bOk : BOOL;
END_VAR

// 组态期赋值 / Configuration-time assignment
fbAxis.fSoftLimitPos := 800.0;
fbAxis.fSoftLimitNeg := -50.0;

// 每周期无条件调用 / Unconditional cyclic call
// 仿真模式（无硬件联调）/ Simulation mode
fbAxis(bUseVirtualKinematics := TRUE, bDriveReady := TRUE);

// 真实驱动模式：上层每拍写实际位置 / Real mode: write position each cycle
// fbAxis.bUseVirtualKinematics := FALSE;  fbAxis.fActPosition := xDrvPos;
bOk := fbAxis.MoveAbsolute(fPos := 300.0, fVel := 200.0, fAcc := 2000.0);
IF fbAxis.uErrorId = 16#0004_0101 THEN
    ; // 同拍多条指令被仲裁丢弃，改单发 / Arbitration drop, issue one at a time
END_IF
```

---

## 4. FB_DL_AxisJogController ｜ 轴点动操作器

**功能**：单轴点动操作器，经 `I_DL_MotionAxis` 接口引用驱动轴体（依赖注入，不关心实现品牌）。点动语义：长按低速、按住高速选择且延时到自动升高速、松开即受控停止；升/降速均走轴接口速度域限幅斜坡，不做阶跃。软限位拦截独立于轴组态：进入制动距离警戒区强制降为低速，限位处拒绝继续。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 4.1 接口表 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `bJogPos` | `BOOL` | IN | `FALSE` | 正向点动，电平生效 / Jog forward, level effective |
| `bJogNeg` | `BOOL` | IN | `FALSE` | 负向点动，电平生效 / Jog backward, level effective |
| `fJogSlow` | `REAL` | IN | `5.0` | 低速点动速度 [mm/s] / Slow jog velocity |
| `fJogFast` | `REAL` | IN | `50.0` | 高速点动速度 [mm/s] / Fast jog velocity |
| `bFastSelect` | `BOOL` | IN | `FALSE` | 高速选择，TRUE 且按住 ≥ `tFastDelay` 自动切高速 / Fast select with delay |
| `tFastDelay` | `TIME` | IN | `T#1S` | 低→高速切换延时（置 `T#0MS` 即瞬切高速）/ Fast switch delay |
| `fSoftLimitPos` | `REAL` | IN | `1000000.0` | 点动软限位上限 [mm]，独立于轴组态以便现场收紧 / Jog soft limit high, independent of axis config |
| `fSoftLimitNeg` | `REAL` | IN | `-1000000.0` | 点动软限位下限 [mm] / Jog soft limit low |
| `fAcc` | `REAL` | IN | `1000.0` | 点动加减速度 [mm/s²]（升/降速同斜率，要「跟手」调大它）/ Jog acceleration |
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | 轴接口引用，由上层注入实现块实例 / Axis reference injected by caller |
| `uErrorId` | `UDINT` | OUT | `0` | 末次信息级事件码（规格外补充引脚，R11 留档；无故障锁存语义）/ Last info code |

### 4.2 故障码表 / Error Codes

| ErrorID | 级别 / Level | 含义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `16#0004_0102` | 信息级 / Info | 双向点动冲突（同按 → 停止，安全侧「不猜」）/ Both directions pressed | 检查按键接线 |
| `16#0004_0103` | 信息级 / Info | 参数对调或兜底修复（`fJogSlow`>`fJogFast` 对调、限位倒置对调）/ Parameter swap repair | 核对参数组态 |
| `16#0004_0105` | 信息级 / Info | 软限位预判停车（与 `FB_DL_SingleAxis` 同码同义，点动与连续运动共用）/ Soft-limit predicted stop | 正常保护动作 |
| `16#0004_0104` | 信息级 / Info | 采样周期钳位 / Sample time clamped | 核对轴实例 `tSampleTime` |

> 状态门禁：`iAxis` 不在 `eStandstill` / `eContinuousMotion`（含 `eStopping` / `eErrorStop`）时点动指令被拒绝，轴状态不变。

### 4.3 调用示例 / Call Example

```iecst
VAR
    fbJog : FB_DL_AxisJogController;     // 点动器实例 / Jog instance
END_VAR

fbJog.iAxis := fbAxis;                   // 接口依赖注入 / Interface injection

// 每周期调用：手轮/按键电平直接接引脚 / Cyclic call with button levels
fbJog(bJogPos := bBtnUp,                 // 正向按键 / Forward button
      bJogNeg := bBtnDown,               // 反向按键 / Backward button
      bFastSelect := bBtnFast,           // 高速键（按住延时升高速）/ Fast key
      fJogSlow := 5.0, fJogFast := 50.0, fAcc := 2000.0,
      fSoftLimitPos := 780.0,            // 现场临时收紧 / Field-tightened limits
      fSoftLimitNeg := -30.0);

// 松开即停（内部调 iAxis.Stop()），无需上层编排停止时序 / Release-to-stop built in
```

---

## 5. FB_DL_AxisHomingSeq ｜ 标准回零序列状态机（R6，v1.0.1）

**功能 / 中文**：标准工业回零序列状态机，经 `I_DL_MotionAxis` 接口驱动轴体（MoveVelocity/MoveRelative/Stop 组合出序列，绝不出自有速度输出）。四模式：限位开关回零 / 原点开关回零 / Z 相脉冲精定位 / 扭矩堵转回零；「快速逼近-回退-爬行再逼近-标定原点」时序；超时 + 行程双护栏；完成/中止/故障三终态收到新启动沿自动重启（终审修复后的「借道」路径，不吞沿）。
**Function**: Industrial homing sequence state machine driving the axis via `I_DL_MotionAxis`, four modes, approach-retreat-reapproach-calibrate timing, timeout+travel dual guards, terminal-state restart.

### 5.1 随文件枚举 / Enums

- `E_DL_HomingMode`（随本块发布，不用厂商模式数值）：`eLimitSwitch(1)` 限位开关回零 ｜ `eHomeSwitch(2)` 原点开关回零 ｜ `eZeroPulse(3)` Z 相脉冲精定位 ｜ `eTorqueBlock(4)` 扭矩堵转回零。
- `E_DL_HomingStep`（随本块发布）：`eIdle(0) / eApproach(10) / eRetreat(20) / eReapproach(30) / eCalibrate(40) / eStopping(50) / eDone(60) / eAborted(70) / eFault(99)`。

### 5.2 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | — | 轴接口引用，由上层注入实现块实例 / Axis reference |
| `eMode` | `E_DL_HomingMode` | IN | `eHomeSwitch` | — | 回零模式 / Homing mode |
| `bCmdStart` | `BOOL` | IN | `FALSE` | — | 回零启动，上升沿生效 / Homing start |
| `bCmdAbort` | `BOOL` | IN | `FALSE` | — | 回零中止，电平生效，触发受控停车 / Homing abort |
| `bDirNeg` | `BOOL` | IN | `FALSE` | — | 回零方向，TRUE=朝负方向逼近（规格外补充引脚，R11 留档）/ Homing direction |
| `fHomingVel` | `REAL` | IN | `50.0` | mm/s | 快速逼近速度，正值 / Approach velocity |
| `fCreepVel` | `REAL` | IN | `2.0` | mm/s | 爬行再逼近速度，正值 / Creep velocity |
| `fAcc` | `REAL` | IN | `1000.0` | mm/s² | 回零加减速，正值 / Homing acceleration |
| `fHomePosition` | `REAL` | IN | `0.0` | mm | 标定原点位置值，暂存引脚，标定后由上层写入轴坐标系 / Home position value |
| `fMaxTravel` | `REAL` | IN | `1.0E6` | mm | 行程护栏上限，\|当前位置−起点\| 超限即故障 / Max travel guard |
| `tHomingTimeout` | `TIME` | IN | `T#60S` | — | 回零总超时，0=禁用 / Homing timeout |
| `bLimPos` | `BOOL` | IN | `FALSE` | — | 正限位开关，TRUE=已压住 / Positive limit switch |
| `bLimNeg` | `BOOL` | IN | `FALSE` | — | 负限位开关，TRUE=已压住 / Negative limit switch |
| `bHomeSw` | `BOOL` | IN | `FALSE` | — | 原点开关，TRUE=已压住 / Home switch |
| `bZeroPulse` | `BOOL` | IN | `FALSE` | — | Z 相脉冲，捕获上升沿 / Encoder zero pulse |
| `bTorqueLimitReached` | `BOOL` | IN | `FALSE` | — | 堵转阈值到达，由驱动层注入（接口无扭矩域，R11 留档）/ Torque limit reached |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪重同步，TRUE 时中止序列回空闲（R19）/ Track resync |
| `bBusy` | `BOOL` | OUT | `FALSE` | — | 回零进行中 / Homing busy |
| `bDone` | `BOOL` | OUT | `FALSE` | — | 回零完成，完成态保持至下次启动 / Homing done |
| `eStep` | `E_DL_HomingStep` | OUT | `eIdle` | — | 当前序列步，HMI 显示用 / Current homing step |
| `uErrorId` | `UDINT` | OUT | `0` | — | 末次事件码，段位 `16#0004_xxxx` / Last error code |

### 5.3 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0106` | 信息级 | 启动门禁/参数门禁拒绝（三块同码同义共用） |
| `0004_0210` | 故障级 | 回零总超时 |
| `0004_0211` | 故障级 | 回零行程超限（启动点距离护栏） |
| `0004_0212` | 故障级 | 回零中止 / 轴故障中断（规格明示分配） |
| `0004_0213` | 故障级 | 序列指令被轴拒绝 / 非法状态兜底 |

### 5.4 调用示例 / Call Example

```iecst
fbHome.iAxis := fbAxis;
fbHome(eMode := E_DL_HomingMode.eHomeSwitch, bCmdStart := bHomeReq,
       fHomingVel := 50.0, fCreepVel := 2.0, fAcc := 800.0,
       fHomePosition := 0.0, tHomingTimeout := T#60S,
       bLimPos := xLimP, bLimNeg := xLimN, bHomeSw := xHomeSw);
IF fbHome.bDone THEN
    (* 上层把 fHomePosition 写入轴坐标系并联动 bHomed / caller writes coordinates *)
END_IF
```

---

## 6. FB_DL_AxisRelativeMove ｜ 单轴相对定位与链式步进（R6）

**功能 / 中文**：单轴相对定位（MC_MoveRelative 语义）与连续累加步进控制封装。仅轴静止态发起；链式模式下到位自动执行下一步，运行中递增 `nChainTarget` 即累加步进；中止与轴故障中断锁存。
**Function**: Relative positioning (MC_MoveRelative semantics) with chained stepping and abort/fault interruption.

### 6.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | — | 轴接口引用，由上层注入实现块实例 / Axis reference |
| `bCmdExecute` | `BOOL` | IN | `FALSE` | — | 执行指令，上升沿生效 / Execute command |
| `fDistance` | `REAL` | IN | `0.0` | mm | 相对位移，带符号，负值=负向 / Relative distance [mm] |
| `fVel` | `REAL` | IN | `100.0` | mm/s | 运行速度，正值 / Run velocity [mm/s] |
| `fAcc` | `REAL` | IN | `1000.0` | mm/s² | 加减速度，正值 / Acceleration |
| `bChainMode` | `BOOL` | IN | `FALSE` | — | 链式步进模式，TRUE=到位后自动连续执行下一步 / Chain mode |
| `nChainTarget` | `UDINT` | IN | `1` | — | 链式目标步数，0=按 1 步处理；运行中递增即累加步进 / Chain target steps |
| `bAbort` | `BOOL` | IN | `FALSE` | — | 中止，电平生效 → 轴受控停止 / Abort |
| `bBusy` | `BOOL` | OUT | `FALSE` | — | 定位进行中 / Move busy |
| `bDone` | `BOOL` | OUT | `FALSE` | — | 单步完成，每步置位保持至下一步启动 / Step done |
| `bChainDone` | `BOOL` | OUT | `FALSE` | — | 链式目标完成 / Chain target reached |
| `uStepsDone` | `UDINT` | OUT | `0` | — | 本次链累计完成步数，执行沿清零 / Steps done |
| `uErrorId` | `UDINT` | OUT | `0` | — | 末次事件码，段位 `16#0004_xxxx` / Last error code |

### 6.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0106` | 信息级 | 启动门禁/参数门禁拒绝（fVel/fAcc 非正值或非有限值） |
| `0004_0220` | 故障级 | 定位指令被轴拒绝（锁存） |
| `0004_0221` | 故障级 | 中止 / 轴故障中断（锁存） |
| `0004_0201` | 故障级 | 非法状态兜底（族码沿用） |

### 6.3 调用示例 / Call Example

```iecst
fbRel.iAxis := fbAxis;
fbRel(bCmdExecute := bStepReq, fDistance := 25.0, fVel := 120.0, fAcc := 1500.0,
      bChainMode := TRUE, nChainTarget := 10);   // 10 步累加步进 / chained 10 steps
```

---

## 7. FB_DL_AxisVelocityMove ｜ 单轴速度模式与动态改速（R6）

**功能 / 中文**：单轴速度模式（MC_MoveVelocity 语义）与动态变速控制封装。启动沿发起、指令电平下降沿受控停止；`bDynamicRetarget := TRUE` 时连续运动中速度变化自动改速（重新调用 MoveVelocity，改速而非重启）；速度上限钳位。
**Function**: Velocity mode (MC_MoveVelocity semantics) with dynamic retargeting, velocity clamping and controlled stop.

### 7.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `iAxis` | `I_DL_MotionAxis` | IN_OUT | — | — | 轴接口引用，由上层注入实现块实例 / Axis reference |
| `bCmdStart` | `BOOL` | IN | `FALSE` | — | 速度运行指令，电平生效：TRUE=运行 / FALSE=受控停止 / Velocity start command |
| `fVelocity` | `REAL` | IN | `0.0` | mm/s | 目标速度，带符号，负值=负向；运行中变更即为改速请求 / Target velocity [mm/s] |
| `fAcc` | `REAL` | IN | `1000.0` | mm/s² | 加减速度，正值 / Acceleration |
| `bDynamicRetarget` | `BOOL` | IN | `FALSE` | — | 动态改速使能，TRUE=连续运动中速度变化自动改速 / Dynamic retarget |
| `fVelMax` | `REAL` | IN | `1000.0` | mm/s | 速度上限，\|fVelocity\| 超限钳位并置信息级 / Velocity limit [mm/s] |
| `bBusy` | `BOOL` | OUT | `FALSE` | — | 速度模式激活 / Velocity mode active |
| `bActive` | `BOOL` | OUT | `FALSE` | — | 轴处于连续运动态，轮询派生 / Axis in continuous motion |
| `uErrorId` | `UDINT` | OUT | `0` | — | 末次事件码，段位 `16#0004_xxxx` / Last error code |

### 7.2 故障码 / Error Codes

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_0106` | 信息级 | 参数门禁拒绝（非有限值 / fAcc 非正值，三块同码同义） |
| `0004_0107` | 信息级 | 改速请求不被受理 / 速度钳位提示 |
| `0004_0230` | 故障级 | 指令被拒 / 轴故障中断（锁存） |
| `0004_0201` | 故障级 | 非法状态兜底（族码沿用） |

### 7.3 调用示例 / Call Example

```iecst
fbVel.iAxis := fbAxis;
fbVel(bCmdStart := bVelMode, fVelocity := fJogSpeed, fAcc := 1200.0,
      bDynamicRetarget := TRUE, fVelMax := 300.0);   // 运行中改 fJogSpeed 即改速 / retarget on the fly
```

---

## 8. FB_DL_SoftLimitGuard ｜ 软限位电子围栏预判器（R7，v1.0.1）

**功能**：软限位安全电子围栏预判器。根据当前速度与减速度实时计算双向制动距离（含扫描/IO/驱动时延项），提前拦截超程指令；超程后仅允许反向指令（向内恢复豁免）。位置/速度经既有 `I_DL_MotionAxis` 接口引用读取。定位声明（公约 0.13）：应用层预判与诊断镜像，输出为建议信号（拦截执行在调用方），不构成认证安全功能。

### 8.1 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 |
|---|---|---|---|---|---|
| `fPosLimitPos` | REAL | 输入 | — | mm | 正向行程边界，域 > fPosLimitNeg |
| `fPosLimitNeg` | REAL | 输入 | — | mm | 负向行程边界 |
| `fDecel` | REAL | 输入 | 500.0 | mm/s² | 拦截减速度，域 >0，按配置减速取保守值 |
| `tLatency` | TIME | 输入 | T#23MS | ms | 系统-驱动总时延（扫描 10 + IO 5 + 驱动 8 ms 口径） |
| `fMargin` | REAL | 输入 | 0.0 | mm | 安全裕量，0=关闭；建议 = 停止距离 × 25% |
| `bEnable` | BOOL | 输入 | — | — | 预判使能，FALSE=仅监视输出不拦截 |
| `bReset` | BOOL | 输入 | — | — | 上升沿复位故障，离开越界区并复位后方可恢复 |
| `bWarnPos` / `bWarnNeg` | BOOL | 输出 | — | — | 正/负向预警：进入「边界 − 停止距离」预判带即置位 |
| `bInterceptPos` / `bInterceptNeg` | BOOL | 输出 | — | — | 正/负向拦截：位置 + 停止距离 + 裕量越界即置位，调用方应禁止该向指令并减速 |
| `bInsideOk` | BOOL | 输出 | — | — | 双向行程内正常 |
| `fStopDistPos` / `fStopDistNeg` | REAL | 输出 | — | mm | 实时双向预判停止距离（HMI 用） |
| `bFault` / `uErrorId` | BOOL / UDINT | 输出 | — | — | 故障标志 / 故障码 `16#0004_xxxx` 段 |
| `iAxis` | I_DL_MotionAxis | IN_OUT | — | — | 轴接口引用，上层注入 |

### 8.2 故障码 / Error Codes

| ErrorID | 级别 | 含义 |
|---|---|---|
| `16#0004_0108` | 信息级 | 时延口径提示（默认值与实际不符建议实测，一次性） |
| `16#0004_0240` | 故障级 | 减速度非法（非有限值/趋零，锁存） |
| `16#0004_0241` | 故障级 | 行程边界非法（正向 ≤ 负向，锁存） |

### 8.3 预判公式与验收向量 / Formula & Vectors

- `fStopDist = fSpeed × tLatency_s + fSpeed² / (2 × fDecel)`；向量：fSpeed=100 mm/s、fDecel=500 mm/s²、tLatency=23MS → 停止距离 = 2.3 + 10.0 = **12.3 mm**。
- 两级带域：拦截带 ⊇ 预警带（拦截含 fMargin 裕量更早触发，保守安全侧；两带重合于 fMargin=0）。
- 复位联锁：位置回到界内且故障源消失才可解除；使能切断时预警照常输出、拦截输出强制 FALSE。

### 8.4 调用示例 / Example

```iecst
fbSLG(fPosLimitPos := 500.0, fPosLimitNeg := -10.0,
      fDecel := 500.0, tLatency := T#23MS, fMargin := 3.0,
      bEnable := bAutoMode, iAxis := iAxisX);
IF fbSLG.bInterceptPos THEN bForbidFwdCmd := TRUE; END_IF  // 拦截执行在调用方
```

---

## 9. 典型组态与联调要点 / Field Notes

1. **仿真先行**：无硬件阶段全程用 `bUseVirtualKinematics=TRUE` 联调上层逻辑；到货后只改这一个开关 + 每拍写 `fActPosition`，上层工艺代码零改动。
2. **点动「跟手性」调 `fAcc`，不动轴组态**：点动加减速由点动器自己的 `fAcc` 承担；把轴的 `fAccMax` 调大来解决点动迟钝是常见误操作，会连带影响自动运行。
3. **瞬切高速**：想让高速键按下立即升速的工位，把 `tFastDelay` 设为 `T#0MS`（TON 零延时当拍满足）。
4. **两道软限位取交集**：点动限位与轴限位是独立防线；试机时现场收紧点动限位，程序自动运行不受影响。
5. **安全件不经过点动块**：本块不做任何传感器/安全件防抖，急停与安全门请走工艺急停链（`bProcessAbort` 类信号）与驱动层安全链。
6. **指令仲裁**：同一拍只发一条 Move 指令；并发需求（如边走边改速度）用 `MoveVelocity` 改速语义，不要靠仲裁丢弃后的重试。

---

## 10. FB_DL_ElectronicGear ｜ 电子齿轮耦合（R8）

**功能 / Function**：从轴速度指令 = 主轴实际速度 × 传动比 + 比例式相位补偿（钳 ±fPhaseMax）。传动比以整数分子/分母全程保存，仅在输出处换算浮点比值——分数比 3:7 长期运行零漂移；啮合过渡按 fAcc 限斜率平滑建立，脱开按 fDec 受控降速到零后单发停止请求。PLCopen MC_GearIn/GearInPos 公开语义 clean-room。
/ Slave speed command = master actual velocity x ratio + proportional phase compensation. Ratio kept as an integer pair; engage ramps on fAcc, disengage decelerates to zero then issues one stop request.

**接口表 / Interface**（逐字取自声明区 / verbatim from the declaration area）：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 耦合总使能，FALSE=脱开并清零输出（电平） |
| `bExecute` | BOOL | IN | 建立耦合指令（上升沿受理） |
| `bDisengage` | BOOL | IN | 脱开指令（上升沿，优先于 bExecute） |
| `bTrack` | BOOL | IN | 参考位置重同步（上升沿重采样并清相位误差） |
| `nRatioNum` | DINT | IN | 传动比分子 [-]，域 1..1000000，≤0 判参数非法 |
| `nRatioDen` | DINT | IN | 传动比分母 [-]，域 1..1000000，=0 防除零故障 |
| `bContinuousUpdate` | BOOL | IN | 运行中改比值使能，FALSE 时啮合内改比值被拒（0004_0131） |
| `fAcc` / `fDec` | REAL | IN | 啮合过渡加速度 / 脱开减速度 [mm/s²]，默认 500 |
| `fVelLimit` | REAL | IN | 从轴速度绝对上限 [mm/s]，0=不限 |
| `fPhaseGain` / `fPhaseMax` | REAL | IN | 相位修正增益 [1/s]（0=关闭）/ 修正量上限 [mm/s] |
| `tCycle` | TIME | IN | 任务扫描周期 [ms]（加速度限斜率基准） |
| `bReset` | BOOL | IN | 复位故障（上升沿，仅 eFault 态有效） |
| `bInGear` / `bBusy` / `bActive` | BOOL | OUT | 已啮合 / 执行中 / 持有从轴控制权 |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存（派生式）/ 故障码 16#0004_xxxx |
| `fRatio` | REAL | OUT | 实际生效传动比 [-]（显示量） |
| `fSlaveSpeedCmd` | REAL | OUT | 下发从轴速度指令 [mm/s]，带符号 |
| `fPhaseError` | REAL | OUT | 相位累计误差 [mm] |
| `iMaster` / `iSlave` | I_DL_MotionAxis | IN_OUT | 主轴 / 从轴接口引用 |
| `E_DL_GearState` | 枚举 | DUT | eIdle/eSynchronizing/eInGear/eDisengaging/eFault（随文件发布） |

**故障码 / Codes**：信息级 0004_0130~0132；故障级 0004_0250~0252、0299。

**调用示例 / Example**：

```iecst
fbGear.iMaster := fbMasterAxis;                 // 主轴实例注入 / Inject master instance
fbGear.iSlave  := fbSlaveAxis;                  // 从轴实例注入 / Inject slave instance
fbGear(bEnable := TRUE, bExecute := bCoupleCmd, // 每拍无条件调用 / Call every scan
       nRatioNum := 1, nRatioDen := 2,
       fAcc := 800.0, fDec := 800.0,
       fVelLimit := 600.0, fPhaseGain := 1.5,
       tCycle := T#10MS);
IF fbGear.bInGear THEN bReady := TRUE; END_IF
```

**现场要点 / Field notes**：速度耦合而非位置同步——硬位置对齐（GearInPos）改用电子凸轮块；小数比值放大为整数对（0.28 → 28:100）；主轴静止时相位冻结属正常工况（0130）；从轴故障锁存 0252 须 bReset 后才能重新啮合。

---

## 11. FB_DL_ElectronicCam ｜ 电子凸轮耦合（R8）

**功能 / Function**：主轴相位归一化 → 16 点表分段线性插值 → 缩放与偏移四段链计算从轴目标位置；周期/非周期双模式、主轴固定偏移 + 运行相位微调（飞剪切点补偿）、啮合沿一次完成全表单调性校验。相位归一化用「截断取整 + 条件加减」，绝不对负数取模（跨平台歧义禁令）。CamIn/CamTableSelect 公开语义 clean-room。
/ Normalized master phase feeds a 16-point piecewise-linear table with scaling and offsets; periodic/one-shot modes, engage-time table monotonicity validation, negative-MOD-free phase normalization.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 总使能，FALSE=立即脱开并清指令 |
| `bExecute` | BOOL | IN | 建立凸轮耦合（上升沿，仅 eIdle/eComplete 受理） |
| `bDisengage` | BOOL | IN | 脱开（上升沿，优先于 bExecute） |
| `bTrack` | BOOL | IN | 相位基准重同步（上升沿退回 eIdle） |
| `bPeriodic` | BOOL | IN | 周期模式，TRUE=表尾回绕表头，FALSE=单程置完成 |
| `bDirNegative` | BOOL | IN | 期望主轴方向，FALSE=正向 |
| `fMasterOffset` / `fPhaseShift` | REAL | IN | 主轴相位固定偏移 [mm] / 运行相位微调 [mm]（飞剪切点补偿） |
| `fSlaveOffset` | REAL | IN | 从轴位置偏移 [mm]，叠加在表输出之上 |
| `fMasterScaling` / `fSlaveScaling` | REAL | IN | 主/从轴缩放 [-]，域 0.001..100，非法回 1.0 |
| `fVelLimit` / `fAcc` / `fDec` | REAL | IN | 从轴速度上限 [mm/s] / 加/减速度 [mm/s²] |
| `nCamPoints` | UINT | IN | 有效点数，域 2..实测表维度，<2 判参数非法 |
| `bReset` | BOOL | IN | 复位故障（上升沿，仅 eFault 态） |
| `bInSync` / `bBusy` / `bEndOfProfile` | BOOL | OUT | 同步中 / 执行中 / 非周期走完表尾（保持到下次啮合） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `fMasterPhase` | REAL | OUT | 归一化主轴相位 [-]，0.0..1.0（HMI 监视） |
| `fSlavePosCmd` / `fCamSlaveTarget` | REAL | OUT | 从轴目标位置指令 [mm] / 表插值原始输出 [mm]（调试） |
| `iMaster` / `iSlave` | I_DL_MotionAxis | IN_OUT | 主轴 / 从轴接口引用 |
| `afCamMaster` / `afCamSlave` | ARRAY[0..15] OF REAL | IN_OUT | 凸轮表主/从轴点 [mm]，主轴点须单调递增 |
| `fCamMasterPeriod` | REAL | IN_OUT | 周期长度 [mm]，仅周期模式，≤0 判参数非法 |
| `E_DL_CamState` | 枚举 | DUT | eIdle/eWaiting/eEngaging/eInSync/eDisengaging/eComplete/eFault |

**故障码 / Codes**：信息级 0004_0140~0142；故障级 0004_0260~0265、0298。

**调用示例 / Example**：

```iecst
fbCam.afCamMaster[0] := 0.0;   fbCam.afCamSlave[0] := 0.0;
fbCam.afCamMaster[1] := 180.0; fbCam.afCamSlave[1] := 90.0;
fbCam.afCamMaster[2] := 360.0; fbCam.afCamSlave[2] := 0.0;
fbCam.fCamMasterPeriod := 360.0;
fbCam(bEnable := TRUE, bExecute := bCamCmd, bPeriodic := TRUE,
      nCamPoints := 3, fVelLimit := 300.0, fAcc := 2000.0);
```

**现场要点 / Field notes**：运行中改表无效须重新啮合；相位微调是运行中微调量、配方切换用 fMasterOffset；非周期走完表尾停在 eComplete 等新啮合沿；等待/啮合态内不停轴——要停给 bDisengage 走受控降速。

---

## 12. FB_DL_GantrySyncAxis ｜ 龙门双驱主从同步（R8）

**功能 / Function**：主动/从动侧实时偏差监视（预警/故障双阈 + 延时确认 + 80% 回差清除）+ 比例纠偏（增益 × 偏差，钳纠偏上限；饱和持续 T#3S 判机械卡滞）+ 偏差超故障阈触发双轴停止。双轴经 `I_DL_MotionAxis` 注入。
/ Dual-drive deviation monitoring with warn/fault thresholds and hysteresis, proportional correction with saturation watchdog, and dual-axis stop on fault-level deviation.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 总使能，FALSE=停止并清指令 |
| `bReset` | BOOL | IN | 复位故障（上升沿；偏差未回预警阈内被拒，0004_0150） |
| `bTrack` | BOOL | IN | 偏差计时重同步（上升沿清计时与锁存） |
| `fDevTolWarn` / `fDevTolFault` | REAL | IN | 偏差预警阈 / 故障阈 [mm]（写反自动对调，0004_0151） |
| `tDevDelay` | TIME | IN | 偏差确认延时 [ms]，超阈须持续此时间才动作 |
| `bCorrectEnable` / `fCorrGain` | BOOL / REAL | IN | 纠偏使能（FALSE=只监视）/ 比例增益 [1/s]（0=关闭） |
| `fCorrSpeedMax` | REAL | IN | 纠偏速度修正上限 [mm/s]，非法回默认 20 |
| `fCoupleSpeed` / `fAcc` | REAL | IN | 耦合建立慢速 [mm/s] / 加减速度 [mm/s²] |
| `bInSync` | BOOL | OUT | 同步中（偏差未超预警阈） |
| `fDeviation` | REAL | OUT | 实时偏差 [mm]（主动 − 从动，带符号） |
| `bDevWarn` | BOOL | OUT | 偏差预警（延时确认后置位，回差内自动清，瞬态型） |
| `bFault` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `bStopBothCmd` | BOOL | OUT | 双轴停止请求（供上层安全链与 HMI 监视） |
| `fCorrSpeedCmd` | REAL | OUT | 纠偏速度修正量 [mm/s]，带符号 |
| `iMasterAxis` / `iSlaveAxis` | I_DL_MotionAxis | IN_OUT | 主动侧 / 从动侧轴接口引用 |
| `E_DL_GantryState` | 枚举 | DUT | eIdle/eCoupling/eRun/eCorrecting/eFault（随文件发布） |

**故障码 / Codes**：信息级 0004_0150~0152；故障级 0004_0270~0274、0297。

**调用示例 / Example**：

```iecst
fbGantry.iMasterAxis := fbGantryDrive;          // 主动侧（驱动侧）注入
fbGantry.iSlaveAxis  := fbGantryFollow;         // 从动侧（跟随侧）注入
fbGantry(bEnable := TRUE, bReset := bResetCmd,
         fDevTolWarn := 0.5, fDevTolFault := 2.0,
         tDevDelay := T#50MS, fCorrGain := 2.0,
         fCoupleSpeed := 10.0, fAcc := 500.0);
```

**现场要点 / Field notes**：预警/故障阈取同值时判据合并为一级动作（观察项留档 v1.1）；纠偏只叠加到从动侧指令，主动侧按原工艺运行；`bStopBothCmd` 置位后由调用方执行双轴停止——本块输出建议信号（公约 0.13 定位）。

---

## 13. FB_DL_TorqueLimitControl ｜ 力矩达限压装判定（R8）

**功能 / Function**：「运行到固定挡块」压装序列——接近 → 慢速压装 → 达限判定（三源 OR：驱动器力矩限制激活 / 实际力矩达阈值 / 到达挡块反馈）→ 达限保持 → 位移窗一次锁存判定 → 释放归位。设备异常进故障锁存，工件不合格只出判定与方向提示（压浅 0163 / 压深 0164），两者严格分离。
/ "Run-to-stop" press sequence with three-source torque-limit detection and a one-shot latched position-window verdict; equipment faults latch, part NG only reports.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 总使能，FALSE=中止流程并清输出 |
| `bStart` | BOOL | IN | 启动压装周期（上升沿，仅 eIdle/eDone 受理） |
| `bAbort` | BOOL | IN | 中止（电平最高优先，立即受控停止） |
| `bReset` / `bTrack` | BOOL | IN | 复位故障与判定（上升沿）/ 内部锁存重同步 |
| `fPressStartPos` / `fPressEndPos` | REAL | IN | 压装起点 [mm]（接近与释放目标）/ 终点 [mm]（须大于起点，否则锁存 0004_0280） |
| `fPosWindowLow` / `fPosWindowHigh` | REAL | IN | 到位位移窗下/上限 [mm]（写反自动对调，0004_0160） |
| `fTorqueLimit` | REAL | IN | 达限判定力矩 [% 额定]，域 1..150，>100 仅提示（0004_0161） |
| `fApproachVel` / `fPressVel` | REAL | IN | 接近速度 [mm/s] / 压装速度 [mm/s]（建议不超接近速度 1/10，反常提示 0004_0162） |
| `fAcc` | REAL | IN | 加/减速度 [mm/s²] |
| `tClampTime` / `tPressTimeout` / `tReleaseTimeout` | TIME | IN | 达限保持时间 / 压装超时 / 释放超时 |
| `fActTorque` | REAL | IN | 实际力矩 [% 额定]，驱动适配层注入（非有限值锁存 0004_0283） |
| `bTorqueLimitActive` / `bInClampFeedback` | BOOL | IN | 驱动器力矩限制激活反馈 / 到达固定挡块反馈（可选） |
| `bJudgeOk` / `bJudgeNg` | BOOL | OUT | 判定合格 / 不合格（eDone 内保持，互斥且 NG 优先） |
| `bInClamp` / `bBusy` / `bDone` | BOOL | OUT | 已达限压紧 / 执行中 / 周期结束单拍脉冲 |
| `fPosAtClamp` / `fTorqueAtClamp` | REAL | OUT | 达限瞬间位置 [mm] / 力矩 [% 额定]（锁存值） |
| `bError` / `uErrorId` / `nCycleCount` | BOOL / UDINT / UDINT | OUT | 故障锁存 / 故障码 / 完成周期计数 |
| `iAxis` | I_DL_MotionAxis | IN_OUT | 压装轴接口引用 |
| `E_DL_PressState` | 枚举 | DUT | 压装序列状态机（随文件发布） |

**故障码 / Codes**：信息级 0004_0160~0164；故障级 0004_0280~0284、0296。

**调用示例 / Example**：

```iecst
fbPress.iAxis := fbPressAxis;
fbPress(bEnable := TRUE, bStart := bPressCmd, bReset := bResetCmd,
        fPressStartPos := 0.0, fPressEndPos := 25.0,
        fPosWindowLow := 20.0, fPosWindowHigh := 21.0,
        fTorqueLimit := 85.0, fPressVel := 5.0);
IF fbPress.bDone AND fbPress.bJudgeNg THEN
    bSortToNgChute := TRUE;                     // 不合格分流（方向提示看 0163/0164）
END_IF
```

**现场要点 / Field notes**：力矩限幅本身由驱动器参数承担——本块是判定与流程编排层，软件力矩限制不是安全功能；三源达限按现场可用信号接入，未接线保持 FALSE（退化为阈值比较可能等不到达限）；释放目标固定取压装起点，需退更远由上层追加定位指令。

---

## 14. FB_DL_MarkPositionLatch ｜ 印刷套准色标锁存（R8）

**功能 / Function**：布防（上升沿进入布防态）→ 标记上升沿同拍单次读写轴接口锁存位置/速度 → 布防窗超时转缺失态（`bMarkMissed`）；最近 8 槽历史前移（索引 0=最新）+ 与上次锁存的位置增量。注册标记/探针锁存公开语义 clean-room。
/ Arm, latch position and velocity on the mark edge with a single same-scan interface access, then flag a missed mark on arm-window timeout; 8-slot history shift with delta.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=清布防与结果（不影响历史与累计计数） |
| `bArm` | BOOL | IN | 布防（上升沿；锁存/缺失态下再次上升沿即重新布防） |
| `bTrigger` | BOOL | IN | 标记输入（上升沿有效，电平持续不影响） |
| `tArmWindow` | TIME | IN | 布防有效窗 [ms]，超时未触发转缺失态；T#0S=不限 |
| `bClearHistory` | BOOL | IN | 清历史缓冲（上升沿，不影响累计计数） |
| `bReset` | BOOL | IN | 复位故障 / 退出缺失态（上升沿） |
| `nHistoryDepth` | UINT | IN | 历史深度，域 1..实测维度，越界钳位（0004_0170） |
| `bLatched` | BOOL | OUT | 已锁存（仅锁存态为 TRUE） |
| `fLatchedPos` / `fLatchedSpeed` | REAL | OUT | 锁存位置 [mm] / 锁存瞬间速度 [mm/s]（带符号） |
| `fDeltaPos` | REAL | OUT | 与上次锁存的位置增量 [mm]（无上次时为 0） |
| `bMarkMissed` | BOOL | OUT | 标记缺失（缺失态为 TRUE，重新布防后自动清） |
| `uMarkCount` | UDINT | OUT | 累计有效标记数 [次] |
| `afHistoryPos` | ARRAY[0..7] OF REAL | OUT | 最近 N 次锁存位置 [mm]，索引 0=最新 |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障锁存 / 故障码 |
| `iAxis` | I_DL_MotionAxis | IN_OUT | 被采样轴接口引用 |
| `E_DL_MarkState` | 枚举 | DUT | 色标锁存状态机（随文件发布） |

**故障码 / Codes**：信息级 0004_0170~0171；故障级 0004_0290、0295。

**调用示例 / Example**：

```iecst
fbMark.iAxis := fbWebAxis;                      // 被采样轴（走料轴）注入
fbMark(bEnable := TRUE, bArm := bArmCmd, bTrigger := bMarkSensor,
       tArmWindow := T#2S, nHistoryDepth := 4);
IF fbMark.bLatched THEN
    fCutPos := fbMark.fLatchedPos + fCompensation;  // 套准补偿后交剪切定位
END_IF
```

**现场要点 / Field notes**：锁存动作与轴接口读写同拍完成（公约 0.13 单次访问），高速走料不丢拍；`bMarkMissed` 是流程信号不是设备故障——色标传感器遮挡/反差不足时先查现场；清历史不影响 `uMarkCount` 累计口径。

---

## 15. FC_DL_CalcMoveTime ｜ 梯形/三角运动耗时计算（R8，纯函数）

**功能 / Function**：按距离/速度上限/加减速度计算梯形曲线三段耗时与峰值速度；距离不足时显式判三角退化（`bTriangular`，峰速 < 上限）；起始速度超上限走「减速到点」分支；稳定延时直接计入总耗时。DL_Motion 首个 FC 形态组件，无状态无实例。
/ Pure trapezoidal/triangular move-time calculator with explicit triangular degradation, over-speed start branch and settle-time inclusion; the first FC in DL_Motion.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | BOOL | RET | TRUE=计算有效；参数非法（近零/非有限值）返回 FALSE |
| `fDistance` | REAL | IN | 移动距离 [mm]，可负（取绝对值） |
| `fVelMax` / `fAcc` / `fDec` | REAL | IN | 速度上限 [mm/s] / 加速度 / 减速度 [mm/s²] |
| `fVelStart` | REAL | IN | 起始速度 [mm/s]（仅用绝对值，接续定位时非零） |
| `tSettle` | TIME | IN | 到位稳定延时 [ms]，直接计入总耗时 |
| `tMove` | TIME | OUT | 总移动耗时 [ms]（含稳定延时） |
| `tAccPhase` / `tCruisePhase` / `tDecPhase` | TIME | OUT | 加速 / 匀速（三角时 T#0S）/ 减速段耗时 [ms] |
| `fVelPeak` | REAL | OUT | 实际峰值速度 [mm/s] |
| `bTriangular` | BOOL | OUT | 三角退化标志（TRUE=距离不足无法达到速度上限） |
| `uErrorId` | UDINT | OUT | 参数提示码 16#0004_0180~0184（仅信息级语义） |

**验收向量勘误 / Vector erratum**：规格第 1.6 节验收向量 V1/V2 数值与公式契约自相矛盾，总监验算裁定公式正确、向量错误——**V1（d=100、vmax=30、a=dec=20）匀速段修正为 ≈1833 ms；V2（d=20）峰速修正为 20 mm/s（三角退化）**；勘误随代码一并留档。

**调用示例 / Example**：

```iecst
IF FC_DL_CalcMoveTime(fDistance := 100.0, fVelMax := 30.0,
                      fAcc := 20.0, fDec := 20.0, tSettle := T#100MS,
                      tMove => tMove, fVelPeak => fPeak,
                      bTriangular => bTri) THEN
    // tMove 含稳定延时；bTri=FALSE 且 fPeak=30（V1 口径）
END_IF
```

**现场要点 / Field notes**：节拍预估与 HMI「预计剩余时间」显示专用——结果为几何闭式解，不含驱动器 S 段平滑与响应滞后，紧节拍验证请叠加 5~10% 裕量；结果超 T#24H 钳位（0004_0184）防 HMI 溢出。

---

## 16. FB_DL_SuperimposedMove ｜ 运动叠加补偿（R9，MC_MoveSuperimposed 语义）

**定位 / Positioning**：叠加运动补偿层——基础轴按既有轨迹运行的同时叠加动态偏移（视觉纠偏 / 张力微调 / 飞剪对位）：偏移指令经幅值限幅与斜坡限速后与基础位置代数叠加输出合成位置，由上层用合成位置下发轴指令。只做叠加律、限幅与收敛判据，不触碰轴本体指令、不做闭环、不做软限位（归 `FB_DL_SoftLimitGuard`）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE = 斜坡**冻结**偏移保持（不归零不跳变，重新使能无阶跃） / FALSE freezes the ramp and holds the offset |
| `fBasePos` | LREAL | IN | 基础轴实际位置 [mm]，每拍由上层注入 / Base axis position [mm] |
| `fOffsetCmd` | LREAL | IN | 叠加偏移指令 [mm]，正负双向 / Offset command [mm] |
| `fMaxOffset` | LREAL | IN | 偏移幅值限幅 [mm]，域 > 0，默认 5.0 / Offset magnitude limit |
| `fMaxOffsetSpeed` | LREAL | IN | 偏移斜坡限速 [mm/s]，0 = 不限速直通，默认 10.0 / Ramp speed limit |
| `fTaskCycle` | LREAL | IN | 任务周期 [s]，斜坡积分步长基准，必须与真实任务一致，默认 0.01 / Task cycle [s] |
| `bZeroNow` | BOOL | IN | 强制归零请求（目标置 0 仍走斜坡） / Force offset to zero via ramp |
| `fSuperPos` | LREAL | OUT | 合成位置 [mm] = 基础位置 + 偏移实际值 / Superimposed position [mm] |
| `fOffsetAct` | LREAL | OUT | 偏移实际值 [mm] / Actual offset [mm] |
| `bActive` | BOOL | OUT | 叠加生效中 / Overlay active |
| `bInSync` | BOOL | OUT | 偏移已收敛（零偏移需 T#100MS 零驻留窗口满 + 残差硬置 0.0 防假偏移显示） / Offset in sync with dwell window |
| `bError` | BOOL | OUT | 故障保持型（显式排除信息级码） / Fault latched |
| `uErrorId` | UDINT | OUT | 故障码：0004_01A0 周期兜底 / 01A1 幅值限幅 / 01A2 非有限值拒绝 / 01A3 不限速提示（信息级）；0004_02B0 幅值非法 / 02B1 周期非法 / 02B2 非法状态兜底（故障级锁存） / Error code |

### 调用示例 / Example

```iecst
VAR
    fbOverlay : FB_DL_SuperimposedMove;     // 叠加补偿实例 / Overlay instance
END_VAR

fbOverlay(bEnable := bVisionOk,
          fBasePos := fbAxis.fPosition,     // 基础轴实际位置注入 / Base position injected
          fOffsetCmd := fVisionOffset,      // 视觉纠偏量 / Vision correction
          fMaxOffset := 5.0,
          fMaxOffsetSpeed := 10.0,
          fTaskCycle := 0.01);              // 与任务周期一致 / Match the real task cycle
// 用合成位置下发轴指令 / Feed the composed position back to the axis:
// fbAxis.MoveAbsolute(fPos := fbOverlay.fSuperPos);
```

**故障码 / Codes**：见 uErrorId 行（0004_01Ax 信息级 / 0004_02Bx 故障级）。

**现场要点 / Field notes**：本块每拍必须调用（斜坡逐拍积分，跳拍丢步长）；bEnable = FALSE 是「冻结」不是「归零」，需要归零置 bZeroNow 或把指令写 0 等 bInSync；偏移实际值是纯指令推算量不含机械跟随误差；幅值上限必须小于安全行程半径（越界风险由调用方软限位预判承担）；验收向量 V1~V6 终审零修改 PASS（O-07 极窄重建窗口留档 v1.1）。

---

## 17. FB_DL_WindingTraverse ｜ 收卷卷径递推 + 排线轴往复（R10，v1.0.1 · D-02 致命修复件）

**定位 / Positioning**：收卷（或放卷）工位的**卷径实时递推 + 排线轴往复执行**二合一功能块。卷径由「圈数增量 × 材料厚度」递推（也可切换到外部注入值），排线位置按「圈数增量 × 每圈节距」积分并在端点停留换向。用于锂电卷绕、薄膜分切复卷、线缆收线、纸机卷取。

**与既有件边界 / Boundary**：`FC_DL_CoilDiameterCalc`（DL_Algo）做的是**瞬时几何反算**（线速度 / 转速 → 卷径，无状态纯函数）；本块做的是**层厚积分递推 + 排线执行**（有状态、含换向时序）。两者零代码调用、互为校验——可把纯函数结果注入 `fDiaInjected` 做偏差比对。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能 [−] / Enable |
| `bStart` | BOOL | IN | — | 启动卷绕，上升沿 [−] / Start winding on a rising edge |
| `bStop` | BOOL | IN | — | 停止，**电平有效，优先于一切运行态** [−] / Stop, level active, outranks every running state |
| `bReset` | BOOL | IN | — | 复位故障与卷径递推，上升沿 [−] / Reset the fault and the diameter recursion |
| `bUseInjectedDia` | BOOL | IN | FALSE | TRUE 采用注入卷径，FALSE 采用内部递推 [−] / TRUE selects the injected diameter |
| `fDiaInjected` | LREAL | IN | 0.0 | 注入卷径，域 0.01~3.0 [米] / Injected diameter |
| `fCoreDia` | LREAL | IN | 0.100 | 卷芯直径，域 0.01~1.0 [米] / Core diameter |
| `fThickness` | LREAL | IN | 0.0001 | 材料厚度，域 1 µm~10 mm [米] / Material thickness |
| `fLineSpeed` | LREAL | IN | 0.0 | 材料线速度，域 0~3000 [米每分] / Line speed |
| `fTaskCycle` | LREAL | IN | 0.01 | 任务周期，域 1 ms~1 s [s] / Task cycle time |
| `fWebWidth` | LREAL | IN | 0.5 | 卷材宽度，域 0.01~5.0 [米] / Web width |
| `fTraverseWidth` | LREAL | IN | 0.5 | 排线行程，域 0.01~5.0 [米] / Traverse stroke |
| `nPitchPerRev` | LREAL | IN | 1.0 | 每圈排线节距，域 0.1~50 [毫米每圈] / Pitch per revolution |
| `fTraverseSpeedMax` | LREAL | IN | 0.5 | 排线轴最大速度，域 0.01~5.0 [米每秒] / Traverse max speed |
| `tDwellEnd` | TIME | IN | T#100MS | 端点停留时间，域 0~2 s [毫秒] / Endpoint dwell time |
| `bAxisReady` | BOOL | IN | — | 排线轴就绪反馈 [−] / Traverse axis ready feedback |
| `fAxisPos` | LREAL | IN | — | 排线轴当前位置反馈，**仅监视不参与积分** [米] / Actual position, monitoring only |
| `bAxisInPos` | BOOL | IN | — | 排线轴到位反馈 [−] / In-position feedback |
| `fDia` | LREAL | OUT | — | 当前卷径（**仲裁后**）[米] / Current diameter after arbitration |
| `fDiaRate` | LREAL | OUT | — | 卷径变化率，正值为收卷增大 [米每秒] / Diameter rate |
| `nRevolutions` | LREAL | OUT | — | 累计圈数（含小数）[圈] / Accumulated revolutions |
| `fTargetPos` | LREAL | OUT | — | 排线轴目标位置，域 0~行程 [米] / Traverse target position |
| `nDir` | INT | OUT | — | 排线方向，+1 / −1，0 为停止 [方向] / Traverse direction |
| `bAtEndA` | BOOL | OUT | — | 已到 A 端（行程零点）[−] / TRUE at end A |
| `bAtEndB` | BOOL | OUT | — | 已到 B 端（行程末端）[−] / TRUE at end B |
| `eState` | E_DL_WindState | OUT | — | 五态：`eIdle(0)` / `eWinding(10)` / `eDwelling(20)` / `eStopping(30)` / `eFault(99)` [−] / Current state |
| `bRunning` | BOOL | OUT | — | 卷绕运行中（含停留）[−] / TRUE while winding or dwelling |
| `bError` | BOOL | OUT | — | 故障锁存 [−] / Fault latch |
| `uErrorId` | UDINT | OUT | — | 事件码（见下表）/ Event code |

**故障码 / Codes**：

| 码位 | 级别 | 语义 |
|---|---|---|
| `0004_01B0` | 信息级 | 卷径、厚度、线速度或任务周期越界被钳位 |
| `0004_01B1` | 信息级 | 排线宽度或每圈节距越界被钳位 |
| `0004_01B2` | 信息级 | 注入卷径越界，回落内部递推 |
| `0004_01B3` | 信息级 | 排线轴未就绪，拒绝启动（不锁故障） |
| `0004_02C0` | 故障级 | 参数非有限值 |
| `0004_02C1` | 故障级 | 非法状态兜底 |
| `0004_02C2` | 故障级 | 排线轴到位超时（方向非零且长期不到位） |
| `0004_02C3` | 故障级 | 卷径递推不收敛（已达上限仍持续增圈） |

### 调用示例 / Example

```iecst
VAR
    fbWind     : FB_DL_WindingTraverse;   // 收卷排线实例 / Winding traverse instance
    fDiaNow    : LREAL;                   // 当前卷径 [米] / Current diameter
    fTravTarget: LREAL;                   // 排线目标位置 [米] / Traverse target
    nTravDir   : INT;                     // 排线方向 / Traverse direction
    bEndA      : BOOL;                    // 在 A 端 / At end A
END_VAR

// 每周期无条件调用：卷芯 152 mm、膜厚 12 µm、排线行程 0.6 m、节距 0.8 mm/圈
fbWind(bEnable := bLineOn, bStart := bWindingStart, bStop := bLineStop,
       bReset := bWindingReset, bUseInjectedDia := FALSE,
       fCoreDia := 0.152, fThickness := 0.000012, fLineSpeed := fWebSpeed,
       fTaskCycle := 0.01, fWebWidth := 0.62, fTraverseWidth := 0.6,
       nPitchPerRev := 0.8, fTraverseSpeedMax := 0.5, tDwellEnd := T#100MS,
       bAxisReady := bTravAxisReady, fAxisPos := fTravAxisFb, bAxisInPos := bTravInPos,
       fDia => fDiaNow, fTargetPos => fTravTarget, nDir => nTravDir,
       bAtEndA => bEndA);

// 排线目标送轴（轴指令由上层 FB_DL_AxisRelativeMove / 伺服功能块执行）
IF fbWind.bRunning AND (nTravDir <> 0) THEN
    fbTravAxis.MoveAbsolute(fPos := fTravTarget);
END_IF
```

**要点 / Notes**：
- **v1.0.1 致命修复（D-02）——「方向量被每拍清零」**：原待机分支写作 `nDirInt := 0;` 且位于分支体**最前**（无条件每拍执行）；启动成功转入 `eWinding` 后卷绕分支**从未把 `nDirInt` 赋回 ±1**，端点只做 `nDirInt := -nDirInt`（0 取反仍 0）→ 位移增量恒 0、排线轴原地不动、状态在 `eWinding`/`eDwelling` 间空转抖动。**现场后果：排线完全失效、收卷叠线，可立即造成废料。** 修法：方向赋值移入**启动成功分支**（固定正向启动），仅未启动时才清零。这是「同一变量在拍内多处写入、次序决定语义」的典型样本（**R32**）。
- **v1.0.1 严重修复（D-04）——端点判据必须带方向**：原判据 `fTravPos <= 0.0` 在启动首拍（`fTravPos = 0`）即命中「到达 A 端」→ 每次启动先跑到 A 端再折返，首圈排线相位错乱。修法：`IF (nDirInt > 0) AND (fTravPos >= fTravUse) … ELSIF (nDirInt < 0) AND (fTravPos <= 0.0) …`。**判据缺维度（「到达」隐含「正在向该端运动」）是文本机检的盲区。**
- **v1.0.1（D-07）**：轴等待上限 `(2·fTravUse/fSpeedUse)/fDtUse` 的分母是外部入参，未配置（0）时先得 `Inf` 再得 `NaN`，`NaN` 参与比较全为 FALSE → **轴等待超时永不触发、卡死在等待态**。修法：`MAX(fSpeedUse, DL_SPEED_MIN)` / `MAX(fDtUse, DL_CYCLE_MIN)` 双守卫。
- **v1.0.1（D-08）**：仲裁卷径 `fDiaArb` 首扫未预置 → 首拍输出 0 米并产生 −10 m/s 级假变化率，触发下游「卷径突变」报警。修法：首扫与复位两条路径均置 `fDiaArb := fCoreDia`（R19 首扫范式：派生量首扫即达稳态）。
- **观察项 O-3**：引脚名 `nPitchPerRev : LREAL` 前缀（`n` = 有符号整数）与类型冲突；与规格书 / 对外契约同源，PATCH 不改名，下一 MAJOR 统一改 `fPitchPerRev`。
- **轴反馈纪律**：`fAxisPos` 只作监视与诊断，目标位置由内部递推给出（避免反馈抖动反向污染节距积分）；需要闭环纠偏时在上层用 `fAxisPos` 与 `fTargetPos` 的偏差另做补偿。

---

## 18. FB_DL_WindingTensionCtrl ｜ 卷绕锥度张力与摆辊修正闭环（R11，v1.0.1）

**定位 / Positioning**：卷绕**张力给定合成器**。基准张力 = 目标张力 × 锥度系数（随卷径由 `1.0` 平滑衰减到 `1−K`），摆辊位置误差经**纯比例**修正环折算为张力修正量，两层相加后限幅输出，可直接送比例阀或伺服转矩限幅入口。卷径可由线速/角速反算，也可由外部注入（视觉或上位机）。

**降级必须显式 / Explicit degradation**：摆辊反馈丢失时进 `eOpenLoop` 并上报 `02D0`，**只输出锥度基准张力**——不静默沿用上次闭环输出，也不静默把自己当闭环继续算。修正量加在基准上而非串接，所以失反馈**不丢张力**，只丢修正。

**无扰投切 / Bumpless transfer**：开环恢复闭环时先给 PID 两拍跟踪（跟踪值 0，跟踪窗内过程值同步取基准以保证偏差为零），跟踪结束积分残量为零、比例作用全量恢复，杜绝投切瞬间张力跳变。

**纯比例修正环 / Proportional-only trim**：PID 实例积分与微分时间均给零——卷径时变工况下积分会被工况漂移拖着走，比例作用才不会饱和。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | `FALSE` | — | 总使能，`FALSE` 时输出 0 并复位 PID / Master enable |
| `bReset` | BOOL | IN | `FALSE` | — | 复位故障、计数与 PID，上升沿有效 / Reset fault, counters and PID |
| `bRun` | BOOL | IN | `FALSE` | — | 卷绕运行中，`FALSE` 时张力给定保持 0 / Winding running |
| `fTensionSet` | REAL | IN | `0.0` | N | 目标张力（满卷前基准），域 0.0~500.0 / Base tension setpoint |
| `fDancerPos` | REAL | IN | `0.0` | mm | 摆辊实际位置，0 为机械中位，绝对值超 500 判失效 / Dancer position |
| `fDancerRef` | REAL | IN | `0.0` | mm | 摆辊中位基准，非有限值按 0 处理 / Dancer reference |
| `fAxisSpeedRpm` | REAL | IN | `0.0` | 转每分 | 卷轴转速，低于 1.0 视为不可反算（编码器低频量化）/ Shaft speed |
| `fLineSpeed` | REAL | IN | `0.0` | 米每分 | 线速度，与卷径件入口同单位 / Line speed |
| `fCoreDia` | REAL | IN | `200.0` | mm | 卷芯直径，域 10.0~3000.0 / Core diameter |
| `fDiaMax` | REAL | IN | `1000.0` | mm | 满卷直径，必须大于卷芯直径，否则锥度退化 / Full-roll diameter |
| `fDiaInjected` | REAL | IN | `0.0` | mm | 外部注入卷径 / Injected diameter |
| `bUseInjectedDia` | BOOL | IN | `FALSE` | — | 卷径来源：`TRUE` 用注入值，`FALSE` 由速度比反算 / Diameter source |
| `fThickness` | REAL | IN | `0.10` | mm | 材料厚度，供卷径件层数积分 / Material thickness |
| `fTaperK` | REAL | IN | `0.50` | — | 锥度系数 0~1，满卷张力降至 `1−K` 倍 / Taper coefficient |
| `fPidKp` | REAL | IN | `0.5` | 每毫米 | 摆辊修正归一化增益（取绝对值后送负值实现反作用）/ Normalised dancer gain |
| `fTrimSpan` | REAL | IN | `1.0` | N | 修正满量程（归一化输出 × 该值 = 张力修正）/ Trim span |
| `fTensionMin` | REAL | IN | `0.0` | N | 张力输出下限，与上限对调时自动修复 / Tension lower limit |
| `fTensionMax` | REAL | IN | `500.0` | N | 张力输出上限，等于下限时输出被钉死 / Tension upper limit |
| `fTensionOut` | REAL | OUT | `0.0` | N | 张力给定输出，送比例阀或转矩限幅入口 / Tension command |
| `fDiaAct` | REAL | OUT | `0.0` | mm | 当前生效卷径，已钳入物理域 / Effective diameter |
| `fTaperFactor` | REAL | OUT | `1.0` | — | 实际锥度系数，域 `1−K`~`1.0` / Effective taper factor |
| `fDancerErr` | REAL | OUT | `0.0` | mm | 摆辊位置误差（实测 − 基准）/ Dancer error |
| `eState` | E_DL_TensionPhase | OUT | `eIdle` | — | `eIdle` 0 / `eOpenLoop` 10 / `eClosedLoop` 20 / `eFault` 99 |
| `bInControl` | BOOL | OUT | `FALSE` | — | 张力闭环生效，仅 `eClosedLoop` 为真 / Closed loop active |
| `bError` | BOOL | OUT | `FALSE` | — | 故障标志：故障级码或降级态置位，信息级码不置位 / Fault flag |
| `uErrorId` | UDINT | OUT | `0` | — | 事件 / 故障码（`0004_01Cx` 与 `0004_02Dx`），0 = 无 / Event or fault code |
| `fDiaLastValid` | REAL | OUT | `0.0` | mm | 最近一次有效卷径，0 = 尚无有效值 / Last valid diameter |
| `fbTensionPid` | FB_DL_PidController | IN_OUT | — | — | 摆辊修正环 PID 实例，**由调用方持有且只允许本块调用** / Dancer trim PID, driven only by this block |
| `stStat` | ST_DL_WindingStat | IN_OUT | — | — | 跨周期统计：`fTensionAvg`（张力一阶指数均值，仅闭环期更新）/ `uInvalidDiaCnt`（卷径连续无效次数）/ Persistent statistics |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0004_01C0` | 信息级 | 卷径无效（无有效反算或注入非法），已沿用上次有效值 | 停机不转时卷径无效属正常，`bRun` 撤除后不累计 |
| `0004_01C1` | 信息级 | 锥度系数分母退化或系数超界，已钳位（系数置 1.0） | 核对 `fDiaMax > fCoreDia`；K 应在 0~1（建议上限 0.7） |
| `0004_01C2` | 信息级 | 张力输出限幅生效，输出被钳到张力域边界 | 检查设定张力与 `fTensionMin/Max` 是否矛盾 |
| `0004_02D0` | 故障级 | 摆辊反馈丢失（非有限值或超机械行程），降级开环 | **不停机**，但张力只剩锥度基准；查摆辊传感器与机械限位 |
| `0004_02D1` | 故障级 | 卷径连续无效超限（几何法已不可信），锁存待复位 | 查编码器/测速或改用 `bUseInjectedDia` 注入卷径 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_WinderTension
VAR
    fbTension      : FB_DL_WindingTensionCtrl;   // 张力控制实例 / Tension controller
    fbTensionPid   : FB_DL_PidController;        // 摆辊修正 PID（只由本块调用）/ Trim PID
    stWinding      : ST_DL_WindingStat;          // 跨周期统计 / Persistent statistics
    bLineRun       : BOOL := TRUE;               // 产线运行 / Line running
    bFaultReset    : BOOL;                       // 故障复位 / Fault reset
    bWinding       : BOOL := TRUE;               // 卷绕运行中 / Winding
    fTensionRecipe : REAL := 120.0;              // 配方张力 [牛] / Recipe tension
    fDancerFeedback: REAL := 0.5;                // 摆辊反馈 [毫米] / Dancer feedback
    fWinderRpm     : REAL := 600.0;              // 卷轴转速 [转每分] / Shaft speed
    fLineSpeedAct  : REAL := 120.0;              // 线速度 [米每分] / Line speed
    fTensionCmd    : REAL;                       // 张力给定 [牛] / Tension command
    fDiaNow        : REAL;                       // 当前卷径 [毫米] / Current diameter
    fTaperNow      : REAL;                       // 当前锥度系数 / Taper factor
    bInControl     : BOOL;                       // 闭环生效 / Closed loop active
    eTensionPhase  : E_DL_TensionPhase;          // 相位观测 / Phase
    bTensionErr    : BOOL;                       // 故障 / Fault
    uTensionErrId  : UDINT;                      // 事件码 / Event code
    fValveCmd      : REAL;                       // 比例阀指令 [牛] / Proportional valve command
    fDancerErrOut  : REAL;                       // 摆辊误差 [毫米] / Dancer error
    fDiaLastValidOut : REAL;                     // 最近有效卷径 [毫米] / Last valid diameter
END_VAR

// 每周期无条件调用：张力和卷径两件都经引用于本块内驱动
fbTension(bEnable := bLineRun, bReset := bFaultReset, bRun := bWinding,
          fTensionSet := fTensionRecipe, fDancerPos := fDancerFeedback,
          fDancerRef := 0.0, fAxisSpeedRpm := fWinderRpm, fLineSpeed := fLineSpeedAct,
          fCoreDia := 200.0, fDiaMax := 1000.0, fDiaInjected := 0.0,
          bUseInjectedDia := FALSE, fThickness := 0.10,
          fTaperK := 0.50, fPidKp := 0.5, fTrimSpan := 5.0,
          fTensionMin := 0.0, fTensionMax := 300.0,
          fTensionOut => fTensionCmd, fDiaAct => fDiaNow, fTaperFactor => fTaperNow,
          fDancerErr => fDancerErrOut, eState => eTensionPhase,
          bInControl => bInControl, bError => bTensionErr, uErrorId => uTensionErrId,
          fDiaLastValid => fDiaLastValidOut,
          fbTensionPid := fbTensionPid, stStat := stWinding);

// 张力给定直接送比例阀；外部不要再对 fbTensionPid 赋值任何引脚
fValveCmd := fTensionCmd;
END_PROGRAM
```

**要点 / Notes**

- **`fbTensionPid` 只允许本块调用**：外部若再对该实例赋引脚，归一化输出域会被覆盖，修正量会放大一百倍（`fTrimSpan` 倍数）。
- **`fTaperK` 取值经验**：0 表示全程恒张力，1 表示满卷张力降到零（实际工艺通常不可用），建议上限取 0.7。
- **摆辊基准同基**：`fDancerPos` 与 `fDancerRef` 必须同一基准；本件用绝对值 500 mm 判「机械不可能值」，若机械行程超过 500 mm 需调整该常量后重新入库。
- **开环降级期必须加摆辊限位联锁**：降级时张力只随卷径变化，摆辊会漂到机械限位，本块不做摆辊位置保护。
- **本件不构成安全功能**：断带与超张力保护必须由硬件与认证安全回路承担。

---

## 19. FB_DL_LineInterp2Axis ｜ 两轴直线插补与速度剖面（R12，v1.0.1）

**定位 / Positioning**：把「起点 → 终点」的二维直线运动折算成逐拍的 X / Y 位置给定，中间由一条**梯形或三角速度剖面**驱动。服务对象是点胶、涂覆、搬运的斜线段、XY 平台的对角定位、贴装头的两点直连——不追求轨迹精度到微米，要的是「速度连续、单轴不超限、暂停能接上、终点不爬行」。

**为什么不直接按合成速度喂给两轴 / Why profile first**：两轴各自限速时，合成速度受**最紧的那一根轴**约束（X 分量 = V×cosθ，必须 ≤ X 轴限速）。本件在准备相一次性算出「单轴限速折算后的合成速度上限」，再定峰值速度，避免运动中因某轴超限而临时降速（那会造成速度台阶）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时停止推进并回待机 / Enable, stopping the move and returning to idle |
| `bReset` | `BOOL` | IN | — | — | 上升沿清故障 / Rising edge clears the fault |
| `bStart` | `BOOL` | IN | — | — | 启动，**上升沿有效**（待机与完成态可受理）/ Rising edge starts the move |
| `bHold` | `BOOL` | IN | — | — | 暂停，`TRUE` 时速度归零且位移保持 / Pauses the interpolation while TRUE |
| `fStartX` | `REAL` | IN | — | mm | 起点 X / Start X |
| `fStartY` | `REAL` | IN | — | mm | 起点 Y / Start Y |
| `fEndX` | `REAL` | IN | — | mm | 终点 X / End X |
| `fEndY` | `REAL` | IN | — | mm | 终点 Y / End Y |
| `fPathSpeed` | `REAL` | IN | `100.0` | mm/s | 期望合成速度，域 > 0 / Desired path speed |
| `fAccel` | `REAL` | IN | `500.0` | mm/s² | 加减速度，域 > 0 / Acceleration |
| `fMaxSpeedX` | `REAL` | IN | `1000.0` | mm/s | X 轴速度上限，域 > 0 / X axis speed limit |
| `fMaxSpeedY` | `REAL` | IN | `1000.0` | mm/s | Y 轴速度上限，域 > 0 / Y axis speed limit |
| `fNominalCycle` | `REAL` | IN | `0.004` | s | 标称插补周期，域 0.0001~1 / Nominal interpolation period |
| `fMaxPathLen` | `REAL` | IN | `100000.0` | mm | 允许最大路径长度，域 > 0 / Maximum path length |
| `bBusy` | `BOOL` | OUT | — | — | 插补进行中（含准备段）/ Interpolation running |
| `bActive` | `BOOL` | OUT | — | — | 位置给定有效（推进中或暂停中）/ Position command valid |
| `bDone` | `BOOL` | OUT | — | — | 到达终点，保持到下一次启动 / End reached, held until the next start |
| `fCmdX` | `REAL` | OUT | — | mm | X 位置给定 / X position command |
| `fCmdY` | `REAL` | OUT | — | mm | Y 位置给定 / Y position command |
| `fPathProgress` | `REAL` | OUT | — | % | 路径完成度 0~100 / Path progress |
| `fPathVel` | `REAL` | OUT | — | mm/s | 当前合成速度 / Current path speed |
| `fPathLen` | `REAL` | OUT | — | mm | 本次路径总长 / Total path length |
| `fPeakVel` | `REAL` | OUT | — | mm/s | 本次实际峰值速度 / Effective peak speed |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `0204`~`0207` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_LineInterpPhase` | OUT | — | — | 相位，见下 / Current phase |

状态枚举：`E_DL_LineInterpPhase`（`eIdle` 0 ／ `ePrep` 10 ／ `eAccel` 20 ／ `eCruise` 30 ／ `eDecel` 40 ／ `eDone` 50 ／ `eHeld` 60 ／ `eFault` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0004_0109` | 信息级 | 路径长度为零，当拍直接完成，给定等于起点、进度 100 | 起终点相同属合法调用（如重复定位到同一点），不是错误 |
| `0004_010A` | 信息级 | 标称插补周期越界，已钳到 0.1 ms~1 s | 周期应与实际任务周期一致，否则位移积分与实际节拍不符 |
| `0004_010B` | 信息级 | 单轴速度上限参与折算，合成速度已被压低 | 正常路径：合成速度被压到「恰好不越单轴限」的值；若长期出现说明某轴限速设得过低 |
| `0004_010C` | 信息级 | 路径过短，速度曲线降为三角（无匀速段） | 短行程必然如此；若要更高节拍请提高加速度而非提高速度 |
| `0004_0204` | 故障级 | 速度、加速度、单轴限速或最大路径长参数非法（≤ 0 或非有限） | 四个参数都必须 > 0；改正后复位 |
| `0004_0205` | 故障级 | 路径长度超过 `fMaxPathLen` | 路径超过机械行程或组态上限；核对坐标是否写错 |
| `0004_0206` | 故障级 | 输入含非有限值（NaN / 无穷），前置拦截 | 上游坐标计算出现除零或开方负数 |
| `0004_0207` | 故障级 | 非法状态兜底（终端安全态） | 检查在线修改与库版本 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_GantryDiagonal
VAR
    fbLine      : FB_DL_LineInterp2Axis;    // 插补实例 / Interpolation instance
    bLineRun    : BOOL := TRUE;             // 使能 / Enable
    bLineStart  : BOOL;                     // 启动沿 / Start edge
    bLineHold   : BOOL;                     // 暂停 / Hold
    bLineReset  : BOOL;                     // 复位 / Reset
    fFromX      : REAL := 0.0;              // 起点 X / Start X
    fFromY      : REAL := 0.0;              // 起点 Y / Start Y
    fToX        : REAL := 300.0;            // 终点 X / End X
    fToY        : REAL := 400.0;            // 终点 Y / End Y
    fCmdXOut    : REAL;                     // X 给定 / X command
    fCmdYOut    : REAL;                     // Y 给定 / Y command
    fProgress   : REAL;                     // 完成度 / Progress
    fVelNow     : REAL;                     // 当前速度 / Current speed
    fLenTotal   : REAL;                     // 路径总长 / Path length
    fPeakGot    : REAL;                     // 峰值速度 / Peak speed
    bLineBusy   : BOOL;                     // 忙 / Busy
    bLineActive : BOOL;                     // 给定有效 / Active
    bLineDone   : BOOL;                     // 完成 / Done
    bLineFault  : BOOL;                     // 故障 / Fault
    uLineErr    : UDINT;                    // 事件码 / Event code
    eLinePhase  : E_DL_LineInterpPhase;     // 相位观测 / Phase
END_VAR

fbLine(bEnable := bLineRun, bReset := bLineReset, bStart := bLineStart, bHold := bLineHold,
       fStartX := fFromX, fStartY := fFromY, fEndX := fToX, fEndY := fToY,
       fPathSpeed := 100.0, fAccel := 200.0, fMaxSpeedX := 1000.0, fMaxSpeedY := 1000.0,
       fNominalCycle := 0.004, fMaxPathLen := 100000.0,
       bBusy => bLineBusy, bActive => bLineActive, bDone => bLineDone,
       fCmdX => fCmdXOut, fCmdY => fCmdYOut,
       fPathProgress => fProgress, fPathVel => fVelNow,
       fPathLen => fLenTotal, fPeakVel => fPeakGot,
       bError => bLineFault, uErrorId => uLineErr, eState => eLinePhase);

// 典型工况（V1）：路径 500 mm、速度 100、加速度 200 → 单侧加速距离 25 mm、峰值 100，
// 中点给定位 (150, 200)、完成度 50、合成速度 100
END_PROGRAM
```

**要点 / Notes**

- **恢复必须按剩余量分流**：v1.0.1 修的正是这条（范式 R41）。原加速段出口只看 `fS >= fAccDist`，暂停恢复时 `fS` 早已超过加速距离，加速段当拍即被判完成、下一拍速度直跳峰值——位置连续但速度阶跃，伺服按位置给定跟随会报跟随误差。现在出口要求「位移到位**且**速度已达峰值」，恢复时剩余量不足加速距离则直接进减速段。
- **终点不爬行**：减速段出口把已走距离**强制钳到路径总长**、进度置 100，收尾速度保留峰值的 5%（`DL_DECEL_FLOOR`）。纯指数衰减会让位移「永远差最后一点」，现场表现为 `bDone` 迟迟不来。
- **暂停语义**：`bHold = TRUE` 时速度归零、位移保持、`bActive` 仍为真（给定仍有效）；恢复后从当前位移重新加速，**不重头**。不要把 `bHold` 与 `bStart` 混用——`bStart` 在暂停态不受理。
- **完成态可再次启动**：`bDone` 保持到下一次 `bStart` 上升沿。重复定位到同一点时不会因为 `bDone` 已为真而拒动。
- **不注入轴接口**：本件只产出位置给定，使能、回零、限位、停止都归 `I_DL_MotionAxis` 实现块。这样换伺服品牌不需要动插补逻辑。

---
---

## 20. FB_DL_PassiveHomingMonitor ｜ 被动回零旁路监听（R13，v1.0.1）

**定位**：轴被**外力**移动时（手摇轮、另一驱动拖动、重力下落、维护推车）的参考点确认——旁路监听参考事件（原点开关沿 / Z 相 / 标记锁存），按「方向一致性 + 速度窗 + 多次位置一致性」三条判据确认参考点，输出建议施加的位置偏移给上层，由上层按 `MC_SetPosition` 语义消费。**不发任何运动指令、不自造轴状态、不定义轴状态枚举**（R11 判例：轴状态只由运动层拥有；本件 `ePhase` 仅供 HMI 诊断显示，禁止被上层当轴状态使用或反向改写轴状态位）。

**与 `FB_DL_AxisHomingSeq` 的分工**：后者是**主动回零顺控**（自己发运动指令、四模式），本件**只旁路监听并输出偏移**；两者可并存，但不得互相改写对方的结论位。

### 20.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能，FALSE 冻结监听并清布防；复位通道不受其屏蔽 / Enable |
| `bReset` | `BOOL` | IN | — | — | 上升沿清结论与锁存 / Rising edge reset |
| `bArm` | `BOOL` | IN | — | — | 布防，上升沿开始监听、下降沿撤防 / Rising edge arms, falling edge disarms |
| `bRefEvent` | `BOOL` | IN | — | — | 参考事件电平（原点开关 / Z 相），内部取上升沿 / Raw reference event |
| `bDirForward` | `BOOL` | IN | `TRUE` | — | 本拍运动方向，TRUE 正向 / Current direction |
| `fActPos` | `REAL` | IN | — | mm | 实际位置（只读采样），域 −1E7~1E7 / Actual position |
| `fActVel` | `REAL` | IN | — | mm/s | 实际速度（只读采样），域 −1E5~1E5 / Actual velocity |
| `bInMotion` | `BOOL` | IN | — | — | 轴在运动（速度超噪声带为 TRUE） / Axis in motion |
| `fVelMin` | `REAL` | IN | `1.0` | mm/s | 速度窗下限，域 0.01~100；低于降精度采信（01C3）/ Velocity window low |
| `fVelMax` | `REAL` | IN | `500.0` | mm/s | 速度窗上限，域 1~10000；高于同样降精度（01C3，偏离留档②不新增码位）/ Velocity window high |
| `nRequireEvents` | `INT` | IN | `2` | 次 | 需一致性确认的事件次数，域 1~3 / Required consistent events |
| `fConsistencyTol` | `REAL` | IN | `0.1` | mm | 事件位置一致性容差，域 0.001~10 / Consistency tolerance |
| `tArmTimeout` | `TIME` | IN | `T#120S` | — | 布防总超时，域 1 s~1 h / Arming timeout |
| `bReferenced` | `BOOL` | OUT | — | — | 参考点已确认（保持语义，复位沿清除）/ Referenced, held |
| `fRefPos` | `REAL` | OUT | — | mm | 确认的参考点位置 = 累计均值（取算术均值，非首个事件）/ Confirmed reference position |
| `fOffsetToApply` | `REAL` | OUT | — | mm | 建议偏移 = 0.0 − fRefPos，夹 ±1.0E6；参考点非 0 的现场由调用方消费时叠加目标值（偏离留档①不新增引脚）/ Offset to apply |
| `nEventCount` | `UINT` | OUT | — | 次 | 本轮布防内已捕获事件数 / Events captured this arming |
| `ePhase` | `E_DL_PassiveHomePhase` | OUT | — | — | `eIdle(0)` / `eArmed(10)` / `eCaptured(20)` / `eConfirmed(30)` / `eTimeout(40)` / `eFault(99)`；**仅供诊断显示，不是轴状态** / Internal phase, diagnostics only |
| `eHealth` / `uDiagCode` / `uErrorId` / `bError` | — | OUT | — | — | NE107 健康态 / 诊断码 / 故障码 / 故障标志（类型引用自 DL_Device 契约件）/ Health and fault outputs |

### 20.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0004_01C3` | 信息级：速度窗越界，事件已采信但精度降级 / Velocity window exceeded, low precision | 手摇过快或过慢；重摇或放宽窗口 |
| `16#0004_01C4` | 信息级：方向与上次相反，一致性计数重置 / Direction reversed, count reset | 单向摇轮确认；反向事件不算一致 |
| `16#0004_01C5` | 信息级：布防期间长时间无运动（10 s，未超总超时）/ No motion during arming | 提示操作方式；非故障 |
| `16#0004_01C6` | 信息级：多次事件位置超容差，计数重置 / Position inconsistent, count reset | 原点开关抖动或重复行程；检查感应块 |
| `16#0004_02D2` | 故障级：布防超时未捕获事件 / Arm timeout without event | 需重新布防；计数从 0 重建（R41 恢复不重头） |
| `16#0004_02D3` | 故障级：位置或速度非有限 / Non-finite position or velocity | 检查位置反馈源；需 `bReset` 退出 |
| `16#0004_02D4` | 故障级：非法状态兜底 / Illegal state fallback | 复现后上报 |

### 20.3 调用示例 / Example

```iecst
PROGRAM PRG_PassiveHome
VAR
    fbHome     : FB_DL_PassiveHomingMonitor;  // 被动回零监听 / Passive homing monitor
    bAxisEn    : BOOL;                        // 轴使能 / Axis enabled
    bHomeArm   : BOOL;                        // 布防按钮（保持到确认）/ Arm button
    bOrigSw    : BOOL;                        // 原点开关 / Origin switch
    bDirPos    : BOOL;                        // 当前运动方向 / Direction
    fPosAct    : REAL;                        // 实际位置 [mm] / Actual position
    fVelAct    : REAL;                        // 实际速度 [mm/s] / Actual velocity
    bMov       : BOOL;                        // 在运动 / In motion
    bAxisReset : BOOL;                        // 复位 / Reset
    fSetPos    : REAL;                        // 送 MC_SetPosition 的偏移 / Offset to apply
END_VAR

(* 每周期无条件调用 *)
fbHome(
    bEnable        := bAxisEn,
    bReset         := bAxisReset,
    bArm           := bHomeArm,
    bRefEvent      := bOrigSw,
    bDirForward    := bDirPos,
    fActPos        := fPosAct,
    fActVel        := fVelAct,
    bInMotion      := bMov,
    fVelMin        := 5.0,
    fVelMax        := 200.0,
    nRequireEvents := 2,
    fConsistencyTol:= 0.1,
    tArmTimeout    := T#120S);

// 确认后由上层按 MC_SetPosition 语义消费（本件不发运动指令）
IF fbHome.bReferenced THEN
    fSetPos := fbHome.fOffsetToApply;   // = 0 − fRefPos / offset onto zero
END_IF
END_PROGRAM
```

### 20.4 要点 / Notes

- **v1.0.1 修复（坏值穿透）**：事件受理条件补串 `bEnable AND NOT _bFaultCond`——原实现下，非有限值被检出、快照置零的同一拍若恰有参考事件沿，零化快照仍被采信，极端情形把 0.0 锁存为参考点，脏值直达 `bReferenced` 保持位。
- **参考点取均值不取首事件**：两次一致事件位置 100.00 / 100.05 mm → `fRefPos = 100.025`（算术均值）；`nRequireEvents` 越大抗抖越好，但布防时间越长。
- **超时恢复不重头**（R41）：`eTimeout` 后重新布防，计数从 0 重建——不允许沿用上次部分计数冒充一致性。
- **`ePhase` 只许看，不许用**：把 `ePhase` 当轴状态去写轴使能/模式位，等于绕过运动层的状态所有权，是本库明令禁止的接法。
- **偏移语义**：按「参考事件处应读 0.0 mm」的通用约定输出 `0 − fRefPos`；现场参考点非 0 时由调用方在消费时叠加目标值，本件不新增引脚（不破坏已冻结契约）。
- 撤防后 `fOffsetToApply` 保持上次值且夹 ±1.0E6 mm；冷启动首拍输出 0.0（R43 保持夹域）。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_AxisFollowingErrorMonitor` | 跟随误差三级判定（提示 / 严重 / 断使能建议） | `fSetPosition` / `fActPosition` / `fError` |
| `FB_DL_AxisSynchronizedStop` | 按固定减速度斜坡生成停车序列并预估停止距离 | `bExecute` / `fDecel` / `fStopDistance` |
| `FB_DL_BacklashCompensator` | 换向瞬间叠加方向性补偿量，EWMA 自学习背隙 | `fCmdPosition` / `fBacklash` / `bAutoLearn` |

> 用法要点：`BacklashCompensator` 与 `FB_DL_RollerGapAdjust`（工艺辊缝顺控）职责不重叠；首拍无历史方向时**不补偿**，否则轴会凭空跳一下；`fLearnGain` 有效域 0.01~0.5（越界钳位并置信息码）。


---

---

## R19 批次补录接口表（2026-11-16，本子库 4 件，R19 遗留 P1）

> 本节为 R19 文档缺口补录。四件一律消费外部给定（位置 / 计数 / 偏差）与采样周期，**不自造轴状态、不定义轴状态枚举、不发运动指令**（R31 家族纪律）；`tSampleTime` 为速度/层数折算的时间基准（R78）。

### `FB_DL_ExternalEncoderScaler`
- **功能**：外部编码器原始计数 → 工程位置 / 速度：多圈回绕展开（`nMultiTurnBits` 位宽）、齿轮比、反向、偏移与每转计数换算，速度按 `tSampleTime` 差分。
- **输入引脚**：`bEnable`、`bReset`、`diRawCount`、`uCountsPerRev`、`fPitch`、`iGearNum`、`iGearDen`、`bInvert`、`fOffset`、`nMultiTurnBits`、`tSampleTime`
- **输出引脚**：`fPosition`、`liTotalCount`、`bWrapped`、`uWrapCount`、`fVelocity`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0004_01CD` / `01CE` ｜ 故障 `16#0004_02DE`~`02E0`

### `FB_DL_CamPhaseTrim`
- **功能**：凸轮相位在线修调：目标相位经**限速斜坡**逼近（`fRateMax`），相位偏置整体限幅（`fPhaseLimit`），标记脉冲可触发一次性修正量（`bMarkPulse` + `fMarkCorrection`，已修正的标记不再重复计入，`uMarkCount` 可查）。
- **输入引脚**：`bEnable`、`bReset`、`fPhaseOffsetCmd`、`fRateMax`、`fPhaseLimit`、`bTrimOnMark`、`fMarkCorrection`、`bMarkPulse`、`tSampleTime`
- **输出引脚**：`fPhaseOffset`、`bTrimming`、`bLimited`、`uMarkCount`、`eErr`、`bError`
- **码位**：信息 `16#0004_01CF` / `01D0` ｜ 故障 `16#0004_02E1`~`02E3`

### `FB_DL_FilmWebCenter`
- **功能**：薄膜纠偏（EPC/LPC 位置给定）：偏差 → 增益 → 死区豁免 → 速率限幅 → 行程限位 → 位置给定；`bWebPresent = FALSE` 时判 `bWebLost` 并冻结给定（断料不追偏）。
- **输入引脚**：`bEnable`、`bReset`、`bAuto`、`fDeviation`、`fGain`、`fManualOffset`、`fDeadband`、`fRateMax`、`fTravelMin`、`fTravelMax`、`bWebPresent`、`tSampleTime`
- **输出引脚**：`fPositionSp`、`bInDeadband`、`bLimited`、`bWebLost`、`bValid`、`eErr`、`bError`
- **码位**：信息 `16#0004_01D1` / `01D2` ｜ 故障 `16#0004_02E4`~`02E6`

### `FB_DL_WindingLayerCounter`
- **功能**：收卷层数计数：由卷径 / 芯径 / 材料厚度反推层数并比较上拍值出 `bLayerEdge`，支持换卷复位（`bNewRoll`）、方向选择、厚度在线自估（`fThicknessEst`）；层数与卷径不一致时置 `bInconsistent`。
- **输入引脚**：`bEnable`、`bReset`、`bNewRoll`、`fCoilDiameter`、`fCoreDiameter`、`fThickness`、`diRevCount`、`uLayerMax`、`bDirPositive`
- **输出引脚**：`uLayerDone`、`uLayerRemain`、`bLayerEdge`、`bInconsistent`、`fThicknessEst`、`uRollCount`、`eErr`、`bError`
- **码位**：信息 `16#0004_01D3` / `01D4` ｜ 故障 `16#0004_02E7`~`02E9`

### 续补说明 / Remaining
本手册现覆盖至 R19 批次；`DL_Motion` 余下 R1~R18 历史件（约 21 件）接口表**下轮续补**。
---

## R22 批次接口表（R22 追加 · 5 件 · 轴侧安全层开层）

### FB_DL_AxisBrakeSeq ｜ 伺服抱闸时序（DL_Motion / AxisSafety）
- **输入引脚**：`bEnableReq`、`fActVel`（mm/s）、`fStandstillVel`（mm/s 缺省 1.0）、`bBrakeReleaseFb`、`bBrakeFbAvailable`（缺省 TRUE）、`tBrakeRelease`（缺省 T#200MS）、`tBrakeHold`（缺省 T#300MS）、`tStandstill`（缺省 T#100MS）、`tFbTimeout`（缺省 T#2S，**须 > tBrakeRelease**）
- **输出引脚**：`bServoEnable`、`bBrakeReleaseCmd`、`bSeqDone`（单拍脉冲）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D5`（无反馈按时间序列放行）/ `01D6`（等待延长，两处共用靠状态区分）｜ 故障 `02EA`（释放反馈超时禁止使能，全失电）/ `02EB`（未静止拒绝断使能，有转矩时保持带使能+抱闸打开）/ `02EC`（参数非法/非有限/兜底，三支复用）
- **要点**：上电序先释放后使能、断电序先静止后抱闸再断使能——两序写反即掉轴；eEnabled 不得直跳 eDisabled。

### FB_DL_VirtualMasterAxis ｜ 虚拟主轴相位源（DL_Motion / MasterSource）
- **输入引脚**：`bEnable`、`fVelSet`（mm/s）、`fAccLimit`/`fDecLimit`（mm/s² 缺省 1000.0）、`bHold`、`bPhaseReset`（上升沿）、`fPosInit`（mm 缺省 0.0）、`tSample`（缺省 T#1MS，禁读系统时钟）
- **输出引脚**：`fMasterPos`（LREAL mm）、`fMasterVel`、`fMasterAcc`、`bReady`、`bLimited`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D7`（限幅生效边沿发布）/ `01D8`（复位已执行）｜ 故障 `02ED`（采样/速度参数非法，冻结）/ `02EE`（相位超 1.0E15 mm 精度门已冻结，需复位才可恢复）/ `02EF`（兜底）
- **要点（v1.0.1）**：eFault 相位与故障拍均冻结积分，恢复仅经失能复位或 bPhaseReset。

### FB_DL_MotionCmdQueue ｜ 运动指令排队器（DL_Motion / CommandMgmt）
- **输入引脚**：`bEnq`（上升沿）、`fTargetPos`（mm）、`fVelocity`（mm/s）、`bAxisDone`（调用方注入）、`bAxisError`、`bOverwriteOldest`（缺省 TRUE）、`bClear`
- **输出引脚**：`bExec`（单拍）、`fExecPos`、`fExecVel`、`uCount`（0~8）、`bFull`、`uDropped`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01D9`（满队：靠 uDropped 是否自增区分丢最旧/拒绝）/ `01DA`（同目标去重）｜ 故障 `02F0`（非有限拒绝入队不占槽）/ `02F1`（轴故障清队挂起禁止自动续发）/ `02F2`（兜底）
- **要点（v1.0.1）**：eSending 被清队竞态下回 eIdle 不空等 Done；只做 Buffered 语义，Blending 不立（职责边界段留档）。

### FC_DL_CamTableValidate ｜ 凸轮表合法性校验（DL_Motion / CamData ｜ FUNCTION → BOOL）
- **输入引脚**：`afPhase`（ARRAY[0..63] OF REAL，°）、`afSlave`（mm）、`uSegCount`（2~64）、`bCyclic`（缺省 TRUE）、`fPhaseTol`（° 缺省 0.01）、`fMaxSlope`（mm/° 缺省 100.0）
- **输出引脚**：`uFailMask`（1 非单调 / 2 非有限 / 4 未闭合 / 8 斜率超限 / 16 点数非法，全掩码不早退）、`uFailIdx`（1 基首败段号）、`fMaxSlopeFound`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01DB`（非周期表跳过闭合校验）/ `01DC`（斜率超限表仍可用）｜ 故障 `02F3`（非单调/点数非法）/ `02F4`（从轴非有限）/ `02F5`（首尾未闭合）

### FB_DL_AxisInPosMonitor ｜ 到位稳定判定（DL_Motion / AxisMonitor）
- **输入引脚**：`bEnable`、`fActPos`/`fTargetPos`（mm）、`fActVel`（mm/s）、`fPosTol`（mm 缺省 0.05）、`fVelTol`（mm/s 缺省 1.0）、`tSettle`（缺省 T#100MS）、`uChatterLimit`（次 缺省 5）、`tChatterWin`（缺省 T#2S）
- **输出引脚**：`bInPos`、`bSettled`（取放联锁用，出窗即清不锁存跨件）、`uChatterCount`、`bChatterAlarm`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0004_01DD`（入窗未稳定）/ `01DE`（抖振计数按窗清零）｜ 故障 `02F6`（容差/时间参数非法）/ `02F7`（非有限保持上次判定，下游与 bValid 相与）/ `02F8`（兜底）
- **要点**：只判「到位稳定」，跟随误差监视归驱动器（职责划界段见头注释）。

### 续补说明 / Remaining（R22 更新）
本手册现覆盖至 R22 批次；`DL_Motion` 余下 R1~R21 历史件（约 21 件）接口表继续按「每轮 ≤10 件」补录。


*Last updated: 2026-11-16（R22 追加接口表 5 件）｜ 道莅工控代码库产品总监*

---

## R23 批次接口表（R23 追加 · 2 件 · 运动工艺延伸（ROADMAP P1） ｜ 子库 v0.12.0→v0.13.0）

### FB_DL_WaferCountAxis ｜ 晶圆计数轴（DL_Motion ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `bEncPulse` | IN | `BOOL` | 编码器脉冲输入 [—] |
| `uPulsesPerWafer` | IN | `UINT := 100` | 分频比 [脉冲 |
| `bCountEnable` | IN | `BOOL` | 计数使能 [—] |
| `bResetCount` | IN | `BOOL` | 计数复位 [—]，优先级最高 |
| `uWaferCount` | OUT | `UDINT` | 晶圆计数 [片]，饱和 4294967295 不回绕 |
| `bWaferIndexPulse` | OUT | `BOOL` | 片位同步单拍脉冲 [—] |
| `fEstRate` | OUT | `LREAL` | 估算节拍率 [片 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FB_DL_BagFeedDancerSync ｜ 制袋供膜摆辊同步（DL_Motion ｜ FUNCTION_BLOCK）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fDancerPosPct` | IN | `LREAL` | 摆辊位置 [百分数]，50 = 中位，有效域 0..100 |
| `fLineSpeedMmS` | IN | `LREAL` | 线速前馈源 [毫米 |
| `fFeedKp` | IN | `LREAL := 1.5` | 摆辊 PI 比例增益 [（毫米 |
| `fFeedKi` | IN | `LREAL := 0.2` | 摆辊 PI 积分增益 [（毫米 |
| `fFeedMaxMmS` | IN | `LREAL := 500.0` | 供膜速度上限 [毫米 |
| `bEnable` | IN | `BOOL` | 同步使能 [—] |
| `bReset` | IN | `BOOL` | 故障复位 [—]，清除张力故障锁存 |
| `fFeedSpMmS` | OUT | `LREAL` | 供膜速度给定 [毫米 |
| `bDancerOk` | OUT | `BOOL` | 摆辊信号可信 [—] |
| `bTensionFault` | OUT | `BOOL` | 张力疑似故障 [—] |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### 续补说明 / Remaining（R23 更新）

> 本节为 R23 新增件接口表（引脚取自 .st 声明区实测抽取，脚本 pins_r23.json 留档）；R23 终审修复件以修订历史为准（v1.0.1 引脚契约零变更）；历史件补录按 R88 节奏（每轮 ≤10 件）继续。

## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 4 件 + 修复件 0 件）

### FC_DL_TrackerBacktrackCalc（函数 FC，）｜ v1.0.0

- **功能**：水平单轴（N-S 向）跟踪支架的阴影几何逆跟踪修正。设排距 P、
- **码位带**：16#0004_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `fSunElevDeg` | LREAL | 太阳高度角 [度]，< 0 判夜间 |
| INPUT | `fSunAzDeg` | LREAL | 太阳方位角 [度]，正北起顺时针 0..360 |
| INPUT | `fAxisAzDeg` | LREAL := 180.0 | 旋转轴方位角 [度]，N-S 水平轴典型 180 |
| INPUT | `fGcrRatio` | LREAL := 0.35 | 邻排占空比 GCR = W/P [比值]，有效域 (0, 1] |
| INPUT | `fMaxAngleDeg` | LREAL := 60.0 | 最大旋转角限幅 [度]，机械限位，须 > 0 |
| OUTPUT | `fTrackAngleDeg` | LREAL | 目标旋转角 [度]（含逆跟踪修正与限幅） |
| OUTPUT | `bBacktrack` | BOOL | TRUE = 本拍目标角处于逆跟踪修正段 |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0004_01E3 起信息级、16#0004_0300 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 结果可用标志 |

### FB_DL_WindingAlignEdge（功能块 FB，）｜ v1.0.0

- **功能**：极片边缘跟随纠偏——边缘传感器上升沿锁存轴位置为边缘基准，
- **码位带**：16#0004_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 跟随使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `bEdgeSensor` | BOOL | 边缘传感器电平 [—]（TRUE = 检出极片边缘） |
| INPUT | `fAxisPosMm` | LREAL | 轴位置实测 [毫米]（纠偏机构位置基准） |
| INPUT | `fTargetEdgeMm` | LREAL := 0.0 | 目标边缘位置 [毫米] |
| INPUT | `fSensorOffsetMm` | LREAL := 0.0 | 传感器安装偏置 [毫米]（锁存值补偿） |
| INPUT | `fFilterAlpha` | LREAL := 0.2 | 一阶滤波系数 [无量纲]，域 [0, 1]，0 = 冻结滤波值 |
| INPUT | `fGainPctPerMm` | LREAL := 10.0 | 纠偏增益 [百分数每毫米] |
| INPUT | `fTravelLimitMm` | LREAL := 20.0 | 纠偏行程限 [毫米]，须 > 0 |
| INPUT | `fMaxJumpMm` | LREAL := 5.0 | 相邻边沿位移物理上限 [毫米]，须 > 0 |
| INPUT | `fCycleTimeS` | LREAL := 0.01 | 任务扫描周期 [秒]，须 > 0（R95 代理阈值） |
| OUTPUT | `fCorrectOutPct` | LREAL | 纠偏输出 [百分数]，-100..100，行程限内 |
| OUTPUT | `fOffsetMm` | LREAL | 滤波后边缘偏差 [毫米]（诊断出口） |
| OUTPUT | `bEdgeLatch` | BOOL | 边缘锁存有效 [—] |
| OUTPUT | `eState` | E_DL_WindAlignState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0004_01E5 起信息级、16#0004_0303 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_SolderRibbonTension（功能块 FB，）｜ v1.0.0

- **功能**：光伏焊带（互连条）放卷张力控制——锥度张力设定随卷径递减：
- **码位带**：16#0004_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 张力控制使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `bRunning` | BOOL | 放卷运行 [—]（判据与修调的使能前提） |
| INPUT | `fTensionMeasN` | LREAL | 张力实测 [牛] |
| INPUT | `fDiamNowMm` | LREAL | 当前卷径 [毫米]，域外钳 [D芯, D满] 照算 |
| INPUT | `fDiamFullMm` | LREAL := 300.0 | 满卷直径 [毫米]，须 > 卷芯 |
| INPUT | `fDiamCoreMm` | LREAL := 50.0 | 卷芯直径 [毫米]，须 >= 0 且 < 满卷 |
| INPUT | `fTensionFullN` | LREAL := 20.0 | 卷芯处张力设定 [牛]，须 > 0 |
| INPUT | `fTaperPct` | LREAL := 20.0 | 锥度百分比 [百分数]，域 [0, 100]，0 = 恒张力 |
| INPUT | `fTensionBreakN` | LREAL := 2.0 | 断带阈 [牛]，运行中低于此判断带 |
| INPUT | `fTensionOverN` | LREAL := 60.0 | 超限阈 [牛]，运行中高于此判过张力 |
| INPUT | `fTrimGainPctPerN` | LREAL := 2.0 | 修调增益 [百分数每牛] |
| INPUT | `fLateralPosMm` | LREAL | 横动位置 [毫米] |
| INPUT | `fLateralLimitMm` | LREAL := 30.0 | 横动行程限 [毫米]，须 > 0 |
| INPUT | `tTripDebounce` | TIME  := T#500MS | 断带/超限去抖窗 [ms]，须 > 0 |
| OUTPUT | `fTensionSpN` | LREAL | 锥度后张力设定 [牛]（诊断出口） |
| OUTPUT | `fTrimPct` | LREAL | 张力修调输出 [百分数]，-100..100 |
| OUTPUT | `bLateralBlock` | BOOL | 横动封锁 [—]（行程限位电平） |
| OUTPUT | `eState` | E_DL_RibbonTenState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0004_01E7 起信息级、16#0004_0306 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FB_DL_TrackerSnowShedAngle（功能块 FB，）｜ v1.0.0

- **功能**：雪载卸荷顺控——采暖季窗有效（bHeatSeason 电平，由上层日历
- **码位带**：16#0004_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `bEnable` | BOOL | 卸荷控制使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清锁存 |
| INPUT | `bHeatSeason` | BOOL | 采暖季窗有效 [—]（上层日历窗电平） |
| INPUT | `fSnowLoadKgm2` | LREAL | 雪载实测/估测 [千克每平方米] |
| INPUT | `fTrackAngleDeg` | LREAL | 正常跟踪角 [度]（上层跟踪器透传） |
| INPUT | `fAngleFbDeg` | LREAL | 角度反馈 [度] |
| INPUT | `fSnowThreshKgm2` | LREAL := 5.0 | 卸荷雪载阈 [千克每平方米]，须 > 0 |
| INPUT | `fSnowHystKgm2` | LREAL := 1.0 | 退出回差 [千克每平方米]，须 >= 0 且 < 阈值 |
| INPUT | `fShedAngleDeg` | LREAL := 60.0 | 卸荷角 [度]，域 [0, 90] |
| INPUT | `fMaxSlewDegS` | LREAL := 2.0 | 限速 [度每秒]，须 > 0 |
| INPUT | `fCycleTimeS` | LREAL := 0.01 | 任务扫描周期 [秒]，须 > 0（R95 代理阈值） |
| INPUT | `tShedHoldMin` | TIME  := T#30S | 卸荷最短保持 [ms]，须 > 0 |
| INPUT | `fTrackTolDeg` | LREAL := 5.0 | 反馈跟踪容差 [度]，须 > 0 |
| INPUT | `tTrackTimeout` | TIME  := T#30S | 跟踪失败窗 [ms]，须 > 0 |
| OUTPUT | `fAngleCmdDeg` | LREAL | 角度命令 [度]（限速后，给驱动层） |
| OUTPUT | `bShedActive` | BOOL | 卸荷活动 [—]（卸荷/保持态电平） |
| OUTPUT | `eState` | E_DL_SnowShedState | 相位出口 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0004_01E9 起信息级、16#0004_0309 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |


## R27 新增接口表（3 件 · 2026-11-17）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_UnwinderDiameterCalc` | FB | IN `fFilmThick_um`/`fDiaInit_mm`/`fWebLen_m`/`fDiaMin_mm`/`bReset`；OUT `fDiaNow_mm`/`bSpoolEnd`/`eErr` | 卷径几何递推 sqrt(D0²−4tL/π)，开方委托 NthRoot(2)，根号内负值冻结不钳零 |
| `FB_DL_StringCutAlign` | FB | IN `fCamOffset_mm`/`fGainPct`/`fMaxCorr_mm`/`bCutCycle`/`bAxisInPos`/`tInPosMax`；OUT `fCorrCmd_mm`/`bCorrDone`/`eErr`/`eState` | 裁切对位四相，偏差经 LowPassFilter，等待相双出口（在位/超时中止） |
| `FB_DL_StepperZLiftMicron` | FB | IN `fUmPerStep`/`fTargetUm`/`fUpLimit_um`/`fLoLimit_um`/`fSpeedPps`/`bStartMove`/`bReset`；OUT `fPosNow_um`/`bMoving`/`bStepPulse`/`bLimitHit`/`eErr`/`eState` | 微米步进：目标先取整成步数并查溢出，软限位两道，运动中越限急停 |

## R30 新增接口表（Motion 3 件 · 2026-11-18）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_TrackerBacktrackCalc` | FB | IN `fSunElev_deg`/`fSunAzi_deg`〔天文角引脚注入，消费 FC_DL_SolarPositionCalc〕/`fRowPitch_m`〔0.5~20 m〕/`fCollectWidth_m`/`fMaxAngle_deg`〔±60〕；OUT `fTrackAngle_deg`/`bBacktrackActive`/`fShadeLimit_deg`/`eErr` | 逆跟踪角 = 阵列阴影几何推导，arctan 归一化防除零；太阳高度角 <0 归位停跟踪（安全侧 0°）；非有限输入保持上次有效角；码位 0354~0358 |
| `FB_DL_LamStepperFeed` | FB | IN `bStepperReady`/`bStepperDone`/`bStepperFault`/`bFeedStart`/`fFilmLen_m`/`fStepLen_m`/`fChangeReserve_m`/`fFedLen_m`/`bMaintWin`/`tFeedTimeout`；OUT `bFeedCmd`/`bFeedDone`/`fRemainLen_m`/`bMaintHold`/`eErr` | 开环步进契约引脚注入（不自造轴状态枚举）；保养窗激活冻结送料（安全侧不启动）；堵转耗时 ×1.5 判据；码位 0359~035D |
| `FB_DL_ElectrodeRollDiameter` | FB | IN `fLineSpd_mmin`/`fRollRpm`/`fPrevDia_mm`/`fCoreDia_mm`/`fThick_um`/`fWarnDia_mm`；OUT `fDia_mm`/`bChangeWarn`/`bAtCore`/`eErr` | D=v·i/(π·n) 防除零递推；低速门限下冻结递推；卷径下限钳芯径；向量含「恰好等于预警径」「预警径 −0.01 mm」两点；码位 035E~0362 |
