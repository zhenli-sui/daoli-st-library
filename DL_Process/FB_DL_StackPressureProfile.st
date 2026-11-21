(*
  Component : FB_DL_StackPressureProfile
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_39
  Summary   : 叠片压力曲线与保压判定：压力段轮廓（升压-保压-泄压）+ 保压容差窗 + 越窗分级。
              Stacking pressure profile and hold verdict: ramp-hold-release segments with a tolerance window and graded verdict.
  溯源声明  : 参照 FB_DL_RampSoakProfile 段轮廓骨架语义，clean-room 自含实现，无实例依赖
  边界安全  : 压力非有限（NaN 自反 + Inf 上限）与负值域拦截；段时长正域闸（> 0，防状态机卡死）；
              容差域闸（> 0）；段进度按节拍计数（自复位 TON），越过段尾推进；压力单位 kN 全程标注；
              保压窗判定带容差比较（禁等值直比）；判定结果锁存至下一周期起动沿解除（可达路径）。
  复用      : 参照 FB_DL_RampSoakProfile 骨架语义（clean-room 自含实现，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_StackPressureProfile
VAR_INPUT
    bRun      : BOOL;                   (* 周期使能/起动 [事件] · Cycle enable/start *)
    fPressKN  : LREAL;                  (* 实测压力 [kN] · Measured pressure *)
    fRampKN   : LREAL := 12.0;          (* 升压段目标 [kN] · Ramp target *)
    fHoldKN   : LREAL := 10.0;          (* 保压段目标 [kN] · Hold target *)
    tRampMs   : TIME  := T#2000MS;      (* 升压段时长 [ms] · Ramp duration *)
    tHoldMs   : TIME  := T#3000MS;      (* 保压段时长 [ms] · Hold duration *)
    fTolKN    : LREAL := 0.5;           (* 保压容差 [kN] · Hold tolerance *)
    fEps      : LREAL := 1.0E-6;        (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    ePhase  : (ePhIdle := 0, ePhRamp := 1, ePhHold := 2, ePhRelease := 3);  (* 相枚举输出 / Phase output enum *)
    fTargetKN: LREAL;                   (* 当前段目标压力 [kN] · Current segment target *)
    bInWin  : BOOL;                     (* 本拍在保压容差窗内 [开关] · In the hold window *)
    nViolN  : INT;                      (* 本周期越窗拍数 [拍] · Violation scans this cycle *)
    bError  : BOOL;                     (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId: UDINT;                    (* 事件码 16#0000_0039，0 无事件 · Event code *)
END_VAR
VAR
    _eState : (eStIdle := 0, eStRamp := 1, eStHold := 2, eStRelease := 3);  (* 内部状态机 / Internal state machine *)
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    tonSeg  : TON;      (* 段计时 [ms]，自复位振荡 · Segment timer, self-reset *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    bRunPrv : BOOL;     (* 上拍起动快照，上升沿判据 · Previous run snapshot *)
    bStart  : BOOL;     (* 起动上升沿 [脉冲] · Start rising edge *)
    nCycles : UDINT;    (* 完成周期计数 [次]，防回卷 · Completed cycle count *)
END_VAR
VAR CONSTANT
    DL_SPP_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonSeg(IN := NOT tonSeg.Q, PT := T#100MS);      (* 段进度节拍自复位振荡 / Self-reset progress pace *)
bStart := bRun AND (NOT bRunPrv);               (* 起动上升沿 / Start edge *)
bRunPrv := bRun;                                (* 快照更新 / Snapshot *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fPressKN = fPressKN) AND (ABS(fPressKN) < 1.0E308)   // 非有限拦截 / Non-finite guard
          AND (fPressKN >= 0.0)                                          // 压力非负域闸 / Non-negative pressure
          AND (fTolKN > fEps)                                            // 容差正域闸 / Tolerance gate
          AND (tRampMs > T#0MS) AND (tHoldMs > T#0MS);                   // 段时长正域闸 / Duration gates
IF NOT bSigOk THEN
    uCode := 16#0039;                   // 故障级：域外，轮廓冻结 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：三段轮廓状态机 === *)
IF bStart AND bSigOk THEN
    _eState := eStRamp;                 (* 拍 N 起动沿进入，拍 N+1 升压相 / To ramp on start edge *)
    nViolN := 0;                        (* 新周期越窗计数清零 / Reset violation count *)
    tonSeg(IN := FALSE, PT := T#100MS); (* 段计时复位重启 / Restart the segment timer *)
END_IF
IF bSigOk THEN
    CASE _eState OF
        eStIdle:                        (* 空闲相：目标钳零 / Idle: zero target *)
            fTargetKN := 0.0;           (* 目标零压 / Zero target *)
        eStRamp:                        (* 升压相：目标=升压目标；窗满转保压 / Ramp *)
            fTargetKN := fRampKN;       (* 升压目标 [kN] / Ramp target *)
            IF tonSeg.Q OR (fPressKN >= (fRampKN - fEps)) THEN
                _eState := eStHold;     (* 时窗满或到位转保压 / To hold on time or arrival *)
                tonSeg(IN := FALSE, PT := tHoldMs);     (* 重载保压时长 / Reload hold duration *)
            END_IF
        eStHold:                        (* 保压相：容差窗判定与越窗计数 / Hold: tolerance verdict *)
            fTargetKN := fHoldKN;       (* 保压目标 [kN] / Hold target *)
            bInWin := (fPressKN > (fHoldKN - fTolKN)) AND (fPressKN < (fHoldKN + fTolKN));
                                        (* 容差窗判定（带限非等比）/ In-window verdict *)
            IF NOT bInWin THEN
                nViolN := nViolN + 1;   (* 越窗拍累加 / Count violations *)
            END_IF
            IF tonSeg.Q THEN
                _eState := eStRelease;  (* 保压窗满转泄压 / To release *)
                tonSeg(IN := FALSE, PT := T#100MS);
            END_IF
        eStRelease:                     (* 泄压相：目标回零，到位收周期 / Release *)
            fTargetKN := 0.0;           (* 泄压目标零 [kN] / Release to zero *)
            IF fPressKN < fEps THEN
                _eState := eStIdle;     (* 到位回空闲，周期收口 / Back to idle *)
                IF nCycles < DL_SPP_WRAP THEN
                    nCycles := nCycles + 1;     (* 完成周期计数 / Count the cycle *)
                END_IF
            END_IF
    ELSE
        _eState := eStIdle;             (* ELSE 兜底回空闲安全相 / ELSE fallback to idle *)
        fTargetKN := 0.0;
        uCode := 16#0039;               (* 状态越界报码 / Code on illegal state *)
    END_CASE
END_IF

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
ePhase := ePhIdle;                      (* 相映射默认 / Default mapping *)
IF _eState = eStRamp THEN
    ePhase := ePhRamp;                  (* 升压相映射 / Map ramp *)
ELSIF _eState = eStHold THEN
    ePhase := ePhHold;                  (* 保压相映射 / Map hold *)
ELSIF _eState = eStRelease THEN
    ePhase := ePhRelease;               (* 泄压相映射 / Map release *)
END_IF
IF _eState <> eStHold THEN
    bInWin := FALSE;                    (* 非保压相在窗标志清零 / Clear in-window outside hold *)
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_0039 形态）/ Single write point *)
END_FUNCTION_BLOCK
