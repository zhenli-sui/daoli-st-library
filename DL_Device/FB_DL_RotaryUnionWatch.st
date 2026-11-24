(*
  组件名 Component   : FB_DL_RotaryUnionWatch
  子库 Sublibrary    : DL_Device
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 旋转接头三判据监视（T2-6 三分类诊断结构复用）：
                       1) 超速判据：转速 > fSpeedLimRpm 持续 tSpeedWin 确认；
                       2) 温升判据：接头温升（接头温 - 环境温）> fTempRiseLimK
                       持续 tTempWin 确认；
                       3) 泄漏判据：泄漏率 > fLeakLimMlMin 持续 tLeakWin 确认；
                       4) 三判据各带独立确认窗与独立锁存位（R190 归因唯一，禁共用
                       枚举成员），任一锁存 → 故障总码 + 成因出口；
                       5) NE107 健康出口引用唯一属主 E_DL_Ne107Status（零重声明）：
                       任一锁存 → eFailure；确认窗在计 → eMaintenanceReq；否则 eOk。
  边界 Boundary      : ① 监视件只出诊断，不执行停机动作（上层按 eFailure 仲裁）；
                       ② 三个锁存位解除路径唯一且可达：rtReset.Q（输入引脚恒可拉沿）；
                       ③ 非有限值（NaN 自反 + 无穷差值自减）判输入非法锁存；
                       ④ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : E_DL_Ne107Status（DL_Device 唯一属主）；Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-6-rockwell-aoi 三分类诊断结构与
                       参数域，零代码行复制；健康出口仅引用唯一属主枚举）
  码位 Code          : 16#03_3_0（Device 05xx 副带 0530）
  码表 Error codes（Device 故障窗口 0530，本件无信息码，单故障总码 + 成因枚举归因）:
    16#0003_0530 故障级：旋转接头故障总码（超速 / 温升 / 泄漏 / 组态非法 /
                 输入非有限），锁存至 bReset 上升沿，归因见 eCause 与三分量出口
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 3 · 序号 12）
*)

TYPE E_DL_RuwState :
(
    eIdle  := 0,    // 空闲：未使能 / Idle, not enabled
    eRun   := 10,   // 监视运行：三判据并行 / Running, three criteria active
    eFault := 90    // 故障：总码锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_RuwCause :
(
    eNone      := 0,  // 无故障成因 / No cause
    eOverSpeed := 1,  // 超速锁存 / Over-speed latched
    eOverTemp  := 2,  // 温升锁存 / Temperature-rise latched
    eLeak      := 3,  // 泄漏锁存 / Leakage latched
    eCfgIllegal:= 4,  // 组态非法 / Illegal configuration
    eNonFinite := 5   // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_RotaryUnionWatch
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    fSpeedRpm    : REAL;                   // 接头转速 [转/分] / Union speed
    fTempUnionC  : REAL;                   // 接头温度 [摄氏度] / Union temperature
    fAmbientC    : REAL;                   // 环境参考温度 [摄氏度] / Ambient temperature
    fLeakRateMlMin: REAL;                  // 泄漏率 [毫升/分] / Leakage rate
    fSpeedLimRpm : REAL := 3000.0;         // 转速上限 [转/分] / Speed limit
    fTempRiseLimK: REAL := 40.0;           // 温升上限 [开尔文] / Temperature-rise limit
    fLeakLimMlMin: REAL := 5.0;            // 泄漏率上限 [毫升/分] / Leakage limit
    tSpeedWin    : TIME := T#2S;           // 超速确认窗 [毫秒] / Speed confirm window
    tTempWin     : TIME := T#5S;           // 温升确认窗 [毫秒] / Temperature confirm window
    tLeakWin     : TIME := T#5S;           // 泄漏确认窗 [毫秒] / Leakage confirm window
END_VAR
VAR_OUTPUT
    bSpdLatch    : BOOL;                   // 超速锁存位（独立成员，R190）[-] / Speed latch
    bTempLatch   : BOOL;                   // 温升锁存位（独立成员，R190）[-] / Temperature latch
    bLeakLatch   : BOOL;                   // 泄漏锁存位（独立成员，R190）[-] / Leakage latch
    fTempRiseK   : REAL;                   // 实测温升 [开尔文] / Measured temperature rise
    eNe107       : E_DL_Ne107Status;       // NE107 健康出口（唯一属主枚举） / NE107 health outlet
    eState       : E_DL_RuwState;          // 状态出口，段尾单点映射 / State outlet
    eCause       : E_DL_RuwCause;          // 故障成因出口（R190） / Fault cause outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset  : R_TRIG;                     // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonSpeedWin : TON;                     // 超速确认窗（独立实例） / Speed confirm timer
    tonTempWin  : TON;                     // 温升确认窗（独立实例） / Temperature confirm timer
    tonLeakWin  : TON;                     // 泄漏确认窗（独立实例） / Leakage confirm timer
    _eState : E_DL_RuwState := E_DL_RuwState.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _eCause : E_DL_RuwCause := E_DL_RuwCause.eNone;    // 故障成因锁存（锁存量）/ Latched cause
    _bSpdL  : BOOL;                        // 超速锁存内部位（锁存量） / Speed latch internal
    _bTmpL  : BOOL;                        // 温升锁存内部位（锁存量） / Temperature latch internal
    _bLeakL : BOOL;                        // 泄漏锁存内部位（锁存量） / Leakage latch internal
    _fRise  : REAL;                        // 温升当拍量 [开尔文] / Temperature rise temp
    _bFault : BOOL;                        // 故障锁存位（锁存量） / Latched fault bit
    _uFault : UDINT;                       // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_ABS_MAX : REAL := 1.0E30;           // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO    : REAL := 0.0;              // 零常量 [工程单位] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；三窗独立实例禁复用） —— *)
_fRise := fTempUnionC - fAmbientC;       // 温升当拍差值（除法无，差值安全）
rtReset(CLK := bReset);
tonSpeedWin(IN := (_eState = E_DL_RuwState.eRun) AND (fSpeedRpm > fSpeedLimRpm) AND (NOT _bFault),
            PT := tSpeedWin);
tonTempWin (IN := (_eState = E_DL_RuwState.eRun) AND (_fRise > fTempRiseLimK) AND (NOT _bFault),
            PT := tTempWin);
tonLeakWin (IN := (_eState = E_DL_RuwState.eRun) AND (fLeakRateMlMin > fLeakLimMlMin) AND (NOT _bFault),
            PT := tLeakWin);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/_bSpdL/_bTmpL/_bLeakL 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障与三锁存位一次性清干净（唯一解除路径，可达性自证：
        rtReset.Q 为输入引脚当拍量，调用方拉 bReset 上升沿即可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eCause := E_DL_RuwCause.eNone;
    _bSpdL  := FALSE;
    _bTmpL  := FALSE;
    _bLeakL := FALSE;
    _eState := E_DL_RuwState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚，R28 加固） —— *)
IF (fSpeedLimRpm <= DL_ZERO) OR (fTempRiseLimK <= DL_ZERO) OR (fLeakLimMlMin <= DL_ZERO)
   OR (tSpeedWin = T#0S) OR (tTempWin = T#0S) OR (tLeakWin = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fSpeedRpm <> fSpeedRpm) OR ((fSpeedRpm - fSpeedRpm) <> DL_ZERO)
   OR (fTempUnionC <> fTempUnionC) OR ((fTempUnionC - fTempUnionC) <> DL_ZERO)
   OR (fAmbientC <> fAmbientC) OR ((fAmbientC - fAmbientC) <> DL_ZERO)
   OR (fLeakRateMlMin <> fLeakRateMlMin) OR ((fLeakRateMlMin - fLeakRateMlMin) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_RuwState.eIdle:
    bSpdLatch  := FALSE;
    bTempLatch := FALSE;
    bLeakLatch := FALSE;
    eNe107 := E_DL_Ne107Status.eOk;
    IF bEnable AND (NOT _bCfgBad) THEN
        _eState := E_DL_RuwState.eRun;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0003_0530;
        _eCause := E_DL_RuwCause.eCfgIllegal;
        bError  := TRUE;
        _eState := E_DL_RuwState.eFault;
    END_IF

E_DL_RuwState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_RuwState.eIdle;  // 使能撤销回空闲
    ELSE
        fTempRiseK := _fRise;            // 温升出口刷新（有限值已过闸）
        IF _bNonFin THEN
            _bFault := TRUE;             // 输入非有限：判据不可信，锁存
            _uFault := 16#0003_0530;
            _eCause := E_DL_RuwCause.eNonFinite;
            bError  := TRUE;
            _eState := E_DL_RuwState.eFault;
        ELSE
            (* 三判据独立确认窗 → 独立锁存位（R190：各有独立状态成员） *)
            IF tonSpeedWin.Q THEN
                _bSpdL := TRUE;
            END_IF
            IF tonTempWin.Q THEN
                _bTmpL := TRUE;
            END_IF
            IF tonLeakWin.Q THEN
                _bLeakL := TRUE;
            END_IF
            bSpdLatch  := _bSpdL;        // 名实双出口（R191 同源赋值）
            bTempLatch := _bTmpL;
            bLeakLatch := _bLeakL;
            (* 成因归因：按锁存位独立判（禁共用枚举成员致某成因永不赋值） *)
            IF _bSpdL THEN
                _eCause := E_DL_RuwCause.eOverSpeed;
            ELSIF _bTmpL THEN
                _eCause := E_DL_RuwCause.eOverTemp;
            ELSIF _bLeakL THEN
                _eCause := E_DL_RuwCause.eLeak;
            END_IF
            IF _bSpdL OR _bTmpL OR _bLeakL THEN
                _bFault := TRUE;
                _uFault := 16#0003_0530;
                bError  := TRUE;
                _eState := E_DL_RuwState.eFault;
            ELSE
                IF tonSpeedWin.IN OR tonTempWin.IN OR tonLeakWin.IN THEN
                    eNe107 := E_DL_Ne107Status.eMaintenanceReq;   // 确认窗在计：需要维护
                ELSE
                    eNe107 := E_DL_Ne107Status.eOk;               // 无锁存无在计：正常
                END_IF
            END_IF
        END_IF
    END_IF

E_DL_RuwState.eFault:
    bError := TRUE;                      // 故障相驻留：锁存位回放，只认复位沿（段 2 迁出）
    bSpdLatch  := _bSpdL;                // 锁存回放（禁按当下输入重推断）
    bTempLatch := _bTmpL;
    bLeakLatch := _bLeakL;
    eNe107 := E_DL_Ne107Status.eFailure; // 故障相健康出口失效级
    ;                                    // （确认窗中间态不再评估：故障相冻结归因）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0003_0530;
    _eCause := E_DL_RuwCause.eCfgIllegal;
    bError  := TRUE;
    eNe107  := E_DL_Ne107Status.eFailure;
    _eState := E_DL_RuwState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
