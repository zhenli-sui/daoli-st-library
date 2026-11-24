(*
  Component : FB_DL_SoakPitTemperatureCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 坑式炉均热控制：设定-实测偏差带内做简化 PI（比例 + 积分限幅）输出加热百分比，偏差带内持续驻留到时报均热完成。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 偏差带、采样周期、输出上限须 > 1e-9，否则判组态非法并锁存故障；
              ② 积分项做 0~输出上限双侧限幅（抗饱和），使能撤销时积分清零；
              ③ 均热完成位为锁存置位，仅在使能撤销或复位沿清除。
*)
FUNCTION_BLOCK FB_DL_SoakPitTemperatureCtrl
VAR_INPUT
    bEnable    : BOOL;   (* 使能电平 [-] Enable level *)
    bReset     : BOOL;   (* 复位上升沿，清完成位与故障 [-] Reset edge *)
    fSetC      : REAL;   (* 均热温度设定 [°C] Soaking temperature setpoint *)
    fActC      : REAL;   (* 炉膛实测温度 [°C] Measured furnace temperature *)
    fKp        : REAL;   (* 比例增益 [%/K] Proportional gain *)
    fKi        : REAL;   (* 积分增益 [%/(K·s)] Integral gain *)
    fOutMaxPct : REAL;   (* 加热输出上限 [%] Heater output upper limit *)
    fBandC     : REAL;   (* 均热偏差带半宽 [K] Soaking band half width *)
    tSample    : TIME;   (* PI 采样周期 [ms] PI sampling period *)
    tSoakDur   : TIME;   (* 均热驻留时长 [ms] Soaking dwell time *)
END_VAR
VAR_OUTPUT
    fOutPct    : REAL;   (* 加热输出百分比 [%] Heater output percent *)
    fErrC      : REAL;   (* 当前温度偏差 [K] Current temperature error *)
    bInBand    : BOOL;   (* 偏差带内标志 [-] Within band flag *)
    bSoakDone  : BOOL;   (* 均热完成（锁存） [-] Soaking done latched *)
    bError     : BOOL;   (* 故障锁存标志 [-] Fault latch flag *)
    uErrId     : UDINT;  (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    tonSample: TON;      (* 采样节拍（自复位错峰） / Sampling tick self-reset *)
    tonSoak  : TON;      (* 均热驻留计时（独立实例） / Soaking dwell timer *)
    _fInteg  : REAL;     (* 积分累计量 [%] Integral accumulator *)
    _bDone   : BOOL;     (* 均热完成锁存位（锁存量） / Latched done bit *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    fDt      : REAL;     (* 采样周期秒值 [s] Sampling period in seconds *)
END_VAR
VAR CONSTANT
    DL_EPS     : REAL := 1.0E-9;    (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_MS_PER_S: REAL := 1000.0;    (* 毫秒转秒换算系数 [ms/s] Milliseconds per second *)
    DL_ZERO    : REAL := 0.0;       (* 零常量 [无量纲] Zero constant *)
END_VAR

(* —— 段 1｜每拍量预清零（锁存量 _bDone/_bFault/_uFault/_fInteg 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜非有限拦截与组态闸（覆盖采样周期、偏差带、输出上限、增益） —— *)
IF (fActC <> fActC) OR ((fActC - fActC) <> 0.0)
   OR (fSetC <> fSetC) OR ((fSetC - fSetC) <> 0.0)
   OR (fKp <> fKp) OR ((fKp - fKp) <> 0.0)
   OR (fKi <> fKi) OR ((fKi - fKi) <> 0.0)
   OR (fOutMaxPct <> fOutMaxPct) OR ((fOutMaxPct - fOutMaxPct) <> 0.0)
   OR (fBandC <> fBandC) OR ((fBandC - fBandC) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (fBandC <= DL_EPS) OR (fOutMaxPct <= DL_EPS) OR (fKp < DL_ZERO) OR (fKi < DL_ZERO)
   OR (tSample = T#0S) OR (tSoakDur = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0022_0001;              (* 故障级：组态非法 / Fault code bad config *)
END_IF
IF _bNonFin AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0022_0002;              (* 故障级：温度反馈非有限 / Non-finite temperature *)
END_IF

(* —— 段 3｜偏差与带内判定（本拍值，先于定时器使用） —— *)
fErrC := fSetC - fActC;                   (* 偏差 = 设定 - 实测 [K] *)
IF fErrC < DL_ZERO THEN
    bInBand := (-fErrC) <= fBandC;        (* 负偏差取绝对值比较 [K] / Absolute compare *)
ELSE
    bInBand := fErrC <= fBandC;           (* 正偏差直接比较 [K] / Direct compare *)
END_IF

(* —— 段 4｜沿与定时器每拍无条件刷新（tonSample 自复位错峰，禁靠外部沿清零） —— *)
rtReset  (CLK := bReset);
tonSample(IN := NOT tonSample.Q, PT := tSample);
tonSoak  (IN := bInBand AND bEnable AND (NOT _bFault), PT := tSoakDur);

(* —— 段 5｜复位沿：清完成位、积分与故障（唯一解除路径） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _bDone := FALSE;
    _fInteg := DL_ZERO;
END_IF

(* —— 段 6｜简化 PI：每个采样节拍做一次积分，积分与输出双侧限幅（抗饱和） —— *)
fDt := TIME_TO_REAL(tSample) / DL_MS_PER_S;
IF tonSample.Q THEN
    IF fDt > DL_EPS THEN
        _fInteg := _fInteg + fKi * fErrC * fDt;
    END_IF
    IF _fInteg > fOutMaxPct THEN
        _fInteg := fOutMaxPct;            (* 积分上限限幅 [%] / Integral upper clamp *)
    ELSIF _fInteg < DL_ZERO THEN
        _fInteg := DL_ZERO;               (* 积分下限限幅 [%] / Integral lower clamp *)
    END_IF
END_IF
IF bEnable AND (NOT _bFault) THEN
    fOutPct := fKp * fErrC + _fInteg;
    IF fOutPct > fOutMaxPct THEN
        fOutPct := fOutMaxPct;            (* 输出上限限幅 [%] / Output upper clamp *)
    ELSIF fOutPct < DL_ZERO THEN
        fOutPct := DL_ZERO;               (* 输出下限限幅 [%] / Output lower clamp *)
    END_IF
ELSE
    fOutPct := DL_ZERO;                   (* 非使能：输出归零、积分复位 *)
    _fInteg := DL_ZERO;
    _bDone := FALSE;
END_IF

(* —— 段 7｜均热完成锁存：驻留到置位，只认复位沿或使能撤销 —— *)
IF tonSoak.Q THEN
    _bDone := TRUE;
END_IF

(* —— 段 8｜出口单点映射 —— *)
bSoakDone := _bDone;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                    (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
