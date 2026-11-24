(*
  Name        : FB_DL_EdgeIntervalMeter
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 双沿间隔/周期/占空比测量：以自复位自由计时器逐拍累计时基，上升沿与下降沿分别测周期与高电平宽度，附抖动（间隔一阶绝对偏差 EMA）与无沿超时判据；/ Measure edge interval, period and duty cycle via a self-resetting free-running time base, with jitter (EMA of absolute interval deviation) and a no-edge timeout verdict
  溯源        : 借 t2-1-lgf·dateandtimer 的分类/参数域组织，clean-room 实现
  Boundary    : ① 时基委托：tonFree 为 1 天 PT 的自复位自由计时器（IN := NOT tonFree.Q，R188），逐拍取 ET 差分累加；跨 1 天回卷那拍差分为负 → 钳 0，单拍损失已声明；
                ② 占空比除子闸：周期 <= eps → 占空比按 0 处理（不产生 Inf）；
                ③ 无沿判据用 TIME 直比（tTimeout > 0 已过组态闸），不额外占定时器实例；
                ④ 高电平宽度为「最近一次采样值」，下降沿那拍取上拍快照（一拍滞后已在头注释声明）；
                ⑤ 计数饱和：UDINT 到上限前停加，防回绕。
*)
TYPE E_DL_EimState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 测量运行 / Measuring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_EimCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：超时/扫描周期非正 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_EdgeIntervalMeter
VAR_INPUT
    bSignal   : BOOL := FALSE;               (* 被测数字信号 [-] / Monitored digital signal *)
    tTimeout  : TIME := T#5S;                (* 无沿超时判据，域 > T#0S [ms] / No-edge timeout, must be > 0 *)
    bEnable   : BOOL := TRUE;                (* 测量使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清全部统计与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    tInterval    : TIME;                     (* 最近一次上升沿间隔（周期）[ms] / Latest rising-to-rising interval *)
    tPulseWidth  : TIME;                     (* 最近一次高电平宽度（下降沿锁存）[ms] / Latest high pulse width, latched on falling *)
    fDuty        : REAL;                     (* 占空比 = 高宽 / 周期，域 0..1 [-] / Duty cycle, 0..1 *)
    fJitterMs    : REAL;                     (* 间隔抖动（绝对偏差 EMA）[ms] / Interval jitter, EMA of abs deviation *)
    tIntervalMin : TIME;                     (* 窗口最小间隔（本测量生命周期）[ms] / Minimum interval seen *)
    tIntervalMax : TIME;                     (* 窗口最大间隔（本测量生命周期）[ms] / Maximum interval seen *)
    bNoEdge      : BOOL;                     (* 超时无沿指示 [-] / No-edge timeout indicator *)
    nEdgeCnt     : UDINT;                    (* 累计上升沿数（饱和）[-] / Rising edge count, saturated *)
    eState       : E_DL_EimState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_EimCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState    : E_DL_EimState := E_DL_EimState.eIdle;   (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause    : E_DL_EimCause := E_DL_EimCause.eNone;   (* 故障成因锁存量 / Latched cause *)
    rtSig      : R_TRIG;                     (* 上升沿实例，段 0 无条件调用 / Rising edge instance *)
    ftSig      : F_TRIG;                     (* 下降沿实例，段 0 无条件调用 / Falling edge instance *)
    rtReset    : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonFree    : TON;                        (* 自由跑时基（PT = 1 天，自复位） / Free-running time base *)
    _tFreePrev : TIME;                       (* 上拍自由时基 ET 快照（差分用）[ms] / Previous free ET snapshot *)
    _tDelta    : TIME;                       (* 本拍时基增量（回卷拍钳 0）[ms] / This-scan time delta *)
    _tSinceEdge: TIME;                       (* 距上次上升沿的累计时长 [ms] / Accumulated time since last rise *)
    _tHighLive : TIME;                       (* 高电平宽度实时值（下降沿取快照）[ms] / Live high width, snapshotted on fall *)
    _tPrevInt  : TIME;                       (* 上一次间隔（抖动基准）[ms] / Previous interval for jitter *)
    _fDev      : REAL;                       (* 本次间隔绝对偏差 [ms] / Absolute interval deviation *)
    _t0        : TIME;                       (* 时间零常量（比较基准）[ms] / Time zero constant *)
    _bFault    : BOOL;                       (* 故障锁存位 / Latched fault bit *)
    _bCfgBad   : BOOL;                       (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite   : BOOL;                       (* 信号有效标志（BOOL 入参恒有限，语义占位）[-] / Signal validity placeholder *)
END_VAR
VAR CONSTANT
    DL_EIM_EPS    : REAL  := 1.0E-6;         (* 除零判零容差（REAL 量级）[-] / Division epsilon *)
    DL_EIM_DAY    : TIME  := T#1D;           (* 自由时基自复位周期（1 天）[ms] / Free base period *)
    DL_EIM_CNTMAX : UDINT := 4294967295;     (* 沿计数饱和上限（R28）[-] / Edge count saturation cap *)
    DL_EIM_JITW   : REAL  := 0.3;            (* 抖动 EMA 新值权重 [-] / Jitter EMA new-sample weight *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；定时器/沿实例全在段 0，无 IF 包裹） —— *)
_bCfgBad := NOT (tTimeout > T#0S);                                             (* 组态闸：超时须为正（TIME 比较，无浮点） / Config gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
rtSig(CLK := bSignal);                                                         (* 上升沿每拍必调 / Rising edge every scan *)
ftSig(CLK := bSignal);                                                         (* 下降沿每拍必调 / Falling edge every scan *)
tonFree(IN := NOT tonFree.Q, PT := DL_EIM_DAY);                                (* 自由时基自复位（R188，禁外部沿清零） / Self-resetting free base *)
_tDelta := tonFree.ET - _tFreePrev;                                            (* 时基差分（ET 单调增，回卷拍为负） / Time delta *)
IF _tDelta < _t0 THEN
    _tDelta := _t0;                                                            (* 回卷拍差分为负：钳 0（单拍损失已声明） / Wrap: clamp to zero *)
END_IF
_tFreePrev := tonFree.ET;                                                      (* 本拍快照留给下拍差分 / Snapshot for next scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bFinite := TRUE;                                                              (* BOOL 入参恒有限（语义占位，保持全路径赋值） / Always finite *)
bNoEdge := FALSE;                                                              (* 无沿指示预清，仅运行相置位 / No-edge preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清全部统计 + 清时基 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_EimCause.eNone;                                            (* 清成因 / Clear cause *)
    tInterval := T#0S;                                                         (* 清间隔 / Clear interval *)
    tPulseWidth := T#0S;                                                       (* 清高宽 / Clear pulse width *)
    fDuty := 0.0;                                                              (* 清占空比 / Clear duty *)
    fJitterMs := 0.0;                                                          (* 清抖动 / Clear jitter *)
    tIntervalMin := T#0S;                                                      (* 清最小值 / Clear minimum *)
    tIntervalMax := T#0S;                                                      (* 清最大值 / Clear maximum *)
    nEdgeCnt := 0;                                                             (* 清沿计数 / Clear edge count *)
    _tSinceEdge := T#0S;                                                       (* 清距沿时长 / Clear since-edge *)
    _tHighLive := T#0S;                                                        (* 清高宽实时值 / Clear live width *)
    _tPrevInt := T#0S;                                                         (* 清抖动基准 / Clear jitter base *)
    _eState := E_DL_EimState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189；故障相不按当下输入重推码） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_EimCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_EimState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_EimState.eIdle:                                                       (* 未使能：时基清零，出口保持 0 / Disabled *)
        _tSinceEdge := T#0S;                                                   (* 距沿时长清零（失能即无测量语义） / Since-edge cleared *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_EimState.eRun;                                     (* 使能进入测量 / Enter measuring *)
        END_IF
    E_DL_EimState.eRun:                                                        (* 测量相：时基累加 + 双沿派生 / Measuring *)
        IF NOT bEnable THEN
            _eState := E_DL_EimState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            _tSinceEdge := _tSinceEdge + _tDelta;                              (* 距沿时长累加（本拍增量已钳非负） / Accumulate *)
            IF bSignal THEN
                _tHighLive := _tHighLive + _tDelta;                            (* 高电平期间累积宽度 / Accumulate high width *)
            END_IF
            IF rtSig.Q THEN                                                    (* 上升沿：结算一个完整周期 / Rising edge: close one period *)
                tInterval := _tSinceEdge;                                      (* 本周期 = 距上次上升沿时长 [ms] / Period *)
                IF (nEdgeCnt > 0) AND (tInterval > T#0S) THEN
                    IF (tIntervalMin = T#0S) OR (tInterval < tIntervalMin) THEN
                        tIntervalMin := tInterval;                             (* 最小值更新（首值直取） / Update minimum *)
                    END_IF
                    IF tInterval > tIntervalMax THEN
                        tIntervalMax := tInterval;                             (* 最大值更新 / Update maximum *)
                    END_IF
                    _fDev := ABS(TIME_TO_LREAL(tInterval) - TIME_TO_LREAL(_tPrevInt));   (* 绝对偏差 [ms] / Absolute deviation *)
                    fJitterMs := DL_EIM_JITW * _fDev + (1.0 - DL_EIM_JITW) * fJitterMs;  (* 抖动 EMA（系数和 = 1，无漂移） / Jitter EMA *)
                END_IF
                _tPrevInt := tInterval;                                        (* 抖动基准更新 / Jitter base update *)
                _tSinceEdge := T#0S;                                           (* 距沿时长重新起算 / Restart since-edge *)
                _tHighLive := T#0S;                                            (* 新高电平段起算 / Restart high width *)
                IF nEdgeCnt < DL_EIM_CNTMAX THEN
                    nEdgeCnt := nEdgeCnt + 1;                                  (* 沿计数饱和累加 / Saturating count *)
                END_IF
                bNoEdge := FALSE;                                              (* 有沿即清超时 / Edge clears timeout *)
            END_IF
            IF ftSig.Q THEN                                                    (* 下降沿：锁存高宽（取上拍实时快照，一拍滞后） / Falling: latch width *)
                tPulseWidth := _tHighLive;                                     (* 高电平宽度锁存 [ms] / Latch width *)
                IF tInterval > T#0S THEN
                    fDuty := TIME_TO_LREAL(tPulseWidth) / TIME_TO_LREAL(tInterval);   (* 占空比：除子已判正 [0..1] / Duty, divisor gated *)
                    IF fDuty > 1.0 THEN
                        fDuty := 1.0;                                          (* 上限饱和 1.0（量测噪声防越界） / Clamp to 1.0 *)
                    ELSIF fDuty < 0.0 THEN
                        fDuty := 0.0;                                          (* 下限饱和 0.0 / Clamp to 0.0 *)
                    END_IF
                ELSE
                    fDuty := 0.0;                                              (* 周期未建立：占空比按 0（边界②） / No period yet: duty 0 *)
                END_IF
            END_IF
            IF _tSinceEdge > tTimeout THEN
                bNoEdge := TRUE;                                               (* 超时无沿判据（TIME 直比，除子无风险） / No-edge timeout *)
            END_IF
        END_IF
    E_DL_EimState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_EimState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_EimCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
