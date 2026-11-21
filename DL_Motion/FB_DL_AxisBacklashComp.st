(*
  组件名 Component   : FB_DL_AxisBacklashComp
  子库 Sublibrary    : DL_Motion
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 轴反向间隙补偿：
                       1) 方向反转沿检测：速度指令符号越过零速死区即判换向（含迟滞），
                       反转沿承载补偿目标翻转；
                       2) 间隙学习值注入：补偿目标 = 方向符号 × 学习值 / 2（两侧各半程），
                       学习值越域（|学习值| > 上限）即冻结沿用上次域内值并告警锁存；
                       3) 补偿量注入按速率限幅爬升（fFeedRateMmS），不阶跃注入；
                       4) 非有限速度判输入非法，补偿冻结在当前值（安全侧）。
  边界 Boundary      : ① 本件只出补偿偏移量 fCompOffsetMm，由上层叠加到位置设定；
                       ② 学习值信任来源为学习工序（头注释声明信任边界：学习值由
                       间隙学习流程写入，本件只做域闸不回写）；
                       ③ 除法前置域闸：fGapMaxMm <= 0、fFeedRateMmS <= 0 判组态非法；
                       ④ 换向死区 fZeroVelEpsMmS 防零速附近符号抖动（迟滞口径）；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / F_TRIG）
  溯源 Origin        : 道莅自研 clean-room（参考 t1-6-plcopen 运动接口分类与参数域，
                       零代码行复制；与 FB_DL_BacklashCompensator 分工：那件为通用
                       丝杠间隙查表补偿，本件为轴域反转沿 + 学习值注入闭环件）
  码位 Code          : 16#04_0_A8
  码表 Error codes（Motion 格 04_0_A8，单轨：故障 0x02A8 / 信息 0x01A8）:
    16#0004_02A8 故障级：组态非法（间隙上限/爬升速率 <= 0）或学习值越域冻结或
                 速度非有限，锁存至 bReset 上升沿
    16#0004_01A8 信息级：换向补偿注入完成沿（爬升到位拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 1 · 序号 5）
*)

TYPE E_DL_AbcState :
(
    eIdle  := 0,    // 空闲：未使能，补偿保持 / Idle, compensation held
    eRun   := 10,   // 运行：换向监视 + 补偿注入 / Running, reversal watch and injection
    eFault := 90    // 故障：组态/越域/非有限锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBacklashComp
VAR_INPUT
    bEnable       : BOOL;                  // 使能（电平），FALSE 时补偿保持 [-] / Enable
    bReset        : BOOL;                  // 上升沿清故障锁存 [-] / Reset edge
    fVelCmdMmS    : REAL;                  // 速度指令 [mm/s]，符号即方向 / Velocity command
    fLearnGapMm   : REAL;                  // 间隙学习值 [mm]，学习工序写入 / Learned backlash value
    fGapMaxMm     : REAL := 0.5;           // 学习值域上限 [mm] / Learned value ceiling
    fZeroVelEpsMmS: REAL := 1.0;           // 换向零速死区 [mm/s] / Reversal zero-speed deadband
    fFeedRateMmS  : REAL := 10.0;          // 补偿注入爬升速率 [mm/s] / Injection slew rate
    tCycle        : TIME := T#10MS;        // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fCompOffsetMm : REAL;                  // 补偿偏移量输出 [mm]，叠加到位置设定 / Compensation offset
    fGapUseMm     : REAL;                  // 生效学习值（域内钳用）[mm] / Effective learned gap
    bReversing    : BOOL;                  // 换向注入进行中电平 [-] / Reversal injection active
    bGapFrozen    : BOOL;                  // 学习值冻结标志 [-] / Learned value frozen flag
    eState        : E_DL_AbcState;         // 状态出口，段尾单点映射 / State outlet
    bError        : BOOL;                  // 故障锁存标志 [-] / Fault latch flag
    uErrId        : UDINT;                 // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset   : R_TRIG;                    // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtRevFwd  : R_TRIG;                    // 正向进入沿实例，段 0 无条件刷新 / Forward entry edge
    ftRevBwd  : F_TRIG;                    // 正向退出（反向进入）沿实例，段 0 无条件刷新 / Reverse entry edge
    _eState   : E_DL_AbcState := E_DL_AbcState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bDirPos  : BOOL;                      // 方向电平（迟滞后）[-] / Direction level with hysteresis
    _fTarget  : REAL;                      // 补偿目标偏移 [mm] / Compensation target
    _fStep    : REAL;                      // 本拍注入步长 [mm] / Injection step per scan
    _bDirSeen : BOOL;                      // 首个有效方向已建立标志 [-] / First direction established
    _bFault   : BOOL;                      // 故障锁存位（锁存量） / Latched fault bit
    _uFault   : UDINT;                     // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad  : BOOL;                      // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin  : BOOL;                      // 输入非有限当拍量 [-] / Non-finite input flag
    _bInjDone : BOOL;                      // 注入到位当拍量 [-] / Injection settled flag
    _bReversingCalc : BOOL;                // 换向注入进行中内部量 [-] / Reversal injection internal
END_VAR
VAR CONSTANT
    DL_TWO     : REAL := 2.0;              // 半程系数（两侧各分半）[无量纲] / Half factor
    DL_STEP_EPS: REAL := 1.0E-9;           // 注入到位判据 [mm] / Injection settled tolerance
    DL_ABS_MAX : REAL := 1.0E30;           // 有限值判定上界 [mm] / Finite value bound
    DL_ZERO    : REAL := 0.0;              // 零常量 [mm] / Zero constant
    DL_MS_PER_S: REAL := 1000.0;           // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset (CLK := bReset);
rtRevFwd(CLK := _bDirPos);
ftRevBwd(CLK := _bDirPos);

(* —— 段 1｜瞬时量预清零与周期换算（锁存量 _bFault/_uFault/fCompOffsetMm 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
_bInjDone := FALSE;
_bReversingCalc := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _eState := E_DL_AbcState.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与换算引脚） —— *)
IF (fGapMaxMm <= DL_ZERO) OR (fFeedRateMmS <= DL_ZERO) OR (fZeroVelEpsMmS <= DL_ZERO)
   OR (tCycle = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fVelCmdMmS <> fVelCmdMmS) OR ((fVelCmdMmS - fVelCmdMmS) <> DL_ZERO)
   OR (fLearnGapMm <> fLearnGapMm) OR ((fLearnGapMm - fLearnGapMm) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：三态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_AbcState.eIdle:
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        bGapFrozen := FALSE;
        fGapUseMm  := ABS(fLearnGapMm);  // 首次进入按当下学习值启用
        _bDirSeen  := FALSE;
        _eState    := E_DL_AbcState.eRun;
    ELSIF bEnable AND (_bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 // 故障级配对置位（R45）
        _uFault := 16#0004_02A8;
        bError  := TRUE;
        _eState := E_DL_AbcState.eFault;
    END_IF

E_DL_AbcState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_AbcState.eIdle;  // 使能撤销回空闲，补偿量保持
    ELSE
        (* 学习值域闸：越域即冻结沿用域内值，锁存告警 *)
        IF ABS(fLearnGapMm) > fGapMaxMm THEN
            bGapFrozen := TRUE;          // 冻结标志（锁存，复位沿解除）
            _bFault := TRUE;
            _uFault := 16#0004_02A8;
            bError  := TRUE;
            _eState := E_DL_AbcState.eFault;
        ELSE
            fGapUseMm := ABS(fLearnGapMm);   // 域内学习值照常更新
            bGapFrozen := FALSE;
        END_IF
        IF NOT _bFault THEN
            (* 换向判定：零速死区迟滞，防零速附近符号抖动 *)
            IF (NOT _bDirPos) AND (fVelCmdMmS > fZeroVelEpsMmS) THEN
                _bDirPos := TRUE;
                _bDirSeen := TRUE;
            ELSIF _bDirPos AND (fVelCmdMmS < -fZeroVelEpsMmS) THEN
                _bDirPos := FALSE;
                _bDirSeen := TRUE;
            END_IF
            IF _bDirSeen THEN
                IF _bDirPos THEN
                    _fTarget := fGapUseMm / DL_TWO;      // 正向：+半程
                ELSE
                    _fTarget := -fGapUseMm / DL_TWO;     // 反向：-半程
                END_IF
            ELSE
                _fTarget := DL_ZERO;     // 首方向未建立：目标归零
            END_IF
            (* 速率限幅注入：步长 = 速率 × 周期，不阶跃 *)
            _fStep := fFeedRateMmS * TIME_TO_REAL(tCycle) / DL_MS_PER_S;
            IF fCompOffsetMm < _fTarget THEN
                fCompOffsetMm := MIN(fCompOffsetMm + _fStep, _fTarget);
                _bReversingCalc := TRUE;
            ELSIF fCompOffsetMm > _fTarget THEN
                fCompOffsetMm := MAX(fCompOffsetMm - _fStep, _fTarget);
                _bReversingCalc := TRUE;
            ELSE
                _bInjDone := TRUE;       // 注入到位
            END_IF
            IF _bInjDone AND (rtRevFwd.Q OR ftRevBwd.Q) THEN
                uErrId := 16#0004_01A8;  // 信息级：换向注入完成沿
            END_IF
        END_IF
    END_IF

E_DL_AbcState.eFault:
    bError := TRUE;                      // 故障相驻留：补偿量冻结保持，只认复位沿（段 2 迁出）
    ;                                    // （冻结语义：fCompOffsetMm 保持最后值，安全侧不归零）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0004_02A8;
    bError  := TRUE;
    _eState := E_DL_AbcState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射（名实同源） —— *)
bReversing := _bReversingCalc;           // 换向注入电平同源赋值（R191）
eState := _eState;
END_FUNCTION_BLOCK
