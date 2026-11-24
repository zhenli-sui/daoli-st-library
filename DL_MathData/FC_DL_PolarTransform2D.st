(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PolarTransform2D
 * 所属子库 (Sublibrary) : DL_MathData
 * 前缀     (Prefix)     : FC_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准函数 SQRT / ATAN2 / COS / SIN / ABS / TRUNC，
 *                         零厂商方言、无状态纯函数
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 直角坐标与极坐标双向变换公开数学语义，
 *                         IEC 61131-3 标准语义的道莅防御性实现，
 *                         防平方溢出归一范式借鉴本库 CalcDistance3D 行为定义，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 直角坐标与极坐标双向变换纯函数。正变换输出半径与
 *                         角度（角度单位 deg，值域 0..360）；先取最大分量归一
 *                         防平方溢出；逆变换先做角度归一防大角度精度损失。
 *                         原点正变换合法（r=0、theta=0 写死本头注释）；负半径
 *                         语义歧义按非法拒绝，不替调用方裁定方向。
 * 码位     (Codes)      : 16#0001_0092 信息级：输入非有限（不置故障标志）
 *                         16#0001_0093 信息级：负半径非法拒绝
 *                         16#0001_0094 信息级：角度超域已归一钳位
 *                         16#0001_0095 信息级：变换模式非法（ELSE 兜底拒绝）
 *                         纯函数四槽全信息级：拒绝时 bValid=FALSE 表达不可用，
 *                         不设故障标志引脚（规格 §2 裁定，FC 无故障级语义）。
 * 边界防错 (Boundary)   : 1 非有限判据：x<>x 自反判 NaN 加幅值界双侧判 Inf；
 *                         2 正变换 m=MAX(ABS(x),ABS(y)) 归一后再求平方和；
 *                         3 ATAN2(0,0) 无定义，原点单列直取 theta=0；
 *                         4 角度一律换算为 deg 并归一到 0..360 半开区间；
 *                         5 大角度先取模归一，防三角函数精度损失。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 2）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PolarMode（归属本函数，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PolarMode :
(
    eToPolar := 0,    // 正变换：直角转极，输出半径/角度 deg / To polar, radius and angle in deg
    eToCart  := 1     // 逆变换：极转直角，输入半径/角度 deg / To cartesian, radius and angle in deg
);
END_TYPE

(*==============================================================================
 * 函数: FC_DL_PolarTransform2D（纯函数，无状态，同输入必得同输出）
 *==============================================================================*)
FUNCTION FC_DL_PolarTransform2D : BOOL
VAR_INPUT
    fX      : LREAL;                    // 直角模式：X 坐标；极模式：半径 [mm 或调用方单位] / Cartesian X or radius
    fY      : LREAL;                    // 直角模式：Y 坐标；极模式：角度 [deg] / Cartesian Y or angle in deg
    eMode   : E_DL_PolarMode;           // 变换方向选择 / Transformation direction selector
END_VAR
VAR_OUTPUT
    fA      : LREAL;                    // 极模式输出：半径；直角模式输出：X [同输入单位] / Radius or X output
    fB      : LREAL;                    // 极模式输出：角度 [deg]；直角模式输出：Y [同输入单位] / Angle deg or Y output
    bValid  : BOOL;                     // 结果可用标志 / Result validity flag
    uErrorId : UINT;                    // 信息级码，0 = 无信息 / Info code, 0 = none
END_VAR
VAR
    fMaxC   : LREAL;                    // 最大分量模，防平方溢出归一基准 / Max component magnitude
    fXn     : LREAL;                    // 归一后 X 分量 / Normalised X component
    fYn     : LREAL;                    // 归一后 Y 分量 / Normalised Y component
    fRad    : LREAL;                    // 中间角 [rad] / Intermediate angle [rad]
    fDeg    : LREAL;                    // 中间角 [deg]，归一前 / Intermediate angle [deg] before normalising
    fLim    : LREAL;                    // 有限幅值判界复用寄存 / Finiteness bound register
END_VAR
VAR CONSTANT
    DL_POL_PI     : LREAL := 3.14159265358979323846; // 圆周率 / Pi constant
    DL_POL_DEG180 : LREAL := 180.0;                  // 弧度转角度系数 [deg/rad] / Rad to deg factor
    DL_POL_EPS    : LREAL := 1.0E-300;               // 原点判零容差 / Origin zero tolerance
    DL_POL_FIN    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_POL_ANGMAX : LREAL := 1.0E6;                  // 角度超域判界 [deg]，超界先取模 / Angle range bound [deg] before modulo
END_VAR

// ---- 段 1｜出口默认值：入口即赋确定值，提前 RETURN 前输出已确定 ---------------
FC_DL_PolarTransform2D := TRUE;                       // 返回值默认真，拒绝时显式改 FALSE / Preset TRUE, set FALSE on rejection
fA      := 0.0;                                       // 输出 A 预置零 / Preset output A
fB      := 0.0;                                       // 输出 B 预置零 / Preset output B
bValid  := FALSE;                                     // 可用标志预置假 / Preset invalid
uErrorId := 16#0000;                                  // 信息码清零（UINT 16 位段）/ Clear info code
fLim    := DL_POL_FIN;                                // 判界装载 / Load finiteness bound

// ---- 段 2｜非有限防御：NaN 用 x<>x 自反判，Inf 用幅值双侧判 -------------------
IF (fX <> fX) OR (fY <> fY) OR (ABS(fX) >= fLim) OR (ABS(fY) >= fLim) THEN
    uErrorId := 16#0001_0092;                         // 信息级：输入非有限 / Info: non-finite input
    RETURN;                                           // 拒绝出口，输出保持预置零 / Rejection exit with deterministic zeros
END_IF

// ---- 段 3｜按模式分派（CASE 含 ELSE 非法模式兜底）---------------------------
CASE eMode OF
    eToPolar:
        // 正变换：先取最大分量归一，防 x^2+y^2 溢出（CalcDistance3D 范式）
        fMaxC := MAX(ABS(fX), ABS(fY));               // 最大分量模 / Max component magnitude
        IF fMaxC < DL_POL_EPS THEN
            fA := 0.0;                                // 原点正变换合法：r=0 写死头注释 / Origin is legal, r=0
            fB := 0.0;                                // 原点正变换合法：theta=0 写死头注释 / Origin is legal, theta=0
        ELSE
            fXn := fX / fMaxC;                        // 归一 X / Normalised X
            fYn := fY / fMaxC;                        // 归一 Y / Normalised Y
            fA  := fMaxC * SQRT(fXn * fXn + fYn * fYn); // 归一后半径还原 / Radius restored after normalising
            fRad := ATAN2(fY, fX);                    // 反正切主值 [rad] / Principal arctangent [rad]
            fDeg := fRad * DL_POL_DEG180 / DL_POL_PI; // 换算角度 [deg] / Convert to degrees
            IF fDeg < 0.0 THEN
                fDeg := fDeg + 360.0;                 // 负角归入 0..360 / Wrap negative into 0..360
            END_IF
            IF fDeg >= 360.0 THEN
                fDeg := fDeg - 360.0;                 // 360 边界归一 / Normalise 360 boundary
            END_IF
            fB := fDeg;                               // 角度输出 [deg] / Angle output [deg]
        END_IF
        bValid := TRUE;                               // 正变换成立 / Forward transform valid
    eToCart:
        IF fX < 0.0 THEN
            uErrorId := 16#0001_0093;                 // 信息级：负半径语义歧义拒绝 / Info: negative radius rejected
            RETURN;                                   // 拒绝出口 / Rejection exit
        END_IF
        IF ABS(fY) > DL_POL_ANGMAX THEN
            fDeg := fY - 360.0 * TRUNC(fY / 360.0);   // 超域大角先取模防精度损失 / Huge angle reduced by modulo
            uErrorId := 16#0001_0094;                 // 信息级：角度超域已归一 / Info: angle out of range, normalised
        ELSE
            fDeg := fY;                               // 常规角原值生效 / Normal angle as-is
        END_IF
        fDeg := fDeg - 360.0 * TRUNC(fDeg / 360.0);   // 统一取模归一 / Uniform modulo normalisation
        IF fDeg < 0.0 THEN
            fDeg := fDeg + 360.0;                     // 取模后负值回正 / Wrap residual negative
        END_IF
        fRad := fDeg * DL_POL_PI / DL_POL_DEG180;     // 角度换算 [rad] / Convert to radians
        fA := fX * COS(fRad);                         // X = r·cos(theta) / X from radius and angle
        fB := fX * SIN(fRad);                         // Y = r·sin(theta) / Y from radius and angle
        bValid := TRUE;                               // 逆变换成立 / Inverse transform valid
    ELSE
        uErrorId := 16#0001_0095;                     // 信息级：模式非法兜底拒绝 / Info: illegal mode fallback
        RETURN;                                       // 拒绝出口 / Rejection exit
END_CASE
END_FUNCTION
