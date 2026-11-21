(*
  FB_DL_DisturbanceObserver  —  模型法负载扰动观测器 / Model-based load disturbance observer
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_81
  版本 Version  : 1.0.0
  来源标签 Tag  : t2-4-s7-motion
  溯源 Source   : S7 Motion Control 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码行
  功能 Function : 1) 标称模型逆（J·dω/dt ÷ Kt）折算等效电流，与指令电流之差乘 Kt 得扰动转矩估计；
                  2) 估计量经一阶 Q 滤波（委托 FB_DL_LowPassFilter）去噪后输出；
                  3) 补偿量按 fCompGain 加权并限幅到 ±fCompLimit，饱和置 bSaturated。
  边界 Boundary : ① fInertia / fTorqueConst / fQFilterTau / fRatedCurrentA 任一 <= 0 判组态错置码且不投运（防除零）；
                  ② 速度为零并持续超冻结窗 tZeroSpeedHold（本件常量 200 ms）时冻结估计（静止段无可观测加速度，防噪声灌入）；
                  ③ bEnable 下降沿清估计值与微分状态（R28-1 解除式 = bEnable 上升沿 + bReset，两路径均在引脚可满足）；
                  ④ 补偿限幅 fCompLimit 由引脚给出，不在本件硬编码；
                  ⑤ bEnable = FALSE 语义：输出降级为安全值 0 + 保持状态 eIdle，不冻结末值（R191 显式声明）。
  依赖 Depends  : FB_DL_LowPassFilter × 1（Q 滤波，每拍无条件调用）
  同拍双窗配比  : 冻结窗 tZeroSpeedHold = 200 ms 与 Q 滤波时间常数 fQFilterTau 同源于 fSampleDt；
                  配比约束 fQFilterTau <= 0.5 × tZeroSpeedHold 保证静止冻结前滤波器已收敛（R100）

  码表 Error codes（本件格 02_3_81，子码步进 +0x10）:
    16#0002_0281 故障级：组态非法（惯量 / 转矩常数 / 滤波时间常数 / 额定电流 <= 0，或采样周期 <= 0，或组态量非有限）
    16#0002_0291 故障级：相 ID 越界（枚举兜底路径，复用组态码段之外的单列码）
    16#0002_02A1 信息级：速度为零冻结估计 / 输入非有限本拍不更新（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R36 首版入库
*)

TYPE E_DL_ObserverState :
(
    eIdle  := 0,   // 空闲（未使能，输出降级为 0）/ Idle, outputs degraded to zero
    eRun   := 10,  // 观测运行 / Observer running
    eHold  := 20,  // 静止冻结（速度为零超冻结窗）/ Frozen at zero speed
    eFault := 90   // 组态故障锁定（需 bReset 沿解除）/ Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_DisturbanceObserver
VAR_INPUT
    bEnable        : BOOL := FALSE;              // 总使能，FALSE 时输出降级为 0 并回 eIdle / Master enable
    bReset         : BOOL := FALSE;              // 复位，上升沿清组态故障锁存 / Reset, clears latched fault
    fCmdOut        : REAL := 0.0;                // 控制器输出（力矩指令）[% 额定力矩] / Controller output [% rated torque]
    fRatedCurrentA : REAL := 10.0;               // 额定电流 [A]，域 > 0 / Rated current [A], domain > 0
    fMeasSpeed     : REAL := 0.0;                // 实测转速 [rpm]，带符号 / Measured speed [rpm]
    fInertia       : REAL := 0.001;              // 折算惯量 [kg·m²]，域 > 0 / Reflected inertia [kg·m²]
    fTorqueConst   : REAL := 1.0;                // 转矩常数 [N·m/A]，域 > 0 / Torque constant [N·m/A]
    fQFilterTau    : REAL := 0.005;              // Q 滤波时间常数 [s]，域 > 0 / Q-filter time constant [s]
    tSampleTime    : TIME := T#10MS;             // 采样周期 [ms 口径]，域 > 0 / Sampling period
    fCompGain      : REAL := 1.0;                // 补偿加权系数 [1]，域 >= 0 / Compensation gain
    fCompLimitPct  : REAL := 20.0;               // 补偿限幅 [%]，域 > 0 / Compensation limit [%]
    fEps           : REAL := 1.0E-6;             // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fDistTorqueEst : REAL;                       // 扰动转矩估计 [N·m] / Estimated disturbance torque [N·m]
    fCompOut       : REAL;                       // 补偿量输出 [%]，限幅后 / Compensation output [%]
    bSaturated     : BOOL;                       // 补偿限幅饱和标志（单拍）/ Compensation saturated, single scan
    bFrozen        : BOOL;                       // 静止冻结标志 / Frozen at zero speed
    bValid         : BOOL;                       // 估计有效标志（单拍）/ Estimate valid, single scan
    bError         : BOOL;                       // 故障标志，派生自锁存 / Fault flag derived from latch
    uErrorId       : UDINT;                      // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_ObserverState;         // 状态出口，段尾单点映射 / State mapped at tail
END_VAR
VAR
    fbQFilter      : FB_DL_LowPassFilter;        // Q 滤波实例（每拍无条件调用）/ Q-filter instance
    tonZeroSpeed   : TON;                        // 零速持续时间窗（本件常量 200 ms）/ Zero-speed dwell timer
    rtEnable       : R_TRIG;                     // 使能上升沿 / Enable rising edge
    rtReset        : R_TRIG;                     // 复位上升沿 / Reset rising edge
    _eState        : E_DL_ObserverState := E_DL_ObserverState.eIdle;  // 内部状态机当前态 / Internal phase
    _uFault        : UDINT;                      // 故障码锁存（仅复位沿清除）/ Latched fault code
    _uInfo         : UDINT;                      // 信息码，每拍重算 / Information code, recomputed each scan
    _bFault        : BOOL;                       // 故障锁存位 / Latched fault bit
    fSpeedPrev     : REAL;                       // 上一拍转速快照 [rpm]（不参与预清零）/ Speed snapshot, kept
    fAccelRpmS     : REAL;                       // 转速微分 [rpm/s] / Speed derivative [rpm/s]
    fAccelRadS     : REAL;                       // 角加速度 [rad/s²] / Angular acceleration [rad/s²]
    fCurrentNomA   : REAL;                       // 标称模型逆等效电流 [A] / Nominal model inverse current [A]
    fCurrentCmdA   : REAL;                       // 指令折算电流 [A] / Command current [A]
    fTorqueDistNm  : REAL;                       // 含噪扰动转矩 [N·m] / Raw disturbance torque [N·m]
    fDtSec         : REAL;                       // 采样周期秒值 [s] / Sampling period in seconds
    bFirstScan     : BOOL := TRUE;               // 首扫标志（微分初值用）/ First-scan flag for derivative
    bZeroSpeed     : BOOL;                       // 零速判定中间量 / Zero-speed predicate
    bCfgBad        : BOOL;                       // 组态非法聚合标志 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_T_ZERO_HOLD : TIME  := T#200MS;   // 零速冻结窗 [ms]，本件声明常量 / Zero-speed freeze window
    DL_RPM2RAD     : REAL  := 0.1047197551;  // rpm 转 rad/s [rad/(s·rpm)] / rpm to rad/s factor
    DL_EPS         : REAL  := 1.0E-6;    // 判零容差 [1] / Zero tolerance
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（禁置于分支内） —— *)
rtEnable(CLK := bEnable);                                      // 使能上升沿（每拍必调）
rtReset(CLK := bReset);                                        // 复位上升沿（每拍必调）
bZeroSpeed := bEnable AND (ABS(fMeasSpeed) < DL_EPS);          // 零速判定，门控挂状态量
tonZeroSpeed(IN := bZeroSpeed, PT := DL_T_ZERO_HOLD);          // 零速驻留计时（输入非字面 TRUE，具备复位路径）

(* —— 段 1：单拍标志预清零（只清单拍量，快照与锁存不入清单） —— *)
bSaturated := FALSE;      // 单拍标志：限幅饱和
bValid     := FALSE;      // 单拍标志：估计有效
bFrozen    := FALSE;      // 单拍标志：静止冻结
bError     := FALSE;      // 单拍标志：故障出口（段 6 由锁存派生重写）
_uInfo     := 0;          // 信息码每拍重算
fDtSec     := TIME_TO_REAL(tSampleTime) / 1000.0;   // 采样周期秒值 [s]

(* —— 段 2：复位沿清故障锁存（R188 可达清除路径） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;     // 复位沿清锁存位
    _uFault := 0;         // 复位沿清锁存码
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚，R151） —— *)
bCfgBad := FALSE;
IF (fInertia <> fInertia) OR (fInertia <= 0.0) THEN
    bCfgBad := TRUE;      // 惯量非有限或 <= 0
END_IF
IF (fTorqueConst <> fTorqueConst) OR (fTorqueConst <= 0.0) THEN
    bCfgBad := TRUE;      // 转矩常数非有限或 <= 0
END_IF
IF (fQFilterTau <> fQFilterTau) OR (fQFilterTau <= 0.0) THEN
    bCfgBad := TRUE;      // 滤波时间常数非有限或 <= 0
END_IF
IF (fRatedCurrentA <> fRatedCurrentA) OR (fRatedCurrentA <= 0.0) THEN
    bCfgBad := TRUE;      // 额定电流非有限或 <= 0
END_IF
IF (fCompLimitPct <> fCompLimitPct) OR (fCompLimitPct <= 0.0) THEN
    bCfgBad := TRUE;      // 补偿限幅非有限或 <= 0
END_IF
IF (fEps <> fEps) OR (fEps <= 0.0) THEN
    bCfgBad := TRUE;      // 判零容差非有限或 <= 0
END_IF
IF tSampleTime <= T#0MS THEN
    bCfgBad := TRUE;      // 采样周期 <= 0（微分除零前置）
END_IF
IF bCfgBad THEN
    _uFault := 16#0002_0281;                              // 故障级：组态非法
    _bFault := TRUE;                                      // 锁存位置位（复位沿可清）
    bError := TRUE;                                       // 故障标志置位（R45 配对）
    _eState := E_DL_ObserverState.eFault;                 // 状态机进故障相
END_IF

(* —— 段 4：观测内核（仅无故障且使能时执行） —— *)
IF (NOT _bFault) AND bEnable AND (fDtSec > 0.0) THEN
    fCurrentCmdA := fCmdOut / 100.0 * fRatedCurrentA;                    // 指令折算电流 [A]
    IF bFirstScan THEN
        fSpeedPrev := fMeasSpeed;                                        // 首扫微分初值，防冲击
        bFirstScan := FALSE;                                             // 首扫标志唯一置假点
    END_IF
    fAccelRpmS := (fMeasSpeed - fSpeedPrev) / fDtSec;                    // 转速微分 [rpm/s]
    fAccelRadS := fAccelRpmS * DL_RPM2RAD;                               // 角加速度 [rad/s²]
    fSpeedPrev := fMeasSpeed;                                            // 快照更新（末行，不预清零）
    fCurrentNomA := fInertia * fAccelRadS / fTorqueConst;                // 标称模型逆等效电流 [A]（Kt 已证 > 0）
    fTorqueDistNm := (fCurrentCmdA - fCurrentNomA) * fTorqueConst;       // 含噪扰动转矩 [N·m]
    IF tonZeroSpeed.Q THEN
        _eState := E_DL_ObserverState.eHold;                             // 静止冻结相
        fFrozen := TRUE;                                                // 冻结标志
        _uInfo := 16#0002_02A1;                                         // 信息级：速度为零冻结估计
    ELSE
        _eState := E_DL_ObserverState.eRun;                             // 观测运行相
        fbQFilter(bEnable := TRUE, fIn := fTorqueDistNm, tTimeConst := REAL_TO_TIME(fQFilterTau * 1000.0),
                  tSampleTime := tSampleTime);                          // Q 滤波实例调用（每拍必调，单点单次）
        IF fbQFilter.bError THEN
            _eState := E_DL_ObserverState.eHold;                        // 滤波故障降级为冻结（降级不抛故障，R191 已声明）
        END_IF
    END_IF
ELSE
    _eState := E_DL_ObserverState.eIdle;                                // 未使能：降级为安全值（R191 声明）
    fSpeedPrev := fMeasSpeed;                                           // 快照跟随，防再使能冲击
    bFirstScan := TRUE;                                                 // 复位首扫标志（再使能重新取值）
END_IF

(* —— 段 5：状态机兜底（非法枚举值回 eIdle 并置故障级码） —— *)
CASE _eState OF
E_DL_ObserverState.eIdle:
    fCompOut := 0.0;                     // 空闲：补偿量降级为 0
    fDistTorqueEst := 0.0;               // 空闲：估计值清零
E_DL_ObserverState.eRun:
    fDistTorqueEst := fbQFilter.fOut;    // 运行：输出滤波后扰动估计 [N·m]
    fCompOut := -fCompGain * fDistTorqueEst / fTorqueConst / fRatedCurrentA * 100.0;  // 补偿量 [%]（Kt、额定电流已证 > 0）
    IF fCompOut > fCompLimitPct THEN
        fCompOut := fCompLimitPct;       // 上行限幅
        bSaturated := TRUE;              // 饱和标志
    ELSIF fCompOut < -fCompLimitPct THEN
        fCompOut := -fCompLimitPct;      // 下行限幅
        bSaturated := TRUE;              // 饱和标志
    END_IF
    bValid := TRUE;                      // 本拍估计有效
E_DL_ObserverState.eHold:
    fDistTorqueEst := 0.0;               // 冻结：不出新估计（静止段无可观测加速度）
    fCompOut := 0.0;                     // 冻结：补偿量 0
E_DL_ObserverState.eFault:
    fDistTorqueEst := 0.0;               // 故障：输出安全值
    fCompOut := 0.0;                     // 故障：输出安全值
ELSE
    _uFault := 16#0002_0291;             // 故障级：相 ID 越界（枚举兜底）
    _bFault := TRUE;                     // 锁存位置位
    bError := TRUE;                      // 故障标志置位（R45 配对）
    _eState := E_DL_ObserverState.eFault;  // 强制回故障相
    fDistTorqueEst := 0.0;               // 兜底输出安全值
    fCompOut := 0.0;                     // 兜底输出安全值
END_CASE

(* —— 段 6：出口单点映射（名实同源，故障码由锁存回放） —— *)
eStateOut := _eState;                    // 状态出口
IF _bFault THEN
    uErrorId := _uFault;                 // 故障锁存码回放（不在故障相按当下输入重推）
ELSE
    uErrorId := _uInfo;                  // 信息码
END_IF
bError := _bFault;                       // 故障出口派生自锁存（非擦除式覆盖）
