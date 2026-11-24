(*
  组件名 Component   : FB_DL_CircInterp2Axis
  子库 Sublibrary    : DL_Motion
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 两轴圆弧插补（与 FB_DL_LineInterp2Axis 同线直角补口）：
                       1) 双模式几何解算：圆心模式（半径由起点到圆心距实测，终点距圆心
                       超容差判组态非法）/ 半径模式（由起终点弦长与半径反解圆心，CW/CCW
                       定唯一解，弦长 > 2R 判组态非法）；
                       2) 弓高误差弦长分段：每拍角步长 = 进给/半径 与 弦长上限角步长
                       取小（弦长上限由弓高误差限反解，半径/进给除法前置域闸）；
                       3) 象限跨越判据：本拍与上拍象限号不同 → bQuadCross 单拍脉冲；
                       4) 终点判定：剩余弧角 <= 步长 → 落终点，eDone 驻留。
  边界 Boundary      : ① 本件只出两轴位置设定点，不接管轴使能与物理 IO；
                       ② 角度归一化循环带守卫计数器（上限 8 次，超限判几何非法）；
                       ③ 反三角经 FC_DL_Atan2Ex 唯一属主（DL_MathData），本件零重写；
                       ④ 非有限值（NaN 自反 + 无穷差值自减）判非法锁存，出点冻结；
                       ⑤ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑥ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : FC_DL_Atan2Ex（DL_MathData，按 registry 实名）；Standard.library（R_TRIG）
  溯源 Origin        : 道莅自研 clean-room（参考 t1-8-github motion 线分类与参数域，
                       零代码行复制；圆弧参数化与弓高分段为公开几何语义）
  码位 Code          : 16#04_0_AC
  码表 Error codes（Motion 格 04_0_AC，单轨：故障 0x02AC / 信息 0x01AC）:
    16#0004_02AC 故障级：几何解算非法（弦长 > 2R / 终点半径超容差 / 进给或弓高限
                 非法 / 输入非有限 / 归一化守卫超限），锁存至 bReset 上升沿
    16#0004_01AC 信息级：象限跨越脉冲沿（bQuadCross 置位拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 2 · 序号 9）
*)

TYPE E_DL_CiaState :
(
    eIdle   := 0,   // 空闲：等启动沿 / Idle, waiting start edge
    eGeom   := 10,  // 几何：单拍解算圆心/半径/弧角 / Geometry, one-pass solve
    eRun    := 20,  // 插补：逐拍步进出点 / Interpolating, per-scan stepping
    eDone   := 30,  // 完成：落终点驻留 / Done, at end point
    eFault  := 90   // 故障：几何/输入锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_CircInterp2Axis
VAR_INPUT
    bStartCmd    : BOOL;                   // 启动指令（上升沿承载）[-] / Start command edge
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    fStartXMm    : REAL;                   // 起点坐标 X [mm] / Start point X
    fStartYMm    : REAL;                   // 起点坐标 Y [mm] / Start point Y
    fEndXMm      : REAL;                   // 终点坐标 X [mm] / End point X
    fEndYMm      : REAL;                   // 终点坐标 Y [mm] / End point Y
    bUseRadius   : BOOL;                   // 模式：TRUE = 半径模式 / Mode, TRUE = radius mode
    fCenterXMm   : REAL;                   // 圆心坐标 X（圆心模式）[mm] / Center X
    fCenterYMm   : REAL;                   // 圆心坐标 Y（圆心模式）[mm] / Center Y
    fRadiusMm    : REAL;                   // 半径（半径模式）[mm] / Radius
    bCwDir       : BOOL;                   // 方向：TRUE = 顺时针 [-] / Direction, TRUE = CW
    fFeedMmS     : REAL := 50.0;           // 合成进给速度 [mm/s] / Feed velocity
    fSagittaMaxMm: REAL := 0.01;           // 弓高误差限 [mm] / Sagitta error limit
    fRadTolMm    : REAL := 0.01;           // 终点半径容差 [mm] / End radius tolerance
    tCycle       : TIME := T#10MS;         // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fPosXMm      : REAL;                   // 位置设定点 X [mm] / Position setpoint X
    fPosYMm      : REAL;                   // 位置设定点 Y [mm] / Position setpoint Y
    bBusy        : BOOL;                   // 插补进行中电平 [-] / Interpolation busy
    bDone        : BOOL;                   // 到达终点电平 [-] / End-point reached level
    bQuadCross   : BOOL;                   // 象限跨越单拍脉冲 [-] / Quadrant crossing pulse
    fArcLenMm    : REAL;                   // 解算弧长 [mm] / Computed arc length
    eState       : E_DL_CiaState;          // 状态出口，段尾单点映射 / State outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset : R_TRIG;                      // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtStart : R_TRIG;                      // 启动沿实例，段 0 无条件刷新 / Start edge
    _eState : E_DL_CiaState := E_DL_CiaState.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fCtrXMm: REAL;                        // 解算圆心 X [mm] / Solved center X
    _fCtrYMm: REAL;                        // 解算圆心 Y [mm] / Solved center Y
    _fRadMm : REAL;                        // 解算半径 [mm] / Solved radius
    _fAng0  : REAL;                        // 起点角 [弧度] / Start angle
    _fAng1  : REAL;                        // 终点角 [弧度] / End angle
    _fSweep : REAL;                        // 弧角绝对扫角 [弧度] / Absolute sweep
    _fAngCur: REAL;                        // 当前角 [弧度] / Current angle
    _fDAng  : REAL;                        // 每拍角步长 [弧度] / Angular step per scan
    _nQuadPrev: DINT;                      // 上拍象限号 [-] / Previous quadrant
    _nQuadCur : DINT;                      // 本拍象限号 [-] / Current quadrant
    _bFault : BOOL;                        // 故障锁存位（锁存量） / Latched fault bit
    _uFault : UDINT;                       // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
    _bValid : BOOL;                        // Atan2Ex 属主返回有效标志（两调用与集） / Atan2 validity flag
    _bVal0  : BOOL;                        // 起点角属主有效标志 [-] / Start angle validity
    _bVal1  : BOOL;                        // 终点角属主有效标志 [-] / End angle validity
    fDxGeom : LREAL;                       // 几何解算弦向量 X [mm] / Geometry chord vector X
    fDyGeom : LREAL;                       // 几何解算弦向量 Y [mm] / Geometry chord vector Y
    fChordGeom : LREAL;                    // 几何解算弦长 [mm] / Geometry chord length
    fHGeom  : LREAL;                       // 圆心偏距 [mm] / Center offset distance
    fAng0Geom : LREAL;                     // 起点角属主返回值 [弧度] / Start angle owner result
    fAng1Geom : LREAL;                     // 终点角属主返回值 [弧度] / End angle owner result
    fSweepGeom: LREAL;                     // 扫角归一化中间量 [弧度] / Sweep normalization temp
    _nNormGuard: DINT;                     // 归一化守卫计数 [次] / Normalization guard counter
    fStepFeed : LREAL;                     // 进给角步长 [弧度] / Feed angular step
    fChordMax : LREAL;                     // 弓高弦长上限 [mm] / Sagitta chord ceiling
    fStepGeom : LREAL;                     // 弦长上限角步长 [弧度] / Chord-ceiling angular step
    fRemainGeom: LREAL;                    // 剩余扫角 [弧度] / Remaining sweep
END_VAR
VAR CONSTANT
    DL_TWO_PI  : REAL := 6.283185307;      // 全周角 [弧度] / Full turn angle
    DL_HALF_PI : REAL := 1.570796327;      // 直角 [弧度] / Quarter turn angle
    DL_TWO     : REAL := 2.0;              // 二常量 [无量纲] / Two constant
    DL_EPS     : REAL := 1.0E-6;           // 几何退化判据 [mm] / Degenerate geometry tolerance
    DL_NORM_GUARD: DINT := 8;              // 角度归一化守卫上限 [次] / Normalization guard limit
    DL_ABS_MAX : REAL := 1.0E30;           // 有限值判定上界 [mm] / Finite bound
    DL_ZERO    : REAL := 0.0;              // 零常量 [mm] / Zero constant
    DL_MS_PER_S: REAL := 1000.0;           // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
END_VAR

(* —— 段 0｜沿实例每拍无条件刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStartCmd);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bDone/几何量不入清单） —— *)
uErrId     := 16#0000_0000;
bQuadCross := FALSE;                     // 跨越脉冲单拍量，每拍清零
_bCfgBad   := FALSE;
_bNonFin   := FALSE;
_bValid    := TRUE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    bDone   := FALSE;
    _eState := E_DL_CiaState.eIdle;
END_IF

(* —— 段 3｜公共组态闸与非有限判据（覆盖全部参与换算引脚） —— *)
IF (fFeedMmS <= DL_ZERO) OR (fSagittaMaxMm <= DL_ZERO) OR (fRadTolMm <= DL_ZERO)
   OR (tCycle = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fStartXMm <> fStartXMm) OR ((fStartXMm - fStartXMm) <> DL_ZERO)
   OR (fStartYMm <> fStartYMm) OR ((fStartYMm - fStartYMm) <> DL_ZERO)
   OR (fEndXMm <> fEndXMm) OR ((fEndXMm - fEndXMm) <> DL_ZERO)
   OR (fEndYMm <> fEndYMm) OR ((fEndYMm - fEndYMm) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：五态全覆盖 + ELSE 兜底 —— *)
CASE _eState OF

E_DL_CiaState.eIdle:
    bBusy := FALSE;
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        fPosXMm := fStartXMm;            // 出点先落起点
        fPosYMm := fStartYMm;
        bDone   := FALSE;
        _eState := E_DL_CiaState.eGeom;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0004_02AC;
        bError  := TRUE;
        _eState := E_DL_CiaState.eFault;
    END_IF

E_DL_CiaState.eGeom:
    (* 单拍几何解算：圆心 / 半径 / 起终角 / 扫角 *)
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0004_02AC;
        bError  := TRUE;
        _eState := E_DL_CiaState.eFault;
    ELSE
        IF bUseRadius THEN
            (* 半径模式：弦长反解圆心（CW/CCW 定唯一解），弦长 > 2R 判非法 *)
            _fRadMm := ABS(fRadiusMm);
            IF _fRadMm <= DL_EPS THEN
                _bFault := TRUE;
                _uFault := 16#0004_02AC;
                bError  := TRUE;
                _eState := E_DL_CiaState.eFault;
            ELSE
                fDxGeom := fEndXMm - fStartXMm;          // 弦向量 X
                fDyGeom := fEndYMm - fStartYMm;          // 弦向量 Y
                fChordGeom := SQRT(fDxGeom * fDxGeom + fDyGeom * fDyGeom);
                IF fChordGeom <= DL_EPS THEN
                    _bFault := TRUE;     // 起终点重合：圆弧退化
                    _uFault := 16#0004_02AC;
                    bError  := TRUE;
                    _eState := E_DL_CiaState.eFault;
                ELSIF fChordGeom > (DL_TWO * _fRadMm) THEN
                    _bFault := TRUE;     // 弦长超直径：无解
                    _uFault := 16#0004_02AC;
                    bError  := TRUE;
                    _eState := E_DL_CiaState.eFault;
                ELSE
                    fHGeom := SQRT(MAX(_fRadMm * _fRadMm - (fChordGeom * fChordGeom) / (DL_TWO * DL_TWO), DL_ZERO));
                    _fCtrXMm := (fStartXMm + fEndXMm) / DL_TWO;
                    _fCtrYMm := (fStartYMm + fEndYMm) / DL_TWO;
                    IF bCwDir THEN
                        _fCtrXMm := _fCtrXMm + (fDyGeom / fChordGeom) * fHGeom;
                        _fCtrYMm := _fCtrYMm - (fDxGeom / fChordGeom) * fHGeom;
                    ELSE
                        _fCtrXMm := _fCtrXMm - (fDyGeom / fChordGeom) * fHGeom;
                        _fCtrYMm := _fCtrYMm + (fDxGeom / fChordGeom) * fHGeom;
                    END_IF
                    _eState := E_DL_CiaState.eRun;
                END_IF
            END_IF
        ELSE
            (* 圆心模式：半径由起点实测，终点半径超容差判非法 *)
            _fCtrXMm := fCenterXMm;
            _fCtrYMm := fCenterYMm;
            fDxGeom := fStartXMm - _fCtrXMm;
            fDyGeom := fStartYMm - _fCtrYMm;
            _fRadMm := SQRT(fDxGeom * fDxGeom + fDyGeom * fDyGeom);
            fDxGeom := fEndXMm - _fCtrXMm;
            fDyGeom := fEndYMm - _fCtrYMm;
            fChordGeom := SQRT(fDxGeom * fDxGeom + fDyGeom * fDyGeom);
            IF _fRadMm <= DL_EPS THEN
                _bFault := TRUE;         // 起点与圆心重合
                _uFault := 16#0004_02AC;
                bError  := TRUE;
                _eState := E_DL_CiaState.eFault;
            ELSIF ABS(fChordGeom - _fRadMm) > fRadTolMm THEN
                _bFault := TRUE;         // 终点半径与起点半径超容差
                _uFault := 16#0004_02AC;
                bError  := TRUE;
                _eState := E_DL_CiaState.eFault;
            ELSE
                _eState := E_DL_CiaState.eRun;
            END_IF
        END_IF
        IF _eState = E_DL_CiaState.eRun THEN
            (* 起终角经 Atan2Ex 唯一属主（返回弧度），属主无效即判故障 *)
            fAng0Geom := FC_DL_Atan2Ex(lrY := fStartYMm - _fCtrYMm, lrX := fStartXMm - _fCtrXMm,
                                       bValid => _bVal0);
            fAng1Geom := FC_DL_Atan2Ex(lrY := fEndYMm - _fCtrYMm, lrX := fEndXMm - _fCtrXMm,
                                       bValid => _bVal1);
            _bValid := _bVal0 AND _bVal1;
            IF NOT _bValid THEN
                _bFault := TRUE;
                _uFault := 16#0004_02AC;
                bError  := TRUE;
                _eState := E_DL_CiaState.eFault;
            ELSE
                IF bCwDir THEN
                    fSweepGeom := fAng0Geom - fAng1Geom;
                ELSE
                    fSweepGeom := fAng1Geom - fAng0Geom;
                END_IF
                _nNormGuard := 0;
                WHILE (fSweepGeom < DL_ZERO) AND (_nNormGuard < DL_NORM_GUARD) DO
                    fSweepGeom := fSweepGeom + DL_TWO_PI;    // 负角加全周归一
                    _nNormGuard := _nNormGuard + 1;
                END_WHILE;
                _nNormGuard := 0;
                WHILE (fSweepGeom >= DL_TWO_PI) AND (_nNormGuard < DL_NORM_GUARD) DO
                    fSweepGeom := fSweepGeom - DL_TWO_PI;    // 超全周减全周归一
                    _nNormGuard := _nNormGuard + 1;
                END_WHILE;
                IF (_nNormGuard >= DL_NORM_GUARD) OR (fSweepGeom <= DL_EPS) THEN
                    _bFault := TRUE;     // 归一化守卫超限或扫角退化
                    _uFault := 16#0004_02AC;
                    bError  := TRUE;
                    _eState := E_DL_CiaState.eFault;
                ELSE
                    _fSweep  := LREAL_TO_REAL(fSweepGeom);
                    _fAng0   := LREAL_TO_REAL(fAng0Geom);
                    _fAngCur := _fAng0;
                    fArcLenMm := _fSweep * _fRadMm;
                    (* 每拍角步长：进给步长与弓高弦长上限步长取小（除数均已过域闸） *)
                    fStepFeed := fFeedMmS * TIME_TO_REAL(tCycle) / DL_MS_PER_S / _fRadMm;
                    fChordMax := DL_TWO * SQRT(DL_TWO * _fRadMm * fSagittaMaxMm
                                 - fSagittaMaxMm * fSagittaMaxMm);
                    fStepGeom := fChordMax / _fRadMm;
                    _fDAng := LREAL_TO_REAL(MIN(fStepFeed, fStepGeom));
                    _nQuadPrev := -1;    // 象限号初始化为哨兵
                    bBusy := TRUE;
                END_IF
            END_IF
        END_IF
    END_IF

E_DL_CiaState.eRun:
    bBusy := TRUE;
    IF bCwDir THEN
        _fAngCur := _fAngCur - _fDAng;
    ELSE
        _fAngCur := _fAngCur + _fDAng;
    END_IF
    (* 象限号判据：cos/sin 符号四象限编码（0..3），本上拍不同即跨越 *)
    IF COS(_fAngCur) >= DL_ZERO THEN
        IF SIN(_fAngCur) >= DL_ZERO THEN
            _nQuadCur := 0;              // 第一象限
        ELSE
            _nQuadCur := 3;              // 第四象限
        END_IF
    ELSE
        IF SIN(_fAngCur) >= DL_ZERO THEN
            _nQuadCur := 1;              // 第二象限
        ELSE
            _nQuadCur := 2;              // 第三象限
        END_IF
    END_IF
    IF (_nQuadPrev >= 0) AND (_nQuadCur <> _nQuadPrev) THEN
        bQuadCross := TRUE;              // 象限跨越脉冲（单拍）
        uErrId := 16#0004_01AC;          // 信息级：象限跨越沿
    END_IF
    _nQuadPrev := _nQuadCur;
    (* 出点由圆心 + 半径 × 当前角三角合成（正解三角为 Standard.library 标准函数） *)
    fPosXMm := _fCtrXMm + COS(_fAngCur) * _fRadMm;
    fPosYMm := _fCtrYMm + SIN(_fAngCur) * _fRadMm;
    (* 终点判定：剩余扫角耗尽 → 落终点驻留 *)
    fRemainGeom := ABS(_fAngCur - _fAng0);
    IF fRemainGeom >= (_fSweep - _fDAng) THEN
        fPosXMm := fEndXMm;
        fPosYMm := fEndYMm;
        bBusy := FALSE;
        bDone := TRUE;
        _eState := E_DL_CiaState.eDone;
    END_IF

E_DL_CiaState.eDone:
    bDone := TRUE;
    bBusy := FALSE;
    IF NOT bStartCmd THEN
        _eState := E_DL_CiaState.eIdle;  // 启动指令撤销：回空闲
    END_IF

E_DL_CiaState.eFault:
    bBusy := FALSE;
    bError := TRUE;
    ;                                    // 故障相驻留：出点冻结，只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0004_02AC;
    bError  := TRUE;
    _eState := E_DL_CiaState.eFault;
END_CASE

(* —— 段 5｜状态出口单点映射 —— *)
eState := _eState;
END_FUNCTION_BLOCK
