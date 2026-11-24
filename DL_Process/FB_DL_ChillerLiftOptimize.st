(*
  Component : FB_DL_ChillerLiftOptimize
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_37
  Summary   : 冷机 Lift（冷凝-蒸发温差）优化限值：温差基线统计窗 + 设定值 RateLimiter 限速输出。
              Chiller lift optimization: condenser-evaporator baseline statistics window plus rate-limited setpoint.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 温度非有限（NaN 自反 + Inf 上限）拦截；基线统计窗点数域闸（≥ 1）；
              统计窗未满时输出冻结在当前值并置 bBaselineReady=FALSE（按派单要点）；
              设定值输出过 RateLimiter 限速（每拍步进钳制，防设定值跳变）；全浮点比较带 fEps 容差。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_ChillerLiftOptimize
VAR_INPUT
    bRun        : BOOL;                 (* 优化使能 · Enable *)
    fCondTC     : LREAL;                (* 冷凝器温度 [degC] · Condenser temperature *)
    fEvapTC     : LREAL;                (* 蒸发器温度 [degC] · Evaporator temperature *)
    nWinScans   : INT := 600;           (* 基线统计窗长 [拍] · Baseline window length *)
    fStepMaxK   : LREAL := 0.1;         (* 设定值每拍最大步进 [K] · Setpoint max step per scan *)
    fDeadK      : LREAL := 0.5;         (* 优化死区 [K]，防频繁调节 · Optimization deadband *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fLiftNowK   : LREAL;                (* 当前 Lift [K] · Current lift *)
    fLiftBaseK  : LREAL;                (* 基线平均 Lift [K] · Baseline mean lift *)
    fSetK       : LREAL;                (* 优化设定值输出 [K]，已限速 · Rate-limited setpoint *)
    bBaselineReady: BOOL;               (* 基线窗满标志 · Baseline ready flag *)
    bError      : BOOL;                 (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId    : UDINT;                (* 事件码 16#0000_0037，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    fSumK   : LREAL;    (* 窗内 Lift 累加和 [K·拍] · Window sum *)
    nFill   : INT;      (* 窗内已累计拍数 [拍] · Window filled scans *)
    fTargetK: LREAL;    (* 目标设定值 [K] · Target setpoint *)
    fStepK  : LREAL;    (* 本拍实际步进 [K] · Actual step this scan *)
    nCycles : UDINT;    (* 有效拍计数 [拍]，防回卷 · Valid scan count *)
END_VAR
VAR CONSTANT
    DL_CLO_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 无 TON/R_TRIG 实例：基线窗按拍计数；No timer instances, scan-counted window *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fCondTC = fCondTC) AND (fEvapTC = fEvapTC)               // 非有限拦截 / Non-finite guard
          AND (ABS(fCondTC) < 1.0E308) AND (ABS(fEvapTC) < 1.0E308) // Inf 上限判据 / Inf limit
          AND (nWinScans >= 1)                                      // 窗长域闸 / Window length gate
          AND (fStepMaxK > 0.0) AND (fDeadK >= 0.0);                // 步进正域闸 / Step and deadband gates
IF NOT bSigOk THEN
    uCode := 16#0037;                   // 故障级：域外，输出冻结 / Fault: domain invalid, frozen
END_IF

(* === 段 2 · 主逻辑：Lift 基线统计与设定值限速 === *)
IF bSigOk THEN
    fLiftNowK := fCondTC - fEvapTC;     (* 当前 Lift [K] / Current lift *)
    IF bRun THEN
        IF nFill < nWinScans THEN
            fSumK := fSumK + fLiftNowK; (* 窗内累加 / Accumulate in window *)
            nFill := nFill + 1;         (* 窗计数推进 / Advance the window count *)
            bBaselineReady := FALSE;    (* 窗未满：基线未就绪 / Window not full *)
        ELSE
            fLiftBaseK := fSumK / UDINT_TO_LREAL(INT_TO_UDINT(nWinScans));  (* 基线均值 [K] / Baseline mean *)
            bBaselineReady := TRUE;     (* 窗满：基线就绪 / Window full, baseline ready *)
            IF fLiftNowK > (fLiftBaseK + fDeadK) THEN
                fTargetK := fLiftBaseK; (* 超死区回基线目标 / Target back to baseline *)
            ELSE
                fTargetK := fSetK;      (* 死区内保持现值 / Hold inside the deadband *)
            END_IF
        END_IF
    ELSE
        nFill := 0;                     (* 撤使能重开统计窗 / Restart the window on disable *)
        fSumK := 0.0;
        bBaselineReady := FALSE;        (* 撤使能基线失效 / Baseline not ready *)
    END_IF
    (* RateLimiter：设定值每拍步进钳制 / Rate limiter: clamp the per-scan step *)
    fStepK := fTargetK - fSetK;         (* 目标差 [K] / Gap to target *)
    IF fStepK > fStepMaxK THEN
        fSetK := fSetK + fStepMaxK;     (* 正向限速 / Positive rate limit *)
    ELSIF fStepK < (-fStepMaxK) THEN
        fSetK := fSetK - fStepMaxK;     (* 负向限速 / Negative rate limit *)
    ELSE
        fSetK := fTargetK;              (* 一步到位 / Settle to target *)
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF bSigOk THEN
    IF nCycles < DL_CLO_WRAP THEN
        nCycles := nCycles + 1;         (* 有效拍计数 / Count valid scans *)
    END_IF
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_0037 形态）/ Single write point *)
END_FUNCTION_BLOCK
