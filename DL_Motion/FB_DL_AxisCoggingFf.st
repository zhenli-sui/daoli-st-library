(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisCoggingFf
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 齿槽转矩前馈（按角度周期查表注入）。
 *                         把机械角等分成 72 个扇区（每扇区 5°），表内每格存该角度位置的补偿量；
 *                         运行时按当前角度取格、乘增益、限幅后以转矩前馈输出（% 额定）。
 *                         **学习与注入分离**（互斥锁存）：
 *                           注入态（bInjectEnable）：只读表 + 输出前馈，绝不改表；
 *                           学习态（bLearnEnable） ：只按"实测转矩指令"缓慢更新表内一格，绝不输出前馈；
 *                           两者同拍为真 → 锁存 eLearnConflict 并**两态全停**（既不改表也不输出），
 *                           避免"边学边补"形成正反馈自激。
 *                         三条固化纪律：
 *                           ① **相位取模防越界**：索引由角度除法取整后对 72 取模，负角再补 72，
 *                              结果恒落 0..71；角度非有限或超 ±1E6 度时当拍不判（防整数转换溢出）；
 *                           ② **注入限幅**：输出钳 ±fFfMaxPct，学习后的表格值同样钳在 ±fTableMaxPct；
 *                           ③ **学习率域闸**：fLearnRate 须在 (0, 1] 内，越域即锁存 eCfgIllegal
 *                              （大于 1 的学习率会使表格发散）。
 *                         验收向量：
 *                           ① 角度 0° → 索引 0；角度 5° → 索引 1；角度 355° → 索引 71
 *                           ② 角度 −5° → 索引 71（负角补模）
 *                           ③ 表[0] = 2.0 %、增益 1.0、限幅 5.0 → 前馈 2.0 %
 *                           ④ bInjectEnable 与 bLearnEnable 同拍为真 → eLearnConflict 锁存，输出 0
 * 接口     (Interface)  : 入 fAngleDeg 反馈机械角、bInjectEnable 注入使能、bLearnEnable 学习使能、
 *                         fTorqueRefPct 实测转矩（学习用观测值）、fFfGain 前馈增益、fFfMaxPct 注入限幅、
 *                         fTableMaxPct 表格值限幅、fLearnRate 学习率、bClear 清表沿、bReset 复位沿；
 *                         出 fFfOutPct 转矩前馈输出、iTableIdx 当前表索引（0..71）、bInjecting 注入中、
 *                         bLearning 学习中、bLearnConflict 学/注冲突锁存、bValid 输出有效、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"角度周期前馈注入与表学习"，不输出位置/速度指令、
 *                         不参与轴使能与故障处理**——与 `FB_DL_AxisFrictionFf` 的分工：齿槽转矩是角度的
 *                         周期函数，摩擦转矩是速度的函数，两表互不替代（R47 边界声明）；
 *                         ② **状态枚举禁定义**：本件不引用任何轴状态枚举（R277），只消费角度引脚；
 *                         ③ **索引边界**：72 格字面量上界（R104），取模后恒在域内，另设显式钳位二次闸；
 *                         ④ **非有限闸**：角度/观测转矩非有限 → 当拍不判、不宣称（不锁存）；
 *                         ⑤ **锁存解除式**：bLearnConflict 与 eFault 仅由 bReset 上升沿解除（R228B），
 *                         bReset 为外部引脚、恒可达；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"齿槽转矩前馈"。不接管：摩擦前馈（属 FB_DL_AxisFrictionFf）、
 *                         反向间隙辨识（属 FB_DL_AxisBacklashIdent）、转矩环整定（属驱动侧）。
 * 来源标签 (Source Tag) : 自研线（与 AxisFrictionFf 成族）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 取模 + 显式钳位 + 双限幅 + 学习率域闸 + 非有限闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ 两 R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 4 · 序号 20）
 *==============================================================================*)

TYPE E_DL_AcgState :
(
    eIdle  := 0,    // 待机相（两态皆关，输出 0） / Idle, both modes off, zero output
    eInject:= 10,   // 注入相（只读表输出前馈） / Injecting, table read only
    eLearn := 20,   // 学习相（只更新表，无输出） / Learning, table update only
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_AcgCause :
(
    eNone         := 0,   // 无异常 / No anomaly
    eCfgIllegal   := 1,   // 组态非法（学习率/限幅越域） / Illegal configuration
    eLearnConflict:= 2,   // 学习与注入同拍（锁存，两态全停） / Learn and inject together, latched
    eAngleBad     := 3,   // 角度非有限或超域（当拍不判） / Angle invalid, skipped this scan
    ePhaseBad     := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisCoggingFf
VAR_INPUT
    fAngleDeg    : LREAL := 0.0;      // 反馈机械角（可正可负） [°] / Feedback mechanical angle [°]
    bInjectEnable: BOOL := FALSE;     // 注入使能（只读表） [-] / Injection enable, table read only
    bLearnEnable : BOOL := FALSE;     // 学习使能（只改表） [-] / Learning enable, table write only
    fTorqueRefPct: LREAL := 0.0;      // 实测转矩（学习观测值） [% 额定] / Measured torque for learning [% rated]
    fFfGain      : LREAL := 1.0;      // 前馈增益，域 ≥ 0 [-] / Feed-forward gain, >= 0
    fFfMaxPct    : LREAL := 20.0;     // 注入限幅，域 > 0 [% 额定] / Injection clamp, > 0
    fTableMaxPct : LREAL := 30.0;     // 表格值限幅，域 > 0 [% 额定] / Table-value clamp, > 0
    fLearnRate   : LREAL := 0.01;     // 学习率，域 (0, 1] [-] / Learning rate, within (0, 1]
    bClear       : BOOL := FALSE;     // 清表沿（表格全置 0） [-] / Table-clear edge
    bReset       : BOOL := FALSE;     // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    fFfOutPct    : LREAL := 0.0;                          // 转矩前馈输出（已限幅） [% 额定] / Feed-forward output, clamped
    iTableIdx    : INT := 0;                              // 当前表索引（0..71） [-] / Present table index
    bInjecting   : BOOL := FALSE;                         // 注入中 [-] / Injecting
    bLearning    : BOOL := FALSE;                         // 学习中 [-] / Learning
    bLearnConflict : BOOL := FALSE;                       // 学/注冲突锁存（等复位） [-] / Learn-inject conflict, latched
    bValid       : BOOL := FALSE;                         // 输出有效（角度有效且注入态） [-] / Output valid
    eState       : E_DL_AcgState := E_DL_AcgState.eIdle;  // 相出口 [-] / Phase outlet
    eCause       : E_DL_AcgCause := E_DL_AcgCause.eNone;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError       : BOOL := FALSE;                         // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_AcgState := E_DL_AcgState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_AcgCause := E_DL_AcgCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bConf    : BOOL := FALSE;                           // 学/注冲突锁存位 / Latched conflict bit
    _iIdx     : INT := 0;                                // 归一后的表索引（0..71） [-] / Normalised table index
    _iRaw     : INT := 0;                                // 取模前的索引 [-] / Index before normalisation
    _fOut     : LREAL := 0.0;                            // 输出工作值 [% 额定] / Output working value
    _fCell    : LREAL := 0.0;                            // 当格补偿量 [% 额定] / Cell compensation value
    _bAngOk   : BOOL := FALSE;                           // 角度有效性结论 / Angle validity result
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _i        : INT := 0;                                // 清表循环下标 / Clear-loop index
    rtClear   : R_TRIG;                                  // 清表沿实例，段 0 无条件调用 / Clear edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
    afTable   : ARRAY[0..71] OF LREAL;                   // 齿槽补偿表（72 格 = 5°/格，字面量上界） [% 额定] / Cogging table
END_VAR
VAR CONSTANT
    DL_ACG_NBINS   : INT := 72;          // 表格数（与数组字面量上界同源） [格] / Table bin count
    DL_ACG_BIN_DEG : LREAL := 5.0;       // 每格角度宽（360/72） [°] / Bin width in degrees
    DL_ACG_ANG_MAX : LREAL := 1000000.0; // 角度绝对值上限（防实数转整数溢出） [°] / Angle magnitude limit
    DL_ACG_EPS     : LREAL := 1.0E-12;   // 浮点判等容差 [-] / Equality tolerance
END_VAR

(* —— 段 0：组态闸 + 两沿无条件周期刷新（R228A；本件无 TON） —— *)
_bCfgBad := (fLearnRate <= 0.0) OR (fLearnRate > 1.0)                 // 学习率须在 (0, 1] / Learning rate within (0, 1]
         OR (fFfMaxPct <= 0.0) OR (fTableMaxPct <= 0.0)               // 两限幅须为正 / Both clamps positive
         OR (fFfGain < 0.0);                                          // 增益须非负 / Gain non-negative
rtClear(CLK := bClear);                                               // 清表沿 / Clear edge
rtReset(CLK := bReset);                                               // 复位沿 / Reset edge

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault/_bConf/_iIdx 不入清单，R107） —— *)
fFfOutPct  := 0.0;                                                    // 前馈输出预置 / Feed-forward preset
bInjecting := FALSE;                                                  // 注入中预置 / Injecting preset
bLearning  := FALSE;                                                  // 学习中预置 / Learning preset
bValid     := FALSE;                                                  // 有效位预置 / Validity preset
bError     := FALSE;                                                  // 故障标志预清（R45 配对） / Error preset
_fOut      := 0.0;                                                    // 输出工作值预置 / Output working preset

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_AcgCause.eCfgIllegal;                             // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                  // 锁存 / Latch
    _eState := E_DL_AcgState.eFault;                                  // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：学/注冲突闸（同拍为真即锁存，两态全停） —— *)
IF bInjectEnable AND bLearnEnable THEN
    _bConf  := TRUE;                                                  // 冲突锁存 / Latch the conflict
    _bFault := TRUE;                                                  // 故障锁存 / Latch the fault
    _eCause := E_DL_AcgCause.eLearnConflict;                          // 归因：学/注冲突 / Cause: learn-inject conflict
    _eState := E_DL_AcgState.eFault;                                  // 入故障相 / Enter fault phase
END_IF

(* —— 段 4：迁出链与清表链（两条显式写出） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                 // 清故障锁存 / Clear fault latch
    _bConf  := FALSE;                                                 // 清冲突锁存 / Clear the conflict latch
    _eCause := E_DL_AcgCause.eNone;                                   // 清成因 / Clear cause
    _eState := E_DL_AcgState.eIdle;                                   // 回待机相 / Back to idle
END_IF
IF rtClear.Q THEN
    FOR _i := 0 TO 71 DO
        afTable[_i] := 0.0;                                           // 逐格清零（循环上界恒定） / Clear every bin
    END_FOR
END_IF

(* —— 段 5：索引归一（角度有限性 → 取整 → 取模 → 负角补模 → 显式钳位） —— *)
_bAngOk := NOT ((fAngleDeg <> fAngleDeg) OR ((fAngleDeg - fAngleDeg) <> (fAngleDeg - fAngleDeg)))
        AND (ABS(fAngleDeg) <= DL_ACG_ANG_MAX);                       // 有限且未超防溢出上限 / Finite and below the guard limit
IF _bAngOk THEN
    _iRaw := LREAL_TO_INT(TRUNC(fAngleDeg / DL_ACG_BIN_DEG));         // 取整到格号（截断向 0） / Truncate to a bin number
    _iIdx := _iRaw MOD DL_ACG_NBINS;                                  // 对格数取模 / Modulo the bin count
    IF _iIdx < 0 THEN
        _iIdx := _iIdx + DL_ACG_NBINS;                                // 负角补模（−5° → 71） / Negative angle wrapped
    END_IF
    IF _iIdx < 0 THEN
        _iIdx := 0;                                                   // 二次下钳（结构性冗余） / Second lower clamp
    ELSIF _iIdx > (DL_ACG_NBINS - 1) THEN
        _iIdx := DL_ACG_NBINS - 1;                                    // 二次上钳（结构性冗余） / Second upper clamp
    END_IF
    iTableIdx := _iIdx;                                               // 索引出口 / Index outlet
ELSE
    _eCause := E_DL_AcgCause.eAngleBad;                               // 归因：角度无效（当拍不判） / Cause: invalid angle
END_IF

(* —— 段 6：相迁移（注入 / 学习互斥；故障由段 4 迁出） —— *)
CASE _eState OF

E_DL_AcgState.eIdle:
    IF bInjectEnable AND (NOT bLearnEnable) THEN
        _eState := E_DL_AcgState.eInject;                              // 进注入相 / Enter injecting
    ELSIF bLearnEnable AND (NOT bInjectEnable) THEN
        _eState := E_DL_AcgState.eLearn;                               // 进学习相 / Enter learning
    END_IF

E_DL_AcgState.eInject:
    IF bLearnEnable THEN
        _eState := E_DL_AcgState.eIdle;                                // 学习被使能：先退注入（互斥由段 3 判冲突） / Leave injecting
    ELSIF NOT bInjectEnable THEN
        _eState := E_DL_AcgState.eIdle;                                // 失能：回待机 / Disabled, back to idle
    END_IF

E_DL_AcgState.eLearn:
    IF bInjectEnable THEN
        _eState := E_DL_AcgState.eIdle;                                // 注入被使能：先退学习 / Leave learning
    ELSIF NOT bLearnEnable THEN
        _eState := E_DL_AcgState.eIdle;                                // 失能：回待机 / Disabled, back to idle
    END_IF

E_DL_AcgState.eFault:
    ;                                                                  // 故障相：由段 4 复位沿迁出 / Exit via the reset edge

ELSE
    _eCause := E_DL_AcgCause.ePhaseBad;                                // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                                   // 锁存 / Latch
    _eState := E_DL_AcgState.eFault;                                   // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 7：注入（只读表；增益与限幅） —— *)
IF (_eState = E_DL_AcgState.eInject) AND _bAngOk THEN
    _fCell := afTable[_iIdx];                                           // 读当格补偿量 / Read the cell value
    _fOut  := _fCell * fFfGain;                                         // 乘增益 / Apply the gain
    IF _fOut > fFfMaxPct THEN
        _fOut := fFfMaxPct;                                             // 上限钳位 / Clamp high
    ELSIF _fOut < (0.0 - fFfMaxPct) THEN
        _fOut := 0.0 - fFfMaxPct;                                       // 下限钳位 / Clamp low
    END_IF
    bInjecting := TRUE;                                                 // 注入中 / Injecting
    bValid     := TRUE;                                                 // 输出有效 / Output valid
END_IF

(* —— 段 8：学习（只改表；观测转矩有限才更新；表值双限幅） —— *)
IF (_eState = E_DL_AcgState.eLearn) AND _bAngOk THEN
    IF NOT ((fTorqueRefPct <> fTorqueRefPct) OR ((fTorqueRefPct - fTorqueRefPct) <> (fTorqueRefPct - fTorqueRefPct))) THEN
        afTable[_iIdx] := afTable[_iIdx] + (fLearnRate * fTorqueRefPct);   // 梯度式更新（学习率已过域闸） / Gradient-style update
        IF afTable[_iIdx] > fTableMaxPct THEN
            afTable[_iIdx] := fTableMaxPct;                             // 表格上限钳位 / Table clamp high
        ELSIF afTable[_iIdx] < (0.0 - fTableMaxPct) THEN
            afTable[_iIdx] := 0.0 - fTableMaxPct;                       // 表格下限钳位 / Table clamp low
        END_IF
        bLearning := TRUE;                                              // 学习中 / Learning
    END_IF
END_IF

(* —— 段 9：出口单点映射（名实双出口，R191） —— *)
fFfOutPct      := _fOut;                                                // 前馈输出出口 / Feed-forward outlet
bLearnConflict := _bConf;                                               // 冲突锁存出口 / Conflict outlet
eState         := _eState;                                              // 相出口 / Phase outlet
eCause         := _eCause;                                              // 成因出口 / Cause outlet
bError         := _bFault;                                              // 故障标志 / Error flag

END_FUNCTION_BLOCK
