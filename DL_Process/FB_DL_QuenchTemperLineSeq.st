(*==============================================================================
  Component : FB_DL_QuenchTemperLineSeq
  Category  : DL_Process
  Type      : FB
  Complexity: C4
  VERSION   : v1.0.0
  功能      : 淬火-回火联动线全流程顺控（上料/加热/保温/淬火/沥液/回火/冷却/下料）
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 本件只编排相与时序闸，不驱动阀门接触器；执行器由 IO 映射层按相指示位驱动。
              ② E1 仅加热相与沥液相可重试（定时器自复位后重新计时），预算 nRetryMax 耗尽升 E2。
              ③ E3 判据（急停断开 / 安全门未闭 / 液位低于下限 / 介质超温）同拍置 bSafeCut；
                 锁存解除唯一路径 = bReset 沿且安全条件已恢复（R152），bStop 不清 E3。
              ④ 配比约束（R100）：atPhaseTmo[1] 加热窗须宽于实测升温时间；atPhaseTmo[6] 回火总窗
                 须 ≥ 升温 + 保温整定之和，否则回火带内判据永不到时。
              ⑤ 复位作用域（R311）：bReset 沿清 E2/E3 锁存 + 节拍累加 + 重试计数；bStop 只清 E2 与相位。
              ⑥ 默认引脚组合自证（R114）：握手类（bPartLoaded / bUnloadPermit / bDrained /
                 bQuenchImmersion）默认 FALSE，默认组合无法越过任一握手直达完成相；使能类（bDoorClosed /
                 bEStopHealthy）默认 TRUE 与 bEnable 同族，断线由硬件安全回路保证，不靠软件默认值兜底。
  状态机    : eIdle 待机 / eLoad 上料 / eHeat 加热 / eSoak 保温 / eQuench 淬火 / eDrain 沥液 /
              eTemper 回火 / eCool 冷却 / eUnload 下料 / eFault 故障停(E2) / eSafeStop 安全断能(E3)
  自检      : R1 零 GVL ｜ R2 零物理地址 ｜ R3 纯 IEC 61131-3 ｜ R4 非有限自反判 + 除零先判 ｜
              R6 CASE 含 ELSE ｜ R7 八 TON 两沿段 0 无条件刷新 ｜ R10 仅标准转换函数 ｜ R14 无属性件
==============================================================================*)
TYPE E_DL_QtlPhase :
(
    eIdle     := 0,     (* 待机：等启动沿 / Idle, waiting for start edge *)
    eLoad     := 10,    (* 上料相：等上料到位 / Loading, wait load-in-position *)
    eHeat     := 20,    (* 加热相：升到保温带（E1 可重试）/ Heating, retryable *)
    eSoak     := 30,    (* 保温相：保温到时 / Soaking *)
    eQuench   := 40,    (* 淬火相：浸没且到时 / Quenching, immersed and timed *)
    eDrain    := 50,    (* 沥液相：等回液到位（E1 可重试）/ Draining, retryable *)
    eTemper   := 60,    (* 回火相：带内且总窗到时 / Tempering, in band and window *)
    eCool     := 70,    (* 冷却相：空冷到出料温度 / Cooling to unload temperature *)
    eUnload   := 80,    (* 下料相：等下料允许 / Unloading, wait permit *)
    eFault    := 90,    (* 故障停待复位（E2）/ Fault stop awaiting reset, E2 *)
    eSafeStop := 95     (* 安全侧断能（E3）/ Safety energy cut, E3 *)
);
END_TYPE
TYPE E_DL_QtlCause :
(
    eNone      := 0,    (* 无异常 / No anomaly *)
    eLoadTmo   := 1,    (* 上料超时 / Load timeout *)
    eHeatTmo   := 2,    (* 加热超时（E1 记录后重试）/ Heat timeout, retried *)
    eSoakTmo   := 3,    (* 保温超时 / Soak timeout *)
    eQuenchTmo := 4,    (* 淬火到时未浸没 / Quench timed out without immersion *)
    eDrainTmo  := 5,    (* 沥液超时（E1 记录后重试）/ Drain timeout, retried *)
    eTemperTmo := 6,    (* 回火超时（带内未达）/ Tempering timeout *)
    eCoolTmo   := 7,    (* 冷却超时 / Cooling timeout *)
    eUnloadTmo := 8,    (* 下料超时 / Unload timeout *)
    eRetryOver := 9,    (* 重试预算耗尽（E1 升 E2）/ Retry budget exhausted *)
    eSigBad    := 10,   (* 工件温度信号非有限（E2）/ Part temperature non-finite *)
    eEstopOpen := 11,   (* 急停回路断开（E3）/ E-stop circuit open *)
    eDoorOpen  := 12,   (* 安全门未闭合（E3）/ Guard door open *)
    eLevelLow  := 13,   (* 淬火槽液位低于下限（E3）/ Bath level low *)
    eMediumHi  := 14,   (* 淬火介质超温（E3）/ Medium over-temperature *)
    eCfgBad    := 15,   (* 组态非法（E2）/ Illegal configuration *)
    ePhaseBad  := 16    (* 非法相位兜底（E2）/ Illegal phase fallback *)
);
END_TYPE
TYPE E_DL_QtlGrade :
(
    eG0 := 0,           (* 无异常 / No anomaly *)
    eG1 := 1,           (* E1 可恢复重试：记录后重试，不置 bError / E1 retried, recorded only *)
    eG2 := 2,           (* E2 停机待复位 / E2 stop, awaiting reset *)
    eG3 := 3            (* E3 安全侧立即断能 / E3 immediate safety energy cut *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_QuenchTemperLineSeq
VAR_INPUT
    bStart        : BOOL := FALSE;      (* 启动沿（eIdle 入 eLoad） [-] / Start rising edge *)
    bStop         : BOOL := FALSE;      (* 中止：回 eIdle 并清 E2 锁存（不清 E3） [-] / Abort, clears E2 only *)
    bReset        : BOOL := FALSE;      (* 复位沿：清全部锁存 + 节拍 + 重试（R311） [-] / Reset edge *)
    bPartLoaded   : BOOL := FALSE;      (* 上料到位（默认 FALSE 禁跳步） [-] / Load in position *)
    bUnloadPermit : BOOL := FALSE;      (* 下料允许（默认 FALSE 禁跳步） [-] / Unload permit *)
    bQuenchOil    : BOOL := TRUE;       (* 介质：TRUE 油淬 / FALSE 水淬 [-] / Oil when TRUE *)
    bQuenchImmersion : BOOL := FALSE;   (* 淬火浸没到位（默认 FALSE 禁跳步） [-] / Quench immersion OK *)
    bDrained      : BOOL := FALSE;      (* 沥液回液到位（默认 FALSE 禁跳步） [-] / Drain back complete *)
    bDoorClosed   : BOOL := TRUE;       (* 安全门闭合（使能类引脚，默认 TRUE） [-] / Guard door closed *)
    bEStopHealthy : BOOL := TRUE;       (* 急停回路正常（使能类引脚，默认 TRUE） [-] / E-stop healthy *)
    fMediumTempC  : LREAL := 0.0;       (* 淬火介质温度实测 [℃] / Medium temperature [degC] *)
    fLevelPct     : LREAL := 0.0;       (* 淬火槽液位实测 [%] / Bath level [%] *)
    fPartTempC    : LREAL := 0.0;       (* 工件温度实测（升温与冷却判据） [℃] / Part temperature [degC] *)
    fSoakSetC     : LREAL := 850.0;     (* 保温设定温度，域 > 0 [℃] / Soak setpoint [degC] *)
    fTemperSetC   : LREAL := 550.0;     (* 回火设定温度，域 > 0 [℃] / Temper setpoint [degC] *)
    fSoakTolC     : LREAL := 15.0;      (* 保温与回火带共用半宽，域 > 0 [℃] / Band half-width [degC] *)
    fMediumMaxC   : LREAL := 60.0;      (* 介质温度上限，域 > 0（E3 判据） [℃] / Medium limit [degC] *)
    fLevelMinPct  : LREAL := 70.0;      (* 液位安全下限，域 0..100（E3 判据） [%] / Level floor [%] *)
    fCoolSetC     : LREAL := 80.0;      (* 冷却出料温度上限，域 > 0 [℃] / Cool-down unload limit [degC] *)
    atPhaseTmo    : ARRAY[0..8] OF TIME := [T#3M, T#45M, T#90M, T#15M, T#8M, T#3M, T#120M, T#30M, T#3M];   (* 超时窗 [ms]，下标 0..8 = 上料/加热/保温/油淬/水淬/沥液/回火/冷却/下料 / Phase windows [ms] *)
    nRetryMax     : UINT := 2;          (* 单相 E1 重试预算，域 1..9（0 入组态闸） [次] / Retry budget *)
    fCycleSec     : LREAL := 0.0;       (* 扫描周期（<=0 用缺省 0.01s） [s] / Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    eState        : E_DL_QtlPhase;      (* 当前相（HMI 诊断） [-] / Present phase *)
    eCause        : E_DL_QtlCause;      (* 成因（锁存回放，R189） [-] / Latched cause playback *)
    eGrade        : E_DL_QtlGrade;      (* 异常分级出口 [-] / Exception grade outlet *)
    bError        : BOOL;               (* 故障标志（E2/E3 为 TRUE，E1 不置） [-] / Error flag *)
    bSafeCut      : BOOL;               (* 安全侧断能指令（E3 常 TRUE 至复位） [-] / Safety energy cut *)
    bHeatActive   : BOOL;               (* 加热相指示（供 IO 层驱动加热阀） [-] / Heating indicator *)
    bQuenchActive : BOOL;               (* 淬火相指示（供 IO 层驱动淬火机构） [-] / Quench indicator *)
    bDone         : BOOL;               (* 单拍完成脉冲 [-] / One-scan done pulse *)
    nPieceCount   : UDINT;              (* 累计产量（饱和于 UDINT 上限） [件] / Piece count, saturating *)
    tCycleLast    : TIME;               (* 最近一件节拍 [ms] / Last piece cycle [ms] *)
    fCycleAvgS    : LREAL;              (* 平均节拍（无件输出 0） [s] / Average cycle [s] *)
    nRetryUsed    : UINT;               (* 当前相已用重试次数 [次] / Retries used in phase *)
END_VAR
VAR
    _ePhase      : E_DL_QtlPhase := E_DL_QtlPhase.eIdle;    (* 内部相（CASE 唯一写入目标） [-] / Internal phase *)
    _ePhasePrev  : E_DL_QtlPhase := E_DL_QtlPhase.eIdle;    (* 上拍相快照（相迁移后置用） [-] / Previous phase *)
    _eCause      : E_DL_QtlCause := E_DL_QtlCause.eNone;    (* 成因锁存量 [-] / Latched cause *)
    _eGrade      : E_DL_QtlGrade := E_DL_QtlGrade.eG0;      (* 分级锁存量 [-] / Latched grade *)
    _bFault      : BOOL := FALSE;       (* E2 锁存位（解除 = bReset 沿或 bStop） [-] / E2 latch *)
    _bSafeLatch  : BOOL := FALSE;       (* E3 锁存位（解除 = bReset 沿且安全恢复） [-] / E3 latch *)
    _bFaultReq   : BOOL := FALSE;       (* 单拍故障请求（段 1 预清，段 6 落地） [-] / One-scan fault request *)
    _bDonePulse  : BOOL := FALSE;       (* 单拍完成标志（段 1 预清） [-] / One-scan done flag *)
    _bMediumBad  : BOOL := FALSE;       (* 介质温度非有限或超上限 [-] / Medium bad *)
    _bLevelBad   : BOOL := FALSE;       (* 液位非有限或低于下限 [-] / Level bad *)
    _bPartBad    : BOOL := FALSE;       (* 工件温度非有限 [-] / Part temperature non-finite *)
    _bSoakBand   : BOOL := FALSE;       (* 保温带内判据 [-] / In soak band *)
    _bTemperBand : BOOL := FALSE;       (* 回火带内判据 [-] / In temper band *)
    _bCfgBad     : BOOL := FALSE;       (* 组态非法当拍量 [-] / Configuration bad *)
    _nRetry      : UINT := 0;           (* 当前相重试计数（相迁移后置清） [次] / Retry counter *)
    _nPiece      : UDINT := 0;          (* 产量累计锁存（饱和） [件] / Piece count latch *)
    _nIdx        : INT := 0;            (* 相窗遍历索引（循环变量） [-] / Loop index *)
    _fCycleAccS  : LREAL := 0.0;        (* 本件节拍累加 [s] / Cycle accumulator *)
    _fCycleSumS  : LREAL := 0.0;        (* 节拍总和（均值分子） [s] / Cycle sum *)
    _fCy         : LREAL := 0.0;        (* 当拍有效周期 [s] / Effective cycle *)
    _tCycleLast  : TIME := T#0S;        (* 最近节拍锁存 [ms] / Last cycle latch *)
    _tQuenchTmo  : TIME := T#15M;       (* 当拍淬火窗（按介质选择） [ms] / Active quench window [ms] *)
    tonLoad      : TON;                 (* 上料超时（段 0 无条件调用） / Load timeout *)
    tonHeat      : TON;                 (* 加热超时（自复位，E1 可重试） / Heat timeout, self-reset *)
    tonSoak      : TON;                 (* 保温超时 / Soak timeout *)
    tonQuench    : TON;                 (* 淬火超时（按介质选窗） / Quench timeout *)
    tonDrain     : TON;                 (* 沥液超时（自复位，E1 可重试） / Drain timeout, self-reset *)
    tonTemper    : TON;                 (* 回火总窗（升温 + 保温） / Temper total window *)
    tonCool      : TON;                 (* 冷却超时 / Cool timeout *)
    tonUnload    : TON;                 (* 下料超时 / Unload timeout *)
    rtStart      : R_TRIG;              (* 启动沿（段 0 无条件调用） / Start edge *)
    rtReset      : R_TRIG;              (* 复位沿（段 0 无条件调用） / Reset edge *)
END_VAR
VAR CONSTANT
    DL_QTL_CYDEF    : LREAL := 0.01;        (* 缺省扫描周期 [s] / Default scan cycle [s] *)
    DL_QTL_PCMAX    : UDINT := 4294967295;  (* 产量计数饱和上限 [件] / Piece count ceiling *)
    DL_QTL_RETRYTOP : UINT := 9;            (* 重试预算可配域顶 [次] / Retry configurable ceiling *)
    DL_QTL_PCTOP    : LREAL := 100.0;       (* 液位百分比满量程 [%] / Level full scale [%] *)
END_VAR

(*-----------------------------------------------------------------------------
  方法 ResetFault：清 E2/E3 锁存（唯一解除入口，R152 可达性自证）
  契约：入参 bSafetyOk 表示安全条件已恢复；返回 TRUE = 本次确实清除了锁存。
  E2 恒可清；E3 仅当 bSafetyOk 为 TRUE 才可清（否则锁存保持，解除路径显式可达）。
  作用域：清 _bFault / _bSafeLatch / _eCause / _eGrade / _nRetry，并把相位迁回 eIdle。
-----------------------------------------------------------------------------*)
METHOD PUBLIC ResetFault : BOOL
VAR_INPUT
    bSafetyOk : BOOL := FALSE;      (* 安全条件已恢复（E3 解除前置） [-] / Safety conditions recovered *)
END_VAR
VAR
    _bCleared : BOOL := FALSE;      (* 本次是否清除过锁存 [-] / Cleared this call *)
END_VAR

ResetFault := FALSE;                (* 返回预置安全值 / Preset safe return *)
_bCleared := FALSE;
IF _bSafeLatch THEN
    IF bSafetyOk THEN
        _bSafeLatch := FALSE;       (* E3 解除：安全侧恢复后允许 / E3 released after safety recovery *)
        _bCleared := TRUE;
    END_IF
ELSIF _bFault THEN
    _bFault := FALSE;               (* E2 解除：无条件可清 / E2 released unconditionally *)
    _bCleared := TRUE;
END_IF
IF _bCleared THEN
    _eCause := E_DL_QtlCause.eNone;     (* 清成因 / Clear cause *)
    _eGrade := E_DL_QtlGrade.eG0;       (* 清分级 / Clear grade *)
    _nRetry := 0;                       (* 清重试预算占用 / Clear retry usage *)
    _ePhase := E_DL_QtlPhase.eIdle;     (* 迁回待机 / Back to idle *)
END_IF
ResetFault := _bCleared;            (* 真值返回 / Final return *)
END_METHOD

(*-----------------------------------------------------------------------------
  方法 CalcCycleTime：本件节拍换算（毫秒取整 + 双向域闸，无跨周期驻留）
  口径：NaN 自反检出 -> 返回哨兵零点 T#0S（还原方向不饱和，R81）；
        Inf 用差值自减检出 -> 亦返回哨兵零点；负值拒收；
        超 TIME 可表上限先钳后转（R153 取整前实数上限兜底）。
-----------------------------------------------------------------------------*)
METHOD PUBLIC CalcCycleTime : TIME
VAR
    fMs   : LREAL := 0.0;           (* 节拍毫秒暂存 [ms] / Milliseconds scratch *)
    fMsCl : LREAL := 0.0;           (* 钳位后毫秒 [ms] / Clamped milliseconds *)
    diMs  : DINT := 0;              (* 整型毫秒（钳位后转换，防溢出翻转） [ms] / Integer milliseconds *)
END_VAR

CalcCycleTime := T#0S;              (* 哨兵零点 / Sentinel zero *)
fMs := _fCycleAccS * 1000.0;        (* 秒 -> 毫秒 [ms] / Second to millisecond *)
IF (fMs <> fMs) OR ((fMs - fMs) <> (fMs - fMs)) OR (fMs < 0.0) THEN
    CalcCycleTime := T#0S;          (* 域闸：NaN 自反 / Inf 差值自减 / 负值，均拒收 / Domain gate *)
    RETURN;
END_IF
IF fMs > 2147483647.0 THEN
    fMsCl := 2147483647.0;          (* 先钳到 TIME 可表毫秒上限 / Clamp to TIME ceiling *)
ELSE
    fMsCl := fMs;
END_IF
diMs := LREAL_TO_DINT(fMsCl);       (* 钳位后整型转换（R10 标准函数） / Clamped integer conversion *)
CalcCycleTime := DINT_TO_TIME(diMs);(* 标准转换链 / Standard conversion chain *)
END_METHOD

(* —— 段 0：三模拟量非有限判定 + 组态闸 + 淬火窗选择 + 周期派生 + 八 TON 两沿无条件刷新（R7） —— *)
_bMediumBad := (fMediumTempC <> fMediumTempC)
            OR ((fMediumTempC - fMediumTempC) <> (fMediumTempC - fMediumTempC))
            OR (fMediumTempC > fMediumMaxC);      (* NaN 自反 + Inf 差值 + 超上限 / NaN, Inf, over-limit *)
_bLevelBad := (fLevelPct <> fLevelPct)
           OR ((fLevelPct - fLevelPct) <> (fLevelPct - fLevelPct))
           OR (fLevelPct < fLevelMinPct);         (* NaN 自反 + Inf 差值 + 低于下限 / NaN, Inf, low level *)
_bPartBad := (fPartTempC <> fPartTempC)
          OR ((fPartTempC - fPartTempC) <> (fPartTempC - fPartTempC));   (* 工件温度非有限 / Part temp non-finite *)
_bCfgBad := (nRetryMax = 0) OR (nRetryMax > DL_QTL_RETRYTOP)
         OR (fSoakSetC <= 0.0) OR (fTemperSetC <= 0.0) OR (fSoakTolC <= 0.0)
         OR (fMediumMaxC <= 0.0) OR (fCoolSetC <= 0.0)
         OR (fLevelMinPct < 0.0) OR (fLevelMinPct > DL_QTL_PCTOP);   (* 静态组态域闸全枚举 / Static config gate *)
FOR _nIdx := 0 TO 8 DO
    IF atPhaseTmo[_nIdx] <= T#0S THEN
        _bCfgBad := TRUE;                          (* 任一相窗非正 -> 组态非法 / Non-positive phase window *)
    END_IF
END_FOR
IF bQuenchOil THEN
    _tQuenchTmo := atPhaseTmo[3];                  (* 油淬窗 / Oil quench window *)
ELSE
    _tQuenchTmo := atPhaseTmo[4];                  (* 水淬窗 / Water quench window *)
END_IF
IF fCycleSec > 0.0 THEN
    _fCy := fCycleSec;                             (* 组态周期有效 / Configured cycle valid *)
ELSE
    _fCy := DL_QTL_CYDEF;                          (* 周期缺省兜底 / Default cycle *)
END_IF
_bSoakBand := (NOT _bPartBad) AND (ABS(fPartTempC - fSoakSetC) <= fSoakTolC);     (* 保温带内（容差比较） / In soak band *)
_bTemperBand := (NOT _bPartBad) AND (ABS(fPartTempC - fTemperSetC) <= fSoakTolC); (* 回火带内（共用半宽） / In temper band *)
rtStart(CLK := bStart);                            (* 启动沿，每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                            (* 复位沿，每拍必调 / Reset edge every scan *)
tonLoad(IN := (_ePhase = E_DL_QtlPhase.eLoad), PT := atPhaseTmo[0]);              (* 上料超时 / Load window *)
tonHeat(IN := (_ePhase = E_DL_QtlPhase.eHeat) AND (NOT tonHeat.Q), PT := atPhaseTmo[1]);   (* 加热自复位窗（R188） / Heat self-reset *)
tonSoak(IN := (_ePhase = E_DL_QtlPhase.eSoak), PT := atPhaseTmo[2]);              (* 保温超时 / Soak window *)
tonQuench(IN := (_ePhase = E_DL_QtlPhase.eQuench), PT := _tQuenchTmo);            (* 淬火超时 / Quench window *)
tonDrain(IN := (_ePhase = E_DL_QtlPhase.eDrain) AND (NOT tonDrain.Q), PT := atPhaseTmo[5]); (* 沥液自复位窗 / Drain self-reset *)
tonTemper(IN := (_ePhase = E_DL_QtlPhase.eTemper), PT := atPhaseTmo[6]);          (* 回火总窗 / Temper window *)
tonCool(IN := (_ePhase = E_DL_QtlPhase.eCool), PT := atPhaseTmo[7]);              (* 冷却超时 / Cool window *)
tonUnload(IN := (_ePhase = E_DL_QtlPhase.eUnload), PT := atPhaseTmo[8]);          (* 下料超时 / Unload window *)

(* —— 段 1：单拍量预清零（不含锁存/累加/快照量，R107）+ 相迁移后置 —— *)
_bFaultReq := FALSE;                               (* 单拍故障请求预清 / Fault request preset *)
_bDonePulse := FALSE;                              (* 单拍完成标志预清 / Done pulse preset *)
bError := FALSE;                                   (* 故障标志预清（出口 OR 汇总） / Error preset *)
IF _ePhase <> _ePhasePrev THEN
    _nRetry := 0;                                  (* 相迁移：重试预算复位 / Phase change: retry reset *)
    IF _eGrade = E_DL_QtlGrade.eG1 THEN
        _eGrade := E_DL_QtlGrade.eG0;              (* E1 记录随相推进清零（信息级可重算） / E1 cleared on advance *)
        _eCause := E_DL_QtlCause.eNone;
    END_IF
END_IF

(* —— 段 2：E3 安全侧拦截（最高优先级，同拍断能 + 归因唯一 + 迁相） —— *)
IF (NOT bEStopHealthy) OR (NOT bDoorClosed) OR _bLevelBad OR _bMediumBad THEN
    IF NOT _bSafeLatch THEN
        _bSafeLatch := TRUE;                       (* 锁存 / Latch *)
        _eGrade := E_DL_QtlGrade.eG3;              (* 分级 E3 / Grade E3 *)
        bError := TRUE;                            (* 分级标志同段置位（R45 配对） / Error pairing *)
        IF NOT bEStopHealthy THEN
            _eCause := E_DL_QtlCause.eEstopOpen;   (* 归因：急停断开 / Cause: E-stop *)
        ELSIF NOT bDoorClosed THEN
            _eCause := E_DL_QtlCause.eDoorOpen;    (* 归因：安全门未闭 / Cause: door *)
        ELSIF _bLevelBad THEN
            _eCause := E_DL_QtlCause.eLevelLow;    (* 归因：液位低 / Cause: level *)
        ELSE
            _eCause := E_DL_QtlCause.eMediumHi;    (* 归因：介质超温 / Cause: medium *)
        END_IF
    END_IF
    _ePhase := E_DL_QtlPhase.eSafeStop;            (* 同步迁安全相 / Migrate to safety stop *)
END_IF

(* —— 段 3：组态闸入 E2（E3 优先，安全相内不重复置因） —— *)
IF _bCfgBad AND (NOT _bSafeLatch) AND (NOT _bFault) THEN
    _bFault := TRUE;                               (* E2 锁存 / Latch E2 *)
    _eGrade := E_DL_QtlGrade.eG2;                  (* 分级 E2 / Grade E2 *)
    _eCause := E_DL_QtlCause.eCfgBad;              (* 归因：组态非法 / Cause: config *)
    _ePhase := E_DL_QtlPhase.eFault;               (* 同步迁相（R252） / Migrate *)
END_IF

(* —— 段 4：迁出链（复位沿 > 中止；作用域逐项声明 R311） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                              (* 作用域①：清 E2 锁存 / Clear E2 *)
    IF NOT ((NOT bEStopHealthy) OR (NOT bDoorClosed) OR _bLevelBad OR _bMediumBad) THEN
        _bSafeLatch := FALSE;                      (* 作用域②：安全恢复才清 E3 / Clear E3 only if safe *)
    END_IF
    _eCause := E_DL_QtlCause.eNone;                (* 作用域③：清成因与分级 / Clear cause and grade *)
    _eGrade := E_DL_QtlGrade.eG0;
    _nRetry := 0;                                  (* 作用域④：清重试 / Clear retry *)
    _fCycleAccS := 0.0;                            (* 作用域⑤：清本件节拍累加 / Clear cycle accumulator *)
    IF NOT _bSafeLatch THEN
        IF (_ePhase = E_DL_QtlPhase.eFault) OR (_ePhase = E_DL_QtlPhase.eSafeStop) THEN
            _ePhase := E_DL_QtlPhase.eIdle;        (* 作用域⑥：故障相迁回待机 / Back to idle *)
        END_IF
    END_IF
ELSIF bStop AND (_ePhase <> E_DL_QtlPhase.eIdle) AND (_ePhase <> E_DL_QtlPhase.eSafeStop) THEN
    IF _ePhase = E_DL_QtlPhase.eFault THEN
        _bFault := FALSE;                          (* 中止清 E2（E3 只能由复位清） / Abort clears E2 only *)
        _eCause := E_DL_QtlCause.eNone;
        _eGrade := E_DL_QtlGrade.eG0;
    END_IF
    _nRetry := 0;                                  (* 重试复位 / Retry reset *)
    _fCycleAccS := 0.0;                            (* 节拍累加作废 / Cycle accumulator void *)
    _ePhase := E_DL_QtlPhase.eIdle;                (* 回待机 / Back to idle *)
END_IF

(* —— 段 5：本件节拍累加（仅工作相计时，故障与安全相不累） —— *)
IF (_ePhase <> E_DL_QtlPhase.eIdle) AND (_ePhase <> E_DL_QtlPhase.eFault) AND (_ePhase <> E_DL_QtlPhase.eSafeStop) THEN
    _fCycleAccS := _fCycleAccS + _fCy;
END_IF

(* —— 段 6：故障请求统一落地（分支内只写成因与请求，落地仅此一处，R187/R252） —— *)
IF _bFaultReq AND (NOT _bSafeLatch) THEN
    _bFault := TRUE;                               (* E2 锁存 / Latch E2 *)
    _eGrade := E_DL_QtlGrade.eG2;                  (* 分级 E2 / Grade E2 *)
    _ePhase := E_DL_QtlPhase.eFault;               (* 同步迁相（R252） / Migrate *)
    bError := TRUE;                                (* 故障标志同段置位（R45 配对） / Error pairing *)
END_IF

(* —— 段 7：主状态机（ENUM + CASE，ELSE 兜底回安全相） —— *)
CASE _ePhase OF
E_DL_QtlPhase.eIdle:
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bSafeLatch) THEN
        _fCycleAccS := 0.0;                        (* 新件起算 / New piece *)
        _ePhase := E_DL_QtlPhase.eLoad;            (* 入上料相 / To loading *)
    END_IF
E_DL_QtlPhase.eLoad:
    IF bPartLoaded THEN
        _ePhase := E_DL_QtlPhase.eHeat;            (* 上料到位 -> 加热 / Loaded, heat *)
    ELSIF tonLoad.Q THEN
        _eCause := E_DL_QtlCause.eLoadTmo;         (* 归因：上料超时 / Cause: load timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eHeat:
    IF _bPartBad THEN
        _eCause := E_DL_QtlCause.eSigBad;          (* 归因：温度信号非有限 / Cause: signal *)
        _bFaultReq := TRUE;
    ELSIF _bSoakBand THEN
        _ePhase := E_DL_QtlPhase.eSoak;            (* 到保温带 -> 保温 / In band, soak *)
    ELSIF tonHeat.Q THEN
        IF _nRetry < nRetryMax THEN
            _nRetry := _nRetry + 1;                (* E1：可重试，计时器自复位后重计时 / E1 retry *)
            _eGrade := E_DL_QtlGrade.eG1;
            _eCause := E_DL_QtlCause.eHeatTmo;
        ELSE
            _eCause := E_DL_QtlCause.eRetryOver;   (* 归因：重试耗尽 / Cause: retry exhausted *)
            _bFaultReq := TRUE;
        END_IF
    END_IF
E_DL_QtlPhase.eSoak:
    IF tonSoak.Q AND _bSoakBand THEN
        _ePhase := E_DL_QtlPhase.eQuench;          (* 到时且带内 -> 淬火 / Timed and in band, quench *)
    ELSIF tonSoak.Q THEN
        _eCause := E_DL_QtlCause.eSoakTmo;         (* 归因：到时仍带外 / Cause: out of band at timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eQuench:
    IF tonQuench.Q AND bQuenchImmersion THEN
        _ePhase := E_DL_QtlPhase.eDrain;           (* 浸没到位且到时 -> 沥液 / Immersed and timed *)
    ELSIF tonQuench.Q THEN
        _eCause := E_DL_QtlCause.eQuenchTmo;       (* 归因：到时未浸没 / Cause: not immersed *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eDrain:
    IF bDrained THEN
        _ePhase := E_DL_QtlPhase.eTemper;          (* 回液到位 -> 回火 / Drained, temper *)
    ELSIF tonDrain.Q THEN
        IF _nRetry < nRetryMax THEN
            _nRetry := _nRetry + 1;                (* E1：可重试 / E1 retry *)
            _eGrade := E_DL_QtlGrade.eG1;
            _eCause := E_DL_QtlCause.eDrainTmo;
        ELSE
            _eCause := E_DL_QtlCause.eRetryOver;   (* 归因：重试耗尽 / Cause: retry exhausted *)
            _bFaultReq := TRUE;
        END_IF
    END_IF
E_DL_QtlPhase.eTemper:
    IF _bTemperBand AND tonTemper.Q THEN
        _ePhase := E_DL_QtlPhase.eCool;            (* 带内且总窗到 -> 冷却 / In band and window done *)
    ELSIF tonTemper.Q THEN
        _eCause := E_DL_QtlCause.eTemperTmo;       (* 归因：回火超时（带内未达） / Cause: temper timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eCool:
    IF _bPartBad THEN
        _eCause := E_DL_QtlCause.eSigBad;          (* 归因：温度信号非有限 / Cause: signal *)
        _bFaultReq := TRUE;
    ELSIF fPartTempC <= fCoolSetC THEN
        _ePhase := E_DL_QtlPhase.eUnload;          (* 冷到出料温度 -> 下料 / Cooled, unload *)
    ELSIF tonCool.Q THEN
        _eCause := E_DL_QtlCause.eCoolTmo;         (* 归因：冷却超时 / Cause: cool timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eUnload:
    IF bUnloadPermit THEN
        _bDonePulse := TRUE;                       (* 单拍完成（段 1 预清） / One-scan done *)
        _tCycleLast := CalcCycleTime();            (* 委托方法换算节拍 / Delegate cycle conversion *)
        _fCycleSumS := _fCycleSumS + _fCycleAccS;  (* 节拍总和累加 / Cycle sum *)
        _fCycleAccS := 0.0;                        (* 本件累加清零 / Clear accumulator *)
        IF _nPiece < DL_QTL_PCMAX THEN
            _nPiece := _nPiece + 1;                (* 产量推进（容量载体判上限） / Saturating count *)
        END_IF
        _ePhase := E_DL_QtlPhase.eIdle;            (* 回待机迎下一件 / Back to idle *)
    ELSIF tonUnload.Q THEN
        _eCause := E_DL_QtlCause.eUnloadTmo;       (* 归因：下料超时 / Cause: unload timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_QtlPhase.eFault:
    bError := TRUE;                                (* 故障相驻留（锁存回放） / Fault residency *)
E_DL_QtlPhase.eSafeStop:
    bError := TRUE;                                (* 安全相驻留（锁存回放） / Safety residency *)
ELSE
    _eCause := E_DL_QtlCause.ePhaseBad;            (* 非法相位兜底 / Illegal phase fallback *)
    _bFault := TRUE;                               (* 兜底锁存 / Fallback latch *)
    _eGrade := E_DL_QtlGrade.eG2;                  (* 兜底分级 E2 / Fallback grade *)
    _ePhase := E_DL_QtlPhase.eFault;               (* 回安全侧 / Fall back to fault *)
    bError := TRUE;
END_CASE

(* —— 段 8：统一出口（电平量由 _ePhase 派生，单拍量由 _b* 标志映射） —— *)
eState := _ePhase;                                 (* 相出口 / Phase outlet *)
eCause := _eCause;                                 (* 成因回放 / Cause playback *)
eGrade := _eGrade;                                 (* 分级出口 / Grade outlet *)
bError := bError OR _bFault OR _bSafeLatch;        (* 故障标志汇总（E1 不置） / Error summary *)
bSafeCut := _bSafeLatch;                           (* 安全断能指令 / Safety energy cut *)
bHeatActive := (_ePhase = E_DL_QtlPhase.eHeat);    (* 加热相指示 / Heating indicator *)
bQuenchActive := (_ePhase = E_DL_QtlPhase.eQuench);(* 淬火相指示 / Quench indicator *)
bDone := _bDonePulse;                              (* 单拍完成脉冲 / One-scan done *)
nPieceCount := _nPiece;                            (* 产量出口 / Count outlet *)
tCycleLast := _tCycleLast;                         (* 节拍出口 [ms] / Cycle outlet *)
IF _nPiece > 0 THEN
    fCycleAvgS := _fCycleSumS / UDINT_TO_LREAL(_nPiece);   (* 均值分母已判非零 / Guarded mean *)
ELSE
    fCycleAvgS := 0.0;                             (* 无件输出 0 / No piece, zero *)
END_IF
nRetryUsed := _nRetry;                             (* 重试占用出口 / Retry outlet *)
_ePhasePrev := _ePhase;                            (* 段末相快照（下拍迁移后置用） / Phase snapshot *)
END_FUNCTION_BLOCK
