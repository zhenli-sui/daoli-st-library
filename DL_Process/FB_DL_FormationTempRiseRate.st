(*
  Component : FB_DL_FormationTempRiseRate
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_3E
  Summary   : 化成温升速率监视与异常电芯截断：MA 前置平滑 + 速率微分 + 工艺窗分级报警 + 截断独立。
              Formation temp rise rate monitor: MA pre-smoothing plus rate differentiation, graded alarm, separate truncate.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 温度非有限（NaN 自反 + Inf 上限）与负绝对温度域拦截；MA 点数域闸（2..16）；
              微分前置 MA 平滑防单拍毛刺误截断（按派单要点）；节拍正域闸与速率分母防除零；
              截断动作与报警分离，截断锁存仅手动复位沿可解除；TON/R_TRIG 每拍无条件刷新。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_FormationTempRiseRate
VAR_INPUT
    bRun        : BOOL;                 (* 监视使能 · Enable *)
    fTempC      : LREAL;                (* 电芯温度 [degC] · Cell temperature *)
    tPaceMs     : TIME  := T#1000MS;    (* 速率采样节拍 [ms] · Rate sample pace *)
    nMaPts      : INT   := 8;           (* MA 平滑点数 [点]，域 2 到 16 · MA smoothing points *)
    fRateHiKps  : LREAL := 0.5;         (* 高速升率报警阈 [K/s] · High rise rate threshold *)
    fRateCritKps: LREAL := 1.0;         (* 临界升率截断阈 [K/s] · Critical truncate threshold *)
    bTruncReset : BOOL;                 (* 截断手动复位 [事件]，沿触发 · Truncate manual reset *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fMaTempC  : LREAL;                  (* 平滑后温度 [degC] · Smoothed temperature *)
    fRateKps  : LREAL;                  (* 温升速率 [K/s] · Temperature rise rate *)
    bWarnHi   : BOOL;                   (* 高速升率报警（非锁存）· High rate warning *)
    bTruncate : BOOL;                   (* 异常截断指令锁存 · Latched truncate command *)
    bError    : BOOL;                   (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId  : UDINT;                  (* 事件码 16#0000_003E，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    tonPace : TON;      (* 采样节拍 [ms]，自复位振荡 · Sample pace timer, self-reset *)
    rTrigRst: R_TRIG;   (* 截断复位沿检测 · Truncate reset edge *)
    aRing   : ARRAY[1..16] OF LREAL;    (* 温度环形缓冲 [degC] · Temperature ring buffer *)
    nHead   : INT;      (* 环形头下标 [索引] · Ring head index *)
    nFill   : INT;      (* 已填充点数 [点] · Filled point count *)
    fMaPrv  : LREAL;    (* 上节拍平滑温度快照 [degC] · Previous MA snapshot *)
    fDtS    : LREAL;    (* 节拍秒值 [s]，一次导出 · Pace seconds *)
    bSnapOk : BOOL;     (* 快照有效标志 · Snapshot validity *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    bTick   : BOOL;     (* 采样到点脉冲 [脉冲] · Sample tick pulse *)
    nI      : INT;      (* 求和循环下标 [索引] · Sum loop index *)
    nCycles : UDINT;    (* 有效采样拍计数 [拍]，防回卷 · Sample count *)
END_VAR
VAR CONSTANT
    DL_FTR_ABS0 : LREAL := 273.15;      (* 绝对零度 [degC] · Absolute zero *)
    DL_FTR_NMAX : INT := 16;            (* 环形容量 [点] · Ring capacity *)
    DL_FTR_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonPace(IN := NOT tonPace.Q, PT := tPaceMs);    (* 节拍自复位振荡 / Self-reset pace *)
rTrigRst(CLK := bTruncReset);                   (* 截断复位沿 / Truncate reset edge *)
bTick := tonPace.Q;                             (* 采样脉冲 / Sample tick *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fTempC = fTempC) AND (ABS(fTempC) < 1.0E308)             // 非有限拦截 / Non-finite guard
          AND (fTempC > -DL_FTR_ABS0 + fEps)                         // 绝对零物理域闸 / Physical domain
          AND (nMaPts >= 2) AND (nMaPts <= DL_FTR_NMAX)              // MA 点数域闸 / MA point gate
          AND (tPaceMs > T#0MS)                                      // 节拍正域闸 / Pace gate
          AND (fRateHiKps > 0.0) AND (fRateCritKps > fRateHiKps);    // 阈值序闸 / Threshold order gate
IF fDtS < fEps THEN
    fDtS := DINT_TO_LREAL(TIME_TO_DINT(tPaceMs)) / 1000.0;      (* 节拍秒值一次导出 / Derive once *)
END_IF
IF NOT bSigOk THEN
    uCode := 16#003E;                   // 故障级：域外，监视冻结 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：MA 平滑与速率微分 === *)
IF bSigOk THEN
    IF bTick THEN
        IF nHead < 1 THEN
            nHead := 1;                 (* 头下标初值钳 1，防零下标越界 / Clamp the head to one *)
        END_IF
        IF nFill < nMaPts THEN
            nFill := nFill + 1;         (* 未满先增填充 / Grow fill *)
        END_IF
        aRing[nHead] := fTempC;         (* 写入采样 / Write the sample *)
        nHead := (nHead MOD DL_FTR_NMAX) + 1;   (* 头下标循环推进 / Advance the head *)
        fMaTempC := 0.0;                (* 平滑和清零 / Clear the sum *)
        FOR nI := 1 TO nMaPts DO
            IF nI <= nFill THEN
                fMaTempC := fMaTempC + aRing[nI];   (* 窗内累加 / Accumulate in window *)
            END_IF
        END_FOR
        fMaTempC := fMaTempC / UDINT_TO_LREAL(INT_TO_UDINT(nFill));     (* MA 均值 [degC] / MA mean *)
        IF bSnapOk THEN
            fRateKps := (fMaTempC - fMaPrv) / fDtS;     (* 速率微分 [K/s]，MA 前置平滑 / Differentiated rate *)
            IF fRateKps < 0.0 THEN
                fRateKps := 0.0;        (* 降温段速率钳零 / Clamp negative rate *)
            END_IF
        END_IF
        fMaPrv := fMaTempC;             (* 快照更新 / Update the snapshot *)
        bSnapOk := TRUE;                (* 快照有效 / Snapshot valid *)
        IF nCycles < DL_FTR_WRAP THEN
            nCycles := nCycles + 1;     (* 有效采样计数 / Count samples *)
        END_IF
    END_IF
    bWarnHi := (fRateKps > fRateHiKps); (* 高速升率报警（非锁存自清）/ Non-latched warning *)
    IF fRateKps > fRateCritKps THEN
        bTruncate := TRUE;              (* 临界截断锁存 / Latch the truncate *)
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF rTrigRst.Q THEN
    bTruncate := FALSE;                 (* 截断仅手动复位沿可解除（可达路径）/ Manual reset clears truncate *)
END_IF
IF NOT bRun THEN
    bWarnHi := FALSE;                   (* 撤使能报警清零 / Clear warnings on disable *)
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003E 形态）/ Single write point *)
END_FUNCTION_BLOCK
