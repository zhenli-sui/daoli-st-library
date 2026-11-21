(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Hysteresis
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），全 REAL 运算
 * 功能描述 (Function)   : 施密特迟滞比较器（双阈值）。输入高于上阈值置 TRUE、
 *                         低于下阈值置 FALSE、落入回差带内保持原态。
 *                         用于液位、温度、压力等模拟量驱动的泵 / 加热器 / 报警器启停，
 *                         消除单阈值在设定点附近反复跨越导致的高频动作。
 *
 * 【接口设计决策 / Interface decision】
 *   迟滞的输出依赖上一周期输出，本质是有状态运算。本组件保持 FC_ 形态（不用 FB），
 *   状态经 VAR_IN_OUT bState 交还调用方持有：调用方声明持久变量 bHystState : BOOL;
 *   并每个扫描周期传入同一变量。好处是无实例内存、可直接放进 IF 表达式；
 *   代价是调用方必须遵守"同一变量回传"纪律。
 *
 * 【有状态纪律警告 / State retention warning（边界 B7）】
 *   VAR_IN_OUT 传入的必须是持久变量（实例成员、静态变量或 RETAIN 变量）。
 *   禁止传表达式、常量或临时变量，否则每周期状态被重置，退化为纯比较器：
 *     ✗ 错误示例：bPump := FC_DL_Hysteresis(fIn := fLevel, fThreshold := 60.0,
 *                                          fHysteresis := 2.0, bState := FALSE);
 *     ✓ 正确示例：bPump := FC_DL_Hysteresis(fIn := fLevel, fThreshold := 60.0,
 *                                          fHysteresis := 2.0, bState := bLevelHystState);
 *
 * 【初值行为 / Initial state behavior（边界 B5）】
 *   bState 上电初值 FALSE，若输入一开始就落在回差带内，输出保持 FALSE 不误动作
 *   （保守方向对泵与加热器均为安全侧）。若需"首次强制同步"，可先用一个低于下阈值的
 *   假值空跑一个周期，使状态与真实工况对齐。
 * 开源溯源 (Origin)     : 原创实现。施密特触发器为公开经典电路模型，本处为其离散化。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 负宽容错 + 回差上限 + 零回差告警 + 容差判零
 *                         R5 ✓ 全变量中英双语同行注释 + 有状态纪律警告 ｜ R6 N/A（用状态位非状态机）
 *                         R7 N/A（无定时器/边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_Hysteresis : BOOL
VAR_INPUT
    fIn         : REAL;           // 输入值 [EU] / Input value [EU]
    fThreshold  : REAL;           // 设定点，回差带中心 [EU] / Setpoint, center of the hysteresis band [EU]
    fHysteresis : REAL := 0.0;    // 回差总宽度 [EU]，负值取绝对值 / Total hysteresis width [EU], negative taken as absolute
END_VAR
VAR_IN_OUT
    bState      : BOOL;           // 迟滞状态，调用方持有并每周期回传同一变量 / Hysteresis state, retained by the caller
END_VAR
VAR_OUTPUT
    fUpperTrip  : REAL;           // 实际上阈值 = fThreshold + 半回差 [EU] / Effective upper trip [EU]
    fLowerTrip  : REAL;           // 实际下阈值 = fThreshold - 半回差 [EU] / Effective lower trip [EU]
    uErrorId    : UDINT;          // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fHalfBand      : REAL;        // 半回差带宽 [EU] / Half hysteresis band [EU]
    fThresholdAbs  : REAL;        // 设定点绝对值 [EU] / Absolute value of the setpoint [EU]
    fMaxBand       : REAL;        // 半回差允许上限 [EU] / Upper limit of the half band [EU]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS      : REAL := 1.0E-6;  // 浮点判零容差 / Float zero tolerance
    DL_HYST_MAX_RATIO : REAL := 0.5;     // 回差不超过设定点绝对值的 50%，防误填 / Max hysteresis ratio
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜默认保持原态：本函数在回差带内"什么都不做"，这是迟滞的定义
 *      Default hold: inside the band nothing is written, which is the definition
 *-----------------------------------------------------------------------------*)
FC_DL_Hysteresis := bState;
uErrorId         := 16#0000_0000;
fHalfBand        := 0.0;
fMaxBand         := 0.0;

(*------------------------------------------------------------------------------
 * 段 2｜回差负值容错（边界 B1）：取绝对值继续运行，仅告警
 *      Negative hysteresis tolerance: absolute value plus a warning only
 *-----------------------------------------------------------------------------*)
fHalfBand := ABS(fHysteresis) * 0.5;

IF fHysteresis < 0.0 THEN
    uErrorId := 16#0001_0003;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜回差上限保护（边界 B2）：按设定点绝对值的比例限幅
 *      Hysteresis upper limit: ratio based on the absolute setpoint value
 *      设定点本身接近 0 时相对上限退化（任何比例乘 0 都是 0），此时跳过比例限幅，
 *      否则回差会被压成 0、迟滞功能被静默取消
 *      限幅目的：防止参数误填导致阈值跑到物理量程之外、设备永不动作
 *-----------------------------------------------------------------------------*)
fThresholdAbs := ABS(fThreshold);

IF fThresholdAbs > DL_FLOAT_EPS THEN
    fMaxBand := fThresholdAbs * DL_HYST_MAX_RATIO;

    IF fHalfBand > fMaxBand THEN
        fHalfBand := fMaxBand;
        uErrorId  := 16#0001_0003;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双阈值计算：上下阈值对称分布于设定点两侧
 *      Dual threshold computation, symmetric around the setpoint
 *-----------------------------------------------------------------------------*)
fUpperTrip := fThreshold + fHalfBand;
fLowerTrip := fThreshold - fHalfBand;

(*------------------------------------------------------------------------------
 * 段 5｜迟滞判定（边界 B3/B4）：置位用严格大于、复位用严格小于
 *      Hysteresis decision: strict greater for set, strict less for reset
 *      等于阈值时保持原态——写成 >= / <= 会让回差带退化，边界抖动立刻回来
 *      零回差时退化为普通比较器，允许运行但必须告警（组态缺陷而非运行故障）
 *-----------------------------------------------------------------------------*)
IF fHalfBand <= DL_FLOAT_EPS THEN
    (* 零回差：阈值重合，按严格不等式做单阈值比较，并置告警 *)
    (* Zero hysteresis: thresholds coincide, single-threshold comparison with a warning *)
    uErrorId := 16#0001_0003;

    IF fIn > fThreshold THEN
        bState := TRUE;
    ELSIF fIn < fThreshold THEN
        bState := FALSE;
    END_IF
ELSE
    IF fIn > fUpperTrip THEN
        bState := TRUE;
    ELSIF fIn < fLowerTrip THEN
        bState := FALSE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜结果回写：同时返回更新后的状态，便于调用方在一次扫描内使用
 *      Result write-back: also return the refreshed state for same-scan use
 *-----------------------------------------------------------------------------*)
FC_DL_Hysteresis := bState;
END_FUNCTION
