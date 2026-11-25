(*
  Component : FB_DL_InductionHardeningScanCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 感应淬火扫描时序控制：ENUM 七态状态机（Idle/Heat/Scan/Spray/Cool/Done/Fault），扫描功率随速度联动，喷淋延时后转冷却。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 扫描速度设定/参考速度/终点行程为除子或比例基，须 > 1e-9，否则拒启动并锁存故障码；
              ② 功率按速度比线性联动并钳位 0~100 %，速度越界不下发超限功率；
              ③ 故障锁存唯一解除路径 = bReset 上升沿；eDone 撤销 bStart 回 eIdle。
*)

TYPE E_DL_IhScanPhase :
(
    eIdle  := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    eHeat  := 10,   (* 预热：定时加热 / Pre-heating by timer *)
    eScan  := 20,   (* 扫描：速度功率联动 / Scanning with speed-power link *)
    eSpray := 30,   (* 喷淋：延时后开喷 / Spray after delay *)
    eCool  := 40,   (* 冷却：驻留冷却 / Cooling dwell *)
    eDone  := 50,   (* 完成：结论驻留 / Done, result held *)
    eFault := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_InductionHardeningScanCtrl
VAR_INPUT
    bEnable         : BOOL;   (* 使能电平 [-] Enable level *)
    bReset          : BOOL;   (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart          : BOOL;   (* 启动上升沿 [-] Start edge *)
    fScanPosMm      : REAL;   (* 感应器实际位置 [mm] Inductor actual position *)
    fScanEndMm      : REAL;   (* 扫描终点行程 [mm] Scan end stroke *)
    fScanSpeedSetMmS: REAL;   (* 扫描速度设定 [mm/s] Scan speed setpoint *)
    fSpeedRefMmS    : REAL;   (* 功率联动参考速度 [mm/s] Speed reference for power link *)
    fPowerSetPct    : REAL;   (* 额定功率设定 [%] Rated power setpoint *)
    tHeatDur        : TIME;   (* 预热驻留 [ms] Pre-heat dwell *)
    tSprayDelay     : TIME;   (* 喷淋开启延时 [ms] Spray on delay *)
    tCoolDur        : TIME;   (* 冷却驻留 [ms] Cooling dwell *)
END_VAR
VAR_OUTPUT
    bHeatOn      : BOOL;             (* 加热输出 [-] Heating output *)
    bScanRun     : BOOL;             (* 扫描运行输出 [-] Scan run output *)
    bSprayOn     : BOOL;             (* 喷淋输出 [-] Spray output *)
    fPowerOutPct : REAL;             (* 功率输出（速度联动后） [%] Power output after link *)
    fSpeedOutMmS : REAL;             (* 速度输出 [mm/s] Speed output *)
    ePhase       : E_DL_IhScanPhase; (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError       : BOOL;             (* 故障锁存标志 [-] Fault latch flag *)
    uErrId       : UDINT;            (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset   : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart   : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonHeat   : TON;      (* 预热驻留计时（独立实例） / Pre-heat timer *)
    tonSpray  : TON;      (* 喷淋延时计时（独立实例） / Spray delay timer *)
    tonCool   : TON;      (* 冷却驻留计时（独立实例） / Cooling timer *)
    _ePhase   : E_DL_IhScanPhase := E_DL_IhScanPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault   : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault   : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad  : BOOL;     (* 组态非法当拍量 [-] / Config illegal flag *)
    _bNonFin  : BOOL;     (* 输入非有限当拍量 [-] / Non-finite input flag *)
END_VAR
VAR CONSTANT
    DL_EPS     : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_MAX : REAL := 100.0;    (* 功率百分比上限 [%] Power percent upper bound *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonHeat (IN := (_ePhase = E_DL_IhScanPhase.eHeat) AND (NOT _bFault), PT := tHeatDur);
tonSpray(IN := (_ePhase = E_DL_IhScanPhase.eSpray) AND (NOT _bFault), PT := tSprayDelay);
tonCool (IN := (_ePhase = E_DL_IhScanPhase.eCool) AND (NOT _bFault), PT := tCoolDur);

(* —— 段 1｜每拍量预清零（锁存量 _bFault/_uFault 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，输出撤销 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _ePhase := E_DL_IhScanPhase.eIdle;
END_IF

(* —— 段 3｜组态闸：覆盖全部参与判据换算的引脚（速度/终点/功率/时长） —— *)
IF (fScanSpeedSetMmS <= DL_EPS) OR (fSpeedRefMmS <= DL_EPS)
   OR (fScanEndMm <= DL_EPS) OR (fPowerSetPct <= 0.0)
   OR (tHeatDur = T#0S) OR (tCoolDur = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fScanPosMm <> fScanPosMm) OR ((fScanPosMm - fScanPosMm) <> 0.0)
   OR (fPowerSetPct <> fPowerSetPct) OR ((fPowerSetPct - fPowerSetPct) <> 0.0)
   OR (fScanSpeedSetMmS <> fScanSpeedSetMmS) OR ((fScanSpeedSetMmS - fScanSpeedSetMmS) <> 0.0)
   OR (fSpeedRefMmS <> fSpeedRefMmS) OR ((fSpeedRefMmS - fSpeedRefMmS) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：七态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_IhScanPhase.eIdle:
    bHeatOn := FALSE; bScanRun := FALSE; bSprayOn := FALSE;
    fPowerOutPct := 0.0; fSpeedOutMmS := 0.0;
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _ePhase := E_DL_IhScanPhase.eHeat;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0020_0001;         (* 故障级：组态非法 / Fault code bad config *)
        _ePhase := E_DL_IhScanPhase.eFault;
    END_IF

E_DL_IhScanPhase.eHeat:
    bHeatOn := TRUE; bScanRun := FALSE; bSprayOn := FALSE;
    fSpeedOutMmS := 0.0;
    IF _bNonFin THEN
        _bFault := TRUE; _uFault := 16#0020_0002;   (* 故障级：输入非有限 / Non-finite *)
        _ePhase := E_DL_IhScanPhase.eFault;
    ELSIF tonHeat.Q THEN
        _ePhase := E_DL_IhScanPhase.eScan;          (* 迁出条件 1：预热驻留完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_IhScanPhase.eIdle;          (* 迁出条件 2：使能撤销回安全态 *)
    END_IF

E_DL_IhScanPhase.eScan:
    bHeatOn := TRUE; bScanRun := TRUE; bSprayOn := FALSE;
    fSpeedOutMmS := fScanSpeedSetMmS;               (* 速度输出 = 设定值 [mm/s] *)
    (* 功率-速度联动：功率 = 额定功率 × 实际速度/参考速度，超限钳位 *)
    fPowerOutPct := fPowerSetPct * (fScanSpeedSetMmS / fSpeedRefMmS);
    IF fPowerOutPct > DL_PCT_MAX THEN
        fPowerOutPct := DL_PCT_MAX;                 (* 功率上限钳位 [%] / Power clamp *)
    ELSIF fPowerOutPct < 0.0 THEN
        fPowerOutPct := 0.0;                        (* 功率下限钳位 [%] / Power floor *)
    END_IF
    IF _bNonFin THEN
        _bFault := TRUE; _uFault := 16#0020_0002;   (* 故障级：输入非有限 / Non-finite *)
        _ePhase := E_DL_IhScanPhase.eFault;
    ELSIF fScanPosMm >= fScanEndMm THEN
        _ePhase := E_DL_IhScanPhase.eSpray;         (* 迁出条件 1：扫描终点达成 *)
    ELSIF fScanPosMm < 0.0 THEN
        _bFault := TRUE; _uFault := 16#0020_0003;   (* 故障级：位置反馈越界 / Position out of range *)
        _ePhase := E_DL_IhScanPhase.eFault;         (* 迁出条件 2（故障路） *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_IhScanPhase.eIdle;          (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_IhScanPhase.eSpray:
    bHeatOn := FALSE; bScanRun := FALSE;
    fSpeedOutMmS := 0.0; fPowerOutPct := 0.0;
    bSprayOn := tonSpray.Q;                         (* 延时到才开喷 / Spray after delay *)
    IF tonSpray.Q THEN
        _ePhase := E_DL_IhScanPhase.eCool;          (* 迁出条件 1：喷淋延时完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_IhScanPhase.eIdle;          (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_IhScanPhase.eCool:
    bHeatOn := FALSE; bScanRun := FALSE; bSprayOn := TRUE;
    fSpeedOutMmS := 0.0; fPowerOutPct := 0.0;
    IF tonCool.Q THEN
        _ePhase := E_DL_IhScanPhase.eDone;          (* 迁出条件 1：冷却驻留完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_IhScanPhase.eIdle;          (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_IhScanPhase.eDone:
    bHeatOn := FALSE; bScanRun := FALSE; bSprayOn := FALSE;
    fSpeedOutMmS := 0.0; fPowerOutPct := 0.0;
    IF NOT bStart THEN
        _ePhase := E_DL_IhScanPhase.eIdle;          (* 启动指令撤销：回空闲 *)
    END_IF

E_DL_IhScanPhase.eFault:
    bHeatOn := FALSE; bScanRun := FALSE; bSprayOn := FALSE;
    fSpeedOutMmS := 0.0; fPowerOutPct := 0.0;       (* 故障相：全部输出走安全侧 *)

ELSE
    _bFault := TRUE;                                (* 兜底：非法相位锁存 *)
    _uFault := 16#0020_0009;
    _ePhase := E_DL_IhScanPhase.eFault;
END_CASE

(* —— 段 5｜相位与故障码出口单点映射 —— *)
ePhase := _ePhase;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                              (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
