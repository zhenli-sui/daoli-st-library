// FB_DL_MultiPumpRotationCtrl v1.0.0
(*==============================================================================
 * 功能描述: C4 多泵轮换均衡。2~4 台泵按累计运行小时数均衡轮换：领泵运行时间达
 *           tMinRun、小时差超 fBalThr 时经 eSwitch 两相切换（先停旧领泵，停机窗
 *           tMinStop 满窗后再启新领泵）；泵故障自动退出轮换池并告警，全池故障进
 *           eFault 锁存，bReset 上升沿唯一迁出。
 * 接口契约: 输入 bEnable/fDtSec/nPumpCount/aPumpFault/tMinRun/tMinStop/fBalThr/bReset；
 *           输出 abPumpRun/nLeadPump/nPoolCnt/eState/eCause/bError/nErrId。
 * 边界: ① 组态闸：nPumpCount 出 [2,4]、fDtSec<=0、tMinRun/tMinStop<=T#0S、fBalThr<0
 *           或任一浮点引脚 NaN → 故障锁存；② 泵槽位按常量 4 固定遍历，超组态槽位不参与；
 *           ③ 两枚 TON + 一枚 R_TRIG 段 0 无条件周期刷新；④ 零全局耦合。
 * 码表: 16#0007_0301 故障级总码（组态非法/全池故障/非法相位，锁存至 bReset 上升沿）；
 *       16#0007_0401 信息级：泵因故障退出轮换池（告警，每拍重算）。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

TYPE E_DL_MprState :
(
    eIdle   := 0,     // 待机（未使能或全停）/ Idle, disabled or all stopped
    eRun    := 10,    // 领泵运行相 / Lead pump running
    eSwitch := 20,    // 切换过渡相（旧领泵已停，等待停机窗）/ Switching transition, old lead stopped
    eFault  := 90     // 故障锁存相（仅复位沿迁出）/ Fault latched, exit by reset edge only
);
END_TYPE

TYPE E_DL_MprCause :
(
    eNone         := 0,   // 无故障成因 / No cause
    eCfgIllegal   := 1,   // 组态非法 / Illegal configuration
    eAllPumpFault := 2,   // 轮换池全空（全部泵故障）/ Rotation pool empty, all pumps faulted
    ePhaseBad     := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_MultiPumpRotationCtrl
VAR_INPUT
    bEnable    : BOOL := FALSE;            // 使能（FALSE 全停回待机）[-] / Enable, FALSE stops all
    fDtSec     : REAL := 0.010;            // 任务周期 [s]，域 > 0 / Task period [s], domain > 0
    nPumpCount : INT := 3;                 // 参与轮换泵数 [台]，域 [2,4] / Pump count in rotation, domain 2..4
    aPumpFault : ARRAY[1..4] OF BOOL := [FALSE, FALSE, FALSE, FALSE];   // 各泵故障反馈（TRUE 退出轮换池）[-] / Per-pump fault feedback
    tMinRun    : TIME := T#600S;           // 领泵最小运行时间，域 > T#0S [ms] / Minimum lead run time, domain > T#0S
    tMinStop   : TIME := T#60S;            // 被停泵最小停机时间，域 > T#0S [ms] / Minimum stop time, domain > T#0S
    fBalThr    : REAL := 1.0;              // 小时均衡切换阈值，域 >= 0 [h] / Hour balance threshold [h]
    bReset     : BOOL := FALSE;            // 复位，上升沿清故障锁存 [-] / Reset, rising edge clears fault
END_VAR
VAR_OUTPUT
    abPumpRun  : ARRAY[1..4] OF BOOL;      // 各泵启停指令（TRUE=运行）[-] / Per-pump run command
    nLeadPump  : INT := 0;                 // 当前领泵号（0=无领泵）[泵号] / Current lead pump index, 0 = none
    nPoolCnt   : INT := 0;                 // 当前轮换池泵数 [台] / Current pool size
    eState     : E_DL_MprState;            // 状态出口，段尾单点映射 / State outlet
    eCause     : E_DL_MprCause;            // 故障成因出口（归因唯一） / Fault cause outlet
    bError     : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    nErrId     : UDINT;                    // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    _eState    : E_DL_MprState := E_DL_MprState.eIdle;     // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_MprCause := E_DL_MprCause.eNone;     // 故障成因锁存量 / Latched cause
    rtReset    : R_TRIG;                    // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    tonMinRun  : TON;                       // 领泵最小运行计时，段 0 无条件刷新 / Lead min-run timer
    tonMinStop : TON;                       // 停机窗计时（eSwitch 相独占），段 0 无条件刷新 / Stop window timer
    _a_fHours  : ARRAY[1..4] OF REAL := [0.0, 0.0, 0.0, 0.0];   // 各泵累计运行小时 [h] / Per-pump accumulated run hours
    _nLead     : INT := 0;                  // 内部领泵号（锁存量）[泵号] / Internal lead pump index
    _nCand     : INT := 0;                  // 切换候选泵号（eSwitch 入相时锁定）[泵号] / Candidate pump locked at switch entry
    _nPoolCnt  : INT := 0;                  // 轮换池泵数工作值 [台] / Pool size working value
    _bCfgBad   : BOOL;                      // 组态非法当拍量 [-] / Illegal configuration this scan
    _bFault    : BOOL;                      // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;                     // 故障码锁存（锁存量） / Latched fault code
    _uInfo     : UDINT;                     // 信息码，每拍重算 / Info code, recomputed each scan
    _bAnyOut   : BOOL;                      // 本拍有泵退出轮换池当拍量 [-] / A pump left the pool this scan
    _iLoop     : INT;                       // 泵槽位遍历游标 [槽位] / Pump slot loop cursor
    _fBest     : REAL;                      // 最小小时数搜索工作值 [h] / Min-hours search working value
    _bFound    : BOOL;                      // 候选命中标志 [-] / Candidate found flag
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge, called every scan
tonMinRun(IN := (_eState = E_DL_MprState.eRun) AND (NOT _bFault), PT := tMinRun);   // 领泵运行计时 / Lead run timer
tonMinStop(IN := (_eState = E_DL_MprState.eSwitch), PT := tMinStop);               // 停机窗计时（切换相独占）/ Stop window timer

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_a_fHours/_nLead 不入清单） —— *)
_uInfo   := 16#0000_0000;                                          // 信息码每拍重算 / Info recomputed every scan
bError   := FALSE;                                                 // 故障标志每拍预清（置位处同拍回填） / Error flag preset
_bAnyOut := FALSE;                                                 // 退池事件标志预清 / Pool-exit flag preset
abPumpRun[1] := FALSE;                                             // 各泵指令每拍预清，运行相同拍回填 / Pump commands preset
abPumpRun[2] := FALSE;                                             // 各泵指令预清 / Pump commands preset
abPumpRun[3] := FALSE;                                             // 各泵指令预清 / Pump commands preset
abPumpRun[4] := FALSE;                                             // 各泵指令预清 / Pump commands preset
nLeadPump := 0;                                                    // 领泵号出口预清（eRun 相回填） / Lead outlet preset

(* —— 段 2：组态域闸（覆盖全部参与判据引脚） —— *)
_bCfgBad := (nPumpCount < 2) OR (nPumpCount > 4)                   // 泵数域闸 / Pump count domain gate
         OR (fDtSec <= 0.0) OR (fDtSec <> fDtSec)                  // 周期域与 NaN 闸 / Period domain and NaN gate
         OR (fBalThr < 0.0) OR (fBalThr <> fBalThr)                // 阈值域与 NaN 闸 / Threshold domain and NaN gate
         OR (tMinRun <= T#0S) OR (tMinStop <= T#0S);               // 时间域闸 / Time domain gates

(* —— 段 3：轮换池统计（常量 4 槽遍历，超组态槽位不参与，防越界） —— *)
_nPoolCnt := 0;                                                    // 池数清零重算 / Pool count recomputed
FOR _iLoop := 1 TO 4 DO                                             // 固定 4 槽遍历（上界常量无越界） / Fixed four-slot traversal
    IF (_iLoop <= nPumpCount) AND aPumpFault[_iLoop] THEN          // 组态内槽位且故障 / Faulted slot inside configuration
        _bAnyOut := TRUE;                                          // 退池事件 / Pool-exit event
    END_IF
    IF (_iLoop <= nPumpCount) AND (NOT aPumpFault[_iLoop]) THEN    // 组态内健康槽位计入池 / Healthy slot joins pool
        _nPoolCnt := _nPoolCnt + 1;                                // 池数递增 / Pool count increments
    END_IF
END_FOR

(* —— 段 4：故障锁存与解除（R45 配对；解除式全当拍量） —— *)
IF _bCfgBad THEN                                                   // 组态非法 / Illegal configuration
    _uFault := 16#0007_0301;                                       // 故障级总码 / Fault-level code
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_MprCause.eCfgIllegal;                          // 归因：组态非法 / Cause: illegal configuration
END_IF
IF bEnable AND (NOT _bFault) AND (_nPoolCnt = 0) THEN              // 全池故障 / Pool empty
    _uFault := 16#0007_0301;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_MprCause.eAllPumpFault;                        // 归因：全池故障 / Cause: pool empty
END_IF
IF _bAnyOut AND (NOT _bFault) THEN                                 // 泵退池告警（信息级，不锁存） / Pool-exit warning
    _uInfo := 16#0007_0401;                                        // 信息级：泵退出轮换池 / Info: pump left pool
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN                               // 解除沿（当拍量，无锁存因子） / Release edge
    _bFault := FALSE;                                              // 清故障锁存 / Clear fault latch
    _uFault := 16#0000_0000;                                       // 清故障码 / Clear fault code
    _eCause := E_DL_MprCause.eNone;                                // 清成因 / Clear cause
    IF _eState = E_DL_MprState.eFault THEN
        _eState := E_DL_MprState.eIdle;                            // 故障相唯一迁出路径 / Sole exit from fault phase
    END_IF
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_MprState.eIdle:
    IF (NOT _bFault) AND bEnable AND (_nPoolCnt > 0) THEN          // 出口 1：使能且池非空，选最小小时泵为领泵 / Enable with non-empty pool
        _fBest  := 1.0E30;                                         // 搜索初值（远大于可行小时数） / Search seed
        _bFound := FALSE;                                          // 命中标志清零 / Found flag cleared
        FOR _iLoop := 1 TO nPumpCount DO                           // 组态内槽位搜索 / Search inside configuration
            IF (NOT aPumpFault[_iLoop]) AND (_a_fHours[_iLoop] < _fBest) THEN   // 健康且小时更小 / Healthy and fewer hours
                _fBest  := _a_fHours[_iLoop];                      // 记录最小值 / Record minimum
                _nLead  := _iLoop;                                 // 记录候选领泵 / Record candidate lead
                _bFound := TRUE;                                   // 命中 / Found
            END_IF
        END_FOR
        IF _bFound THEN
            _eState := E_DL_MprState.eRun;                         // 进运行相 / Enter run phase
        END_IF
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_MprState.eFault;
    END_IF

E_DL_MprState.eRun:
    IF (NOT bEnable) THEN                                          // 出口 1：撤使能全停回待机 / Disable stops all
        _eState := E_DL_MprState.eIdle;
    ELSIF aPumpFault[_nLead] THEN                                  // 出口 2：领泵故障 → 立即停旧领泵进切换相（跳过运行窗，安全侧） / Lead fault, stop now
        _nCand := 0;                                               // 候选待重选 / Candidate to be reselected
        _eState := E_DL_MprState.eSwitch;
    ELSIF _bFault OR (_nPoolCnt = 0) THEN                          // 出口 3：锁存或池空 / Fault or pool empty
        _eState := E_DL_MprState.eFault;
    ELSE
        _a_fHours[_nLead] := _a_fHours[_nLead] + fDtSec / 3600.0;  // 领泵小时累计 [h] / Lead hours accumulate
        _fBest  := 1.0E30;                                         // 备用候选搜索初值 / Search seed
        _bFound := FALSE;                                          // 命中标志清零 / Found flag cleared
        FOR _iLoop := 1 TO nPumpCount DO                           // 搜索除领泵外最小小时候选 / Search candidate excluding lead
            IF (_iLoop <> _nLead) AND (NOT aPumpFault[_iLoop]) AND (_a_fHours[_iLoop] < _fBest) THEN
                _fBest  := _a_fHours[_iLoop];                      // 记录最小值 / Record minimum
                _nCand  := _iLoop;                                 // 记录候选 / Record candidate
                _bFound := TRUE;                                   // 命中 / Found
            END_IF
        END_FOR
        IF _bFound AND tonMinRun.Q AND ((_a_fHours[_nLead] - _a_fHours[_nCand]) > fBalThr) THEN  // 均衡切换判据（运行窗满 + 小时差超阈） / Balance criteria
            _eState := E_DL_MprState.eSwitch;                      // 进切换过渡相（旧领泵停） / Enter switch transition
        END_IF
    END_IF

E_DL_MprState.eSwitch:
    IF (NOT bEnable) THEN                                          // 出口 1：撤使能回待机 / Disable to idle
        _eState := E_DL_MprState.eIdle;
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_MprState.eFault;
    ELSE
        IF (_nCand < 1) OR (aPumpFault[_nCand]) THEN               // 候选未定或已故障 → 重选 / Candidate invalid, reselect
            _fBest  := 1.0E30;                                     // 搜索初值 / Search seed
            _bFound := FALSE;                                      // 命中标志清零 / Found flag cleared
            FOR _iLoop := 1 TO nPumpCount DO                       // 全池重选最小小时泵 / Reselection over the full pool
                IF (NOT aPumpFault[_iLoop]) AND (_a_fHours[_iLoop] < _fBest) THEN
                    _fBest  := _a_fHours[_iLoop];                  // 记录最小值 / Record minimum
                    _nCand  := _iLoop;                             // 记录候选 / Record candidate
                    _bFound := TRUE;                               // 命中 / Found
                END_IF
            END_FOR
            IF NOT _bFound THEN
                _nCand := 0;                                       // 池空，候选清零 / Pool empty, candidate cleared
            END_IF
        END_IF
        IF (_nCand >= 1) AND tonMinStop.Q THEN                     // 停机窗满且候选有效 → 启新领泵 / Stop window elapsed, start new lead
            _nLead  := _nCand;                                     // 领泵交接 / Lead handover
            _nCand  := 0;                                          // 候选清零 / Candidate cleared
            _eState := E_DL_MprState.eRun;                         // 回运行相 / Back to run phase
        END_IF
    END_IF

E_DL_MprState.eFault:
    ;                                                              // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0007_0301;                                       // 故障级：非法相位兜底 / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_MprCause.ePhaseBad;                            // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_MprState.eFault;                               // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放；故障相安全侧全停） —— *)
IF _eState = E_DL_MprState.eRun THEN                               // 仅运行相输出领泵指令 / Run phase drives lead only
    abPumpRun[_nLead] := TRUE;                                     // 领泵指令置位 / Lead command set
    nLeadPump := _nLead;                                           // 领泵号出口 / Lead outlet
END_IF
nPoolCnt := _nPoolCnt;                                             // 池数出口 / Pool size outlet
IF _bFault THEN
    nErrId := _uFault;                                             // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                              // 信息码 / Info code
END_IF
bError := _bFault;                                                 // 故障标志与锁存同源（名实双出口） / Flag from latch
eState := _eState;                                                 // 状态出口 / State outlet
eCause := _eCause;                                                 // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
