(*
  Name: FC_DL_StripLengthAccumCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：带长累计：编码器脉冲差分解算 + 辊径磨损补偿，累积为米制长度。
  边界条件：① 两浮点入参过非有限闸，配置越域置 xValid = FALSE 并保持末值（不清零，防长度跳变）；
            ② 差分为负视为计数器清零或回绕：本拍不计入（reset 语义），并把快照更新到当前值；
            ③ 本件在 FC 内使用 VAR 保持量（上一拍脉冲、累计长度）；交付门槛：须在 CODESYS / TwinCAT /
               InoProShop 三平台各编译验证一次，确认 FC 局部静态量保留语义一致（R64 门槛声明）；
            ④ 有效辊径 = 标称辊径 − 磨损量，须 > 10 mm 否则判配置非法（周长为除数量纲基准）。
  量纲自证：脉冲数/每转脉冲数 = 转；转 × π·D[m] = m；D 由 mm/1000 得 m。
*)
FUNCTION FC_DL_StripLengthAccumCalc : REAL
VAR_INPUT
    nPulse : DINT;          (* 编码器累计脉冲（有符号，允许回绕） [pulse] Encoder pulse count [pulse] *)
    nPulsePerRev : DINT;    (* 每转脉冲数 [pulse/rev] Pulses per revolution [pulse/rev] *)
    fRollDiaMm : REAL;      (* 测量辊标称直径 [mm] Measuring roll nominal diameter [mm] *)
    fRollWearMm : REAL;     (* 测量辊累计磨损量 [mm] Roll accumulated wear [mm] *)
    xReset : BOOL;          (* 长度清零（换卷时置位一拍） [-] Reset accumulated length *)
END_VAR
VAR_OUTPUT
    fLengthM : REAL;        (* 累计长度 [m] Accumulated length [m] *)
    fRollDiaEffMm : REAL;   (* 有效（磨损后）辊径 [mm] Effective roll diameter [mm] *)
    xValid : BOOL;          (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _nPulsePrev : DINT := 0;    (* 上一拍脉冲快照 [pulse] Previous pulse snapshot [pulse] *)
    _diDelta : DINT := 0;       (* 本拍脉冲增量 [pulse] Pulse increment [pulse] *)
    _fLenAccM : REAL := 0.0;    (* 累计长度保持量 [m] Accumulated length hold [m] *)
    _fCircM : REAL := 0.0;      (* 有效周长 [m] Effective circumference [m] *)
    _fDiaEff : REAL := 0.0;     (* 有效辊径保持量 [mm] Effective diameter hold [mm] *)
    _bCfgBad : BOOL := FALSE;   (* 配置非法当拍量 [-] Configuration bad *)
END_VAR
VAR CONSTANT
    DL_MM_TO_M : REAL := 1000.0;    (* 毫米 → 米换算 [mm/m] Millimetre to metre *)
    DL_DIA_MIN : REAL := 10.0;      (* 有效辊径下限 [mm] Effective diameter floor [mm] *)
    DL_DIA_MAX : REAL := 2000.0;    (* 标称辊径上限 [mm] Nominal diameter ceiling [mm] *)
    DL_WEAR_MAX : REAL := 50.0;     (* 磨损量上限 [mm] Wear ceiling [mm] *)
END_VAR
(* 出口预置：三出口与返回值统一预置（R256） *)
fLengthM := 0.0; fRollDiaEffMm := 0.0; xValid := FALSE; FC_DL_StripLengthAccumCalc := 0.0;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，两浮点入参全枚举 *)
IF (fRollDiaMm <> fRollDiaMm) OR ((fRollDiaMm - fRollDiaMm) <> 0.0)
   OR (fRollWearMm <> fRollWearMm) OR ((fRollWearMm - fRollWearMm) <> 0.0) THEN
    fLengthM := _fLenAccM;                  (* 保持末值 / Hold last value *)
    fRollDiaEffMm := _fDiaEff;
    FC_DL_StripLengthAccumCalc := _fLenAccM;
    RETURN;
END_IF
(* 组态域闸：每转脉冲数为除子，磨损量不得吞掉辊径 *)
_bCfgBad := (nPulsePerRev < 1) OR (fRollDiaMm < (DL_DIA_MIN + DL_DIA_MIN))
         OR (fRollDiaMm > DL_DIA_MAX) OR (fRollWearMm < 0.0) OR (fRollWearMm > DL_WEAR_MAX);
IF _bCfgBad THEN
    fLengthM := _fLenAccM;                  (* 冻结保持，xValid 置假 / Freeze and mark invalid *)
    fRollDiaEffMm := _fDiaEff;
    FC_DL_StripLengthAccumCalc := _fLenAccM;
    RETURN;
END_IF
(* 有效辊径与周长：周长 = π·D，D 用米 *)
_fDiaEff := fRollDiaMm - fRollWearMm;
IF _fDiaEff <= DL_DIA_MIN THEN
    fLengthM := _fLenAccM;                  (* 磨损过限：冻结保持 / Wear too large, freeze *)
    fRollDiaEffMm := _fDiaEff;
    FC_DL_StripLengthAccumCalc := _fLenAccM;
    RETURN;
END_IF
_fCircM := 3.141592653589793 * (_fDiaEff / DL_MM_TO_M);
(* 脉冲差分：负增量视为计数器清零/回绕，本拍不计入 *)
_diDelta := nPulse - _nPulsePrev;
IF _diDelta > 0 THEN
    (* 转数 = 脉冲 ÷ 每转脉冲，再乘周长得米 *)
    _fLenAccM := _fLenAccM + (DINT_TO_REAL(_diDelta) / DINT_TO_REAL(nPulsePerRev)) * _fCircM;
END_IF
(* 清零：只清长度累计，不动配置（作用域声明） *)
IF xReset THEN
    _fLenAccM := 0.0;
END_IF
(* 末行更新快照：无论增量正负，快照都跟上，防回绕后重复计数 *)
_nPulsePrev := nPulse;
fLengthM := _fLenAccM;
fRollDiaEffMm := _fDiaEff;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_StripLengthAccumCalc := fLengthM;
END_FUNCTION
