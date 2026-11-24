(*
  Component : FB_DL_CrystallizerVacuumCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 结晶罐真空控制：ENUM 四态（Off/Run/Lost/Fault），真空泵按压差分级投运，按锤度算沸点升高与罐内沸点，真空丢失延时联锁停泵。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 真空度输入按罐内绝对压力定义 [kPa]：实测值升高即真空丢失，判据方向不得反接；
              ② 沸点升高按 锤度/(100-锤度) 经验式，锤度须 < 100 °Bx 且钳位 0~30 K；
              ③ 真空丢失锁存后全泵切除（防倒吸油返），唯一解除路径 = bReset 上升沿。
*)

TYPE E_DL_VacMode :
(
    eOff   := 0,    (* 停机：使能撤销 / Off, disabled *)
    eRun   := 10,   (* 运行：分级投运 / Running with staged pumps *)
    eLost  := 20,   (* 真空丢失：全泵切除锁存 / Vacuum lost, pumps cut off *)
    eFault := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrystallizerVacuumCtrl
VAR_INPUT
    bEnable     : BOOL;   (* 使能电平 [-] Enable level *)
    bReset      : BOOL;   (* 复位上升沿，清丢失与故障锁存 [-] Reset edge *)
    fVacuumKPa  : REAL;   (* 罐内绝对压力实测 [kPa] Measured absolute pressure *)
    fVacSetKPa  : REAL;   (* 目标绝对压力设定 [kPa] Absolute pressure setpoint *)
    fVacLostKPa : REAL;   (* 真空丢失判据压力 [kPa] Vacuum-lost pressure threshold *)
    fBrixPct    : REAL;   (* 糖膏锤度 [°Bx] Massecuite brix *)
    fWaterBoilC : REAL;   (* 当前真空下纯水沸点 [°C] Water boiling point at this vacuum *)
    tLostDelay  : TIME;   (* 真空丢失确认延时 [ms] Vacuum-lost confirmation delay *)
    nPumpMax    : INT;    (* 可用真空泵台数 1~3 [-] Available pump count *)
END_VAR
VAR_OUTPUT
    abPumpCmd  : ARRAY[0..2] OF BOOL;  (* 三级真空泵指令 [-] Vacuum pump commands *)
    nPumpRun   : INT;                  (* 当前投运泵台数 [-] Running pump count *)
    fBoilRiseK : REAL;                 (* 沸点升高 [K] Boiling point elevation *)
    fBoilTempC : REAL;                 (* 罐内糖膏沸点 [°C] Massecuite boiling point *)
    bVacLost   : BOOL;                 (* 真空丢失锁存标志 [-] Vacuum lost latch *)
    eMode      : E_DL_VacMode;         (* 模式出口，段尾单点映射 [-] Mode outlet *)
    bError     : BOOL;                 (* 故障锁存标志 [-] Fault latch flag *)
    uErrId     : UDINT;                (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    tonLost  : TON;      (* 真空丢失确认计时 / Vacuum lost timer *)
    _eMode   : E_DL_VacMode := E_DL_VacMode.eOff;  (* 内部模式 / Internal mode *)
    _bLost   : BOOL;     (* 真空丢失锁存位（锁存量） / Latched vacuum lost bit *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    nIdx     : INT;      (* 泵组遍历下标 [-] Pump loop index *)
    fErrKPa  : REAL;     (* 压差（实测 - 设定） [kPa] Pressure error *)
    fDenBrix : REAL;     (* 锤度余量（100 - 锤度） [°Bx] Brix headroom *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_BAND1    : REAL := 1.0;      (* 一级投运压差 [kPa] Stage 1 pressure band *)
    DL_BAND2    : REAL := 4.0;      (* 二级投运压差 [kPa] Stage 2 pressure band *)
    DL_BAND3    : REAL := 8.0;      (* 三级投运压差 [kPa] Stage 3 pressure band *)
    DL_RISE_K   : REAL := 2.6;      (* 沸点升高经验系数 [K] Elevation coefficient *)
    DL_RISE_MAX : REAL := 30.0;     (* 沸点升高上限 [K] Elevation upper clamp *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [°Bx 基准] Percent base *)
    DL_IDX_MAX  : INT := 2;         (* 泵组最高下标 [-] Highest pump index *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
tonLost(IN := bEnable AND (fVacuumKPa >= fVacLostKPa) AND (NOT _bLost), PT := tLostDelay);

(* —— 段 1｜每拍量预清零 + 泵指令全预置（锁存量 _bLost/_bFault/_uFault 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
nPumpRun := 0;
FOR nIdx := 0 TO 2 DO
    IF (nIdx >= 0) AND (nIdx <= DL_IDX_MAX) THEN
        abPumpCmd[nIdx] := FALSE;            (* 泵指令预置停止 [-] / Pump preset off *)
    END_IF
END_FOR

(* —— 段 2｜非有限拦截与组态闸（覆盖压力设定/丢失判据/锤度/延时/泵数） —— *)
IF (fVacuumKPa <> fVacuumKPa) OR ((fVacuumKPa - fVacuumKPa) <> 0.0)
   OR (fBrixPct <> fBrixPct) OR ((fBrixPct - fBrixPct) <> 0.0)
   OR (fVacSetKPa <> fVacSetKPa) OR ((fVacSetKPa - fVacSetKPa) <> 0.0)
   OR (fVacLostKPa <> fVacLostKPa) OR ((fVacLostKPa - fVacLostKPa) <> 0.0)
   OR (fWaterBoilC <> fWaterBoilC) OR ((fWaterBoilC - fWaterBoilC) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (fVacSetKPa <= DL_EPS) OR (fVacLostKPa <= fVacSetKPa) OR (tLostDelay = T#0S)
   OR (nPumpMax < 1) OR (nPumpMax > 3) OR (fBrixPct < 0.0) OR (fBrixPct >= DL_PCT_BASE) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 3｜沸点升高与罐内沸点：dT = 2.6·B/(100-B)，钳位 0~30 K —— *)
fDenBrix := DL_PCT_BASE - fBrixPct;
IF fDenBrix > DL_EPS THEN
    fBoilRiseK := DL_RISE_K * fBrixPct / fDenBrix;
ELSE
    fBoilRiseK := DL_RISE_MAX;               (* 锤度近饱和：按上限处理 *)
END_IF
IF fBoilRiseK < 0.0 THEN
    fBoilRiseK := 0.0;
ELSIF fBoilRiseK > DL_RISE_MAX THEN
    fBoilRiseK := DL_RISE_MAX;
END_IF
fBoilTempC := fWaterBoilC + fBoilRiseK;

(* —— 段 4｜复位沿：一次性清丢失与故障锁存（唯一解除路径，恒可达） —— *)
IF rtReset.Q THEN
    _bLost := FALSE;
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eMode := E_DL_VacMode.eOff;
END_IF
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0029_0001;                 (* 故障级：组态非法 / Fault code bad config *)
END_IF
IF _bNonFin AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0029_0002;                 (* 故障级：压力或锤度非有限 / Non-finite input *)
END_IF
IF tonLost.Q AND (NOT _bLost) THEN
    _bLost := TRUE;                          (* 真空丢失锁存：全泵切除防倒吸 *)
END_IF

(* —— 段 5｜模式机：四态全覆盖 + ELSE 兜底 —— *)
CASE _eMode OF
E_DL_VacMode.eOff:
    nPumpRun := 0;
    IF bEnable AND (NOT _bLost) AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _eMode := E_DL_VacMode.eRun;         (* 迁入条件：使能且无任何锁存 *)
    END_IF

E_DL_VacMode.eRun:
    (* 压差分级投运：实测绝对压力高于设定越多，投运泵台数越多 *)
    fErrKPa := fVacuumKPa - fVacSetKPa;
    IF fErrKPa > DL_BAND3 THEN
        nPumpRun := 3;
    ELSIF fErrKPa > DL_BAND2 THEN
        nPumpRun := 2;
    ELSIF fErrKPa > DL_BAND1 THEN
        nPumpRun := 1;
    ELSE
        nPumpRun := 0;
    END_IF
    IF nPumpRun > nPumpMax THEN
        nPumpRun := nPumpMax;                (* 受可用台数限制 [-] / Limited by available pumps *)
    END_IF
    IF _bLost THEN
        _eMode := E_DL_VacMode.eLost;        (* 迁出条件 1：真空丢失 *)
    ELSIF _bFault THEN
        _eMode := E_DL_VacMode.eFault;       (* 迁出条件 2：故障锁存 *)
    ELSIF NOT bEnable THEN
        _eMode := E_DL_VacMode.eOff;         (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_VacMode.eLost:
    nPumpRun := 0;                           (* 丢失相：全泵切除（防倒吸油返） *)
    IF NOT _bLost THEN
        _eMode := E_DL_VacMode.eOff;         (* 迁出条件：锁存被复位沿清除 *)
    END_IF

E_DL_VacMode.eFault:
    nPumpRun := 0;                           (* 故障相：全泵切除 *)
    IF (NOT _bFault) AND (NOT _bLost) THEN
        _eMode := E_DL_VacMode.eOff;         (* 迁出条件：故障锁存被复位沿清除 *)
    END_IF

ELSE
    _bFault := TRUE;                         (* 兜底：非法模式锁存 *)
    _uFault := 16#0029_0009;
    _eMode := E_DL_VacMode.eFault;
END_CASE

(* —— 段 6｜泵指令下发：仅运行相按台数投运，其余相全切除 —— *)
IF _eMode = E_DL_VacMode.eRun THEN
    FOR nIdx := 0 TO 2 DO
        IF (nIdx >= 0) AND (nIdx <= DL_IDX_MAX) THEN
            abPumpCmd[nIdx] := nIdx < nPumpRun;   (* 前 nPumpRun 台投运 [-] / First N pumps on *)
        END_IF
    END_FOR
ELSE
    nPumpRun := 0;
END_IF

(* —— 段 7｜出口单点映射 —— *)
eMode := _eMode;
bVacLost := _bLost;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                       (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
