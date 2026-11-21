(*
  ==================================================================
  组件名 Component  : FC_DL_HermiteInterp
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 单区间三次 Hermite 插值。由端点值 y0 / y1 与端点斜率 m0 / m1
                      四条件唯一确定区间 [x0, x1] 内的三次多项式，输出插值 y；
                      x 越出区间按端点钳位并置 bClamped，x1 = x0（含反向）判退化
                      （bDegenerate，出口取 y0），任一输入非有限置 bInvalid 且出口取零。
  来源   Source     : t2-1-lgf-math
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；三次 Hermite 基函数为公开
                      数值分析结果，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无方言转换、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做单区间插值，不建全局网格表、不做样条全局连续性（属主边界）；
                      二 区间方向固定 x0 < x1，区间宽度不大于 1.0E-12 一律判退化并取 y0；
                      三 非有限输入不穿透出口，安全侧取常量零（R127）；
                      四 早退分支出口变换与主体一致（R94）：退化分支取 y0 即四条件曲线
                         在退化极限下的正确极限值；
                      五 无全局变量、无外部变量声明、无物理地址寻址、无定时器（纯函数）。
  输出契约 Output contract:
                      y 仅在输入有限时为插值结果；标志优先级 bInvalid > bDegenerate > bClamped；
                      本件为纯函数，无跨扫描周期状态驻留。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 1 · 序号 1）
  ==================================================================
*)

FUNCTION FC_DL_HermiteInterp : LREAL
VAR_INPUT
    x  : LREAL; // 插值自变量 [自变量单位] / independent variable of the interpolation
    x0 : LREAL; // 区间左端点 [自变量单位] / left interval bound
    x1 : LREAL; // 区间右端点 [自变量单位] / right interval bound
    y0 : LREAL; // 左端点函数值 [因变量单位] / function value at the left bound
    y1 : LREAL; // 右端点函数值 [因变量单位] / function value at the right bound
    m0 : LREAL; // 左端点斜率 [因变量每自变量] / slope at the left bound
    m1 : LREAL; // 右端点斜率 [因变量每自变量] / slope at the right bound
END_VAR
VAR_OUTPUT
    bClamped    : BOOL; // x 越出区间已按端点钳位 [-] / x was clamped to an interval bound
    bDegenerate : BOOL; // 区间退化（x1 = x0），出口取 y0 [-] / degenerate interval, the outlet takes y0
    bInvalid    : BOOL; // 任一输入非有限，出口取零 [-] / any input non finite, the outlet takes zero
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 七个输入全部有限 [-] / all seven inputs are finite
    _fDx   : LREAL := 0.0;  // 区间宽度 [自变量单位] / interval width
    _fXUse : LREAL := 0.0;  // 钳位后的插值自变量 [自变量单位] / clamped independent variable
    _fT    : LREAL := 0.0;  // 归一化区间参数（0..1）[无量纲] / normalised interval parameter
    _fT2   : LREAL := 0.0;  // 参数平方 [无量纲] / square of the parameter
    _fT3   : LREAL := 0.0;  // 参数立方 [无量纲] / cube of the parameter
    _fH00  : LREAL := 0.0;  // Hermite 基函数 h00 [无量纲] / Hermite basis h00
    _fH10  : LREAL := 0.0;  // Hermite 基函数 h10 [无量纲] / Hermite basis h10
    _fH01  : LREAL := 0.0;  // Hermite 基函数 h01 [无量纲] / Hermite basis h01
    _fH11  : LREAL := 0.0;  // Hermite 基函数 h11 [无量纲] / Hermite basis h11
END_VAR

// 段 1｜非有限闸（R151 全覆盖）：七个输入逐项判，NaN 自反、Inf 差值自减 / segment 1, finiteness gate over every input
_bFin := (x = x) AND ((x - x) = (x - x)) AND (x0 = x0) AND ((x0 - x0) = (x0 - x0)) AND (x1 = x1) AND ((x1 - x1) = (x1 - x1)) AND (y0 = y0) AND ((y0 - y0) = (y0 - y0)) AND (y1 = y1) AND ((y1 - y1) = (y1 - y1)) AND (m0 = m0) AND ((m0 - m0) = (m0 - m0)) AND (m1 = m1) AND ((m1 - m1) = (m1 - m1)); // 七输入有限性判定 / finiteness verdict over all seven inputs
IF NOT _bFin THEN // 非有限输入 / non finite input
    FC_DL_HermiteInterp := 0.0; // 安全侧取常量零（R127）/ the safe side takes the constant zero
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    bClamped := FALSE; // 钳位标志不成立 / the clamp flag is false
    bDegenerate := FALSE; // 退化标志不成立 / the degenerate flag is false
    RETURN; // 早退 / early return
END_IF
bInvalid := FALSE; // 有限输入，无效标志不成立 / finite input, the invalid flag is false

// 段 2｜退化判据：区间宽度不大于退化阈即取左端点值 / segment 2, degeneracy verdict
_fDx := x1 - x0; // 区间宽度 / interval width
IF _fDx <= 1.0E-12 THEN // 区间退化（含反向区间与等端点）/ the interval is degenerate
    FC_DL_HermiteInterp := y0; // 出口取左端点值（四条件曲线的退化极限，R94 一致出口）/ the outlet takes the left bound value, the degenerate limit of the same curve
    bDegenerate := TRUE; // 置退化标志 / raise the degenerate flag
    bClamped := FALSE; // 钳位标志不成立 / the clamp flag is false
    RETURN; // 早退 / early return
END_IF

// 段 3｜越域钳位 / segment 3, domain clamp
_fXUse := x; // 自变量直通 / the abscissa passes through
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag to false
IF x < x0 THEN // 左越域 / below the left bound
    _fXUse := x0; // 钳到左端点 / clamp to the left bound
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF x > x1 THEN // 右越域 / above the right bound
    _fXUse := x1; // 钳到右端点 / clamp to the right bound
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
END_IF

// 段 4｜Hermite 基函数与四条件插值（幂次以显式乘法展开，禁 **）/ segment 4, Hermite basis and interpolation with explicit multiplications
_fT := (_fXUse - x0) / _fDx; // 归一化参数，除子为区间宽度已证大于退化阈 / normalised parameter, the divisor is the proven width
_fT2 := _fT * _fT; // 参数平方 / square of the parameter
_fT3 := _fT2 * _fT; // 参数立方 / cube of the parameter
_fH00 := 2.0 * _fT3 - 3.0 * _fT2 + 1.0; // 基函数 h00（端点值权重）/ basis h00, the endpoint value weight
_fH10 := _fT3 - 2.0 * _fT2 + _fT; // 基函数 h10（端点斜率权重）/ basis h10, the endpoint slope weight
_fH01 := -2.0 * _fT3 + 3.0 * _fT2; // 基函数 h01 / basis h01
_fH11 := _fT3 - _fT2; // 基函数 h11 / basis h11
FC_DL_HermiteInterp := _fH00 * y0 + _fH10 * _fDx * m0 + _fH01 * y1 + _fH11 * _fDx * m1; // 四条件三次插值 / the cubic interpolation from four conditions
END_FUNCTION
