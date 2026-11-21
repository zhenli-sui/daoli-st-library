(*
  FC_DL_AngleDiffWrap  —  角度差环绕归一至 ±180° / Angle difference wrapped into the plus-minus 180 degree span
  分类 Category : DL_MathData
  版本 Version  : 1.0.0
  来源 Source   : iec-std-wrapper — 标准语义包装族（fMod 归一口径），IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 返回 fAngA - fAngB 归一至 [-180.0, 180.0] 的环绕角差 [deg]；
                  2) 归一口径：先 fMod := 差值 - 360 × TRUNC(差值/360)（fMod 语义），
                  再 fMod > 180 减 360、fMod <= -180 加 360，360° 环绕；
                  3) 进位点向量：正好 ±180.0（含 -180 精确落点）一律归 +180.0，不归 -180.0；
                  4) 非有限输入（NaN 自反判 / Inf 差值自减判）→ 返回 0、故障级 03E0、bValid FALSE。
  边界 Boundary : ① 非有限判定：NaN 用 x <> x 自反判；Inf 用 (x-x) <> (x-x) 判，
                  禁近似阈值（R40 LREAL 口径）；
                  ② 浮点比较禁用 = / <> 判相等（除自反 NaN 判外），进位点用容差 1.0E-6；
                  ③ 无 GVL 依赖：纯函数，无外部变量引用，无物理 IO 地址；
                  ④ 返回角差量纲 [deg]，输入量纲亦须 [deg]，换算由调用方完成。
  依赖 Depends  : 仅 Standard.library（TRUNC / ABS / LREAL 算术）
  码表 Error codes（段 0001，窗口 03E0 / 04A3）:
    16#0001_03E0 故障级：输入非有限（NaN 或 Inf），返回 0，bValid = FALSE，bError = TRUE
    16#0001_04A3 信息级：进位点命中（|结果| = 180.0 容差内，归 +180）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 1 · 序号 3；同日机检后主控重建正文，规格以本头注释为准）
*)

FUNCTION FC_DL_AngleDiffWrap : LREAL
VAR_INPUT
    fAngA       : LREAL;             // 角 A [deg]，量纲须为度 / Angle A in degrees
    fAngB       : LREAL;             // 角 B [deg]，量纲须为度 / Angle B in degrees
END_VAR
VAR_OUTPUT
    eErr        : UDINT;             // 事件码，0 = 正常 / Event code
    bError      : BOOL;              // 故障级标志 / Fault-level flag
    bValid      : BOOL;              // 返回值是否可用 / Result usable flag
END_VAR
VAR
    fDiff       : LREAL;             // 原始差值 [deg] / Raw difference before wrap
    fMod        : LREAL;             // 模 360 中间量 [deg] / Modulo-360 intermediate
END_VAR
VAR CONSTANT
    DL_ADW_TOL       : LREAL := 1.0E-6;         // 进位点容差 [deg] / Tie-point tolerance
    DL_ADW_ERR_NFIN  : UDINT := 16#0001_03E0;   // 故障级：输入非有限 / Fault: non-finite input
    DL_ADW_INFO_TIE  : UDINT := 16#0001_04A3;   // 信息级：进位点命中 / Info: tie-point hit
END_VAR

(* —— 段 1｜返回值与错误状态预置 —— *)
FC_DL_AngleDiffWrap := 0.0;         // 缺省返回 0 / default return zero
eErr := 16#0000_0000;               // 预置无事件 / preset no event
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 预置不可用 / preset unusable

(* —— 段 2｜非有限输入拦截（NaN 自反判 / Inf 差值自减判，R40 LREAL 口径）—— *)
IF (fAngA <> fAngA) OR (fAngB <> fAngB)
   OR ((fAngA - fAngA) <> (fAngA - fAngA))
   OR ((fAngB - fAngB) <> (fAngB - fAngB)) THEN
    FC_DL_AngleDiffWrap := 0.0;     // 非有限输入返回 0 / non-finite input returns zero
    eErr := DL_ADW_ERR_NFIN;        // 置故障级 03E0 / fault code 03E0
    bError := TRUE;                 // 故障标志 / fault flag
    bValid := FALSE;                // 结果不可用 / result unusable
    RETURN;
END_IF

(* —— 段 3｜域内归一（委托 fMod 语义：TRUNC 取整方向与 fMod 一致）—— *)
fDiff := fAngA - fAngB;             // 原始差值 / raw difference
fMod := fDiff - 360.0 * TRUNC(fDiff / 360.0);   // fMod 语义归一 / fMod-semantics normalize
IF fMod > 180.0 THEN                // (180, 360) 区间减一圈 / wrap upper half
    fMod := fMod - 360.0;
END_IF
IF fMod <= -180.0 THEN              // [-360, -180] 区间加一圈（-180 精确落点归 +180）/ wrap lower half
    fMod := fMod + 360.0;
END_IF

(* —— 段 4｜进位点向量：±180 精确落点一律归 +180.0 —— *)
IF ABS(ABS(fMod) - 180.0) <= DL_ADW_TOL THEN    // 容差内视为进位点 / within tolerance is tie point
    fMod := 180.0;                  // 统一归 +180 / unify to +180
    eErr := DL_ADW_INFO_TIE;        // 置信息级 04A3 / info code 04A3
END_IF

(* —— 段 5｜结果复检兜底（防溢出/异常传播）—— *)
IF (fMod <> fMod) OR (fMod < -180.0) OR (fMod > 180.0) THEN
    FC_DL_AngleDiffWrap := 0.0;     // 复检失败返回 0 / recheck failed returns zero
    eErr := DL_ADW_ERR_NFIN;        // 归故障级 / fault-level
    bError := TRUE;
    bValid := FALSE;
    RETURN;
END_IF

FC_DL_AngleDiffWrap := fMod;        // 输出环绕角差 / output wrapped difference
bError := FALSE;                    // 无故障 / no fault
bValid := TRUE;                     // 结果可用 / result usable

END_FUNCTION
