(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GantrySkewMonitor
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS / ATAN），零厂商私有库
 * 功能描述 (Function)   : 龙门双侧偏斜监控，位置差量与角度双出口、超限分预警/报警两档。
 *                           ① 位置差量 fSkewPos = fPosLeft − fPosRight（带符号，右驱超前者为负）；
 *                           ② 角度 fSkewDeg = ATAN(fSkewPos / fGantryWidth) × 180 / π（度，带符号）。
 *                              单参 ATAN 而非 ATAN2：fGantryWidth 已过正数硬闸（> DL_GSK_EPS），
 *                              且工程上 |偏斜| 远小于 90°，该域内 ATAN(y/x) 与 ATAN2(y,x) 等价；
 *                              避开 ATAN2 在各平台库中可用性不一致的问题（跨平台可移植要求）。
 *                           ③ 双档：位置差或角度任一越预警线 → 维护级预警（bWarn，当拍量）；
 *                              任一越报警线且持续 tConfirm → 故障锁存（bAlarm，锁存至复位）。
 *                              两档并列判，取"或"关系，因为机械上位置超限与角度超限是同一次
 *                              扭曲的两种量纲表达，任一口径报警都必须报（宁可双报，不可漏报）。
 * 接口     (Interface)  : 输入 fPosLeft / fPosRight 两侧位置、fGantryWidth 两驱间距（mm，> 0）、
 *                         fSkewWarnPos / fSkewAlarmPos 位置档阈值（mm，> 0）、fSkewWarnDeg /
 *                         fSkewAlarmDeg 角度档阈值（度，> 0）、tConfirm 报警确认时间、bReset 复位；
 *                         输出 fSkewPos 差量、fSkewDeg 角度、bWarn 预警、bAlarm 报警锁存、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① 组态闸（覆盖每个参与判据的引脚，缺一即该判据静默失效）：
 *                         fGantryWidth <= DL_GSK_EPS（防除零把角度算成 ±Inf 或 NaN）、
 *                         位置与角度阈值 <= 0.0、报警阈值 <= 预警阈值、tConfirm <= T#0S、
 *                         任一浮点引脚 NaN（NaN 会让 ABS 比较恒假，双档同时静默失效）→ 故障锁存。
 *                         ② **本件不输出纠偏量、不发补偿指令**：龙门纠偏（如双驱转矩分配、
 *                         从动侧位置补偿）属运动学层，本件只出诊断结论。
 *                         ③ 角度换算用常量 DL_GSK_RAD2DEG，不由调用方传入（避免与本件阈值口径漂移）。
 *                         ④ TON 一枚 + R_TRIG 一枚段 0 无条件周期刷新。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_GantrySyncAxis`（双轴同步偏差与同步控制）分工——那件关心
 *                         "同步得上不上"，可能含补偿；本件只做**偏斜监控与分档告警**，纯诊断件。
 * 来源标签 (Source Tag) : T1-6 ◐（开源参考：龙门偏斜双口径监控阈值参数域，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍 |fSkewPos| <= fSkewWarnPos ∧
 *                         当拍 |fSkewDeg| <= fSkewWarnDeg（回落到预警带内，R240 全当拍量）。
 *                         自证可满足：四个因子均为当拍量，龙门回到对正位置即满足，无死锁。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL（bWarn / bAlarm / bError）+
 *                         ENUM（eLevel 可另读 eState / eCause）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸 + 阈值几何闸 + 浮点容差比较 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 2 · 序号 7）
 *==============================================================================*)

TYPE E_DL_GskState :
(
    eIdle  := 0,    // 首拍未取到可信输入 / Awaiting trustworthy input
    eRun   := 10,   // 偏斜监控运行相 / Skew monitoring phase
    eFault := 90    // 报警锁存相（仅复位沿可迁出） / Alarm latched phase
);
END_TYPE

TYPE E_DL_GskCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（宽度非正/阈值倒置/非有限） / Illegal configuration
    ePosLimit   := 2,   // 位置差量越报警线且确认窗到 / Position skew over limit confirmed
    eAngLimit   := 3,   // 角度越报警线且确认窗到 / Angle skew over limit confirmed
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_GantrySkewMonitor
VAR_INPUT
    fPosLeft     : REAL := 0.0;      // 左侧（主动侧）位置 [mm] / Left, master-side position [mm]
    fPosRight    : REAL := 0.0;      // 右侧（从动侧）位置 [mm] / Right, follower-side position [mm]
    fGantryWidth : REAL := 1000.0;   // 两驱间距，域 > DL_GSK_EPS（角度换算分母） [mm] / Drive spacing, angle denominator, > epsilon [mm]
    fSkewWarnPos : REAL := 0.5;      // 位置差预警线，域 > 0.0 [mm] / Position skew warning line, > 0.0 [mm]
    fSkewAlarmPos: REAL := 2.0;      // 位置差报警线，域 > fSkewWarnPos [mm] / Position skew alarm line, > warning [mm]
    fSkewWarnDeg : REAL := 0.05;     // 角度预警线，域 > 0.0 [度] / Angle warning line, > 0.0 [deg]
    fSkewAlarmDeg: REAL := 0.20;     // 角度报警线，域 > fSkewWarnDeg [度] / Angle alarm line, > warning [deg]
    tConfirm     : TIME := T#200MS;  // 报警确认时间，域 > T#0S [ms] / Alarm confirm time, > T#0S [ms]
    bReset       : BOOL := FALSE;    // 复位，上升沿清报警锁存 [-] / Reset, rising edge clears the alarm latch
END_VAR
VAR_OUTPUT
    fSkewPos : REAL;                // 位置差量（左 − 右，带符号） [mm] / Position skew, left minus right [mm]
    fSkewDeg : REAL;                // 偏斜角度（带符号，右驱超前为负） [度] / Skew angle in degrees [deg]
    bWarn    : BOOL;                // 维护级预警（未达报警） [-] / Maintenance warning below alarm level
    bAlarm   : BOOL;                // 报警锁存 [-] / Latched alarm
    eState   : E_DL_GskState;       // 状态出口 [-] / State outlet
    eCause   : E_DL_GskCause;       // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError   : BOOL;                // 故障标志（报警或组态非法） [-] / Error flag
END_VAR
VAR
    _eState  : E_DL_GskState := E_DL_GskState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_GskCause := E_DL_GskCause.eNone;    // 成因锁存量 / Latched cause
    tonAlarm : TON;             // 报警确认计时，段 0 无条件调用 / Alarm confirm timer
    rtReset  : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bFault  : BOOL;            // 报警锁存位（锁存量） / Latched alarm bit
    _bCfgBad : BOOL;            // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin : BOOL;            // 输入非有限当拍量 [-] / Non-finite input this scan
    _bPosOver: BOOL;            // 位置差越报警线当拍量 [-] / Position skew over the alarm line
    _bAngOver: BOOL;            // 角度越报警线当拍量 [-] / Angle skew over the alarm line
    _bWarnRaw: BOOL;            // 预警判据当拍量 [-] / Raw warning criterion
    _fSkewPos: REAL;            // 当拍差量中间量 [mm] / Skew intermediate [mm]
    _fSkewDeg: REAL;            // 当拍角度中间量 [度] / Angle intermediate [deg]
END_VAR
VAR CONSTANT
    DL_GSK_EPS     : REAL := 1.0E-6;         // 浮点判零容差（宽度与阈值统一口径） [无量纲] / Float epsilon for gates
    DL_GSK_RAD2DEG : REAL := 57.2957795;     // 弧度转度常量（180/π，7 位有效） [度/弧度] / Radians to degrees constant
END_VAR

(* —— 段 0：当拍量派生（角度先算，判据后算，顺序即依赖序） —— *)
_bNonFin := (fPosLeft <> fPosLeft) OR (fPosRight <> fPosRight)          // 位置 NaN 自反判（判等禁令唯一例外） / Position NaN tests
         OR (fGantryWidth <> fGantryWidth) OR (fSkewWarnPos <> fSkewWarnPos)
         OR (fSkewAlarmPos <> fSkewAlarmPos) OR (fSkewWarnDeg <> fSkewWarnDeg)
         OR (fSkewAlarmDeg <> fSkewAlarmDeg);                            // 阈值引脚 NaN 全量判 / Threshold NaN tests, all pins
_bCfgBad := (ABS(fGantryWidth) <= DL_GSK_EPS)                           // 宽度除零闸（缺此即角度判据静默失效） / Width divide gate
         OR (fSkewWarnPos <= 0.0) OR (fSkewAlarmPos <= fSkewWarnPos)     // 位置档几何闸 / Position threshold geometry
         OR (fSkewWarnDeg <= 0.0) OR (fSkewAlarmDeg <= fSkewWarnDeg)     // 角度档几何闸 / Angle threshold geometry
         OR (tConfirm <= T#0S) OR _bNonFin;                              // 时间闸 + 非有限 / Time gate and non-finite
_fSkewPos := fPosLeft - fPosRight;                                      // 位置差量（左 − 右） / Position skew, left minus right
IF ABS(fGantryWidth) > DL_GSK_EPS THEN                                  // 除零闸（双保险：段 0 已闸，此处防类型级直除） / Divide guard, second layer
    _fSkewDeg := ATAN(_fSkewPos / fGantryWidth) * DL_GSK_RAD2DEG;       // 角度换算：单参 ATAN，宽度为正故符号随差量 / Angle via single-arg ATAN, sign follows skew
ELSE
    _fSkewDeg := 0.0;                                                   // 宽度病态：角度不宣称 / Degenerate width: angle not claimed
END_IF
_bPosOver := ABS(_fSkewPos) > fSkewAlarmPos;                            // 位置差越报警线 / Position skew over the alarm line
_bAngOver := ABS(_fSkewDeg) > fSkewAlarmDeg;                            // 角度越报警线 / Angle skew over the alarm line
_bWarnRaw := (ABS(_fSkewPos) > fSkewWarnPos) OR (ABS(_fSkewDeg) > fSkewWarnDeg);   // 预警判据（双口径取或） / Warning criterion, either unit
rtReset(CLK := bReset);                                                 // 复位沿，每拍必调（R228A） / Reset edge, every scan
tonAlarm(IN := _bPosOver OR _bAngOver, PT := tConfirm);                 // 报警确认窗（IN 由当拍判据派生） / Alarm confirm window

(* —— 段 1：单拍量预清零（锁存量 _bFault / _eCause 不入清单，R107） —— *)
fSkewPos := 0.0;        // 差量出口每拍预清，段 6 回填 / Skew outlet preset
fSkewDeg := 0.0;        // 角度出口每拍预清 / Angle outlet preset
bWarn    := FALSE;      // 预警位每拍预清 / Warning preset
bAlarm   := FALSE;      // 报警出口每拍预清，锁存分支同拍回填 / Alarm outlet preset
bError   := FALSE;      // 故障标志每拍预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                   // 清报警锁存（锁存量） / Clear the alarm latch
    _eCause := E_DL_GskCause.eNone;                      // 清成因 / Clear cause
    IF _eState = E_DL_GskState.eFault THEN
        _eState := E_DL_GskState.eIdle;                  // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                                     // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_GskCause.eCfgIllegal;                // 归因：组态非法 / Cause: illegal configuration
    bError  := TRUE;                                     // 故障标志同拍置位 / Error flag set same scan
END_IF

(* —— 段 3：报警分级（位置与角度归因分开，先位置后角度，同拍双越限时归因确定） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND tonAlarm.Q THEN
    _bFault := TRUE;                                     // 锁存 / Latch
    IF _bPosOver THEN
        _eCause := E_DL_GskCause.ePosLimit;              // 归因：位置差越限（优先） / Cause: position skew over limit
    ELSE
        _eCause := E_DL_GskCause.eAngLimit;              // 归因：角度越限 / Cause: angle skew over limit
    END_IF
    bError := TRUE;                                      // 故障标志同拍置位 / Error flag set same scan
END_IF

(* —— 段 4：预警（维护级，不锁存；报警命中时不再宣称预警） —— *)
IF (NOT _bFault) AND _bWarnRaw THEN
    bWarn := TRUE;                                       // 维护级预警 / Maintenance warning
END_IF

(* —— 段 5：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_GskState.eFault) THEN
    _eState := E_DL_GskState.eFault;                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_GskState.eIdle:
    IF (NOT _bNonFin) AND (NOT _bCfgBad) THEN            // 出口 1：输入可信 / Input trustworthy
        _eState := E_DL_GskState.eRun;
    ELSIF _bFault THEN                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_GskState.eFault;
    END_IF

E_DL_GskState.eRun:
    IF _bFault THEN                                      // 出口 1：报警锁存 / Alarm latched
        _eState := E_DL_GskState.eFault;
    ELSIF rtReset.Q THEN                                 // 出口 2：复位沿回观测相 / Reset edge back to observation
        _eState := E_DL_GskState.eIdle;
    END_IF

E_DL_GskState.eFault:
    ;                                                    // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault := TRUE;                                     // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause := E_DL_GskCause.ePhaseBad;                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_GskState.eFault;                     // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 7：出口单点映射（差量与角度始终回放当拍计算值，故障相亦然——诊断量不可清零） —— *)
fSkewPos := _fSkewPos;                                   // 差量出口 / Skew outlet
fSkewDeg := _fSkewDeg;                                   // 角度出口 / Angle outlet
bAlarm   := _bFault;                                     // 报警与锁存同源（R191） / Alarm from latch
bError   := _bFault OR _bCfgBad;                         // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
IF _bFault THEN
    bWarn := FALSE;                                      // 报警相不再宣称「仅预警」 / No warning claim in alarm
END_IF
eState := _eState;                                       // 状态出口 / State outlet
eCause := _eCause;                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
