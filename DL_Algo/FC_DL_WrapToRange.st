(*==============================================================================
 * 名称 : FC_DL_WrapToRange —— 周期量卷绕到 [fLo,fHi)（区间宽度 <=0 判参数非法）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将任意输入卷绕到 [fLo, fHi) 周期区间：先平移到以 fLo 为原点，
 *            整周期 TRUNC 截断缩圈，负余量加一周期修正，再加回 fLo。
 *            例：区间 [0,360)、输入 -10 → 350；区间 [100,200)、输入 250 → 150。
 *            边界处理：fHi-fLo<=0 判参数非法（防除零，区间无宽度）；任一
 *            输入非有限（NaN/±Inf）置 eErr 返回 0.0；TRUNC 为 LREAL 通用
 *            形式无整型溢出，结果落在 [fLo,fHi) 左闭右开。
 * 错误码 : 16#0001_1C06 = 区间宽度非法（fHi<=fLo），或输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示卷绕结果可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/除零防护（宽度校验）｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_WrapToRange : LREAL
VAR_INPUT
    fIn : LREAL;    // 待卷绕输入量 [工程单位] / input value to wrap
    fLo : LREAL;    // 区间下界（含）[工程单位] / range lower bound, inclusive
    fHi : LREAL;    // 区间上界（不含）[工程单位] / range upper bound, exclusive
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1C06=区间非法或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=卷绕结果可用 / TRUE when result is usable
END_VAR
VAR
    _fW : LREAL;       // 区间宽度（周期）[工程单位] / range width as period
    _fR : LREAL;       // 平移后的余量 [工程单位] / offset remainder
END_VAR

FC_DL_WrapToRange := 0.0;                    // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn))          // fIn 非有限 / NaN or infinite
   OR (fLo <> fLo) OR ((fLo - fLo) <> (fLo - fLo))        // fLo 非有限 / NaN or infinite
   OR (fHi <> fHi) OR ((fHi - fHi) <> (fHi - fHi)) THEN   // fHi 非有限 / NaN or infinite
    eErr   := 16#0001_1C06;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_fW := fHi - fLo;                            // 计算区间宽度 / compute range width
IF _fW <= 0.0 THEN                           // 宽度非正：参数非法且防除零 / non-positive width invalid
    eErr   := 16#0001_1C06;                  // 置区间非法码 / set invalid-range code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_fR := fIn - fLo;                            // 平移到原点 / shift origin to fLo
_fR := _fR - _fW * TRUNC(_fR / _fW);         // 整周期截断缩圈（TRUNC 向零，防除零已保证）/ strip whole periods
IF _fR < 0.0 THEN                            // 负余量修正 / fix negative remainder
    _fR := _fR + _fW;                        // 加一周期 / add one period
END_IF

FC_DL_WrapToRange := fLo + _fR;              // 加回下界，落 [fLo,fHi) / restore origin

END_FUNCTION
