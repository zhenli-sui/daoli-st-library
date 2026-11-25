(*
  Name: FB_DL_LehrZoneTempSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 退火窑分区温度时序给定：斜坡相按设定升温/降温速率把温度给定从当前保持值斜坡推到
           设定值 fSetC，到达后进保温相；保温相保持 fHoldS 后置完成位并停在保持相。
           斜坡步进按「速率 × 扫描周期」逐拍累加：ΔT = 速率[°C/min] × (周期[s]/60)，
           因此必须把扫描周期作为入参并对它做零闸（R21），不许假设固定扫描周期。
        2) 温度给定的起点是本件自身的保持值 _fOutC：完成相保持在 fSetC，再次启动即从 fSetC
           重新斜坡到新设定值，语义自洽；上电首次运行为 0 °C 起始（保持变量默认值）。
        3) 超温保护：斜坡与保温两相内，只要温度给定超过 fOverLimitC 立即进故障相并锁存，
           同时把温度给定回退到超温前的安全值（不超过上限），输出侧不再继续推高。
  边界条件：1) 非有限值闸：设定值、速率、超温上限、扫描周期四路实值入参统一过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即判组态非法并进故障相，
           绝不把 NaN 累加进温度给定（一旦累加，保持值会被永久污染，R19）。
        2) 组态零闸：ABS(fCycleS) > DL_EPS 才允许积分（周期为零则斜坡不推进，且 ΔT 会除零）；
           fRateCmin 必须 > DL_EPS（速率为 0 时永远到不了设定值，属组态错误）；
           fOverLimitC 必须 > fSetC（超温上限低于设定值时保护恒动作，属组态错误）。
        3) 时间零闸：fHoldS <= T#0S 时保温相定时器立即置 Q（等价于跳过保温），
           这是合法组态（调试用），语义在此声明。
        4) 相超时说明：eLztRamp 的超时由「斜坡是否推进」间接体现（速率与周期已闸），
           另设 tonRampOv 兜底防组态导致的永久不达；eLztHold 由 tonHold 定时，无额外超时；
           eLztDone 为稳态持留相（等 xStart 撤令），不设超时。
        5) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相；故障解除路径为
           (NOT xStart) AND 组态恢复，可达。
        6) FB 主体不使用 RETURN，统一单出口（跨平台可移植性）。
  量纲自证：ΔT = (°C/min) × (s / 60 (s/min)) = °C，步进与温度同量纲；
           fOutC = °C + °C = °C；与 fOverLimitC 同为 °C 后方可比较；
           tonXxx 的 PT 均为 [TIME]；本件无跨量纲相加。
  码表 Error codes（本件格 0090_06xx，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0090_0601 故障级：组态非法（周期为零/速率非正/超温上限不高于设定值/非有限）
    16#0090_0602 故障级：超温保护动作（温度给定超过上限）
    16#0090_0603 故障级：斜坡相超时兜底（长时间未到达设定值）
    16#0090_0604 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0090_0605 信息级：斜坡已到达设定值，转入保温

  修订历史 Revision :
    2026-11-25  v1.0.0  R90 首版
*)

TYPE E_DL_LztState :
(
    eLztIdle := 0,    // 待机：等启动上升沿 / Idle, awaiting start edge
    eLztRamp := 10,   // 斜坡：按速率推向设定值 / Ramping toward setpoint
    eLztHold := 20,   // 保温：等保温时长 / Holding for the hold duration
    eLztDone := 30,   // 完成：给定保持，等撤令 / Done, setpoint held until release
    eLztFault:= 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_LehrZoneTempSeq
VAR_INPUT
    xStart      : BOOL;    // 时序启动指令（上升沿有效）[bool] / Sequence start, edge triggered [bool]
    fSetC       : REAL;    // 目标设定温度 [°C] / Target setpoint temperature [°C]
    fRateCmin   : REAL;    // 升温/降温速率 [°C/min] / Ramp rate [°C/min]
    fHoldS      : TIME;    // 保温时长 [TIME] / Hold duration [TIME]
    fOverLimitC : REAL;    // 超温保护上限 [°C] / Over-temperature protection limit [°C]
    fCycleS     : REAL;    // 扫描周期 [s] / Scan cycle time [s]
END_VAR
VAR_OUTPUT
    fOutC       : REAL;    // 温度给定输出 [°C] / Temperature setpoint output [°C]
    xDone       : BOOL;    // 时序完成保持位 [bool] / Sequence complete held flag [bool]
    xBusy       : BOOL;    // 时序进行中 [bool] / Sequence busy flag [bool]
    eState      : E_DL_LztState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId      : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonHold     : TON;     // 保温时长定时器 [TIME] / Hold duration timer
    tonRampOv   : TON;     // 斜坡相超时兜底定时器 [TIME] / Ramp overrun watchdog timer
    rtStart     : R_TRIG;  // 启动上升沿检测 [bool] / Start rising edge detector
    _eState     : E_DL_LztState := E_DL_LztState.eLztIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev : E_DL_LztState := E_DL_LztState.eLztIdle;   // 上一拍相位快照（周期末更新）
    _fOutC      : REAL;    // 温度给定保持值 [°C] / Retained setpoint value [°C]
    _fStepC     : REAL;    // 单拍温度步进量 [°C] / Temperature step per cycle [°C]
    _bCfgBad    : BOOL;    // 组态非法聚合 [bool] / Configuration invalid aggregate [bool]
    _bAtSet     : BOOL;    // 已达设定值（带死区）[bool] / Reached setpoint within deadband [bool]
    _bOverTemp  : BOOL;    // 超温条件成立 [bool] / Over-temperature condition [bool]
    _bBusy      : BOOL;    // 激活相（斜坡/保温）[bool] / Active phase flag [bool]
    _bFault     : BOOL;    // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo      : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault     : UDINT;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;    // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG      : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_S_PER_MIN: REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_DEADBAND : REAL := 0.05;      // 到达设定值的死区 [°C] / Setpoint arrival deadband [°C]
    DL_RAMP_MAX : TIME := T#4H;      // 斜坡相超时兜底上限 [TIME] / Ramp overrun ceiling [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_fOutC/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸（R19：NaN 一旦累加进保持值会永久污染，必须前置拦截） —— *)
_bCfgBad := NOT (fSetC > -DL_BIG AND fSetC < DL_BIG)
            OR NOT (fRateCmin > -DL_BIG AND fRateCmin < DL_BIG)
            OR NOT (fOverLimitC > -DL_BIG AND fOverLimitC < DL_BIG)
            OR NOT (fCycleS > -DL_BIG AND fCycleS < DL_BIG);

(* —— 段 2：组态零闸（R4 / R21：周期与速率两个零闸，另加超温上限的逻辑闸） —— *)
_bCfgBad := _bCfgBad
            OR (ABS(fCycleS) <= DL_EPS)               // 周期为零：积分不推进且步进发散
            OR (fRateCmin <= DL_EPS)                  // 速率为零：永远到不了设定值
            OR (fOverLimitC <= fSetC)                 // 超温上限不高于设定值：保护恒动作
            OR (fRateCmin > DL_BIG);                  // 速率荒谬：拒绝进入运算

(* —— 段 3：步进量与判据量（每拍重算） —— *)
IF _bCfgBad THEN
    _fStepC := 0.0;                               // 组态坏：步进量置 0，保持值不动
ELSE
    _fStepC := fRateCmin * (fCycleS / DL_S_PER_MIN);   // 速率 × 周期 = 单拍步进 [°C]
END_IF
_bAtSet := (NOT _bCfgBad) AND (ABS(fSetC - _fOutC) <= DL_DEADBAND);   // 已达设定值
_bOverTemp := (NOT _bCfgBad) AND (_fOutC > fOverLimitC);              // 超温条件

(* —— 段 4：激活量与定时器无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
_bBusy := (_eState = E_DL_LztState.eLztRamp) OR (_eState = E_DL_LztState.eLztHold);
rtStart(CLK := xStart);                                                  // 启动上升沿，每拍必调
tonHold(IN := (_eState = E_DL_LztState.eLztHold), PT := fHoldS);         // 保温时长
tonRampOv(IN := (_eState = E_DL_LztState.eLztRamp), PT := DL_RAMP_MAX);  // 斜坡超时兜底

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0090_0601;                // 故障级：组态非法
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_LztState.eLztFault;
END_IF
IF _bOverTemp AND _bBusy AND (NOT _bFault) THEN
    _uFault := 16#0090_0602;                // 故障级：超温保护动作
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LztState.eLztFault;
END_IF
IF tonRampOv.Q AND (_eState = E_DL_LztState.eLztRamp) AND (NOT _bFault) THEN
    _uFault := 16#0090_0603;                // 故障级：斜坡相超时兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LztState.eLztFault;
END_IF

(* —— 段 6：相位机与斜坡积分（只做迁移与保持值更新；出口在段 8 单点映射） —— *)
CASE _eState OF

E_DL_LztState.eLztIdle:
    IF NOT xStart THEN
        ;                                   // 等启动，保持值不变 / Waiting, retained value held
    ELSIF rtStart.Q THEN
        _eState := E_DL_LztState.eLztRamp;  // 进斜坡相
    END_IF

E_DL_LztState.eLztRamp:
    IF NOT xStart THEN
        _eState := E_DL_LztState.eLztIdle;  // 撤令：回待机（保持值保留）
    ELSIF _bAtSet THEN
        _uInfo := 16#0090_0605;             // 信息级：已到达设定值
        _eState := E_DL_LztState.eLztHold;  // 进保温相
    ELSE
        IF _fOutC < fSetC THEN
            _fOutC := MIN(fSetC, _fOutC + _fStepC);   // 升温：向上逼近，不越过设定值
        ELSE
            _fOutC := MAX(fSetC, _fOutC - _fStepC);   // 降温：向下逼近，不越过设定值
        END_IF
    END_IF

E_DL_LztState.eLztHold:
    IF NOT xStart THEN
        _eState := E_DL_LztState.eLztIdle;  // 撤令：回待机
    ELSIF tonHold.Q THEN
        _eState := E_DL_LztState.eLztDone;  // 保温结束：进完成相
    END_IF

E_DL_LztState.eLztDone:
    IF _bOverTemp THEN
        ;                                   // 超温由段 5 全局拦截，此处不重复赋值
    ELSIF NOT xStart THEN
        _eState := E_DL_LztState.eLztIdle;  // 撤令：回待机
    END_IF

E_DL_LztState.eLztFault:
    IF (NOT xStart) AND (NOT _bCfgBad) THEN
        _bFault := FALSE;                   // 解除路径：撤令 + 组态恢复（可达）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_LztState.eLztIdle;  // 回待机
    END_IF

ELSE
    _uFault := 16#0090_0604;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LztState.eLztFault;     // 强制回故障相

END_CASE

(* —— 段 7：后置段（R23：保持值安全回退与快照统一放在迁移判断之后） —— *)
IF _fOutC > fOverLimitC THEN
    _fOutC := fOverLimitC;                  // 超温回退：保持值不得高于上限（安全侧）
END_IF
_eStatePrev := _eState;                     // 快照统一在周期末尾更新（R23）

(* —— 段 8：出口单点映射（名实同源；由状态与保持值导出，不在多分支各写一遍） —— *)
fOutC := _fOutC;                                              // 温度给定出口 [°C]
xBusy := _bBusy AND (NOT _bFault);                            // 进行中出口
xDone := (_eState = E_DL_LztState.eLztDone) AND (NOT _bFault); // 完成位出口
eState := _eState;                                            // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
