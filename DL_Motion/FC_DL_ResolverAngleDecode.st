(* ===========================================================================
   组件名   : FC_DL_ResolverAngleDecode
   分类     : DL_Motion / 旋转变压器角度解算
   一句话   : 由 sin/cos 两路幅值解算机械角，arctan2 采用分段线性近似加象限修正
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fSin 正弦路瞬时值 [V]；fCos 余弦路瞬时值 [V]；fAmpMin 最小有效合成幅值 [V]
   输出契约 : 返回值 = 机械角 [rad]，范围 [0, 2π)；xValid 解算有效
              fAmplitude 合成幅值 [V]；fRatioNorm 归一化插值量 0..1（诊断用）
   算法说明 : atan(t) ≈ t / (1 + 0.28086·t^2)，t 为小值/大值（0..1），误差优于 0.005 rad
              象限修正按 atan2 恒等式：|x|≥|y| 取 base，否则取 π/2−base；x<0 取 π−θ，y<0 取 −θ
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverAngleDecode : REAL
VAR_INPUT
    fSin : REAL;                       // 正弦路瞬时值 [V] | sine channel value [V]
    fCos : REAL;                       // 余弦路瞬时值 [V] | cosine channel value [V]
    fAmpMin : REAL := 0.1;             // 最小有效合成幅值 [V] | min valid amplitude [V]
END_VAR
VAR_OUTPUT
    xValid : BOOL;                     // 解算有效标志 | decode valid flag
    fAmplitude : REAL;                 // 合成幅值 [V] | resultant amplitude [V]
    fRatioNorm : REAL;                 // 归一化插值量 0..1 | normalized ratio 0..1
END_VAR
VAR
    _fAbsSin : REAL;                   // 正弦绝对值 [V] | absolute sine [V]
    _fAbsCos : REAL;                   // 余弦绝对值 [V] | absolute cosine [V]
    _fMin : REAL;                      // 两路绝对值较小者 [V] | smaller magnitude [V]
    _fMax : REAL;                      // 两路绝对值较大者 [V] | larger magnitude [V]
    _fT : REAL;                        // 小/大 归一化比 0..1 | small/large ratio 0..1
    _fBase : REAL;                     // 基准角 [rad] | base angle [rad]
    _fOut : REAL;                      // 结果角 [rad] | result angle [rad]
END_VAR

// ---- 输出预置：任何提前返回路径都不会留下未初始化值 ----
xValid := FALSE;
fAmplitude := 0.0;
fRatioNorm := 0.0;
FC_DL_ResolverAngleDecode := 0.0;

// ---- 非有限值拦截：NaN 用自反比较，Inf 用 (x-x)<>(x-x) ----
IF ((fSin <> fSin) OR ((fSin - fSin) <> (fSin - fSin))) THEN
    RETURN;
END_IF
IF ((fCos <> fCos) OR ((fCos - fCos) <> (fCos - fCos))) THEN
    RETURN;
END_IF

_fAbsSin := ABS(fSin);
_fAbsCos := ABS(fCos);
fAmplitude := SQRT(fSin * fSin + fCos * fCos);

// ---- 幅值为零保护：合成幅值不足则角度不可信 ----
IF (fAmpMin <= 0.0) OR (fAmplitude < fAmpMin) THEN
    RETURN;
END_IF
xValid := TRUE;

// ---- 归一化：小值 / 大值 落在 0..1，分母由幅值门限保证非零 ----
_fMax := MAX(_fAbsSin, _fAbsCos);
_fMin := MIN(_fAbsSin, _fAbsCos);
IF _fMax < 0.000000001 THEN
    xValid := FALSE;                                // 双路同时近零，再兜底一次
    RETURN;
END_IF
_fT := _fMin / _fMax;                               // 分母已守卫
fRatioNorm := _fT;

// ---- atan 分段线性近似（t 在 0..1，结果在 0..π/4） ----
_fBase := _fT / (1.0 + 0.28086 * _fT * _fT);

// ---- 象限修正：先按 |x| 与 |y| 的大小关系选基准轴 ----
IF _fAbsCos >= _fAbsSin THEN
    _fOut := _fBase;                                // 以余弦轴为基准
ELSE
    _fOut := 1.570796327 - _fBase;                  // π/2 − base
END_IF

// ---- 符号修正：x<0 折到第二/三象限，y<0 取负角 ----
IF fCos < 0.0 THEN
    _fOut := 3.141592654 - _fOut;
END_IF
IF fSin < 0.0 THEN
    _fOut := -_fOut;
END_IF

// ---- 归一化到 [0, 2π) ----
IF _fOut < 0.0 THEN
    _fOut := _fOut + 6.283185307;
END_IF
IF _fOut >= 6.283185307 THEN
    _fOut := _fOut - 6.283185307;
END_IF

FC_DL_ResolverAngleDecode := _fOut;
END_FUNCTION
