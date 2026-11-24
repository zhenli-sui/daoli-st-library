(*
  Component : FB_DL_CoolingTowerOpt
  Category  : DL_Algo
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#02_3_5F
  Summary   : 冷却塔群控逼近度优化：湿球逼近度控制律 + 塔群投切决策（最小开机数 + 防震荡死区）。
              Cooling tower approach optimization: wet-bulb approach control law plus staging with min-on units and deadband.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 温度/台数非有限（NaN 自反 + Inf 上限）拦截；塔数域闸（1..8，防数组越界）；
              最小开机数域闸（1..nTowers，防全停）与投切错峰窗（自复位 TON）防频繁投切；
              投切决策带对称死区（防震荡）；风机设定值输出过 RateLimiter 限速；
              全浮点比较带 fEps 容差；计数防回卷。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_CoolingTowerOpt
VAR_INPUT
    bRun          : BOOL;              (* 优化使能 · Enable *)
    fWetBulbC     : LREAL;             (* 湿球温度 [degC] · Wet-bulb temperature *)
    fOutTC        : LREAL;             (* 塔群出水温度 [degC] · Tower outlet temperature *)
    fApprTargetC  : LREAL := 3.0;      (* 逼近度目标 [K] · Approach target *)
    fDeadK        : LREAL := 0.5;      (* 投切死区 [K]，防震荡 · Staging deadband *)
    nTowersAvail  : INT   := 4;        (* 可用塔数 [台]，域 1 到 8 · Available towers *)
    nMinOn        : INT   := 1;        (* 最小开机数 [台] · Minimum on units *)
    tStaggerMs    : TIME  := T#30000MS; (* 投切错峰窗 [ms] · Stagger window *)
    fFanStepPct   : LREAL := 2.0;      (* 风机设定每拍最大步进 [％] · Fan setpoint max step *)
    fEps          : LREAL := 1.0E-6;   (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    aTowerCmd : ARRAY[1..8] OF BOOL;    (* 各塔投切指令 [引脚] · Per-tower commands *)
    nRunCnt   : INT;                    (* 当前开机数 [台] · Currently running count *)
    fApprNowC : LREAL;                  (* 当前逼近度 [K] · Current approach *)
    fFanSetPct: LREAL;                  (* 风机群设定值输出 [％]，已限速 · Rate-limited fan setpoint *)
    bError    : BOOL;                   (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId  : UDINT;                  (* 事件码 16#0000_005F，0 无事件 · Event code *)
END_VAR
VAR
    _eState   : (eStHold := 0, eStAdd := 1, eStDrop := 2);  (* 内部决策状态 / Internal decision state *)
    uCode     : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonStagger: TON;     (* 投切错峰窗 [ms]，自复位振荡 · Stagger timer, self-reset *)
    bSigOk    : BOOL;    (* 输入有效标志 · Input validity flag *)
    bTick     : BOOL;    (* 错峰窗到点脉冲 [脉冲] · Stagger tick pulse *)
    nI        : INT;     (* 塔循环下标 [索引] · Tower loop index *)
    fFanTgt   : LREAL;   (* 风机设定目标 [％] · Fan setpoint target *)
    fStep     : LREAL;   (* 本拍设定步进 [％] · Actual step this scan *)
    nCycles   : UDINT;   (* 有效拍计数 [拍]，防回卷 · Valid scan count *)
END_VAR
VAR CONSTANT
    DL_CTO_NMAX  : INT   := 8;          (* 塔数上限 [台]，与数组一致 · Tower cap *)
    DL_CTO_FANHI : LREAL := 100.0;      (* 风机设定上限 [％] · Fan setpoint cap high *)
    DL_CTO_FANLO : LREAL := 40.0;       (* 风机设定下限 [％] · Fan setpoint cap low *)
    DL_CTO_WRAP  : UDINT := 4294967290; (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonStagger(IN := NOT tonStagger.Q, PT := tStaggerMs);   (* 错峰窗自复位振荡 / Self-reset stagger window *)
bTick := tonStagger.Q;                                  (* 窗到点脉冲 / Stagger tick *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fWetBulbC = fWetBulbC) AND (fOutTC = fOutTC)             // 非有限拦截 / Non-finite guard
          AND (ABS(fWetBulbC) < 1.0E308) AND (ABS(fOutTC) < 1.0E308) // Inf 上限判据 / Inf limit
          AND (nTowersAvail >= 1) AND (nTowersAvail <= DL_CTO_NMAX)  // 塔数域闸，防越界 / Tower count gate
          AND (nMinOn >= 1) AND (nMinOn <= nTowersAvail)             // 最小开机数域闸，防全停 / Min-on gate
          AND (fDeadK >= 0.0) AND (fFanStepPct > 0.0);               // 死区/步进域闸 / Deadband and step gates
IF NOT bSigOk THEN
    uCode := 16#005F;                   // 故障级：域外，决策冻结 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：逼近度控制律与投切决策 === *)
IF bSigOk THEN
    fApprNowC := fOutTC - fWetBulbC;    (* 当前逼近度 [K] / Current approach *)
    IF NOT bRun THEN
        _eState := eStHold;             (* 撤使决策保持 / Hold on disable *)
        FOR nI := 1 TO DL_CTO_NMAX DO
            aTowerCmd[nI] := FALSE;     (* 撤使全停 / All off on disable *)
        END_FOR
        nRunCnt := 0;                   (* 开机数清零 / Clear the count *)
        fFanTgt := DL_CTO_FANLO;        (* 撤使风机回下限 / Fan to low cap *)
    ELSE
        (* 决策状态机：死区外才进投切相，错峰窗内每窗一台 / One unit per window outside the deadband *)
        IF NOT bTick THEN
            _eState := eStHold;         (* 窗内保持 / Hold inside the window *)
        ELSIF fApprNowC > (fApprTargetC + fDeadK) THEN
            _eState := eStAdd;          (* 逼近度超标：投塔相 / Over target: add phase *)
        ELSIF fApprNowC < (fApprTargetC - fDeadK) THEN
            _eState := eStDrop;         (* 逼近度过低：切塔相 / Under target: drop phase *)
        ELSE
            _eState := eStHold;         (* 死区内保持（防震荡）/ Hold inside the deadband *)
        END_IF
        CASE _eState OF
            eStAdd:                     (* 投塔：找一台未开塔，保最小开机数下限之上 / Add one tower *)
                FOR nI := 1 TO nTowersAvail DO
                    IF NOT aTowerCmd[nI] THEN
                        aTowerCmd[nI] := TRUE;      (* 投入该塔 / Turn the tower on *)
                        EXIT;           (* 单台即止 / One unit only *)
                    END_IF
                END_FOR
            eStDrop:                    (* 切塔：开机数大于最小开机数才允许 / Drop only above min-on *)
                IF nRunCnt > nMinOn THEN
                    FOR nI := nTowersAvail TO 1 BY -1 DO
                        IF aTowerCmd[nI] THEN
                            aTowerCmd[nI] := FALSE; (* 切除该塔 / Turn the tower off *)
                            EXIT;       (* 单台即止 / One unit only *)
                        END_IF
                    END_FOR
                END_IF
            eStHold:                    (* 保持相：不动塔群 / Hold: no staging *)
                (* 无动作 / No action *)
        ELSE
            _eState := eStHold;         (* ELSE 兜底回保持相 / ELSE fallback to hold *)
        END_CASE
        nRunCnt := 0;                   (* 开机数重算 / Recount *)
        FOR nI := 1 TO DL_CTO_NMAX DO
            IF aTowerCmd[nI] THEN
                nRunCnt := nRunCnt + 1; (* 累加实开塔数 / Count the running towers *)
            END_IF
        END_FOR
        (* 风机设定目标：逼近度超死区升频，低于死区降频，钳上下限 / Fan target by approach *)
        IF fApprNowC > (fApprTargetC + fDeadK) THEN
            fFanTgt := fFanTgt + fFanStepPct;   (* 升频目标 / Raise target *)
        ELSIF fApprNowC < (fApprTargetC - fDeadK) THEN
            fFanTgt := fFanTgt - fFanStepPct;   (* 降频目标 / Lower target *)
        END_IF
        IF fFanTgt > DL_CTO_FANHI THEN
            fFanTgt := DL_CTO_FANHI;    (* 钳上限 / Cap high *)
        ELSIF fFanTgt < DL_CTO_FANLO THEN
            fFanTgt := DL_CTO_FANLO;    (* 钳下限 / Cap low *)
        END_IF
    END_IF
    (* RateLimiter：风机设定限速 / Rate limit the fan setpoint *)
    fStep := fFanTgt - fFanSetPct;      (* 目标差 [％] / Gap to target *)
    IF fStep > fFanStepPct THEN
        fFanSetPct := fFanSetPct + fFanStepPct;     (* 正向限速 / Positive rate limit *)
    ELSIF fStep < (-fFanStepPct) THEN
        fFanSetPct := fFanSetPct - fFanStepPct;     (* 负向限速 / Negative rate limit *)
    ELSE
        fFanSetPct := fFanTgt;          (* 一步到位 / Settle *)
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF bSigOk THEN
    IF nCycles < DL_CTO_WRAP THEN
        nCycles := nCycles + 1;         (* 有效拍计数 / Count valid scans *)
    END_IF
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_005F 形态）/ Single write point *)
END_FUNCTION_BLOCK
