(*
  Name: FC_DL_MercerShrinkageCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 丝光收缩率按「经纬密度变化」反算：丝光使纤维膨化、纱线屈曲减少，
           单位长度内纱线根数（密度）上升，故收缩率 = (D_after − D_before) / D_after * 100，
           分母取丝光后密度（即按成品基准计），与纺织行业「按成品计收缩」的惯例一致。
        2) 经纬分别输出 fWarpShrinkPct（经向）/ fWeftShrinkPct（纬向），并给出算术平均
           fAvgShrinkPct，供工艺判断丝光均匀性（经纬差过大说明张力控制不一致）。
        3) 负值判异常：密度减少（收缩率为负）在丝光工序物理上不可能（丝光只增密不疏松），
           判 xNegative = TRUE 且 xValid = FALSE，不取绝对值掩盖方向错误。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（三个收缩率强制 0.0），不得只置标志（R19）。
        2) 分母零闸：丝光后密度 fWarpDensityAfter / fWeftDensityAfter 均须 > DL_EPS
           （收缩率式的分母），为零则结果发散，判无效。
        3) 密度非负闸：丝光前密度不得为负（负密度属测点或录入错误），判无效。
        4) 判据取原始值（R24）：负值与量级判定使用钳制前的原始收缩率，钳制只作用于输出。
        5) 物理域钳制：收缩率钳 -DL_SHRINK_SPAN ~ +DL_SHRINK_SPAN（±100 %），
           保留负值观测余量以供上层识别异常方向。
        6) 纯函数无状态：多批次收缩率的统计与工艺纠偏由上层质量模块承担。
  量纲自证：shrink = (根/10cm − 根/10cm) / (根/10cm) * 100 = 无因次百分数 [%]，
           比量上下同为密度量纲（纱线根数/10cm），量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_MercerShrinkageCalc : BOOL
VAR_INPUT
    fWarpDensityBefore : REAL;   // 丝光前经密 [ends/10cm] / Warp density before mercerising [ends/10cm]
    fWarpDensityAfter  : REAL;   // 丝光后经密 [ends/10cm] / Warp density after mercerising [ends/10cm]
    fWeftDensityBefore : REAL;   // 丝光前纬密 [picks/10cm] / Weft density before mercerising [picks/10cm]
    fWeftDensityAfter  : REAL;   // 丝光后纬密 [picks/10cm] / Weft density after mercerising [picks/10cm]
END_VAR
VAR_OUTPUT
    fWarpShrinkPct   : REAL;   // 经向收缩率 [%] / Warp shrinkage [%]
    fWeftShrinkPct   : REAL;   // 纬向收缩率 [%] / Weft shrinkage [%]
    fAvgShrinkPct    : REAL;   // 经纬平均收缩率 [%] / Average shrinkage of warp and weft [%]
    xNegative        : BOOL;   // 出现负收缩（方向异常）标志 [bool] / Negative shrinkage flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fWarpRawPct     : REAL;   // 钳制前的经向收缩率 [%] / Raw warp shrinkage before limiting [%]
    _fWeftRawPct     : REAL;   // 钳制前的纬向收缩率 [%] / Raw weft shrinkage before limiting [%]
    _fAvgRawPct      : REAL;   // 钳制前的平均收缩率 [%] / Raw average before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_TWO           : REAL := 2.0;       // 平均值折算系数 [-] / Average divisor [-]
    DL_DENS_HI       : REAL := 5000.0;    // 密度量级闸上限 [ends/10cm] / Density magnitude upper bound [ends/10cm]
    DL_SHRINK_SPAN   : REAL := 100.0;     // 收缩率钳制跨度 [%] / Shrinkage clamp span [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fWarpDensityBefore > -DL_BIG AND fWarpDensityBefore < DL_BIG)
   OR NOT (fWarpDensityAfter > -DL_BIG AND fWarpDensityAfter < DL_BIG)
   OR NOT (fWeftDensityBefore > -DL_BIG AND fWeftDensityBefore < DL_BIG)
   OR NOT (fWeftDensityAfter > -DL_BIG AND fWeftDensityAfter < DL_BIG) THEN
    fWarpShrinkPct := 0.0;                  // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fWeftShrinkPct := 0.0;                  // 纬向强制 0.0 / Weft forced to zero
    fAvgShrinkPct := 0.0;                   // 平均强制 0.0 / Average forced to zero
    xNegative := TRUE;                      // 失效侧按方向异常处理（保守侧）/ Treat as abnormal when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_MercerShrinkageCalc := FALSE;     // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与量级闸（分母取丝光后密度） —— *)
IF (fWarpDensityAfter <= DL_EPS)                                  // 后经密不可为零
   OR (fWeftDensityAfter <= DL_EPS)                               // 后纬密不可为零
   OR (fWarpDensityBefore < 0.0)                                  // 前经密不得为负
   OR (fWeftDensityBefore < 0.0)                                  // 前纬密不得为负
   OR (fWarpDensityAfter > DL_DENS_HI)                            // 后经密量级闸
   OR (fWeftDensityAfter > DL_DENS_HI)                            // 后纬密量级闸
   OR (fWarpDensityBefore > DL_DENS_HI)                           // 前经密量级闸
   OR (fWeftDensityBefore > DL_DENS_HI) THEN                      // 前纬密量级闸
    fWarpShrinkPct := 0.0;                  // 分母为零即不可算 / No denominator, no ratio
    fWeftShrinkPct := 0.0;                  // 纬向不可算 / Weft not computable
    fAvgShrinkPct := 0.0;                   // 平均不可算 / Average not computable
    xNegative := TRUE;                      // 按方向异常处理（保守侧）/ Treat as abnormal
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_MercerShrinkageCalc := FALSE;     // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fWarpRawPct := (fWarpDensityAfter - fWarpDensityBefore) / fWarpDensityAfter * DL_PCT;   // 经向 [%]
_fWeftRawPct := (fWeftDensityAfter - fWeftDensityBefore) / fWeftDensityAfter * DL_PCT;   // 纬向 [%]
_fAvgRawPct := (_fWarpRawPct + _fWeftRawPct) / DL_TWO;                                   // 平均 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xNegative := (_fWarpRawPct < 0.0) OR (_fWeftRawPct < 0.0);                        // 密度减少：方向异常
xValid := (NOT xNegative)                                                         // 丝光只增密不疏松
          AND (_fWarpRawPct <= DL_SHRINK_SPAN)                                    // 不超钳制跨度（量级异常）
          AND (_fWeftRawPct <= DL_SHRINK_SPAN)                                    // 不超钳制跨度
          AND (_fAvgRawPct >= 0.0);                                               // 平均值非负（与方向闸一致）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fWarpShrinkPct := LIMIT(-DL_SHRINK_SPAN, _fWarpRawPct, DL_SHRINK_SPAN);            // 经向钳 ±100 [%]
fWeftShrinkPct := LIMIT(-DL_SHRINK_SPAN, _fWeftRawPct, DL_SHRINK_SPAN);            // 纬向钳 ±100 [%]
fAvgShrinkPct := LIMIT(-DL_SHRINK_SPAN, _fAvgRawPct, DL_SHRINK_SPAN);              // 平均钳 ±100 [%]
FC_DL_MercerShrinkageCalc := xValid;                                              // 返回码：TRUE = 计算可信

END_FUNCTION
