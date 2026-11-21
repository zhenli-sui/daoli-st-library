(*
  Name        : FB_DL_FilterWeekWindow
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 过滤器周维护窗与压差累计：按星期/小时维护窗到期提示，运行期累计压差积分（kPa·h）与压差超限告警，保养完成后一并清零；/ Filter weekly maintenance window and differential-pressure accumulation: window-due hint by weekday/hour, running kPa*h integral, DP-high alarm, all cleared on maintenance done
  溯源        : 借 ROADMAP P2（WeekOfYearCalc/RuntimeMeter 口径复用），clean-room 实现
  Boundary    : ① 组态闸：维护星期域 1..7 / 维护小时域 0..23 / 压差上限 > 0 / 周期 > 0 → 锁存故障；
                ② 压差积分仅在 eMon 相 + 过滤器运行电平下进行，非有限压差该拍不积分（防污染积分器，边界③）；
                ③ 维护窗匹配用「星期与小时同拍命中」沿触发（R_TRIG 提取，R187 两段式），窗期内重复命中不重复报；
                ④ bWindowDue 锁存至 bMaintDone 沿或复位沿（唯一两条清除路径，头注释声明清除边：bMaintDone 上升沿与 bReset 上升沿，R188）；
                ⑤ 压差积分饱和上限防 REAL 有效位耗尽（R28）；
                ⑥ 本件只提示与告警，不执行反吹/更换动作（属主边界）。
*)
TYPE E_DL_FwwState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 维护窗与压差监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_FwwCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：星期/小时/压差上限/周期越域 / Illegal config *)
    eWindowDue  := 2,                        (* 周维护窗到期 / Weekly window due *)
    eDpHigh     := 3,                        (* 压差超上限（滤芯堵塞判据） / DP above limit *)
    ePhaseBad   := 4                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FilterWeekWindow
VAR_INPUT
    fDp        : REAL := 0.0;                (* 过滤器压差实测 [kPa] / Measured differential pressure *)
    fDpMax     : REAL := 5.0;                (* 压差告警上限，域 > 0 [kPa] / DP alarm limit, > 0 *)
    bRunning   : BOOL := FALSE;              (* 过滤器运行电平（积分门控）[-] / Filter running level *)
    nDayOfWeek : INT := 1;                   (* 当前星期几（1 = 周一..7 = 周日），域 1..7 [日] / Current weekday, 1..7 *)
    nHourOfDay : INT := 0;                   (* 当前小时，域 0..23 [时] / Current hour, 0..23 *)
    nMaintDay  : INT := 1;                   (* 计划维护星期，域 1..7 [日] / Planned maintenance weekday *)
    nMaintHour : INT := 6;                   (* 计划维护小时，域 0..23 [时] / Planned maintenance hour *)
    bMaintDone : BOOL := FALSE;              (* 保养完成脉冲（清窗提示与压差累计，R188 声明清除边）[-] / Maintenance done pulse *)
    tCycle     : TIME := T#1S;               (* 运行周期，域 > T#0S [ms] / Cycle period, > 0 *)
    bEnable    : BOOL := TRUE;               (* 监视使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清累计与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDpHours   : REAL;                       (* 累计压差积分（运行期，饱和）[kPa·h] / DP integral, saturated *)
    bWindowDue : BOOL;                       (* 周维护窗到期锁存（保养沿/复位沿清）[-] / Weekly window due latched *)
    bDpHigh    : BOOL;                       (* 压差超限告警锁存（保养沿/复位沿清）[-] / DP-high alarm latched *)
    bMaintReq  : BOOL;                       (* 保养需求汇总（窗到期 OR 压差超限，电平）[-] / Maintenance demand summary *)
    eState     : E_DL_FwwState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_FwwCause;              (* 成因出口（R190 双成因独立归因） / Cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_FwwState := E_DL_FwwState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_FwwCause := E_DL_FwwCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtWin    : R_TRIG;                       (* 维护窗命中沿实例，段 0 无条件调用 / Window-hit edge *)
    rtMaint  : R_TRIG;                       (* 保养完成沿实例，段 0 无条件调用 / Maintenance-done edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin    : BOOL;                         (* 压差有限性当拍量 / DP finiteness *)
    _bWinHit : BOOL;                         (* 星期与小时同拍命中当拍量 / Weekday-hour hit this scan *)
    _fDtSec  : REAL;                         (* 周期折算秒值，域 > eps [s] / Period in seconds *)
    _fDpHI   : REAL;                         (* 压差积分中间量 [kPa·h] / DP integral intermediate *)
END_VAR
VAR CONSTANT
    DL_FWW_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_FWW_H2S    : REAL  := 3600.0;         (* 小时→秒换算常量（积分换算除子）[-] / Hours-seconds factor *)
    DL_FWW_DAYMAX : INT   := 7;              (* 星期域上限 [日] / Weekday domain max *)
    DL_FWW_HRMAX  : INT   := 23;             (* 小时域上限 [时] / Hour domain max *)
    DL_FWW_DPHMAX : REAL  := 1.0E7;          (* 压差积分饱和上限（防 REAL 有效位耗尽，R28）[kPa·h] / DP integral saturation cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG 全在段 0，无 IF 包裹） —— *)
_fDtSec := TIME_TO_LREAL(tCycle) / 1000.0;                                     (* 周期秒化（除子常量 1000） / Period to seconds *)
_bCfgBad := (nMaintDay < 1) OR (nMaintDay > DL_FWW_DAYMAX)                     (* 维护星期域闸 / Weekday gate *)
            OR (nMaintHour < 0) OR (nMaintHour > DL_FWW_HRMAX)                 (* 维护小时域闸 / Hour gate *)
            OR (fDpMax <= DL_FWW_EPS)                                          (* 压差上限正域闸 / DP limit gate *)
            OR NOT (tCycle > T#0S);                                            (* 周期正域闸 / Period gate *)
rtWin(CLK := _bWinHit);                                                        (* 窗命中沿每拍必调（命中量在下行派生，R_TRIG 用上拍值） / Window edge every scan *)
rtMaint(CLK := bMaintDone);                                                    (* 保养完成沿每拍必调 / Done edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bWinHit := (_eState = E_DL_FwwState.eMon)                                     (* 相位闸：仅监视相判窗（族③） / Phase gate *)
            AND (nDayOfWeek = nMaintDay) AND (nHourOfDay = nMaintHour);        (* 星期与小时同拍命中 / Weekday-hour match *)
_bFin := (fDp = fDp) AND ((fDp - fDp) = (fDp - fDp));                          (* 压差 NaN 自反 + Inf 差判闸 / DP NaN and Inf gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fDpHI := 0.0;                                                                 (* 积分中间量预清（积分拍覆盖） / Integral intermediate preset *)
bMaintReq := FALSE;                                                            (* 汇总出口预清 / Summary preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清提示与告警 + 清积分 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_FwwCause.eNone;                                            (* 清成因 / Clear cause *)
    bWindowDue := FALSE;                                                       (* 清窗到期锁存 / Clear window latch *)
    bDpHigh := FALSE;                                                          (* 清压差超限锁存 / Clear DP latch *)
    fDpHours := 0.0;                                                           (* 清压差积分出口 / Clear integral outlet *)
    _eState := E_DL_FwwState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_FwwCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_FwwState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_FwwState.eIdle:                                                       (* 未使能：出口确定值 / Disabled *)
        fDpHours := 0.0;                                                       (* 失能清积分出口 / Clear integral outlet *)
        bWindowDue := FALSE;                                                   (* 失能清窗提示出口 / Clear window outlet *)
        bDpHigh := FALSE;                                                      (* 失能清压差告警出口 / Clear DP outlet *)
        bMaintReq := FALSE;                                                    (* 失能清汇总出口 / Clear summary outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_FwwState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_FwwState.eMon:                                                        (* 监视相：窗判定 + 压差积分 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_FwwState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF rtWin.Q THEN                                                    (* 窗命中沿（窗期内同拍重复命中不重复触发，边界③） / Window-hit edge *)
                bWindowDue := TRUE;                                            (* 窗到期锁存（保养沿/复位沿清） / Latch window due *)
                _eCause := E_DL_FwwCause.eWindowDue;                           (* 成因：窗到期 / Cause: window due *)
            END_IF
            IF _bFin AND bRunning AND (_fDtSec > DL_FWW_EPS) THEN              (* 运行期积分（除子已闸） / Integrate while running *)
                _fDpHI := fDpHours + fDp * _fDtSec / DL_FWW_H2S;               (* 压差积分增量 = DP × dt / 3600 [kPa·h] / DP integral increment *)
                IF _fDpHI > DL_FWW_DPHMAX THEN
                    _fDpHI := DL_FWW_DPHMAX;                                   (* 积分饱和上限（最后一次写，R28） / Integral saturation, last write *)
                END_IF
                fDpHours := _fDpHI;                                            (* 积分出口 / Integral outlet *)
            END_IF
            IF _bFin AND (fDp > fDpMax) THEN                                   (* 压差超限判据（直比阈值，非浮点等值） / DP over limit *)
                bDpHigh := TRUE;                                               (* 超限锁存（保养沿/复位沿清） / Latch DP high *)
                _eCause := E_DL_FwwCause.eDpHigh;                              (* 成因：压差超限（最新成因覆盖，R190 独立位并存） / Cause: DP high *)
            END_IF
        END_IF
    E_DL_FwwState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_FwwState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_FwwCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：保养完成沿统一清零（清除边：bMaintDone 上升沿与 bReset 上升沿，R188 声明） + 出口映射 —— *)
IF rtMaint.Q AND NOT _bFault THEN
    bWindowDue := FALSE;                                                       (* 保养沿清窗提示 / Clear window latch *)
    bDpHigh := FALSE;                                                          (* 保养沿清压差告警 / Clear DP latch *)
    fDpHours := 0.0;                                                           (* 保养沿清压差积分 / Clear integral *)
    _eCause := E_DL_FwwCause.eNone;                                            (* 成因复位 / Cause reset *)
END_IF
bMaintReq := bWindowDue OR bDpHigh;                                            (* 保养需求汇总（名实同源，R191） / Summary re-derived *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
