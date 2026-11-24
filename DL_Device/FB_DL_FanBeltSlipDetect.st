(*
  Component : FB_DL_FanBeltSlipDetect
  Category  : DL_Device
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#03_1_01
  Summary   : 风机皮带打滑判据：转速比（风扇/电机）偏差速率越阈判打滑，锁存告警并带维护提醒计数。
              Fan belt slip detection: speed-ratio deviation rate over threshold latches the alarm with a maintenance counter.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 电机转速正域闸（> eps 防比值除零）；输入非有限（NaN 自反 + Inf 上限）拦截；
              采样窗时长域闸（tWinMs > 0，防 dt 为零除零）；比值偏差速率比较带容差；
              TON 实例每拍无条件刷新且自复位振荡（IN := NOT ton.Q）；锁存有可达恢复清码路径。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_FanBeltSlipDetect
VAR_INPUT
    bRun       : BOOL;                  (* 监视使能 · Enable *)
    fMotRpm    : LREAL;                 (* 电机转速 [rpm] · Motor speed *)
    fFanRpm    : LREAL;                 (* 风扇转速 [rpm] · Fan speed *)
    fRatioNom  : LREAL := 1.0;          (* 额定风扇/电机转速比 [比值] · Nominal speed ratio *)
    fDevRateTh : LREAL := 0.02;         (* 打滑判据：比值偏差速率阈 [比值/s] · Slip rate threshold *)
    tWinMs     : TIME  := T#1000MS;     (* 采样窗时长 [ms]，禁魔法数 · Sample window *)
    tClearMs   : TIME  := T#5000MS;     (* 恢复清码持续时长 [ms] · Recovery clear duration *)
    fEps       : LREAL := 1.0E-6;       (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    bSlip      : BOOL;                  (* 打滑锁存告警 · Latched slip alarm *)
    fRatioNow  : LREAL;                 (* 当前转速比 [比值] · Current speed ratio *)
    fDevRate   : LREAL;                 (* 比值偏差速率 [比值/s] · Ratio deviation rate *)
    nSlipCount : UDINT;                 (* 打滑事件累计 [次]，防回卷 · Slip event count *)
    bMaintHint : BOOL;                  (* 维护提醒（累计超阈）· Maintenance hint *)
    bError     : BOOL;                  (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId   : UDINT;                 (* 事件码 16#0000_0101，0 无事件 · Event code *)
END_VAR
VAR
    uCode    : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonWin   : TON;     (* 采样窗节拍定时器 [ms]，自复位振荡 · Sample window timer, self-reset *)
    tonClr   : TON;     (* 恢复清码定时器 [ms] · Recovery clear timer *)
    bSigOk   : BOOL;    (* 输入有效标志 · Input validity flag *)
    bTick    : BOOL;    (* 采样窗到点脉冲 [脉冲] · Sample tick pulse *)
    fDtS     : LREAL;   (* 采样窗秒值 [s]，一次导出 · Window seconds derived once *)
    fRatioPrv: LREAL;   (* 上窗比值快照 [比值] · Previous ratio snapshot *)
    bSlipPrv : BOOL;    (* 上拍锁存快照，事件沿判据 · Previous latch snapshot *)
    nSlipCnt2: INT;     (* 连续越阈窗数 [窗] · Consecutive over-threshold windows *)
    nCycles  : UDINT;   (* 有效采样窗计数 [窗]，防回卷 · Sampled window count *)
END_VAR
VAR CONSTANT
    DL_FBS_WRAP  : UDINT := 4294967290; (* 计数防回卷余量 [次] · Counter wrap guard *)
    DL_FBS_HINTN : UDINT := 3;          (* 维护提醒事件阈 [次] · Maintenance hint threshold *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonWin(IN := NOT tonWin.Q, PT := tWinMs);       // 采样窗自复位振荡 / Self-reset oscillating window
tonClr(IN := bSigOk AND (NOT bSlip) AND (nSlipCnt2 = 0), PT := tClearMs);
                                                // 恢复计时：比值正常且无越阈时计时 / Recovery timing
bTick := tonWin.Q;                              // 窗到点脉冲 / Tick pulse

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fMotRpm = fMotRpm) AND (fFanRpm = fFanRpm) AND (fRatioNom = fRatioNom)
          AND (ABS(fMotRpm) < 1.0E308) AND (ABS(fFanRpm) < 1.0E308)     // 非有限拦截 / Non-finite guard
          AND (fMotRpm > fEps) AND (fRatioNom > fEps)                   // 转速/比值正域闸 / Positive domain
          AND (tWinMs > T#0MS);                                         // 窗时长正域闸 / Window duration gate
IF fDtS < fEps THEN
    fDtS := DINT_TO_LREAL(TIME_TO_DINT(tWinMs)) / 1000.0;   // 窗秒值一次导出 / Derive window seconds once
END_IF
IF NOT bSigOk THEN
    uCode := 16#0101;                   // 故障级：输入域外，判据冻结 / Fault: input domain invalid
END_IF

(* === 段 2 · 主逻辑：比值-偏差速率判据 === *)
IF bSigOk THEN
    fRatioNow := fFanRpm / fMotRpm;     // 当前转速比（分母已闸）/ Current ratio
    IF bTick THEN
        fDevRate := (fRatioNow - fRatioPrv) / fDtS;     // 偏差速率 [比值/s]，先算后存快照 / Rate first, then snapshot
        fRatioPrv := fRatioNow;         // 快照更新 / Update the snapshot
        IF ABS(fDevRate) > fDevRateTh THEN
            nSlipCnt2 := nSlipCnt2 + 1; // 连续越阈窗数累加 / Count over-threshold windows
        ELSE
            nSlipCnt2 := 0;             // 正常窗清计数 / Clear on a normal window
        END_IF
        IF nCycles < DL_FBS_WRAP THEN
            nCycles := nCycles + 1;     // 有效窗计数 / Count valid windows
        END_IF
    END_IF
    IF nSlipCnt2 >= 2 THEN              // 连续 2 窗越阈才判打滑（防单拍毛刺）/ Two windows to latch
        bSlip := TRUE;                  // 打滑锁存 / Latch the slip
    END_IF
    IF tonClr.Q THEN                    // 恢复条件持续满足 → 可达清锁存 / Reachable clear path
        bSlip := FALSE;                 // 解除锁存 / Release the latch
        fDevRate := 0.0;                // 速率复位 / Reset the rate
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF bSlip AND (NOT bSlipPrv) THEN
    IF nSlipCount < DL_FBS_WRAP THEN
        nSlipCount := nSlipCount + 1;   // 打滑事件沿计数 / Count slip events on the edge
    END_IF
END_IF
bSlipPrv := bSlip;                      // 锁存快照 / Latch snapshot
bMaintHint := (nSlipCount >= DL_FBS_HINTN);     // 维护提醒 / Maintenance hint
bError := bSlip OR (uCode <> 16#0000);  // 故障标志：打滑或域外 / Fault flag
IF bSlip THEN
    uErrorId := WORD_TO_UDINT(16#0101); // 码位 16#0000_0101 打滑锁存 / Slip latch code
ELSE
    uErrorId := WORD_TO_UDINT(uCode);   // 域外码或零 / Domain code or zero
END_IF
END_FUNCTION_BLOCK
