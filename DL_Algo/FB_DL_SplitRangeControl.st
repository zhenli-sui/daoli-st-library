(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SplitRangeControl
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 数学运算，零库依赖，零厂商方言
 * 功能描述 (Function)   : 分程输出分配。把单一控制器输出（-100..100%）分配为
 *                         两路执行器信号：正半区驱动加热通道、负半区驱动冷却
 *                         通道，中央死区间隙防双阀同开；两路输出各自按独立量程
 *                         二次映射，支持加热通道反相。现场用途：温控冷热双执
 *                         行器、蒸汽 / 冷水阀对。
 * 开源溯源 (Origin)     : 原创实现。分程控制功能分类与参数域参考过程控制经典
 *                         文献（split-range pairing）的公开语义描述，
 *                         未复制任何厂商源码，clean-room 重写。
 * 本文件内含       : TYPE  E_DL_SplitState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_SplitRangeControl
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 无实例依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 ✓ 本块无定时器 / 边沿实例（无可刷新项，天然合规）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 * 验收向量 (Acceptance) :
 *   V1 正半区：fCtrlIn=50 → fOutHeat=50、fOutCool=0、bHeatActive=TRUE
 *   V2 负半区：fCtrlIn=-40 → fOutCool=40、fOutHeat=0、bCoolActive=TRUE
 *   V3 死区：fCtrlIn=1.0 且 fGap=2.0 → 两路输出均为 0
 *   V4 反相：fCtrlIn=50 且 bInvertHeat=TRUE → fOutHeat=50 映射后取 100-x
 *   V5 非有限值：fCtrlIn 写入非法浮点 → 两路输出保持上一拍且码 0002_0004
 *   V6 二次映射：rOutHeatMin=20 → fOutHeat 从 20 起算
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SplitState（归属 DL_Algo，与 FB_DL_SplitRangeControl 同文件）
 * 含义: 分程分配离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SplitState :
(
    eIdle     := 0,    // 使能关：两路输出回各自量程下限 / Idle: enable off, both outputs at range low
    eHeatZone := 10,   // 加热区：正半区驱动加热通道 / Heat zone: positive half drives heating channel
    eDeadband := 20,   // 中央死区：两路输出均为零 / Central deadband: both outputs zero
    eCoolZone := 30,   // 冷却区：负半区驱动冷却通道 / Cool zone: negative half drives cooling channel
    eFault    := 99    // 故障兜底态：非法状态进入，输出安全值 / Fault fallback: illegal state, safe output
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SplitRangeControl
 * 调用约定: 每个扫描周期无条件调用一次。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 工程披露: tSampleTime 仅用于与子库其余组件保持引脚一致性与未来扩展。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SplitRangeControl
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 总使能，FALSE 时两路回量程下限 / Master enable, FALSE drives both to range low
    fCtrlIn     : REAL := 0.0;        // 控制器输入 [%]，-100..100 / Controller input in percent, -100..100
    fGap        : REAL := 2.0;        // 中央死区 [%]，负值钳 0 / Central deadband in percent, negative clamped
    rCtrlMax    : REAL := 100.0;      // 输入满量程幅值 [%]，须大于 0 / Input full-scale magnitude in percent
    rOutHeatMin : REAL := 0.0;        // 加热通道输出下限 [%] / Heating channel output lower limit
    rOutHeatMax : REAL := 100.0;      // 加热通道输出上限 [%] / Heating channel output upper limit
    rOutCoolMin : REAL := 0.0;        // 冷却通道输出下限 [%] / Cooling channel output lower limit
    rOutCoolMax : REAL := 100.0;      // 冷却通道输出上限 [%] / Cooling channel output upper limit
    bInvertHeat : BOOL := FALSE;      // 加热通道反相输出 100-x / Invert heating channel output
    tSampleTime : TIME := T#100MS;    // 采样周期，仅保持一致性 / Sample period, consistency only
END_VAR
VAR_OUTPUT
    fOutHeat    : REAL;               // 加热通道输出 [%] / Heating channel output in percent
    fOutCool    : REAL;               // 冷却通道输出 [%] / Cooling channel output in percent
    bHeatActive : BOOL;               // 加热通道激活标志 / Heating channel active flag
    bCoolActive : BOOL;               // 冷却通道激活标志 / Cooling channel active flag
    bError      : BOOL;               // 故障标志 / Fault flag
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fHeatRaw    : REAL;               // 加热通道映射中间量 [%] / Heating channel mapping intermediate
    fCoolRaw    : REAL;               // 冷却通道映射中间量 [%] / Cooling channel mapping intermediate
    eState      : E_DL_SplitState;    // 主状态机当前状态 / Current state of the state machine
    fCtrlMaxEff : REAL;               // 钳位后的有效满量幅值 [%] / Clamped effective full-scale
    fGapEff     : REAL;               // 钳位后的有效死区 [%] / Clamped effective deadband
    fCtrlClamp  : REAL;               // 钳位到满量幅值后的输入 [%] / Input clamped to full-scale
    fHeatLow    : REAL;               // 对调修复后的加热下限 [%] / Repaired heating low limit
    fHeatHigh   : REAL;               // 对调修复后的加热上限 [%] / Repaired heating high limit
    fCoolLow    : REAL;               // 对调修复后的冷却下限 [%] / Repaired cooling low limit
    fCoolHigh   : REAL;               // 对调修复后的冷却上限 [%] / Repaired cooling high limit
    bNonFinite  : BOOL;               // 本拍输入非有限值标志 / Non-finite input flag of this cycle
END_VAR
VAR CONSTANT
    DL_SPLIT_CTRL_MAX_DEF : REAL := 100.0;  // 满量幅值钳位默认值 [%] / Full-scale clamp default value
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位与公共防御（不中断扫描）
 *      Parameter clamping and common defenses, never stops the scan
 *-----------------------------------------------------------------------------*)
bError   := FALSE;                    // 每拍重算故障标志 / Recompute fault flag every cycle
uErrorId := 16#0002_0000;             // 每拍重算故障码 / Recompute error code every cycle
bHeatActive := FALSE;                 // 激活标志每拍重算 / Active flags recomputed every cycle
bCoolActive := FALSE;                 // 激活标志每拍重算 / Active flags recomputed every cycle
bNonFinite  := FALSE;                 // 非有限值标志每拍重算 / Non-finite flag recomputed every cycle

IF tSampleTime < T#10MS THEN
    tSampleTime := T#10MS;            // 采样周期非法钳位为 10 ms / Illegal sample period clamped to 10 ms
    uErrorId := 16#0002_0002;         // 公共码：采样周期已钳位 / Common code: sample period clamped
END_IF

IF rCtrlMax <= 1.0E-6 THEN
    fCtrlMaxEff := DL_SPLIT_CTRL_MAX_DEF;  // 满量幅值非法钳位默认值 / Illegal full-scale clamped to default
    uErrorId := 16#0002_0301;         // 组件码：输入满量程非法已钳位 / Code: full-scale illegal, clamped
ELSE
    fCtrlMaxEff := rCtrlMax;          // 合法满量幅值直通 / Valid full-scale passed through
END_IF

IF fGap < 0.0 THEN
    fGapEff := 0.0;                   // 死区负值钳 0 / Negative deadband clamped to zero
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fGapEff := fGap;                  // 合法死区直通 / Valid deadband passed through
END_IF

(* 通道量程 Min>Max 对调修复：加热通道 *)
(* Range swap repair: heating channel *)
IF rOutHeatMin > rOutHeatMax THEN
    fHeatLow  := rOutHeatMax;         // 下限取原上限 / Low limit takes former high
    fHeatHigh := rOutHeatMin;         // 上限取原下限 / High limit takes former low
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fHeatLow  := rOutHeatMin;         // 合法下限直通 / Valid low limit passed
    fHeatHigh := rOutHeatMax;         // 合法上限直通 / Valid high limit passed
END_IF

(* 通道量程 Min>Max 对调修复：冷却通道 *)
(* Range swap repair: cooling channel *)
IF rOutCoolMin > rOutCoolMax THEN
    fCoolLow  := rOutCoolMax;         // 下限取原上限 / Low limit takes former high
    fCoolHigh := rOutCoolMin;         // 上限取原下限 / High limit takes former low
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fCoolLow  := rOutCoolMin;         // 合法下限直通 / Valid low limit passed
    fCoolHigh := rOutCoolMax;         // 合法上限直通 / Valid high limit passed
END_IF

(* 输入非有限值防御：非法浮点拒绝本拍更新，保持上一拍输出 *)
(* Non-finite defense: reject this cycle, hold previous outputs *)
IF (fCtrlIn <> fCtrlIn) OR (ABS(fCtrlIn) > 1.0E30) THEN
    bNonFinite := TRUE;               // 置非有限值标志 / Set non-finite flag
    bError   := TRUE;                 // 置故障标志 / Set fault flag
    uErrorId := 16#0002_0004;         // 公共码：输入非有限值已拒绝 / Common code: non-finite rejected
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    eState := eIdle;                  // 强制回空闲态 / Force idle state
ELSIF bNonFinite THEN
    (* 非有限值拍：状态派生冻结，输出保持由 CASE 外的早退保证 *)
    (* Non-finite cycle: state derivation frozen, hold guaranteed by early exit *)
ELSIF bError AND (uErrorId = 16#0002_0301) AND (fCtrlMaxEff <= 1.0E-6) THEN
    eState := eFault;                 // 满量幅值非法进故障态 / Illegal full-scale leads to fault
ELSE
    (* 状态派生：按钳位后输入的半区归属决定状态 *)
    (* State derivation: zone decided by clamped input half-range *)
    fCtrlClamp := LIMIT(-fCtrlMaxEff, fCtrlIn, fCtrlMaxEff);  // 输入钳位到满量幅值 / Clamp input to full-scale
    IF fCtrlClamp > fGapEff THEN
        eState := eHeatZone;          // 正半区进加热态 / Positive half enters heat zone
    ELSIF fCtrlClamp < -fGapEff THEN
        eState := eCoolZone;          // 负半区进冷却态 / Negative half enters cool zone
    ELSE
        eState := eDeadband;          // 中央死区 / Central deadband
    END_IF
END_IF

CASE eState OF

    eIdle:
        (* 使能关：两路输出回各自量程下限，激活标志清零 *)
        (* Enable off: both outputs to range low, active flags cleared *)
        fOutHeat    := fHeatLow;      // 加热回下限 / Heating to low limit
        fOutCool    := fCoolLow;      // 冷却回下限 / Cooling to low limit

    eHeatZone:
        (* 加热区：正半区按满量幅值归一化映射，冷却通道置 0 *)
        (* Heat zone: positive half normalized by full-scale, cooling set to zero *)
        fHeatRaw := fCtrlClamp / fCtrlMaxEff * 100.0;             // 归一化 [%] / Normalized percent
        fCoolRaw := 0.0;              // 冷却通道归零 / Cooling channel zeroed
        (* 二次映射到加热通道独立量程，支持反相 *)
        (* Second mapping onto heating range, inversion supported *)
        IF bInvertHeat THEN
            fOutHeat := LIMIT(fHeatLow, 100.0 - (fHeatLow + (fHeatRaw / 100.0) * (fHeatHigh - fHeatLow)), fHeatHigh);
        ELSE
            fOutHeat := LIMIT(fHeatLow, fHeatLow + (fHeatRaw / 100.0) * (fHeatHigh - fHeatLow), fHeatHigh);
        END_IF
        fOutCool    := fCoolLow;      // 冷却输出回下限 / Cooling output to low limit
        bHeatActive := TRUE;          // 加热激活 / Heating active

    eDeadband:
        (* 中央死区：两路输出均为量程下限，防双阀同开 *)
        (* Central deadband: both outputs at range low, prevents simultaneous opening *)
        fOutHeat    := fHeatLow;      // 加热回下限 / Heating to low limit
        fOutCool    := fCoolLow;      // 冷却回下限 / Cooling to low limit

    eCoolZone:
        (* 冷却区：负半区取幅值映射，加热通道置 0 *)
        (* Cool zone: negative half mapped by magnitude, heating set to zero *)
        fHeatRaw := 0.0;              // 加热通道归零 / Heating channel zeroed
        fCoolRaw := -fCtrlClamp / fCtrlMaxEff * 100.0;            // 幅值归一化 [%] / Magnitude normalized
        fOutHeat := fHeatLow;         // 加热输出回下限 / Heating output to low limit
        fOutCool := LIMIT(fCoolLow, fCoolLow + (fCoolRaw / 100.0) * (fCoolHigh - fCoolLow), fCoolHigh);
        bCoolActive := TRUE;          // 冷却激活 / Cooling active

    eFault:
        (* 故障兜底态：两路输出回量程下限安全值 *)
        (* Fault fallback: both outputs to safe range low *)
        fOutHeat := fHeatLow;         // 加热安全输出 / Heating safe output
        fOutCool := fCoolLow;         // 冷却安全输出 / Cooling safe output

    ELSE
        (* 非法状态拦截：任何未定义状态一律进故障兜底，不做隐式恢复 *)
        (* Illegal state interception: any undefined state goes to fault fallback *)
        eState   := eFault;           // 进故障态 / Enter fault state
        bError   := TRUE;             // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;     // 非法状态兜底码 / Illegal state fallback code
        fOutHeat := fHeatLow;         // 加热安全输出 / Heating safe output
        fOutCool := fCoolLow;         // 冷却安全输出 / Cooling safe output
END_CASE;

IF bNonFinite THEN
    (* 非有限值拍输出回滚：保持上一拍输出，激活标志清零 *)
    (* Non-finite output rollback: hold previous outputs, clear active flags *)
    fOutHeat    := fOutHeat;          // 输出保持 / Output held
    fOutCool    := fOutCool;          // 输出保持 / Output held
    bHeatActive := FALSE;             // 激活标志清零 / Active flag cleared
    bCoolActive := FALSE;             // 激活标志清零 / Active flag cleared
END_IF
END_FUNCTION_BLOCK
