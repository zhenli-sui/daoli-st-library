(*
  道莅工业代码库 | DL_Process | FB_DL_PaintBoothAirBalance
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；行业池·涂装送排风平衡通用语义，零代码行复制）
  功能: 喷漆房送排风平衡控制——排风速度按压差带 trim 积分调节，送风速度恒基准；
        压差越带超延时进失衡降级（bDegrade），消防联动切排烟模式（送风最小/排风最大），
        压差传感器非有限故障锁存。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG，零厂商私有库
  接口: 输入送/排风实测流量、房间压差、压差设定与带宽、trim 增益与周期、
        风机速度限幅、消防联动、复位；输出 rSupSp/rExhSp [%]、fBalRatio、
        bBalanceOk/bDegrade/bSmokeMode/eState/eCause/bError/nErrId。
  码表: 16#0005_03B8 故障级：压差传感器非有限（NaN/Inf，锁存至复位沿）
        16#0005_04DB 信息级：失衡降级进入（压差越带持续 tDpBadDelay）
        码段说明：0005 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① trim 方向：err = fDpAct - fDpSp > 0（房间偏正压）→ 减排风；
        ② 降级相退出条件 ≥ 2 条：压差回带（前置消失）或使能撤（事件），再入
        eRun 前经 tonDpBad 重新去抖（R240 eWait 相退出双条件口径）；
        ③ 排烟模式优先级最高，压过 trim 与降级（安全侧不可被闸掉）；
        ④ 流量比除法前判送风流量 > EPS，否则出口钳零；
        ⑤ TON/R_TRIG 段 0 无条件周期刷新；⑥ 故障解除唯一路径 = 复位沿 ∧ 组态合法；
        ⑦ 零全局耦合。
  邻件比对: CleanRoomPressure / RoomCo2DemandVent（房间压差恒值控制 / CO2 需求通风，
            与本件涂装双风机平衡+排烟联锁域不同）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B1 · C05）
*)

TYPE E_DL_PbaState :
(
    eIdle    := 0,   // 待机（风机速度保持下限） | Idle, fans at minimum
    eRun     := 10,  // 平衡运行 | Balanced run
    eDegrade := 20,  // 失衡降级（压差越带超延时） | Degrade, dp out of band
    eSmoke   := 30,  // 排烟模式（消防联动） | Smoke extraction mode
    eFault   := 90   // 故障锁存相 | Fault latch phase
);
END_TYPE

TYPE E_DL_PbaCause :
(
    eNone          := 0,  // 无故障 | No cause
    eCfgIllegal    := 1,  // 组态非法 | Illegal configuration
    eSensorNonFinite := 2 // 压差传感器非有限 | Dp sensor non-finite
);
END_TYPE

FUNCTION_BLOCK FB_DL_PaintBoothAirBalance
VAR_INPUT
    bAutoEn     : BOOL := FALSE;    // 自动平衡使能 [-] | Auto balance enable
    fSupFlowAct : REAL := 0.0;      // 送风实测流量 [m3/h] | Supply flow actual
    fExhFlowAct : REAL := 0.0;      // 排风实测流量 [m3/h] | Exhaust flow actual
    fDpAct      : REAL := 0.0;      // 房间压差实测（负=负压）[Pa] | Room dp actual, negative = negative pressure
    fDpSp       : REAL := -25.0;    // 压差设定 [Pa] | Dp setpoint
    fDpBand     : REAL := 5.0;      // 压差半带宽，域 > 0 [Pa] | Dp half band
    fSupSpBase  : REAL := 60.0;     // 送风机速度基准 [%] | Supply fan speed base
    fTrimGain   : REAL := 2.0;      // 排风 trim 增益，域 > 0 [%/(Pa·s)] | Exhaust trim gain
    fDtSec      : REAL := 0.1;      // 调节周期，域 (0, 1] [s] | Trim cycle time
    fFanSpMin   : REAL := 20.0;     // 风机速度下限，域 >= 0 [%] | Fan speed lower limit
    fFanSpMax   : REAL := 90.0;     // 风机速度上限，域 > 下限 [%] | Fan speed upper limit
    bFireAlarm  : BOOL := FALSE;    // 消防联动（电平，排烟）[-] | Fire alarm level
    tDpBadDelay : TIME := T#5S;     // 失衡确认延时，域 > T#0S | Dp out-of-band confirm delay
    bReset      : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    rSupSp     : REAL;              // 送风机速度设定 [%] | Supply fan speed setpoint
    rExhSp     : REAL;              // 排风机速度设定 [%] | Exhaust fan speed setpoint
    fBalRatio  : REAL;              // 排/送流量比（送风流量钳零时出口 0）[-] | Exhaust/supply flow ratio, 0 when supply flow zero
    bBalanceOk : BOOL;              // 压差带内 [-] | Dp within band
    bDegrade   : BOOL;              // 失衡降级态 [-] | Degrade state
    bSmokeMode : BOOL;              // 排烟模式态 [-] | Smoke mode state
    eState     : E_DL_PbaState;     // 状态出口 | State outlet
    eCause     : E_DL_PbaCause;     // 故障成因出口 | Fault cause outlet
    bError     : BOOL;              // 故障锁存标志 [-] | Fault latch flag
    nErrId     : UDINT;             // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState   : E_DL_PbaState := E_DL_PbaState.eIdle;   // 内部状态（CASE 唯一写入目标） | Internal state
    _eCause   : E_DL_PbaCause := E_DL_PbaCause.eNone;   // 成因锁存 | Latched cause
    _bFault   : BOOL;             // 故障锁存位 | Fault latch bit
    _rSupSp   : REAL := 0.0;      // 送风速度给定内部镜像 [%] | Supply speed internal mirror
    _rExhSp   : REAL := 0.0;      // 排风速度给定内部镜像 [%] | Exhaust speed internal mirror
    _bCfgBad  : BOOL;           // 组态非法当拍量 [-] | Illegal configuration
    _bSensBad : BOOL;           // 压差传感器非有限当拍量 [-] | Dp sensor non-finite this scan
    _bDpOut   : BOOL;           // 压差越带当拍量 [-] | Dp outside band this scan
    _uInfo    : UDINT;          // 信息码每拍重算 | Info code per scan
    rtReset   : R_TRIG;         // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonDpBad  : TON;            // 失衡确认计时，段 0 无条件刷新 | Dp out-of-band confirm timer
END_VAR
VAR CONSTANT
    DL_PBA_EPS : REAL := 1.0E-6;    // 流量比除零判据下限 [m3/h] | Flow ratio zero-guard threshold
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bSensBad := (fDpAct <> fDpAct);                                            // 压差传感器 NaN 自反判 / Dp sensor NaN self-reflex check
_bCfgBad := (fDpBand <= 0.0) OR (fTrimGain <= 0.0) OR (fDtSec <= 0.0) OR (fDtSec > 1.0)
         OR (fFanSpMin < 0.0) OR (fFanSpMax <= fFanSpMin)
         OR (fSupSpBase < fFanSpMin) OR (fSupSpBase > fFanSpMax);           // 组态域闸 / Configuration gate
_bDpOut := (NOT _bSensBad) AND (ABS(fDpAct - fDpSp) > fDpBand);             // 越带判据（NaN 不判越带） / Out-of-band judgement
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
tonDpBad(IN := (_eState = E_DL_PbaState.eRun) AND _bDpOut, PT := tDpBadDelay); // 越带去抖 IN 挂运行 ∧ 越带 / Debounce gated by run and out-of-band

(* —— 段 1：单拍量预清零 —— *)
_uInfo := 16#0000_0000;                                                     // 信息码每拍重算 / Info recomputed per scan

(* —— 段 2：复位沿 + 组态/传感器域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN                                        // 复位沿且组态合法 / Reset with legal config
    _bFault := FALSE;                                                       // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_PbaCause.eNone;                                         // 清成因 / Clear cause
    IF _eState = E_DL_PbaState.eFault THEN
        _eState := E_DL_PbaState.eIdle;                                     // 故障相迁出唯一路径 / Sole fault exit
    END_IF
END_IF
IF _bCfgBad THEN                                                            // 组态域闸 / Configuration gate
    _bFault := TRUE;
    _eCause := E_DL_PbaCause.eCfgIllegal;                                   // 归因组态 / Cause: config
END_IF
IF _bSensBad AND (NOT _bFault) THEN                                         // 传感器域闸（组态闸优先归因） / Sensor gate
    _bFault := TRUE;
    _eCause := E_DL_PbaCause.eSensorNonFinite;                              // 归因传感器 / Cause: sensor
END_IF

(* —— 段 3：排烟优先拦截（安全侧优先级最高） —— *)
IF (NOT _bFault) AND bFireAlarm THEN
    IF _eState <> E_DL_PbaState.eSmoke THEN
        _eState := E_DL_PbaState.eSmoke;                                    // 消防联动即切排烟 / Fire alarm switches to smoke mode
    END_IF
END_IF

(* —— 段 4：状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_PbaState.eIdle:
    _rSupSp := fFanSpMin;                                                   // 待机送风保下限 / Idle supply at minimum
    _rExhSp := fFanSpMin;                                                   // 待机排风保下限 / Idle exhaust at minimum
    IF bAutoEn AND (NOT _bFault) AND (NOT bFireAlarm) THEN
        _rSupSp := fSupSpBase;                                              // 使能进入运行，送风回基准 / Enabled, supply to base
        _rExhSp := fFanSpMin;                                               // 排风从下限起 trim / Exhaust trims up from minimum
        _eState := E_DL_PbaState.eRun;
    END_IF

E_DL_PbaState.eRun:
    _rSupSp := fSupSpBase;                                                  // 送风恒基准 / Supply held at base
    IF _bDpOut THEN
        _rExhSp := _rExhSp - fTrimGain * (fDpAct - fDpSp) * fDtSec;         // 偏正压减排风、偏负压增排风 / Positive dp reduces exhaust
        _rExhSp := LIMIT(fFanSpMin, _rExhSp, fFanSpMax);                    // 速度限幅 / Speed clamp
    END_IF
    IF tonDpBad.Q THEN
        _uInfo := 16#0005_04DB;                                             // 信息级：失衡降级进入 / Info: degrade entered
        _eState := E_DL_PbaState.eDegrade;                                  // 越带超延时降级 / Degrade after confirm delay
    END_IF

E_DL_PbaState.eDegrade:
    _rSupSp := fSupSpBase;                                                  // 降级相仍保持送风基准 / Degrade keeps supply base
    IF _bDpOut THEN
        _rExhSp := _rExhSp - fTrimGain * (fDpAct - fDpSp) * fDtSec;         // 降级相继续 trim 回带 / Degrade keeps trimming
        _rExhSp := LIMIT(fFanSpMin, _rExhSp, fFanSpMax);                    // 速度限幅 / Speed clamp
    END_IF
    IF (NOT _bDpOut) OR (NOT bAutoEn) THEN
        _eState := E_DL_PbaState.eRun;                                      // 退出双条件：回带或使能撤（R240 口径）/ Dual exit conditions
    END_IF

E_DL_PbaState.eSmoke:
    _rSupSp := fFanSpMin;                                                   // 排烟：送风最小 / Smoke: supply minimum
    _rExhSp := fFanSpMax;                                                   // 排烟：排风最大 / Smoke: exhaust maximum
    IF (NOT bFireAlarm) AND (NOT _bFault) THEN
        IF bAutoEn THEN
            _eState := E_DL_PbaState.eRun;                                  // 消防撤且使能回运行 / Fire clear and enabled, back to run
        ELSE
            _eState := E_DL_PbaState.eIdle;                                 // 消防撤且未使能回待机 / Fire clear, not enabled, idle
        END_IF
    END_IF

E_DL_PbaState.eFault:
    ;                                                                       // 出口保持故障前最后给定（冻结） / Outputs hold last setpoints
                                                                            // 仅段 2 复位沿可迁出 / Only reset edge leaves

ELSE
    _bFault := TRUE;                                                        // 非法状态兜底（R6）/ Illegal state fallback
    _eCause := E_DL_PbaCause.eCfgIllegal;                                   // 归因归并组态 / Cause folded to config
    _eState := E_DL_PbaState.eFault;

END_CASE

(* —— 段 5：故障锁存状态迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_PbaState.eFault) THEN
    _eState := E_DL_PbaState.eFault;                                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
rSupSp := _rSupSp;                                                          // 送风速度出口 [%] / Supply speed outlet
rExhSp := _rExhSp;                                                          // 排风速度出口 [%] / Exhaust speed outlet
IF fSupFlowAct > DL_PBA_EPS THEN                                            // 流量比除法前判送风流量（R4）/ Zero-guard before ratio
    fBalRatio := fExhFlowAct / fSupFlowAct;                                 // 排/送流量比 [-] / Flow ratio
ELSE
    fBalRatio := 0.0;                                                       // 送风流量近零钳零出口 / Clamp ratio to zero
END_IF
bBalanceOk := (_eState = E_DL_PbaState.eRun) AND (NOT _bDpOut);             // 带内判据 / In-band judgement
bDegrade := (_eState = E_DL_PbaState.eDegrade);                             // 降级镜像 / Degrade mirror
bSmokeMode := (_eState = E_DL_PbaState.eSmoke);                             // 排烟镜像 / Smoke mirror
eState := _eState;                                                          // 状态出口 / State outlet
eCause := _eCause;                                                          // 成因出口 / Cause outlet
bError := _bFault;                                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := 16#0005_03B8;                                                 // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                       // 信息码 / Info code
END_IF

END_FUNCTION_BLOCK
