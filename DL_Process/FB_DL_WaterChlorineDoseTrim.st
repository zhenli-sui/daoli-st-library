(*
  道莅工业代码库 | DL_Process | FB_DL_WaterChlorineDoseTrim
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；绿区水处理语义域延伸，零代码行复制）
  功能: 余氯-浊度双参数加药量 trim 控制——以余氯偏差比例 trim 出口加药量设定，
        浊度超高经延时进护栏态（trim 只允许下调禁上调），剂量上限闸（±fTrimLim），
        流量折算加药流量出口（L/h）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG / LIMIT，零厂商私有库
  接口: 输入余氯实测/设定、浊度实测/上限、基准加药量、trim 增益与幅值限、
        处理流量、周期、冻结、复位；输出 fDoseRate [mg/L]/fTrimOut [mg/L]/
        fDoseFlow [L/h]/bTurbGuard/eState/eCause/bError/nErrId。
  码表: 16#0005_03B9 故障级：传感器非有限（余氯/浊度 NaN，锁存至复位沿，剂量保持最后有效值）
        16#0005_04E0 信息级：处理流量近零（fDoseFlow 出口钳零，加药量出口不受影响）
        码段说明：0005 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① trim 幅值闸：LIMIT(±fTrimLim)，护栏态下 trim := MIN(trim, 0)（只降不升）；
        ② 护栏态退出条件 ≥ 2 条：浊度回落前置消失，或使能撤/复位事件；
        ③ 传感器 NaN 故障锁存期间剂量保持锁存量（不随坏值波动）；
        ④ fDoseFlow = fDoseRate·fFlowAct/1000，除法无（乘法），流量比换算在出口
        判 fFlowAct > EPS 否则钳零并置信息码；
        ⑤ TON/R_TRIG 段 0 无条件周期刷新；⑥ 零全局耦合。
  邻件比对: DosingPumpCalib/BatchDosingControl（标定/批量加药 vs 本件余氯连续 trim）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B2 · C07）
*)

TYPE E_DL_WctState :
(
    eIdle     := 0,   // 待机（出口保持） | Idle, outlet held
    eTrim     := 10,  // 正常 trim 运行 | Normal trim run
    eTurbHold := 20,  // 浊度护栏（trim 禁上调） | Turbidity guard, trim down only
    eFault    := 90   // 故障锁存相 | Fault latch phase
);
END_TYPE

TYPE E_DL_WctCause :
(
    eNone          := 0,  // 无故障 | No cause
    eCfgIllegal    := 1,  // 组态非法 | Illegal configuration
    eSensNonFinite := 2   // 传感器非有限 | Sensor non-finite
);
END_TYPE

FUNCTION_BLOCK FB_DL_WaterChlorineDoseTrim
VAR_INPUT
    bAutoEn   : BOOL := FALSE;    // 自动 trim 使能 [-] | Auto trim enable
    fClResAct : REAL := 0.0;      // 余氯实测 [mg/L] | Chlorine residual actual
    fClResSp  : REAL := 0.8;      // 余氯设定，域 > 0 [mg/L] | Chlorine residual setpoint
    fTurbAct  : REAL := 0.0;      // 浊度实测 [NTU] | Turbidity actual
    fTurbMax  : REAL := 1.0;      // 浊度护栏上限，域 > 0 [NTU] | Turbidity guard limit
    fDoseBase : REAL := 1.2;      // 基准加药量，域 >= 0 [mg/L] | Base dose
    fKpTrim   : REAL := 1.0;      // trim 比例增益，域 >= 0 [mg/L per mg/L] | Trim proportional gain
    fTrimLim  : REAL := 0.5;      // trim 幅值限（±对称），域 >= 0 [mg/L] | Trim magnitude limit
    fFlowAct  : REAL := 0.0;      // 处理流量 [m3/h] | Treated flow actual
    fDtSec    : REAL := 0.1;      // 调节周期（护栏去抖基准），域 (0, 1] [s] | Trim cycle time
    tTurbHold : TIME := T#10S;    // 浊度超高确认延时，域 > T#0S | Turbidity confirm delay
    bFreeze   : BOOL := FALSE;    // trim 冻结（电平，剂量回基准）[-] | Trim freeze level
    bReset    : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    fDoseRate  : REAL;            // 出口加药量设定 [mg/L] | Dose rate outlet
    fTrimOut   : REAL;            // trim 分量出口 [mg/L] | Trim component outlet
    fDoseFlow  : REAL;            // 折算加药流量出口 [L/h] | Dosing flow outlet
    bTurbGuard : BOOL;            // 浊度护栏激活态 [-] | Turbidity guard active
    eState     : E_DL_WctState;   // 状态出口 | State outlet
    eCause     : E_DL_WctCause;   // 故障成因出口 | Fault cause outlet
    bError     : BOOL;            // 故障锁存标志 [-] | Fault latch flag
    nErrId     : UDINT;           // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState   : E_DL_WctState := E_DL_WctState.eIdle;   // 内部状态（CASE 唯一写入目标） | Internal state
    _eCause   : E_DL_WctCause := E_DL_WctCause.eNone;   // 成因锁存 | Latched cause
    _bFault   : BOOL;             // 故障锁存位 | Fault latch bit
    _fDoseRate: REAL := 0.0;      // 剂量锁存量 [mg/L]（故障保持载体） | Dose rate latch
    _fTrimOut : REAL := 0.0;      // trim 锁存量 [mg/L]（故障保持载体） | Trim latch
    _bCfgBad  : BOOL;             // 组态非法当拍量 [-] | Illegal configuration
    _bSensBad : BOOL;             // 传感器非有限当拍量 [-] | Sensor non-finite this scan
    _bTurbHi  : BOOL;             // 浊度超高当拍量 [-] | Turbidity high this scan
    _bFlowLo  : BOOL;             // 流量近零当拍量 [-] | Flow near zero this scan
    _uInfo    : UDINT;            // 信息码每拍重算 | Info code per scan
    fErr      : REAL;             // 余氯偏差当拍量 [mg/L] | Residual error this scan
    fTrimCalc : REAL;             // 本拍 trim 计算量 [mg/L] | Trim calculated this scan
    rtReset   : R_TRIG;           // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonTurb   : TON;              // 浊度超高确认计时，段 0 无条件刷新 | Turbidity confirm timer
END_VAR
VAR CONSTANT
    DL_WCT_EPS : REAL := 1.0E-6;      // 流量近零判据 [m3/h] | Flow zero threshold
    DL_WCT_ERR : UDINT := 16#0005_03B9;   // 传感器非有限故障码 | Sensor non-finite code
    DL_WCT_IFL : UDINT := 16#0005_04E0;   // 流量近零信息码 | Flow near-zero info code
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bSensBad := (fClResAct <> fClResAct) OR (fTurbAct <> fTurbAct);            // 传感器 NaN 自反判 / Sensor NaN self-reflex check
_bCfgBad := (fClResSp <= 0.0) OR (fTurbMax <= 0.0) OR (fDoseBase < 0.0)
         OR (fKpTrim < 0.0) OR (fTrimLim < 0.0) OR (fDtSec <= 0.0) OR (fDtSec > 1.0);  // 组态域闸 / Configuration gate
_bTurbHi := (NOT _bSensBad) AND (fTurbAct > fTurbMax);                      // 浊度超高判据（NaN 不判超高） / Turbidity high judgement
_bFlowLo := (fFlowAct <= DL_WCT_EPS) OR (fFlowAct <> fFlowAct);             // 流量近零/非有限判据 / Flow near-zero or non-finite
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
tonTurb(IN := bAutoEn AND _bTurbHi, PT := tTurbHold);                       // 浊度去抖 IN 挂使能 ∧ 超高 / Debounce gated by enable and turbidity

(* —— 段 1：单拍量预清零 —— *)
_uInfo := 16#0000_0000;                                                     // 信息码每拍重算 / Info recomputed per scan
fErr := 0.0;                                                                // 偏差当拍量预清 / Error preset
fTrimCalc := 0.0;                                                           // trim 计算量预清 / Trim calc preset

(* —— 段 2：复位沿 + 组态/传感器域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN                                        // 复位沿且组态合法 / Reset with legal config
    _bFault := FALSE;                                                       // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_WctCause.eNone;                                         // 清成因 / Clear cause
    IF _eState = E_DL_WctState.eFault THEN
        _eState := E_DL_WctState.eIdle;                                     // 故障相迁出唯一路径 / Sole fault exit
    END_IF
END_IF
IF _bCfgBad THEN                                                            // 组态域闸 / Configuration gate
    _bFault := TRUE;
    _eCause := E_DL_WctCause.eCfgIllegal;                                   // 归因组态 / Cause: config
END_IF
IF _bSensBad AND (NOT _bFault) THEN                                         // 传感器域闸（组态闸优先归因） / Sensor gate
    _bFault := TRUE;
    _eCause := E_DL_WctCause.eSensNonFinite;                                // 归因传感器 / Cause: sensor
END_IF

(* —— 段 3：trim 计算（限幅 + 护栏只降 + 冻结归零） —— *)
IF bAutoEn AND (NOT _bFault) AND (NOT _bSensBad) THEN
    fErr := fClResSp - fClResAct;                                           // 余氯偏差（正=欠氯需增药）[mg/L] / Residual error
    fTrimCalc := fKpTrim * fErr;                                            // 比例 trim 计算 [mg/L] / Proportional trim
    fTrimCalc := LIMIT(-fTrimLim, fTrimCalc, fTrimLim);                     // 剂量幅值闸（±对称限幅） / Magnitude gate
    IF _bTurbHi THEN
        fTrimCalc := 0.5 * (fTrimCalc + MIN(fTrimCalc, 0.0));               // 护栏半限：向零收敛、只允许下调分量 / Guard: converge toward zero, down-only
    END_IF
    IF bFreeze THEN
        fTrimCalc := 0.0;                                                   // 冻结：trim 归零（剂量回基准） / Freeze: trim zero
    END_IF
    _fTrimOut := fTrimCalc;                                                 // trim 锁存量更新（有效拍才写） / Trim latch updated on valid scans
    _fDoseRate := fDoseBase + _fTrimOut;                                    // 剂量 = 基准 + trim [mg/L] / Dose = base + trim
    IF _fDoseRate < 0.0 THEN
        _fDoseRate := 0.0;                                                  // 剂量非负防御（基准+负 trim 越界） / Dose non-negative defense
    END_IF
END_IF

(* —— 段 4：状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_WctState.eIdle:
    IF bAutoEn AND (NOT _bFault) THEN
        _eState := E_DL_WctState.eTrim;                                     // 使能进 trim / Enabled, enter trim
    END_IF

E_DL_WctState.eTrim:
    IF tonTurb.Q THEN
        _eState := E_DL_WctState.eTurbHold;                                 // 浊度超高确认进护栏 / Turbidity confirmed, guard
    ELSIF (NOT bAutoEn) OR _bFault THEN
        _eState := E_DL_WctState.eIdle;                                     // 使能撤或故障回待机 / Disable or fault, idle
    END_IF

E_DL_WctState.eTurbHold:
    IF (NOT _bTurbHi) OR (NOT bAutoEn) THEN
        _eState := E_DL_WctState.eTrim;                                     // 退出双条件：浊度回落（去抖经 tonTurb 重入）或使能撤 / Dual exit conditions
    ELSIF _bFault THEN
        _eState := E_DL_WctState.eIdle;                                     // 故障回待机 / Fault, idle
    END_IF

E_DL_WctState.eFault:
    ;                                                                       // 剂量保持锁存量（故障冻结）/ Dose holds latch, only reset leaves

ELSE
    _bFault := TRUE;                                                        // 非法状态兜底（R6）/ Illegal state fallback
    _eCause := E_DL_WctCause.eCfgIllegal;                                   // 归因归并组态 / Cause folded to config
    _eState := E_DL_WctState.eFault;

END_CASE

(* —— 段 5：故障锁存状态迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_WctState.eFault) THEN
    _eState := E_DL_WctState.eFault;                                        // 锁存即入故障相（剂量冻结在锁存量）/ Latch enters fault phase
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fDoseRate := _fDoseRate;                                                    // 剂量出口（故障相回放锁存量）[mg/L] / Dose outlet
fTrimOut := _fTrimOut;                                                      // trim 出口 [mg/L] / Trim outlet
IF _bFlowLo OR _bFault THEN
    fDoseFlow := 0.0;                                                       // 流量近零/故障折算出口钳零 [L/h] / Flow outlet clamped zero
    IF _bFlowLo THEN
        _uInfo := DL_WCT_IFL;                                               // 信息级：流量近零 / Info: flow near zero
    END_IF
ELSE
    fDoseFlow := _fDoseRate * fFlowAct * 0.001;                             // 折算加药流量 = 剂量·流量/1000 [L/h] / Dosing flow conversion
END_IF
bTurbGuard := (_eState = E_DL_WctState.eTurbHold);                          // 护栏镜像 / Guard mirror
eState := _eState;                                                          // 状态出口 / State outlet
eCause := _eCause;                                                          // 成因出口 / Cause outlet
bError := _bFault;                                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := DL_WCT_ERR;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                       // 信息码 / Info code
END_IF

END_FUNCTION_BLOCK
