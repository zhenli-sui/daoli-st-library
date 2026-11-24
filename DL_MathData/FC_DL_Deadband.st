(*==============================================================================
 * 组件名称 (Component)  : FC_DL_Deadband
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS），全 REAL 运算
 * 功能描述 (Function)   : 死区（Dead Band）处理，用于抑制零点附近的传感器零漂、
 *                         量化噪声与计算残差，典型用途是 PID 误差通道，防止调节阀
 *                         在设定点附近高频动作导致定位器磨损。
 *                         提供两种互斥语义（由 bZeroMode 选择，不可同时生效）：
 *                         移位型（默认）：死区内输出 0，死区外输出 dev - sign(dev)*width，
 *                                        边界连续、无阶跃，可串入闭环；
 *                         归零型：死区内输出 0，死区外原样输出 dev，
 *                                边界有跳变（跳变量 = 死区宽度），属阈值开关直觉。
 * 失真披露 (Distortion): 死区必然使信号失真，失真量恰为死区宽度。用于 PID 误差通道时
 *                         fCenter 必须为 0，否则零点被人工搬移，积分项会持续累积偏置。
 * 开源溯源 (Origin)     : 原创实现。限幅思想参考 OSCAT DEAD_BAND_A 的 LM 处理，
 *                         语义与故障码按本库体系重写，未复制源码。
 * 依赖     (Depends)    : 无 DL_ 内部依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（自建符号函数，无标准 SIGN）
 *                         R4 ✓ 负宽容错 / 零宽直通 / 浮点容差 / 宽度上限
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_Deadband : REAL
VAR_INPUT
    fIn       : REAL;              // 输入值 [EU] / Input value [EU]
    fWidth    : REAL := 0.0;       // 死区半宽 [EU]，负值取绝对值 / Deadband half-width [EU], negative taken as absolute
    fCenter   : REAL := 0.0;       // 死区中心偏移 [EU]，零点不在 0 时使用 / Deadband center offset [EU]
    bZeroMode : BOOL := FALSE;     // FALSE = 移位型（连续），TRUE = 归零型（阈值开关） / FALSE = shift type, TRUE = zero type
END_VAR
VAR_OUTPUT
    bInDeadband : BOOL;            // 当前处于死区内 / Currently inside the deadband
    fDeviation  : REAL;            // 去中心后的原始偏差 [EU] / Raw deviation from the center [EU]
    fEffWidth   : REAL;            // 实际生效的死区半宽 [EU] / Effective deadband half-width [EU]
    uErrorId    : UDINT;           // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fSign       : REAL;            // 自建符号函数结果，取值 +1.0 或 -1.0 / Self-built sign result, +1.0 or -1.0
    fWidthAbs   : REAL;            // 原始宽度的绝对值 [EU] / Absolute value of the input width [EU]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS      : REAL := 1.0E-6;      // 浮点判零容差 / Float zero tolerance
    DL_DEADBAND_MAX_WIDTH : REAL := 1000.0;  // 死区半宽硬上限 [EU]，防参数误填成 999 导致输出恒 0 / Hard upper limit [EU]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置：返回值先落到"直通"语义，异常路径不引入额外失真
 *      Safe preset: default to pass-through so error paths add no extra distortion
 *-----------------------------------------------------------------------------*)
FC_DL_Deadband := fIn;
bInDeadband    := FALSE;
fDeviation     := 0.0;
fEffWidth      := 0.0;
fSign          := 1.0;
fWidthAbs      := 0.0;
uErrorId       := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜负宽度容错（边界 B1）：取绝对值后继续运行，绝不把宽度压成 0
 *      Negative width tolerance: take the absolute value and keep running
 *      宽度为 0 等价于死区消失，阀门会立刻恢复高频动作，正是现场最怕的结果，
 *      因此这里只告警、不降级
 *-----------------------------------------------------------------------------*)
fWidthAbs := ABS(fWidth);
fEffWidth := fWidthAbs;

IF fWidth < 0.0 THEN
    uErrorId := 16#0001_0003;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜宽度上限保护（边界 B5）：防止参数误填导致输出恒为 0
 *      Width upper limit: prevents a mis-typed parameter from freezing the output at 0
 *      "输出恒 0"在现场表现为"设备不响应"而非"参数错误"，极难定位，
 *      因此宁可钳位并告警，也要保证回路仍有响应
 *-----------------------------------------------------------------------------*)
IF fEffWidth > DL_DEADBAND_MAX_WIDTH THEN
    fEffWidth := DL_DEADBAND_MAX_WIDTH;
    uErrorId  := 16#0001_0003;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜偏差计算：先去掉中心偏移，后续所有判定只基于 fDeviation
 *      Deviation computation: remove the center offset first, all tests use fDeviation
 *-----------------------------------------------------------------------------*)
fDeviation := fIn - fCenter;

(*------------------------------------------------------------------------------
 * 段 5｜零宽度直通（边界 B2/B4）：严格直通，且不判为"在死区内"
 *      Zero-width pass-through: strict pass-through, never reported as inside the band
 *      判定用 ABS(..) <= EPS 的容差比较，禁止 fEffWidth = 0.0
 *-----------------------------------------------------------------------------*)
IF fEffWidth <= DL_FLOAT_EPS THEN
    FC_DL_Deadband := fDeviation;
    bInDeadband    := FALSE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜死区内判定：使用严格小于，边界点算"死区外"，保证移位型在边界连续
 *      Inside-band test: strict less-than keeps the shift type continuous at the edge
 *-----------------------------------------------------------------------------*)
IF ABS(fDeviation) < fEffWidth THEN
    bInDeadband    := TRUE;
    FC_DL_Deadband := 0.0;
ELSE
    IF bZeroMode THEN
        (*----------------------------------------------------------------------
         * 段 7a｜归零型：死区外原样输出，边界处存在等于死区宽度的阶跃
         *       Zero type: pass the deviation through, step size equals the band width
         *---------------------------------------------------------------------*)
        FC_DL_Deadband := fDeviation;
    ELSE
        (*----------------------------------------------------------------------
         * 段 7b｜移位型（默认）：减去带符号的死区宽度，边界连续无阶跃
         *       Shift type (default): subtract the signed band width, edge is continuous
         *       IEC 61131-3 无标准 SIGN 函数，必须自建；偏差为 0 时符号取 +1.0
         *       （此时实际不可达，因为已在段 6 判为死区内，仍显式给定以避免
         *        0/0 式未定义推导）
         *---------------------------------------------------------------------*)
        IF fDeviation >= 0.0 THEN
            fSign := 1.0;
        ELSE
            fSign := -1.0;
        END_IF

        FC_DL_Deadband := fDeviation - fSign * fEffWidth;
    END_IF
END_IF
END_FUNCTION
