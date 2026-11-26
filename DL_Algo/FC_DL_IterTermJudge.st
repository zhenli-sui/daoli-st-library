(* ============================================================
   DL_Algo / FC_DL_IterTermJudge ｜ v1.0.0 ｜ 2026-11-25
   功能：迭代终止四判据仲裁，优先级 超时 > 迭代上限 > 区间宽度 > 步长；
         命中即 bDone=TRUE 并给 uReason：0 继续 / 1 宽度 / 2 步长 / 3 上限 / 4 超时
   边界：容差与超时按 R95 代理阈值三句声明 —— 代理值：宽度 1E-9、步长 1E-9、
         超时 10s；覆盖 1~100ms 常规控制周期；覆盖不到的亚毫秒任务与超长批处理
         由调用方自备阈值件负责。5 号码反证：NaN 输入下四判据比较全假 → 永不终止，
         该死锁无法由 0~4 号组合观测，故立 5 号（R90）
   依赖：仅 IEC 61131-3（ABS / TIME_TO_REAL） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_IterTermJudge : BOOL
VAR_INPUT
    fWidth   : LREAL;  // 当前括号宽度，域 ≥ 0 [-] / Current bracket width
    fStep    : LREAL;  // 上一步位移绝对值，域 ≥ 0 [-] / Absolute step of the last iteration
    uIter    : UDINT;  // 已用迭代次数 [次] / Iterations already consumed
    uIterMax : UDINT;  // 允许最大迭代次数，0 = 不限 [次] / Iteration cap, zero means unlimited
    tElapsed : TIME;   // 已耗时 [ms] / Elapsed time since the iteration started
END_VAR
VAR_OUTPUT
    bDone   : BOOL;   // 终止标志 [-] / Terminate flag
    uReason : UDINT;  // 终止原因码 0/1/2/3/4/5 [-] / Termination reason code
END_VAR
VAR
    _fTEsc : LREAL;  // 超时阈值秒值 [s] / Timeout threshold in seconds
    _fElap : LREAL;  // 已耗时秒值 [s] / Elapsed time in seconds
END_VAR
VAR CONSTANT
    DL_ITJ_XTOL : LREAL := 1.0E-9;  // 区间宽度容差代理值 [-] / Proxy tolerance on the bracket width
    DL_ITJ_STOL : LREAL := 1.0E-9;  // 步长容差代理值 [-] / Proxy tolerance on the step size
    DL_ITJ_TMAX : TIME := T#10S;    // 超时阈值代理值 [ms] / Proxy timeout value
    DL_ITJ_MSPS : LREAL := 1000.0;  // 毫秒 → 秒换算系数 [ms/s] / Milliseconds per second
END_VAR

(* 段 0：出口预置安全侧（不终止、原因 0） *)
FC_DL_IterTermJudge := FALSE;
bDone := FALSE;  uReason := 0;

(* 段 1：非有限闸（判据量不可用 → 安全侧终止，防死锁） *)
IF (fWidth <> fWidth) OR (fStep <> fStep)
   OR ((fWidth - fWidth) <> (fWidth - fWidth)) OR ((fStep - fStep) <> (fStep - fStep)) THEN
    bDone := TRUE;  uReason := 5;  RETURN;
END_IF

(* 段 2：超时判据（最高优先级，时间域不可回退） *)
_fTEsc := TIME_TO_REAL(DL_ITJ_TMAX) / DL_ITJ_MSPS;
_fElap := TIME_TO_REAL(tElapsed) / DL_ITJ_MSPS;
IF _fElap >= _fTEsc THEN bDone := TRUE;  uReason := 4;  RETURN; END_IF

(* 段 3：迭代上限判据（uIterMax = 0 视为不限） *)
IF (uIterMax > 0) AND (uIter >= uIterMax) THEN bDone := TRUE;  uReason := 3;  RETURN; END_IF

(* 段 4：区间宽度判据 *)
IF ABS(fWidth) <= DL_ITJ_XTOL THEN bDone := TRUE;  uReason := 1;  RETURN; END_IF

(* 段 5：步长判据（最后一级，防「步长极小但区间仍宽」的假收敛） *)
IF ABS(fStep) <= DL_ITJ_STOL THEN bDone := TRUE;  uReason := 2;  RETURN; END_IF

(* 段 6：单一出口裁决（N4：未命中任何判据才继续） *)
bDone := FALSE;  uReason := 0;  FC_DL_IterTermJudge := TRUE;
END_FUNCTION
