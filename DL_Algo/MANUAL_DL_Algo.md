# MANUAL — DL_Algo 工业控制算法子库使用手册

> **Sublibrary**：`DL_Algo` ｜ **Version**：v1.6.0 ｜ **Level**：1（仅依赖 Level 0）｜ **Components**：27（FB 21 ｜ FC 6；R5 补强 1 项 + R6 补充 1 项 + R8 峰值/步进 2 项 + R10 信号发生族 4 项 + R11 R2R 批级微调 1 项 + R12 阀特性/水焓 2 项）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert
> **Depends**：仅 `Standard.library`（`R_TRIG` / `LIMIT` / `MIN` / `MAX` / `ABS` / `LN` / `EXP` / `TAN` / `SQRT` / `TIME_TO_REAL`）；不引用任何其他 `DL_` 子库；子库内部 `FB_DL_CascadePid` / `FB_DL_SmithPredictor` 引用 `FB_DL_PidController`。
> 配套版本记录见 `DL_Algo/VERSION.md`；全库导航见 `C:\Library\README.md`。**引脚级细节以 `.st` 源码声明区为准**，本手册接口表逐字取自源码。

---

## 0. 使用前必读 / Before You Start

1. **每周期无条件调用**：全部 `FB_` 组件必须在主任务每个扫描周期调用一次；使能、模式只通过 `bEnable` / `bManual` 等输入引脚表达，严禁把实例调用塞进 `IF`（丢沿、状态机冻结）。
2. **`tSampleTime` 必须显式给定**：所有递推（PID、滤波、积分、轨迹、PWM）都以输入引脚 `tSampleTime` 为节拍口径，严禁依赖隐式扫描周期；小于 `T#10MS` 一律钳位为 10ms 并置 `16#0002_0002`，不中断扫描。组件必须放在**固定周期任务**中，变频任务会让所有时间常数失真。
3. **参数防御口径统一**：量程 / 限幅参数 Min > Max 自动对调修复并置码；速率 / 时间常数负值或非法值钳位为规格合法值并置码；输入 NaN 或幅值超 `1.0E30` 当拍拒绝更新、保持上一拍输出并置 `16#0002_0004`。**置码不等于停机**，停机决策权留给调用方。
4. **故障码口径**：本子库统一使用 `16#0002_xxxx` 段并按组件细分（01xx PID / 02xx 串级 / 03xx 分程 / 04xx 前馈 / 05xx 史密斯 / 06xx 斜坡 / 07xx S 曲线 / 08xx PWM / 10xx 低通 / 11xx 二阶 / 12xx 高通 / 14xx 微分 / 15xx 露点 / 16xx 流量 / 17xx 湿空气焓值 / **18xx Ramp/Soak 程序曲线族——R6 终审裁定归位的独立族段**）；公共码：`0001` 参数越界已钳位、`0002` 采样周期已钳位、`0004` 输入非有限值已拒绝、`0005` 非法状态兜底。无故障基准码存在两种口径：多数组件每拍重算为 `16#0002_0000`，斜坡 / S 曲线 / PWM / 积分 / 微分五组件为 `16#0000_0000`，各节接口表已按源码标注。信息级码（饱和、钳位提示）不置 `bError`，防下游报警误动作。
5. **跟踪/无扰投切通用语义**：`bTrack = TRUE` 时输出当拍立即跟随 `fTrackValue`，内部积分/历史同步反算，回自动零扰动；该引脚专用于手自动切换、仿真回投与初始化对齐，禁止当常态限幅用。
6. **输出量纲**：控制类组件（PID / 串级 / 分程 / PWM / 前馈 / 史密斯）输出统一为 `[%]`；信号类组件（斜坡 / S 曲线 / 滤波 / 积分 / 微分 / 限速）输出量纲与输入同为 `[EU]`。混接前先对量纲。

---

## 1. FB_DL_PidController ｜ 单回路通用 PID 控制器 / Single-Loop PID Controller

**功能**：单回路通用离散 PID。位置式与增量式由 `bIncremental` 独立选择；含控制死区、积分分离（触限停积分）、两级抗积分饱和（条件积分 + 限幅反算回填）、手自动无扰切换与跟踪回投；`fKp` 为负即反作用（沿 OSCAT / 西门子惯例）。现场用途：温度 / 压力 / 流量单闭环调节主块。
**Function**: General-purpose discrete PID with positional and incremental forms, deadband, conditional integration, two-stage anti-windup (back-calculation), bumpless manual/auto transfer and track input. Negative `fKp` means reverse acting.

### 1.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时输出回输出下限 / Master enable, FALSE drives output to low limit |
| `bManual` | `BOOL` | IN | `FALSE` | — | 手动模式选择，TRUE = 手动输出 / Manual mode select, TRUE = manual output |
| `fManualValue` | `REAL` | IN | `0.0` | % | 手动输出值，越限自动钳位 / Manual output value, auto-clamped |
| `fSetpoint` | `REAL` | IN | `0.0` | EU | 设定值 / Setpoint in engineering units |
| `fActual` | `REAL` | IN | `0.0` | EU | 过程实际值 / Process actual value |
| `fKp` | `REAL` | IN | `1.0` | 1 | 比例增益，负值 = 反作用 / Proportional gain, negative = reverse acting |
| `tTi` | `TIME` | IN | `T#2S` | s | 积分时间，T#0S 表示纯 PD 无积分 / Integral time, T#0S = pure PD |
| `tTd` | `TIME` | IN | `T#0S` | s | 微分时间，T#0S 关闭微分（对偏差做 1/10 tTd 一阶预滤波）/ Derivative time, disabled at T#0S |
| `fDeadband` | `REAL` | IN | `0.0` | EU | 控制死区，负值自动钳 0 / Control deadband, negative clamped to 0 |
| `bIncremental` | `BOOL` | IN | `FALSE` | — | TRUE = 增量式算法，FALSE = 位置式 / TRUE = incremental form |
| `rOutMin` | `REAL` | IN | `0.0` | % | 输出下限 / Output lower limit |
| `rOutMax` | `REAL` | IN | `100.0` | % | 输出上限 / Output upper limit |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 T#10MS 钳位 / Sample period, clamped to 10 ms minimum |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | % | 跟踪值，用于无扰投切 / Track value for bumpless transfer |
| `bReset` | `BOOL` | IN | `FALSE` | — | 复位信号，上升沿清积分与故障 / Reset, rising edge clears integral and fault |
| `fOut` | `REAL` | OUT | — | % | 控制输出 / Control output |
| `fErr` | `REAL` | OUT | — | EU | 偏差 = 设定 - 实际 / Error = setpoint minus actual |
| `fIntPart` | `REAL` | OUT | — | % | 积分分量，诊断用 / Integral component, diagnostics |
| `bLimitHigh` | `BOOL` | OUT | — | — | 输出触上限标志 / Output saturated at upper limit |
| `bLimitLow` | `BOOL` | OUT | — | — | 输出触下限标志 / Output saturated at lower limit |
| `bActive` | `BOOL` | OUT | — | — | 自动调节进行中标志 / Auto regulation active |
| `bError` | `BOOL` | OUT | — | — | 故障标志（信息级码不置位）/ Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` 参数越界已钳位、`0002` 采样周期钳位、`0004` 非有限值拒绝、`0005` 非法状态、`0101` 输出饱和（信息级）、`0102` 手动值钳位（信息级）/ Error code base `16#0002_0000` |

配套枚举：`E_DL_PidState`（`eIdle` / `eAuto` / `eManual` / `eFault`）。

### 1.2 调用示例 / Example

```iecst
PROGRAM PRG_TempLoop
VAR
    fbPid      : FB_DL_PidController;   // 温度回路 PID 实例 / Temperature loop PID instance
    fTempSp    : REAL := 80.0;          // 温度设定 [degC] / Temperature setpoint [degC]
    fTempPv    : REAL;                  // 滤波后温度 [degC] / Filtered temperature [degC]
    fDutyCmd   : REAL;                  // 加热占空比指令 [%] / Heating duty command [%]
END_VAR

(* 每周期无条件调用；反作用：温度高于设定时关小加热，故 fKp 取负 *)
fbPid(
    bEnable     := bLineRunning,
    fSetpoint   := fTempSp,
    fActual     := fTempPv,
    fKp         := -2.0,             // 反作用 [1] / Reverse acting
    tTi         := T#30S,            // 温度回路积分时间 / Integral time
    tTd         := T#5S,             // 温度回路微分时间 / Derivative time
    rOutMin     := 0.0,
    rOutMax     := 100.0,
    tSampleTime := T#100MS );
fDutyCmd := fbPid.fOut;
```

### 1.3 现场注意事项 / Field Notes

- **采样周期与 tTi 保持比例概念**：增量式积分增量 `fKp·fErr·fDt/Ti` 依赖 `tSampleTime` 准确；任务实际周期与设定不符时积分速度同比失真——改任务周期必须同步改 `tSampleTime`。经验整定顺序：先 P 后 I 再 D，`tTi` 取振荡周期 1/2~1/5 起步。
- **投切时机**：手自动切换与跟踪回投期间内部已做积分反算同步，无需外部干预；但**首次投自动前**建议先让 PV 经 `FB_DL_LowPassFilter` 稳定，避免首拍偏差尖峰直接打满输出。

---

## 2. FB_DL_CascadePid ｜ 主副串级 PID 控制器 / Cascade PID Controller

**功能**：主副双回路串级。主回路 PID 输出经副设定域限幅后作为副回路设定值，副回路输出驱动执行器；内部组合两个 `FB_DL_PidController` 实例（本块不自写 PID 律），采样周期与输出限幅统一由本块注入。手动时副回路直接手动输出，主回路经跟踪回投跟随副设定，回自动零跳变。适用温控（主温度 / 副加热功率）、张力（主张力 / 副速度）等场景。
**Function**: Master-slave cascade PID composing two `FB_DL_PidController` instances; the master output is clamped into the slave setpoint domain. Unified sample period and limit injection; bumpless manual transfer via master tracking.

### 2.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时输出回下限 / Master enable |
| `bManual` | `BOOL` | IN | `FALSE` | — | 手动模式，TRUE 时副环手动 / Manual mode, TRUE puts slave loop in manual |
| `fManualSlaveValue` | `REAL` | IN | `0.0` | % | 副回路手动输出 / Slave loop manual output |
| `fSpMaster` | `REAL` | IN | `0.0` | EU | 主回路设定值 / Master loop setpoint |
| `fPvMaster` | `REAL` | IN | `0.0` | EU | 主回路过程值 / Master loop process value |
| `fPvSlave` | `REAL` | IN | `0.0` | EU | 副回路过程值 / Slave loop process value |
| `fKpM` | `REAL` | IN | `1.0` | 1 | 主回路比例增益 / Master proportional gain |
| `tTiM` | `TIME` | IN | `T#5S` | s | 主回路积分时间 / Master integral time |
| `tTdM` | `TIME` | IN | `T#0S` | s | 主回路微分时间 / Master derivative time |
| `fKpS` | `REAL` | IN | `2.0` | 1 | 副回路比例增益，默认更硬 / Slave gain, harder by default |
| `tTiS` | `TIME` | IN | `T#1S` | s | 副回路积分时间 / Slave integral time |
| `tTdS` | `TIME` | IN | `T#0S` | s | 副回路微分时间 / Slave derivative time |
| `rSpSlaveMin` | `REAL` | IN | `0.0` | EU | 副设定域下限，超限自动对调 / Slave setpoint domain low limit |
| `rSpSlaveMax` | `REAL` | IN | `100.0` | EU | 副设定域上限 / Slave setpoint domain high limit |
| `rOutMin` | `REAL` | IN | `0.0` | % | 副环输出下限 / Slave output lower limit |
| `rOutMax` | `REAL` | IN | `100.0` | % | 副环输出上限 / Slave output upper limit |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，统一注入两个子块 / Sample period injected to both sub-blocks |
| `bReset` | `BOOL` | IN | `FALSE` | — | 复位信号，电平透传两个子块 / Reset passed through |
| `fOut` | `REAL` | OUT | — | % | 副回路控制输出 / Slave loop control output |
| `fSpSlave` | `REAL` | OUT | — | EU | 副回路设定值，诊断 / Slave setpoint, diagnostics |
| `fErrMaster` | `REAL` | OUT | — | EU | 主回路偏差，诊断 / Master loop error, diagnostics |
| `bLimitHigh` | `BOOL` | OUT | — | — | 副环输出触上限 / Slave output at upper limit |
| `bLimitLow` | `BOOL` | OUT | — | — | 副环输出触下限 / Slave output at lower limit |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` / `0002` / `0004` / `0005` 公共码，`0201` 副设定超域已钳位（信息级）/ Error code base `16#0002_0000` |

配套枚举：`E_DL_CascadeState`（`eIdle` / `eCascade` / `eManual` / `eFault`）。

### 2.2 调用示例 / Example

```iecst
PROGRAM PRG_OvenCascade
VAR
    fbCas     : FB_DL_CascadePid;      // 烘箱串级实例 / Oven cascade instance
    fZoneSp   : REAL := 120.0;         // 主环：炉温设定 [degC] / Master: oven temperature SP
    fZonePv   : REAL;                  // 主环：炉温实测 [degC] / Master: measured oven temperature
    fJacketPv : REAL;                  // 副环：夹套温度 [degC] / Slave: jacket temperature
END_VAR

(* 每周期无条件调用 *)
fbCas(
    bEnable     := bOvenOn,
    fSpMaster   := fZoneSp,
    fPvMaster   := fZonePv,
    fPvSlave    := fJacketPv,
    fKpM        := -1.5,  tTiM := T#60S, tTdM := T#0S,   // 主环慢 / Slow master
    fKpS        := -4.0,  tTiS := T#8S,  tTdS := T#0S,   // 副环硬 / Fast slave
    rSpSlaveMin := 20.0,  rSpSlaveMax := 150.0,          // 副设定域 / Slave SP domain
    tSampleTime := T#100MS );
// 执行器指令 = fbCas.fOut（[%]），副设定诊断 = fbCas.fSpSlave
```

### 2.3 现场注意事项 / Field Notes

- **副环必须显著快于主环**（本块默认 `fKpS=2.0`、`tTiS=T#1S` 更硬）：副环振荡周期应为主环的 1/3~1/5，否则串级退化为两个互相拖累的单环。
- **主环输出域 = 副设定域**由本块内部统一钳位，调用方不要再对 `fSpSlave` 二次限幅；投运时先整定副环（主环置手动、副环单回路运行），再投入串级。

---

## 3. FB_DL_SplitRangeControl ｜ 分程输出分配 / Split-Range Output Allocator

**功能**：把单一控制器输出（-100..100%）分配为两路执行器信号：正半区驱动加热通道、负半区驱动冷却通道，中央死区间隙防双阀同开；两路输出各自按独立量程二次映射，支持加热通道反相。现场用途：温控冷热双执行器、蒸汽 / 冷水阀对。
**Function**: Splits a single -100..100% controller output into heating and cooling actuator channels with a central deadband to prevent simultaneous opening; each channel is remapped to its own range, with an invert option for the heating channel.

### 3.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时两路回量程下限 / Master enable |
| `fCtrlIn` | `REAL` | IN | `0.0` | % | 控制器输入，-100..100 / Controller input, -100..100 |
| `fGap` | `REAL` | IN | `2.0` | % | 中央死区，负值钳 0 / Central deadband, negative clamped |
| `rCtrlMax` | `REAL` | IN | `100.0` | % | 输入满量程幅值，须大于 0 / Input full-scale magnitude |
| `rOutHeatMin` | `REAL` | IN | `0.0` | % | 加热通道输出下限 / Heating channel output low limit |
| `rOutHeatMax` | `REAL` | IN | `100.0` | % | 加热通道输出上限 / Heating channel output high limit |
| `rOutCoolMin` | `REAL` | IN | `0.0` | % | 冷却通道输出下限 / Cooling channel output low limit |
| `rOutCoolMax` | `REAL` | IN | `100.0` | % | 冷却通道输出上限 / Cooling channel output high limit |
| `bInvertHeat` | `BOOL` | IN | `FALSE` | — | 加热通道反相输出 100-x / Invert heating channel output |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，仅保持一致性 / Sample period, consistency only |
| `fOutHeat` | `REAL` | OUT | — | % | 加热通道输出 / Heating channel output |
| `fOutCool` | `REAL` | OUT | — | % | 冷却通道输出 / Cooling channel output |
| `bHeatActive` | `BOOL` | OUT | — | — | 加热通道激活标志 / Heating channel active |
| `bCoolActive` | `BOOL` | OUT | — | — | 冷却通道激活标志 / Cooling channel active |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` 参数越界已钳位、`0002` 采样周期钳位、`0004` 非有限值拒绝、`0005` 非法状态、`0301` 满量程幅值非法已钳位 / Error code base `16#0002_0000` |

配套枚举：`E_DL_SplitState`（`eIdle` / `eHeatZone` / `eDeadband` / `eCoolZone` / `eFault`）。

### 3.2 调用示例 / Example

```iecst
PROGRAM PRG_SplitTemp
VAR
    fbSplit  : FB_DL_SplitRangeControl; // 分程分配实例 / Split-range instance
    fPidOut  : REAL;                    // 前级控制器输出 -100..100 [%] / Upstream controller output
END_VAR

fbSplit(
    bEnable     := bTempLoopOn,
    fCtrlIn     := fPidOut,            // 直接接 PID 输出 / Direct from PID output
    fGap        := 2.0,                // 中央死区防双阀同开 [%] / Central gap in percent
    rOutHeatMin := 20.0,               // 加热阀起闭 20% 以上 [%] / Heat valve starts at 20%
    bInvertHeat := FALSE );
// 阀指令：fHeatValve := fbSplit.fOutHeat;  fCoolValve := fbSplit.fOutCool;
```

### 3.3 现场注意事项 / Field Notes

- **中央死区是双阀保护**：`fGap` 不宜为 0——热/冷阀特性死区不一致时，0 死区会在零点附近双阀微开互相抵消，能耗翻倍且控温品质下降；推荐 `fGap` 取阀灵敏度的 1~2 倍。
- 前级控制器的 `rOutMin/rOutMax` 应配置为 `-100..100`（如 `FB_DL_PidController` 双侧对称输出），否则负半区永不生效、冷却通道全程关断。

---

## 4. FB_DL_FeedforwardComp ｜ 前馈补偿器 / Feedforward Compensator

**功能**：静态 + 动态前馈补偿。对可测扰动量做前馈：静态增益项即时响应 + 一阶惯性 / 超前滞后动态整形 + 可选纯滞后（固定 10 槽延时队列），输出叠加到 PID 反馈通道，提升抗负载扰动速度。现场用途：配料设定突变、蒸汽压力波动的前馈补偿。
**Function**: Static and dynamic feedforward compensation of a measurable disturbance: static gain, first-order lead/lag shaping and an optional 10-slot dead-time queue; the output is summed into the PID feedback path for faster disturbance rejection.

### 4.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时输出回下限 / Master enable |
| `fDisturbance` | `REAL` | IN | `0.0` | EU | 扰动量，可测负载信号 / Measured disturbance |
| `fFfGain` | `REAL` | IN | `1.0` | 1 | 前馈增益 / Feedforward gain |
| `tLeadTime` | `TIME` | IN | `T#0S` | s | 超前时间，T#0S = 纯静态 / Lead time, T#0S = static only |
| `tLagTime` | `TIME` | IN | `T#0S` | s | 惯性时间，T#0S = 直通（合法口径）/ Lag time, T#0S = pass-through |
| `tDelayTime` | `TIME` | IN | `T#0S` | s | 纯滞后时间，T#0S = 无滞后队列 / Dead time, T#0S = no queue |
| `rOutMin` | `REAL` | IN | `-100.0` | % | 输出下限 / Output lower limit |
| `rOutMax` | `REAL` | IN | `100.0` | % | 输出上限 / Output upper limit |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 T#10MS 钳位 / Sample period |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能 / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | % | 跟踪值，用于无扰投切 / Track value |
| `fFfOut` | `REAL` | OUT | — | % | 前馈输出 / Feedforward output |
| `fStaticPart` | `REAL` | OUT | — | % | 静态分量，诊断 / Static component, diagnostics |
| `fDynPart` | `REAL` | OUT | — | % | 动态分量，诊断 / Dynamic component, diagnostics |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；公共码 `0001` / `0002` / `0004`，`0402` 滞后队列深度超上限已截断 / Error code base `16#0002_0000` |

配套枚举：`E_DL_FfState`（`eIdle` / `eStatic` / `eDynamic` / `eFault`）。

### 4.2 调用示例 / Example

```iecst
PROGRAM PRG_Feedforward
VAR
    fbFf    : FB_DL_FeedforwardComp;    // 前馈补偿实例 / Feedforward instance
    fbPid   : FB_DL_PidController;      // 反馈 PID 实例 / Feedback PID instance
    fLoadKg : REAL;                     // 可测下料量扰动 [kg/h] / Measured load disturbance
END_VAR

fbFf(
    bEnable     := bLoopOn,
    fDisturbance:= fLoadKg,
    fFfGain     := 0.8,                // 前馈增益 [1]，先静后动整定 / Start static, then shape
    tLeadTime   := T#1S,  tLagTime := T#3S,   // 超前滞后整形 / Lead-lag shaping
    tDelayTime  := T#500MS,            // 纯滞后（≤ 10 × 100ms = 1s）/ Dead time ≤ 1 s
    rOutMin     := -100.0, rOutMax := 100.0,
    tSampleTime := T#100MS );

(* 每周期无条件调用；前馈与反馈叠加 *)
fbPid(bEnable := bLoopOn, fSetpoint := fSp, fActual := fPv,
      fKp := 1.0, tTi := T#10S, tSampleTime := T#100MS);
fActuatorCmd := fbPid.fOut + fbFf.fFfOut;   // 执行器合成指令 [%] / Combined command
```

### 4.3 现场注意事项 / Field Notes

- **整定顺序「先静后动」**：先把 `tLeadTime/tLagTime/tDelayTime` 全置 0、调 `fFfGain` 使扰动阶跃后 PV 初期几乎不动，再逐步加入动态整形；前馈永远不承担稳态精度——那是反馈的职责。
- **纯滞后上限硬约束**：队列固定 10 槽，`tDelayTime` 折算深度超 10 拍即截断并置 `16#0002_0402`；滞后补偿量须满足 `tDelayTime ≤ 10 × tSampleTime`，超限时减小滞后设定或降低采样周期。

---

## 5. FB_DL_SmithPredictor ｜ 史密斯预估器 / Smith Dead-Time Predictor

**功能**：大滞后对象专用史密斯预估器。内部按一阶 + 纯滞后模型（20 槽滞后队列）实时仿真"若无滞后过程会如何响应"，用补偿后误差驱动内嵌 `FB_DL_PidController`，等效消除纯滞后对环路稳定性的破坏；模型静态偏差经小增益（`DL_SMITH_KB = 0.02 [1/s]`）在线自适应校正。上电后队列填充期自动退化为普通 PID（学习态），不阻塞控制。现场用途：长管道加热、烘箱等大纯滞后温控回路。
**Function**: Smith predictor for large dead-time processes: a first-order-plus-dead-time model (20-slot queue) simulates the delay-free response; the compensated error drives an embedded PID. Model static bias is adapted online; during queue fill-up the block gracefully degrades to plain PID.

### 5.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时输出回下限 / Master enable |
| `bManual` | `BOOL` | IN | `FALSE` | — | 手动模式，TRUE 时输出手动值（模型继续仿真）/ Manual mode, model keeps simulating |
| `fManualValue` | `REAL` | IN | `0.0` | % | 手动输出值，越限自动钳位 / Manual output value |
| `fSetpoint` | `REAL` | IN | `0.0` | EU | 设定值 / Setpoint |
| `fPv` | `REAL` | IN | `0.0` | EU | 过程值 / Process value |
| `fKp` | `REAL` | IN | `1.0` | 1 | 内嵌 PID 比例增益 / Embedded PID proportional gain |
| `tTi` | `TIME` | IN | `T#2S` | s | 内嵌 PID 积分时间 / Embedded PID integral time |
| `tTd` | `TIME` | IN | `T#0S` | s | 内嵌 PID 微分时间 / Embedded PID derivative time |
| `fModelK` | `REAL` | IN | `1.0` | EU/EU | 对象模型增益，0 视为非法置码 / Plant model gain |
| `tModelT` | `TIME` | IN | `T#5S` | s | 模型惯性时间 / Model time constant |
| `tModelLag` | `TIME` | IN | `T#1S` | s | 模型纯滞后，超队列上限截断置码 / Model dead time |
| `rOutMin` | `REAL` | IN | `0.0` | % | 输出下限 / Output lower limit |
| `rOutMax` | `REAL` | IN | `100.0` | % | 输出上限 / Output upper limit |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 T#10MS 钳位 / Sample period |
| `bReset` | `BOOL` | IN | `FALSE` | — | 复位信号，上升沿重置模型与队列 / Reset, rising edge resets model |
| `fCtrlOut` | `REAL` | OUT | — | % | 控制器输出 / Controller output |
| `fModelOut` | `REAL` | OUT | — | EU | 模型无滞后输出，诊断 / Model no-delay output, diagnostics |
| `fErrComp` | `REAL` | OUT | — | EU | 补偿后偏差，诊断 / Compensated error, diagnostics |
| `fModelBias` | `REAL` | OUT | — | EU | 模型自适应偏差 / Model adaptive bias |
| `bError` | `BOOL` | OUT | — | — | 故障标志（信息级 `0502` 不置位）/ Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；公共码 `0001` / `0002` / `0004` / `0005`，`0501` 模型增益非法、`0502` 模型滞后超队列上限已截断（信息级）/ Error code base `16#0002_0000` |

配套枚举：`E_DL_SmithState`（`eIdle` / `eLearning` / `eCompensating` / `eManual` / `eFault`）。

### 5.2 调用示例 / Example

```iecst
PROGRAM PRG_LongPipeHeater
VAR
    fbSmith : FB_DL_SmithPredictor;     // 长滞后温控实例 / Long dead-time heater instance
    fSpDeg  : REAL := 180.0;            // 出口温度设定 [degC] / Outlet temperature SP
    fPvDeg  : REAL;                     // 出口温度实测 [degC] / Measured outlet temperature
END_VAR

fbSmith(
    bEnable     := bSteamOn,
    fSetpoint   := fSpDeg,
    fPv         := fPvDeg,
    fKp         := -1.2,   tTi := T#40S,           // 内嵌 PID / Embedded PID
    fModelK     := -1.2,   tModelT := T#25S,       // 模型增益/惯性先按开环阶跃拟合 / Fit model from step test
    tModelLag   := T#8S,                            // 管道传输纯滞后 [s] / Transport dead time
    tSampleTime := T#100MS );
fValveCmd := fbSmith.fCtrlOut;                   // 蒸汽阀指令 [%] / Steam valve command
```

### 5.3 现场注意事项 / Field Notes

- **模型参数来自开环阶跃试验**：`fModelK / tModelT / tModelLag` 按阶跃响应的增益、时间常数、纯滞后拟合；模型失配只降低补偿效果，不会像开环一样发散（内嵌 PID 仍闭环兜底），但失配大于 30% 时建议重新做阶跃试验。
- **滞后约束**：`tModelLag` 折算深度超 20 拍截断并置 `16#0002_0502`（信息级，不置 `bError`）；队列填充期（上电后 `tModelLag/tSampleTime` 拍内）状态为 `eLearning`，控制器按原始误差运行，属预期行为而非故障。

---

## 6. FB_DL_RateLimiter ｜ 变化率限制器 / Slew-Rate Limiter

**功能**：变化率限制器。输入阶跃时输出以最大速率跟随，保护加热元件 / 执行器免受给定值阶跃冲击；上升与下降速率独立可调，速率为 0 表示该方向不限速直通（沿测量库惯例），负值非法按 0 处理并置码；支持跟踪回投与限速进行中标志。
**Function**: Slew-rate limiter: on input steps the output follows at the configured rate; rise and fall rates are independent, a rate of 0 means unlimited in that direction, negatives are treated as 0 with a code. Track input and a limiting flag are provided.

### 6.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 总使能，FALSE 时输出直通输入 / Master enable, FALSE passes through |
| `fIn` | `REAL` | IN | `0.0` | EU | 输入信号 / Input signal |
| `fRateUp` | `REAL` | IN | `0.0` | EU/s | 最大上升速率，0 = 不限 / Max rising rate, 0 = unlimited |
| `fRateDown` | `REAL` | IN | `0.0` | EU/s | 最大下降速率，0 = 不限 / Max falling rate, 0 = unlimited |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能 / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪值，用于无扰投切 / Track value |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 T#10MS 钳位 / Sample period |
| `fOut` | `REAL` | OUT | — | EU | 限速后输出 / Rate-limited output |
| `bLimiting` | `BOOL` | OUT | — | — | 限速进行中标志 / Rate limiting in progress |
| `fRateActual` | `REAL` | OUT | — | EU/s | 本拍实际变化率，HMI 趋势用 / Actual rate this cycle |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；公共码 `0001`（负速率已按 0 处理）/ `0002` / `0004` / `0005` / Error code base `16#0002_0000` |

配套枚举：`E_DL_RateState`（`eIdle` / `eFollow` / `eLimitUp` / `eLimitDown` / `eFault`）。

### 6.2 调用示例 / Example

```iecst
PROGRAM PRG_SoftStart
VAR
    fbRate : FB_DL_RateLimiter;         // 给定值软化实例 / Setpoint softener instance
    fOpSp  : REAL;                      // 操作员设定 [degC] / Operator setpoint
END_VAR

fbRate(
    bEnable     := TRUE,
    fIn         := fOpSp,
    fRateUp     := 5.0,                // 升温 5 degC/s 封顶 [%]/[EU/s] / Limit rise rate
    fRateDown   := 10.0,               // 降温可更快，保护工艺 / Faster cooling allowed
    tSampleTime := T#100MS );
fPidSp := fbRate.fOut;                 // 送 PID 的实际设定值 / Softened setpoint to PID
```

### 6.3 现场注意事项 / Field Notes

- **0 与负值语义完全不同**：`0 = 不限速直通`（合法），负值按 0 处理并置 `16#0002_0001`；想要"禁止变化"请改用 `FB_DL_RampGenerator`（其速率 ≤ 0 为冻结语义）。
- 限速中（`bLimiting = TRUE`）输出滞后于输入属正常现象；串级场合把本块放在**主环设定值通道**上，不要串在 PV 通道（会给控制器引入伪惯性）。

---

## 7. FB_DL_RampGenerator ｜ 线性斜坡发生器 / Linear Ramp Generator

**功能**：线性设定值斜坡发生器。把阶跃目标值变为按独立上升/下降速率（EU/s）平滑逼近的斜坡输出，防止操作员大阶跃直接冲击执行器。支持暂停保持（`bHold` 冻结当前值）与跟踪回投。斜率为 0 表示该方向**冻结**（保持输出，绝不直通，防误操作）；到达判定以限幅后的实际输出为准，防止目标超量程时死等。
**Function**: Linear setpoint ramp: step targets are approached at independent EU/s rates with hold and track modes. A rate of 0 freezes that direction (never passes through); arrival is judged on the clamped output so an out-of-range target cannot stall the ramp.

### 7.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 时斜坡停止并保持输出 / Enable, FALSE stops ramp and holds |
| `fTarget` | `REAL` | IN | `0.0` | EU | 目标值，可为任意有限值 / Target value, any finite value |
| `fRateUp` | `REAL` | IN | `10.0` | EU/s | 上升速率，≤0 视为非法冻结并置码 / Up rate, ≤0 illegal and frozen |
| `fRateDown` | `REAL` | IN | `10.0` | EU/s | 下降速率，≤0 视为非法冻结并置码 / Down rate, ≤0 illegal and frozen |
| `bHold` | `BOOL` | IN | `FALSE` | — | 暂停保持请求，TRUE 冻结在当前值 / Hold request |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，输出立即跟随 fTrackValue / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪值，投切无扰动基准 / Track value |
| `rOutMin` | `REAL` | IN | `-1.0E10` | EU | 输出下限，大于上限时自动对调 / Output lower limit |
| `rOutMax` | `REAL` | IN | `1.0E10` | EU | 输出上限 / Output upper limit |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sample time |
| `fOut` | `REAL` | OUT | — | EU | 斜坡输出 / Ramp output |
| `bDone` | `BOOL` | OUT | — | — | 到达目标标志（偏差在容差内）/ Done flag |
| `bMoving` | `BOOL` | OUT | — | — | 斜坡进行中标志 / Ramp in progress |
| `fRemain` | `REAL` | OUT | — | EU | 距目标剩余量 = fTarget - fOut / Remaining amount to target |
| `bError` | `BOOL` | OUT | — | — | 故障标志（瞬时，逐拍重算）/ Fault flag, transient |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0000_0000`；`0001` 量程对调、`0002` 采样周期钳位、`0004` 目标非有限值拒绝、`0601` 速率非法已冻结 / Error code base `16#0000_0000` |

配套枚举：`E_DL_RampState`（`eIdle` / `eHold` / `eRampUp` / `eRampDown` / `eDone` / `eFault`）。

### 7.2 调用示例 / Example

```iecst
PROGRAM PRG_PressRamp
VAR
    fbRamp  : FB_DL_RampGenerator;      // 压力斜坡实例 / Pressure ramp instance
    fPressSp: REAL := 6.0;              // 目标压力 [MPa] / Target pressure
    bRampGo : BOOL;                     // 启动斜坡命令 / Ramp start command
END_VAR

fbRamp(
    bEnable     := bRampGo,
    fTarget     := fPressSp,
    fRateUp     := 0.5,                // 升压 0.5 MPa/s（工艺限值）/ Pressure ramp limit
    fRateDown   := 2.0,                // 泄压更快 / Faster venting
    tSampleTime := T#100MS );
fPidSetpoint := fbRamp.fOut;           // 斜坡后设定值送 PID / Ramped SP to PID
IF fbRamp.bDone THEN (* 到达目标，转入保压逻辑 / Switch to holding logic *) END_IF
```

### 7.3 现场注意事项 / Field Notes

- **速率 ≤ 0 是冻结不是直通**（与 `FB_DL_RateLimiter` 的 0 = 不限相反，两块语义刻意不同并都在头注释披露）：配置错误时现象是"输出原地不动"而非"飞车"，优先查 `uErrorId = 16#0002_0601`。
- 到达判定基于限幅后的实际输出：目标超量程不会死等，输出停在量程端点即置 `bDone`；投切（手/自动、配方切换）用 `bTrack + fTrackValue` 一拍对齐，避免斜坡从旧值重爬。

---

## 8. FB_DL_SCurveGenerator ｜ 七段式 S 型轨迹发生器 / Seven-Phase S-Curve Trajectory Generator

**功能**：七段式 S 型点到点轨迹规划器：加加速-匀加速-减加速-匀速-减减速-匀减速-减减速，jerk→加速度→速度→位移四级积分链真实推进，消除柔性冲击。采用自适应减速行程估算（裕量 1.05），三约束（速度/加速度/Jerk）逐拍限幅；`bAbort` 任意运行态立即按最大减速停车（安全优先）。现场用途：伺服点位给定前级、升降机构、注液泵平滑启停。
**Function**: Seven-phase jerk-limited point-to-point trajectory with a true jerk→acc→vel→pos integration chain and adaptive braking-distance estimation; `bAbort` commands an immediate maximum-deceleration stop from any running phase.

### 8.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 运动量全清零 / Enable, FALSE clears all motion |
| `fTarget` | `REAL` | IN | `0.0` | EU | 目标位置，非有限值拒绝 / Target position, non-finite rejected |
| `fMaxVel` | `REAL` | IN | `100.0` | EU/s | 最大速度，≤0 钳位 1.0 / Max velocity |
| `fMaxAcc` | `REAL` | IN | `200.0` | EU/s² | 最大加速度，≤0 钳位 fMaxVelEff/fDt / Max acceleration |
| `fMaxJerk` | `REAL` | IN | `1000.0` | EU/s³ | 最大加加速度，≤0 钳位 fMaxAccEff/fDt / Max jerk |
| `bAbort` | `BOOL` | IN | `FALSE` | — | 急停请求，TRUE 立即按最大减速停车 / Abort request, immediate max decel |
| `tSampleTime` | `TIME` | IN | `T#10MS` | s | 采样周期，小于 10ms 钳位 / Sample time |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，输出立即跟随 fTrackValue / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪值，投切无扰动基准 / Track value |
| `fOut` | `REAL` | OUT | — | EU | 输出位置 / Output position |
| `fVel` | `REAL` | OUT | — | EU/s | 当前速度 / Current velocity |
| `fAcc` | `REAL` | OUT | — | EU/s² | 当前加速度 / Current acceleration |
| `bDone` | `BOOL` | OUT | — | — | 到位标志（吸附后置位）/ In-position flag |
| `bMoving` | `BOOL` | OUT | — | — | 运动进行中标志 / Motion in progress |
| `bError` | `BOOL` | OUT | — | — | 故障标志（瞬时，逐拍重算）/ Fault flag, transient |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0000_0000`；`0002` 采样周期钳位、`0004` 目标非有限值、`0701` 动态参数非法已钳位、`0702` 瞬态相位卡死 / Error code base `16#0000_0000` |
| `eState` | `E_DL_SCurveState` | OUT | — | — | 当前相位（十态，诊断）/ Current phase, diagnostics |

配套枚举：`E_DL_SCurveState`（`eIdle` / `eAccJerkUp` / `eAccConst` / `eAccJerkDown` / `eCruise` / `eDecJerkUp` / `eDecConst` / `eDecJerkDown` / `eDone` / `eFault`）。

### 8.2 调用示例 / Example

```iecst
PROGRAM PRG_LiftSCurve
VAR
    fbSC   : FB_DL_SCurveGenerator;     // 升降机构轨迹实例 / Lift trajectory instance
    fPosSp : REAL := 850.0;             // 目标高度 [mm] / Target height [mm]
END_VAR

fbSC(
    bEnable     := bAxisReady,
    fTarget     := fPosSp,
    fMaxVel     := 300.0,              // 最大速度 [mm/s] / Max velocity
    fMaxAcc     := 600.0,              // 最大加速度 [mm/s²] / Max acceleration
    fMaxJerk    := 3000.0,             // 最大加加速度 [mm/s³]，越小越柔 / Max jerk
    bAbort      := bEStop,             // 急停直连，安全优先 / Direct E-Stop link
    tSampleTime := T#10MS );
fPosCommand := fbSC.fOut;              // 位置给定送伺服 / Position command to servo
```

### 8.3 现场注意事项 / Field Notes

- **Jerk 优先整定**：`fMaxJerk` 直接决定柔性冲击水平，从小值起调（如 5 × fMaxAcc）直至节拍满足；三参数呈速度→加速度→Jerk 的依赖顺序，非法值钳位规则为 jerk←acc/ Dt、acc←vel/Dt、vel←1.0。
- **急停接线**：`bAbort` 必须直接绑定安全回路信号（如急停继电器触点经 PLC 采集），不得经过工艺条件包装；急停按最大减速停车，到位后速度/加速度清零，须重新给出目标才能继续。
- 瞬态相位（非匀速段）同段持续超 10000 拍强制进故障态并置 `16#0002_0702`，防参数矛盾导致轨迹卡死空转。

---

## 9. FB_DL_PwmDutyController ｜ 时间比例慢速 PWM / Time-Proportional Slow PWM

**功能**：时间比例慢速 PWM 控制器。把 0~100% 占空比调制成周期级布尔输出，驱动固态继电器（SSR）/ 接触器做加热功率调节，避免高频开关对触点与电网的冲击。周期内按占空比分配导通时间；含最短导通/关断时间抑制（过窄脉冲跨周期债务累加补偿）、反相输出；输出可与 PID 输出直连（0~100% 占空比）。
**Function**: Time-proportional slow PWM converting a 0..100% duty command into a boolean output for SSR/contactor heating. Includes minimum on/off pulse suppression via cross-cycle debt accumulation and an invert option; connects directly to a PID percent output.

### 9.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 立即关断并清债务 / Enable, FALSE forces off and clears debt |
| `fDuty` | `REAL` | IN | `0.0` | % | 占空比输入，0..100，越界钳位 / Duty cycle input, clamped |
| `tPeriod` | `TIME` | IN | `T#10S` | s | PWM 周期，下限 1s 且须 ≥ 最短开关时间和 / PWM period, min 1s |
| `tMinOn` | `TIME` | IN | `T#500MS` | s | 最短导通时间，窄脉冲并入债务 / Minimum on time |
| `tMinOff` | `TIME` | IN | `T#500MS` | s | 最短关断时间，两者之和须 < tPeriod / Minimum off time |
| `bInvert` | `BOOL` | IN | `FALSE` | — | 反相输出，TRUE 时输出取反 / Invert output |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sample time |
| `bPwmOut` | `BOOL` | OUT | — | — | PWM 布尔输出（已含反相处理）/ PWM boolean output |
| `fDutyEff` | `REAL` | OUT | — | % | 本周期实际有效占空比，含债务补偿 / Effective duty with debt |
| `nCycleCount` | `UDINT` | OUT | — | 个 | 已完成周期计数 / Completed cycle count |
| `bError` | `BOOL` | OUT | — | — | 故障标志（瞬时，逐拍重算）/ Fault flag, transient |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0000_0000`；`0001` 占空比越界钳位、`0002` 采样周期钳位、`0801` 周期低于下限 / 最短开关时间和已钳位 / Error code base `16#0000_0000` |

配套枚举：`E_DL_PwmState`（`eIdle` / `eOnPhase` / `eOffPhase` / `eFault`）。

### 9.2 调用示例 / Example

```iecst
PROGRAM PRG_SsrHeater
VAR
    fbPwm   : FB_DL_PwmDutyController;  // SSR 加热 PWM 实例 / SSR heater PWM instance
    fbPid   : FB_DL_PidController;      // 温控 PID 实例 / Temperature PID instance
    fHeater : BOOL;                     // 加热器输出点 / Heater output point
END_VAR

fbPid(bEnable := bAuto, fSetpoint := fSp, fActual := fPv,
      fKp := -3.0, tTi := T#20S, tSampleTime := T#100MS);

fbPwm(
    bEnable     := bPid.fOut >= 0.0,    // 也可直接 TRUE / May be simply TRUE
    fDuty       := fbPid.fOut,          // PID 输出 0..100% 直连 / Direct from PID
    tPeriod     := T#10S,               // 10s 慢周期 / Slow 10 s period
    tMinOn      := T#500MS,             // SSR 最短导通 / Min on for SSR life
    tMinOff     := T#500MS,
    tSampleTime := T#100MS );
fHeater := fbPwm.bPwmOut;
```

### 9.3 现场注意事项 / Field Notes

- **周期与热时间常数匹配**：`tPeriod` 取被控对象时间常数的 1/5~1/10（烘箱通常 5~20s）；周期太短接近扫描周期会丢脉宽分辨率，太长温度纹波加大。
- **最短 ON/OFF 是触点寿命保护**：机械接触器建议 `tMinOn/tMinOff ≥ 1s`，SSR 可取 100~500ms；欠脉冲按债务跨周期累加补偿，长期平均占空比无静差，但单周期内纹波会略增。

---

## 10. FB_DL_Integrator ｜ 梯形法积分器 / Trapezoidal Integrator

**功能**：梯形法离散积分器：`fSum += (fIn + fInPrev)/2 · fDt`，精度高于矩形法，对缓变信号无系统偏差。内部以 LREAL 双精度累加、输出转 REAL，防长时累计的舍入漂移。带上下限限幅（触限保持）、保持（`bHold`）、电平复位（`bReset`）、跟踪回投（`bTrack`）。现场用途：流量累计（总量表）、速度→位移、电量/电能累计。
**Function**: Trapezoidal integrator with double-precision (LREAL) accumulation to prevent long-term rounding drift; limit-with-hold, hold, level reset and track modes. Typical uses: flow totalizing, speed-to-position, energy accumulation.

### 10.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 保持累加器 / Enable, FALSE holds accumulator |
| `fIn` | `REAL` | IN | `0.0` | EU | 被积量，如流量/速度/电流 / Integrated input |
| `rOutMin` | `REAL` | IN | `0.0` | EU·s | 积分下限，大于上限时自动对调 / Integral lower limit |
| `rOutMax` | `REAL` | IN | `1.0E12` | EU·s | 积分上限，长时累计防溢出 / Integral upper limit |
| `bHold` | `BOOL` | IN | `FALSE` | — | 保持请求，TRUE 冻结累加 / Hold request |
| `bReset` | `BOOL` | IN | `FALSE` | — | 复位信号，**电平**触发清零 / Reset, level triggered clear |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，累加器立即跟随 fTrackValue / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU·s | 跟踪值，投切无扰动基准 / Track value |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sample time |
| `fOut` | `REAL` | OUT | — | EU·s | 积分结果 / Integration result |
| `bLimitHigh` | `BOOL` | OUT | — | — | 触上限标志 / Upper limit reached |
| `bLimitLow` | `BOOL` | OUT | — | — | 触下限标志 / Lower limit reached |
| `bError` | `BOOL` | OUT | — | — | 故障标志（瞬时，逐拍重算）/ Fault flag, transient |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0000_0000`；`0001` 量程对调 / 累加器幅值超 1.0E30 钳位、`0002` 采样周期钳位、`0004` 输入非有限值拒绝 / Error code base `16#0000_0000` |

配套枚举：`E_DL_IntState`（`eIdle` / `eHold` / `eIntegrating` / `eLimited` / `eFault`）。

### 10.2 调用示例 / Example

```iecst
PROGRAM PRG_FlowTotalizer
VAR
    fbTotal : FB_DL_Integrator;         // 流量累计实例 / Flow totalizer instance
    fFlow   : REAL;                     // 瞬时流量 [m3/h] / Instantaneous flow
END_VAR

fbTotal(
    bEnable     := bMeterOk,
    fIn         := fFlow / 3600.0,     // m3/h → m3/s，与 fDt 口径一致 / Convert to per-second
    rOutMin     := 0.0,
    rOutMax     := 1.0E9,              // 累计上限 [m3] / Totalizer ceiling
    bReset      := bShiftReset,        // 交接班清零（电平）/ Shift-reset (level)
    tSampleTime := T#100MS );
fTotalM3 := fbTotal.fOut;              // 班次累计量 [m3] / Shift total [m3]
```

### 10.3 现场注意事项 / Field Notes

- **单位自洽**：输出单位为 [EU·s]（被积量 × 秒）；流量 m³/h 必须先除以 3600 再积分，否则累计值放大 3600 倍——总量表对不上贸易结算的最大根因。
- **`bReset` 是电平语义**：保持 TRUE 即持续清零；交接班清零用一拍脉冲。被积信号先经 `FB_DL_LowPassFilter`（或 `FB_DL_MovingAverage`）去脉动，否则正负抵消不充分的累计误差随时间显性化。

---

## 11. FB_DL_Differentiator ｜ 实用微分器 / Practical Differentiator

**功能**：带一阶低通滤波的实用微分器：差分商 `(fIn - fInPrev)/fDt` 计算变化率，后接一阶低通抑制高频噪声放大（纯差分对采样噪声增益 1/fDt），输出变化率限幅（`rRateMin/rRateMax`）防异常尖峰误触发趋势报警。现场用途：温度变化速率监控（趋势报警前级）、压装速度计算、液位升降速率。
**Function**: Practical differentiator: difference quotient followed by a first-order low-pass to suppress the 1/fDt noise amplification, plus output rate clamping. Typical uses: temperature rate monitoring, press-fit velocity, level rate.

### 11.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 时输出 0 / Enable, FALSE forces output to zero |
| `fIn` | `REAL` | IN | `0.0` | EU | 被微分量，如温度/位置/液位 / Differentiated input |
| `tFiltTime` | `TIME` | IN | `T#500MS` | s | 速率低通时间常数，0 = 原始差分直通，超 60s 钳位 / Rate low-pass time constant |
| `rRateMin` | `REAL` | IN | `-1.0E10` | EU/s | 速率下限，大于上限时自动对调 / Rate lower limit |
| `rRateMax` | `REAL` | IN | `1.0E10` | EU/s | 速率上限 / Rate upper limit |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，输出立即跟随 fTrackValue / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU/s | 跟踪值，投切无扰动基准 / Track value |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位（防除零）/ Sample time, zero-division guarded |
| `fRateOut` | `REAL` | OUT | — | EU/s | 变化率输出（滤波并限幅）/ Rate output, filtered and limited |
| `fRawRate` | `REAL` | OUT | — | EU/s | 未滤波原始速率，诊断 / Raw unfiltered rate, diagnostics |
| `bValid` | `BOOL` | OUT | — | — | 输出有效标志（端点已同步且有真实差分）/ Output valid flag |
| `bError` | `BOOL` | OUT | — | — | 故障标志（瞬时，逐拍重算）/ Fault flag, transient |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0000_0000`；`0001` 量程对调、`0002` 采样周期钳位、`0004` 输入非有限值（清历史输出归零）、`1401` 滤波常数超 60s 钳位 / Error code base `16#0000_0000` |

配套枚举：`E_DL_DiffState`（`eInit` / `eRun` / `eTrack` / `eFault`）。

### 11.2 调用示例 / Example

```iecst
PROGRAM PRG_TempRate
VAR
    fbDiff : FB_DL_Differentiator;      // 温度速率监控实例 / Temperature rate monitor
    fTemp  : REAL;                      // 滤波后炉温 [degC] / Filtered furnace temperature
    bRampOK: BOOL;                      // 升温速率合规 / Ramp rate within limits
END_VAR

fbDiff(
    bEnable     := bFurnaceOn,
    fIn         := fTemp,
    tFiltTime   := T#500MS,            // 建议 ≥ 5 × tSampleTime / At least 5 sampling periods
    rRateMin    := -5.0,  rRateMax := 5.0,   // 速率量程 [degC/s] / Rate range
    tSampleTime := T#100MS );
bRampOK := fbDiff.bValid AND (ABS(fbDiff.fRateOut) <= 2.0);  // 2 degC/s 工艺限值 / Process rate limit
```

### 11.3 现场注意事项 / Field Notes

- **tFiltTime ≥ 5 × tSampleTime**（本块默认 500ms @ 100ms）：太小噪声抑制不足、趋势报警抖动；输出滞后 ≈ tFiltTime，用于联锁时把该滞后计入响应预算。`tFiltTime = 0` 为合法直通（输出原始差分商，不置故障），仅限信号本身干净的场合。
- 输入非有限值时本拍拒绝、清历史、输出归零（`bValid = FALSE`），下一有效拍重新同步端点——**报警逻辑必须与 `bValid` 相与**，避免初始化期伪造速率误报。

---

## 12. FB_DL_LowPassFilter ｜ 一阶低通滤波器 / First-Order Low-Pass Filter (PT1)

**功能**：一阶惯性低通数字滤波器（PT1）。递推式 `fOut := fOut + fAlpha*(fIn - fOut)`，`fAlpha := fDt / (fTf + fDt)`；时间常数 `tTimeConst` 运行中可调，变更即时重算；`T#0S` 直通；首扫与 `bTrack` 跟踪均无滞后，投切无扰动。现场用途：温度 / 压力 / 流量模拟量采集降噪。
**Function**: First-order PT1 low-pass with runtime-adjustable time constant (coefficients recomputed on change), T#0S pass-through, and lag-free first scan / track for bumpless transfer.

### 12.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 时输出直通原始输入 / Enable, FALSE passes raw input through |
| `fIn` | `REAL` | IN | `0.0` | EU | 原始采样输入 / Raw sampling input |
| `tTimeConst` | `TIME` | IN | `T#1S` | s | 滤波时间常数，T#0S = 直通，超 3600s 钳位 / Filter time constant |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sampling period |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，输出立即跟随跟踪值 / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪目标值，无扰投切用 / Track target value |
| `fOut` | `REAL` | OUT | — | EU | 滤波输出 / Filtered output |
| `fAlpha` | `REAL` | OUT | — | 1 | 当前滤波系数 0..1，诊断用 / Current filter coefficient |
| `bValid` | `BOOL` | OUT | — | — | 输出有效标志，首扫未完成时为 FALSE / Output valid flag |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0002` 采样周期钳位、`0004` 非有限值拒绝、`0005` 非法状态、`1001` 时间常数非法已钳位 / Error code base `16#0002_0000` |

配套枚举：`E_DL_LpfState`（`eInit` / `eRun` / `eTrack` / `eFault`）。

### 12.2 调用示例 / Example

```iecst
PROGRAM PRG_PressureFilter
VAR
    fbLpf   : FB_DL_LowPassFilter;      // 压力降噪实例 / Pressure noise filter
    fRawPa  : REAL;                     // AI 原始压力 [kPa] / Raw AI pressure
    fPvPa   : REAL;                     // 滤波后压力送 PID / Filtered pressure to PID
END_VAR

fbLpf(
    bEnable     := bSensorOk,
    fIn         := fRawPa,
    tTimeConst  := T#500MS,            // 压力回路 0.3..1s，温度 1..3s / Per loop class
    tSampleTime := T#100MS );
fPvPa := fbLpf.fOut;
```

### 12.3 现场注意事项 / Field Notes

- **时间常数按回路类型选**：温度 1~3s、压力 0.3~1s、流量 0.2~0.5s；输出对阶跃的 63.2% 响应时间 ≈ `tTimeConst`，越大越平滑、相位滞后越大——**串入 PID 反馈通道时滞后直接侵蚀稳定裕度**，滤波与控制带宽必须联合评估。
- 投入调节回路前先用 `bTrack` 跟踪当前过程值一拍，切换瞬间输出无跳变；联锁/急停必须用原始值，禁用滤波值。

---

## 13. FB_DL_SecondOrderFilter ｜ 二阶巴特沃斯低通 / Second-Order Butterworth Low-Pass

**功能**：二阶巴特沃斯低通滤波器，双二阶（biquad）离散递推实现，高频滚降 -40dB/dec，阻尼比 ζ=0.7071（最平坦幅频）。截止频率 `fCutoffFreq` 与采样周期变更时经双线性变换（含 TAN 频率预畸变）即时重算五系数；直流增益归一化恒为 1，稳态无静差；截止频率越奈奎斯特自动钳位至 0.45 倍采样频率。现场用途：振动 / 高速模拟量降噪、控制反馈信号整形。
**Function**: Second-order Butterworth biquad (-40 dB/dec, ζ=0.7071) with bilinear prewarped coefficient recomputation on parameter change, unity DC gain and Nyquist-aware cutoff clamping.

### 13.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 时输出直通原始输入 / Enable, FALSE passes raw input through |
| `fIn` | `REAL` | IN | `0.0` | EU | 原始采样输入 / Raw sampling input |
| `fCutoffFreq` | `REAL` | IN | `5.0` | Hz | 截止频率，大于 0 且低于 0.45 倍采样频率，越限自动钳位并置码 / Cutoff frequency, clamped at 0.45 × fs |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，输出立即跟随跟踪值 / Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪目标值，无扰投切用 / Track target value |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sampling period |
| `fOut` | `REAL` | OUT | — | EU | 滤波输出 / Filtered output |
| `bCoeffValid` | `BOOL` | OUT | — | — | 系数就绪标志，重算完成置 TRUE / Coefficient ready flag |
| `bValid` | `BOOL` | OUT | — | — | 输出有效标志 / Output valid flag |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0002` 采样周期钳位、`0004` 非有限值拒绝、`0005` 非法状态、`1101` 截止频率越奈奎斯特已钳位 / Error code base `16#0002_0000` |

配套枚举：`E_DL_SofState`（`eInit` / `eCoeffCalc` / `eRun` / `eTrack` / `eFault`）。

### 13.2 调用示例 / Example

```iecst
PROGRAM PRG_VibrationFilter
VAR
    fbSof   : FB_DL_SecondOrderFilter;  // 振动信号滤波实例 / Vibration filter instance
    fVibRaw : REAL;                     // 加速度传感器原始值 [mm/s²] / Raw accelerometer value
    fVibRms : REAL;                     // 滤波后有效值链路输入 / Filtered value for RMS chain
END_VAR

fbSof(
    bEnable     := bSensorOk,
    fIn         := fVibRaw,
    fCutoffFreq := 20.0,               // 保留 20Hz 以下工况频率 / Keep process band below 20 Hz
    tSampleTime := T#10MS );           // fs = 100 Hz，20Hz 远低于 45Hz 上限 / fs = 100 Hz
fVibRms := fbSof.fOut;
```

### 13.3 现场注意事项 / Field Notes

- **截止频率必须远低于奈奎斯特频率**（组件自动钳位至 0.45 × fs 并置 `16#0002_1101`，但钳位不等于频响正确）：想要抑制的噪声若折叠进带内，先提高采样频率再谈滤波。
- 截止频率处幅值衰减 -3dB、相位滞后约 90°；`fCutoffFreq` / `tSampleTime` 运行中变更会当拍原子重算五系数（`eCoeffCalc` 过渡态），变更瞬间输出无新旧系数混算，但趋势画面应预期一个短暂瞬态。

---

## 14. FB_DL_HighPassFilter ｜ 一阶高通滤波器 / First-Order High-Pass Filter (HP1)

**功能**：一阶高通数字滤波器（HP1）。递推式 `fOut := fAlpha * (fOutPrev + fIn - fInPrev)`，`fAlpha := tTf / (tTf + fDt)`。剥离静态偏置、提取动态分量：振动 / 位移传感器趋势分量剥离、皮带秤动态分量提取、结露监测的缓变漂移滤除。含输出限幅（Min > Max 对调防御）、`T#0S` 全通差分、首扫防上电脉冲、跟踪时输出清零并同步历史。
**Function**: First-order HP1 extracting the dynamic component by removing static bias; output clamping with limit-swap defense, all-pass difference at T#0S, power-up pulse suppression and zero-baseline tracking.

### 14.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | `FALSE` | — | 使能，FALSE 时输出置 0 / Enable, FALSE forces output to zero |
| `fIn` | `REAL` | IN | `0.0` | EU | 原始采样输入 / Raw sampling input |
| `tTimeConst` | `TIME` | IN | `T#1S` | s | 高通时间常数，越大截止频率越低；T#0S = 全通差分，超 3600s 钳位 / High-pass time constant |
| `tSampleTime` | `TIME` | IN | `T#100MS` | s | 采样周期，小于 10ms 钳位 / Sampling period |
| `rOutMin` | `REAL` | IN | `-1.0E10` | EU | 输出下限（工程防护，防差分尖峰打穿下游量程）/ Output lower limit, engineering guard |
| `rOutMax` | `REAL` | IN | `1.0E10` | EU | 输出上限 / Output upper limit |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，跟踪语义为**输出清零**并同步历史（重新定基线）/ Track zeroes the baseline |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪目标值（占位，输出仍清零）/ Track target placeholder |
| `fOut` | `REAL` | OUT | — | EU | 动态分量输出 / Dynamic component output |
| `fAlpha` | `REAL` | OUT | — | 1 | 当前滤波系数 0..1，诊断用 / Current filter coefficient |
| `bValid` | `BOOL` | OUT | — | — | 输出有效标志，首扫未完成时为 FALSE / Output valid flag |
| `bError` | `BOOL` | OUT | — | — | 故障标志 / Fault flag |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` 量程对调、`0002` 采样周期钳位、`0004` 非有限值拒绝并复位历史、`0005` 非法状态、`1201` 时间常数非法已钳位 / Error code base `16#0002_0000` |

配套枚举：`E_DL_HpfState`（`eInit` / `eRun` / `eTrack` / `eFault`）。

### 14.2 调用示例 / Example

```iecst
PROGRAM PRG_VibrationTrend
VAR
    fbHpf   : FB_DL_HighPassFilter;     // 振动动态分量提取实例 / Vibration HPF instance
    fVibSig : REAL;                     // 位移传感器信号（含缓变温漂）[um] / Sensor signal with drift
    fDynPk  : REAL;                     // 动态分量送峰值检测 / Dynamic part to peak detector
END_VAR

fbHpf(
    bEnable     := bSensorOk,
    fIn         := fVibSig,
    tTimeConst  := T#2S,               // 截止 ≈ 1/(2·π·2s) ≈ 0.08 Hz，温漂被剥离 / Cutoff ≈ 0.08 Hz
    tSampleTime := T#100MS );
fDynPk := fbHpf.fOut;
```

### 14.3 现场注意事项 / Field Notes

- **截止频率 fc = 1/(2π·tTimeConst)**：时间常数越大截止越低、保留的低频动态越丰富；剥离趋势监控用途取大时间常数（1~10s），皮带秤动态分量提取按工艺带宽选。
- 高通输出**均值恒趋于 0**：判断"信号是否正常"不能看输出的均值，要看其包络 / 峰峰值 / RMS；`bTrack` 在此组件中语义是"输出清零重新定基线"，不是跟随 `fTrackValue`，勿按低通习惯使用。

---

## 15. FC_DL_DewPointCalc ｜ 露点温度计算 / Dew Point Calculation

**功能**：Magnus-Tetens（Stull 参数化）露点温度计算。由干球温度与相对湿度求露点：`gamma := LN(RH/100) + a*T/(b+T)`，`Td := b*gamma/(a-gamma)`，a=17.625、b=243.04（过水面参数化）。另附实际水汽压输出供焓值类组件复用。现场用途：洁净室 / 干燥房环控、冷面结露风险判断（表面温度低于露点即结露）。函数无状态，同输入必得同输出。
**Function**: Stateless Magnus-Tetens (Stull) dew point from dry-bulb temperature and relative humidity, with the actual vapor pressure as a secondary output for enthalpy chains. Typical uses: cleanroom / dry-room HVAC and condensation-risk interlocks.

### 15.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `fTempC` | `REAL` | IN | — | °C | 干球温度，有效域 -40..60，越域钳位继续计算 / Dry-bulb temperature, clamped outside domain |
| `fRhPct` | `REAL` | IN | — | % | 相对湿度，有效域 0.1..100（下限防对数发散）/ Relative humidity, floor 0.1 guards LN divergence |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` 参数越界已钳位、`0004` 非有限值拒绝、`1501` 湿度越域已钳位、`1502` 温度越域已钳位 / Error code base `16#0002_0000` |
| `fVaporPa` | `REAL` | OUT | — | Pa | 实际水汽压，诊断与焓值复用 / Actual vapor pressure, diagnostic and reuse |
| `bInRange` | `BOOL` | OUT | — | — | 输入是否处于公式有效域 / Inputs within formula valid domain |
| 返回值 / Return | `REAL` | RET | — | °C | 露点温度；异常路径返回哨兵值 -40.0 / Dew point; sentinel -40.0 on error paths |

常量：`DL_DEW_A = 17.625`、`DL_DEW_C = 243.04 °C`、`DL_DEW_E0 = 611.2 Pa`、`DL_DEW_SENTINEL = -40.0 °C`。

### 15.2 调用示例 / Example

```iecst
PROGRAM PRG_CondenseGuard
VAR
    fAirTemp : REAL;                    // 干球温度 [degC] / Dry-bulb temperature
    fAirRh   : REAL;                    // 相对湿度 [%RH] / Relative humidity
    fDewPt   : REAL;                    // 露点 [degC] / Dew point
    fSurfTemp: REAL;                    // 冷面温度 [degC] / Cold surface temperature
    bCondRisk: BOOL;                    // 结露风险 / Condensation risk
    uDewErr  : UDINT;
    bInDom   : BOOL;
END_VAR

fDewPt := FC_DL_DewPointCalc(
    fTempC  := fAirTemp,
    fRhPct  := fAirRh,
    uErrorId => uDewErr,
    bInRange => bInDom );

(* 仅当无故障且在有效域时才参与联锁 / Interlock only on valid codes *)
bCondRisk := (uDewErr = 16#0002_0000) AND bInDom AND (fSurfTemp <= fDewPt);
```

### 15.3 现场注意事项 / Field Notes

- **只接收相对湿度**：把绝对湿度或露点值误当作 `fRhPct` 输入会得到荒谬结果；冰点以下按过水面参数化计算霜点近似，锂电干燥房等精密对标场景建议上层做冰面 Magnus 修正。
- **哨兵值 -40.0 不构成有效数据**：返回值等于 -40.0 时必须先核对 `uErrorId` 再使用，上位趋势画面应按故障码过滤后再绘图；输入温湿度应先滤波，露点输出抖动会带抖联锁逻辑。

---

## 16. FC_DL_FlowCompensate ｜ 流量温压补偿 / Flow Temperature-Pressure Compensation

**功能**：气体 / 蒸汽流量温压补偿：按理想气体定律 `Qs = Qa × (Pa/Ps) × (Ts/Ta)` 把工况体积流量换算为标准状态流量（Nm³/h 口径）；压缩因子比 Zs/Za 按中低压口径简化为 1（头部明示）。绝压 = 表压 + 大气压，温度开尔文化。可选开方支持差压流量计（孔板 / 文丘里）口径：`bEnableSqRt = TRUE` 时输入先按差压线性量开方。函数无状态。现场用途：涡街 / 孔板气体计量贸易交接、能耗统计。
**Function**: Stateless ideal-gas compensation converting operating volumetric flow to standard cubic meters per hour; optional square-root input for differential-pressure meters. Z-ratio simplified to 1 for medium/low pressure (disclosed).

### 16.1 接口 / Interface

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `fFlowActual` | `REAL` | IN | — | m³/h | 工况体积流量（差压口径且 `bEnableSqRt=TRUE` 时为差压线性量）/ Actual volume flow, or dp-linear value when square root enabled |
| `fPressGauge` | `REAL` | IN | — | kPa | 管线表压，负值钳位 0 / Line gauge pressure, negative clamped to 0 |
| `fAtmPress` | `REAL` | IN | `101.325` | kPa | 当地大气压 / Local atmospheric pressure |
| `fTempC` | `REAL` | IN | — | °C | 介质温度，有效域 -40..300，越域标记不阻断 / Medium temperature |
| `rNormPressPs` | `REAL` | IN | `101.325` | kPa | 标准状态压力（非正钳回 NTP 口径）/ Standard state pressure |
| `rNormTempTs` | `REAL` | IN | `0.0` | °C | 标准状态温度，0 = NTP 口径 / Standard state temperature, 0 = NTP |
| `bEnableSqRt` | `BOOL` | IN | `FALSE` | — | 差压口径开方使能 / Square-root enable for dp meters |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码，无故障基准 `16#0002_0000`；`0001` 表压/标准压力越界已钳位、`0004` 非有限值拒绝、`1601` 绝压低于防御下限 1.0 kPa 返回 0、`1602` 绝对温度低于防御下限 50 K 返回 0 / Error code base `16#0002_0000` |
| `fPaAbs` | `REAL` | OUT | — | kPa | 绝压，诊断 / Absolute pressure, diagnostic |
| `bInRange` | `BOOL` | OUT | — | — | 温度是否处于公式有效域（越域按钳位口径继续计算不阻断）/ Temperature within valid domain |
| 返回值 / Return | `REAL` | RET | — | Nm³/h | 标准状态流量；异常路径返回哨兵值 0.0 / Standard flow; sentinel 0.0 on error paths |

常量：`DL_FLOW_T0K = 273.15 K`、`DL_FLOW_PRESS_MIN = 1.0 kPa`、`DL_FLOW_TA_MIN = 50.0 K`、`DL_FLOW_SENTINEL = 0.0 m³/h`。

### 16.2 调用示例 / Example

```iecst
PROGRAM PRG_GasMetering
VAR
    fFlowOp : REAL;                     // 工况流量（涡街线性口径）[m3/h] / Operating flow
    fPressK : REAL;                     // 管线表压 [kPa] / Gauge pressure
    fTempD  : REAL;                     // 介质温度 [degC] / Medium temperature
    fQn     : REAL;                     // 标况流量 [Nm3/h] / Standard flow
    uFlowErr: UDINT;
END_VAR

fQn := FC_DL_FlowCompensate(
    fFlowActual  := fFlowOp,
    fPressGauge  := fPressK,
    fAtmPress    := 101.325,           // 高原现场按当地值改 / Local value at altitude
    fTempC       := fTempD,
    bEnableSqRt  := FALSE,             // 涡街自带线性流量；孔板/文丘里置 TRUE / TRUE for dp meters
    uErrorId => uFlowErr );

(* 贸易交接与能耗统计只累计无故障期间的数值 / Accumulate only fault-free scans *)
IF uFlowErr = 16#0002_0000 THEN
    fEnergyTotal := fEnergyTotal + fQn;   // 送累计链路 / Feed totalizer chain
END_IF
```

### 16.3 现场注意事项 / Field Notes

- **口径边界**：压缩因子比 Zs/Za 按中低压（绝压 < 2 MPa）简化为 1；高压计量必须在上层引入真实气体因子修正，本组件不替调用方做高压外推。孔板 / 文丘里差压口径务必置 `bEnableSqRt = TRUE`，否则差压平方关系导致流量严重偏大。
- **哨兵 0.0 与防御下限**：绝压 < 1.0 kPa 或绝对温度 < 50 K 时返回 0 并置 `16#0002_1601/1602`（典型根因是大气压引脚留了出厂缺省 5.0 或温度开尔文化遗漏）；贸易交接累计必须与 `uErrorId = 16#0002_0000` 相与。

---

## 17. FC_DL_HumidAirEnthalpy ｜ 湿空气比焓计算（R5 补强）/ Moist-Air Specific Enthalpy

**定位**：湿空气比焓 clean-room 计算。公式链：饱和蒸汽压 `p_ws` 用 Magnus-Tetens（Stull 参数化，与 `FC_DL_DewPointCalc` 同系数口径 a=17.625、b=243.04 常量复用防两套公式漂移）→ 含湿量 `W = 0.622·φ·p_ws / (p − φ·p_ws)` → 比焓 `h = 1.006·T + W·(2501 + 1.86·T)`。现场用途：洁净室/干燥房表冷器与再热功率预算、焓差控制（新风焓 < 室内焓 才引入新风）、能耗对比。行为定义对标 OSCAT Building `AIR_ENTHALPY`（0~100 ℃ 域）与 PsychroLib `GetMoistAirEnthalpy` 公开物理公式，clean-room 未复制任何源码行。
**兼容性**：CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert。

### 17.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fTempC` | `REAL` | IN | 干球温度 [°C]，有效域 0.0..100.0，越界钳位照算 / Dry-bulb temperature |
| `fRelHum` | `REAL` | IN | 相对湿度 [%]，有效域 1.0..100.0，钳位 [1,100] 防 W 发散 / Relative humidity |
| `fAtmPress` | `REAL` | IN | 大气压 [kPa]，默认 101.325 标准大气，有效域 80.0..110.0 / Atmospheric pressure |
| 返回值 | `REAL` | RETURN | 湿空气比焓 [kJ/kg 干空气]；异常路径返回确定值 0.0 / Specific enthalpy per kg dry air |
| `uErrorId` | `UDINT` | OUT | `0002_1701` 温/湿度越界已钳位照算 ｜ `0002_1702` 大气压越界已钳位照算 ｜ `0002_1703` 饱和退化分母已保护 ｜ `0002_0004` 输入非有限值已拒绝——全部信息级；0=无 / Info codes, clamping |

### 17.2 调用示例 / Call Example

```iecst
VAR
    fHSupply  : REAL;                    // 送风焓值 [kJ/kg 干空气] / Supply-air enthalpy
    fHOutdoor : REAL;                    // 新风焓值 / Outdoor-air enthalpy
    uHErr     : UDINT;                   // 故障码 / Error code
END_VAR
fHSupply  := FC_DL_HumidAirEnthalpy(fTempC := stAHU.fSupplyT,
                                    fRelHum := stAHU.fSupplyRh,
                                    uErrorId => uHErr);
fHOutdoor := FC_DL_HumidAirEnthalpy(fTempC := stMet.fTemp,
                                    fRelHum := stMet.fRh,
                                    fAtmPress := 100.8);   // 高原工程传真实大气压 / Real pressure
// 焓差控制联锁：仅 uErrorId = 0 时焓值才可用于联锁 / Interlock only when uErrorId = 0
IF (uHErr = 0) AND (fHOutdoor < fHSupply - 2.0) THEN
    bFreshAirOk := TRUE;
END_IF
```

**现场提示 / Field notes**：① 输入必须是干球温度 + 相对湿度百分数，给成湿球温度会得到荒谬结果；② 高海拔厂房（< 80 kPa 被钳位）含湿量系统性偏小，影响表冷选型；③ 返回值为每公斤**干空气**比焓，能量平衡时风量乘干空气密度换算；④ 100 ℃/100% RH 附近 W 发散是物理事实，该域结果勿用于工艺联锁。

---

## 18. FB_DL_RampSoakProfile ｜ 多段 Ramp/Soak 程序曲线发生器（R6，v1.0.1）

**功能 / 中文**：多段 Ramp/Soak 程序曲线发生器（T2-1 LGF Technology 组曲线族深化）。段数 1..16 可配，每段目标值 + 斜坡时间 + 保温时间三数组；段切换沿单发、外部保持（冻结当前值与段内计时，含暂停语义）、跳段、循环运行、中途跟踪无扰重启（R19）；作为温控区设定源，烘箱/烧结炉/化成工步共用。连续量核心件：`tSampleTime` 显式（必须放固定周期任务）。
**Function**: Multi-segment Ramp/Soak profile generator (1..16 segments) with per-segment target/ramp/soak arrays, segment-change edge, external hold, skip, loop and mid-run track resync; the setpoint source for temperature zones.

### 18.1 随文件枚举 / Enums

`E_DL_RampSoakPhase`（随本块发布）：`eIdle(0) / eRamp(10) / eSoak(20) / eDone(30) / eFault(99)`。

### 18.2 接口 / Interface（逐字取自源码声明区）

| 引脚 | 类型 | 方向 | 默认值 | 单位 | 说明 / Description |
|---|---|---|---|---|---|
| `tSampleTime` | `TIME` | IN | `T#100MS` | — | 采样周期，<T#10MS 钳位并置码 / Sample time |
| `aTarget` | `ARRAY[1..16] OF REAL` | IN | `[16(0.0)]` | EU | 各段目标值，量纲由调用方工艺定义 / Segment targets [EU] |
| `aRampTime` | `ARRAY[1..16] OF TIME` | IN | — | — | 各段斜坡时间，0=从当前值阶跃直达该段目标（信息级）/ Segment ramp times |
| `aSoakTime` | `ARRAY[1..16] OF TIME` | IN | — | — | 各段保温时间，0=该段无保温直达下段 / Segment soak times |
| `nSegCount` | `USINT` | IN | `1` | — | 有效段数 1..16，越界钳位至 1 并置码 / Active segment count |
| `fStartValue` | `REAL` | IN | `0.0` | EU | 启动基准值，首段斜坡起点 / Start value [EU] |
| `bStart` | `BOOL` | IN | `FALSE` | — | 启动指令，上升沿生效 / Profile start |
| `bHold` | `BOOL` | IN | `FALSE` | — | 外部保持，电平生效：冻结当前值与段内计时（含暂停语义）/ External hold |
| `bSkipSeg` | `BOOL` | IN | `FALSE` | — | 跳段指令，上升沿生效：当前段立即结束进入下段 / Skip segment |
| `bTrack` | `BOOL` | IN | `FALSE` | — | 跟踪使能，TRUE 时设定值跟随跟踪值（R19，运行中途插入必测）/ Track enable |
| `fTrackValue` | `REAL` | IN | `0.0` | EU | 跟踪值，温控区实际温度回同步（无扰重启）/ Track value [EU] |
| `bLoopProfile` | `BOOL` | IN | `FALSE` | — | 循环运行，TRUE=末段完成后自动从段 1 重启（斜坡起点=当前值）/ Loop profile |
| `bReset` | `BOOL` | IN | `FALSE` | — | 复位，上升沿复位故障并回空闲 / Reset |
| `fSetpoint` | `REAL` | OUT | `0.0` | EU | 程序设定值输出 → 温控区设定源，量纲=EU / Profile setpoint [EU] |
| `nSegAct` | `USINT` | OUT | `0` | — | 当前段号 1..nSegCount，0=未启动 / Active segment |
| `ePhase` | `E_DL_RampSoakPhase` | OUT | `eIdle` | — | 段内相位，HMI 显示用 / Phase |
| `bSegChange` | `BOOL` | OUT | `FALSE` | — | 段切换沿单发，TRUE 持续一拍 / Segment change edge |
| `bDone` | `BOOL` | OUT | `FALSE` | — | 全部段完成，完成态保持至重启/复位 / Profile done |
| `uErrorId` | `UDINT` | OUT | `0` | — | 末次事件码，段位 `16#0002_xxxx` / Last error code |

### 18.3 故障码 / Error Codes（独立 18xx 族段，终审裁定）

| 码位 | 级别 | 语义 |
|---|---|---|
| `0002_1801` | 信息级 | 末段跳段完成 |
| `0002_1802` | 信息级 | 段数钳位（越界钳位至 1） |
| `0002_1803` | 信息级 | 零斜坡阶跃直达 |
| `0002_1804` | 信息级 | 采样周期钳位 |
| `0002_1810` | 故障级 | 段目标非有限值（锁存进故障态，仅复位可清） |
| `0002_0005` | 故障级 | 非法状态兜底（子库族码） |

> 族段裁定：规格原分配落入既有 01xx PID / 02xx 串级族段，终审裁定划独立 `18xx` 族段并已修正码位常量；语义零变更，仅码位重排。

### 18.4 调用示例 / Call Example

```iecst
(* 四段：150℃→180℃→220℃→40℃（含保温），作温控区设定源 / four-segment profile *)
fbProfile.tSampleTime := T#100MS;
fbProfile.nSegCount   := 4;
fbProfile.aTarget[1]  := 150.0;  fbProfile.aRampTime[1] := T#20M;  fbProfile.aSoakTime[1] := T#30M;
fbProfile.aTarget[2]  := 180.0;  fbProfile.aRampTime[2] := T#30M;  fbProfile.aSoakTime[2] := T#45M;
fbProfile.aTarget[3]  := 220.0;  fbProfile.aRampTime[3] := T#25M;  fbProfile.aSoakTime[3] := T#60M;
fbProfile.aTarget[4]  := 40.0;   fbProfile.aRampTime[4] := T#40M;  fbProfile.aSoakTime[4] := T#0S;
fbProfile(bStart := bRunProfile, bHold := bPause, bTrack := bResync, fTrackValue := fZoneT);
fZoneSetpoint := fbProfile.fSetpoint;
```

---

## 19. 子库故障码登记说明 / Sublibrary Error Code Registry Note

本子库 18 组件故障码全部位于 `16#0002_xxxx` 段，**按组件细分**：01xx PID（`0101` 输出饱和、`0102` 手动值钳位，均信息级）、02xx 串级（`0201` 副设定超域，信息级）、03xx 分程（`0301` 满量程非法）、04xx 前馈（`0402` 队列截断）、05xx 史密斯（`0501` 模型增益非法、`0502` 滞后截断，信息级）、06xx 斜坡（`0601` 速率非法冻结）、07xx S 曲线（`0701` 动态参数钳位、`0702` 相位卡死）、08xx PWM（`0801` 周期钳位）、10xx 低通（`1001` 时间常数钳位）、11xx 二阶（`1101` 截止频率钳位）、12xx 高通（`1201` 时间常数钳位）、14xx 微分（`1401` 滤波常数钳位）、15xx 露点（`1501` 湿度越域、`1502` 温度越域）、16xx 流量（`1601` 绝压下限、`1602` 温度下限）、17xx 湿空气焓值（`1701~1703` 信息级）、**18xx Ramp/Soak 程序曲线族（`1801~1804` 信息级、`1810` 故障级——R6 终审裁定自 01xx/02xx 归位的独立族段，语义零变更仅码位重排）**。

段内公共码：`0001` 参数越界已钳位、`0002` 采样周期已钳位、`0004` 输入非有限值已拒绝、`0005` 非法状态兜底。无故障基准码存在两种口径：多数组件每拍重算为 `16#0002_0000`，斜坡 / S 曲线 / PWM / 积分 / 微分五组件为 `16#0000_0000`（见各节接口表）。该段与 Level 0 早期登记的业务语义（同步超时、联锁配置非法等）为段内并行使用，判读以本手册各节为准，全库统一归并安排见 `LIBRARY_MANUAL.md` 第四节登记说明。

---

## 20. 典型组态与联调要点 / Typical Configurations and Commissioning Notes

1. **温控标准链路**：`FB_DL_LowPassFilter`（PV 降噪）→ `FB_DL_PidController`（`fKp` 负 = 反作用）→ `FB_DL_SplitRangeControl`（冷热分程）→ `FB_DL_PwmDutyController`（SSR 驱动）；长滞后对象把 PID 换成 `FB_DL_SmithPredictor`。
2. **给定值软化链路**：`FB_DL_RampGenerator`（工艺速率）或 `FB_DL_RateLimiter`（防阶跃）→ PID 设定值通道；两块"速率为 0"语义刻意相反（Ramp 冻结 / Rate 不限），组态时禁止凭习惯互拷参数。
3. **程序曲线链路（R6）**：`FB_DL_RampSoakProfile` → 温控区设定引脚（`fSetpoint` 直连）；跟踪通道接温控区实际温度实现无扰重启；HMI 段号/相位用 `nSegAct` / `ePhase` 显示，`bSegChange` 可触发段相关工艺动作。
4. **计量链路**：`FC_DL_FlowCompensate`（标况换算）→ `FB_DL_Integrator`（`fIn` 除以 3600 统一 [EU·s] 口径）→ 贸易交接累计；累计链路必须与两个 FC 的 `uErrorId` 相与。
5. **联调顺序**：先单组件开环验收（对照各 `.st` 头注释验收向量），再串链路；所有 FB 放同一固定周期任务，`tSampleTime` 全链路取同一值。

---

## 21. FB_DL_PeakDetector ｜ 峰值/谷值检测器（R8）

**功能 / Function**：输入信号的全周期极值保持：峰值只升不降（除衰减与复位），可选线性衰减模型（fDecayRate [EU/s]，冲击型信号回落后极值缓慢下降）；谷值独立使能；峰值变化率（正值=仍在爬升）；阈值超限电平位 + 峰值/谷值更新单拍事件与冲击计数。LGF Math 统计族语义 clean-room——与 `FB_DL_SignalStatistics` 职责分离（本块做全周期极值，统计块做窗口聚合），禁止合并成 MODE 巨无霸。
/ Full-horizon peak/valley hold with optional linear decay, valley enable, peak rate, threshold level and one-scan update events; deliberately separate from FB_DL_SignalStatistics.

**接口表 / Interface**（逐字取自声明区 / verbatim from the declaration area）：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=极值冻结不更新、事件清零 |
| `bReset` | BOOL | IN | 复位（上升沿把极值复位到当前信号并清零计数） |
| `fSignal` | REAL | IN | 输入信号 [工程单位]，非有限值保持上次有效值（0002_1901） |
| `tSample` | TIME | IN | 采样周期 [ms]（衰减与变化率换算基准），T#0S=不衰减 |
| `fDecayRate` | REAL | IN | 峰值衰减率 [EU/s]，0=无限保持，负值取绝对值（非法提示 1903） |
| `bDetectValley` | BOOL | IN | 谷值检测使能，FALSE 时 fValley 恒为 0 |
| `fThreshold` / `bThresholdEnable` | REAL / BOOL | IN | 事件阈值 [EU]（非有限值禁用提示 1902）/ 阈值事件使能 |
| `fPeak` / `fValley` | REAL | OUT | 峰值 / 谷值 [工程单位]（只升不降，除衰减与复位） |
| `fPeakRate` | REAL | OUT | 峰值变化率 [EU/s]，正值=仍在爬升 |
| `bPeakEvent` / `bValleyEvent` | BOOL | OUT | 峰值 / 谷值更新事件（单拍脉冲，R25 三律） |
| `bOverThreshold` | BOOL | OUT | 峰值超阈值（电平型每拍重算） |
| `uPeakCount` | UDINT | OUT | 峰值更新次数（可作冲击次数统计） |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障标志（全信息级故恒 FALSE）/ 错误码 16#0002_19xx |

**故障码 / Codes**：全信息级 0002_1901~1904；`bError` 恒 FALSE（R21）。

**调用示例 / Example**：

```iecst
fbPeak(bEnable := TRUE, bReset := bResetCmd,
       fSignal := fPressEU,                     // 压装压力信号 [kN]
       tSample := T#10MS, fDecayRate := 0.0,    // 0 = 峰值无限保持
       bDetectValley := FALSE,
       fThreshold := 12.0, bThresholdEnable := TRUE);
IF fbPeak.bOverThreshold THEN bOverloadWarn := TRUE; END_IF
```

**现场要点 / Field notes**：冲击/过载监视用「衰减关闭 + 阈值事件」；周期性峰值跟踪（如每件压装力）配 bPeakEvent 计数；衰减模型为线性速率，指数衰减族留扩产——需要「缓慢遗忘」历史极值的场景现场可改用 bReset 周期复位。

---

## 22. FB_DL_StepController ｜ 多级步进控制器（R8）

**功能 / Function**：1..8 级步进调节（LBP CtrlStp 语义 clean-room 平移）：偏差归一化分级（fBandSpan 满量程对应全部级投入）+ 级间死区（迟滞半宽，加/减级判据分离）+ 最小驻留（换级后须停留 tMinDwell）+ 累积（多级依次投入）/ 单级（互斥）双拓扑 + 均衡轮换偏移（同型设备轮换）；满出力/回零警示。
/ 1..8-stage step controller with normalized-error staging, inter-stage deadband hysteresis, minimum dwell, cumulative/single-stage topologies and rotation offset across identical devices.

**接口表 / Interface**：

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bEnable` | BOOL | IN | 使能，FALSE=全部级复位为 0 |
| `bReset` | BOOL | IN | 复位（上升沿把级数与轮换偏移清零） |
| `fSetpoint` / `fActual` | REAL | IN | 设定值 / 实际值 [工程单位]（同量纲；非有限值级数保持 0002_1A05） |
| `nStages` | UINT | IN | 级数，域 1..8，越界钳位（0002_1A02） |
| `fBandSpan` | REAL | IN | 级带宽 [工程单位]（非法回默认 1A03；钳位后仍退化判故障级 1A06） |
| `fDeadband` | REAL | IN | 级间死区 [EU]（迟滞半宽；过大钳至半级带 1A04） |
| `tMinDwell` | TIME | IN | 最小驻留，换级后须停留此时间才允许再切（未到拒绝 1A01） |
| `bCumulative` | BOOL | IN | 累积拓扑（TRUE=多级依次投入，FALSE=单级互斥） |
| `bRotate` / `nRotateStep` | BOOL / UINT | IN | 均衡轮换使能 / 轮换步长（按级数取模归约） |
| `nActiveStage` | UINT | OUT | 当前投入级数，域 0..nStages |
| `abStage` | ARRAY[0..7] OF BOOL | OUT | 各级输出（索引 0=第 1 级） |
| `nRotateOffset` | UINT | OUT | 轮换偏移，域 0..nStages-1 |
| `nSwitchCount` | UDINT | OUT | 投切次数（级数每变化一次 +1） |
| `bAtMaxStage` / `bAtMinStage` | BOOL | OUT | 已达最大级（满出力警示）/ 已回零级 |
| `bError` / `uErrorId` | BOOL / UDINT | OUT | 故障标志（仅故障级置位）/ 错误码 16#0002_1Axx |

**故障码 / Codes**：信息级 0002_1A01~1A05；故障级 0002_1A06（级带宽退化无法运算，锁存）。

**调用示例 / Example**：

```iecst
fbStep(bEnable := TRUE, bReset := bResetCmd,
       fSetpoint := fTempSP, fActual := fTempPV,   // 温区分级加热 [℃]
       nStages := 4, fBandSpan := 20.0,
       fDeadband := 0.5, tMinDwell := T#30S,
       bCumulative := TRUE, bRotate := TRUE);
heater1 := fbStep.abStage[0];                    // 四组加热器依次投入
heater2 := fbStep.abStage[1];
```

**现场要点 / Field notes**：轮换仅适用同型设备——不同容量级混布时轮换语义由调用方保证；驻留时间内换级请求被拒属正常节流（1A01 每拍重算，不置故障），频繁出现说明死区/带宽整定偏小；单级拓扑（bCumulative=FALSE）适合多台压缩机互斥轮停场景。

---

## 23. FB_DL_SineGenerator ｜ 相位累加正弦发生器（R10，v1.0.1）

**定位 / Positioning**：以任务周期与频率引脚推进相位，输出 `fOut = fOffset + fAmplitude × sin(2π·(f·t + φ0))` 的连续正弦给定。用于振动台 / 摇摆机构测试给定、执行器疲劳试验、阀门特性扫描、仿真信号注入、张力摆辊扰动测试。

**与同类组件选型 / Selection**：正弦本件；锯齿 / 三角选 `FB_DL_SawtoothGenerator`；方波（布尔与时间域）选 `FB_DL_PulseGenerator`；斜坡给定量（把阶跃目标平滑）选 `FB_DL_RampGenerator`。**三类波形独立成块，严禁用波形选择参数合并**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能，FALSE 时输出保持值并冻结相位 [−] / Enable, FALSE holds the output and freezes the phase |
| `bResetPhase` | BOOL | IN | — | 相位复位，上升沿把累计相位归到初相（不改频率与幅值）[−] / Phase reset to the initial phase |
| `fAmplitude` | LREAL | IN | 1.0 | 幅值，域 ≥ 0，0 表示恒输出偏置 [工程单位] / Amplitude, non-negative |
| `fOffset` | LREAL | IN | 0.0 | 直流偏置 [工程单位] / DC offset |
| `fFreq` | LREAL | IN | 1.0 | 频率，域 0~100，0 表示冻结在当前相位 [Hz] / Frequency, 0..100 |
| `fPhase0` | LREAL | IN | 0.0 | 初相位，域 ±360°，超域归一 [度] / Initial phase in degrees |
| `fTaskCycle` | LREAL | IN | 0.01 | 任务周期，域 1 ms~1 s，由调用方按实际任务注入 [s] / Task cycle time |
| `fHoldValue` | LREAL | IN | 0.0 | 失能或故障时的输出保持值 [工程单位] / Output hold value |
| `bClampOut` | BOOL | IN | FALSE | TRUE 表示按上下限限幅输出 [−] / TRUE enables output clamping |
| `fOutMin` | LREAL | IN | -1.0E6 | 输出下限，仅 `bClampOut = TRUE` 时生效 [工程单位] / Output lower limit |
| `fOutMax` | LREAL | IN | 1.0E6 | 输出上限，仅 `bClampOut = TRUE` 时生效 [工程单位] / Output upper limit |
| `fOut` | LREAL | OUT | — | 正弦输出 [工程单位] / Sine output value |
| `fPhaseDeg` | LREAL | OUT | — | 当前相位，域 0~360 [度] / Current phase in degrees |
| `uCycleCnt` | UDINT | OUT | — | 完整周期计数，用于寿命与疲劳计数 [个] / Completed cycle counter |
| `bRunning` | BOOL | OUT | — | 运行中（使能且频率 > 0）[−] / TRUE while running |
| `uErrorId` | UDINT | OUT | — | 事件码：`1B01~1B04` 四类钳位（信息级）/ `1B10` 参数非有限（故障级）/ `1B11` 回绕超限或非法状态（故障级）/ Event code |
| `bError` | BOOL | OUT | — | 故障锁存，仅故障级码置位 [−] / Fault latch |

### 调用示例 / Example

```iecst
VAR
    fbShaker : FB_DL_SineGenerator;   // 振动台正弦给定 / Shaker sine setpoint
    fShakeSp : LREAL;                 // 给定值 [mm] / Setpoint
    fPhase   : LREAL;                 // 当前相位 [度] / Current phase
    nCycles  : UDINT;                 // 累计循环数 / Completed cycles
END_VAR

// 每周期无条件调用：2 Hz、幅值 5 mm、偏置 0、任务周期 10 ms
fbShaker(bEnable := bTestRunning, bResetPhase := bStartNewRun,
         fAmplitude := 5.0, fOffset := 0.0, fFreq := 2.0, fPhase0 := 0.0,
         fTaskCycle := 0.01, fHoldValue := 0.0, bClampOut := TRUE,
         fOutMin := -6.0, fOutMax := 6.0,
         fOut => fShakeSp, fPhaseDeg => fPhase, uCycleCnt => nCycles);
```

**要点 / Notes**：
- **相位采样与拍号对应（D-15 修复后显式约定）**：`f = 1 Hz`、`dt = 0.25 s` 时每拍相位增量 90°；**第 1 拍（进态拍）输出 `φ0` 对应值，第 2 拍才到 `φ0 + 90°`** —— 即存在**一拍固有延迟**。写验收向量与上层相位对齐时必须按此口径，否则会得到「差一拍」的系统性偏差。
- **累加而非绝对时间乘频率**：累加式不受任务周期抖动影响，长时间运行不产生相位漂移。
- **回绕用减法不用取模**：`φ ≥ 360° → φ -= 360°`，避 LREAL 取模的平台差异；用 WHILE + `DL_MAX_WRAP = 64` 防死锁（欠采样时需一次减多个整圈）。
- **失能 / 频率 0 均冻结相位不归零**：归零会让现场看到输出突跳到偏置，误判为故障；重新使能从原相位继续，保证疲劳试验相位连续。
- **故障锁存解除条件**：参数回到有限值**且**收到 `bResetPhase` 上升沿，二者缺一不可。

---

## 24. FB_DL_SawtoothGenerator ｜ 对称度参数化锯齿 / 三角波（R10，v1.0.1）

**定位 / Positioning**：以单一**对称度**参数实现连续波形族——`fSymmetry → 1` 为纯锯齿（快速回落），`= 0.5` 为对称三角，中间值为非对称三角。用于伺服往复扫描、涂布摆杆试运行、阀门全行程循环老化、料仓料位模拟。

**关于「不是巨无霸块」/ Not a mode-monolith**：对称度是**连续物理参数**（上升段占周期比例），不是离散模式枚举；块内没有按模式分叉的职责差异，故不违反「禁止用 MODE 参数合并多变体」的禁令。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| `bEnable` | BOOL | IN | TRUE | 使能，FALSE 时输出保持值并冻结相位 [−] / Enable |
| `bResetPhase` | BOOL | IN | — | 相位复位，上升沿把周期内相位归零 [−] / Phase reset |
| `fPeriod` | LREAL | IN | 1.0 | 波形周期，域 1 ms~3600 s [s] / Waveform period |
| `fSymmetry` | LREAL | IN | 0.5 | 上升段占周期比例，域 0.01~0.99，0.5 为对称三角 [−] / Rising fraction |
| `fLow` | LREAL | IN | 0.0 | 波形下限（谷值）[工程单位] / Waveform lower bound |
| `fHigh` | LREAL | IN | 100.0 | 波形上限（峰值）[工程单位] / Waveform upper bound |
| `fTaskCycle` | LREAL | IN | 0.01 | 任务周期，域 1 ms~1 s [s] / Task cycle time |
| `fHoldValue` | LREAL | IN | 0.0 | 失能或故障时的输出值 [工程单位] / Hold value |
| `fOut` | LREAL | OUT | — | 波形输出，值域 `fLow~fHigh` [工程单位] / Waveform output |
| `fPhasePct` | LREAL | OUT | — | 当前周期内相位，域 0~100 [百分比] / In-cycle phase |
| `bRising` | BOOL | OUT | — | 当前处于上升段为 TRUE [−] / TRUE while rising |
| `uCycleCnt` | UDINT | OUT | — | 完整周期计数 [个] / Completed cycle counter |
| `bRunning` | BOOL | OUT | — | 运行中 [−] / TRUE while running |
| `uErrorId` | UDINT | OUT | — | 事件码：`1C01~1C03` 周期/对称度钳位与区间抬升（信息级）/ `1C10` 参数非有限·回绕超限·非法状态（故障级）/ Event code |
| `bError` | BOOL | OUT | — | 故障锁存 [−] / Fault latch |

### 调用示例 / Example

```iecst
VAR
    fbScan : FB_DL_SawtoothGenerator;   // 阀门全行程循环 / Valve full-stroke cycle
    fCmd   : LREAL;                     // 阀位指令 [%] / Valve command
    bUp    : BOOL;                      // 上升段标志 / Rising segment flag
END_VAR

// 10 s 周期、对称度 0.5（对称三角）、0~100 %，用于阀门老化台
fbScan(bEnable := bAgeTestOn, fPeriod := 10.0, fSymmetry := 0.5,
       fLow := 0.0, fHigh := 100.0, fTaskCycle := 0.01, fHoldValue := 0.0,
       fOut => fCmd, bRising => bUp);
```

**要点 / Notes**：
- **相位采样约定（D-16 修复后）**：与 Sine 同为一拍固有延迟。`幅值 100、对称度 0.5、周期 4 拍` 的逐拍序列是 `0 → 50 → 100 → 50`（第 1 拍输出下限、第 3 拍到峰值）。规格原向量「第 1 拍 50、第 3 拍 50」与实现矛盾，已按实现改写并新增采样约定段。
- **对称度收窄到 0.01~0.99**：保留极窄的另一段，避免分段换算出现除零（该收窄为设计登记项，非缺陷）。
- **高低值区间修正**：`fHigh − fLow < 1 µm` 时把上限抬到 `fLow + 1 µm` 并置 `1C03`，保证分段斜率可算。
- **相位半开区间**：周期内相位取 `[0, 1)`，回绕用 WHILE + `DL_MAX_WRAP` 防死锁；先判段再算值（上升段分母 = 对称度、下降段 = 1 − 对称度，二者均已被钳位）。

---

## 25. FC_DL_CoilDiameterCalc ｜ 卷径瞬时反算（R10，v1.0.0）

**定位 / Positioning**：由「材料线速度 + 卷轴转速 + 传动比」反算瞬时卷径 `D = v · i / (π · n)`，并同时给出卷径变化率与相对卷芯的累计层数。是收放卷张力控制（`T = F·D/2`）、线速度匹配、排线节距计算的数据源头。

**与同类组件选型 / Selection**：只需瞬时几何反算（无记忆）本件；需要层厚积分递推 + 排线轴执行选 `FB_DL_WindingTraverse`（DL_Motion）。两者**零代码调用、互为校验**——可把本件结果注入该块的 `fDiaInjected` 做比对。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | BOOL | RET | — | 本次计算有效（无钳位/打滑修正/低速保持）= TRUE / TRUE when no clamp, slip correction or hold |
| `fLineSpeed` | LREAL | IN | 0.0 | 材料线速度，域 0~3000 [米每分] / Material line speed |
| `fShaftRpm` | LREAL | IN | 0.0 | 卷轴转速，域 0~6000，低于 0.5 视为停机 [转每分] / Shaft speed |
| `fGearRatio` | LREAL | IN | 1.0 | 卷轴对电机传动比，域 0.01~1000，1.0 为直连 [−] / Gear ratio |
| `fCoreDia` | LREAL | IN | 0.100 | 卷芯（纸管）直径，域 0.01~1.0 [米] / Core diameter |
| `fThickness` | LREAL | IN | 0.0001 | 材料厚度，域 1 µm~10 mm，层数换算用 [米] / Material thickness |
| `fPrevDia` | LREAL | IN | 0.0 | 上拍卷径，0 表示无历史（变化率出口置 0）[米] / Previous diameter |
| `fTaskCycle` | LREAL | IN | 0.01 | 任务周期，域 1 ms~1 s，变化率换算用 [s] / Task cycle time |
| `bFilterEn` | BOOL | IN | TRUE | 一阶低通使能，抑制编码器量化噪声 [−] / Low-pass enable |
| `fFilterTau` | LREAL | IN | 1.0 | 低通时间常数，域 0.1~10 [s] / Low-pass time constant |
| `fDia` | LREAL | OUT | — | 估算卷径，低通使能时为滤波后的值 [米] / Estimated diameter |
| `fDiaRaw` | LREAL | OUT | — | 未滤波原始卷径，用于诊断与比对 [米] / Unfiltered diameter |
| `fDiaRate` | LREAL | OUT | — | 卷径变化率，正值为收卷增大 [米每秒] / Diameter rate |
| `fLayerCount` | LREAL | OUT | — | 相对卷芯的累计层数，由厚度推算 [层] / Layer count |
| `bValid` | BOOL | OUT | — | 计算有效，任一钳位或修正事件为 FALSE [−] / TRUE when no clamping or correction |
| `uErrorId` | UDINT | OUT | — | 事件码：`1D01~1D04 / 1D10`（均信息级）/ Event code |

### 调用示例 / Example

```iecst
VAR
    fDiaNow  : LREAL;    // 当前卷径 [米] / Current diameter
    fDiaRaw  : LREAL;    // 未滤波卷径 [米] / Raw diameter
    fRate    : LREAL;    // 卷径变化率 [米每秒] / Diameter rate
    fLayers  : LREAL;    // 层数 [层] / Layer count
    bDiaOk   : BOOL;     // 计算有效 / Calculation valid
    uDiaErr  : UDINT;    // 事件码 / Event code
    fPrevDia : LREAL;    // 上拍卷径（调用方持有）/ Previous diameter held by caller
END_VAR

bDiaOk := FC_DL_CoilDiameterCalc(fLineSpeed := fWebSpeed, fShaftRpm := fWinderRpm,
                                 fGearRatio := 12.5, fCoreDia := 0.152, fThickness := 0.000012,
                                 fPrevDia := fPrevDia, fTaskCycle := 0.01,
                                 bFilterEn := TRUE, fFilterTau := 1.0,
                                 fDia => fDiaNow, fDiaRaw => fDiaRaw,
                                 fDiaRate => fRate, fLayerCount => fLayers,
                                 bValid => bDiaOk, uErrorId => uDiaErr);
fPrevDia := fDiaNow;    // 状态回写必须在调用之后
```

**要点 / Notes**：
- **低速保护是核心工程语义**：转速低于 0.5 rpm 时编码器低频量化会让反算卷径跳动到毫米级，此时**沿用 `fPrevDia`** 而非归零——停机瞬间卷径突然归零会让张力给定瞬间飙到上限，是现场最常见的事故源。
- **卷芯保护**：反算卷径小于卷芯直径说明打滑或测速错，按卷芯直径修正并置 `1D04`，绝不把几何上不可能的值下发。
- **首拍无滞后（R19 精神）**：`fPrevDia = 0` 时直接取原始值，不从 0 缓慢爬升。
- **变化率次序**：先算 `(fDia − fPrevDia)/dt` 再更新历史值；次序颠倒会得到恒 0。
- **状态在调用方**：这是 FC，`fPrevDia` 必须由调用方每拍回写（见示例最后一行），忘记回写等于每拍首拍。

---

## 26. FC_DL_AirDensity ｜ 湿空气密度（R10，v1.0.0）

**定位 / Positioning**：由干球温度、绝对大气压、相对湿度求湿空气密度（kg/m³）。Magnus-Tetens 饱和蒸汽压 + 干/湿分压叠加 `ρ = p_d/(R_d·T) + p_v/(R_v·T)`。用于风量-质量流量换算、风机选型校核、烘干/涂布热风焓湿计算。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | BOOL | RET | — | 入参域合法且无修正事件 = TRUE / TRUE when domain legal and no correction |
| `fTempC` | LREAL | IN | 20.0 | 干球温度，域 −40~120 [摄氏度] / Dry-bulb temperature |
| `fPressPa` | LREAL | IN | 101325.0 | 绝对大气压，域 50000~120000 [帕] / Absolute pressure |
| `fRh` | LREAL | IN | 50.0 | 相对湿度，域 0~100 [百分比] / Relative humidity |
| `fDensity` | LREAL | OUT | — | 湿空气密度 [千克每立方米] / Moist air density |
| `fSatPressPa` | LREAL | OUT | — | 饱和蒸汽压，诊断与复用出口 [帕] / Saturation vapour pressure |
| `fVapPressPa` | LREAL | OUT | — | 水蒸气分压 [帕] / Water vapour partial pressure |
| `bValid` | BOOL | OUT | — | 入参域全部合法且无修正事件 [−] / TRUE when domain legal |
| `uErrorId` | UDINT | OUT | — | 事件码：`1E01~1E04 / 1E10`（均信息级）/ Event code |

### 调用示例 / Example

```iecst
VAR
    fRho      : LREAL;   // 湿空气密度 [kg/m³] / Moist air density
    fPsat     : LREAL;   // 饱和蒸汽压 [Pa] / Saturation pressure
    bRhoOk    : BOOL;    // 有效 / Valid
    uRhoErr   : UDINT;   // 事件码 / Event code
END_VAR

bRhoOk := FC_DL_AirDensity(fTempC := fDuctTempC, fPressPa := fBaroPa, fRh := fDuctRh,
                           fDensity => fRho, fSatPressPa => fPsat,
                           bValid => bRhoOk, uErrorId => uRhoErr);

// 工况体积流量 → 质量流量：m_dot [kg/s] = Q [m³/s] × ρ
fMassFlow := (fVolFlowM3h / 3600.0) * fRho;
```

**要点 / Notes**：
- **数值口径**：`T = 15 ℃、P = 101325 Pa、RH = 0 %` → `ρ ≈ 1.2250 kg/m³`（标准大气值，已复算）；`psat` 用 Magnus 系数 `A = 17.62 / B = 243.12 / C = 611.2 Pa`。
- **分母恒正性**：`243.12 + T` 在 `T > −243 ℃` 恒正，工况域内不可能为 0，无需除零守卫；`p_v = RH·p_sat` 由 `MAX(0, …)` 防负。
- **精度承诺收窄**：仅承诺 −10~50 ℃ 域内可用，超出域标「趋势参考」（R11 留档）；域外仍照算，但 `bValid = FALSE`。
- **密度钳位** 0~20 kg/m³（覆盖高压低温极端工况），负密度一律钳到 0。

---

## 27. FB_DL_R2rEwmaTuner ｜ 批级工艺参数自动微调（Run-to-Run，R11，v1.0.0）

**定位 / Positioning**：**批级**离散更新（一个批次只动一次参数）。每批采集一次实测值 → 与目标求偏差 → 经 EWMA 平滑 → 乘工艺增益倒数折算成参数修正量 → 叠加到历史参数 → 参数域钳位 → 回写下发值。典型场景：镀膜/刻蚀膜厚、注塑尺寸、涂布面密度、烧结密度等「逐批微调、不允许一次大改」的工艺。

**时间尺度边界 / Timescale boundary**：`FB_DL_PidController` 是**拍级**连续闭环、`FB_DL_RateLimiter` 限信号变化率、本件是**批级**（批次间隔通常是分钟到小时级，差三到四个数量级）。三件不可互替。本件刻意**不复用** `DL_MathData` 的滤波件：EWMA 与限幅全部内联，避免拍级滤波语义与批级更新语义混淆。

**双约束次序 / Dual clamp order（次序固定）**：① 先限**单次修正量**（`±fCorrectionLim`，工艺侧安全——不允许单批大幅跃迁）；② 再限**参数域**（`fParamMin ~ fParamMax`，设备侧安全）。次序颠倒会让「参数到界」被误报成「修正被限」，现场无法区分根因。

**首样本直取 / First-sample take-over**：历史无 EWMA 时第一批直接取本批偏差，**不让 0 参与平均**（否则前若干批严重偏置）。判据为 `bHasEwma`，置 `1F02` 留痕。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | BOOL | IN | `FALSE` | — | 使能，`FALSE` 时输出保持上次参数 / Enable; FALSE holds the last parameter |
| `bReset` | BOOL | IN | `FALSE` | — | 上升沿清 EWMA 与故障，**参数保持** / Rising edge clears EWMA and fault, keeps the parameter |
| `bNewLot` | BOOL | IN | `FALSE` | — | 新批次标志，上升沿开启一次批事务（一个批次只允许一个沿）/ New lot, one edge per lot |
| `fMeasure` | REAL | IN | `0.0` | 工艺单位 | 本批实测值（如膜厚 nm），非有限值判故障 / Measured value of this lot |
| `fTarget` | REAL | IN | `0.0` | 同测量单位 | 目标值 / Target value |
| `fLambda` | REAL | IN | `0.30` | — | EWMA 权重，域 0~1，越界双向钳位并置 `1F01` / EWMA weight, clamped both ways |
| `fGainInv` | REAL | IN | `1.0` | 参数单位/测量单位 | 工艺增益倒数；0 表示不修正 / Inverse process gain; zero disables correction |
| `fCorrectionLim` | REAL | IN | `1.0` | 参数单位 | 单次修正限幅，取绝对值；0 表示只审计不动作 / Per-lot correction limit |
| `fParamMin` | REAL | IN | `0.0` | 参数单位 | 参数下限，与上限对调时自动修复 / Parameter lower bound |
| `fParamMax` | REAL | IN | `100.0` | 参数单位 | 参数上限，等于下限表示参数被钉死 / Parameter upper bound |
| `fParamInit` | REAL | IN | `50.0` | 参数单位 | 初始参数，**仅首扫装载一次** / Initial parameter, first scan only |
| `fParamOut` | REAL | OUT | `0.0` | 参数单位 | 下发工艺参数，恒等于历史生效参数 / Output parameter |
| `fEwmaDev` | REAL | OUT | `0.0` | 测量单位 | 平滑后偏差，本批算完保持到下批 / Smoothed deviation |
| `bCorrected` | BOOL | OUT | `FALSE` | — | 本批已修正**单拍**脉冲 / One-shot correction pulse |
| `bAtLimit` | BOOL | OUT | `FALSE` | — | 修正量或参数触限，逐拍重算（非故障）/ At limit, recomputed each scan |
| `uLotCount` | UDINT | OUT | `0` | 批 | 已处理批次数，饱和累加，**复位不清零** / Lot counter, saturating |
| `eState` | E_DL_R2rState | OUT | `eIdle` | — | `eIdle` 0 / `eReady` 10 / `eCompute` 20 / `eApply` 30 / `eFault` 99 / Current state |
| `bError` | BOOL | OUT | `FALSE` | — | 故障锁存，**仅 `eFault` 态置位**（信息级码不置位）/ Latched fault |
| `uErrorId` | UDINT | OUT | `0` | — | 事件 / 故障码（`0002_1Fxx`），0 = 无 / Event or fault code |
| `stHist` | ST_DL_R2rHistory | IN_OUT | — | — | 跨周期批历史（`fLastParam` / `fLastEwma` / `bHasEwma` / `afDevBuf[1..10]` / `nBufIdx`），调用方持有并可持久化 / Persistent batch history |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0002_1F01` | 信息级 | EWMA 权重 λ 越出 0~1，已双向钳位 | 查配方里的 λ 是否被写成百分数（如 30 而非 0.3） |
| `0002_1F02` | 信息级 | 历史无 EWMA 样本，本批按首样本直取 | 正常现象（首个批次或刚复位后）；连续出现说明 `stHist` 未被持久化 |
| `0002_1F03` | 信息级 | 单次修正量达限幅，已钳到 ±`fCorrectionLim` | 偏差持续偏大时应排查工艺漂移根因，而不是调大限幅 |
| `0002_1F10` | 故障级 | 实测值 / 目标值 / 增益倒数非有限值，拒绝本批并锁存 | 查测量通道与配方下发；参数保持不变，修好输入后给 `bReset` 沿 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ThicknessR2R
VAR
    fbTuner         : FB_DL_R2rEwmaTuner;    // Run-to-Run 微调实例 / R2R tuner
    stR2rHist       : ST_DL_R2rHistory;      // 批历史（配方域持久化）/ Batch history
    bLineReady      : BOOL := TRUE;          // 产线就绪 / Line ready
    bLotDonePulse   : BOOL;                  // 单批完成脉冲 / Lot done pulse
    bTunerReset     : BOOL;                  // 微调复位 / Tuner reset
    fThicknessMeas  : REAL := 100.0;         // 本批实测膜厚 [纳米] / Measured thickness
    fThicknessTarget: REAL := 100.0;         // 目标膜厚 [纳米] / Target thickness
    fFurnaceParam   : REAL;                  // 下发工艺参数 [参数单位] / Output parameter
    bCorrected      : BOOL;                  // 本批已修正单拍 / Corrected pulse
    bAtLimit        : BOOL;                  // 触限提示 / At limit
    uLotCount       : UDINT;                 // 已处理批次 / Lot counter
    bTunerErr       : BOOL;                  // 故障 / Fault
    uTunerErrId     : UDINT;                 // 事件码 / Event code
END_VAR

// 每周期无条件调用；stHist 由本程序持有，跨批次不丢 EWMA
fbTuner(bEnable := bLineReady, bReset := bTunerReset, bNewLot := bLotDonePulse,
        fMeasure := fThicknessMeas, fTarget := fThicknessTarget,
        fLambda := 0.30, fGainInv := 2.0, fCorrectionLim := 0.50,
        fParamMin := 10.0, fParamMax := 90.0, fParamInit := 50.0,
        fParamOut => fFurnaceParam, bCorrected => bCorrected,
        bAtLimit => bAtLimit, uLotCount => uLotCount,
        bError => bTunerErr, uErrorId => uTunerErrId,
        stHist := stR2rHist);

// 下发值只从 fParamOut 取，禁止在外部再叠一次限幅
fFurnaceParam := fbTuner.fParamOut;
END_PROGRAM
```

**要点 / Notes**

- **一个批次只给一个 `bNewLot` 沿**：块内 `eCompute` / `eApply` 各驻留一拍，同一批次物理上不可能重复修正；若上游给了多个沿，会变成多批。
- **`fGainInv` 是「参数单位 / 测量单位」的倒数**：工艺增益变大时应**减小**该值；符号错了会越调越偏，调试期建议先给 0.1 倍保守值。
- **`fCorrectionLim = 0` 是合法组态**（只审计不动作），此时 `bAtLimit` 常置位属正常，不要把 `bAtLimit` 当故障。
- **`bReset` 不回初始参数**：只清 EWMA 与故障，参数保持历史值；要回初始值请在复位后重新走首扫装载路径（`fParamInit` 仅首扫生效）。
- **`uLotCount` 复位不清零**：可用来与产能/追溯系统对齐；饱和累加（`16#FFFF_FFFE` 封顶）。

---

## 28. FC_DL_WaterEnthalpy ｜ 液态水比焓与平均比热（R12，v1.0.0）

**定位 / Positioning**：按「比热随温度变化」的三次多项式积分给出液态水比焓（0 ℃ 基准，kJ/kg），同时输出 0 ℃ 到当前温度的**平均比热**。服务对象是热水/冷冻水系统的能量结算、板换两侧焓差计算、蓄能罐容量核算。

**域与精度 / Domain and accuracy**：温度域 **0~150 ℃**，域外一律返回 0.0 且 `bValid = FALSE`——**绝不把域外温度夹到边界再照算**（把 200 ℃ 的蒸汽按 150 ℃ 的液水结算属静默错误）。0~100 ℃ 与 IAPWS-IF97 饱和液焓偏差优于 0.3 个百分点，100~150 ℃ 优于 0.8 个百分点；**仅适用液态水**，不得用于蒸汽、过冷水与冰水混合物。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fTempC` | `REAL` | IN | `0.0` | ℃ | 水温，域 0~150 / Water temperature in degrees Celsius |
| `bUseMeanCp` | `BOOL` | IN | `FALSE` | — | `TRUE` 时对平均比热出口做零值兜底（`fCpMean ≤ 0` 时取一次项系数）/ Uses the mean cp output with a zero fallback |
| `fEnthalpy` | `REAL` | OUT | — | kJ/kg | 比焓，0 ℃ 基准 / Specific enthalpy, zero degree reference |
| `fCpMean` | `REAL` | OUT | — | kJ/(kg·K) | 0 ℃ 到当前温度的平均比热 / Mean specific heat from zero |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code |
| `bValid` | `BOOL` | OUT | — | — | 温度在域内为真 / Temperature inside the domain |

状态枚举：无（纯函数）。函数返回值：`REAL`，等于 `fEnthalpy`。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0002_2101` | 信息级 | 水温越 0~150 ℃ 域，已拒绝（返回 0.0 且 `bValid` 为假），不外插、不夹取 | 检查测温点是否串到蒸汽侧或冰水侧；域外应改走对应介质模型 |
| `0002_2102` | 信息级 | 温度落在零度点，平均比热退化为一次项系数（分母保护生效） | 属事实性提示：0 ℃ 时分母为零，平均比热无统计意义，只能取零度附近比热 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_WaterEnergyMeter
VAR
    fTempIn     : REAL := 55.0;            // 进水温度 [℃] / Supply temperature
    fTempOut    : REAL := 45.0;            // 回水温度 [℃] / Return temperature
    fFlowKgS    : REAL := 1.2;             // 质量流量 [kg/s] / Mass flow
    fHIn        : REAL;                    // 进水比焓 [kJ/kg] / Supply enthalpy
    fHOut       : REAL;                    // 回水比焓 [kJ/kg] / Return enthalpy
    fCpIn       : REAL;                    // 进水平均比热 / Supply mean cp
    fCpOut      : REAL;                    // 回水平均比热 / Return mean cp
    uInErr      : UDINT;                   // 事件码 / Event code
    uOutErr     : UDINT;                   // 事件码 / Event code
    bInOk       : BOOL;                    // 进水在域内 / Supply in range
    bOutOk      : BOOL;                    // 回水在域内 / Return in range
    fInRet      : REAL;                    // 返回值 / Return value
    fOutRet     : REAL;                    // 返回值 / Return value
    fPowerKw    : REAL;                    // 热功率 [kW] / Thermal power
    bMeterOk    : BOOL;                    // 结算有效 / Settlement valid
END_VAR

fInRet  := FC_DL_WaterEnthalpy(fTempC := fTempIn,  bUseMeanCp := TRUE,
                               fEnthalpy => fHIn,  fCpMean => fCpIn,
                               uErrorId => uInErr,  bValid => bInOk);
fOutRet := FC_DL_WaterEnthalpy(fTempC := fTempOut, bUseMeanCp := TRUE,
                               fEnthalpy => fHOut, fCpMean => fCpOut,
                               uErrorId => uOutErr, bValid => bOutOk);

// 一侧越域则整笔结算作废（不能用 0 焓参与差分成「满功率」）
bMeterOk := bInOk AND bOutOk;
IF bMeterOk THEN
    fPowerKw := fFlowKgS * (fHIn - fHOut);
ELSE
    fPowerKw := 0.0;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **越域不夹取**：这是本件与「钳位后照算」类组件的关键差别。水在 100 ℃ 以上是汽水混合物，把 120 ℃ 按液态水结算会系统性高估焓值，故域外直接拒。
- **`bUseMeanCp` 的真实语义**：本件**总是**计算并输出 `fCpMean`；该引脚只决定「`fCpMean` 非正时是否做零值兜底」。传 `FALSE` 也能读到平均比热，但若为零需调用方自行处理。
- **平均比热的分母**：平均比热 = 比焓 / 温度，0 ℃ 时温度为 0、无统计意义，故零度点显式置 `2102` 并取零度附近比热。这是**事实性**提示，不是开关派生。
- **单精度中间量**：与既有湿空气焓件同一精度口径，150 ℃ 时三次项约 3.4E6，七位有效数字仍有余量。若需更高精度请勿在本件上叠加二次修正，改用外部物性表。

---

## 29. FB_DL_ValveCharacteristic ｜ 调节阀固有特性补偿（R12，v1.0.1）

**定位 / Positioning**：把「期望流量百分比」按调节阀的**固有流量特性**折算成「阀位百分比给定」，并完成行程限幅、输出死区与可调比域守护。服务对象是热水/蒸汽调节阀、化工配料阀：线性阀在小开度段过于灵敏（增益过大）、等百分比阀在低负荷段过于迟钝，用错特性会让同一条 PID 参数在不同负荷点表现迥异。

**三种特性 / Three characteristics**：`eLinear`（阀位与流量成正比）／`eEqualPercent`（单位阀位变化引起的流量变化与当前流量成正比，可调比 R 决定低端斜率）／`eQuickOpen`（小阀位即获大流量，后段渐平）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时阀位**保持上次值** / Enable, holds the last travel when FALSE |
| `bReset` | `BOOL` | IN | — | — | 上升沿清故障回空闲 / Rising edge clears the fault |
| `fFlowCmd` | `REAL` | IN | `0.0` | % | 期望流量，域 0~100 / Desired flow in percent |
| `eChar` | `E_DL_ValveCharKind` | IN | `eEqualPercent` | — | 固有特性：`eLinear` 0 ／ `eEqualPercent` 10 ／ `eQuickOpen` 20 / Inherent characteristic |
| `fRangeability` | `REAL` | IN | `30.0` | — | 可调比，域 2~100，越界钳位 / Rangeability, clamped to 2..100 |
| `fMinTravel` | `REAL` | IN | `0.0` | % | 最小阀位，域 0~100 / Minimum travel |
| `fMaxTravel` | `REAL` | IN | `100.0` | % | 最大阀位，域 0~100 / Maximum travel |
| `fDeadband` | `REAL` | IN | `0.2` | % | 输出死区，变化小于此值保持上次 / Output deadband |
| `fTravel` | `REAL` | OUT | — | % | 阀位给定，域 `fMinTravel`~`fMaxTravel` / Travel command |
| `bSaturated` | `BOOL` | OUT | — | — | 输出被上下限或可调比下限截断 / Output clamped |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `2010`~`2012` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_ValveCharState` | OUT | — | — | `eIdle` 0 ／ `eActive` 10 ／ `eFault` 99 / Current state |

状态枚举：`E_DL_ValveCharKind`（特性）/ `E_DL_ValveCharState`（`eIdle` 0 ／ `eActive` 10 ／ `eFault` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0002_2001` | 信息级 | 输出被行程下限截断（含流量给定越下限钳位），`bSaturated` 置位 | 下限抬高通常是防冻/防最小流量；确认是否为有意限制 |
| `0002_2002` | 信息级 | 输出被行程上限截断（含流量给定越上限钳位），`bSaturated` 置位 | 长期饱和说明阀门选型偏小或工艺负荷超设计 |
| `0002_2003` | 信息级 | 输出变化小于死区，保持上次阀位 | 死区压抖动，但过大会造成稳态偏差；按执行器分辨率设 |
| `0002_2010` | 故障级 | 行程配置非法（上下限越 0~100 或下限 > 上限），锁存并保持上次阀位 | **不自动交换上下限**：倒置几乎总是填反，交换会掩盖错误 |
| `0002_2011` | 故障级 | 可调比对数分母的二次守卫触发（正常钳位下不可达） | 说明有人绕过钳位直接注入可调比；检查是否有外部赋值 |
| `0002_2012` | 故障级 | 非法特性枚举兜底，锁存并保持上次阀位 | 检查在线修改与库版本是否匹配 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_HeatingValveTrim
VAR
    fbValve     : FB_DL_ValveCharacteristic;  // 阀特性实例 / Valve characteristic instance
    bLoopRun    : BOOL := TRUE;               // 回路运行 / Loop running
    bValveReset : BOOL;                       // 复位 / Reset
    fFlowDemand : REAL := 42.0;               // PID 输出的流量需求 [%] / Flow demand
    fTravelCmd  : REAL;                       // 阀位给定 [%] / Travel command
    bClamped    : BOOL;                       // 被截断 / Clamped
    bValveFault : BOOL;                       // 故障 / Fault
    uValveErr   : UDINT;                      // 事件码 / Event code
    eValveState : E_DL_ValveCharState;        // 状态观测 / State
    bTravelSent : BOOL;                       // 给定可信 / Command trustworthy
END_VAR

fbValve(bEnable := bLoopRun, bReset := bValveReset,
        fFlowCmd := fFlowDemand,
        eChar := E_DL_ValveCharKind.eEqualPercent, fRangeability := 50.0,
        fMinTravel := 5.0, fMaxTravel := 95.0, fDeadband := 0.2,
        fTravel => fTravelCmd, bSaturated => bClamped,
        bError => bValveFault, uErrorId => uValveErr, eState => eValveState);

// 故障时给定保持上次值且不可信；把「保持」当「闭环有效」会让 PID 继续积分
bTravelSent := (NOT bValveFault) AND (eValveState = E_DL_ValveCharState.eActive);
END_PROGRAM
```

**要点 / Notes**

- **不做阀位回零**：v1.0.1 修的正是这条（范式 R43）。原实现投运与故障复位首拍把阀位强制置为行程下限，**复位当拍阀门直冲最小开度**——水锤、批量扰动，且与本件「突跳比保持更危险」的契约自相矛盾。现在改为「保持上次阀位并夹进生效行程」。
- **可调比影响低端而非高端**：等百分比特性在流量低于 `1/R` 时阀位归零（记 `2001`）。R 取 30 意味着流量低于 3.3% 时阀门全关，这是等百分比阀的物理特性，不是实现缺陷。R 填太大会让低负荷段完全失去调节能力。
- **死区只压抖动**：死区比较用容差不用判等，且**内部限幅结果不变**——死区只影响出口，不影响下次比较的基准（基准随实际输出更新）。
- **故障态不做任何折算**：`eFault` 保持上次阀位、只认复位沿。不要在故障态继续喂 `fFlowCmd`，指望它自行恢复。
- **规格偏离留痕**：计划正文提到 `2004`~`2006` 三个「输入钳位」码，但码位表只分配了 `2001`~`2003` 与 `2010`~`2012`。按「码位表为准、不得自创」的纪律，流量越界钳位并入 `2001`/`2002`，整定参数钳位不单独置码（详见源码头注释）。

---
---

## 30. FB_DL_FoulingResistanceEstimator ｜ 换热器污垢热阻趋势估计（R13，v1.0.0）

**定位**：换热器本体退化算法底座——由热侧/冷侧进出口温度与体积流量算出换热量 Q、对数平均温差 LMTD 与实测传热系数 K，再由 K 与清洁态基准 K_clean 反算污垢热阻 Rf = 1/K − 1/K_clean；趋势窗内最小二乘拟合 Rf 增长斜率并给出清洗建议。**只做「算一个值 + 算一个趋势」**：不做 PID、不做阀门/泵控制、不做结垢成分与化学分析；不内置换热器几何模型与介质物性库，`fCp`/`fRho` 与 `K_clean` 全部由调用方按设备台账注入。

**数据纪律（本件核心）**：数据不可信（温差过小 / 流量过低 / 两侧热负荷不平衡 / 输入非有限）时**拒绝更新并保持上次有效值**——宁可不给数，也不给脏数（R42：判可用与取值同拍）。公式取公开传热学常识：Q = m·cp·ΔT、逆/顺流 LMTD、Rf = 1/K − 1/K_clean。

### 30.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能，FALSE 冻结更新并回空闲；复位通道不受其屏蔽 / Enable |
| `bReset` | `BOOL` | IN | — | — | 上升沿清趋势窗、清洗锁存与保持值 / Rising edge reset |
| `fTinHot` / `fToutHot` | `REAL` | IN | — | ℃ | 热侧进/出口温度，域 −50~300 / Hot side in/out temperatures |
| `fTinCold` / `fToutCold` | `REAL` | IN | — | ℃ | 冷侧进/出口温度，域 −50~300 / Cold side in/out temperatures |
| `fFlowHot` / `fFlowCold` | `REAL` | IN | — | m³/h | 热/冷侧体积流量，域 0~10000 / Hot/cold volumetric flows |
| `fCpHot` / `fCpCold` | `REAL` | IN | `4.18` | kJ/(kg·K) | 热/冷侧比热，域 0.5~10 / Specific heats |
| `fRhoHot` / `fRhoCold` | `REAL` | IN | `1000.0` | kg/m³ | 热/冷侧密度，域 1~2000 / Densities |
| `fArea` | `REAL` | IN | — | m² | 换热面积，域 > 0（除零保护对象）/ Heat transfer area |
| `fKClean` | `REAL` | IN | — | W/(m²·K) | 清洁态传热系数基准，域 > 0 / Clean-condition K |
| `bCounterFlow` | `BOOL` | IN | `TRUE` | — | 流型，TRUE 逆流 / FALSE 顺流；切换时趋势基准重置（2204）/ TRUE counter-flow |
| `fDtmMin` | `REAL` | IN | `2.0` | K | 最小可用温差，域 0.5~20 / Minimum usable LMTD |
| `fHeatBalTol` | `REAL` | IN | `0.10` | — | 两侧热负荷允许偏差比，域 0.02~0.5 / Heat balance tolerance |
| `fFlowMinRatio` | `REAL` | IN | `0.20` | — | 流量下限比例，域 0.05~0.9；比例基准为块内自学习峰值流量（投运以来观测最大值）——规格未给额定流量引脚，语义为「相对自身额定」/ Minimum flow ratio, self-learned reference |
| `tWindow` | `TIME` | IN | `T#1H` | — | 趋势窗长，域 5 min~24 h；时长到**或**样本数触顶（64）即结算重开 / Trend window |
| `tSamplePeriod` | `TIME` | IN | `T#10S` | ms | 调用周期，必须与实际任务周期一致 / Call period, must match the task |
| `fRfAlarm` | `REAL` | IN | `3.0E-4` | m²·K/W | 污垢热阻报警阈，域 1E-5~5E-3 / Rf alarm threshold |
| `fSlopeAlarm` | `REAL` | IN | `2.0E-5` | m²·K/(W·h) | 污垢增长速率阈，域 1E-7~1E-3 / Slope alarm threshold |
| `fQ` | `REAL` | OUT | — | kW | 热负荷两侧平均（保持语义）/ Mean heat duty, held |
| `fLmtd` | `REAL` | OUT | — | K | 对数平均温差（保持语义）/ LMTD, held |
| `fK` | `REAL` | OUT | — | W/(m²·K) | 实测传热系数，保持且夹 ≥ 0 / Measured K, held, clamped non-negative |
| `fRf` | `REAL` | OUT | — | m²·K/W | 污垢热阻 = 1/K − 1/K_clean（保持语义）/ Fouling resistance, held |
| `fRfSlope` | `REAL` | OUT | — | m²·K/(W·h) | 窗内趋势斜率（保持语义）/ Trend slope, held |
| `bValid` | `BOOL` | OUT | — | — | 本拍输出有效；数据质量不足时 FALSE / Valid this scan |
| `bCleanAdvice` | `BOOL` | OUT | — | — | 建议清洗（保持语义，复位沿清除）/ Cleaning advised |
| `eHealth` | `E_DL_Ne107Status` | OUT | — | — | NE107 健康态（类型引用自 DL_Device 契约件 `I_DL_DeviceHealth`）/ NE107 health |
| `uDiagCode` / `uErrorId` / `bError` | `UDINT` / `UDINT` / `BOOL` | OUT | — | — | 诊断码（单一优先级链）/ 故障码 / 故障标志 / Diagnostic and fault codes |
| `nUpdateCount` | `UDINT` | OUT | — | 次 | 有效更新次数 / Valid update counter |

**状态机 / State machine**（`E_DL_FoulingState`，同文件发布）：`eIdle(0)` 空闲 → `eValid(10)` 本拍可信 → `eTrend(20)` 样本 ≥ 3 斜率可算 → `eAdvice(30)` 建议清洗（锁存）→ `eFault(99)` 故障；非法值走 ELSE 兜底（2212）。

### 30.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0002_2201` | 信息级：LMTD 低于最小可用温差 / LMTD below usable limit | 降负荷工况常见；检查 `fDtmMin` 组态 |
| `16#0002_2202` | 信息级：流量低于下限比例 / Flow below minimum ratio | 比例基准为自学习峰值，投运初期门限自然宽松 |
| `16#0002_2203` | 信息级：两侧热负荷偏差超容差 / Heat balance exceeded | 查计量仪表与旁路泄漏 |
| `16#0002_2204` | 信息级：逆/顺流口径切换，趋势基准已重置 / Arrangement changed, trend reset | 切换后趋势窗重新累计，属正常而非故障 |
| `16#0002_2210` | 故障级：换热面积/清洁 K 非正或输入非有限 / Illegal area, clean K or non-finite input | 检查台账注入；需 `bReset` 退出 |
| `16#0002_2211` | 故障级：LMTD ≤ 0（温度交叉或流型用错）/ Non-positive LMTD | 核对流型 `bCounterFlow` 与温度接线 |
| `16#0002_2212` | 故障级：非法状态兜底 / Illegal state fallback | 复现后上报枚举被强制写入的路径 |

### 30.3 调用示例 / Example

```iecst
PROGRAM PRG_HxMonitoring
VAR
    fbFouling : FB_DL_FoulingResistanceEstimator;  // 污垢趋势实例 / Fouling estimator
    fThi, fTho, fTci, fTco : REAL;   // 四点温度 [degC] / Four temperatures
    fFh, fFc  : REAL;                // 两侧流量 [m3/h] / Flows
    fAreaEq   : REAL := 120.0;       // 换热面积 [m2] / Area from the datasheet
    fK0       : REAL := 1400.0;      // 清洁态 K [W/(m2 K)] / Clean K
    bHxRun    : BOOL;                // 运行使能 / Running
    bHxReset  : BOOL;                // 复位 / Reset
    fRfNow    : REAL;                // 当前热阻 / Current Rf
    bNeedClean: BOOL;                // 清洗建议 / Cleaning advised
END_VAR

(* 每周期无条件调用 *)
fbFouling(
    bEnable      := bHxRun,
    bReset       := bHxReset,
    fTinHot      := fThi,
    fToutHot     := fTho,
    fTinCold     := fTci,
    fToutCold    := fTco,
    fFlowHot     := fFh,
    fFlowCold    := fFc,
    fArea        := fAreaEq,
    fKClean      := fK0,
    bCounterFlow := TRUE,
    tWindow      := T#2H,
    tSamplePeriod:= T#10S);

fRfNow     := fbFouling.fRf;        // 保持语义：不可信拍保持上次值 / held value
bNeedClean := fbFouling.bCleanAdvice;
IF fbFouling.bError THEN
    ;   // 按 uErrorId 处理（2210/2211 需复位）
END_IF
END_PROGRAM
```

### 30.4 要点 / Notes

- **V1 口径**：热侧 90/70 ℃、冷侧 20/40 ℃、逆流、两侧 10 m³/h → 等温差时 LMTD 退化为算术平均 50.0 K、fQ ≈ 232.2 kW（规格记 49.7 K 属取整口径差，已在头注释偏离留档②）。
- **等温差退化**：LMTD 分母（对数比值）趋零时显式退化算术平均，不做 0 除。
- **首拍样本不进趋势**（R19）：上电首拍只装基准，不参与斜率；斜率最少需窗内 3 个样本（`eTrend` 起始条件）。
- **趋势窗双出口**：时长到或样本数触顶 64 即结算——触顶提前结算是为了避免「为凑时长丢分辨率」和「样本触顶后窗永远关不上」。
- **K > K_clean 时 Rf 归 0**：物理上 K 不可能超过清洁基准，测量噪声导致时按 0 处理（Rf 出口下限 0），不给负热阻。
- 清洗建议 `bCleanAdvice` 是保持位不是脉冲：判定后一直保持，只有复位沿清除——HMI 与维护排程读它不需抢拍。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_BumplessTransfer` | 手动末值按限斜率过渡到 PID 输出，手动期反算跟踪 | `fPidOut` / `fRateMax` / `fOut` |
| `FB_DL_GainScheduler` | 按调度变量落区间输出该段一组 PID 参数 | `fScheduleVar` / `fKp` / `fKi` |
| `FB_DL_NotchFilter` | 中心频率 + Q 可调二阶陷波，改参只重算系数、状态保留 | `fCenterFreq` / `fQuality` / `tSampleTime` |
| `FB_DL_ThermalI2tModel` | I²t 热容量累积，输出热态系数供过载降额 | `fCurrent` / `fTheta` |

> 用法要点：`BumplessTransfer` 不内联 PID（PID 输出由上层注入，避免两套积分器）；`NotchFilter` 的中心频率必须低于 0.45 倍采样频率，超了陷波会变放大器（本件已拦截并旁路）。


---


---

## R19 追加组件接口表（2026-11-16，本子库 4 件）

### `FB_DL_FlowSqrtExtract`
- **功能**：差压流量开方与低切切除（迟滞切除 + 阻尼）
- **输入引脚**：bEnable、bReset、fDp、fDpSpan、fFlowSpan、fCutPercent、fCutHystPercent、fDampCoef、tSampleTime、bSquareRoot（语义与单位见 .st 头注释）
- **输出引脚**：fFlow、bCutoff、bSaturated、uCutCount、eErr、bError、bValid
- **码位**：16#0002_2701 用 / 16#0002_2702 预留 ｜ 16#0002_2710 用 / 16#0002_2711 用 / 16#0002_2712 预留

### `FB_DL_RatioController`
- **功能**：比值控制器（从动量跟随主动量比值）
- **输入引脚**：bEnable、bReset、fMasterFlow、fRatio、fRatioMin、fRatioMax、fBias、fMasterLowLimit、fMasterLowSp、fOutMin、fOutMax、fRateMax、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：fSlaveSp、bMasterLow、bRatioClamped、bOutClamped、fEffectiveRatio、eErr、bError、bValid
- **码位**：16#0002_2801 用 / 16#0002_2802 预留 ｜ 16#0002_2810 用 / 16#0002_2811 用 / 16#0002_2812 用

### `FB_DL_LeadLagCompensator`
- **功能**：超前滞后补偿 Kc(1+T_lead·s)/(1+T_lag·s)，Tustin 离散化 + 改参保状态
- **输入引脚**：bEnable、bReset、fIn、fGain、tLeadTime、tLagTime、tSampleTime、fOutLimit（语义与单位见 .st 头注释）
- **输出引脚**：fOut、bBypass、bSaturated、uCoeffRev、eErr、bError
- **码位**：16#0002_2901 用 / 16#0002_2902 预留 ｜ 16#0002_2910 用 / 16#0002_2911 用 / 16#0002_2912 预留

### `FB_DL_AutoTuneRelay`
- **功能**：继电反馈自整定（描述函数 Ku + ZN/AH 四规则，五态机，撤继电最高危点）
- **输入引脚**：bEnable、bStart、bAbort、fPv、fSp、fRelayAmp、fRelayHyst、uCyclesRequired、uMinSamplesPerHalf、tMaxDuration、fStabTolPercent、eRule、tSampleTime（语义与单位见 .st 头注释）
- **输出引脚**：bRelayOut、bBusy、bDone、fOscAmp、tUltPeriod、fUltGain、fKp、fTi、fTd、uCycleDone、eErr、bError、bValid
- **码位**：16#0002_2A01 用 / 16#0002_2A02 预留 ｜ 16#0002_2A10 用 / 16#0002_2A11 用 / 16#0002_2A12 用
---

## R22 批次接口表（R22 追加 · 2 件 · 燃烧控制律）

### FB_DL_CrossLimitSelect ｜ 燃烧双交叉限幅（DL_Algo / ProcessControl）
- **输入引脚**：`fMasterOut`（%）、`fAirFlow`（Nm3/h）、`fGasFlow`（Nm3/h）、`fAirFuelRatio`（缺省 10.0）、`fLeadMargin`（倍 缺省 1.05，须 > 1.0）、`bAirLead`、`bEnable`
- **输出引脚**：`fAirSp`（%）、`fGasSp`（%）、`bLimited`、`fLimitMargin`（%）、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0002_2B01`（空气侧受限）/ `2B02`（燃气侧受限）｜ 故障 `2B10`（空燃比/裕度非法，双侧归零）/ `2B11`（非有限保持末值）/ `2B12`（兜底）
- **要点**：依赖收窄——迟滞与限幅内联等价实现（不引用 DL_Base/DL_MathData）。

### FB_DL_ExcessAirTrim ｜ 氧量修正（DL_Algo / ProcessControl）
- **输入引脚**：`fO2Meas`（%）、`fO2Target`（% 缺省 3.0）、`fO2Deadband`（% 缺省 0.3）、`fTrimLimit`（% 缺省 5.0）、`fTrimStep`（% 缺省 0.05）、`fLoadRate`（%/s）、`fRateFreeze`（%/s 缺省 2.0）、`tConfirm`（缺省 T#30S）、`bEnable`
- **输出引脚**：`fTrim`（%）、`bActive`、`bFrozen`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0002_2C01`（死区内不修正）/ `2C02`（负荷变化率超限已冻结）｜ 故障 `2C10`（参数非法）/ `2C11`（非有限保持末值）/ `2C12`（兜底）


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*

---

## 附录 · R25 批次接口表（2026-11-17，共 4 件）

> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。

### FB_DL_ParticleCounterStat ｜ 尘埃粒子计数器统计与等级判定（DL_Algo v1.0.0）
- **输入引脚**：`auCounts`（ARRAY[0..5] OF UDINT）、`fSampleVolL`（LREAL 缺省 1.0）、`bSamplePulse`（BOOL）、`fClassTarget`（LREAL 缺省 7.0）、`nConfirmSamples`（INT 缺省 3）、`tSampleTime`（TIME 缺省 T#1M）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`afConcM3`（ARRAY[0..5] OF LREAL）、`fClassMeasured`（LREAL）、`bClassOk`（BOOL）、`bOverLimit`（BOOL）、`bSampleLost`（BOOL）、`tSinceSample`（TIME）、`uSampleCount`（UDINT）、`uOverCount`（UDINT）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_ParticleStatState）
- **码位**：`16#0002_3301` ｜ `16#0002_3302` ｜ `16#0002_3310` ｜ `16#0002_3311`

### FB_DL_CoolingTowerApproachCalc ｜ 冷却塔逼近度计算与风机台数优化建议（DL_Algo v1.0.0）
- **输入引脚**：`fCondOutC`（LREAL）、`fAmbDryC`（LREAL）、`fRhPct`（LREAL）、`fPressPa`（LREAL 缺省 101325.0）、`nFanTotal`（INT）、`nFanRunning`（INT）、`fApproachTargetK`（LREAL 缺省 4.0）、`fApproachTolK`（LREAL 缺省 0.5）、`tMinStageTime`（TIME 缺省 T#5M）、`nWinSamples`（INT 缺省 10）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fWetBulbC`（LREAL）、`fApproachK`（LREAL）、`fApproachAvgK`（LREAL）、`nFanCmd`（INT）、`bIncReq`（BOOL）、`bDecReq`（BOOL）、`bNoFurtherGain`（BOOL）、`bWetBulbFault`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_ApproachState）
- **码位**：`16#0002_3401` ｜ `16#0002_3402` ｜ `16#0002_3410` ｜ `16#0002_3411`

### FB_DL_DuctStaticReset ｜ 风管静压设定重置（DL_Algo v1.0.0）
- **输入引脚**：`fWorstDamperPct`（LREAL）、`fStaticMinPa`（LREAL）、`fStaticMaxPa`（LREAL）、`fBandPct`（LREAL 缺省 10.0）、`fGainPaPerPct`（LREAL 缺省 2.0）、`fRatePaPerS`（LREAL 缺省 5.0）、`bFbValid`（BOOL 缺省 TRUE）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fStaticSetPa`（LREAL）、`bAtLimit`（BOOL）、`fErrPct`（LREAL）、`bFbInvalid`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_DuctStaticState）
- **码位**：`16#0002_3501` ｜ `16#0002_3502` ｜ `16#0002_3510` ｜ `16#0002_3511`

### FB_DL_DewpointReset ｜ 依据室内露点重置冷冻水供水温度设定（DL_Algo v1.0.0）
- **输入引脚**：`fRoomTempC`（LREAL）、`fRoomRhPct`（LREAL）、`fChwMinC`（LREAL 缺省 7.0）、`fChwMaxC`（LREAL 缺省 18.0）、`fDewMarginK`（LREAL 缺省 1.5）、`fRateKPerS`（LREAL 缺省 0.05）、`uDeltaTimeMs`（UDINT）、`bEnable`（BOOL）、`bReset`（BOOL）
- **输出引脚**：`fChwSetC`（LREAL）、`fDewPointC`（LREAL）、`fMarginK`（LREAL）、`bCondRisk`（BOOL）、`bAtMin`（BOOL）、`bAtMax`（BOOL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）、`eState`（E_DL_DewpointResetState）
- **码位**：`16#0002_3601` ｜ `16#0002_3602` ｜ `16#0002_3610` ｜ `16#0002_3611`

*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*
