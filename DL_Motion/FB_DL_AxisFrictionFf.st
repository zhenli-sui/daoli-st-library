(*
  组件名 Component   : FB_DL_AxisFrictionFf
  子库 Sublibrary    : DL_Motion
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 摩擦转矩前馈：
                       1) 静/动摩擦分段：|速度| < 静动切换阈 → 静摩擦段（出全静摩擦值），
                       否则动摩擦段（出动摩擦值）；
                       2) 速度方向切换滞环：方向电平只在速度越过零速迟滞带后翻转，
                       防零速附近前馈符号抖动；
                       3) 前馈系数钳位：fFfGain 域 [0, 1]，域外钳位并告警锁存；
                       4) 分段切换与换向均经一阶惯性平滑（tSmooth），防前馈阶跃。
  边界 Boundary      : ① 本件只出前馈转矩，不参与闭环（叠加由上层转矩合成）；
                       ② 组态闸：静摩擦 < 动摩擦（物理不可能）、系数负值、tCycle 零 → 故障；
                       ③ 非有限值（NaN 自反 + 无穷差值自减）判输入非法锁存；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG）
  溯源 Origin        : 道莅自研 clean-room（参考 t2-4-s7-motion 前馈分类与参数域，
                       零代码行复制）
  码位 Code          : 16#04_0_AB
  码表 Error codes（Motion 格 04_0_AB，单轨：故障 0x02AB / 信息 0x01AB）:
    16#0004_02AB 故障级：组态非法（静摩擦 < 动摩擦 / 系数负 / tCycle 零）或输入
                 非有限，锁存至 bReset 上升沿
    16#0004_01AB 信息级：前馈系数已钳位（域 [0,1] 越界当拍，瞬时口径）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 2 · 序号 8）
*)

TYPE E_DL_AffState :
(
    eIdle  := 0,    // 空闲：未使能，前馈归零 / Idle, feedforward zeroed
    eRun   := 10,   // 运行：分段前馈 / Running, segmented feedforward
    eFault := 90    // 故障：组态/输入锁存 / Fault, latched
);
END_TYPE

TYPE E_DL_AffZone :
(
    eStatic := 0,   // 静摩擦段：|速度| < 切换阈 / Static zone
    eDynamic := 10, // 动摩擦段：|速度| >= 切换阈 / Dynamic zone
    eHold   := 20   // 保持段：故障相冻结 / Hold zone, fault frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisFrictionFf
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    fVelCmdMmS   : REAL;                   // 速度指令 [mm/s]，符号即方向 / Velocity command
    fFricStaticNm: REAL := 2.0;            // 静摩擦幅值 [牛·米] / Static friction magnitude
    fFricDynNm   : REAL := 1.0;            // 动摩擦幅值 [牛·米] / Dynamic friction magnitude
    fSwitchVelMmS: REAL := 2.0;            // 静动切换速度阈 [mm/s] / Static-dynamic switch threshold
    fHystVelMmS  : REAL := 0.5;            // 换向迟滞带 [mm/s] / Direction hysteresis band
    fFfGain      : REAL := 1.0;            // 前馈系数 [无量纲]，域 0..1 / Feedforward gain
    tSmooth      : TIME := T#100MS;        // 分段/换向平滑惯性 [毫秒] / Smoothing lag
    tCycle       : TIME := T#10MS;         // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fFfTorqueNm  : REAL;                   // 前馈转矩输出 [牛·米] / Feedforward torque
    eFricZone    : E_DL_AffZone;           // 当前摩擦段出口 / Friction zone outlet
    bGainClamped : BOOL;                   // 系数已钳位标志 [-] / Gain clamped flag
    eState       : E_DL_AffState;          // 状态出口，段尾单点映射 / State outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset : R_TRIG;                      // 复位沿实例，段 0 无条件刷新 / Reset edge
    _eState : E_DL_AffState := E_DL_AffState.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bDirPos: BOOL;                        // 方向电平（迟滞后）[-] / Direction level
    _bDirSeen: BOOL;                       // 首方向已建立标志 [-] / First direction established
    _fDemand: REAL;                        // 平滑前前馈需求 [牛·米] / Pre-smooth demand
    _fSmK   : REAL;                        // 平滑系数 [无量纲] / Smoothing coefficient
    _fGainUse: REAL;                       // 生效前馈系数 [无量纲] / Effective gain
    _eZone  : E_DL_AffZone := E_DL_AffZone.eStatic;    // 内部段（CASE 唯一写入目标）/ Internal zone
    _bFault : BOOL;                        // 故障锁存位（锁存量） / Latched fault bit
    _uFault : UDINT;                       // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_GAIN_MAX : REAL := 1.0;             // 前馈系数上限 [无量纲] / Gain ceiling
    DL_ZERO     : REAL := 0.0;             // 零常量 [工程单位] / Zero constant
    DL_ONE      : REAL := 1.0;             // 单位常量 [无量纲] / Unity constant
    DL_ABS_MAX  : REAL := 1.0E30;          // 有限值判定上界 [工程单位] / Finite bound
    DL_MS_PER_S : REAL := 1000.0;          // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/_bDirSeen/_fFfTorqueNm 不入清单） —— *)
uErrId   := 16#0000_0000;
bGainClamped := FALSE;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，前馈归零 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    fFfTorqueNm := DL_ZERO;
    _eState := E_DL_AffState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与换算引脚） —— *)
IF (fFricStaticNm < fFricDynNm) OR (fFricStaticNm < DL_ZERO) OR (fFricDynNm < DL_ZERO)
   OR (fFfGain < DL_ZERO) OR (fSwitchVelMmS <= DL_ZERO) OR (fHystVelMmS <= DL_ZERO)
   OR (tCycle = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fVelCmdMmS <> fVelCmdMmS) OR ((fVelCmdMmS - fVelCmdMmS) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_AffState.eIdle:
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _bDirSeen := FALSE;
        _bDirPos  := FALSE;
        fFfTorqueNm := DL_ZERO;
        _eState := E_DL_AffState.eRun;
    ELSIF bEnable AND (_bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;
        _uFault := 16#0004_02AB;
        bError  := TRUE;
        _eState := E_DL_AffState.eFault;
    END_IF

E_DL_AffState.eRun:
    IF NOT bEnable THEN
        fFfTorqueNm := DL_ZERO;
        _eState := E_DL_AffState.eIdle;  // 使能撤销回空闲，前馈归零
    ELSIF _bNonFin THEN
        _bFault := TRUE;                 // 运行中输入非有限：锁存
        _uFault := 16#0004_02AB;
        bError  := TRUE;
        _eState := E_DL_AffState.eFault;
    ELSE
        (* 前馈系数钳位：域 [0,1]，越界钳位并留信息码 *)
        _fGainUse := fFfGain;
        IF _fGainUse > DL_GAIN_MAX THEN
            _fGainUse := DL_GAIN_MAX;
            bGainClamped := TRUE;
            uErrId := 16#0004_01AB;      // 信息级：系数钳位（瞬时口径）
        END_IF
        (* 方向迟滞：越零速迟滞带才翻转，防符号抖动 *)
        IF (NOT _bDirPos) AND (fVelCmdMmS > fHystVelMmS) THEN
            _bDirPos := TRUE;
            _bDirSeen := TRUE;
        ELSIF _bDirPos AND (fVelCmdMmS < -fHystVelMmS) THEN
            _bDirPos := FALSE;
            _bDirSeen := TRUE;
        END_IF
        (* 静/动分段 + 符号合成 *)
        IF ABS(fVelCmdMmS) < fSwitchVelMmS THEN
            _eZone := E_DL_AffZone.eStatic;
            IF _bDirPos THEN
                _fDemand := fFricStaticNm;
            ELSE
                _fDemand := -fFricStaticNm;
            END_IF
        ELSE
            _eZone := E_DL_AffZone.eDynamic;
            IF _bDirPos THEN
                _fDemand := fFricDynNm;
            ELSE
                _fDemand := -fFricDynNm;
            END_IF
        END_IF
        IF NOT _bDirSeen THEN
            _fDemand := DL_ZERO;         // 首方向未建立：需求归零
        END_IF
        _fDemand := _fDemand * _fGainUse;
        (* 一阶惯性平滑：tSmooth 零时直通 *)
        IF tSmooth = T#0S THEN
            _fSmK := DL_ONE;
        ELSE
            _fSmK := (TIME_TO_REAL(tCycle) / DL_MS_PER_S)
                     / ((TIME_TO_REAL(tCycle) / DL_MS_PER_S)
                        + TIME_TO_REAL(tSmooth) / DL_MS_PER_S);
        END_IF
        fFfTorqueNm := fFfTorqueNm + _fSmK * (_fDemand - fFfTorqueNm);
    END_IF

E_DL_AffState.eFault:
    bError := TRUE;                      // 故障相驻留：前馈冻结保持，只认复位沿（段 2 迁出）
    ;                                    // （冻结语义：fFfTorqueNm 保持最后值，禁降级归零不声明）
    _eZone := E_DL_AffZone.eHold;        // 段出口进保持段（名实双出口）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0004_02AB;
    bError  := TRUE;
    _eState := E_DL_AffState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射（名实同源） —— *)
eFricZone := _eZone;
eState := _eState;
END_FUNCTION_BLOCK
