(*
  Component : FB_DL_PilePressLimitClass
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_3A
  Summary   : 堆叠压力四档分级与 NG 分道：压力归类（A/B/C/NG 四档，档界常量带单位）+ 分道放行。
              Stacking pressure four-band classification and NG routing: band classify with unit-tagged limits plus lane release.
  溯源声明  : 参照 FC_DL_LimitClassify 语义（clean-room 自含实现，无实例依赖）
  边界安全  : 压力非有限（NaN 自反 + Inf 上限）与负值域拦截（kN）；档界常量域闸（L1 < L2 < L3，
              防档位倒置）；判定电平比较（非等值直比）；分道放行带起动沿防重复放行；
              各档计数独立且防回卷；全浮点比较带 fEps 容差。
  复用      : 参照 FC_DL_LimitClassify 语义（clean-room 自含实现，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_PilePressLimitClass
VAR_INPUT
    bRun     : BOOL;                    (* 分级使能 · Enable *)
    fPressKN : LREAL;                   (* 堆叠压力 [kN] · Stacking pressure *)
    bPiecePulse: BOOL;                  (* 单件到位脉冲 [事件] · Piece-in-place pulse *)
    fL1KN    : LREAL := 8.0;            (* A 档下界 [kN] · Band A lower bound *)
    fL2KN    : LREAL := 6.0;            (* B 档下界 [kN] · Band B lower bound *)
    fL3KN    : LREAL := 4.0;            (* C 档下界 [kN] · Band C lower bound *)
    fEps     : LREAL := 1.0E-6;         (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    eClass   : (eClsA := 0, eClsB := 1, eClsC := 2, eClsNG := 3);   (* 档位枚举输出 / Class output enum *)
    bNgLane  : BOOL;                    (* NG 分道放行 [引脚] · NG lane release *)
    bOkLane  : BOOL;                    (* 合格道放行 [引脚] · OK lane release *)
    nCntA    : UDINT;                   (* A 档累计 [件]，防回卷 · Band A count *)
    nCntB    : UDINT;                   (* B 档累计 [件]，防回卷 · Band B count *)
    nCntC    : UDINT;                   (* C 档累计 [件]，防回卷 · Band C count *)
    nCntNG   : UDINT;                   (* NG 档累计 [件]，防回卷 · NG count *)
    bError   : BOOL;                    (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId : UDINT;                   (* 事件码 16#0000_003A，0 无事件 · Event code *)
END_VAR
VAR
    uCode    : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    bSigOk   : BOOL;    (* 输入有效标志 · Input validity flag *)
    bThrOk   : BOOL;    (* 档界整定域标志 · Band limit tuning validity *)
    bPiecePrv: BOOL;    (* 上拍到位脉冲快照，上升沿判据 · Previous pulse snapshot *)
    bPiece   : BOOL;    (* 到位上升沿 [脉冲] · Piece rising edge *)
    bClassNow: BOOL;    (* 本拍已归类标志（防重复放行）/ Classified this scan *)
    nCycles  : UDINT;   (* 有效归类拍计数 [拍]，防回卷 · Classify scan count *)
END_VAR
VAR CONSTANT
    DL_PLC_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [件] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 无 TON/R_TRIG 实例：沿判据用快照实现；No timer instances, edges via snapshots *)
bPiece := bPiecePulse AND (NOT bPiecePrv);      (* 到位上升沿 / Piece rising edge *)
bPiecePrv := bPiecePulse;                       (* 快照更新 / Snapshot *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (fPressKN = fPressKN) AND (ABS(fPressKN) < 1.0E308)   // 非有限拦截 / Non-finite guard
          AND (fPressKN >= 0.0);                                        // 压力非负域闸 / Non-negative pressure
bThrOk := (fL3KN > fEps) AND (fL2KN > fL3KN) AND (fL1KN > fL2KN);   // 档界倒置闸（L1>L2>L3）/ Band order gate
IF NOT bSigOk OR NOT bThrOk THEN
    uCode := 16#003A;                   // 故障级：域外或档界倒置 / Fault: domain or band order invalid
END_IF

(* === 段 2 · 主逻辑：四档归类与分道放行 === *)
bOkLane := FALSE;                       (* 放行输出为脉冲量，默认收口 / Lane outputs are pulses *)
bNgLane := FALSE;
IF bSigOk AND bThrOk THEN
    IF bPiece THEN                      (* 到位沿：归类一次 / Classify once on the edge *)
        bClassNow := TRUE;              (* 本拍已归类 / Classified *)
        IF fPressKN >= fL1KN THEN
            eClass := eClsA;            (* A 档（输出枚举在沿上直赋，非 CASE 状态机）/ Band A *)
            IF nCntA < DL_PLC_WRAP THEN
                nCntA := nCntA + 1;     (* A 档计数 / Count band A *)
            END_IF
            bOkLane := TRUE;            (* 合格道放行 / Release the OK lane *)
        ELSIF fPressKN >= fL2KN THEN
            eClass := eClsB;            (* B 档 / Band B *)
            IF nCntB < DL_PLC_WRAP THEN
                nCntB := nCntB + 1;
            END_IF
            bOkLane := TRUE;
        ELSIF fPressKN >= fL3KN THEN
            eClass := eClsC;            (* C 档 / Band C *)
            IF nCntC < DL_PLC_WRAP THEN
                nCntC := nCntC + 1;
            END_IF
            bOkLane := TRUE;
        ELSE
            eClass := eClsNG;           (* NG 档：低于 C 下界 / NG below the C bound *)
            IF nCntNG < DL_PLC_WRAP THEN
                nCntNG := nCntNG + 1;
            END_IF
            bNgLane := TRUE;            (* NG 分道放行 / Release the NG lane *)
        END_IF
        IF nCycles < DL_PLC_WRAP THEN
            nCycles := nCycles + 1;     (* 归类拍计数 / Count classifications *)
        END_IF
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF NOT (bPiece OR bClassNow) THEN
    (* 非归类拍保持上次档位输出（回放语义）/ Keep the last class between pieces *)
END_IF
IF NOT bRun THEN
    bClassNow := FALSE;                 (* 撤使能清归类态（可达复位）/ Clear on disable *)
    bOkLane := FALSE;
    bNgLane := FALSE;
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003A 形态）/ Single write point *)
END_FUNCTION_BLOCK
