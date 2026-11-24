//==============================================================================
// 函数：FC_DL_FanLawRootCalc ｜ 中文名称：风机相似定律换算（流量/压力/功率）
// 所属子库：DL_MathData ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：风机相似定律（Fan Affinity Laws）双向换算：
//           正向（由转速比 N2/N1 = r）：Q2 = Q1 x r，P2 = P1 x r^2，
//           W2 = W1 x r^3；反向（由流量比 Q2/Q1）：r = SQRT(流量比)
//           （流量与转速成正比 → 转速比在开方域反解），反解后再按正向
//           公式算三参数。判据来源：风机相似律公开公式（本库组合律
//           实现；开方原子归 FC_DL_NthRoot，本件是组合不重复原子）。
//           工程域闸：转速比有效域 [0.1, 5.0]，域外钳位照算（信息级）；
//           转速比/流量比 <= 0 物理非法 → 故障级拒绝。
// 开源溯源 (Origin)：道莅原创实现（参考风机相似定律公开公式 分类与参数域）
// 单位表：转速比[比值] / 流量比[比值] / 流量[m3/h] / 全压[Pa] / 轴功率[kW]
// 错误码表：16#0001_046C 信息级（转速比域外 [0.1, 5.0] 已钳位照算，不置
//           bError）/ 16#0001_046D 预留禁用（不得挪用）/ 16#0001_046E
//           预留禁用（不得挪用）/ 16#0001_03BB 故障级（任一输入非有限，
//           或转速比/流量比 <= 0 物理非法——流量比 <= 0 即负开方域，
//           置 bError）/ 16#0001_03BC 预留禁用（不得挪用）
// 状态机：N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底
// 边界行为：① 任一输入非有限（NaN 自反判 + 幅值上限兜底，R79）→ 故障
//           03BB、输出 0、bValid := FALSE；② 正向模式转速比 <= 0 或反向
//           模式流量比 <= 0（负开方域）→ 故障 03BB；③ 生效转速比域外
//           [0.1, 5.0] → 双侧钳位照算 + 信息 046C（工程域承诺收窄声明：
//           域外相似律误差不承诺）；④ 结果非有限复检（r^3 放大溢出）→
//           复用 03BB（R90：与输入非法共用「数据不可信」语义，现有输出
//           组合不可观测出独立信息，不新占码位）；⑤ 失能清零不适用
//           （纯函数无使能闸，非法输入即故障早退）；⑥ 基准参数 Q1/P1/W1
//           允许为 0（用户只需部分输出），不影响其余换算项。
// 验收向量（算法已证，手算）：① r=2、Q1=100 m3/h、P1=500 Pa、W1=10 kW →
//           Q2=200、P2=2000、W2=80；② 反向流量比 4 → r=2 → 同①；
//           ③ r=10 → 钳 5.0 + 信息 046C → Q2=5xQ1。
//           编译器已证（三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §661 · FB→FC 改判留档：纯函数无状态，按 R14 聚居判据归 DL_MathData）
//==============================================================================

FUNCTION FC_DL_FanLawRootCalc : BOOL
VAR_INPUT
    fSpeedRatio : LREAL := 1.0;             // 转速比 N2/N1 [比值]，正向模式输入，有效域 0.1..5.0，域外钳位照算 / Speed ratio [ratio], forward mode, valid range 0.1..5.0
    fFlowRatio  : LREAL := 1.0;             // 流量比 Q2/Q1 [比值]，反向模式输入，须 > 0（负开方域闸） / Flow ratio [ratio], reverse mode input, must be > 0
    xReverse    : BOOL  := FALSE;           // FALSE = 由转速比正算三参数；TRUE = 由流量比反算转速比（开方域） / FALSE = forward from speed ratio, TRUE = reverse from flow ratio
    fQ1         : LREAL := 0.0;             // 基准工况流量 [立方米每小时] / Reference flow [m3/h]
    fP1         : LREAL := 0.0;             // 基准工况全压 [帕] / Reference total pressure [Pa]
    fW1         : LREAL := 0.0;             // 基准工况轴功率 [千瓦] / Reference shaft power [kW]
END_VAR
VAR_OUTPUT
    fSpeedRatioOut : LREAL;                 // 生效转速比 [比值]（含钳位后值） / Effective speed ratio [ratio], post-clamp
    fQ2 : LREAL;                            // 换算流量 [立方米每小时] / Scaled flow [m3/h]
    fP2 : LREAL;                            // 换算全压 [帕] / Scaled total pressure [Pa]
    fW2 : LREAL;                            // 换算轴功率 [千瓦] / Scaled shaft power [kW]
    eErr   : UDINT;                         // 错误码，0 = 无错，码位 16#0001_046C 起信息级、16#0001_03BB 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError : BOOL;                          // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid : BOOL;                          // 结果可用标志 / Result usable flag
END_VAR
VAR CONSTANT
    DL_FLR_RATIO_LO : LREAL := 0.1;         // 转速比工程域下限 [比值] / Speed ratio engineering floor [ratio]
    DL_FLR_RATIO_HI : LREAL := 5.0;         // 转速比工程域上限 [比值] / Speed ratio engineering ceiling [ratio]
    DL_FLR_EPS      : LREAL := 1.0E-6;      // 浮点判零容差 [比值] / Float zero tolerance [ratio]
    DL_FLR_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_FLR_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [比值] / Zero constant, avoids a bare literal [ratio]
END_VAR
VAR
    fRatio  : LREAL;                        // 生效转速比中间量 [比值] / Effective speed ratio intermediate
    bNonFin : BOOL;                         // 非有限判定中间标志 / Non-finite detection intermediate flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：返回值与输出预置（安全侧 = 0）
 *      Exit defaults: return value and outputs preset, fail-safe zero
 *-----------------------------------------------------------------------------*)
FC_DL_FanLawRootCalc := FALSE;              // 返回值默认无效 / Return value preset invalid
fSpeedRatioOut := DL_FLR_ZERO;              // 转速比出口预置 0 / Speed ratio outlet preset zero
fQ2 := DL_FLR_ZERO;                         // 流量出口预置 0 / Flow outlet preset zero
fP2 := DL_FLR_ZERO;                         // 全压出口预置 0 / Pressure outlet preset zero
fW2 := DL_FLR_ZERO;                         // 功率出口预置 0 / Power outlet preset zero
eErr   := 16#0000_0000;                     // 错误码先清零 / Error code cleared first
bError := FALSE;                            // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                            // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜输入非有限闸（R79 双侧幅值判：NaN 自反 + Inf 幅值兜底）
 *      Input non-finite gate
 *-----------------------------------------------------------------------------*)
IF (fSpeedRatio <> fSpeedRatio) OR (ABS(fSpeedRatio) > DL_FLR_INF)
   OR (fFlowRatio <> fFlowRatio) OR (ABS(fFlowRatio) > DL_FLR_INF)
   OR (fQ1 <> fQ1) OR (ABS(fQ1) > DL_FLR_INF)
   OR (fP1 <> fP1) OR (ABS(fP1) > DL_FLR_INF)
   OR (fW1 <> fW1) OR (ABS(fW1) > DL_FLR_INF) THEN
    eErr   := 16#0001_03BB;                 // 故障级：输入非有限 / Fault: non-finite input
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退，输出保持 0 / Early return, outputs stay zero
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜方向闸：反向先过开方域（流量比 <= 0 物理非法），正向过转速比闸
 *      Direction gate, reverse mode enters the square-root domain first
 *-----------------------------------------------------------------------------*)
IF xReverse THEN
    IF fFlowRatio <= DL_FLR_EPS THEN
        eErr   := 16#0001_03BB;             // 故障级：流量比 <= 0，负开方域 / Fault: flow ratio <= 0, negative square-root domain
        bError := TRUE;                     // 置故障标志 / Raise the fault flag
        bValid := FALSE;                    // 输出不可用 / Outputs unusable
        RETURN;                             // 故障早退 / Early return
    END_IF
    fRatio := SQRT(fFlowRatio);             // 反解转速比（流量与转速成正比） / Reverse speed ratio via square root
ELSE
    IF fSpeedRatio <= DL_FLR_EPS THEN
        eErr   := 16#0001_03BB;             // 故障级：转速比 <= 0 物理非法 / Fault: speed ratio <= 0, physically illegal
        bError := TRUE;                     // 置故障标志 / Raise the fault flag
        bValid := FALSE;                    // 输出不可用 / Outputs unusable
        RETURN;                             // 故障早退 / Early return
    END_IF
    fRatio := fSpeedRatio;                  // 正向直接沿用转速比 / Forward mode applies the ratio as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜工程域钳位：[0.1, 5.0] 域外双侧钳位照算 + 信息 046C
 *      Engineering-domain clamp with info-level notice
 *-----------------------------------------------------------------------------*)
IF (fRatio < DL_FLR_RATIO_LO) OR (fRatio > DL_FLR_RATIO_HI) THEN
    fRatio := MIN(MAX(fRatio, DL_FLR_RATIO_LO), DL_FLR_RATIO_HI); // 双侧钳位 / Two-sided clamp
    eErr := 16#0001_046C;                   // 信息级：转速比域外已钳位照算（不置 bError） / Info: ratio clamped, computation continues
END_IF
fSpeedRatioOut := fRatio;                   // 生效转速比出口 / Effective speed ratio outlet

(*------------------------------------------------------------------------------
 * 段 5｜相似定律三参数：Q x r、P x r^2、W x r^3（乘法链避免 EXP 溢出域争议）
 *      Affinity-law scaling of flow, pressure and power
 *-----------------------------------------------------------------------------*)
fQ2 := fQ1 * fRatio;                        // 流量 x 转速比 / Flow times speed ratio
fP2 := fP1 * fRatio * fRatio;               // 全压 x 转速比平方 / Pressure times ratio squared
fW2 := fW1 * fRatio * fRatio * fRatio;      // 轴功率 x 转速比立方 / Power times ratio cubed

(*------------------------------------------------------------------------------
 * 段 6｜结果非有限复检（复用 03BB，R90）
 *      Result non-finite recheck, code reused per R90
 *-----------------------------------------------------------------------------*)
bNonFin := (fQ2 <> fQ2) OR (ABS(fQ2) > DL_FLR_INF)
        OR (fP2 <> fP2) OR (ABS(fP2) > DL_FLR_INF)
        OR (fW2 <> fW2) OR (ABS(fW2) > DL_FLR_INF); // 三参数溢出判定 / Overflow check on the three parameters
IF bNonFin THEN
    fQ2 := DL_FLR_ZERO;                     // 溢出即输出 0（安全侧） / Overflow yields zero
    fP2 := DL_FLR_ZERO;                     // 溢出即输出 0 / Overflow yields zero
    fW2 := DL_FLR_ZERO;                     // 溢出即输出 0 / Overflow yields zero
    eErr   := 16#0001_03BB;                 // 故障级：结果溢出复用输入非法码（R90） / Fault: overflow, code reused per R90
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退 / Early return
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜出口
 *      Exit
 *-----------------------------------------------------------------------------*)
bValid := TRUE;                             // 结果可用（含 046C 钳位情形） / Result usable, including the clamped case
FC_DL_FanLawRootCalc := TRUE;               // 返回 TRUE = 换算有效 / Return TRUE = scaling valid
END_FUNCTION
