(*
  Component : FB_DL_AnodizeRinseCascadeCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 逆流漂洗级联补水控制：按三级液位分级开补水阀，末级叠加电导率补水需求，末级电导超限延时报警。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 高液位须严格高于低液位、电导报警限须 > 1e-9，否则判组态非法并锁存故障；
              ② 任一液位达到高液位即强制关该级补水阀（防溢流），优先级高于电导补水；
              ③ 电导报警为延时确认型，故障锁存唯一解除路径 = bReset 上升沿。
*)
FUNCTION_BLOCK FB_DL_AnodizeRinseCascadeCtrl
VAR_INPUT
    bEnable      : BOOL;                    (* 使能电平 [-] Enable level *)
    bReset       : BOOL;                    (* 复位上升沿，清报警与故障 [-] Reset edge *)
    afLevelPct   : ARRAY[0..2] OF REAL;     (* 三级漂洗槽液位（0 为末级） [%] Rinse tank levels *)
    fCondUs      : REAL;                    (* 末级漂洗槽电导率 [μS/cm] Last stage conductivity *)
    fCondAlarmUs : REAL;                    (* 电导报警限 [μS/cm] Conductivity alarm limit *)
    fLevelLowPct : REAL;                    (* 补水启动液位 [%] Fill start level *)
    fLevelHighPct: REAL;                    (* 补水停止液位 [%] Fill stop level *)
    tCondDelay   : TIME;                    (* 电导报警确认延时 [ms] Alarm confirmation delay *)
END_VAR
VAR_OUTPUT
    abFillValve : ARRAY[0..2] OF BOOL;      (* 三级补水阀指令 [-] Fill valve commands *)
    bCondAlarm  : BOOL;                     (* 末级电导超限报警 [-] Conductivity alarm *)
    bError      : BOOL;                     (* 故障锁存标志 [-] Fault latch flag *)
    uErrId      : UDINT;                    (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    tonCond  : TON;      (* 电导报警确认计时 / Conductivity alarm timer *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    nIdx     : INT;      (* 级遍历下标 [-] Stage loop index *)
    nLast    : INT;      (* 末级下标常量 [-] Last stage index *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_SEG : INT := 2;         (* 级联最高下标（三级） [-] Highest cascade index *)
END_VAR

(* —— 段 1｜每拍量预清零 + 阀门全预置（锁存量 _bFault/_uFault 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
nLast := DL_SEG;
FOR nIdx := 0 TO 2 DO
    IF (nIdx >= 0) AND (nIdx <= 2) THEN
        abFillValve[nIdx] := FALSE;         (* 阀门复位到关闭 [-] / Valve preset closed *)
    END_IF
END_FOR

(* —— 段 2｜非有限拦截：末级电导与三级液位逐个判（自反判 NaN，差值判 Inf） —— *)
IF (fCondUs <> fCondUs) OR ((fCondUs - fCondUs) <> 0.0)
   OR (fCondAlarmUs <> fCondAlarmUs) OR ((fCondAlarmUs - fCondAlarmUs) <> 0.0)
   OR (fLevelLowPct <> fLevelLowPct) OR ((fLevelLowPct - fLevelLowPct) <> 0.0)
   OR (fLevelHighPct <> fLevelHighPct) OR ((fLevelHighPct - fLevelHighPct) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
FOR nIdx := 0 TO 2 DO
    IF (nIdx >= 0) AND (nIdx <= 2) THEN
        IF (afLevelPct[nIdx] <> afLevelPct[nIdx])
           OR ((afLevelPct[nIdx] - afLevelPct[nIdx]) <> 0.0) THEN
            _bNonFin := TRUE;
        END_IF
    END_IF
END_FOR

(* —— 段 3｜组态闸：液位窗口上下界关系 + 电导报警限 —— *)
IF (fLevelHighPct <= fLevelLowPct) OR (fCondAlarmUs <= DL_EPS) OR (tCondDelay = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0023_0001;                (* 故障级：组态非法 / Fault code bad config *)
END_IF
IF _bNonFin AND (NOT _bFault) THEN
    _bFault := TRUE;
    _uFault := 16#0023_0002;                (* 故障级：液位或电导非有限 / Non-finite input *)
END_IF

(* —— 段 4｜定时器每拍无条件刷新（使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
tonCond(IN := bEnable AND (NOT _bFault) AND (fCondUs > fCondAlarmUs), PT := tCondDelay);

(* —— 段 5｜复位沿：一次性清故障锁存（唯一解除路径，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
END_IF

(* —— 段 6｜分级补水：低液位开阀；末级叠加电导超限补水；高液位强制关阀（优先级最高） —— *)
IF bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    FOR nIdx := 0 TO 2 DO
        IF (nIdx >= 0) AND (nIdx <= 2) THEN
            IF afLevelPct[nIdx] < fLevelLowPct THEN
                abFillValve[nIdx] := TRUE;  (* 低液位补水 [-] / Fill on low level *)
            END_IF
        END_IF
    END_FOR
    IF (fCondUs > fCondAlarmUs) AND (afLevelPct[nLast] < fLevelHighPct) THEN
        abFillValve[nLast] := TRUE;         (* 末级电导超限置换补水 [-] / Refresh on high conductivity *)
    END_IF
    FOR nIdx := 0 TO 2 DO
        IF (nIdx >= 0) AND (nIdx <= 2) THEN
            IF afLevelPct[nIdx] >= fLevelHighPct THEN
                abFillValve[nIdx] := FALSE; (* 高液位强制关阀，防溢流 [-] / Force close on high level *)
            END_IF
        END_IF
    END_FOR
END_IF

(* —— 段 7｜出口单点映射 —— *)
bCondAlarm := tonCond.Q AND (NOT _bFault);
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                      (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
