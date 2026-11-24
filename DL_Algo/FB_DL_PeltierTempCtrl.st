(*
  道莅工业代码库 | DL_Algo | FB_DL_PeltierTempCtrl
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；行业池·精密温控 TEC 语义，零代码行复制）
  功能: 半导体制冷（TEC）双向温控——单 PI 输出带符号（正=加热极性/负=制冷极性），
        极性切换带回差（fDeadband）与最短驻留（tPolDwell，经 eSwitch 过渡相强制
        输出归零泄流），双向抗饱和（限幅同向禁积分）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG / LIMIT，零厂商私有库
  接口: 输入使能/温度设定/实测/PI 增益/输出限幅/积分限幅/切换回差/极性驻留/
        周期/复位；输出 fOutPct [%，-100..100]/bHeatMode/bCoolMode/fErrC/
        eState/eCause/bError/nErrId。
  码表: 16#0002_030B 故障级：温控故障总码（组态非法/温度非有限，锁存至复位沿）
        16#0002_0400 信息级：极性切换过渡进入（eSwitch 相，输出强制归零泄流）
        码段说明：0002 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① 极性切换三闸：误差越反向回差 ∧ 极性驻留满 tPolDwell ∧ 使能保持；
        切换经 eSwitch 过渡相（输出归零一拍周期 tPolDwell 泄流）后按当拍误差
        符号落极；
        ② 抗饱和：输出已饱和且误差继续同向 → 本拍不积分（双向对称口径）；
        ③ 极性驻留计时 tonDwell IN 挂加热/制冷相，经 eSwitch（IN 假）自然复位
        （R188 自复位口径）；
        ④ 温度/设定 NaN 故障锁存，输出钳零（安全侧）；
        ⑤ TON/R_TRIG 段 0 无条件周期刷新；⑥ 故障解除唯一路径 = 复位沿 ∧ 组态合法；
        ⑦ 零全局耦合。
  邻件比对: PidController（通用 PID vs 本件冷热极性切换+双向抗饱和 TEC 专用件）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B3 · C13）
*)

TYPE E_DL_PtcState :
(
    eIdle   := 0,   // 待机（输出零） | Idle, output zero
    eHeat   := 10,  // 加热极性（输出 >= 0） | Heat polarity, output non-negative
    eCool   := 20,  // 制冷极性（输出 <= 0） | Cool polarity, output non-positive
    eSwitch := 30,  // 极性切换过渡（输出归零泄流） | Polarity switch transition, output zero
    eFault  := 90   // 故障锁存相 | Fault latch phase
);
END_TYPE

TYPE E_DL_PtcCause :
(
    eNone          := 0,  // 无故障 | No cause
    eCfgIllegal    := 1,  // 组态非法 | Illegal configuration
    eSensNonFinite := 2   // 温度信号非有限 | Temperature signal non-finite
);
END_TYPE

FUNCTION_BLOCK FB_DL_PeltierTempCtrl
VAR_INPUT
    bEn        : BOOL := FALSE;    // 温控使能 [-] | Control enable
    fTempSp    : REAL := 25.0;     // 温度设定 [°C] | Temperature setpoint
    fTempAct   : REAL := 25.0;     // 温度实测 [°C] | Temperature actual
    fKp        : REAL := 20.0;     // 比例增益，域 > 0 [%/°C] | Proportional gain
    fKi        : REAL := 4.0;      // 积分增益，域 >= 0 [%/(°C·s)] | Integral gain
    fOutMax    : REAL := 100.0;    // 输出限幅，域 > 0 [%] | Output limit
    fIntLim    : REAL := 50.0;     // 积分限幅，域 (0, fOutMax] [%] | Integral limit
    fDeadband  : REAL := 0.5;      // 极性切换回差，域 >= 0 [°C] | Polarity switch hysteresis
    tPolDwell  : TIME := T#2S;     // 极性最短驻留/过渡泄流时长，域 > T#0S | Polarity dwell and transition time
    fDtSec     : REAL := 0.1;      // 控制周期，域 (0, 1] [s] | Control cycle time
    bReset     : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    fOutPct   : REAL;               // 输出出口（带符号：正=加热/负=制冷）[%] | Signed output outlet, positive heat
    bHeatMode : BOOL;               // 加热极性态 [-] | Heat polarity state
    bCoolMode : BOOL;               // 制冷极性态 [-] | Cool polarity state
    fErrC     : REAL;               // 温差出口（Sp - Act）[°C] | Error outlet
    eState    : E_DL_PtcState;      // 状态出口 | State outlet
    eCause    : E_DL_PtcCause;      // 故障成因出口 | Fault cause outlet
    bError    : BOOL;               // 故障锁存标志 [-] | Fault latch flag
    nErrId    : UDINT;              // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState  : E_DL_PtcState := E_DL_PtcState.eIdle;   // 内部状态（CASE 唯一写入目标） | Internal state
    _eCause  : E_DL_PtcCause := E_DL_PtcCause.eNone;   // 成因锁存 | Latched cause
    _bFault  : BOOL;            // 故障锁存位 | Fault latch bit
    _fInt    : REAL := 0.0;     // 积分项内部镜像 [%] | Integral term mirror
    _fOutPct : REAL := 0.0;     // 输出内部镜像 [%] | Output mirror
    _bCfgBad : BOOL;            // 组态非法当拍量 [-] | Illegal configuration
    _bSensBad: BOOL;            // 温度信号非有限当拍量 [-] | Temperature non-finite this scan
    _uInfo   : UDINT;           // 信息码每拍重算 | Info code per scan
    fErr     : REAL;            // 温差当拍量 [°C] | Error this scan
    fRaw     : REAL;            // 未限幅输出当拍量 [%] | Raw output this scan
    rtReset  : R_TRIG;          // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonDwell : TON;             // 极性驻留计时，段 0 无条件刷新 | Polarity dwell timer
    tonSw    : TON;             // 过渡泄流计时，段 0 无条件刷新 | Transition discharge timer
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bSensBad := (fTempSp <> fTempSp) OR (fTempAct <> fTempAct);                // 温度信号 NaN 自反判 / Temperature NaN self-reflex check
_bCfgBad := (fKp <= 0.0) OR (fKi < 0.0) OR (fOutMax <= 0.0) OR (fIntLim <= 0.0)
         OR (fIntLim > fOutMax) OR (fDeadband < 0.0) OR (tPolDwell <= T#0S)
         OR (fDtSec <= 0.0) OR (fDtSec > 1.0);                              // 组态域闸 / Configuration gate
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
tonDwell(IN := (_eState = E_DL_PtcState.eHeat) OR (_eState = E_DL_PtcState.eCool), PT := tPolDwell); // 驻留计时挂极性相 / Dwell timer in polarity states
tonSw(IN := (_eState = E_DL_PtcState.eSwitch), PT := tPolDwell);            // 泄流计时挂过渡相 / Discharge timer in transition

(* —— 段 1：单拍量预清零 + 温差派生（待机相极性判据依赖，全相可用） —— *)
_uInfo := 16#0000_0000;                                                     // 信息码每拍重算 / Info recomputed per scan
fErr := 0.0;                                                                // 温差预清（NaN 时保持零，安全侧）/ Error preset
fRaw := 0.0;                                                                // 原始输出预清 / Raw output preset
IF (NOT _bSensBad) AND (NOT _bFault) THEN
    fErr := fTempSp - fTempAct;                                             // 温差（正=欠温需加热）[°C]，全相派生 / Error derived in all states
END_IF

(* —— 段 2：复位沿 + 组态/传感器域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN                                        // 复位沿且组态合法 / Reset with legal config
    _bFault := FALSE;                                                       // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_PtcCause.eNone;                                         // 清成因 / Clear cause
    _fInt := 0.0;                                                           // 清积分（复位后重新起控） / Clear integral on reset
    IF _eState = E_DL_PtcState.eFault THEN
        _eState := E_DL_PtcState.eIdle;                                     // 故障相迁出唯一路径 / Sole fault exit
    END_IF
END_IF
IF _bCfgBad THEN                                                            // 组态域闸 / Configuration gate
    _bFault := TRUE;
    _eCause := E_DL_PtcCause.eCfgIllegal;                                   // 归因组态 / Cause: config
END_IF
IF _bSensBad AND (NOT _bFault) THEN                                         // 传感器域闸（组态闸优先归因） / Sensor gate
    _bFault := TRUE;
    _eCause := E_DL_PtcCause.eSensNonFinite;                                // 归因传感器 / Cause: sensor
END_IF

(* —— 段 3：PI 计算（双向抗饱和：限幅同向禁积分，边界②） —— *)
IF (NOT _bFault) AND bEn
   AND ((_eState = E_DL_PtcState.eHeat) OR (_eState = E_DL_PtcState.eCool)) THEN
    fRaw := fKp * fErr + _fInt;                                             // 未限幅输出 [%]（fErr 已段 1 全相派生）/ Raw output
    IF (fRaw >= fOutMax) AND (fErr > 0.0) THEN
        ;                                                                   // 加热向饱和且误差仍正向：本拍不积分 / Saturated toward heat, skip integration
    ELSIF (fRaw <= -fOutMax) AND (fErr < 0.0) THEN
        ;                                                                   // 制冷向饱和且误差仍负向：本拍不积分 / Saturated toward cool, skip integration
    ELSE
        _fInt := _fInt + fKi * fErr * fDtSec;                               // 积分递推 [%.s] / Integration step
        _fInt := LIMIT(-fIntLim, _fInt, fIntLim);                           // 积分限幅 / Integral clamp
    END_IF
    _fOutPct := LIMIT(-fOutMax, fKp * fErr + _fInt, fOutMax);               // 输出限幅 [%] / Output clamp
END_IF

(* —— 段 4：状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_PtcState.eIdle:
    _fOutPct := 0.0;                                                        // 待机输出零 / Idle output zero
    IF bEn AND (NOT _bFault) THEN
        IF fErr >= 0.0 THEN                                                 // 首次进入按温差符号落极（NaN 已被域闸拦） / Initial polarity by error sign
            _eState := E_DL_PtcState.eHeat;                                 // 欠温进加热极性 / Under-temperature, heat
        ELSE
            _eState := E_DL_PtcState.eCool;                                 // 过温进制冷极性 / Over-temperature, cool
        END_IF
    END_IF

E_DL_PtcState.eHeat:
    IF (NOT bEn) OR _bFault THEN
        _eState := E_DL_PtcState.eIdle;                                     // 使能撤/故障回待机 / Disable or fault, idle
    ELSIF (fErr < -fDeadband) AND tonDwell.Q THEN                           // 切换三闸：越反向回差 ∧ 驻留满 ∧ 使能（边界①）/ Three switch gates
        _uInfo := 16#0002_0400;                                             // 信息级：极性切换过渡进入 / Info: transition entered
        _eState := E_DL_PtcState.eSwitch;                                   // 进过渡相泄流 / Enter transition
    END_IF

E_DL_PtcState.eCool:
    IF (NOT bEn) OR _bFault THEN
        _eState := E_DL_PtcState.eIdle;                                     // 使能撤/故障回待机 / Disable or fault, idle
    ELSIF (fErr > fDeadband) AND tonDwell.Q THEN                            // 切换三闸（对称口径）/ Three switch gates, symmetric
        _uInfo := 16#0002_0400;                                             // 信息级：极性切换过渡进入 / Info: transition entered
        _eState := E_DL_PtcState.eSwitch;                                   // 进过渡相泄流 / Enter transition
    END_IF

E_DL_PtcState.eSwitch:
    _fOutPct := 0.0;                                                        // 过渡相输出强制归零（泄流）/ Transition output forced zero
    _fInt := 0.0;                                                           // 极性翻转清积分（防反向饱和滞后）/ Clear integral on polarity transition
    IF (NOT bEn) OR _bFault THEN
        _eState := E_DL_PtcState.eIdle;                                     // 使能撤/故障回待机 / Disable or fault, idle
    ELSIF tonSw.Q THEN
        IF fErr < 0.0 THEN
            _eState := E_DL_PtcState.eCool;                                 // 泄流毕按当拍误差落制冷极 / Discharge done, cool polarity
        ELSE
            _eState := E_DL_PtcState.eHeat;                                 // 泄流毕按当拍误差落加热极 / Discharge done, heat polarity
        END_IF
    END_IF

E_DL_PtcState.eFault:
    _fOutPct := 0.0;                                                        // 故障相输出钳零（安全侧）/ Fault output zero
    ;                                                                       // 仅段 2 复位沿可迁出 / Only reset edge leaves

ELSE
    _bFault := TRUE;                                                        // 非法状态兜底（R6）/ Illegal state fallback
    _eCause := E_DL_PtcCause.eCfgIllegal;                                   // 归因归并组态 / Cause folded to config
    _eState := E_DL_PtcState.eFault;

END_CASE

(* —— 段 5：故障锁存状态迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_PtcState.eFault) THEN
    _eState := E_DL_PtcState.eFault;                                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fOutPct := _fOutPct;                                                        // 输出出口 [%] / Output outlet
bHeatMode := (_eState = E_DL_PtcState.eHeat);                               // 加热极性镜像 / Heat mirror
bCoolMode := (_eState = E_DL_PtcState.eCool);                               // 制冷极性镜像 / Cool mirror
fErrC := fErr;                                                              // 温差出口 [°C] / Error outlet
eState := _eState;                                                          // 状态出口 / State outlet
eCause := _eCause;                                                          // 成因出口 / Cause outlet
bError := _bFault;                                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := 16#0002_030B;                                                 // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                       // 信息码 / Info code
END_IF

END_FUNCTION_BLOCK
