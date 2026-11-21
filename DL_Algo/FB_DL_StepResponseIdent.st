(*
  FB_DL_StepResponseIdent  —  一阶+纯滞后阶跃响应辨识（切线法） / First-order plus dead-time step response identification by tangent method
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t2-5-modpid — 过程辨识族零检索深化
  溯源 Origin   : clean-room 实现，切线法公开教科书语义，未复制任何源码行
  功能 Function : 1) bTrig 沿锁存基线 _fY0 → eRamp 相采样跟踪：3 点滑窗差分求最大斜率，
                  记忆最大斜率幅值、发生时刻与样本值（拐点近似）；
                  2) 稳态判据：相邻拍变化 < fSteadyBand 持续 tSteadyTo → 锁定 fYss；
                  3) 切线法换算：θ := t_inf - (y_inf - Y0)/slope；T := (Yss - Y0)/slope - θ；
                  K := (Yss - Y0)/fStepCmd；θ/T 负值钳 0 并置信息级（T>=0、θ>=0 判据显式化）；
                  4) 辨识未完成输出保持 + bValid FALSE；总超时 → 03A6 锁存。
  边界 Boundary : ① 组态闸：fStepCmd = 0（防除零）、tSamp/tSteadyTo/tGuardTo <= 0 → 03A5；
                  ② 斜率退化（|slope| < 1.0E-12 防除零）或样本非有限 → 03A7 锁存；
                  ③ 采样环形窗容量 256，饱和后停录继续判稳，置信息级 048D；
                  ④ 相位机 CASE 全覆盖 + ELSE 兜底落 03A8；
                  ⑤ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG / ABS / TRUNC）
  码表 Error codes（Algo 段 0002，窗口 03A5~03A8 / 048B~048E）:
    16#0002_03A5 故障级：组态非法（阶跃幅值为零 / 任一时间域非法），锁存至 bReset
    16#0002_03A6 故障级：辨识总超时（tGuardTo），锁存至 bReset
    16#0002_03A7 故障级：斜率退化或样本非有限（防除零兜底），锁存至 bReset
    16#0002_03A8 故障级：相位落 ELSE 兜底（非法相位 ID），锁存至 bReset
    16#0002_048B 信息级：辨识完成沿（结果有效）
    16#0002_048C 信息级：稳态确认中（伴随态）
    16#0002_048D 信息级：采样窗饱和（停止记录，继续判稳）
    16#0002_048E 信息级：复位清账确认
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 3 · 序号 3）
*)

TYPE E_DL_SriState :
(
    eIdle   := 0,    // 空闲：等触发沿 / Idle, waiting trigger edge
    eRamp   := 10,   // 响应跟踪：采样求斜率 / Ramp tracking, sampling for slope
    eSteady := 20,   // 稳态确认：变化小于带持续窗 / Steady confirm, small change persists
    eDone   := 30,   // 完成：K/T/θ 已锁定 / Done, parameters latched
    eFault  := 90    // 故障：超时/退化锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepResponseIdent
VAR_INPUT
    fProcVal     : LREAL := 0.0;      // 过程量输入 [EU] / Process value input
    fStepCmd     : LREAL := 100.0;    // 阶跃幅值 [EU]，非零（防除零）/ Step magnitude, nonzero
    fSteadyBand  : LREAL := 0.1;      // 稳态判定带 [EU]，域 > 0 / Steady-state band
    tSamp        : TIME := T#100MS;   // 采样周期 [ms]，域 > 0 / Sampling period
    tSteadyTo    : TIME := T#2S;      // 稳态确认窗 [ms]，域 > 0 / Steady confirm window
    tGuardTo     : TIME := T#60S;     // 辨识总超时 [ms]，域 > 0 / Total identification timeout
    bTrig        : BOOL := FALSE;     // 启动触发沿 [-] / Start trigger edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障与账目 / Reset edge clears faults and ledger
END_VAR
VAR_OUTPUT
    fK           : LREAL;             // 增益估计 [EU/EU] / Gain estimate
    fT           : LREAL;             // 时间常数估计 [s]，域 >= 0 / Time constant estimate
    fTheta       : LREAL;             // 纯滞后估计 [s]，域 >= 0 / Dead-time estimate
    bIdent       : BOOL;              // 辨识完成保持标志 [-] / Identification done latched flag
    bValid       : BOOL;              // 结果可用标志 / Result usable flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonSamp      : TON;               // 采样节拍定时器（自复位口径），无条件刷新 / Sampling tick timer
    tonSteadyTo  : TON;               // 稳态确认定时器，无条件刷新 / Steady confirm timer
    tonGuardTo   : TON;               // 辨识总超时定时器（专用超时命名），无条件刷新 / Total timeout timer
    rtTrig       : R_TRIG;            // 触发沿实例，无条件刷新 / Trigger edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_SriState := E_DL_SriState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fY0         : LREAL;             // 基线快照 [EU] / Baseline snapshot
    _fYss        : LREAL;             // 稳态快照 [EU] / Steady-state snapshot
    _fYPrev      : LREAL;             // 上拍过程量快照 [EU] / Previous process value
    _fY3Prev     : LREAL;             // 3 拍前过程量快照 [EU] / Three-scan-old process value
    _fSlopeMax   : LREAL;             // 最大斜率 [EU/s] / Maximum slope
    _fSlopeVal   : LREAL;             // 最大斜率处样本值 [EU] / Sample value at max slope
    _nSmp        : INT;               // 采样计数 [个] / Sample counter
    _nSmpSlope   : INT;               // 最大斜率处采样计数 [个] / Sample counter at max slope
    _nSmpPrev    : INT;               // 上拍采样计数（节拍沿判据）/ Previous sample counter
    _fElapSec    : LREAL;             // 累计时间 [s] / Elapsed time
    _fSampSec    : LREAL;             // 采样周期秒 [s] / Sample period in seconds
    _fSlope      : LREAL;             // 当前滑窗斜率 [EU/s] / Current window slope
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bIdentPrev  : BOOL;              // 上拍完成镜像（完成沿判据）/ Previous done mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_fSampSec := TIME_TO_LREAL(tSamp) * 1.0E-3;               // 采样周期换算秒
rtTrig(CLK := bTrig);                                     // 触发沿（每拍必调）
rtReset(CLK := bReset);                                   // 复位沿（每拍必调）
tonSamp(IN := (_eState = E_DL_SriState.eRamp), PT := tSamp);            // 采样节拍（每拍必调）
tonSteadyTo(IN := (_eState = E_DL_SriState.eRamp)
            AND (ABS(fProcVal - _fYPrev) < fSteadyBand), PT := tSteadyTo);  // 稳态确认（每拍必调）
tonGuardTo(IN := (_eState = E_DL_SriState.eRamp), PT := tGuardTo);      // 总超时（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_fK/_fT/_fTheta 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _eState := E_DL_SriState.eIdle; // 相位回空闲
    bIdent := FALSE;                // 完成标志清除
    _uInfo := 16#0002_048E;         // 信息级：复位清账确认
END_IF
IF (fStepCmd = 0.0) OR (fSteadyBand <= 0.0) OR (_fSampSec <= 0.0)
   OR (TIME_TO_DINT(tSteadyTo) <= 0) OR (TIME_TO_DINT(tGuardTo) <= 0) THEN
    _uFault := 16#0002_03A5;        // 故障级：组态非法（阶跃幅值零 = 防除零闸）
    _bFault := TRUE;
END_IF

(* —— 段 3：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SriState.eIdle:
    IF rtTrig.Q AND (NOT _bFault) THEN
        _fY0 := fProcVal;               // 锁存基线
        _fYPrev := fProcVal;            // 上拍快照初始化
        _fY3Prev := fProcVal;           // 3 拍前快照初始化
        _fSlopeMax := 0.0;              // 最大斜率清零
        _fSlopeVal := fProcVal;         // 斜率处样本值初始化
        _nSmpSlope := 0;                // 拐点时刻清零
        _nSmp := 0;                     // 采样计数清零
        _nSmpPrev := 0;                 // 节拍沿判据清零
        _fElapSec := 0.0;               // 累计时间清零
        bIdent := FALSE;                // 完成标志清除
        _eState := E_DL_SriState.eRamp; // 进响应跟踪相
    END_IF

E_DL_SriState.eRamp:
    IF _bFault THEN
        _eState := E_DL_SriState.eFault;    // 故障相
    ELSIF tonGuardTo.Q THEN
        _uFault := 16#0002_03A6;            // 故障级：辨识总超时
        _bFault := TRUE;
        _eState := E_DL_SriState.eFault;
    ELSE
        IF tonSamp.Q THEN                   // 采样节拍到（TON 自复位口径：本件 IN 为相电平，节拍由 Q 检出）
            _nSmp := _nSmp + 1;             // 采样计数递增
            _fElapSec := INT_TO_LREAL(_nSmp) * _fSampSec;   // 累计时间推进
            IF _nSmp >= 256 THEN
                _uInfo := 16#0002_048D;     // 信息级：采样窗饱和（停录继续判稳）
            ELSE
                _fY3Prev := _fYPrev;        // 滑窗推进（简化 3 点窗：上拍即 2 拍前）
            END_IF
            _fSlope := (fProcVal - _fY3Prev) / (_fSampSec * 2.0);
                                                // 3 点滑窗差分斜率（分母为组态常量已过闸，防除零）
            IF (_fSlope <> _fSlope) OR ((fProcVal <> fProcVal)) THEN
                _uFault := 16#0002_03A7;    // 故障级：样本/斜率非有限
                _bFault := TRUE;
            ELSIF ABS(_fSlope) > _fSlopeMax THEN
                _fSlopeMax := ABS(_fSlope); // 最大斜率刷新
                _fSlopeVal := fProcVal;     // 拐点样本值记忆
                _nSmpSlope := _nSmp;        // 拐点时刻记忆（采样计数口径）
            END_IF
            _fYPrev := fProcVal;            // 上拍快照推进
        END_IF
        IF (NOT _bFault) AND tonSteadyTo.Q THEN
            _fYss := fProcVal;              // 稳态锁定
            _uInfo := 16#0002_048B;         // 信息级：辨识完成沿（伴随态并入）
            _eState := E_DL_SriState.eDone; // 进完成相
        ELSIF NOT _bFault THEN
            _uInfo := 16#0002_048C;         // 信息级：稳态确认中
        END_IF
    END_IF

E_DL_SriState.eDone:
    bIdent := TRUE;                     // 完成标志保持
    IF NOT _bIdentPrev THEN
        (* 切线法换算（仅在完成沿执行一次；分母已过防除零闸） *)
        IF _fSlopeMax < 1.0E-12 THEN
            _uFault := 16#0002_03A7;    // 故障级：斜率退化（防除零兜底）
            _bFault := TRUE;
            _eState := E_DL_SriState.eFault;
        ELSE
            fK := (_fYss - _fY0) / fStepCmd;
                                                // 增益：K = ΔY/ΔU（幅值非零已过闸）
            fTheta := INT_TO_LREAL(_nSmpSlope) * _fSampSec
                      - (_fSlopeVal - _fY0) / _fSlopeMax;
                                                // 切线法：θ = t_inf - (y_inf - Y0)/slope（切线与基线交点）
            IF fTheta < 0.0 THEN
                fTheta := 0.0;              // θ >= 0 判据显式钳位
            END_IF
            fT := (_fYss - _fY0) / _fSlopeMax - fTheta;
                                                // 时间常数：T = ΔY/slope - θ（切线与稳态渐近线交点差）
            IF fT < 0.0 THEN
                fT := 0.0;                  // T >= 0 判据显式钳位
            END_IF
        END_IF
    END_IF

E_DL_SriState.eFault:
    ;                                   // 故障相：等复位沿（段 2 承载迁出）

ELSE
    _uFault := 16#0002_03A8;            // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_SriState.eFault;    // 强制回故障相

END_CASE

(* —— 段 4：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bValid := bIdent AND (NOT _bFault);     // 结果可用（完成且无故障）
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bValid := FALSE;                // 故障期强制 FALSE（安全侧）
    bIdent := FALSE;                // 故障期完成标志清除（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
_bIdentPrev := bIdent;              // 完成沿判据快照

END_FUNCTION_BLOCK
