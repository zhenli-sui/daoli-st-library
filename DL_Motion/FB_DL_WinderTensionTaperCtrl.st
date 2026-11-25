// FB_DL_WinderTensionTaperCtrl v1.0.0
(*==============================================================================
 * 功能描述: C4 收卷锥度张力控制。给定内圈张力 fTensionIn 与锥度系数 fTaperK，按当前
 *           卷径 fDiameter 外推张力设定（锥度模式）或恒张力模式，设定值经 fRampRate
 *           斜坡限速输出；模式切换与卷径突变均由斜坡自然平滑。卷径/张力限幅与组态
 *           非法、非有限输入防御齐备。
 * 接口契约: 输入 bEnable/eModeReq/fTensionIn/fTaperK/fDiameter/fDiaMin/fDiaMax/
 *           fTensionMin/fTensionMax/fRampRate/fDtSec/bReset；
 *           输出 fTensionSet/eModeAct/bValid/eState/bError/nErrId。
 * 边界: ① 组态闸：fDiaMin<=0、fDiaMax<fDiaMin、fTensionMin<0、fTensionMax<=fTensionMin、
 *           fRampRate<=0、fDtSec<=0 或任一浮点引脚 NaN → 故障锁存；② 卷径先钳位到
 *           [fDiaMin,fDiaMax] 再进锥度外推（R4 防越界）；③ 一枚 R_TRIG 段 0 无条件刷新；
 *           ④ 零全局耦合。
 * 码表: 16#0007_0302 故障级总码（组态非法/非有限输入/非法相位，锁存至 bReset 上升沿）。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

TYPE E_DL_WttMode :
(
    eConstant := 0,   // 恒张力模式（不随卷径外推）/ Constant tension mode
    eTaper    := 1    // 锥度张力模式（随卷径线性外推）/ Taper tension mode
);
END_TYPE

TYPE E_DL_WttState :
(
    eIdle  := 0,      // 待机（设定值冻结保持）/ Idle, setpoint frozen
    eRun   := 10,     // 运行（斜坡跟随目标）/ Running, ramp toward target
    eFault := 90      // 故障锁存相（仅复位沿迁出）/ Fault latched, exit by reset edge only
);
END_TYPE

FUNCTION_BLOCK FB_DL_WinderTensionTaperCtrl
VAR_INPUT
    bEnable     : BOOL := FALSE;         // 使能（FALSE 冻结输出保持）[-] / Enable, FALSE freezes output
    eModeReq    : E_DL_WttMode := E_DL_WttMode.eTaper;   // 张力模式请求 [枚举] / Tension mode request
    fTensionIn  : REAL := 50.0;          // 内圈张力给定，域 > 0 [N] / Inner tension setpoint [N]
    fTaperK     : REAL := 0.0005;        // 锥度系数，域 >= 0 [1/mm] / Taper coefficient [1/mm]
    fDiameter   : REAL := 100.0;         // 当前卷径反馈 [mm] / Current roll diameter [mm]
    fDiaMin     : REAL := 100.0;         // 卷径下限（纸芯径），域 > 0 [mm] / Minimum diameter [mm]
    fDiaMax     : REAL := 800.0;         // 卷径上限，域 >= fDiaMin [mm] / Maximum diameter [mm]
    fTensionMin : REAL := 0.0;           // 张力下限，域 >= 0 [N] / Tension lower limit [N]
    fTensionMax : REAL := 200.0;         // 张力上限，域 > fTensionMin [N] / Tension upper limit [N]
    fRampRate   : REAL := 10.0;          // 设定值斜坡速率，域 > 0 [N/s] / Ramp rate [N/s]
    fDtSec      : REAL := 0.010;         // 任务周期 [s]，域 > 0 / Task period [s], domain > 0
    bReset      : BOOL := FALSE;         // 复位，上升沿清故障锁存 [-] / Reset edge clears fault
END_VAR
VAR_OUTPUT
    fTensionSet : REAL := 0.0;           // 张力设定输出（斜坡后，限幅内）[N] / Tension setpoint output [N]
    eModeAct    : E_DL_WttMode;          // 当前生效模式出口 [枚举] / Active mode outlet
    bValid      : BOOL;                  // 设定值有效回执 [-] / Setpoint validity receipt
    eState      : E_DL_WttState;         // 状态出口，段尾单点映射 / State outlet
    bError      : BOOL;                  // 故障锁存标志 [-] / Fault latch flag
    nErrId      : UDINT;                 // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    _eState    : E_DL_WttState := E_DL_WttState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    rtReset    : R_TRIG;                 // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    _fTarget   : REAL := 0.0;            // 本拍目标张力（限幅后）[N] / Target tension this scan [N]
    _fSetInt   : REAL := 0.0;            // 内部斜坡设定值（锁存量）[N] / Internal ramped setpoint
    _fDiaEff   : REAL := 0.0;            // 钳位后有效卷径 [mm] / Clamped effective diameter [mm]
    _fStep     : REAL := 0.0;            // 本拍斜坡步长 [N] / Ramp step this scan
    _bCfgBad   : BOOL;                   // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin   : BOOL;                   // 输入非有限当拍量 [-] / Non-finite input this scan
    _bFault    : BOOL;                   // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;                  // 故障码锁存（锁存量） / Latched fault code
    _eModeInt  : E_DL_WttMode := E_DL_WttMode.eTaper;    // 生效模式锁存 / Active mode latch
END_VAR

(* —— 段 0：沿实例无条件周期刷新 —— *)
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge, called every scan

(* —— 段 1：单拍量预清零（锁存量 _fSetInt/_eModeInt/_bFault/_uFault 不入清单） —— *)
bValid := FALSE;                                                   // 有效回执预清（运行相回填） / Validity preset
bError := FALSE;                                                   // 故障标志预清（置位处同拍回填） / Error flag preset
nErrId := 16#0000_0000;                                            // 事件码缺省无事件 / Event code default none

(* —— 段 2：组态域闸与非有限闸（覆盖全部参与引脚） —— *)
_bNonFin := (fTensionIn <> fTensionIn) OR (fTaperK <> fTaperK)     // 给定与系数 NaN 自反判 / NaN self-reflexive tests
         OR (fDiameter <> fDiameter) OR (fDiaMin <> fDiaMin)       // 卷径引脚 NaN 判 / Diameter NaN tests
         OR (fDiaMax <> fDiaMax) OR (fTensionMin <> fTensionMin)   // 限幅引脚 NaN 判 / Limit NaN tests
         OR (fTensionMax <> fTensionMax) OR (fRampRate <> fRampRate)// 上限与速率 NaN 判 / Upper limit and rate NaN tests
         OR (fDtSec <> fDtSec);                                    // 周期 NaN 判 / Period NaN test
_bCfgBad := (fDiaMin <= 0.0) OR (fDiaMax < fDiaMin)                // 卷径域闸 / Diameter domain gates
         OR (fTensionMin < 0.0) OR (fTensionMax <= fTensionMin)    // 张力限幅域闸 / Tension limit gates
         OR (fRampRate <= 0.0) OR (fDtSec <= 0.0)                  // 速率与周期域闸 / Rate and period gates
         OR (fTensionIn <= 0.0);                                   // 给定正值闸 / Positive setpoint gate

(* —— 段 3：故障锁存与解除（R45 配对；解除式全当拍量） —— *)
IF _bCfgBad THEN                                                   // 组态非法 / Illegal configuration
    _uFault := 16#0007_0302;                                       // 故障级总码 / Fault-level code
    _bFault := TRUE;
    bError  := TRUE;
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                 // 输入非有限 / Non-finite input
    _uFault := 16#0007_0302;
    _bFault := TRUE;
    bError  := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN            // 解除沿（当拍量） / Release edge
    _bFault := FALSE;                                              // 清故障锁存 / Clear fault latch
    _uFault := 16#0000_0000;                                       // 清故障码 / Clear fault code
    IF _eState = E_DL_WttState.eFault THEN
        _eState := E_DL_WttState.eIdle;                            // 故障相唯一迁出路径 / Sole exit from fault phase
    END_IF
END_IF

(* —— 段 4：相位机（ENUM 全成员显式标签 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_WttState.eIdle:
    IF (NOT _bFault) AND bEnable THEN                              // 出口 1：使能进运行 / Enable enters run
        _eModeInt := eModeReq;                                     // 锁存生效模式 / Latch active mode
        _eState := E_DL_WttState.eRun;
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_WttState.eFault;
    END_IF

E_DL_WttState.eRun:
    IF (NOT bEnable) THEN                                          // 出口 1：撤使能回待机（设定值冻结保持） / Disable, setpoint frozen
        _eState := E_DL_WttState.eIdle;
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_WttState.eFault;
    ELSE
        _eModeInt := eModeReq;                                     // 模式请求每拍跟随（切换由斜坡平滑） / Mode follows request, ramp smooths
        _fDiaEff := fDiameter;                                     // 卷径预装 / Diameter preloaded
        IF _fDiaEff < fDiaMin THEN                                 // 卷径下限钳位（R4 防越界） / Clamp to lower bound
            _fDiaEff := fDiaMin;
        END_IF
        IF _fDiaEff > fDiaMax THEN                                 // 卷径上限钳位 / Clamp to upper bound
            _fDiaEff := fDiaMax;
        END_IF
        IF _eModeInt = E_DL_WttMode.eTaper THEN                    // 锥度模式：按卷径线性外推 / Taper mode, linear extrapolation
            _fTarget := fTensionIn * (1.0 + fTaperK * (_fDiaEff - fDiaMin));   // 锥度外推 [N] / Taper extrapolation
        ELSE                                                       // 恒张力模式 / Constant mode
            _fTarget := fTensionIn;                                // 目标 = 给定 / Target equals setpoint
        END_IF
        IF _fTarget < fTensionMin THEN                             // 张力下限饱和钳位 / Saturate at lower limit
            _fTarget := fTensionMin;
        END_IF
        IF _fTarget > fTensionMax THEN                             // 张力上限饱和钳位 / Saturate at upper limit
            _fTarget := fTensionMax;
        END_IF
        _fStep := fRampRate * fDtSec;                              // 本拍斜坡步长 [N] / Ramp step this scan
        IF _fSetInt < (_fTarget - _fStep) THEN                     // 上升斜坡限速 / Upward ramp limited
            _fSetInt := _fSetInt + _fStep;
        ELSIF _fSetInt > (_fTarget + _fStep) THEN                  // 下降斜坡限速 / Downward ramp limited
            _fSetInt := _fSetInt - _fStep;
        ELSE
            _fSetInt := _fTarget;                                  // 步长内直达目标 / Within step, reach target
        END_IF
    END_IF

E_DL_WttState.eFault:
    ;                                                              // 故障相：仅段 3 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0007_0302;                                       // 故障级：非法相位兜底 / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eState := E_DL_WttState.eFault;                               // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF (_eState = E_DL_WttState.eRun) AND (NOT _bFault) THEN
    fTensionSet := _fSetInt;                                       // 运行相输出斜坡设定 / Run phase outputs ramped setpoint
    bValid := TRUE;                                                // 有效回执 / Validity receipt
END_IF
eModeAct := _eModeInt;                                             // 模式出口 / Mode outlet
IF _bFault THEN
    fTensionSet := fTensionMin;                                    // 故障相安全侧：输出张力下限 / Safe side in fault
    nErrId := _uFault;                                             // 故障锁存码回放 / Replay latched fault code
END_IF
bError := _bFault;                                                 // 故障标志与锁存同源 / Flag from latch
eState := _eState;                                                 // 状态出口 / State outlet

END_FUNCTION_BLOCK
