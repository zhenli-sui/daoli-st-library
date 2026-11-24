(*
  Component : FB_DL_FilmTaperTension
  Category  : DL_Motion
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#04_0_6C
  Summary   : 薄膜锥度张力给定曲线：卷径计算 + 锥度张力给定 + 收卷闭环握手（VAR_IN_OUT）。
              Film taper tension setpoint: roll diameter calculation plus taper curve with a winding handshake via VAR_IN_OUT.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 卷径最小值域闸（> 最小卷径常量，防除零，按派单要点）；膜厚正域闸（> 0）；
              锥度系数为 0 时退化为恒张力（按派单要点）；张力给定钳非负下限；
              与 FB_DL_WindingTensionCtrl 的握手经 VAR_IN_OUT（ioTensionAck），不写其内部状态；
              全浮点比较带 fEps 容差；计数防回卷。
  复用      : 与 FB_DL_WindingTensionCtrl 握手（VAR_IN_OUT 引脚级，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_FilmTaperTension
VAR_INPUT
    bRun        : BOOL;                 (* 给定使能 · Enable *)
    fCoreDiaM   : LREAL := 0.075;       (* 卷芯直径 [m] · Core diameter *)
    fFilmThickUm: LREAL := 20.0;        (* 膜厚 [um] · Film thickness *)
    nTurns      : DINT;                 (* 已卷圈数 [圈] · Wrapped turns *)
    fTensionBaseN: LREAL := 50.0;       (* 外层基准张力 [N] · Base tension at full roll *)
    fTaperK     : LREAL := 0.5;         (* 锥度系数 [比值]，0 为恒张力 · Taper coefficient *)
    fDiaRefM    : LREAL := 0.60;        (* 锥度参考卷径 [m] · Taper reference diameter *)
    fEps        : LREAL := 1.0E-6;      (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_IN_OUT
    ioTensionAck: BOOL;                 (* 收卷闭环握手应答 [引脚]，由张力控件置位 · Handshake ack from the winding ctrl *)
END_VAR
VAR_OUTPUT
    fDiaM       : LREAL;                (* 当前卷径 [m] · Current roll diameter *)
    fTensionSetN: LREAL;                (* 张力给定输出 [N] · Tension setpoint output *)
    bDiaReady   : BOOL;                 (* 卷径有效标志 · Diameter validity flag *)
    bHandshakeOk: BOOL;                 (* 握手应答有效 [开关] · Handshake accepted *)
    bError      : BOOL;                 (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId    : UDINT;                (* 事件码 16#0000_006C，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    fDiaMin : LREAL;    (* 最小卷径域值 [m] · Minimum diameter *)
    fRatio  : LREAL;    (* 参考卷径比 [比值] · Diameter ratio *)
    nCycles : UDINT;    (* 有效给定拍计数 [拍]，防回卷 · Valid setpoint count *)
END_VAR
VAR CONSTANT
    DL_FTT_UM2M : LREAL := 1.0E-6;      (* um 到 m 系数 [m/um] · Micrometers to meters *)
    DL_FTT_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 无 TON/R_TRIG 实例：给定按拍直算；No timer instances, direct per-scan setpoint *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
fDiaMin := fCoreDiaM + fEps;            (* 最小卷径域值 [m] / Minimum diameter *)
bSigOk := (fCoreDiaM = fCoreDiaM) AND (fFilmThickUm = fFilmThickUm) // 非有限拦截 / Non-finite guard
          AND (fTensionBaseN = fTensionBaseN) AND (fDiaRefM = fDiaRefM)
          AND (ABS(fCoreDiaM) < 1.0E308) AND (ABS(fDiaRefM) < 1.0E308)  // Inf 上限判据 / Inf limits
          AND (fCoreDiaM > fEps)                                        // 卷芯正域闸 / Core diameter gate
          AND (fFilmThickUm > fEps)                                     // 膜厚正域闸 / Thickness gate
          AND (fTensionBaseN >= 0.0)                                    // 张力非负域闸 / Non-negative tension
          AND (fTaperK >= 0.0)                                          // 锥度系数非负闸 / Taper coefficient gate
          AND (fDiaRefM > fEps) AND (nTurns >= 0);                      // 参考卷径/圈数域闸 / Reference and turns gates
IF NOT bSigOk THEN
    uCode := 16#006C;                   // 故障级：域外，给定冻结 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：卷径计算与锥度张力给定 === *)
IF bSigOk THEN
    fDiaM := fCoreDiaM + 2.0 * DINT_TO_LREAL(nTurns) * fFilmThickUm * DL_FTT_UM2M;
                                        (* 卷径 = 芯径 + 2×圈数×膜厚 [m] / Diameter from turns *)
    IF fDiaM < fDiaMin THEN
        fDiaM := fDiaMin;               (* 卷径最小值防御（防除零）/ Minimum diameter guard *)
    END_IF
    bDiaReady := TRUE;                  (* 卷径有效 / Diameter valid *)
    IF fTaperK < fEps THEN
        fTensionSetN := fTensionBaseN;  (* 锥度系数为 0：退化为恒张力 / Zero taper: constant tension *)
    ELSE
        fRatio := fDiaRefM / fDiaM;     (* 参考卷径比（分母已最小值防御）/ Diameter ratio *)
        fTensionSetN := fTensionBaseN * (1.0 + fTaperK * (fRatio - 1.0));
                                        (* 锥度张力给定 [N]：内层紧外层松 / Taper tension setpoint *)
        IF fTensionSetN < 0.0 THEN
            fTensionSetN := 0.0;        (* 给定钳非负下限 / Clamp non-negative *)
        END_IF
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
bHandshakeOk := ioTensionAck;           (* 握手应答直读映射（引脚级，不写对方内部）/ Handshake mapping *)
IF bSigOk THEN
    IF nCycles < DL_FTT_WRAP THEN
        nCycles := nCycles + 1;         (* 有效给定计数 / Count valid setpoints *)
    END_IF
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_006C 形态）/ Single write point *)
END_FUNCTION_BLOCK
