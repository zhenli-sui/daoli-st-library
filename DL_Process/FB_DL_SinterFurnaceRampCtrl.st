(*
  Component : FB_DL_SinterFurnaceRampCtrl
  Category  : DL_Process
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 烧结炉升温曲线跟踪：ENUM 七态（Idle/Purge/Ramp/Soak/Cool/Done/Fault），斜率限幅给定值输出，露点超限联锁，吹扫/保温/冷却分段计时。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 升温斜率、目标温度、露点上限、各段时长为判据基，须 > 1e-9 或非 0，否则拒启动并锁故障；
              ② 给定值斜率限幅按采样周期积分推进（每个采样节拍最多走 斜率×dt/60），禁阶跃；
              ③ 露点超上限在吹扫/升温/保温三相均联锁，故障锁存唯一解除路径 = bReset 上升沿。
*)

TYPE E_DL_SintPhase :
(
    eIdle  := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    ePurge := 10,   (* 吹扫：露点置换 / Atmosphere purge *)
    eRamp  := 20,   (* 升温：斜率限幅跟踪 / Ramp with slope limit *)
    eSoak  := 30,   (* 保温：目标温度保持 / Soak at target *)
    eCool  := 40,   (* 冷却：斜率限幅下降 / Controlled cooling *)
    eDone  := 50,   (* 完成：曲线结束 / Curve finished *)
    eFault := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SinterFurnaceRampCtrl
VAR_INPUT
    bEnable    : BOOL;   (* 使能电平 [-] Enable level *)
    bReset     : BOOL;   (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart     : BOOL;   (* 启动上升沿 [-] Start edge *)
    fActC      : REAL;   (* 炉膛实测温度 [°C] Measured furnace temperature *)
    fTargetC   : REAL;   (* 目标保温温度 [°C] Target soaking temperature *)
    fCoolToC   : REAL;   (* 冷却终点温度 [°C] Cooling end temperature *)
    fRampCmin  : REAL;   (* 允许升温/降温斜率 [°C/min] Allowed ramp rate *)
    fDewPointC : REAL;   (* 炉内实测露点 [°C] Measured dew point *)
    fDewMaxC   : REAL;   (* 露点允许上限 [°C] Dew point upper limit *)
    tPurge     : TIME;   (* 吹扫驻留 [ms] Purge dwell *)
    tSoak      : TIME;   (* 保温驻留 [ms] Soak dwell *)
    tCool      : TIME;   (* 冷却超时保护 [ms] Cooling timeout *)
    tSample    : TIME;   (* 斜率积分采样周期 [ms] Ramp integration period *)
END_VAR
VAR_OUTPUT
    fSetOutC : REAL;              (* 温度给定值输出 [°C] Temperature setpoint output *)
    bHeatOn  : BOOL;              (* 加热使能输出 [-] Heater enable output *)
    ePhase   : E_DL_SintPhase;    (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError   : BOOL;              (* 故障锁存标志 [-] Fault latch flag *)
    uErrId   : UDINT;             (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart  : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonPurge : TON;      (* 吹扫驻留计时（独立实例） / Purge timer *)
    tonSoak  : TON;      (* 保温驻留计时（独立实例） / Soak timer *)
    tonCool  : TON;      (* 冷却计时（独立实例） / Cooling timer *)
    tonSample: TON;      (* 采样节拍（自复位错峰） / Sampling tick self-reset *)
    _ePhase  : E_DL_SintPhase := E_DL_SintPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    fDt      : REAL;     (* 采样周期秒值 [s] Sampling period in seconds *)
    fStepK   : REAL;     (* 单拍允许最大温度变化量 [K] Max temperature step per tick *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_MS_PER_S : REAL := 1000.0;   (* 毫秒转秒换算系数 [ms/s] Milliseconds per second *)
    DL_S_PER_MIN: REAL := 60.0;     (* 分钟转秒换算系数 [s/min] Seconds per minute *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonPurge (IN := (_ePhase = E_DL_SintPhase.ePurge) AND (NOT _bFault), PT := tPurge);
tonSoak  (IN := (_ePhase = E_DL_SintPhase.eSoak)  AND (NOT _bFault), PT := tSoak);
tonCool  (IN := (_ePhase = E_DL_SintPhase.eCool)  AND (NOT _bFault), PT := tCool);
tonSample(IN := NOT tonSample.Q, PT := tSample);

(* —— 段 1｜每拍量预清零（锁存量 _bFault/_uFault/fSetOutC 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
bHeatOn := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，给定值跟随实测，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    fSetOutC := fActC;
    _ePhase := E_DL_SintPhase.eIdle;
END_IF

(* —— 段 3｜非有限拦截与组态闸（覆盖斜率/目标/露点/各段时长） —— *)
IF (fActC <> fActC) OR ((fActC - fActC) <> 0.0)
   OR (fTargetC <> fTargetC) OR ((fTargetC - fTargetC) <> 0.0)
   OR (fDewPointC <> fDewPointC) OR ((fDewPointC - fDewPointC) <> 0.0)
   OR (fRampCmin <> fRampCmin) OR ((fRampCmin - fRampCmin) <> 0.0)
   OR (fCoolToC <> fCoolToC) OR ((fCoolToC - fCoolToC) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (fRampCmin <= DL_EPS) OR (fDewMaxC = DL_ZERO) OR (tPurge = T#0S)
   OR (tSoak = T#0S) OR (tCool = T#0S) OR (tSample = T#0S) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 4｜斜率限幅单拍步长：每个采样节拍最多走 斜率 × dt / 60 —— *)
fDt := TIME_TO_REAL(tSample) / DL_MS_PER_S;
fStepK := fRampCmin * fDt / DL_S_PER_MIN;

(* —— 段 5｜主状态机：七态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_SintPhase.eIdle:
    fSetOutC := fActC;                       (* 空闲：给定跟随实测，无加热 *)
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _ePhase := E_DL_SintPhase.ePurge;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                     (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0027_0001;
        _ePhase := E_DL_SintPhase.eFault;
    END_IF

E_DL_SintPhase.ePurge:
    fSetOutC := fActC;                       (* 吹扫相不升温 *)
    IF (_bNonFin) OR (fDewPointC > fDewMaxC) THEN
        _bFault := TRUE; _uFault := 16#0027_0002;   (* 故障级：露点超限/输入非有限 *)
        _ePhase := E_DL_SintPhase.eFault;
    ELSIF tonPurge.Q THEN
        _ePhase := E_DL_SintPhase.eRamp;            (* 迁出条件 1：吹扫驻留完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SintPhase.eIdle;            (* 迁出条件 2：使能撤销回安全态 *)
    END_IF

E_DL_SintPhase.eRamp:
    bHeatOn := TRUE;
    (* 给定值按单拍步长向目标推进，禁阶跃（斜率限幅） *)
    IF tonSample.Q THEN
        IF (fTargetC - fSetOutC) > fStepK THEN
            fSetOutC := fSetOutC + fStepK;
        ELSIF (fSetOutC - fTargetC) > fStepK THEN
            fSetOutC := fSetOutC - fStepK;
        ELSE
            fSetOutC := fTargetC;
        END_IF
    END_IF
    IF (_bNonFin) OR (fDewPointC > fDewMaxC) THEN
        _bFault := TRUE; _uFault := 16#0027_0002;   (* 故障级：露点超限/输入非有限 *)
        _ePhase := E_DL_SintPhase.eFault;
    ELSIF (fTargetC - fSetOutC) <= (fStepK + DL_EPS) THEN
        _ePhase := E_DL_SintPhase.eSoak;            (* 迁出条件 1：到达保温温度 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SintPhase.eIdle;            (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SintPhase.eSoak:
    bHeatOn := TRUE;
    fSetOutC := fTargetC;                    (* 保温相给定恒为目标温度 *)
    IF (_bNonFin) OR (fDewPointC > fDewMaxC) THEN
        _bFault := TRUE; _uFault := 16#0027_0002;   (* 故障级：露点超限/输入非有限 *)
        _ePhase := E_DL_SintPhase.eFault;
    ELSIF tonSoak.Q THEN
        _ePhase := E_DL_SintPhase.eCool;            (* 迁出条件 1：保温驻留完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SintPhase.eIdle;            (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SintPhase.eCool:
    (* 冷却相给定按单拍步长下降，加热输出撤销 *)
    IF tonSample.Q THEN
        IF (fSetOutC - fCoolToC) > fStepK THEN
            fSetOutC := fSetOutC - fStepK;
        ELSE
            fSetOutC := fCoolToC;
        END_IF
    END_IF
    IF tonCool.Q THEN
        _bFault := TRUE; _uFault := 16#0027_0003;   (* 故障级：冷却超时 *)
        _ePhase := E_DL_SintPhase.eFault;
    ELSIF fSetOutC <= (fCoolToC + DL_EPS) THEN
        _ePhase := E_DL_SintPhase.eDone;            (* 迁出条件 1：达冷却终点 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SintPhase.eIdle;            (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SintPhase.eDone:
    bHeatOn := FALSE;
    IF NOT bStart THEN
        _ePhase := E_DL_SintPhase.eIdle;            (* 启动撤销：回空闲 *)
    END_IF

E_DL_SintPhase.eFault:
    bHeatOn := FALSE;                        (* 故障相：加热输出安全侧撤销 *)

ELSE
    _bFault := TRUE;                         (* 兜底：非法相位锁存 *)
    _uFault := 16#0027_0009;
    _ePhase := E_DL_SintPhase.eFault;
END_CASE

(* —— 段 6｜相位与故障码出口单点映射 —— *)
ePhase := _ePhase;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                       (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
