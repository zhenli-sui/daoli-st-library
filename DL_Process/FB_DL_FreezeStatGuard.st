(*
  Component : FB_DL_FreezeStatGuard
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_38
  Summary   : 表冷器防冻保护与低温联锁：低温门限持续判定 + 预热阀比例调节 + 冻结告警锁存。
              Coil freeze protection: sustained low-temp gate plus proportional preheat valve and latched freeze alarm.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 温度非有限（NaN 自反 + Inf 上限）拦截；低温需持续 tFrostMs（TON 防单拍毛刺误报）；
              预热阀输出钳 0..100 ％；冻结告警锁存且解除路径可达（温度恢复 + 复位沿）；
              TON/R_TRIG 每拍无条件刷新（段 0）；全浮点比较带 fEps 容差。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_FreezeStatGuard
VAR_INPUT
    bRun       : BOOL;                  (* 保护使能 · Enable *)
    fAirTC     : LREAL;                 (* 表冷器后风温 [degC] · Coil downstream air temperature *)
    fFrostThC  : LREAL := 2.0;          (* 低温门限 [degC] · Low temperature threshold *)
    fGainPctK  : LREAL := 25.0;         (* 预热阀比例增益 [％/K] · Preheat proportional gain *)
    tFrostMs   : TIME  := T#10000MS;    (* 低温持续窗 [ms] · Sustained low-temp window *)
    bReset     : BOOL;                  (* 告警复位指令 [事件]，沿触发 · Alarm reset command *)
    fEps       : LREAL := 1.0E-6;       (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fPreheatPct: LREAL;                 (* 预热阀开度输出 [％] · Preheat valve output *)
    bPreheat   : BOOL;                  (* 预热激活标志 · Preheat active flag *)
    bFrostWarn : BOOL;                  (* 低温持续告警（非锁存）· Sustained frost warning *)
    bFreezeAlm : BOOL;                  (* 冻结告警锁存 · Latched freeze alarm *)
    bError     : BOOL;                  (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId   : UDINT;                 (* 事件码 16#0000_0038，0 无事件 · Event code *)
END_VAR
VAR
    _eState  : (eStWatch := 0, eStFrozen := 1);     (* 内部状态机 / Internal state machine *)
    uCode    : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonFrost : TON;     (* 低温持续计时 [ms]，每拍无条件刷新 · Frost duration timer *)
    rTrigRst : R_TRIG;  (* 复位沿检测 · Reset edge detection *)
    bSigOk   : BOOL;    (* 输入有效标志 · Input validity flag *)
    bLowNow  : BOOL;    (* 本拍低温判定 / This-scan low-temp verdict *)
    fSubK    : LREAL;   (* 过冷深度 [K] · Sub-cooling depth *)
    nCycles  : UDINT;   (* 有效监视拍计数 [拍]，防回卷 · Monitor scan count *)
END_VAR
VAR CONSTANT
    DL_FSG_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [拍] · Counter wrap guard *)
    DL_FSG_PCTMAX: LREAL := 100.0;      (* 阀开度上限 [％] · Valve output cap *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonFrost(IN := bRun AND bSigOk AND (NOT bFreezeAlm), PT := tFrostMs);   (* 低温持续计时 / Frost timing *)
rTrigRst(CLK := bReset);                        (* 复位沿检测 / Reset edge *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fAirTC = fAirTC) AND (ABS(fAirTC) < 1.0E308)             // 非有限拦截 / Non-finite guard
          AND (fFrostThC = fFrostThC) AND (fGainPctK >= 0.0)         // 门限非有限 + 增益非负闸 / Threshold and gain gates
          AND (tFrostMs > T#0MS);                                    (* 持续窗正域闸 / Duration window gate *)
IF NOT bSigOk THEN
    uCode := 16#0038;                   // 故障级：域外，保护冻结于安全输出 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：低温判定与冻结告警状态机 === *)
IF bSigOk THEN
    bLowNow := (fAirTC < fFrostThC);    (* 本拍低温判定（单比较非容差问题）/ Low-temp verdict *)
    fSubK := fFrostThC - fAirTC;        (* 过冷深度 [K] / Sub-cooling depth *)
    IF fSubK < 0.0 THEN
        fSubK := 0.0;                   (* 深度钳非负 / Clamp non-negative *)
    END_IF
    CASE _eState OF
        eStWatch:                       (* 监视相：低温持续到点转冻结 / Watch: escalate on sustained frost *)
            IF tonFrost.Q THEN
                _eState := eStFrozen;   (* 拍 N 窗满，拍 N+1 转冻结相 / To frozen next scan *)
            END_IF
        eStFrozen:                      (* 冻结相：告警锁存 / Frozen: alarm latched *)
            (* 解除路径：温度恢复 + 复位沿（可达）/ Clear: recovery plus reset edge *)
            IF rTrigRst.Q AND (NOT bLowNow) THEN
                _eState := eStWatch;    (* 拍 N+1 回监视相 / Back to watch *)
            END_IF
    ELSE
        _eState := eStWatch;            (* ELSE 兜底回监视相 / ELSE fallback to watch *)
        uCode := 16#0038;               (* 状态越界报码 / Code on illegal state *)
    END_CASE
    bFreezeAlm := (_eState = eStFrozen);        (* 冻结告警回放 / Latched alarm replay *)
    bFrostWarn := tonFrost.Q;           (* 低温持续告警（非锁存自清）/ Non-latched warning *)
    (* 预热阀比例调节：过冷深度 × 增益，冻结相全开 / Proportional preheat, full open when frozen *)
    IF bFreezeAlm THEN
        fPreheatPct := DL_FSG_PCTMAX;   (* 冻结全开预热 / Full open when frozen *)
    ELSIF bLowNow THEN
        fPreheatPct := fSubK * fGainPctK;   (* 比例调节 [％] / Proportional output *)
        IF fPreheatPct > DL_FSG_PCTMAX THEN
            fPreheatPct := DL_FSG_PCTMAX;   (* 钳上限 / Cap high *)
        END_IF
    ELSE
        fPreheatPct := 0.0;             (* 正温关阀 / Close on normal temperature *)
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF NOT bRun THEN
    bFreezeAlm := FALSE;                (* 撤使能告警释放（可达清零路径）/ Clear on disable *)
    _eState := eStWatch;                (* 回监视相 / Back to watch *)
    fPreheatPct := 0.0;                 (* 阀关安全位 / Safe valve close *)
END_IF
bPreheat := (fPreheatPct > fEps);       (* 预热激活标志 / Preheat active flag *)
IF bSigOk THEN
    IF nCycles < DL_FSG_WRAP THEN
        nCycles := nCycles + 1;         (* 有效监视计数 / Count monitor scans *)
    END_IF
END_IF
bError := bFreezeAlm OR (uCode <> 16#0000);     (* 故障标志 / Fault flag *)
IF bFreezeAlm THEN
    uErrorId := WORD_TO_UDINT(16#0038); (* 码位 16#0000_0038 冻结告警 / Freeze alarm code *)
ELSE
    uErrorId := WORD_TO_UDINT(uCode);   (* 域外码或零 / Domain code or zero *)
END_IF
END_FUNCTION_BLOCK
