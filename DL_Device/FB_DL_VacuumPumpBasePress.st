(*
  Component : FB_DL_VacuumPumpBasePress
  Category  : DL_Device
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#03_1_03
  Summary   : 真空泵本底压强与恢复时间台账：本底压强滑动平均平滑 + 起泵恢复超时事件计数留痕。
              Vacuum pump base pressure and recovery ledger: moving-average smoothing plus restart recovery timeout counting.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 压强非物理域闸（负压 < 0 拦截，非有限 NaN/Inf 拦截）；MA 环形缓冲点数域闸（2..16，防越界）；
              采样窗/恢复窗时长正域闸（> 0）；MA 采样窗与恢复计时窗为独立 TON 实例；
              恢复超时计数用事件触发（timing 停止后不重复累加）；锁存故障有可达清码路径（恢复成功即清）。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_VacuumPumpBasePress
VAR_INPUT
    bRun       : BOOL;                  (* 监视使能 · Enable *)
    bPumpRun   : BOOL;                  (* 泵运行反馈 [开关]，上升沿起恢复计时 · Pump run feedback *)
    fPressKpa  : LREAL;                 (* 泵入口压强 [kPa] · Pump inlet pressure *)
    fBaseOkKpa : LREAL := 5.0;          (* 本底压强达标阈 [kPa] · Base pressure target *)
    tMaWinMs   : TIME  := T#2000MS;     (* MA 采样节拍 [ms] · MA sample pace *)
    tRecWinMs  : TIME  := T#60000MS;    (* 恢复计时窗 [ms] · Recovery timing window *)
    nMaPts     : INT   := 8;            (* MA 有效点数 [点]，域 2 到 16 · MA valid points *)
    fEps       : LREAL := 1.0E-6;       (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fMaKpa      : LREAL;                (* 本底压强滑动平均 [kPa] · Moving average pressure *)
    bRecTiming  : BOOL;                 (* 恢复计时进行中 [开关] · Recovery timing active *)
    bRecOk      : BOOL;                 (* 最近一次恢复成功 [开关] · Last recovery succeeded *)
    nRecTimeout : UDINT;                (* 恢复超时累计 [次]，事件计数防回卷 · Recovery timeout count *)
    bError      : BOOL;                 (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId    : UDINT;                (* 事件码 16#0000_0103，0 无事件 · Event code *)
END_VAR
VAR
    uCode    : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonMa    : TON;     (* MA 采样节拍 [ms]，自复位振荡 · MA pace timer, self-reset *)
    tonRec   : TON;     (* 恢复计时窗 [ms]，独立实例 · Recovery window timer, separate instance *)
    rTrigRun : R_TRIG;  (* 起泵上升沿 · Pump start rising edge *)
    aRing    : ARRAY[1..16] OF LREAL;   (* MA 环形缓冲 [kPa] · MA ring buffer *)
    nHead    : INT;     (* 环形头下标 [索引] · Ring head index *)
    nFill    : INT;     (* 已填充点数 [点] · Filled point count *)
    fSum     : LREAL;   (* 环内累加和 [kPa] · Ring sum *)
    bRecFlt  : BOOL;    (* 恢复超时锁存 · Recovery timeout latched *)
    bSigOk   : BOOL;    (* 输入有效标志 · Input validity flag *)
    bTick    : BOOL;    (* 采样到点脉冲 [脉冲] · Sample tick pulse *)
    nI       : INT;     (* 求和循环下标 [索引] · Sum loop index *)
END_VAR
VAR CONSTANT
    DL_VBP_NMAX : INT := 16;            (* 环形缓冲容量 [点] · Ring capacity *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonMa(IN := NOT tonMa.Q, PT := tMaWinMs);       (* 采样节拍自复位振荡 / Self-reset MA pace *)
tonRec(IN := bRecTiming, PT := tRecWinMs);      (* 恢复计时窗独立实例 / Separate recovery window *)
rTrigRun(CLK := bPumpRun);                      (* 起泵沿检测 / Pump start edge *)
bTick := tonMa.Q;                               (* 采样脉冲 / Sample tick *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fPressKpa = fPressKpa) AND (ABS(fPressKpa) < 1.0E308)    // 非有限拦截 / Non-finite guard
          AND (fPressKpa >= 0.0)                                     // 压强非负域闸 / Non-negative pressure
          AND (nMaPts >= 2) AND (nMaPts <= DL_VBP_NMAX)              // 点数域闸，防越界 / Point-count gate
          AND (tMaWinMs > T#0MS) AND (tRecWinMs > T#0MS);            // 窗时长正域闸 / Window duration gates
IF NOT bSigOk THEN
    uCode := 16#0103;                   // 故障级：域外，台账冻结 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：MA 平滑与恢复台账 === *)
IF bSigOk THEN
    IF bTick THEN                       (* 采样到点：写环并重算均值 / Sample tick: write ring *)
        IF nFill < nMaPts THEN
            nFill := nFill + 1;         (* 未满先增填充数 / Grow fill count *)
        ELSE
            fSum := fSum - aRing[nHead];    (* 满环先减旧值 / Remove the old value *)
        END_IF
        aRing[nHead] := fPressKpa;      (* 写入新采样 / Write the new sample *)
        fSum := fSum + fPressKpa;       (* 累加新值 / Add the new value *)
        nHead := (nHead MOD DL_VBP_NMAX) + 1;   (* 头下标循环推进 / Advance the head *)
    END_IF
    IF nFill >= 2 THEN
        fMaKpa := fSum / UDINT_TO_LREAL(INT_TO_UDINT(nFill));   (* 均值，填充数 ≥2 已闸 / Mean *)
    END_IF
    (* 恢复台账：起泵沿起计时，达标即成功，超窗即超时计数 / Recovery ledger *)
    IF rTrigRun.Q THEN
        bRecTiming := TRUE;             (* 拍 N 起泵沿进入，本拍置计时，拍 N+1 tonRec 生效 / Start timing *)
        bRecOk := FALSE;                (* 新恢复未达标 / New recovery pending *)
    END_IF
    IF bRecTiming AND (fMaKpa <= fBaseOkKpa) AND (nFill >= nMaPts) THEN
        bRecTiming := FALSE;            (* 达标：停止计时 / Reached target: stop timing *)
        bRecOk := TRUE;                 (* 恢复成功 / Recovery succeeded *)
        bRecFlt := FALSE;               (* 超时锁存清码（可达路径）/ Reachable clear of the latch *)
    END_IF
    IF bRecTiming AND tonRec.Q THEN     (* 计时窗满仍未达标 / Window expired without target *)
        bRecTiming := FALSE;            (* 停止计时，防重复计数 / Stop timing, no double count *)
        bRecFlt := TRUE;                (* 超时锁存 / Latch the timeout *)
        IF nRecTimeout < 4294967290 THEN
            nRecTimeout := nRecTimeout + 1;     (* 事件计数，一次恢复只计一次 / Count once per recovery *)
        END_IF
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF NOT bRun THEN
    bRecTiming := FALSE;                (* 撤使能停计时 / Stop timing on disable *)
END_IF
bError := bRecFlt OR (uCode <> 16#0000);        (* 故障标志：超时锁存或域外 / Fault flag *)
IF bRecFlt THEN
    uErrorId := WORD_TO_UDINT(16#0103); (* 码位 16#0000_0103 恢复超时锁存 / Recovery timeout code *)
ELSE
    uErrorId := WORD_TO_UDINT(uCode);   (* 域外码或零 / Domain code or zero *)
END_IF
END_FUNCTION_BLOCK
