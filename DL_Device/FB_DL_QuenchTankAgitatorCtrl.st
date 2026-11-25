(*
  Component : FB_DL_QuenchTankAgitatorCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 淬火槽搅拌器分级投运控制：按油温分三级递增投运，超温持续超时联锁停泵并锁存，R_TRIG 捕捉升入二级的上升沿上报信息码。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 三级温度阈值必须严格递增且低于联锁温度，否则判组态非法并锁存故障；
              ② 超温联锁为持续型判据（延时确认），复位后若温度仍超限将立即重新锁存；
              ③ 泵输出为互锁递进：N 级投运时前 N 台全部运行，高液位/超温时全部切除。
*)
FUNCTION_BLOCK FB_DL_QuenchTankAgitatorCtrl
VAR_INPUT
    bEnable    : BOOL;   (* 使能电平 [-] Enable level *)
    bReset     : BOOL;   (* 复位上升沿，清联锁锁存 [-] Reset edge *)
    fOilTempC  : REAL;   (* 油槽实测油温 [°C] Measured oil temperature *)
    fStage1C   : REAL;   (* 一级投运温度 [°C] Stage 1 start temperature *)
    fStage2C   : REAL;   (* 二级投运温度 [°C] Stage 2 start temperature *)
    fStage3C   : REAL;   (* 三级投运温度 [°C] Stage 3 start temperature *)
    fTripC     : REAL;   (* 超温联锁温度 [°C] Over-temperature trip limit *)
    tTripDelay : TIME;   (* 超温确认延时 [ms] Trip confirmation delay *)
END_VAR
VAR_OUTPUT
    bPump1  : BOOL;    (* 一级搅拌泵输出 [-] Agitator pump 1 output *)
    bPump2  : BOOL;    (* 二级搅拌泵输出 [-] Agitator pump 2 output *)
    bPump3  : BOOL;    (* 三级搅拌泵输出 [-] Agitator pump 3 output *)
    nStage  : INT;     (* 当前投运级数 0~3 [-] Active stage count *)
    bTrip   : BOOL;    (* 超温联锁锁存标志 [-] Trip latch flag *)
    bError  : BOOL;    (* 故障锁存标志 [-] Fault latch flag *)
    uErrId  : UDINT;   (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset    : R_TRIG;  (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStage2   : R_TRIG;  (* 升入二级上升沿实例 / Stage-2 rising edge *)
    tonTrip    : TON;     (* 超温确认计时（独立实例） / Trip confirmation timer *)
    _bTrip     : BOOL;    (* 联锁锁存位（锁存量） / Latched trip bit *)
    _bFault    : BOOL;    (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault    : UDINT;   (* 故障码锁存（锁存量） / Latched fault code *)
    _bS2Rise   : BOOL;    (* 二级上升沿单拍位 [-] Stage-2 rise one-shot *)
    _bCfgBad   : BOOL;    (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin   : BOOL;    (* 输入非有限当拍量 [-] Non-finite input flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;   (* 浮点比较容差 [无量纲] Float compare tolerance *)
END_VAR

(* —— 段 1｜每拍量预清零（锁存量 _bTrip/_bFault/_uFault 不入清单） —— *)
uErrId := 16#0000_0000;
_bS2Rise := FALSE;
_bCfgBad := FALSE;
_bNonFin := FALSE;
nStage := 0;

(* —— 段 2｜输入非有限拦截 —— *)
IF (fOilTempC <> fOilTempC) OR ((fOilTempC - fOilTempC) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 3｜组态闸：三级阈值严格递增且低于联锁温度，全部参与判据的引脚逐个覆盖 —— *)
IF (fStage1C >= fStage2C) OR (fStage2C >= fStage3C) OR (fStage3C >= fTripC) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 4｜温度分级判定（无 NaN 时执行；分组阶梯，不插值） —— *)
IF (NOT _bNonFin) AND (NOT _bCfgBad) THEN
    IF fOilTempC > (fStage3C + DL_EPS) THEN
        nStage := 3;                     (* 三级投运 [-] / Stage 3 *)
    ELSIF fOilTempC > (fStage2C + DL_EPS) THEN
        nStage := 2;                     (* 二级投运 [-] / Stage 2 *)
    ELSIF fOilTempC > (fStage1C + DL_EPS) THEN
        nStage := 1;                     (* 一级投运 [-] / Stage 1 *)
    ELSE
        nStage := 0;                     (* 全部停运 [-] / All stopped *)
    END_IF
END_IF

(* —— 段 5｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset (CLK := bReset);
rtStage2(CLK := (nStage >= 2));
tonTrip (IN := _bNonFin OR ((fOilTempC >= fTripC) AND bEnable), PT := tTripDelay);

IF rtStage2.Q THEN
    _bS2Rise := TRUE;                    (* 升入二级上升沿捕获，出口单拍映射 *)
END_IF

(* —— 段 6｜复位沿：联锁与故障一次性清干净（唯一解除路径，恒可达） —— *)
IF rtReset.Q THEN
    _bTrip := FALSE;
    _bFault := FALSE;
    _uFault := 16#0000_0000;
END_IF

(* —— 段 7｜超温联锁：延时确认后锁存，锁存量不当拍按输入重算 —— *)
IF (NOT _bTrip) AND tonTrip.Q THEN
    _bTrip := TRUE;
END_IF
IF (NOT _bFault) AND _bCfgBad THEN
    _bFault := TRUE;
    _uFault := 16#0021_0001;             (* 故障级：温度阈值组态非法 / Bad threshold config *)
END_IF
IF (NOT _bFault) AND _bNonFin THEN
    _bFault := TRUE;
    _uFault := 16#0021_0002;             (* 故障级：油温反馈非有限 / Non-finite temperature *)
END_IF

(* —— 段 8｜输出侧：使能、联锁、故障三者全通过才允许投运 —— *)
IF bEnable AND (NOT _bTrip) AND (NOT _bFault) THEN
    bPump1 := nStage >= 1;               (* 一级泵 [-] / Pump 1 *)
    bPump2 := nStage >= 2;               (* 二级泵 [-] / Pump 2 *)
    bPump3 := nStage >= 3;               (* 三级泵 [-] / Pump 3 *)
ELSE
    bPump1 := FALSE;                     (* 安全侧切除 [-] / Cut off to safe side *)
    bPump2 := FALSE;
    bPump3 := FALSE;
END_IF

(* —— 段 9｜出口单点映射（锁存码回放 + 信息码单拍） —— *)
bTrip := _bTrip;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                   (* 故障码锁存回放 / Latched fault replay *)
ELSIF _bS2Rise THEN
    uErrId := 16#0021_0101;              (* 信息级：升入二级搅拌投运沿 / Stage-2 rise info *)
END_IF
END_FUNCTION_BLOCK
