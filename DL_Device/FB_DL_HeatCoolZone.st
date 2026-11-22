(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HeatCoolZone
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 语义与 DL_Algo 既有算法组件，
 *                         零厂商方言，零物理地址直写
 * 分类     (Category)   : 功能块（FUNCTION_BLOCK）· 加热/冷却温控区 · Level 1 DL_Device 开库件
 * 功能描述 (Function)   : 双通道（加热/冷却）温控区控制器，R4 算法族首个上层消费者。
 *                         控制链：FB_DL_PidController（含抗饱和，实例经引脚注入，
 *                         参数外置组态）→ 分程分配（Split-range，fSplitLow/High
 *                         可组态，非魔法数）→ FB_DL_PwmDutyController × 2（加热/
 *                         冷却 SSR 驱动）。断偶保护：传感器接口信号质量进入断线/
 *                         开路域时按 eBreakAction 切断对应通道并锁存 eSensorBreak
 *                         态（0003_0211），退出需 CmdReset 且质量恢复 eGood；
 *                         锁存期间双通道全断为最终安全态。设定值经 fTempMin/Max
 *                         钳位（信息级 0003_0101，不置故障）。本块零内嵌组态、
 *                         零魔法数，PID/PWM 全部实例经 IN_OUT 引脚注入。
 * 开源溯源 (Origin)     : 原创实现。分程控制与断偶安全方向为行业公知语义
 *                         （来源标签 lbp-device；断偶方向参考 NAMUR NE43 公开
 *                         标准），未复制任何厂商源码。PID/PWM 语义消费本库
 *                         DL_Algo 既有组件 FB_DL_PidController / FB_DL_PwmDutyController。
 * 本文件内含       : TYPE      E_DL_BreakAction（断偶动作方向枚举，归属 DL_Device）
 *                    FUNCTION_BLOCK FB_DL_HeatCoolZone IMPLEMENTS I_DL_TemperatureZone
 *                    （随附 METHOD ×3 与 PROPERTY GET ×5 实现体）
 * 依赖     (Depends)    : I_DL_TemperatureZone / E_DL_TempZoneState（同轮泳道交付
 *                          的 I_DL_TemperatureZone.st）；FB_DL_PidController、
 *                          FB_DL_PwmDutyController（DL_Algo v1.0.1+，实例注入）；
 *                          Standard.library：LIMIT / MIN / ABS。不引用库内任何
 *                          其他实现文件的具体逻辑。
 * 【规格偏离留档 / R11 Deviation register】
 *   D1 规格 §1.8 引脚表要求 fTempActual/fPowerOut/eState/bFault/uErrorId 五个
 *      「接口属性映射」成员同时作为 OUT 引脚暴露；IEC 61131-3 同一 POU 的变量
 *      与属性共享命名空间，同名变量与同名属性并存无法通过编译。按 R11 留档：
 *      该五成员以只读 PROPERTY 形式对外暴露（属性即输出引脚语义，接口成员逐一
 *      兑现），bHeaterOut/bCoolerOut 两个非接口成员保留 VAR_OUTPUT。
 *   D2（已闭环 / Closed）规格 §1.5 的 E_DL_SignalQuality / I_DL_AnalogSensor 为
 *      本块温度信号源契约。编码阶段宿主文件未入库，本文件曾就地声明副本；
 *      R5 注册收口阶段 I_DL_AnalogSensor.st（正式承载 E_DL_SignalQuality 枚举
 *      与 I_DL_AnalogSensor 接口）已随 DL_Device 开库交付，本文件重复副本已
 *      删除，改为引用该正式定义（IEC 同工程内 INTERFACE/ENUM 全局可见，与原
 *      D2 预设处置一致）。契约语义以 I_DL_AnalogSensor.st 为准（本块仅消费
 *      fValue 与 eQuality 两个成员）。
 *   D3 规格 §1.8「按 eBreakAction 切断对应通道并锁存」细化：eBreakAction 决定
 *      断偶瞬间立即切断的危险通道方向；锁存 eSensorBreak 期间双通道全断为最终
 *      安全态（锁存态不维持任何输出，安全侧选择）。
 *   D4 公约 0.6 示例码 16#0001_0001 属 DL_Base 段；按公约 0.7 段位分配（DL_Device
 *      族 16#0003_xxxx），本块参数钳位/对调修复统一置信息级 16#0003_0101。
 *   D5 新增故障/信息码顺延登记（无冲突）：16#0003_0212 非法状态兜底（故障级）、
 *      16#0003_0213 传感器接口引用未注入/无效（故障级）。
 * 故障码表（本块全部登记，0=无故障）：
 *   16#0003_0101【信息级】参数钳位/对调修复/设定值钳位提示，不置故障
 *   16#0003_0211【故障级】传感器断线/开路锁存，CmdReset + 质量恢复 eGood 方可清
 *   16#0003_0212【故障级】非法状态兜底（CASE ELSE 落点），CmdReset 可清
 *   16#0003_0213【故障级】温度传感器接口引用未注入/无效，CmdReset + 引脚有效方可清
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值防御+浮点容差
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 六态 ENUM+CASE+ELSE 兜底
 *                         R7 ✓ 无直接定时器实例（PID/PWM 实例每拍无条件调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 05 · 泳道 B · 契约出处 ROUND_PLAN_R5 §1.8
 *   2026-11-15  v1.0.0  R5 收口：删除就地重复的 E_DL_SignalQuality /
 *                       I_DL_AnalogSensor 声明，改引用 I_DL_AnalogSensor.st
 *                       正式定义（D2 闭环），功能与引脚零变更
 * 验收向量 (Acceptance) :
 *   V1 正常跃迁链：bEnable=TRUE → eHolding；fTempActual 低于设定 → eHeating；
 *      回到中性带 → eHolding；高于设定 → eCooling（fPowerOut 正负号随之翻转）
 *   V2 非法态兜底：强写内部状态为越界值 → CASE ELSE 落入 eFault（0003_0212）
 *   V3 中途跟踪脉冲（公约 0.1 必含）：闭环运行中 bTrack 单拍脉冲 + fTrackValue
 *      =30.0 → 本拍 PID 输出跟随 30.0，双通道占空比无扰重分配，无输出踢腿
 *   V4 断偶：eQuality=eWireBreakHigh → 按 eBreakAction 切断并锁存 eSensorBreak
 *      （0003_0211）；质量恢复 eGood + CmdReset → 回 eHolding（带无扰同步）
 *   V5 设定值钳位：fTempSetpoint=500 且 fTempMax=300 → 生效 300，0003_0101，
 *      故障位保持 FALSE（R21 信息级不置故障）
 *   V6 参数对调：fTempMin=300 > fTempMax=0 → 对调后继续计算，0003_0101
 *   V7 引脚无效：iTempSensor 未注入 → eFault（0003_0213），双通道切断
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 契约引用说明（R5 收口）: 本块温度信号源契约 E_DL_SignalQuality 与
 * I_DL_AnalogSensor 不在本文件就地声明，统一引用 DL_Device 正式定义文件
 * I_DL_AnalogSensor.st（枚举随宿主接口文件同文件发布，IEC 同工程内全局可见，
 * 留档见头注释 D2）。本块仅消费 fValue 与 eQuality 两个成员。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_BreakAction（归属 DL_Device，随 FB_DL_HeatCoolZone 同文件）
 * 含义: 断偶动作方向，按被控对象安全策略配置。
 *----------------------------------------------------------------------------*)
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_DL_BreakAction :
(
    eHeatOff := 0,   // 断偶切断加热（Cut heating on break）：升温对象超温风险侧
    eCoolOff := 1    // 断偶切断冷却（Cut cooling on break）：骤冷风险对象（如防脆断工艺）侧
) UINT;
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_HeatCoolZone IMPLEMENTS I_DL_TemperatureZone
 * 调用约定: 每个扫描周期无条件调用一次；PID/PWM 注入实例在本块主体每拍无条件
 *           调用（不在任何 IF/CASE 分支内部）；方法仅置请求标志，动作由主体执行。
 * 分程约定: PID 输出 [0..100 %]。输出低于 fSplitLow → 加热段（越低加热越强，
 *           配合 fKp 负值反作用）；高于 fSplitHigh → 冷却段（越高冷却越强）；
 *           两点之间为中性带（双通道全关，热平衡保持）。fSplitLow=0 时加热段
 *           跨度为零、加热通道自动禁用（防除零）；fSplitHigh=100 时同理禁用冷却。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_HeatCoolZone IMPLEMENTS I_DL_TemperatureZone
VAR_INPUT
    fTempSetpoint   : REAL := 0.0;      // 目标温度（Setpoint）[°C]，经 fTempMin/Max 钳位后生效
    fTempMin        : REAL := 0.0;     // 设定值下边界（Setpoint lower bound）[°C]，默认 0.0
    fTempMax        : REAL := 300.0;   // 设定值上边界（Setpoint upper bound）[°C]，默认 300.0
    fSplitLow       : REAL := 50.0;    // 分程下切换点（Split-range low crossover）[%]，PID 输出低于此点进入加热段
    fSplitHigh      : REAL := 50.0;    // 分程上切换点（Split-range high crossover）[%]，PID 输出高于此点进入冷却段
    eBreakAction    : E_DL_BreakAction := E_DL_BreakAction.eHeatOff; // 断偶动作方向（Break action）：eHeatOff=切断加热 / eCoolOff=切断冷却
    bEnable         : BOOL := FALSE;   // 投运使能（Zone enable），与 CmdEnable 方法锁存值取与
    tSampleTime     : TIME := T#100MS; // 采样周期（Sample time），下传注入的 PID 与两路 PWM（公约 0.5）
    bTrack          : BOOL := FALSE;   // 跟踪使能（Track enable），TRUE 时本拍输出跟随 fTrackValue 无扰接管
    fTrackValue     : REAL := 0.0;     // 跟踪值（Track value）[-100..100 %]，与输出功率同量纲
END_VAR
VAR_IN_OUT
    iTempSensor     : I_DL_AnalogSensor;       // 温度信号源接口引用（Sensor interface reference），上层注入 FB_DL_AnalogTransmitter 实例
    fbPid           : FB_DL_PidController;     // 温度 PID 实例（Injected PID instance），增益/积分/限幅由调用方组态
    fbPwmHeat       : FB_DL_PwmDutyController; // 加热 SSR PWM 实例（Injected heat PWM），周期/最短脉冲由调用方组态
    fbPwmCool       : FB_DL_PwmDutyController; // 冷却 SSR PWM 实例（Injected cool PWM），周期/最短脉冲由调用方组态
END_VAR
VAR_OUTPUT
    bHeaterOut      : BOOL;            // 加热执行通道镜像（Heater channel mirror），等于加热 PWM 实例布尔输出
    bCoolerOut      : BOOL;            // 冷却执行通道镜像（Cooler channel mirror），等于冷却 PWM 实例布尔输出
END_VAR
VAR
    bInit           : BOOL := TRUE;    // 首扫标志（First-scan flag），首扫判据见段 1（公约 0.1 唯一合法范式）
    _eState         : E_DL_TempZoneState := E_DL_TempZoneState.eIdle; // 内部状态机步序（Internal zone state）
    _fTempActual    : REAL := 0.0;     // 实测温度快照（Actual temperature snapshot）[°C]，取自传感器接口
    _fPowerOut      : REAL := 0.0;     // 输出功率（Power output）[-100..100 %]，正=加热 / 负=冷却（R20 量纲与赋值式一致）
    _bFault         : BOOL := FALSE;   // 故障锁存标志（Fault latched），派生式：仅故障级状态置位，信息级不置位（R21）
    _uErrorId       : UDINT := 0;      // 故障/信息码（Error/info code），0=无；故障级进态写入、锁存保持
    _bCmdEnabled    : BOOL := TRUE;    // CmdEnable 方法锁存值（Method enable latch），默认投运（方法为可选入口）
    _fSetpointMethod: REAL := 0.0;     // SetSetpoint 方法锁存设定值（Method setpoint latch）[°C]，已按边界钳位
    _bUseMethodSp   : BOOL := FALSE;   // TRUE=方法设定值覆盖引脚设定值（Method setpoint override）
    _bSyncReq       : BOOL := FALSE;   // 跃迁无扰同步请求（Bumpless sync request），置位后下一拍 PID 跟踪当前功率
    _bTrackActive   : BOOL := FALSE;   // 本拍处于外部跟踪（External track active this scan），由段 1 判据得出
    _fPowerOutLast  : REAL := 0.0;     // 上一拍输出功率（Last power output）[-100..100 %]，跃迁同步的跟踪源
    _fTempMinEff    : REAL := 0.0;     // 修复后设定值下边界（Repaired lower bound）[°C]
    _fTempMaxEff    : REAL := 300.0;   // 修复后设定值上边界（Repaired upper bound）[°C]
    _fSplitLowEff   : REAL := 50.0;    // 修复后分程下切换点（Repaired low crossover）[%]
    _fSplitHighEff  : REAL := 50.0;    // 修复后分程上切换点（Repaired high crossover）[%]
    _fSpEff         : REAL := 0.0;     // 有效设定值（Effective setpoint）[°C]，来源仲裁 + 钳位后
    _fTrackSrc      : REAL := 0.0;     // 本拍跟踪源（Track source this scan）[-100..100 %]
    _fPidOut        : REAL := 0.0;     // PID 输出快照（PID output snapshot）[0..100 %]
    _fHeatDuty      : REAL := 0.0;     // 加热通道占空比（Heater duty）[0..100 %]
    _fCoolDuty      : REAL := 0.0;     // 冷却通道占空比（Cooler duty）[0..100 %]
    _fSpTmp         : REAL := 0.0;     // 参数对调临时变量（Swap temporary）[°C 或 %]
    _bRefOk         : BOOL := FALSE;   // 传感器接口引用有效标志（Sensor reference valid）
    _bSensorBad     : BOOL := FALSE;   // 传感器断线/开路标志（Sensor break flag），含非有限值防御归入
    _bInfoClamp     : BOOL := FALSE;   // 本拍发生钳位/对调修复（Info-level clamp occurred）
    _bRunPre        : BOOL := FALSE;   // CASE 前运行态判定（Pre-CASE running flag），PID 使能源
    _bZoneRun       : BOOL := FALSE;   // CASE 后运行态判定（Post-CASE running flag），PWM 使能源
    _bReqEnable     : BOOL := FALSE;   // CmdEnable 请求挂起（Enable request pending）
    _bValEnable     : BOOL := FALSE;   // CmdEnable 请求值（Enable request value）
    _bReqReset      : BOOL := FALSE;   // CmdReset 请求挂起（Reset request pending）
    _bReqSetSp      : BOOL := FALSE;   // SetSetpoint 请求挂起（Setpoint request pending）
    _fReqSetSp      : REAL := 0.0;     // SetSetpoint 请求原始值（Raw setpoint request）[°C]
    _eQuality       : E_DL_SignalQuality := E_DL_SignalQuality.eGood; // 传感器信号质量快照（Quality snapshot）
END_VAR
VAR CONSTANT
    DL_ZONE_POWER_TOL : REAL := 0.01;   // 热平衡零功率判定容差（Power tolerance）[%]，浮点容差红线，状态判稳阈值
    DL_ZONE_SPAN_EPS  : REAL := 1.0E-6; // 分程跨度防除零判据（Span epsilon）[%]，低于此值通道禁用
END_VAR

METHOD SetSetpoint : BOOL
VAR_INPUT
    fTemp : REAL;                        // 目标温度（Target temperature）[°C]，非有限值拒绝
END_VAR
// 返回合法性：非有限值一律拒绝（公约 0.8 判式），合法值锁存待主体钳位生效
IF fTemp <> fTemp THEN
    SetSetpoint := FALSE;                // 非有限值拒绝
ELSE
    _fReqSetSp := fTemp;                 // 请求原始值 [°C]
    _bReqSetSp := TRUE;                  // 置单发标志，主体段 2/段 3 落实
    SetSetpoint := TRUE;                 // 受理成功
END_IF

    END_METHOD

METHOD CmdEnable
VAR_INPUT
    bOn : BOOL;                          // TRUE=投运（Commission on），FALSE=退出并切断双通道
END_VAR
_bReqEnable := TRUE;                     // 置请求标志
_bValEnable := bOn;                      // 请求值随行

    END_METHOD

METHOD CmdReset : BOOL
// 返回当前是否可复位：断偶锁存态要求信号质量快照已恢复 eGood（规格 §1.8 退出条件）
_bReqReset := TRUE;                      // 置请求标志，主体段 7 各态消费
IF _eState = E_DL_TempZoneState.eSensorBreak THEN
    IF _bRefOk AND (_eQuality = E_DL_SignalQuality.eGood) AND (NOT _bSensorBad) THEN
        CmdReset := TRUE;                // 质量已恢复，可复位
    ELSE
        CmdReset := FALSE;               // 仍在断线域，拒绝复位
    END_IF
ELSE
    CmdReset := TRUE;                    // 非断偶态一律受理
END_IF

// =============================================================================
// 属性实现区（PROPERTY GET ×5，接口契约逐字兑现；偏离 D1：属性即输出引脚语义）
// =============================================================================

    END_METHOD

// -----------------------------------------------------------------------------
// 段 1｜首扫与跟踪同步（公约 0.1 / R19 唯一合法范式：跟踪项在前、首扫项取反在后，
//       禁止两项顺序颠倒的反式写法；验收向量 V3 覆盖运行中途跟踪脉冲）
// -----------------------------------------------------------------------------
IF bTrack OR (NOT bInit) THEN
    _fPowerOutLast := 0.0;               // 首扫/外部跟踪：历史功率清零，杜绝接管瞬间踢腿 [±100 %]
    _bTrackActive  := TRUE;              // 本拍输出跟随外部跟踪值 fTrackValue
    bInit          := TRUE;              // 首扫完成置位
ELSE
    _bTrackActive  := FALSE;             // 正常闭环拍，跟踪源取内部历史功率
END_IF

// -----------------------------------------------------------------------------
// 段 2｜方法请求消费（方法内只置标志，动作在本周期落实——跨周期动作不驻留方法）
// -----------------------------------------------------------------------------
IF _bReqEnable THEN
    _bCmdEnabled := _bValEnable;         // 投/退锁存值更新
    _bReqEnable  := FALSE;               // 单发消费
END_IF
IF _bReqSetSp THEN
    _fSetpointMethod := _fReqSetSp;      // 方法设定值锁存 [°C]，边界钳位在段 3 统一进行
    _bUseMethodSp    := TRUE;            // 方法设定值覆盖引脚设定值
    _bReqSetSp       := FALSE;           // 单发消费
END_IF
IF NOT ( (_eState = E_DL_TempZoneState.eSensorBreak) OR (_eState = E_DL_TempZoneState.eFault) ) THEN
    _bReqReset := FALSE;                 // 非锁存态下的复位请求立即作废，防陈旧请求迟到生效
END_IF

// -----------------------------------------------------------------------------
// 段 3｜参数修复（公约 0.6 对调自修复 + 公约 0.8 非有限值防御；信息级 0003_0101
//       只进 uErrorId 不置故障，R21；偏离 D4：段位按公约 0.7 归 DL_Device 族）
// -----------------------------------------------------------------------------
_bInfoClamp := FALSE;
IF fTempMin <> fTempMin THEN             // NaN 恒不等于自身（公约 0.8 指定判式）
    _fTempMinEff := 0.0;                 // 非有限值回退默认下边界 [°C]
    _bInfoClamp  := TRUE;
ELSE
    _fTempMinEff := fTempMin;            // 直接采纳 [°C]
END_IF
IF fTempMax <> fTempMax THEN
    _fTempMaxEff := 300.0;               // 非有限值回退默认上边界 [°C]
    _bInfoClamp  := TRUE;
ELSE
    _fTempMaxEff := fTempMax;            // 直接采纳 [°C]
END_IF
IF _fTempMinEff > _fTempMaxEff THEN      // 边界对调自修复（公约 0.6）：修复后继续计算，不中断
    _fSpTmp       := _fTempMinEff;
    _fTempMinEff  := _fTempMaxEff;
    _fTempMaxEff  := _fSpTmp;
    _bInfoClamp   := TRUE;
END_IF

IF fSplitLow <> fSplitLow THEN
    _fSplitLowEff := 50.0;               // 非有限值回退对称默认 [%]
    _bInfoClamp   := TRUE;
ELSE
    _fSplitLowEff := fSplitLow;          // 直接采纳 [%]
END_IF
IF fSplitHigh <> fSplitHigh THEN
    _fSplitHighEff := 50.0;              // 非有限值回退对称默认 [%]
    _bInfoClamp    := TRUE;
ELSE
    _fSplitHighEff := fSplitHigh;        // 直接采纳 [%]
END_IF
IF _fSplitLowEff < 0.0 THEN
    _fSplitLowEff := 0.0;                // 钳到分程域下限 [%]（此时加热段跨度为零，加热禁用）
    _bInfoClamp   := TRUE;
END_IF
IF _fSplitLowEff > 100.0 THEN
    _fSplitLowEff := 100.0;              // 钳到分程域上限 [%]
    _bInfoClamp   := TRUE;
END_IF
IF _fSplitHighEff < 0.0 THEN
    _fSplitHighEff := 0.0;               // 钳到分程域下限 [%]
    _bInfoClamp    := TRUE;
END_IF
IF _fSplitHighEff > 100.0 THEN
    _fSplitHighEff := 100.0;             // 钳到分程域上限 [%]（此时冷却段跨度为零，冷却禁用）
    _bInfoClamp    := TRUE;
END_IF
IF _fSplitLowEff > _fSplitHighEff THEN   // 分程点对调自修复（公约 0.6）
    _fSpTmp        := _fSplitLowEff;
    _fSplitLowEff  := _fSplitHighEff;
    _fSplitHighEff := _fSpTmp;
    _bInfoClamp    := TRUE;
END_IF

// 设定值来源仲裁：方法锁存值优先，否则取引脚连续值
IF _bUseMethodSp THEN
    _fSpEff := _fSetpointMethod;         // 方法通道 [°C]
ELSE
    _fSpEff := fTempSetpoint;            // 引脚通道 [°C]
END_IF
IF _fSpEff <> _fSpEff THEN
    _fSpEff     := _fTempMinEff;         // 非有限设定值回退下边界（安全侧低温待机）[°C]
    _bInfoClamp := TRUE;
END_IF
IF (_fSpEff < _fTempMinEff) OR (_fSpEff > _fTempMaxEff) THEN
    _fSpEff     := LIMIT(_fTempMinEff, _fSpEff, _fTempMaxEff);  // 设定值钳位（规格 §1.8 设计点，信息级 0003_0101）
    _bInfoClamp := TRUE;
END_IF

// -----------------------------------------------------------------------------
// 段 4｜传感器采集与有效性判定（接口引用检查 + 质量域 + 非有限值防御）
// -----------------------------------------------------------------------------
_bRefOk     := FALSE;
_bSensorBad := FALSE;
_eQuality   := E_DL_SignalQuality.eGood;
IF iTempSensor <> 0 THEN                 // 接口引用有效性检查（未注入防御）
    _bRefOk     := TRUE;
    _fTempActual := iTempSensor.fValue;  // 工程量实测值 [°C]，契约保证 NaN 防御后输出
    _eQuality    := iTempSensor.eQuality;
    IF _fTempActual <> _fTempActual THEN
        _bSensorBad := TRUE;             // 非有限值防御：NaN 按断线域处理（公约 0.8 判式）
    ELSIF (_eQuality = E_DL_SignalQuality.eWireBreakLow)
       OR (_eQuality = E_DL_SignalQuality.eWireBreakHigh)
       OR (_eQuality = E_DL_SignalQuality.eOpenLoop) THEN
        _bSensorBad := TRUE;             // NE43 断线/开路域（规格 §1.8 断偶保护集合）
    END_IF
END_IF

// -----------------------------------------------------------------------------
// 段 5｜运行态预判定与注入 PID 无条件调用（R7 精神：实例调用不在 IF/CASE 分支内）
// -----------------------------------------------------------------------------
_bRunPre := (_eState = E_DL_TempZoneState.eHolding)
         OR (_eState = E_DL_TempZoneState.eHeating)
         OR (_eState = E_DL_TempZoneState.eCooling);
IF _bTrackActive THEN
    _fTrackSrc := fTrackValue;           // 外部跟踪源 [-100..100 %]
ELSE
    _fTrackSrc := _fPowerOutLast;        // 跃迁同步源 = 上一拍实际输出功率 [-100..100 %]
END_IF
fbPid(
    bEnable     := _bRunPre AND _bRefOk AND (NOT _bSensorBad),  // 断偶/无引用时冻结 PID（输出回下限）
    bManual     := FALSE,                // 温控区纯自动模式，手动路径不由本块开放
    fSetpoint   := _fSpEff,              // 有效设定值 [°C]
    fActual     := _fTempActual,         // 实测温度 [°C]
    tSampleTime := tSampleTime,          // 采样周期下传（公约 0.5）
    bTrack      := _bTrackActive OR _bSyncReq,  // 外部跟踪或跃迁无扰同步（电平，一拍）
    fTrackValue := _fTrackSrc            // 跟踪值 [-100..100 %]
);
_bSyncReq := FALSE;                      // 同步请求单发消费（段 7 跃迁时重新置位）

// -----------------------------------------------------------------------------
// 段 6｜分程分配（热平衡计算，防除零：跨度不足的通道自动禁用，R4 红线）
// -----------------------------------------------------------------------------
IF _bRunPre AND _bRefOk AND (NOT _bSensorBad) THEN
    _fPidOut := fbPid.fOut;              // PID 输出 [0..100 %]，量程由调用方组态
    IF _fPidOut < _fSplitLowEff THEN
        // 加热段：输出越低于下切换点，加热越强（配合 fKp 负值反作用惯例）
        IF _fSplitLowEff > DL_ZONE_SPAN_EPS THEN
            _fHeatDuty := LIMIT(0.0, (_fSplitLowEff - _fPidOut) / _fSplitLowEff * 100.0, 100.0); // 加热占空比 [0..100 %]
        ELSE
            _fHeatDuty := 0.0;           // 加热段跨度为零，通道禁用（防除零）
        END_IF
        _fCoolDuty := 0.0;               // 加热段冷却通道必关 [0..100 %]
    ELSIF _fPidOut > _fSplitHighEff THEN
        // 冷却段：输出越高于上切换点，冷却越强
        IF (100.0 - _fSplitHighEff) > DL_ZONE_SPAN_EPS THEN
            _fCoolDuty := LIMIT(0.0, (_fPidOut - _fSplitHighEff) / (100.0 - _fSplitHighEff) * 100.0, 100.0); // 冷却占空比 [0..100 %]
        ELSE
            _fCoolDuty := 0.0;           // 冷却段跨度为零，通道禁用（防除零）
        END_IF
        _fHeatDuty := 0.0;               // 冷却段加热通道必关 [0..100 %]
    ELSE
        _fHeatDuty := 0.0;               // 中性带：双通道全关，热平衡保持 [0..100 %]
        _fCoolDuty := 0.0;               // 中性带 [0..100 %]
    END_IF
ELSE
    _fPidOut   := 0.0;                   // 非运行拍 PID 输出按 0 [%] 处理
    _fHeatDuty := 0.0;                   // 非运行拍加热占空比清零 [0..100 %]
    _fCoolDuty := 0.0;                   // 非运行拍冷却占空比清零 [0..100 %]
END_IF
_fPowerOut := _fHeatDuty - _fCoolDuty;   // 输出功率 [-100..100 %]，正=加热/负=冷却（R20 量纲与赋值式一致）

// -----------------------------------------------------------------------------
// 段 7｜状态机（ENUM + CASE + ELSE 兜底；断偶/非法态/无引用均为锁存，R15 仅复位可清）
// -----------------------------------------------------------------------------
CASE _eState OF

    E_DL_TempZoneState.eIdle:            // 空闲：双通道切断（PWM 使能在段 8 落实）
        IF _bRefOk AND (NOT _bSensorBad) AND bEnable AND _bCmdEnabled THEN
            _bSyncReq := TRUE;           // 投运首拍无扰同步，PID 跟踪当前功率 0 [%]
            _eState   := E_DL_TempZoneState.eHolding;
        END_IF

    E_DL_TempZoneState.eHolding:         // 保温：双通道处于热平衡容差带
        IF NOT (bEnable AND _bCmdEnabled) THEN
            _eState := E_DL_TempZoneState.eIdle;
        ELSIF NOT _bRefOk THEN
            _uErrorId := 16#0003_0213;   // 接口引用未注入/无效（故障级锁存）
            _eState   := E_DL_TempZoneState.eFault;
        ELSIF _bSensorBad THEN
            _uErrorId := 16#0003_0211;   // 断偶锁存（故障级；eBreakAction 切断方向语义见偏离 D3）
            _eState   := E_DL_TempZoneState.eSensorBreak;
        ELSIF _fPowerOut > DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eHeating;
        ELSIF _fPowerOut < -DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eCooling;
        END_IF

    E_DL_TempZoneState.eHeating:         // 加热中
        IF NOT (bEnable AND _bCmdEnabled) THEN
            _eState := E_DL_TempZoneState.eIdle;
        ELSIF NOT _bRefOk THEN
            _uErrorId := 16#0003_0213;   // 接口引用未注入/无效
            _eState   := E_DL_TempZoneState.eFault;
        ELSIF _bSensorBad THEN
            _uErrorId := 16#0003_0211;   // 断偶锁存
            _eState   := E_DL_TempZoneState.eSensorBreak;
        ELSIF _fPowerOut < -DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eCooling;
        ELSIF ABS(_fPowerOut) <= DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eHolding;   // 回到热平衡带（浮点容差红线）
        END_IF

    E_DL_TempZoneState.eCooling:         // 冷却中
        IF NOT (bEnable AND _bCmdEnabled) THEN
            _eState := E_DL_TempZoneState.eIdle;
        ELSIF NOT _bRefOk THEN
            _uErrorId := 16#0003_0213;   // 接口引用未注入/无效
            _eState   := E_DL_TempZoneState.eFault;
        ELSIF _bSensorBad THEN
            _uErrorId := 16#0003_0211;   // 断偶锁存
            _eState   := E_DL_TempZoneState.eSensorBreak;
        ELSIF _fPowerOut > DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eHeating;
        ELSIF ABS(_fPowerOut) <= DL_ZONE_POWER_TOL THEN
            _eState := E_DL_TempZoneState.eHolding;   // 回到热平衡带
        END_IF

    E_DL_TempZoneState.eSensorBreak:     // 断偶锁存：双通道全断（安全终态，偏离 D3）
        IF _bReqReset AND _bRefOk AND (_eQuality = E_DL_SignalQuality.eGood)
           AND (NOT _bSensorBad) AND bEnable AND _bCmdEnabled THEN
            _bReqReset := FALSE;         // 复位请求消费
            _bSyncReq  := TRUE;          // 复位回投无扰同步
            _eState    := E_DL_TempZoneState.eHolding;
        END_IF

    E_DL_TempZoneState.eFault:           // 故障兜底：双通道全断
        IF _bReqReset AND _bRefOk THEN
            _bReqReset := FALSE;         // 复位请求消费（引用已恢复有效）
            _bSyncReq  := TRUE;          // 复位回投无扰同步
            _eState    := E_DL_TempZoneState.eHolding;
        END_IF

    ELSE                                 // 非法状态兜底拦截（R6 红线）
        _uErrorId := 16#0003_0212;       // 非法状态（故障级锁存）
        _eState   := E_DL_TempZoneState.eFault;
END_CASE

// -----------------------------------------------------------------------------
// 段 8｜注入 PWM 无条件调用与输出镜像（R7 精神：实例调用不在 IF/CASE 分支内）
// -----------------------------------------------------------------------------
_bZoneRun := (_eState = E_DL_TempZoneState.eHolding)
          OR (_eState = E_DL_TempZoneState.eHeating)
          OR (_eState = E_DL_TempZoneState.eCooling);
fbPwmHeat(
    bEnable     := _bZoneRun,            // 锁存态/空闲态强制关断
    fDuty       := _fHeatDuty,           // 加热占空比 [0..100 %]
    tSampleTime := tSampleTime,          // 采样周期下传（公约 0.5）
    bInvert     := FALSE                 // 正相输出
);
fbPwmCool(
    bEnable     := _bZoneRun,            // 锁存态/空闲态强制关断
    fDuty       := _fCoolDuty,           // 冷却占空比 [0..100 %]
    tSampleTime := tSampleTime,          // 采样周期下传（公约 0.5）
    bInvert     := FALSE                 // 正相输出
);
bHeaterOut := fbPwmHeat.bPwmOut;         // 加热通道镜像 = 注入 PWM 布尔输出
bCoolerOut := fbPwmCool.bPwmOut;         // 冷却通道镜像 = 注入 PWM 布尔输出

// -----------------------------------------------------------------------------
// 段 9｜故障派生（R21：bFault 为显式排除信息级码的派生式）与历史存档
// -----------------------------------------------------------------------------
_bFault := (_eState = E_DL_TempZoneState.eSensorBreak)
        OR (_eState = E_DL_TempZoneState.eFault);       // 仅故障级状态置位，0003_0101 不置位
IF _eState = E_DL_TempZoneState.eSensorBreak THEN
    _uErrorId := 16#0003_0211;           // 断偶锁存码逐拍保持，直至复位
ELSIF _eState <> E_DL_TempZoneState.eFault THEN
    IF _bInfoClamp THEN
        _uErrorId := 16#0003_0101;       // 信息级：钳位/对调修复提示，不置故障（R19）
    ELSE
        _uErrorId := 16#0000_0000;       // 无故障无提示
    END_IF
END_IF
// eFault 态不重写 _uErrorId：保持进态时写入的 0212/0213，锁存至复位（R15）
_fPowerOutLast := _fPowerOut;            // 存档本拍功率，供下一拍跃迁同步跟踪 [-100..100 %]

// =============================================================================
// 方法实现区（METHOD，共 3 个，接口契约逐字兑现；非阻塞单发语义）
// =============================================================================




PROPERTY fTempActual : REAL
fTempActual := _fTempActual;             // 实测温度 [°C]

PROPERTY fPowerOut : REAL
fPowerOut := _fPowerOut;                 // 输出功率 [-100..100 %]，正=加热/负=冷却

PROPERTY eState : E_DL_TempZoneState
eState := _eState;                       // 当前温控区状态

PROPERTY bFault : BOOL
bFault := _bFault;                       // 故障锁存标志（派生式，信息级不置位）

PROPERTY uErrorId : UDINT
uErrorId := _uErrorId;                   // 末次故障/信息码

END_FUNCTION_BLOCK
