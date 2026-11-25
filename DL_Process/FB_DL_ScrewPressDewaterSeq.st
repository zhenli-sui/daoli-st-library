(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FB_DL_ScrewPressDewaterSeq
  分类: DL_Process
  复杂度: C4 ｜ 版本: 1.0.0 ｜ 2026-11-24
  平台兼容: CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
  开源溯源: 无（clean-room 工程时序自研；参考公开的螺旋压榨脱水机单循环工艺步骤，
            未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)

  功能职责:
    污泥螺旋压榨脱水机单循环时序：进泥 → 加药混合 → 压榨 → 冲洗 → 退让复位。
    互锁：eFeed 要求 bFeedOk AND bPolyOk（缺料进故障码 21）；ePress 期间 bPressHigh
    累计超过 tPress 的 30% 即提前转 eFlush（过压保护，码 22，先降后报的安全侧）；
    bPressFault 任意相进故障码 23 并在同一拍切断 bPressMotor；bStop 任意相转 eRetract（码 26）。

  输入/输出契约:
    IN  bStart 上升沿启动；bStop 任意相转退让相；bReset 上升沿是 eFault 唯一出口。
    OUT 四个执行输出全部为「单稳态、每拍按相位重算、不锁存」，eFault 内全部 FALSE。

  码表 (Codes):
    21 = 进泥或加药未就绪（故障级；转 eFault）
    22 = 压榨过压提前转冲洗（降级级安全侧；不置故障相）
    23 = 压榨机故障（故障级；同拍断 bPressMotor）
    24 = 泥饼含固率低于设定（信息级；本循环照常结束，仅记录）
    25 = 泥饼含固率信号非有限（故障级）
    26 = 停止指令触发退让（信息级）
    27 = 时间参数越域且不满足 tPress > tMix（故障级；约束不成立则过压窗口无意义）
    28 = 过压触发次数达上限（故障级；同一循环内反复过压视为机械异常）
    99 = 非法状态枚举值（ELSE 兜底）

  边界与红线:
    ① 六个 TON 与两个 R_TRIG 全在 CASE 外无条件刷新（R7），CASE 内只读 .Q / .ET。
    ② 每个 TON 的 IN 均串本相闸并带 NOT .Q 自复位（R188）；tonHigh 的 IN 是 ePress 相内
       的「过压累计窗」，属本相看门狗而非跨相累计（红线 14 声明）。
    ③ 约束: tPress > tMix（压榨时长必须大于混合时长，否则过压保护窗口早于压榨建立）。
       该约束不仅写在注释，还在段 2 做运行期断言，不满足即故障码 27（fail-closed）。
    ④ R528：bStart 必须上升沿且进料/加药条件同时就绪才迁 eFeed，全默认引脚时停留 eIdle。
    ⑤ eFault 出口 = rtReset.Q AND NOT _bFaultCondNow（逐码反算残留条件，R28 可达性）。
    ⑥ 过压次数计数 _iPressTripCnt 有容量载体 DL_SPR_TRIP_MAX 并饱和，每触发一次步进 1。
  修订历史: 2026-11-24  v1.0.0  R82-B 首版
*)

TYPE E_DL_SPR_STATE :
(
    eIdle    := 0,    // 空闲：等启动上升沿 / Idle: waiting for the start rising edge
    eFeed    := 1,    // 进泥相：进泥阀开、加药泵随动 / Feed phase: feed valve open, polymer pump following
    eMix     := 2,    // 混合相：加药泵继续，絮体反应 / Mix phase: polymer pump continues, floc reaction
    ePress   := 3,    // 压榨相：压榨电机运行，过压保护生效 / Press phase: press motor running with overpressure protection
    eFlush   := 4,    // 冲洗相：冲洗阀开 / Flush phase: flush valve open
    eRetract := 5,    // 退让相：全输出关，等退让计时 / Retract phase: all outputs off, waiting for the retract timer
    eFault   := 6     // 故障安全相：全部执行输出 FALSE / Fault safe phase: all actuator outputs FALSE
);
END_TYPE

FUNCTION_BLOCK FB_DL_ScrewPressDewaterSeq
VAR_INPUT
    bStart       : BOOL := FALSE;     // 启动（上升沿有效）/ Start, rising edge only
    bStop        : BOOL := FALSE;     // 停止（任意相转退让相）/ Stop, any phase moves to retract
    bReset       : BOOL := FALSE;     // 复位（上升沿，eFault 唯一出口）/ Reset rising edge, the only fault exit
    bFeedOk      : BOOL := FALSE;     // 进泥条件就绪（泥位/泵/阀位）/ Feed condition ready, level, pump and valve position
    bPolyOk      : BOOL := FALSE;     // 加药条件就绪（药液在位/计量泵就绪）/ Polymer condition ready
    bPressHigh   : BOOL := FALSE;     // 压榨压力高开关 / Press overpressure switch
    bPressFault  : BOOL := FALSE;     // 压榨机故障（电机保护/堵转/变频器故障）/ Press machine fault, motor protection, jam or drive fault
    rCakeTsPct   : REAL := 0.0;       // 泥饼含固率实测 [%] / Measured cake solids content [%]
    rCakeTsSp    : REAL := 0.0;       // 泥饼含固率设定 [%] / Cake solids content setpoint [%]
    tFeed        : TIME := T#60S;     // 进泥时长，有效域 100ms..4h [s] / Feed duration, valid domain 100ms..4h [s]
    tMix         : TIME := T#60S;     // 混合时长，有效域 100ms..4h [s] / Mix duration, valid domain 100ms..4h [s]
    tPress       : TIME := T#5M;      // 压榨时长，约束 tPress > tMix [s] / Press duration, constrained above tMix [s]
    tFlush       : TIME := T#30S;     // 冲洗时长，有效域 100ms..4h [s] / Flush duration, valid domain 100ms..4h [s]
    tRetract     : TIME := T#20S;     // 退让时长，有效域 100ms..4h [s] / Retract duration, valid domain 100ms..4h [s]
END_VAR
VAR_OUTPUT
    bFeedValve   : BOOL := FALSE;     // 进泥阀（单稳态，每拍重算）/ Feed valve, monostable, recomputed every scan
    bPolyPump    : BOOL := FALSE;     // 加药计量泵（单稳态，每拍重算）/ Polymer dosing pump, monostable, recomputed every scan
    bPressMotor  : BOOL := FALSE;     // 压榨电机（单稳态，故障同拍切断）/ Press motor, monostable, cut in the same scan on fault
    bFlushValve  : BOOL := FALSE;     // 冲洗阀（单稳态，每拍重算）/ Flush valve, monostable, recomputed every scan
    iErrCode     : INT := 0;          // 错误码（故障期锁存回放）/ Error code, latched replay during fault
    sMsg         : STRING;            // 文本提示（当前相位摘要）/ Text message, a summary of the current phase
END_VAR
VAR
    _eState        : E_DL_SPR_STATE := E_DL_SPR_STATE.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch   : BOOL := FALSE;   // 故障锁存位 / Fault latch
    _iErrLatch     : INT := 0;        // 锁存故障码（故障期唯一回放源）/ Latched fault code, the only replay source during fault
    _iInfoCode     : INT := 0;        // 信息级/降级级码 / Info or degraded-level code
    _iErrTmp       : INT := 0;        // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq     : BOOL := FALSE;   // 当拍故障请求（段 5 统一锁存）/ Fault request of this scan, latched at segment 5
    _bFaultCondNow : BOOL := FALSE;   // 残留故障条件（eFault 出口唯一附加判据）/ Residual fault condition, the only extra fault-exit criterion
    _iPressTripCnt : INT := 0;        // 过压触发累计次数，容量载体 DL_SPR_TRIP_MAX [次] / Overpressure trip counter, capacity carrier DL_SPR_TRIP_MAX [count]
    _rCakeTsCl     : REAL := 0.0;     // 泥饼含固率净化副本 [%] / Sanitised cake solids copy [%]
    _tFeed         : TIME := T#60S;   // 进泥时长钳定值 [s] / Clamped feed duration [s]
    _tMix          : TIME := T#60S;   // 混合时长钳定值 [s] / Clamped mix duration [s]
    _tPress        : TIME := T#5M;    // 压榨时长钳定值 [s] / Clamped press duration [s]
    _tFlush        : TIME := T#30S;   // 冲洗时长钳定值 [s] / Clamped flush duration [s]
    _tRetract      : TIME := T#20S;   // 退让时长钳定值 [s] / Clamped retract duration [s]
    _tHigh         : TIME := T#90S;   // 过压保护窗口 = tPress 的 30% [s] / Overpressure window, thirty percent of tPress [s]
    _diPressMs     : DINT := 0;       // 压榨时长毫秒值 [ms] / Press duration in milliseconds [ms]
    _diHighMs      : DINT := 0;       // 过压窗口毫秒值 [ms] / Overpressure window in milliseconds [ms]
    rtReset        : R_TRIG;          // bReset 边沿（段 3 无条件刷新）/ bReset edge, refreshed unconditionally
    rtStart        : R_TRIG;          // bStart 边沿（段 3 无条件刷新，R528）/ bStart edge, refreshed unconditionally
    tonFeed        : TON;             // 进泥计时（本相单发，自复位）/ Feed timer, single shot in its phase
    tonMix         : TON;             // 混合计时（本相单发，自复位）/ Mix timer, single shot in its phase
    tonPress       : TON;             // 压榨计时（本相单发，自复位）/ Press timer, single shot in its phase
    tonHigh        : TON;             // 过压累计窗计时（本相看门狗，自复位）/ Overpressure window timer, phase watchdog with self reset
    tonFlush       : TON;             // 冲洗计时（本相单发，自复位）/ Flush timer, single shot in its phase
    tonRetract     : TON;             // 退让计时（本相单发，自复位）/ Retract timer, single shot in its phase
END_VAR
VAR CONSTANT
    DL_SPR_EPS       : REAL := 1.0E-6;    // 数值闸阈值 [-]/ Numeric guard threshold [-]
    DL_SPR_FIN       : REAL := 1.0E15;    // 非有限判据阈值（ABS 比较用）[-] / Non-finite criterion threshold, compared by ABS [-]
    DL_SPR_HIGH_PCT  : DINT := 30;        // 过压保护窗口占压榨时长百分比 [%] / Overpressure window as a percentage of the press duration [%]
    DL_SPR_PCT_BASE  : DINT := 100;       // 百分比基准值 [%] / Percentage base value [%]
    DL_SPR_TRIP_MAX  : INT := 3;          // 单循环过压触发上限 [次] / Overpressure trip limit per cycle [count]
    DL_SPR_ONE       : INT := 1;          // 计数步进一 [1] / Counter step of one [1]
    DL_SPR_ZERO      : INT := 0;          // 计数零基准 [-] / Counter zero base [-]
    DL_SPR_T_MIN     : TIME := T#100MS;   // 时间参数下限 [s] / Time parameter lower bound [s]
    DL_SPR_T_MAX     : TIME := T#4H;      // 时间参数上限 [s] / Time parameter upper bound [s]
    DL_SPR_T_FEED_DEF: TIME := T#60S;     // 进泥时长默认回退值（在域内）[s] / Default feed duration inside the domain [s]
    DL_SPR_T_MIX_DEF : TIME := T#60S;     // 混合时长默认回退值（在域内）[s] / Default mix duration inside the domain [s]
    DL_SPR_T_PRESS_DEF: TIME := T#5M;     // 压榨时长默认回退值（在域内）[s] / Default press duration inside the domain [s]
    DL_SPR_T_FLUSH_DEF: TIME := T#30S;    // 冲洗时长默认回退值（在域内）[s] / Default flush duration inside the domain [s]
    DL_SPR_T_RETR_DEF: TIME := T#20S;     // 退让时长默认回退值（在域内）[s] / Default retract duration inside the domain [s]
END_VAR

(* —— 段 1：中间量预置（只清当拍扫描量，不清锁存/过压计数，FB32-1） —— *)
_iErrTmp   := 0;                                   // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq := FALSE;                               // 当拍故障请求复位 / Scan fault request reset

(* —— 段 2：时间参数两级回退 + 运行期约束断言 + 入参净化 —— *)
IF (tFeed < DL_SPR_T_MIN) OR (tFeed > DL_SPR_T_MAX) THEN
    _tFeed := DL_SPR_T_FEED_DEF;                   // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tFeed := tFeed;                               // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tMix < DL_SPR_T_MIN) OR (tMix > DL_SPR_T_MAX) THEN
    _tMix := DL_SPR_T_MIX_DEF;                     // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tMix := tMix;                                 // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tPress < DL_SPR_T_MIN) OR (tPress > DL_SPR_T_MAX) THEN
    _tPress := DL_SPR_T_PRESS_DEF;                 // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tPress := tPress;                             // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tFlush < DL_SPR_T_MIN) OR (tFlush > DL_SPR_T_MAX) THEN
    _tFlush := DL_SPR_T_FLUSH_DEF;                 // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tFlush := tFlush;                             // 域内：原值采用 / Inside the domain: use as given
END_IF
IF (tRetract < DL_SPR_T_MIN) OR (tRetract > DL_SPR_T_MAX) THEN
    _tRetract := DL_SPR_T_RETR_DEF;                // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tRetract := tRetract;                         // 域内：原值采用 / Inside the domain: use as given
END_IF
_rCakeTsCl := rCakeTsPct;                          // 泥饼含固率副本，参与干度比较 / Cake solids copy used by the dryness comparison
IF (ABS(_rCakeTsCl) > DL_SPR_FIN) OR (_rCakeTsCl < 0.0) THEN
    _rCakeTsCl := 0.0;                             // 非有限或负值兜底为零 / Non-finite or negative falls back to zero
END_IF
_diPressMs := TIME_TO_DINT(_tPress);               // 压榨时长转毫秒 [ms] / Press duration converted to milliseconds [ms]
IF _diPressMs > 0 THEN
    // 量纲: (ms)/(%)*(%) = ms，整数先除基准再乘占比，避免中间量越 DINT 域
    _diHighMs := (_diPressMs / DL_SPR_PCT_BASE) * DL_SPR_HIGH_PCT;   // 过压窗口毫秒值 [ms] / Overpressure window in milliseconds [ms]
ELSE
    _diHighMs := 0;                                // 分母闸：时长为零则不设窗口 / Denominator guard: no window when the duration is zero
END_IF
_tHigh := DINT_TO_TIME(_diHighMs);                 // 毫秒值回转 TIME [s] / Milliseconds converted back to TIME [s]
_bFaultCondNow := FALSE;                           // 残留条件预置（eFault 出口唯一附加判据）/ Residual preset, the only extra fault-exit criterion
IF _iErrLatch = 21 THEN
    _bFaultCondNow := NOT (bFeedOk AND bPolyOk);   // 码 21：进料/加药条件仍缺 / Code 21: feed or polymer condition still missing
ELSIF _iErrLatch = 23 THEN
    _bFaultCondNow := bPressFault;                 // 码 23：压榨故障仍存在 / Code 23: press fault still present
ELSIF _iErrLatch = 25 THEN
    _bFaultCondNow := (ABS(rCakeTsPct) > DL_SPR_FIN);   // 码 25：含固率信号仍非有限 / Code 25: the solids signal is still non-finite
ELSIF _iErrLatch = 27 THEN
    _bFaultCondNow := (_tPress <= _tMix);          // 码 27：约束仍不成立 / Code 27: the constraint still fails
END_IF
(* 码 28（过压次数达上限）由计数驱动、无输入残留条件，复位沿单独即可退出；码 99 同理。 / Codes 28 and 99 have no residual input condition *)

(* —— 段 3：边沿与定时器（全部在 CASE 外无条件刷新，R7；IN 带 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                            // 复位边沿无条件刷新 / Reset edge refreshed unconditionally
rtStart(CLK := bStart);                            // 启动边沿无条件刷新（R528 起点判据）/ Start edge refreshed unconditionally
tonFeed(IN := (_eState = E_DL_SPR_STATE.eFeed) AND (NOT tonFeed.Q) AND (NOT _bFaultLatch),
        PT := _tFeed);                             // 本相单发计时：仅进泥相 / Single-shot timer in the feed phase only
tonMix(IN := (_eState = E_DL_SPR_STATE.eMix) AND (NOT tonMix.Q) AND (NOT _bFaultLatch),
       PT := _tMix);                               // 本相单发计时：仅混合相 / Single-shot timer in the mix phase only
tonPress(IN := (_eState = E_DL_SPR_STATE.ePress) AND (NOT tonPress.Q) AND (NOT _bFaultLatch),
         PT := _tPress);                           // 本相单发计时：仅压榨相 / Single-shot timer in the press phase only
tonHigh(IN := (_eState = E_DL_SPR_STATE.ePress) AND bPressHigh AND (NOT tonHigh.Q) AND (NOT _bFaultLatch),
        PT := _tHigh);                             // 本相过压累计窗：压榨相内压力高持续累计，与压榨总时长计时独立 / Phase overpressure watchdog, independent of the total press timer
tonFlush(IN := (_eState = E_DL_SPR_STATE.eFlush) AND (NOT tonFlush.Q) AND (NOT _bFaultLatch),
         PT := _tFlush);                           // 本相单发计时：仅冲洗相 / Single-shot timer in the flush phase only
tonRetract(IN := (_eState = E_DL_SPR_STATE.eRetract) AND (NOT tonRetract.Q) AND (NOT _bFaultLatch),
           PT := _tRetract);                       // 本相单发计时：仅退让相 / Single-shot timer in the retract phase only

(* —— 段 4：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 5 执行） —— *)
CASE _eState OF
    E_DL_SPR_STATE.eIdle :
        (* 迁移①：拍 N 进入（启动上升沿）/ 本拍行为：三项前置校验（进料、加药、时间约束）/ 拍 N+1 转出至进泥相 *)
        IF rtStart.Q AND (NOT _bFaultLatch) THEN
            IF (NOT bFeedOk) OR (NOT bPolyOk) THEN
                _iErrTmp   := 21;                            // 故障级：进泥或加药未就绪 / Fault: feed or polymer not ready
                _bFaultReq := TRUE;                          // 请求段 5 锁存 / Request the latch at segment 5
            ELSIF _tPress <= _tMix THEN
                _iErrTmp   := 27;                            // 故障级：约束 tPress > tMix 不成立 / Fault: the tPress above tMix constraint fails
                _bFaultReq := TRUE;                          // 请求段 5 锁存 / Request the latch at segment 5
            ELSIF ABS(rCakeTsPct) > DL_SPR_FIN THEN
                _iErrTmp   := 25;                            // 故障级：含固率信号非有限 / Fault: non-finite solids signal
                _bFaultReq := TRUE;                          // 请求段 5 锁存 / Request the latch at segment 5
            ELSE
                _iPressTripCnt := DL_SPR_ZERO;               // 新循环：过压计数归零 / New cycle: trip counter cleared
                _iInfoCode     := 0;                         // 新循环：信息码归零 / New cycle: info code cleared
                _eState        := E_DL_SPR_STATE.eFeed;      // 迁移①：进泥相 / Move to the feed phase
            END_IF
        END_IF

    E_DL_SPR_STATE.eFeed :
        (* 迁移②：拍 N 进入 / 本拍行为：进泥阀与加药泵随动，逐拍复检进料条件 / 拍 N+1 转出至混合相或故障相 *)
        IF (NOT bFeedOk) OR (NOT bPolyOk) THEN
            _iErrTmp   := 21;                                // 故障级：运行中进料条件丢失 / Fault: the feed condition is lost while running
            _bFaultReq := TRUE;                              // 请求段 5 锁存 / Request the latch at segment 5
        ELSIF tonFeed.Q THEN
            _eState := E_DL_SPR_STATE.eMix;                  // 迁移②：进泥完成，转混合相 / Feed complete, move to mix
        END_IF

    E_DL_SPR_STATE.eMix :
        (* 迁移③：拍 N 进入 / 本拍行为：加药泵继续，絮体反应 / 拍 N+1 转出至压榨相 *)
        IF tonMix.Q THEN
            _iInfoCode := 0;                                 // 混合完成：清信息码 / Mix complete: info code cleared
            _eState    := E_DL_SPR_STATE.ePress;             // 迁移③：转压榨相 / Move to press
        END_IF

    E_DL_SPR_STATE.ePress :
        (* 迁移④⑤：拍 N 进入 / 本拍行为：压榨电机运行，过压累计窗与总时长同时计时 / 拍 N+1 转出至冲洗或故障相 *)
        IF tonHigh.Q THEN
            _iInfoCode := 22;                                // 降级级：过压提前转冲洗（安全侧，先降后报）/ Degraded: early flush on overpressure
            IF _iPressTripCnt < DL_SPR_TRIP_MAX THEN
                _iPressTripCnt := _iPressTripCnt + DL_SPR_ONE;   // 过压次数净额 +1，达容量上限饱和 / Net trip increment, saturated at capacity
            END_IF
            IF _iPressTripCnt >= DL_SPR_TRIP_MAX THEN
                _iErrTmp   := 28;                            // 故障级：反复过压视为机械异常 / Fault: repeated overpressure indicates a mechanical problem
                _bFaultReq := TRUE;                          // 请求段 5 锁存 / Request the latch at segment 5
            ELSE
                _eState := E_DL_SPR_STATE.eFlush;            // 迁移④：提前转冲洗相 / Move to flush early
            END_IF
        ELSIF (rCakeTsSp > DL_SPR_EPS) AND (_rCakeTsCl < rCakeTsSp) THEN
            _iInfoCode := 24;                                // 信息级：泥饼干度不足（设定未配置则不告警，域闸用 EPS）/ Info: the cake is not dry enough, skipped when the setpoint is unconfigured
            IF tonPress.Q THEN
                _eState := E_DL_SPR_STATE.eFlush;            // 迁移⑤：压榨时长到，转冲洗相 / Press time elapsed, move to flush
            END_IF
        ELSIF tonPress.Q THEN
            _eState := E_DL_SPR_STATE.eFlush;                // 迁移⑤：压榨时长到，转冲洗相 / Press time elapsed, move to flush
        END_IF

    E_DL_SPR_STATE.eFlush :
        (* 迁移⑥：拍 N 进入 / 本拍行为：冲洗阀开，压榨电机已停 / 拍 N+1 转出至退让相 *)
        IF tonFlush.Q THEN
            _eState := E_DL_SPR_STATE.eRetract;              // 迁移⑥：转退让相 / Move to retract
        END_IF

    E_DL_SPR_STATE.eRetract :
        (* 迁移⑦：拍 N 进入（正常结束或 bStop 重定向）/ 本拍行为：全输出关，等退让计时 / 拍 N+1 转出至空闲相 *)
        IF tonRetract.Q THEN
            _eState := E_DL_SPR_STATE.eIdle;                 // 迁移⑦：回空闲相 / Back to idle
        END_IF

    E_DL_SPR_STATE.eFault :
        (* 迁移⑧：拍 N 进入 / 本拍行为：只等出口条件（复位沿 + 残留条件消失）/ 拍 N+1 转出至 eIdle *)
        IF rtReset.Q AND (NOT _bFaultCondNow) THEN
            _bFaultLatch   := FALSE;                         // 清故障锁存 / Clear the fault latch
            _iErrLatch     := 0;                             // 清锁存故障码 / Clear the latched code
            _iInfoCode     := 0;                             // 清信息码 / Clear the info code
            _iPressTripCnt := DL_SPR_ZERO;                   // 过压计数清零 / Trip counter cleared
            _eState        := E_DL_SPR_STATE.eIdle;          // 回空闲相，不滞留 / Back to idle, never parked
        END_IF
ELSE
    (* 迁移⑨：非法枚举兜底（R6），码位赋值与锁存 3 行内配对（R45） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                                  // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                                // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 5：故障锁存 + 段尾迁相 + bStop 退让重定向 + 撤启动降级（R191 已声明） —— *)
IF bPressFault AND (NOT _bFaultLatch) THEN
    _iErrTmp   := 23;                                        // 故障级：压榨机故障（相位无关，同拍切 bPressMotor）/ Fault: press machine fault, phase independent, the motor is cut in the same scan
    _bFaultReq := TRUE;                                      // 请求本次锁存 / Request the latch in this scan
END_IF
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                                // 锁存当拍首因 / Latch the first cause of this scan
    _bFaultLatch := TRUE;                                    // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_SPR_STATE.eFault) THEN
    _eState := E_DL_SPR_STATE.eFault;                        // 锁存即迁相（段尾统一执行）/ The latch forces the fault phase at the tail
END_IF
IF bStop AND (NOT _bFaultLatch) AND (_eState <> E_DL_SPR_STATE.eIdle)
   AND (_eState <> E_DL_SPR_STATE.eRetract) AND (_eState <> E_DL_SPR_STATE.eFault) THEN
    _iInfoCode := 26;                                        // 信息级：停止指令触发退让 / Info: the stop command triggered a retract
    _eState    := E_DL_SPR_STATE.eRetract;                   // 任意相转退让相（bStop 优先于步序推进）/ Any phase moves to retract
END_IF

(* —— 段 6：统一出口（单稳态每拍重算，不锁存；eFault 内全部 FALSE） —— *)
bFeedValve  := (_eState = E_DL_SPR_STATE.eFeed) AND (NOT _bFaultLatch);    // 进泥阀仅进泥相 / The feed valve is open in the feed phase only
bPolyPump   := ((_eState = E_DL_SPR_STATE.eFeed) OR (_eState = E_DL_SPR_STATE.eMix))
               AND (NOT _bFaultLatch);                                     // 加药泵在进泥相与混合相 / The polymer pump runs in feed and mix
bPressMotor := (_eState = E_DL_SPR_STATE.ePress) AND (NOT _bFaultLatch);   // 压榨电机仅压榨相，故障同拍切断 / Press motor only in press, cut in the same scan on fault
bFlushValve := (_eState = E_DL_SPR_STATE.eFlush) AND (NOT _bFaultLatch);   // 冲洗阀仅冲洗相 / The flush valve is open in the flush phase only
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                                  // 故障期回放锁存码 / Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                                  // 非故障期输出信息/降级码 / Info or degraded code outside fault
END_IF
IF _eState = E_DL_SPR_STATE.eIdle THEN
    sMsg := 'IDLE';                                          // 空闲 / Idle
ELSIF _eState = E_DL_SPR_STATE.eFeed THEN
    sMsg := 'FEED';                                          // 进泥 / Feeding
ELSIF _eState = E_DL_SPR_STATE.eMix THEN
    sMsg := 'MIX';                                           // 混合 / Mixing
ELSIF _eState = E_DL_SPR_STATE.ePress THEN
    sMsg := 'PRESS';                                         // 压榨 / Pressing
ELSIF _eState = E_DL_SPR_STATE.eFlush THEN
    sMsg := 'FLUSH';                                         // 冲洗 / Flushing
ELSIF _eState = E_DL_SPR_STATE.eRetract THEN
    sMsg := 'RETRACT';                                       // 退让 / Retracting
ELSE
    sMsg := 'FAULT';                                         // 故障 / Fault
END_IF
END_FUNCTION_BLOCK
