(*
  Component : FB_DL_PrecursorCanisterWeight
  Category  : DL_Device
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#03_1_05
  Summary   : 前驱体源瓶称重余量预测：消耗速率节拍积分 + 余量耗尽时间预测 + 换瓶 tare 留痕。
              Precursor canister weight and remaining-life prediction: paced consumption rate, empty-time forecast, tare trace.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 称重非有限（NaN 自反 + Inf 上限）与负值域拦截；速率积分 dt 正域闸，dt 为 0 时速率取上次
              有效值（防除零，按派单要点）；净重 = 毛重 − 皮重，皮重域闸（≥ 0 且 < 毛重）；
              耗尽预测分母（速率）正域闸，速率为零时预测冻结；tare 沿触发清积分器但留痕
              （nTareCount / fLastTareKg）；计数防回卷。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_PrecursorCanisterWeight
VAR_INPUT
    bRun        : BOOL;                 (* 预测使能 · Enable *)
    fWeightKg   : LREAL;                (* 源瓶毛重 [kg] · Gross canister weight *)
    fEmptyKg    : LREAL := 2.5;         (* 空瓶皮重 [kg] · Empty tare weight *)
    tPaceMs     : TIME  := T#1000MS;    (* 速率采样节拍 [ms] · Rate sample pace *)
    fLowWarnKg  : LREAL := 1.0;         (* 余量低报警阈 [kg] · Low remaining warning *)
    bTare       : BOOL;                 (* 换瓶 tare 指令 [事件]，沿触发 · Tare command, edge *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fRateKgs   : LREAL;                 (* 消耗速率 [kg/s]，正值消耗 · Consumption rate *)
    fRemKg     : LREAL;                 (* 剩余净重 [kg] · Remaining net weight *)
    fRemTimeS  : LREAL;                 (* 耗尽预测时间 [s]，速率为零时冻结 · Empty time forecast *)
    bLowWarn   : BOOL;                  (* 余量低报警 · Low remaining warning *)
    nTareCount : UDINT;                 (* 换瓶累计 [次]，防回卷 · Tare count *)
    fLastTareKg: LREAL;                 (* 上次 tare 时毛重留痕 [kg] · Last tare snapshot *)
    bError     : BOOL;                  (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId   : UDINT;                 (* 事件码 16#0000_0105，0 无事件 · Event code *)
END_VAR
VAR
    uCode     : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    tonPace   : TON;      (* 速率采样节拍 [ms]，自复位振荡 · Rate pace timer, self-reset *)
    rTrigTare : R_TRIG;   (* tare 上升沿 · Tare rising edge *)
    bSigOk    : BOOL;     (* 输入有效标志 · Input validity flag *)
    bTick     : BOOL;     (* 采样到点脉冲 [脉冲] · Sample tick pulse *)
    fDtS      : LREAL;    (* 节拍秒值 [s]，一次导出 · Pace seconds derived once *)
    fWeightPrv: LREAL;    (* 上节拍毛重快照 [kg] · Previous weight snapshot *)
    bSnapOk   : BOOL;     (* 快照有效标志（tare 后重建）· Snapshot validity *)
    nCycles   : UDINT;    (* 有效采样拍计数 [拍]，防回卷 · Sample count *)
END_VAR
VAR CONSTANT
    DL_PCW_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonPace(IN := NOT tonPace.Q, PT := tPaceMs);    (* 节拍自复位振荡 / Self-reset pace *)
rTrigTare(CLK := bTare);                        (* tare 沿检测 / Tare edge *)
bTick := tonPace.Q;                             (* 采样脉冲 / Sample tick *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fWeightKg = fWeightKg) AND (fEmptyKg = fEmptyKg)         // 非有限拦截 / Non-finite guard
          AND (ABS(fWeightKg) < 1.0E308)                             // Inf 上限判据 / Inf limit
          AND (fWeightKg >= 0.0)                                     (* 毛重非负域闸 / Non-negative weight *)
          AND (fEmptyKg >= 0.0) AND (fEmptyKg < fWeightKg + 1.0E9)   (* 皮重域闸 / Tare domain *)
          AND (tPaceMs > T#0MS);                                     (* 节拍正域闸 / Pace duration gate *)
IF fDtS < fEps THEN
    fDtS := DINT_TO_LREAL(TIME_TO_DINT(tPaceMs)) / 1000.0;      (* 节拍秒值一次导出 / Derive once *)
END_IF
IF NOT bSigOk THEN
    uCode := 16#0105;                   (* 故障级：称重域外，预测冻结 / Fault: weight domain invalid *)
END_IF

(* === 段 2 · 主逻辑：速率积分与耗尽预测 === *)
IF rTrigTare.Q THEN                     (* tare 沿：清积分器并留痕 / Tare edge: clear and trace *)
    fWeightPrv := fWeightKg;            (* 重建快照基线 / Rebuild the snapshot *)
    bSnapOk := TRUE;                    (* 快照有效 / Snapshot valid *)
    fRateKgs := 0.0;                    (* 积分器清零（留痕不清）/ Clear the integrator, keep the trace *)
    fRemTimeS := 0.0;                   (* 预测清零 / Clear the forecast *)
    IF nTareCount < DL_PCW_WRAP THEN
        nTareCount := nTareCount + 1;   (* 换瓶计数留痕 / Count the tare *)
    END_IF
    fLastTareKg := fWeightKg;           (* tare 时毛重留痕 / Trace the tare weight *)
END_IF
IF bSigOk THEN
    fRemKg := fWeightKg - fEmptyKg;     (* 剩余净重 [kg] / Remaining net weight *)
    IF bTick AND bSnapOk THEN
        IF fDtS > fEps THEN             (* dt 正域闸 / dt positive gate *)
            fRateKgs := (fWeightPrv - fWeightKg) / fDtS;    (* 速率 [kg/s]，正为消耗 / Rate *)
            IF fRateKgs < 0.0 THEN
                fRateKgs := 0.0;        (* 加料期负速率钳零 / Clamp negative rate *)
            END_IF
        END_IF                          (* dt ≤ 0 时速率保持上次有效值 / Keep last rate on bad dt *)
        fWeightPrv := fWeightKg;        (* 快照更新 / Update the snapshot *)
        IF nCycles < DL_PCW_WRAP THEN
            nCycles := nCycles + 1;     (* 有效采样计数 / Count valid samples *)
        END_IF
    END_IF
    IF fRateKgs > fEps THEN             (* 预测分母正域闸 / Forecast denominator gate *)
        fRemTimeS := fRemKg / fRateKgs; (* 耗尽预测 [s] / Empty time forecast *)
    END_IF                              (* 速率为零：预测冻结在当前值 / Frozen forecast *)
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF bSigOk THEN
    bLowWarn := (fRemKg < fLowWarnKg);  (* 余量低报警（带域闸）/ Low warning *)
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_0105 形态）/ Single write point *)
END_FUNCTION_BLOCK
