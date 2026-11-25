(*
  Name: FC_DL_DyeShadeDeltaCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 色差按 CIE76 色差公式（CIE 1976 L*a*b* 空间的欧氏距离）计算：
           dE = SQRT(dL^2 + da^2 + db^2)，
           其中 dL = L_sample − L_std、da = a_sample − a_std、db = b_sample − b_std，
           标准样与被测样必须取自同一光源/观察者条件（D65 / 10 deg）下的测色值。
           CIE76 为不带权重的等距公式，计算稳定、可复现，是染厂判色的基准口径。
        2) 三档判定（nGrade）：0 = 合格（dE <= fPassDE）、1 = 返修（可回修，<= fReworkDE）、
           2 = 回修（超出返修上限，须改色或降级），两级阈值由工艺按订单要求给定。
        3) 亮度分量 dL 单独输出：dL 与 |da|/|db| 的大小关系决定纠偏方向
           （dL 主导调深浅，a/b 主导调色光），供配色系统选配方。
  边界条件：1) 非有限值闸：六路 Lab 入参与两路阈值先过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即闸断实值通路（色差强制 0.0 且分级置 2 = 回修，保守侧），
           不得只置标志（R19）。
        2) 量级闸：Lab 各分量必须落在 [-DL_LAB_SPAN, +DL_LAB_SPAN] 内（L* 为 0~100、a*/b* 约 ±128），
           越域说明色差仪标定丢失或数据通道错位，判无效。
        3) 阈值域闸：须满足 0.0 < fPassDE < fReworkDE，且 fReworkDE <= DL_DE_HI，
           否则三档判定区间为空、某档永不触发，判无效并把分级置 2（保守侧）。
        4) 平方和防溢出：三个分量的平方和先做量级闸（各分量有界 => 平方和有界），
           SQRT 前不再额外钳制，量级闸是唯一入口，避免「先钳后判」使判据恒真（R24）。
        5) 判据取原始值（R24）：三档判定使用未钳制的 _fDeltaERaw，钳制只作用于输出数值。
        6) 纯函数无状态：多测点平均色差与首件/末件比对由上层判色模块承担。
  量纲自证：dL / da / db 与 Lab 分量同为无因次色度值（CIE L*a*b* 为无量纲量）；
           dE = SQRT(无因次^2 * 3) = 无因次，与阈值 fPassDE / fReworkDE 同量纲。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_DyeShadeDeltaCalc : BOOL
VAR_INPUT
    fLStd            : REAL;   // 标准样明度 L* [-]/ Standard lightness L* [-]
    fAStd            : REAL;   // 标准样红绿色度 a* [-]/ Standard redness-greenness a* [-]
    fBStd            : REAL;   // 标准样黄蓝色度 b* [-]/ Standard yellowness-blueness b* [-]
    fLSample         : REAL;   // 被测样明度 L* [-]/ Sample lightness L* [-]
    fASample         : REAL;   // 被测样红绿色度 a* [-]/ Sample redness-greenness a* [-]
    fBSample         : REAL;   // 被测样黄蓝色度 b* [-]/ Sample yellowness-blueness b* [-]
    fPassDE          : REAL;   // 合格色差上限 [-]/ Colour difference acceptance limit [-]
    fReworkDE        : REAL;   // 返修色差上限 [-]/ Colour difference rework limit [-]
END_VAR
VAR_OUTPUT
    fDeltaE          : REAL;   // 色差 dE（CIE76）[-]/ Colour difference dE, CIE76 [-]
    fDeltaL          : REAL;   // 明度差 dL（带符号）[-]/ Lightness difference, signed [-]
    nGrade           : INT;    // 判定 0=合格 1=返修 2=回修 [level] / Verdict 0=pass 1=reworkable 2=reject [level]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDeltaL         : REAL;   // 明度差分量 [-]/ Lightness difference component [-]
    _fDeltaA         : REAL;   // 红绿色度差分量 [-]/ Redness-greenness difference component [-]
    _fDeltaB         : REAL;   // 黄蓝色度差分量 [-]/ Yellowness-blueness difference component [-]
    _fSumSq          : REAL;   // 三分量平方和 [-]/ Sum of squared components [-]
    _fDeltaERaw      : REAL;   // 未钳制的色差 [-]/ Unclamped colour difference [-]
END_VAR
VAR CONSTANT
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_LAB_SPAN      : REAL := 500.0;     // Lab 分量量级闸跨度 [-] / Lab component magnitude gate span [-]
    DL_DE_HI         : REAL := 500.0;     // 色差物理上限 [-] / Colour difference physical upper bound [-]
    DL_GRADE_OK      : INT := 0;          // 判定：合格 [level] / Verdict: pass [level]
    DL_GRADE_REWORK  : INT := 1;          // 判定：返修 [level] / Verdict: reworkable [level]
    DL_GRADE_REJECT  : INT := 2;          // 判定：回修 [level] / Verdict: reject [level]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧分级置回修） —— *)
IF NOT (fLStd > -DL_BIG AND fLStd < DL_BIG)
   OR NOT (fAStd > -DL_BIG AND fAStd < DL_BIG)
   OR NOT (fBStd > -DL_BIG AND fBStd < DL_BIG)
   OR NOT (fLSample > -DL_BIG AND fLSample < DL_BIG)
   OR NOT (fASample > -DL_BIG AND fASample < DL_BIG)
   OR NOT (fBSample > -DL_BIG AND fBSample < DL_BIG)
   OR NOT (fPassDE > -DL_BIG AND fPassDE < DL_BIG)
   OR NOT (fReworkDE > -DL_BIG AND fReworkDE < DL_BIG) THEN
    fDeltaE := 0.0;                         // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDeltaL := 0.0;                         // 明度差强制 0.0 / Lightness difference forced to zero
    nGrade := DL_GRADE_REJECT;              // 失效侧按回修处理（保守侧）/ Treat as reject when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_DyeShadeDeltaCalc := FALSE;       // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：量级闸与阈值域闸（Lab 越域与阈值倒置都使判定失效） —— *)
IF (ABS(fLStd) > DL_LAB_SPAN) OR (ABS(fAStd) > DL_LAB_SPAN) OR (ABS(fBStd) > DL_LAB_SPAN)
   OR (ABS(fLSample) > DL_LAB_SPAN) OR (ABS(fASample) > DL_LAB_SPAN) OR (ABS(fBSample) > DL_LAB_SPAN)
   OR (fPassDE <= 0.0) OR (fReworkDE <= fPassDE) OR (fReworkDE > DL_DE_HI) THEN
    fDeltaE := 0.0;                         // 量级越域即不可算 / Out of range, not computable
    fDeltaL := 0.0;                         // 明度差不可算 / Lightness difference not computable
    nGrade := DL_GRADE_REJECT;              // 按回修处理（保守侧）/ Treat as reject
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_DyeShadeDeltaCalc := FALSE;       // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（CIE76 欧氏距离；分量已由段 2 保证有界，平方和不会溢出） —— *)
_fDeltaL := fLSample - fLStd;                                                     // 明度差 [-]
_fDeltaA := fASample - fAStd;                                                     // 红绿色度差 [-]
_fDeltaB := fBSample - fBStd;                                                     // 黄蓝色度差 [-]
_fSumSq := _fDeltaL * _fDeltaL + _fDeltaA * _fDeltaA + _fDeltaB * _fDeltaB;       // 平方和 [-]
_fDeltaERaw := SQRT(_fSumSq);                                                     // 色差 [-]
fDeltaL := _fDeltaL;                                                              // 明度差出口（供纠偏方向）

(* —— 段 4：三档判定（取原始色差；由上到下判，区间互斥且完整） —— *)
IF _fDeltaERaw <= fPassDE THEN
    nGrade := DL_GRADE_OK;                  // 合格
ELSIF _fDeltaERaw <= fReworkDE THEN
    nGrade := DL_GRADE_REWORK;              // 可返修
ELSE
    nGrade := DL_GRADE_REJECT;              // 回修/降级
END_IF

xValid := (_fDeltaERaw >= 0.0)                                                    // 色差恒非负（SQRT 性质）
          AND (_fDeltaERaw <= DL_DE_HI);                                          // 不超物理上限（量级异常）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fDeltaE := LIMIT(0.0, _fDeltaERaw, DL_DE_HI);                                     // 色差钳物理域 [-]
FC_DL_DyeShadeDeltaCalc := xValid;                                                // 返回码：TRUE = 计算可信

END_FUNCTION
