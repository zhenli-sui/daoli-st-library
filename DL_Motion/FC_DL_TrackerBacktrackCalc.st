//==============================================================================
// 函数：FC_DL_TrackerBacktrackCalc ｜ 中文名称：跟踪支架逆跟踪角度修正计算
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：水平单轴（N-S 向）跟踪支架的阴影几何逆跟踪修正。设排距 P、
//           集热宽度 W，GCR = W/P（占空比，域 (0, 1]）。太阳高度角 a、
//           相对轴方位 D（归约到 (-180, 180]）。理想跟踪角与逆跟踪角
//           由本库自有规格的闭式几何解给出：
//           记 A = sin(a)，B = sin(D)·cos(a)，R = SQRT(A^2 + B^2)，
//           phi = ATAN2(B, A)；临界掠射方程 P·sin(a)/W = cos(t)·sin(a)
//           + sin(D)·sin(t)·cos(a) 的解为 cos(t - phi) = A/(GCR·R)；
//           当 A/(GCR·R) >= 1（太阳高或方位接近轴面）无遮蔽，输出理想角
//           phi；否则输出逆跟踪角 phi - sign(D)·ACOS(A/(GCR·R))（朝零回
//           拉的掠射临界解）。结果再按最大旋转角限幅照算（常规机械限位，
//           不占码位）。
// 开源溯源 (Origin)：道莅原创实现（参考跟踪支架逆跟踪阵列阴影几何公开惯例 分类与参数域）
// 单位表：太阳高度角[度] / 太阳方位角[度] / 轴方位角[度] / 相对方位角[度] /
//         GCR[比值] / 旋转角[度] / 最大旋转角[度]
// 错误码表：16#0004_01E3 信息级（逆跟踪修正生效：目标角被掠射临界解回拉，
//           不置 bError）/ 16#0004_01E4 信息级（太阳在地平线下（高度角
//           < 0），夜间无跟踪语义，返回 0 度，不置 bError）/
//           16#0004_0300 故障级（任一输入非有限，或 GCR <= 0 / GCR > 1
//           （集热宽度大于排距，结构性永久遮蔽），或最大旋转角 <= 0，
//           置 bError）/ 16#0004_0301 故障级（几何退化：R < 容差（高度角
//           与相对方位同时趋零，太阳位于轴面地平线，判据无定义），或
//           结果非有限，置 bError——该场景不可由 0300 的组态类判据观测，
//           属几何求解独立域）/ 16#0004_0302 预留禁用（兜底槽；纯函数无
//           状态机兜底场景，不得挪用）
// 状态机：N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底
// 边界行为：① 高度角 < 0（夜间）→ 信息 01E4、输出 0 度、bValid := TRUE
//           （夜间零角是合法输出非故障）；② A/(GCR·R) >= 1 → 无遮蔽段，
//           输出理想角 phi，bBacktrack := FALSE；③ 掠射临界解落零侧
//           （ACOS 项大于 |phi|）→ 输出贴零小角，属低太阳角物理正确
//           行为；④ 结果超过最大旋转角 → 机械限幅照算，不占码位；
//           ⑤ 失能清零不适用（纯函数无使能闸，非法输入即故障早退）；
//           ⑥ 安全侧 = 故障路径输出 0 度并 bValid := FALSE，禁止残角
//           进入驱动层。
// 验收向量（算法已证，手算）：① a=20 度、D=30 度、GCR=0.35 → 无遮蔽，
//           输出 54.0 度；② a=20 度、D=30 度、GCR=0.7 → 逆跟踪 21.3 度；
//           ③ a=-5 度（夜间）→ 0 度 + 信息 01E4；④ a=90 度、D=0 度 →
//           理想角 0 度（正午贴轴）。
//           编译器已证（三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P2 §360）
//==============================================================================

FUNCTION FC_DL_TrackerBacktrackCalc : BOOL
VAR_INPUT
    fSunElevDeg  : LREAL;                   // 太阳高度角 [度]，< 0 判夜间 / Sun elevation [deg], negative means night
    fSunAzDeg    : LREAL;                   // 太阳方位角 [度]，正北起顺时针 0..360 / Sun azimuth [deg], clockwise from north
    fAxisAzDeg   : LREAL := 180.0;          // 旋转轴方位角 [度]，N-S 水平轴典型 180 / Axis azimuth [deg], N-S horizontal typical 180
    fGcrRatio    : LREAL := 0.35;           // 邻排占空比 GCR = W/P [比值]，有效域 (0, 1] / Ground coverage ratio [ratio], valid range (0, 1]
    fMaxAngleDeg : LREAL := 60.0;           // 最大旋转角限幅 [度]，机械限位，须 > 0 / Max rotation angle [deg], mechanical limit, must be > 0
END_VAR
VAR_OUTPUT
    fTrackAngleDeg : LREAL;                 // 目标旋转角 [度]（含逆跟踪修正与限幅） / Target rotation angle [deg], backtrack-corrected and clamped
    bBacktrack     : BOOL;                  // TRUE = 本拍目标角处于逆跟踪修正段 / TRUE = target angle in the backtracking band
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0004_01E3 起信息级、16#0004_0300 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 结果可用标志 / Result usable flag
END_VAR
VAR CONSTANT
    DL_TBT_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_TBT_EPS     : LREAL := 1.0E-6;       // 浮点判零/退化容差 [比值] / Float zero and degeneracy tolerance [ratio]
    DL_TBT_HALF    : LREAL := 180.0;        // 半圆角 [度]，方位差归约半宽 / Half turn [deg], azimuth wrap half-width
    DL_TBT_FULL    : LREAL := 360.0;        // 整圆角 [度]，方位差归约周期 / Full turn [deg], azimuth wrap period
    DL_TBT_DEG2RAD : LREAL := 0.017453292519943295; // 度转弧度系数 [弧度每度]，LREAL 精度字面量（R51） / Deg-to-rad factor [rad/deg], LREAL literal per R51
    DL_TBT_RAD2DEG : LREAL := 57.29577951308232;    // 弧度转度系数 [度每弧度]，LREAL 精度字面量 / Rad-to-deg factor [deg/rad], LREAL literal
    DL_TBT_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [度] / Zero constant, avoids a bare literal [deg]
END_VAR
VAR
    fDeltaRaw : LREAL;                      // 方位差原值 [度] / Raw azimuth difference [deg]
    fDelta    : LREAL;                      // 归约后相对方位角 [度]，(-180, 180] / Wrapped relative azimuth [deg]
    fWrapQ    : LREAL;                      // 归约整数商中间量 [无量纲] / Wrap integer quotient intermediate
    fElevRad  : LREAL;                      // 高度角弧度 [弧度] / Elevation in radians [rad]
    fARad     : LREAL;                      // 临界方程 A = sin(a) [无量纲] / Critical-equation term A
    fBRad     : LREAL;                      // 临界方程 B = sin(D)·cos(a) [无量纲] / Critical-equation term B
    fR        : LREAL;                      // 合成幅值 R = SQRT(A^2 + B^2) [无量纲] / Magnitude R
    fPhi      : LREAL;                      // 理想跟踪角（弧度）[弧度] / Ideal tracking angle [rad]
    fCosC     : LREAL;                      // 掠射参数 A/(GCR·R) [无量纲] / Grazing parameter A divided by GCR times R
    fAcos     : LREAL;                      // ACOS 项 [弧度] / ACOS term [rad]
    fSignD    : LREAL;                      // 方差符号 (+1/-1) [无量纲] / Sign of the azimuth difference
    fOutRad   : LREAL;                      // 输出角暂存（弧度）[弧度] / Output angle staging [rad]
    bNonFin   : BOOL;                       // 非有限判定中间标志 / Non-finite detection intermediate flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜出口默认值：返回值与输出预置（安全侧 = 0 度）
 *      Exit defaults: return value and outputs preset, fail-safe zero
 *-----------------------------------------------------------------------------*)
FC_DL_TrackerBacktrackCalc := FALSE;        // 返回值默认无效 / Return value preset invalid
fTrackAngleDeg := DL_TBT_ZERO;              // 目标角预置 0 / Target angle preset zero
bBacktrack := FALSE;                        // 逆跟踪标志预清零 / Backtrack flag pre-cleared
eErr   := 16#0000_0000;                     // 错误码先清零 / Error code cleared first
bError := FALSE;                            // 故障标志先清零 / Fault flag cleared first
bValid := FALSE;                            // 可用标志先清零 / Usable flag cleared first

(*------------------------------------------------------------------------------
 * 段 2｜输入闸：非有限（R79）+ 组态域（GCR / 最大角）
 *      Input gates: non-finite plus configuration domains
 *-----------------------------------------------------------------------------*)
IF (fSunElevDeg <> fSunElevDeg) OR (ABS(fSunElevDeg) > DL_TBT_INF)
   OR (fSunAzDeg <> fSunAzDeg) OR (ABS(fSunAzDeg) > DL_TBT_INF)
   OR (fAxisAzDeg <> fAxisAzDeg) OR (ABS(fAxisAzDeg) > DL_TBT_INF)
   OR (fGcrRatio <> fGcrRatio) OR (ABS(fGcrRatio) > DL_TBT_INF)
   OR (fMaxAngleDeg <> fMaxAngleDeg) OR (ABS(fMaxAngleDeg) > DL_TBT_INF) THEN
    eErr   := 16#0004_0300;                 // 故障级：输入非有限 / Fault: non-finite input
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退，输出保持 0 度 / Early return, outputs stay zero
END_IF
IF (fGcrRatio <= DL_TBT_EPS) OR (fGcrRatio > 1.0) OR (fMaxAngleDeg <= DL_TBT_EPS) THEN
    eErr   := 16#0004_0300;                 // 故障级：GCR 域外或最大角非法 / Fault: GCR out of domain or illegal max angle
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退 / Early return
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜夜间闸：高度角 < 0 → 信息 01E4，输出 0 度（合法输出）
 *      Night gate: elevation below the horizon yields zero with an info
 *-----------------------------------------------------------------------------*)
IF fSunElevDeg < DL_TBT_ZERO THEN
    eErr := 16#0004_01E4;                   // 信息级：夜间无跟踪语义（不置 bError） / Info: night, no tracking semantics
    bValid := TRUE;                         // 夜间零角为合法输出 / Night zero is a legal output
    FC_DL_TrackerBacktrackCalc := TRUE;     // 返回 TRUE / Return TRUE
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜相对方位归约：减 360 乘整数商，单算式路径（R51 路径纪律）
 *      Relative azimuth wrap by the integer-quotient single expression
 *-----------------------------------------------------------------------------*)
fDeltaRaw := fSunAzDeg - fAxisAzDeg;        // 方位差原值 [度] / Raw azimuth difference
fWrapQ := TRUNC((fDeltaRaw + DL_TBT_HALF) / DL_TBT_FULL); // 整数商（向零截断，除数常量 360 恒非零） / Integer quotient, divisor is a nonzero constant
fDelta := fDeltaRaw - DL_TBT_FULL * fWrapQ; // 归约到 [-180, 180) / Wrapped into [-180, 180)

(*------------------------------------------------------------------------------
 * 段 5｜几何求解：A/B/R/phi 与掠射参数（ATAN2 贴轴归属由内建域保证）
 *      Geometry solve: A, B, R, phi and the grazing parameter
 *-----------------------------------------------------------------------------*)
fElevRad := fSunElevDeg * DL_TBT_DEG2RAD;   // 高度角转弧度 / Elevation to radians
fARad := SIN(fElevRad);                     // A = sin(a) [无量纲] / Term A
fBRad := SIN(fDelta * DL_TBT_DEG2RAD) * COS(fElevRad); // B = sin(D)·cos(a) [无量纲] / Term B
fR := SQRT(fARad * fARad + fBRad * fBRad);  // R = SQRT(A^2 + B^2) [无量纲] / Magnitude R
IF fR < DL_TBT_EPS THEN
    eErr   := 16#0004_0301;                 // 故障级：几何退化（a 与 D 同时趋零） / Fault: geometric degeneracy
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退 / Early return
END_IF
fPhi := ATAN2(fBRad, fARad);                // 理想跟踪角 [弧度]，贴轴归属随内建域 / Ideal angle, on-axis attribution per the built-in
fCosC := fARad / (fGcrRatio * fR);          // 掠射参数 [无量纲] / Grazing parameter

(*------------------------------------------------------------------------------
 * 段 6｜遮蔽判定与逆跟踪解：c >= 1 无遮蔽（纯跟踪）；否则朝零回拉临界解
 *      Shading test and the backtracking solution pulled toward zero
 *-----------------------------------------------------------------------------*)
IF fCosC >= 1.0 THEN
    fOutRad := fPhi;                        // 无遮蔽段：纯理想跟踪 / No shading, pure ideal tracking
ELSE
    fCosC := MIN(MAX(fCosC, DL_TBT_ZERO), 1.0); // 参数入域钳位（数值安全，理论上域 [0,1)） / Parameter clamped into the domain
    fAcos := ACOS(fCosC);                   // ACOS 项 [弧度] / ACOS term
    IF fDelta >= DL_TBT_ZERO THEN
        fSignD := 1.0;                      // 东侧上午支取正号 / Morning side takes the positive sign
    ELSE
        fSignD := -1.0;                     // 西侧下午支取负号 / Afternoon side takes the negative sign
    END_IF
    fOutRad := fPhi - fSignD * fAcos;       // 逆跟踪临界解（朝零回拉） [弧度] / Backtracking critical solution
    bBacktrack := TRUE;                     // 逆跟踪修正生效 / Backtracking correction active
    eErr := 16#0004_01E3;                   // 信息级：逆跟踪修正生效（不置 bError） / Info: backtracking active, no fault flag
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜机械限幅与结果复检（限幅照算不占码位；复检复用 0301，R90）
 *      Mechanical clamp, result recheck with code reused per R90
 *-----------------------------------------------------------------------------*)
fOutRad := MIN(MAX(fOutRad, -fMaxAngleDeg * DL_TBT_DEG2RAD),
               fMaxAngleDeg * DL_TBT_DEG2RAD); // 双侧机械限幅 [弧度] / Two-sided mechanical clamp
bNonFin := (fOutRad <> fOutRad) OR (ABS(fOutRad) > DL_TBT_INF); // 结果非有限判定 / Result non-finite check
IF bNonFin THEN
    fTrackAngleDeg := DL_TBT_ZERO;          // 溢出即输出 0（安全侧） / Overflow yields zero
    eErr   := 16#0004_0301;                 // 故障级：结果非有限复用退化码（R90） / Fault: non-finite result, code reused per R90
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;                                 // 故障早退 / Early return
END_IF
fTrackAngleDeg := fOutRad * DL_TBT_RAD2DEG; // 输出角转度 [度] / Output angle to degrees

(*------------------------------------------------------------------------------
 * 段 8｜出口
 *      Exit
 *-----------------------------------------------------------------------------*)
bValid := TRUE;                             // 结果可用（含 01E3/01E4 提示情形） / Result usable, including notice cases
FC_DL_TrackerBacktrackCalc := TRUE;         // 返回 TRUE = 求解有效 / Return TRUE = solve valid
END_FUNCTION
