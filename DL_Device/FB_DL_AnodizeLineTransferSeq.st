(*==============================================================================
  Component : FB_DL_AnodizeLineTransferSeq
  Category  : DL_Device
  Type      : FB
  Complexity: C4
  VERSION   : v1.0.0
  功能      : 阳极氧化线行车转序顺控：三轴位置联动（大车 / 小车 / 升降）+ 槽位占用表互锁
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 顺序闸（硬约束）：升到位（上限位）→ 才允许行走；行走到位（大车 + 小车）→ 才允许下降；
                 下降中任一轴位移信号丢失 → 同拍 E3 断能。
              ② 槽位占用表 abTankBusy 由本件唯一写入：取件相清位、放件相置位，写点各一处；
                 越界 / 占用冲突 / 非法跳槽（跨槽数 > nMaxSkipSteps 或路径中间槽被占）一律 E3。
              ③ 防双载：取件相要求吊具空载且目标槽有料；放件相要求吊具载件且目标槽空闲，
                 不满足即 E3（防丢件 / 防撞件）。方向由 _bHookLoaded 决定，无外部模式引脚。
              ④ 传感器极性义务：bPathBlockedDi / bHoistOverload 为「有障碍 / 过载」正逻辑，
                 断线失效方向（掉电无信号 = 无障碍）由 IO 适配层定义并须现场验证。
              ⑤ 默认引脚组合自证（R114）：位置与夹具类（bBridgeInPos / bTrolleyInPos / bHoistAtUpper /
                 bHoistAtLower / bClampClosed / bClampOpen）默认 FALSE，默认组合无法越过顺序闸直达放行相；
                 使能类（bEStopHealthy）默认 TRUE 与 bEnable 同族，断线由硬件安全回路保证。
              ⑥ 复位作用域（R311）：bReset 沿清 E2/E3 锁存 + 节拍 + 重试；bStop 只清 E2 与相位。
  状态机    : eIdle 待机 / eCheck 目标校验 / eLiftUp 提升到行走高度 / eTravel 大小车行走 /
              eLiftDown 下降到槽内 / eClaim 取件 / eRelease 放件 / eLiftClear 提升离槽 /
              eFault 故障停(E2) / eSafeStop 安全断能(E3)（完成结算在 eLiftClear 相内）
  自检      : R1 零 GVL ｜ R2 零物理地址 ｜ R3 纯 IEC 61131-3 ｜ R4 数组先判界 + 非有限自反判 ｜
              R6 CASE 含 ELSE ｜ R7 六 TON 两沿段 0 无条件刷新 ｜ R13 无倒序循环（单升序镜像环） ｜
              R15 定长 ARRAY，无变长数组透传 ｜ R14 无属性件
==============================================================================*)
TYPE E_DL_AtlPhase :
(
    eIdle     := 0,     (* 待机：等启动沿 / Idle, waiting for start edge *)
    eCheck    := 10,    (* 目标槽校验：越界/占用/跳槽/双载 / Target validation *)
    eLiftUp   := 20,    (* 提升到行走高度（先升后走）/ Lift to travel height *)
    eLiftDown := 40,    (* 下降到槽内（先到位再降）/ Lower into tank *)
    eTravel   := 30,    (* 大小车行走到位 / Bridge and trolley travel *)
    eClaim    := 50,    (* 取件：夹紧到位 / Claim the load *)
    eRelease  := 55,    (* 放件：松开到位 / Release the load *)
    eLiftClear:= 60,    (* 提升离槽（防撞）/ Lift clear of tank *)
    eFault    := 90,    (* 故障停待复位（E2）/ Fault stop awaiting reset, E2 *)
    eSafeStop := 95     (* 安全侧断能（E3）/ Safety energy cut, E3 *)
);
END_TYPE
TYPE E_DL_AtlCause :
(
    eNone        := 0,  (* 无异常 / No anomaly *)
    eTargetRange := 1,  (* 目标槽越界（E3）/ Target out of range, E3 *)
    eTargetSame  := 2,  (* 目标槽与当前槽相同（E3）/ Target equals current, E3 *)
    eSkipIllegal := 3,  (* 非法跳槽：跨槽数超限（E3）/ Illegal skip, E3 *)
    ePathBlocked := 4,  (* 防撞：行走路径中间槽被占（E3）/ Path blocked by occupied tank, E3 *)
    eSlotConflict:= 5,  (* 占用冲突：放件遇占用 / 取件遇空槽（E3）/ Occupancy conflict, E3 *)
    eDoubleLoad  := 6,  (* 防双载：吊具状态与任务不符（E3）/ Double-load violation, E3 *)
    eEStopOpen   := 7,  (* 急停回路断开（E3）/ E-stop circuit open, E3 *)
    eObstruct    := 8,  (* 通道障碍 / 升降过载（E3）/ Obstruction or hoist overload, E3 *)
    eLiftTmo     := 9,  (* 提升超时（E2）/ Lift-up timeout, E2 *)
    eTravelTmo   := 10, (* 行走超时（E1 记录后重试）/ Travel timeout, retried *)
    eLowerTmo    := 11, (* 下降超时（E2）/ Lower timeout, E2 *)
    eClampTmo    := 12, (* 夹取超时（E2）/ Claim timeout, E2 *)
    eOpenTmo     := 13, (* 放件超时（E2）/ Release timeout, E2 *)
    eClearTmo    := 14, (* 离槽超时（E2）/ Lift-clear timeout, E2 *)
    eRetryOver   := 15, (* 重试预算耗尽（E1 升 E2）/ Retry budget exhausted, E2 *)
    ePosBad      := 16, (* 升降位置非有限（E2）/ Hoist position non-finite, E2 *)
    eCfgBad      := 17, (* 组态非法（E2）/ Illegal configuration, E2 *)
    ePhaseBad    := 18  (* 非法相位兜底（E2）/ Illegal phase fallback, E2 *)
);
END_TYPE
TYPE E_DL_AtlGrade :
(
    eG0 := 0,           (* 无异常 / No anomaly *)
    eG1 := 1,           (* E1 可恢复重试：记录后重试，不置 bError / E1 retried, recorded only *)
    eG2 := 2,           (* E2 停机待复位 / E2 stop, awaiting reset *)
    eG3 := 3            (* E3 安全侧立即断能 / E3 immediate safety energy cut *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnodizeLineTransferSeq
VAR_INPUT
    bStart          : BOOL := FALSE;    (* 启动沿（eIdle 入 eCheck） [-] / Start rising edge *)
    bStop           : BOOL := FALSE;    (* 中止：回 eIdle 并清 E2 锁存 [-] / Abort, clears E2 only *)
    bReset          : BOOL := FALSE;    (* 复位沿：清全部锁存 + 重试（R311） [-] / Reset edge *)
    nTargetTank     : INT := -1;        (* 目标槽号，域 0..15（-1 = 未指定） [号] / Target tank index *)
    bBridgeInPos    : BOOL := FALSE;    (* 大车到位（默认 FALSE 禁跳步） [-] / Bridge in position *)
    bTrolleyInPos   : BOOL := FALSE;    (* 小车到位（默认 FALSE 禁跳步） [-] / Trolley in position *)
    bHoistAtUpper   : BOOL := FALSE;    (* 升降上限位（行走高度） [-] / Hoist upper limit *)
    bHoistAtLower   : BOOL := FALSE;    (* 升降下限位（槽内位置） [-] / Hoist lower limit *)
    bClampClosed    : BOOL := FALSE;    (* 夹具夹紧到位 [-] / Clamp closed *)
    bClampOpen      : BOOL := FALSE;    (* 夹具松开到位 [-] / Clamp open *)
    bPathBlockedDi  : BOOL := FALSE;    (* 通道障碍（TRUE = 有障碍，正逻辑） [-] / Path obstruction *)
    bHoistOverload  : BOOL := FALSE;    (* 升降过载（TRUE = 过载，正逻辑） [-] / Hoist overload *)
    bEStopHealthy   : BOOL := TRUE;     (* 急停回路正常（使能类引脚，默认 TRUE） [-] / E-stop healthy *)
    fHoistPosMm     : LREAL := 0.0;     (* 升降实际位置（0 = 下限，向上为正） [mm] / Hoist position [mm] *)
    fHoistSafeMm    : LREAL := 500.0;   (* 行走安全高度，域 0 < v <= fHoistStrokeMm [mm] / Travel-safe height [mm] *)
    fHoistStrokeMm  : LREAL := 2000.0;  (* 升降行程上限，域 > 0 [mm] / Hoist stroke [mm] *)
    nMaxSkipSteps   : INT := 2;         (* 允许跨槽数上限，域 1..15（0 入组态闸） [槽] / Max skip [tanks] *)
    nRetryMax       : UINT := 2;        (* 行走相 E1 重试预算，域 1..9（0 入组态闸） [次] / Retry budget *)
    atPhaseTmo      : ARRAY[0..5] OF TIME := [T#60S, T#60S, T#60S, T#30S, T#30S, T#60S];   (* 超时窗 [ms]，下标 0..5 = 提升/行走/下降/夹取/放件/离槽 / Phase windows [ms] *)
    fCycleSec       : LREAL := 0.0;     (* 扫描周期（<=0 用缺省 0.01s） [s] / Scan cycle [s] *)
END_VAR
VAR_IN_OUT
    abTankBusy      : ARRAY[0..15] OF BOOL;   (* 槽位占用表（跨行车共享，写权限归本件） [-] / Tank occupancy table, written here *)
END_VAR
VAR_OUTPUT
    eState          : E_DL_AtlPhase;    (* 当前相（HMI 诊断） [-] / Present phase *)
    eCause          : E_DL_AtlCause;    (* 成因（锁存回放，R189） [-] / Latched cause playback *)
    eGrade          : E_DL_AtlGrade;    (* 异常分级出口 [-] / Exception grade outlet *)
    bError          : BOOL;             (* 故障标志（E2/E3 为 TRUE，E1 不置） [-] / Error flag *)
    bSafeCut        : BOOL;             (* 安全侧断能指令（E3 常 TRUE 至复位） [-] / Safety energy cut *)
    bHookLoaded     : BOOL;             (* 吊具载件状态（TRUE = 载件） [-] / Hook loaded state *)
    nCurrTank       : INT;              (* 行车当前槽号（-1 = 未知） [号] / Current tank index *)
    nTransferCount  : UDINT;            (* 累计转序次数（饱和） [次] / Transfer count, saturating *)
    bDone           : BOOL;             (* 单拍完成脉冲 [-] / One-scan done pulse *)
    bLiftActive     : BOOL;             (* 升降动作指示（供 IO 层驱动） [-] / Hoist action indicator *)
    bTravelActive   : BOOL;             (* 行走动作指示（供 IO 层驱动） [-] / Travel action indicator *)
    nRetryUsed      : UINT;             (* 当前相已用重试次数 [次] / Retries used in phase *)
END_VAR
VAR
    _ePhase      : E_DL_AtlPhase := E_DL_AtlPhase.eIdle;     (* 内部相（CASE 唯一写入目标） [-] / Internal phase *)
    _ePhasePrev  : E_DL_AtlPhase := E_DL_AtlPhase.eIdle;     (* 上拍相快照（相迁移后置用） [-] / Previous phase *)
    _eCause      : E_DL_AtlCause := E_DL_AtlCause.eNone;     (* 成因锁存量 [-] / Latched cause *)
    _eGrade      : E_DL_AtlGrade := E_DL_AtlGrade.eG0;       (* 分级锁存量 [-] / Latched grade *)
    _bFault      : BOOL := FALSE;       (* E2 锁存位（解除 = bReset 沿或 bStop） [-] / E2 latch *)
    _bSafeLatch  : BOOL := FALSE;       (* E3 锁存位（解除 = bReset 沿且安全恢复） [-] / E3 latch *)
    _bFaultReq   : BOOL := FALSE;       (* 单拍 E2 请求（段 1 预清，段 6 落地） [-] / One-scan E2 request *)
    _bSafeReq    : BOOL := FALSE;       (* 单拍 E3 请求（段 1 预清，段 6 落地） [-] / One-scan E3 request *)
    _bDonePulse  : BOOL := FALSE;       (* 单拍完成标志（段 1 预清） [-] / One-scan done flag *)
    _bHookLoaded : BOOL := FALSE;       (* 吊具载件内部量（分支内唯一切换） [-] / Internal hook state *)
    _bPosBad     : BOOL := FALSE;       (* 升降位置非有限当拍量 [-] / Hoist position non-finite *)
    _bCfgBad     : BOOL := FALSE;       (* 组态非法当拍量 [-] / Configuration bad *)
    _nCurr       : INT := -1;           (* 行车当前槽内部量（-1 = 未知） [号] / Internal current tank *)
    _nTarget     : INT := -1;           (* 目标槽锁存（校验通过时锁存，任务期间改目标无效） [号] / Latched target *)
    _nIdxChk     : INT := 0;            (* 相窗遍历索引（循环变量） [-] / Loop index *)
    _nRetry      : UINT := 0;           (* 当前相重试计数（相迁移后置清） [次] / Retry counter *)
    _nTransfer   : UDINT := 0;          (* 转序累计锁存（饱和） [次] / Transfer count latch *)
    _fCy         : LREAL := 0.0;        (* 当拍有效周期 [s] / Effective cycle *)
    tonLiftUp    : TON;                 (* 提升超时 / Lift-up timeout *)
    tonTravel    : TON;                 (* 行走超时（自复位，E1 可重试） / Travel timeout, self-reset *)
    tonLiftDown  : TON;                 (* 下降超时 / Lower timeout *)
    tonClaim     : TON;                 (* 取件超时 / Claim timeout *)
    tonRelease   : TON;                 (* 放件超时 / Release timeout *)
    tonLiftClear : TON;                 (* 离槽超时 / Lift-clear timeout *)
    rtStart      : R_TRIG;              (* 启动沿（段 0 无条件调用） / Start edge *)
    rtReset      : R_TRIG;              (* 复位沿（段 0 无条件调用） / Reset edge *)
END_VAR
VAR CONSTANT
    DL_ATL_TANKMAX  : INT := 15;            (* 槽号上限（ARRAY[0..15] 上界） [号] / Tank index ceiling *)
    DL_ATL_TANKCNT  : INT := 16;            (* 槽位总数（镜像取模基） [个] / Tank count *)
    DL_ATL_CYDEF    : LREAL := 0.01;        (* 缺省扫描周期 [s] / Default scan cycle [s] *)
    DL_ATL_TCNTMAX  : UDINT := 4294967295;  (* 转序计数饱和上限 [次] / Transfer count ceiling *)
    DL_ATL_RETRYTOP : UINT := 9;            (* 重试预算可配域顶 [次] / Retry configurable ceiling *)
END_VAR

(*-----------------------------------------------------------------------------
  方法 IsTankFree：槽位空闲查询（数组先判界，越界返回 FALSE 不抛错）
  契约：入参槽号越界（<0 或 >15）一律返回 FALSE，调用方须自行把它当"不可用"处理。
-----------------------------------------------------------------------------*)
METHOD PUBLIC IsTankFree : BOOL
VAR_INPUT
    nTank : INT := -1;              (* 待查槽号，域 0..15 [号] / Tank index to query *)
END_VAR

IsTankFree := FALSE;                (* 预置安全值：不可用 / Preset not-free *)
IF (nTank >= 0) AND (nTank <= DL_ATL_TANKMAX) THEN
    IF NOT abTankBusy[nTank] THEN
        IsTankFree := TRUE;         (* 界内且未占用 / In range and free *)
    END_IF
END_IF
END_METHOD

(*-----------------------------------------------------------------------------
  方法 IsPathClear：行走路径中间槽防撞校验（只扫中间槽，两端不在判据内）
  实现：先把起止槽归一为升序区间 [nLo, nHi]，再单升序循环（禁倒序循环，R13）；
        区间两端槽不属于"路径中间槽"，因此循环自 nLo+1 起、到 nHi-1 止。
-----------------------------------------------------------------------------*)
METHOD PUBLIC IsPathClear : BOOL
VAR_INPUT
    nFrom : INT := -1;              (* 起点槽号，域 0..15 [号] / Source tank *)
    nTo   : INT := -1;              (* 终点槽号，域 0..15 [号] / Destination tank *)
END_VAR
VAR
    nLo  : INT := 0;                (* 区间下界（已归一） [号] / Normalised lower bound *)
    nHi  : INT := 0;                (* 区间上界（已归一） [号] / Normalised upper bound *)
    nTmp : INT := 0;                (* 交换暂存 [号] / Swap scratch *)
    nIdx : INT := 0;                (* 升序扫描索引 [号] / Ascending index *)
END_VAR

IsPathClear := FALSE;               (* 预置不放行 / Preset not-clear *)
IF ((nFrom < 0) OR (nFrom > DL_ATL_TANKMAX)) OR ((nTo < 0) OR (nTo > DL_ATL_TANKMAX)) THEN
    IsPathClear := FALSE;           (* 端点越界：不放行 / Endpoint out of range *)
    RETURN;
END_IF
nLo := nFrom;
nHi := nTo;
IF nLo > nHi THEN
    nTmp := nLo;                    (* 归一为升序，避免倒序循环 / Normalise to ascending *)
    nLo := nHi;
    nHi := nTmp;
END_IF
IsPathClear := TRUE;                (* 默认畅通（中间槽为空集即畅通）/ Clear by default *)
FOR nIdx := nLo + 1 TO nHi - 1 DO
    IF abTankBusy[nIdx] THEN
        IsPathClear := FALSE;       (* 中间槽被占 -> 防撞拦截 / Middle tank occupied *)
    END_IF
END_FOR
END_METHOD

(*-----------------------------------------------------------------------------
  方法 NextTankIndex：从指定槽沿指定方向找下一个空闲槽（镜像取模，单升序）
  契约：nDir > 0 向后找 / nDir < 0 向前找 / nDir = 0 返回 -1（非法方向）；
        找不到空闲槽返回 -1。负模修正按 IEC 未定义行为显式补基（+16），不信平台方言。
-----------------------------------------------------------------------------*)
METHOD PUBLIC NextTankIndex : INT
VAR_INPUT
    nFrom : INT := -1;              (* 起点槽号，域 0..15 [号] / Source tank *)
    nDir  : INT := 1;               (* 方向：>0 向后 / <0 向前 [-] / Search direction *)
END_VAR
VAR
    nIdx  : INT := 0;               (* 升序步进索引 [-] / Ascending step index *)
    nCand : INT := -1;              (* 候选槽号 [号] / Candidate tank *)
END_VAR

NextTankIndex := -1;                (* 预置：未找到 / Preset not found *)
IF (nFrom < 0) OR (nFrom > DL_ATL_TANKMAX) THEN
    NextTankIndex := -1;            (* 起点越界 / Source out of range *)
    RETURN;
END_IF
IF nDir = 0 THEN
    NextTankIndex := -1;            (* 方向非法 / Illegal direction *)
    RETURN;
END_IF
FOR nIdx := 1 TO DL_ATL_TANKCNT DO
    nCand := (nFrom + nDir * nIdx) MOD DL_ATL_TANKCNT;   (* 镜像取模 / Mirror modulo *)
    IF nCand < 0 THEN
        nCand := nCand + DL_ATL_TANKCNT;                 (* 负模修正（显式补基）/ Negative modulo fix *)
    END_IF
    IF (nCand >= 0) AND (nCand <= DL_ATL_TANKMAX) THEN
        IF (NOT abTankBusy[nCand]) AND (NextTankIndex < 0) THEN
            NextTankIndex := nCand;                          (* 首个空闲槽 / First free tank *)
        END_IF
    END_IF
END_FOR
END_METHOD

(* —— 段 0：位置非有限判定 + 组态闸 + 周期派生 + 七 TON 两沿无条件刷新（R7） —— *)
_bPosBad := (fHoistPosMm <> fHoistPosMm)
         OR ((fHoistPosMm - fHoistPosMm) <> (fHoistPosMm - fHoistPosMm));   (* NaN 自反 + Inf 差值 / NaN and Inf *)
_bCfgBad := (nRetryMax = 0) OR (nRetryMax > DL_ATL_RETRYTOP)
         OR (fHoistStrokeMm <= 0.0) OR (fHoistSafeMm <= 0.0)
         OR (fHoistSafeMm > fHoistStrokeMm) OR (nMaxSkipSteps < 1) OR (nMaxSkipSteps > DL_ATL_TANKMAX);  (* 静态域闸 / Static gate *)
FOR _nIdxChk := 0 TO 5 DO
    IF atPhaseTmo[_nIdxChk] <= T#0S THEN
        _bCfgBad := TRUE;                              (* 任一相窗非正 -> 组态非法 / Non-positive window *)
    END_IF
END_FOR
IF fCycleSec > 0.0 THEN
    _fCy := fCycleSec;                                 (* 组态周期有效 / Configured cycle *)
ELSE
    _fCy := DL_ATL_CYDEF;                              (* 周期缺省兜底 / Default cycle *)
END_IF
rtStart(CLK := bStart);                                (* 启动沿，每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                (* 复位沿，每拍必调 / Reset edge every scan *)
tonLiftUp(IN := (_ePhase = E_DL_AtlPhase.eLiftUp), PT := atPhaseTmo[0]);          (* 提升窗 / Lift window *)
tonTravel(IN := (_ePhase = E_DL_AtlPhase.eTravel) AND (NOT tonTravel.Q), PT := atPhaseTmo[1]);  (* 行走自复位窗（R188） / Travel self-reset *)
tonLiftDown(IN := (_ePhase = E_DL_AtlPhase.eLiftDown), PT := atPhaseTmo[2]);      (* 下降窗 / Lower window *)
tonClaim(IN := (_ePhase = E_DL_AtlPhase.eClaim), PT := atPhaseTmo[3]);            (* 取件窗 / Claim window *)
tonRelease(IN := (_ePhase = E_DL_AtlPhase.eRelease), PT := atPhaseTmo[4]);        (* 放件窗 / Release window *)
tonLiftClear(IN := (_ePhase = E_DL_AtlPhase.eLiftClear), PT := atPhaseTmo[5]);    (* 离槽窗 / Lift-clear window *)

(* —— 段 1：单拍量预清零（不含锁存/计数/快照量，R107）+ 相迁移后置 —— *)
_bFaultReq := FALSE;                                   (* E2 请求预清 / E2 request preset *)
_bSafeReq := FALSE;                                    (* E3 请求预清 / E3 request preset *)
_bDonePulse := FALSE;                                  (* 完成标志预清 / Done preset *)
bError := FALSE;                                       (* 故障标志预清（出口汇总） / Error preset *)
IF _ePhase <> _ePhasePrev THEN
    _nRetry := 0;                                      (* 相迁移：重试复位 / Retry reset *)
    IF _eGrade = E_DL_AtlGrade.eG1 THEN
        _eGrade := E_DL_AtlGrade.eG0;                  (* E1 记录随相推进清零 / E1 cleared on advance *)
        _eCause := E_DL_AtlCause.eNone;
    END_IF
END_IF

(* —— 段 2：E3 全局安全侧（急停 / 通道障碍 / 升降过载 / 位置非有限）——最高优先级 —— *)
IF (NOT bEStopHealthy) OR bPathBlockedDi OR bHoistOverload OR _bPosBad THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;                             (* 请求落地位于段 6 / Landed in segment 6 *)
        IF NOT bEStopHealthy THEN
            _eCause := E_DL_AtlCause.eEStopOpen;       (* 归因：急停断开 / Cause: E-stop *)
        ELSIF _bPosBad THEN
            _eCause := E_DL_AtlCause.ePosBad;          (* 归因：位置信号非有限 / Cause: position *)
        ELSE
            _eCause := E_DL_AtlCause.eObstruct;        (* 归因：障碍或过载 / Cause: obstruction *)
        END_IF
    END_IF
END_IF

(* —— 段 3：组态闸入 E2 —— *)
IF _bCfgBad AND (NOT _bSafeLatch) AND (NOT _bFault) THEN
    _bFaultReq := TRUE;                                (* 请求落地位于段 6 / Landed in segment 6 *)
    _eCause := E_DL_AtlCause.eCfgBad;                  (* 归因：组态非法 / Cause: config *)
END_IF

(* —— 段 4：迁出链（复位沿 > 中止；作用域逐项声明 R311） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                  (* 作用域①：清 E2 锁存 / Clear E2 *)
    IF NOT ((NOT bEStopHealthy) OR bPathBlockedDi OR bHoistOverload OR _bPosBad) THEN
        _bSafeLatch := FALSE;                          (* 作用域②：安全恢复才清 E3 / Clear E3 only if safe *)
    END_IF
    _eCause := E_DL_AtlCause.eNone;                    (* 作用域③：清成因分级 / Clear cause and grade *)
    _eGrade := E_DL_AtlGrade.eG0;
    _nRetry := 0;                                      (* 作用域④：清重试 / Clear retry *)
    IF NOT _bSafeLatch THEN
        IF (_ePhase = E_DL_AtlPhase.eFault) OR (_ePhase = E_DL_AtlPhase.eSafeStop) THEN
            _ePhase := E_DL_AtlPhase.eIdle;            (* 作用域⑤：故障相迁回待机 / Back to idle *)
        END_IF
    END_IF
ELSIF bStop AND (_ePhase <> E_DL_AtlPhase.eIdle) AND (_ePhase <> E_DL_AtlPhase.eSafeStop) THEN
    IF _ePhase = E_DL_AtlPhase.eFault THEN
        _bFault := FALSE;                              (* 中止清 E2（E3 只由复位清） / Abort clears E2 only *)
        _eCause := E_DL_AtlCause.eNone;
        _eGrade := E_DL_AtlGrade.eG0;
    END_IF
    _nRetry := 0;                                      (* 重试复位 / Retry reset *)
    _ePhase := E_DL_AtlPhase.eIdle;                    (* 回待机 / Back to idle *)
END_IF

(* —— 段 5：主状态机（顺序闸在相序与迁移判据双重固化） —— *)
CASE _ePhase OF
E_DL_AtlPhase.eIdle:
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bSafeLatch) THEN
        _ePhase := E_DL_AtlPhase.eCheck;               (* 入校验相 / To check *)
    END_IF
E_DL_AtlPhase.eCheck:
    IF (nTargetTank < 0) OR (nTargetTank > DL_ATL_TANKMAX) THEN
        _eCause := E_DL_AtlCause.eTargetRange;         (* 归因：越界（E3）/ Cause: out of range *)
        _bSafeReq := TRUE;
    ELSIF (_nCurr >= 0) AND (nTargetTank = _nCurr) THEN
        _eCause := E_DL_AtlCause.eTargetSame;          (* 归因：目标等于当前（E3）/ Cause: same tank *)
        _bSafeReq := TRUE;
    ELSIF (_nCurr >= 0) AND (ABS(nTargetTank - _nCurr) > nMaxSkipSteps) THEN
        _eCause := E_DL_AtlCause.eSkipIllegal;         (* 归因：跨槽数超限（E3）/ Cause: skip too far *)
        _bSafeReq := TRUE;
    ELSIF (_nCurr >= 0) AND (NOT IsPathClear(_nCurr, nTargetTank)) THEN
        _eCause := E_DL_AtlCause.ePathBlocked;         (* 归因：路径中间槽被占（E3）/ Cause: path blocked *)
        _bSafeReq := TRUE;
    ELSIF _bHookLoaded AND (NOT IsTankFree(nTargetTank)) THEN
        _eCause := E_DL_AtlCause.eSlotConflict;        (* 放件遇占用（E3）/ Release into busy tank *)
        _bSafeReq := TRUE;
    ELSIF (NOT _bHookLoaded) AND IsTankFree(nTargetTank) THEN
        _eCause := E_DL_AtlCause.eSlotConflict;        (* 取件遇空槽（E3）/ Claim from empty tank *)
        _bSafeReq := TRUE;
    ELSIF ((NOT _bHookLoaded) AND bClampClosed) OR (_bHookLoaded AND bClampOpen) THEN
        _eCause := E_DL_AtlCause.eDoubleLoad;          (* 防双载：夹具状态与吊具记录矛盾（E3）/ Clamp state contradicts hook record *)
        _bSafeReq := TRUE;
    ELSE
        _nTarget := nTargetTank;                       (* 目标锁存：任务期间改目标无效 / Latch target *)
        _ePhase := E_DL_AtlPhase.eLiftUp;              (* 校验通过 -> 先升到位 / Valid, lift first *)
    END_IF
E_DL_AtlPhase.eLiftUp:
    IF bHoistAtUpper AND (NOT _bPosBad) THEN
        _ePhase := E_DL_AtlPhase.eTravel;              (* 升到位才允许行走 / Lift done, travel allowed *)
    ELSIF tonLiftUp.Q THEN
        _eCause := E_DL_AtlCause.eLiftTmo;             (* 归因：提升超时 / Cause: lift timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_AtlPhase.eTravel:
    IF bBridgeInPos AND bTrolleyInPos AND (NOT bPathBlockedDi) THEN
        _ePhase := E_DL_AtlPhase.eLiftDown;            (* 两轴到位才允许下降 / Both axes in pos, lower *)
    ELSIF tonTravel.Q THEN
        IF _nRetry < nRetryMax THEN
            _nRetry := _nRetry + 1;                    (* E1：可重试，计时器自复位后重计时 / E1 retry *)
            _eGrade := E_DL_AtlGrade.eG1;
            _eCause := E_DL_AtlCause.eTravelTmo;
        ELSE
            _eCause := E_DL_AtlCause.eRetryOver;       (* 归因：重试耗尽 / Cause: retry exhausted *)
            _bFaultReq := TRUE;
        END_IF
    END_IF
E_DL_AtlPhase.eLiftDown:
    IF bHoistAtLower AND bBridgeInPos AND bTrolleyInPos THEN
        IF _bHookLoaded THEN
            _ePhase := E_DL_AtlPhase.eRelease;         (* 载件 -> 放件相 / Carrying, release *)
        ELSE
            _ePhase := E_DL_AtlPhase.eClaim;           (* 空载 -> 取件相 / Empty, claim *)
        END_IF
    ELSIF tonLiftDown.Q THEN
        _eCause := E_DL_AtlCause.eLowerTmo;            (* 归因：下降超时 / Cause: lower timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_AtlPhase.eClaim:
    IF bClampClosed AND bHoistAtLower AND (_nTarget >= 0) AND (_nTarget <= DL_ATL_TANKMAX) THEN
        abTankBusy[_nTarget] := FALSE;              (* 占用表唯一清位点（取件）/ Single clear point *)
        _bHookLoaded := TRUE;                          (* 吊具载件 / Hook loaded *)
        _ePhase := E_DL_AtlPhase.eLiftClear;           (* 提升离槽 / Lift clear *)
    ELSIF tonClaim.Q THEN
        _eCause := E_DL_AtlCause.eClampTmo;            (* 归因：夹取超时 / Cause: claim timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_AtlPhase.eRelease:
    IF bClampOpen AND bHoistAtLower AND (_nTarget >= 0) AND (_nTarget <= DL_ATL_TANKMAX) THEN
        abTankBusy[_nTarget] := TRUE;               (* 占用表唯一置位点（放件）/ Single set point *)
        _bHookLoaded := FALSE;                         (* 吊具空载 / Hook empty *)
        _ePhase := E_DL_AtlPhase.eLiftClear;           (* 提升离槽 / Lift clear *)
    ELSIF tonRelease.Q THEN
        _eCause := E_DL_AtlCause.eOpenTmo;             (* 归因：放件超时 / Cause: release timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_AtlPhase.eLiftClear:
    IF bHoistAtUpper AND (NOT _bPosBad) THEN
        _nCurr := _nTarget;                            (* 当前槽更新（离槽后才确认）/ Current tank committed *)
        _bDonePulse := TRUE;                           (* 单拍完成（段 1 预清）/ One-scan done *)
        IF _nTransfer < DL_ATL_TCNTMAX THEN
            _nTransfer := _nTransfer + 1;              (* 计数推进（容量载体判上限）/ Saturating count *)
        END_IF
        _ePhase := E_DL_AtlPhase.eIdle;                (* 回待机 / Back to idle *)
    ELSIF tonLiftClear.Q THEN
        _eCause := E_DL_AtlCause.eClearTmo;            (* 归因：离槽超时 / Cause: clear timeout *)
        _bFaultReq := TRUE;
    END_IF
E_DL_AtlPhase.eFault:
    bError := TRUE;                                    (* 故障相驻留（锁存回放）/ Fault residency *)
E_DL_AtlPhase.eSafeStop:
    bError := TRUE;                                    (* 安全相驻留（锁存回放）/ Safety residency *)
ELSE
    _eCause := E_DL_AtlCause.ePhaseBad;                (* 非法相位兜底 / Illegal phase fallback *)
    _bFaultReq := TRUE;                                (* 由段 6 落地 / Landed in segment 6 *)
END_CASE

(* —— 段 6：E2/E3 请求统一落地（分支内只写成因与请求，落地仅此一处，R187/R252） —— *)
IF _bSafeReq AND (NOT _bSafeLatch) THEN
    _bSafeLatch := TRUE;                               (* E3 锁存 / Latch E3 *)
    _eGrade := E_DL_AtlGrade.eG3;                      (* 分级 E3 / Grade E3 *)
    _ePhase := E_DL_AtlPhase.eSafeStop;                (* 同步迁安全相 / Migrate *)
    bError := TRUE;                                    (* 故障标志同段置位（R45 配对）/ Error pairing *)
ELSIF _bFaultReq AND (NOT _bSafeLatch) THEN
    _bFault := TRUE;                                   (* E2 锁存 / Latch E2 *)
    _eGrade := E_DL_AtlGrade.eG2;                      (* 分级 E2 / Grade E2 *)
    _ePhase := E_DL_AtlPhase.eFault;                   (* 同步迁相（R252）/ Migrate *)
    bError := TRUE;                                    (* 故障标志同段置位（R45 配对）/ Error pairing *)
END_IF

(* —— 段 7：统一出口（电平量由 _ePhase 派生，单拍量由 _b* 标志映射） —— *)
eState := _ePhase;                                     (* 相出口 / Phase outlet *)
eCause := _eCause;                                     (* 成因回放 / Cause playback *)
eGrade := _eGrade;                                     (* 分级出口 / Grade outlet *)
bError := bError OR _bFault OR _bSafeLatch;            (* 故障标志汇总（E1 不置）/ Error summary *)
bSafeCut := _bSafeLatch;                               (* 安全断能指令 / Safety energy cut *)
bHookLoaded := _bHookLoaded;                           (* 吊具载件出口 / Hook state outlet *)
nCurrTank := _nCurr;                                   (* 当前槽出口 / Current tank outlet *)
nTransferCount := _nTransfer;                          (* 转序计数出口 / Transfer count outlet *)
bDone := _bDonePulse;                                  (* 单拍完成脉冲 / One-scan done *)
bLiftActive := (_ePhase = E_DL_AtlPhase.eLiftUp) OR (_ePhase = E_DL_AtlPhase.eLiftDown)
            OR (_ePhase = E_DL_AtlPhase.eLiftClear);   (* 升降动作指示 / Hoist indicator *)
bTravelActive := (_ePhase = E_DL_AtlPhase.eTravel);    (* 行走动作指示 / Travel indicator *)
nRetryUsed := _nRetry;                                 (* 重试占用出口 / Retry outlet *)
_ePhasePrev := _ePhase;                                (* 段末相快照 / Phase snapshot *)
END_FUNCTION_BLOCK
