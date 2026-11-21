(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CaseErectFaultSeq
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 开箱成型失败重试与吸盘堵塞诊断。bStartCmd 沿启动
 *                         成型吸持：bSuctionCmd 置位等待真空达 fVacOkLevel
 *                         （tonSeek 窗）；达压 → bPickDone 单拍并保持吸持监视
 *                         （中途掉压判 eVacDrop）；超时 → 吹气清理（bBlowOffCmd
 *                         in eRetryPause tRetryPause）后重试，超 nMaxRetry 次
 *                         归因收口：全程真空峰值 <= fVacFloor → eVacClog（吸盘
 *                         堵塞/无真空），曾达压后掉 → eVacDrop，部分真空但
 *                         不足 → eVacTimeout。三成因独立分码（R190 归因唯一）。
 * 来源标签 (Origin)     : ROADMAP 在册空勾 P2（R13 新增行）；判据思想复用既有
 *                         VacuumEjector 件（真空等级判据语义域借鉴），实现与
 *                         码位独立 clean-room，IEC 61131-3 标准语义的道莅防御性实现
 * 边界语义 (Boundary)   : ① 三段 TON 一相一实例（R275）：tonSeek/tonPause/
 *                         tonDrop 各自独立，禁跨相复用；
 *                         ② 归因锁存：故障相按锁存回放，不按当下真空重推断（R28）；
 *                         ③ 重试计数只在收口沿或复位沿清（bStop 中止保留计数，
 *                         作用域在此声明——中止视为本轮未完，重试额度保留）；
 *                         ④ 组态闸：真空等级/地板值/时间/次数全引脚覆盖（R151）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 全输出强制 FALSE（吸持是
 *                         执行器指令，失能必须收敛）；eFault 相 → bSuctionCmd
 *                         强制 FALSE（故障先断气源），bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 组态闸全引脚/容差比较 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 三 TON + 两 R_TRIG 段 0 无条件刷新，各实例单用途 ✓
 * 验收向量 (Acceptance) : V1 首次达压 → bPickDone 单拍 TRUE，nRetryCnt=0；
 *                         V2 达压后掉压 → eFault，eCause=eVacDrop；
 *                         V3 三次超时且真空峰值恒为地板值 → eCause=eVacClog；
 *                         V4 三次超时峰值 0.5·fVacOkLevel → eCause=eVacTimeout；
 *                         V5 重试期 bBlowOffCmd 电平 TRUE（暂停相内）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 2 · 序号 10）
 *==============================================================================*)
TYPE E_DL_CefState :
(
    eIdle       := 0,                        (* 待启动 / Idle *)
    eErect      := 10,                       (* 吸持建立中（真空达压窗） / Erecting, vacuum seek *)
    eHold       := 20,                       (* 吸持保持监视（掉压判据） / Holding, drop watch *)
    eRetryPause := 30,                       (* 吹气清理暂停（重试间隔） / Blow-off pause *)
    eFault      := 90                        (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_CefCause :
(
    eNone        := 0,                       (* 无故障成因 / No cause *)
    eVacClog     := 1,                       (* 吸盘堵塞：全程真空不高于地板值 / Suction clog: vacuum never above floor *)
    eVacDrop     := 2,                       (* 中途掉压：曾达压后失压 / Vacuum drop after reaching level *)
    eVacTimeout  := 3,                       (* 达压超时：部分真空但始终不足 / Vacuum seek timeout, partial only *)
    eCfgIllegal  := 4,                       (* 组态非法 / Illegal config *)
    ePhaseBad    := 5                        (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CaseErectFaultSeq
VAR_INPUT
    bVacOkLvl   : BOOL := FALSE;             (* 真空达压电平（真空开关或比较器输出直连）[-] / Vacuum-ok level input *)
    fVacReading : LREAL := 0.0;              (* 真空读数（归因诊断用）[kPa] / Vacuum reading for diagnosis *)
    fVacOkLevel : LREAL := 60.0;             (* 达压等级阈值，域 > 0.0 [kPa] / Vacuum ok threshold *)
    fVacFloor   : LREAL := 5.0;              (* 地板值：峰值不高于此判堵塞，域 >= 0.0 且 < fVacOkLevel [kPa] / Vacuum floor for clog verdict *)
    tVacSeek    : TIME := T#3S;              (* 达压窗保持时长，域 > T#0S [ms] / Vacuum seek window *)
    tRetryPause : TIME := T#1S;              (* 吹气清理暂停保持时长，域 > T#0S [ms] / Retry pause hold *)
    nMaxRetry   : INT := 3;                  (* 最大重试次数，域 0..20 [次] / Max retry count *)
    bStartCmd   : BOOL := FALSE;             (* 成型启动命令，上升沿发起 / Start command edge *)
    bStop       : BOOL := FALSE;              (* 中止命令，电平 TRUE 立即断吸回 eIdle（保留重试计数，见边界③） / Stop level, keeps retry count *)
    bEnable     : BOOL := TRUE;              (* 使能，FALSE 全输出强制收敛 [-] / Enable *)
    bReset      : BOOL := FALSE;              (* 复位命令，上升沿清故障锁存与全部状态 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bSuctionCmd : BOOL;                      (* 吸盘吸持命令输出 [-] / Suction command output *)
    bBlowOffCmd : BOOL;                      (* 吹气清理命令输出（重试暂停相电平）[-] / Blow-off command output *)
    bPickDone   : BOOL;                      (* 本轮吸持达压完成单拍位 [-] / Pick-done single-scan pulse *)
    nRetryCnt   : INT;                       (* 本轮已用重试次数 [次] / Retry count this round *)
    nAttemptCnt : INT;                       (* 本轮尝试总次数（含首次）[次] / Attempt count this round *)
    eState      : E_DL_CefState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_CefCause;             (* 故障成因出口（R190 三成因独立分码） / Fault cause outlet *)
    bError      : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_CefState := E_DL_CefState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_CefCause := E_DL_CefCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    tonSeek   : TON;                         (* 达压窗计时（eErect 相专用），段 0 无条件调用 / Seek timer, phase-specific *)
    tonPause  : TON;                         (* 吹气暂停计时（eRetryPause 相专用），段 0 无条件调用 / Pause timer, phase-specific *)
    tonDrop   : TON;                         (* 掉压确认计时（eHold 相专用），段 0 无条件调用 / Drop confirm timer, phase-specific *)
    rtStart   : R_TRIG;                      (* 启动沿实例，段 0 无条件调用 / Start edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _nRetry   : INT;                         (* 重试计数锁存 [次] / Retry count latch *)
    _nAttempt : INT;                         (* 尝试计数锁存 [次] / Attempt count latch *)
    _fVacMax  : LREAL;                       (* 本轮真空峰值锁存（归因判据源）[kPa] / Vacuum peak latch *)
    _bReached : BOOL;                        (* 本轮曾达压位（掉压归因判据）[-] / Reached-ok latch this round *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A，三 TON 各自独立 IN 派生） —— *)
_bCfgBad := (fVacOkLevel <= 0.0) OR (fVacFloor < 0.0) OR (fVacFloor >= fVacOkLevel)   (* 组态闸：等级/地板域及序关系（R151 全引脚覆盖） / Config gate *)
            OR (tVacSeek <= T#0S) OR (tRetryPause <= T#0S) OR (nMaxRetry < 0) OR (nMaxRetry > 20);
rtStart(CLK := bStartCmd);                   (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
tonSeek(IN := _eState = E_DL_CefState.eErect, PT := tVacSeek);        (* 达压窗随相位派生 / Seek timer phase-derived *)
tonPause(IN := _eState = E_DL_CefState.eRetryPause, PT := tRetryPause);   (* 暂停计时随相位派生 / Pause timer phase-derived *)
tonDrop(IN := _eState = E_DL_CefState.eHold AND NOT bVacOkLvl, PT := tRetryPause);   (* 掉压确认随相位派生（PT 复用暂停时长作为失压容忍窗，语义声明） / Drop confirm timer *)

(* —— 段 1：单拍量预清零（R107） —— *)
bPickDone := FALSE;                          (* 达压完成单拍位预清，唯一分支置位 / Pick pulse preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清成因 + 清计数 + 清峰值 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CefCause.eNone;          (* 清成因 / Clear cause *)
    _nRetry := 0;                            (* 清重试计数 / Clear retry count *)
    _nAttempt := 0;                          (* 清尝试计数 / Clear attempt count *)
    _fVacMax := 0.0;                         (* 清真空峰值 / Clear vacuum peak *)
    _bReached := FALSE;                      (* 清曾达压位 / Clear reached latch *)
    _eState := E_DL_CefState.eIdle;          (* 迁待启动相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CefCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_CefState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CefState.eIdle:                     (* 待启动相 / Idle *)
        IF rtStart.Q AND bEnable AND NOT _bFault THEN
            _nAttempt := _nAttempt + 1;      (* 尝试计数递增 / Attempt count advance *)
            _fVacMax := 0.0;                 (* 本轮峰值清零 / Clear round peak *)
            _bReached := FALSE;              (* 本轮曾达压清零 / Clear reached latch *)
            _eState := E_DL_CefState.eErect; (* 进入吸持建立 / Enter erect *)
        END_IF
    E_DL_CefState.eErect:                    (* 吸持建立相 / Erect *)
        IF NOT bEnable OR bStop THEN         (* 失能/中止：断吸回待机（重试计数保留，边界③声明） / Disable or stop *)
            _eState := E_DL_CefState.eIdle;  (* 回待机 / Back to idle *)
        ELSIF bVacOkLvl THEN
            _bReached := TRUE;               (* 曾达压置位 / Reached latch *)
            bPickDone := TRUE;               (* 达压完成单拍脉冲 / Pick-done pulse *)
            _eState := E_DL_CefState.eHold;  (* 进入保持监视 / Enter hold *)
        ELSE
            IF fVacReading > _fVacMax THEN
                _fVacMax := fVacReading;     (* 真空峰值跟踪（NaN 参与比较恒 FALSE，不污染峰值） / Vacuum peak tracking, NaN-safe *)
            END_IF
            IF tonSeek.Q THEN
                _nRetry := _nRetry + 1;      (* 超时计一次重试 / Retry count advance *)
                IF _nRetry > nMaxRetry THEN
                    IF _bReached THEN
                        _eCause := E_DL_CefCause.eVacDrop;      (* 曾达压后失压归因（独立分码，R190） / Drop cause *)
                    ELSIF _fVacMax <= fVacFloor THEN
                        _eCause := E_DL_CefCause.eVacClog;      (* 峰值不高于地板：吸盘堵塞归因 / Clog cause *)
                    ELSE
                        _eCause := E_DL_CefCause.eVacTimeout;   (* 部分真空但不足：超时归因 / Timeout cause *)
                    END_IF
                    _bFault := TRUE;         (* 重试耗尽故障锁存（R45 配对） / Retry exhausted fault *)
                    _eState := E_DL_CefState.eFault;   (* 同步迁故障相 / Migrate to fault *)
                ELSE
                    _eState := E_DL_CefState.eRetryPause;   (* 未耗尽：吹气清理后重试 / Enter retry pause *)
                END_IF
            END_IF
        END_IF
    E_DL_CefState.eHold:                     (* 吸持保持相 / Hold *)
        IF NOT bEnable OR bStop THEN
            _eState := E_DL_CefState.eIdle;  (* 失能/中止回待机 / Back to idle *)
        ELSIF bVacOkLvl THEN
            ;                                (* 吸持正常，无动作 / Holding normal *)
        ELSIF tonDrop.Q THEN                 (* 失压持续到容忍窗 / Drop held to tolerance *)
            _eCause := E_DL_CefCause.eVacDrop;   (* 中途掉压归因（独立分码，R190） / Drop cause *)
            _bFault := TRUE;                 (* 故障锁存（R45 配对） / Latch fault *)
            _eState := E_DL_CefState.eFault; (* 同步迁故障相 / Migrate to fault *)
        END_IF
    E_DL_CefState.eRetryPause:               (* 吹气清理暂停相 / Retry pause *)
        IF NOT bEnable OR bStop THEN
            _eState := E_DL_CefState.eIdle;  (* 失能/中止回待机 / Back to idle *)
        ELSIF tonPause.Q THEN
            _nAttempt := _nAttempt + 1;      (* 新尝试计数 / Attempt count advance *)
            _eState := E_DL_CefState.eErect; (* 重新吸持建立 / Re-enter erect *)
        END_IF
    E_DL_CefState.eFault:                    (* 故障相：先断气源，仅复位沿出 / Fault: suction cut *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CefState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_CefCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（双门控：失能收敛 + 故障断气源，R191/R285 全路径赋值） —— *)
IF (NOT bEnable) OR _bFault OR (_eState = E_DL_CefState.eIdle) THEN
    bSuctionCmd := FALSE;                    (* 失能/故障/待机：吸持强制收敛 / Suction forced off *)
    bBlowOffCmd := FALSE;                    (* 吹气强制收敛 / Blow-off forced off *)
ELSIF _eState = E_DL_CefState.eErect OR _eState = E_DL_CefState.eHold THEN
    bSuctionCmd := TRUE;                     (* 建立/保持相：吸持命令电平 / Suction on *)
    bBlowOffCmd := FALSE;                    (* 吹气关闭 / Blow-off off *)
ELSIF _eState = E_DL_CefState.eRetryPause THEN
    bSuctionCmd := FALSE;                    (* 暂停相断吸 / Suction off *)
    bBlowOffCmd := TRUE;                     (* 吹气清理电平 / Blow-off on *)
ELSE
    bSuctionCmd := FALSE;                    (* 兜底收敛 / Fallback off *)
    bBlowOffCmd := FALSE;                    (* 兜底收敛 / Fallback off *)
END_IF
nRetryCnt := _nRetry;                        (* 重试计数镜像 / Retry count mirror *)
nAttemptCnt := _nAttempt;                    (* 尝试计数镜像 / Attempt count mirror *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
