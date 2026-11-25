(*
  Name: FC_DL_KilnBypassRatioCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 窑尾旁路放风比 = 旁路抽风量 / 窑尾总风量 * 100，分母取窑尾总风量（含旁路），
           方向固定不可交换：分子是被抽走的那一支，分母是全量。
        2) 碱氯负荷约束下的推荐区间由 fRatioLoPct / fRatioHiPct 两个组态引脚给出，
           低于下限意味着碱氯循环富集无法抑制，高于下限则热耗与废气处理负担过大；
           输出 xBelowBand / xAboveBand 两个方向判据，供上层决定增开放风或收小放风。
        3) 偏差量 fDevPct 给出与区间中值的偏移，正值为偏高、负值为偏低，
           作为放风阀 PID 的前馈修正量使用（不做积分，积分在阀门回路内）。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：窑尾总风量 |fKilnTailNm3h| <= DL_EPS 时不做除法，判无效并清零全部输出。
        3) 物理域闸：旁路风量与总风量均不得为负；旁路风量不得大于总风量（超出守恒判无效）；
           推荐区间须满足 0.0 <= lo < hi <= 100.0，否则视为组态错误判无效，不钳制。
        4) 判据取原始值（R24）：区间判定使用钳制前的 _fRatioRawPct，不得先钳再判（否则判据恒真）。
        5) 物理域钳制：放风比钳 0.0 ~ 100.0 %；偏差钳 -100.0 ~ +100.0 %。
        6) 纯函数无状态：区间带内的迟滞与放风阀动作延时由下游回路承担，本件不做回差。
  量纲自证：fBypassPct = (Nm3/h)/(Nm3/h)*100 = 无因次百分数 [%]；
           fDevPct = (无因次百分数) − (无因次百分数) = 无因次百分数 [%]，减法两侧同量纲，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_KilnBypassRatioCalc : BOOL
VAR_INPUT
    fBypassNm3h      : REAL;   // 窑尾旁路放风量 [Nm3/h] / Kiln-tail bypass air flow [Nm3/h]
    fKilnTailNm3h    : REAL;   // 窑尾总风量（含旁路）[Nm3/h] / Total kiln-tail gas flow, bypass included [Nm3/h]
    fRatioLoPct      : REAL;   // 碱氯约束推荐区间下限 [%] / Recommended band low limit, alkali-chloride [%]
    fRatioHiPct      : REAL;   // 碱氯约束推荐区间上限 [%] / Recommended band high limit, alkali-chloride [%]
END_VAR
VAR_OUTPUT
    fBypassPct       : REAL;   // 旁路放风比 [%] / Bypass air ratio [%]
    fDevPct          : REAL;   // 相对区间中值的偏差 [%] / Deviation from the band mid value [%]
    xBelowBand       : BOOL;   // 低于推荐区间标志 [bool] / Below recommended band flag [bool]
    xAboveBand       : BOOL;   // 高于推荐区间标志 [bool] / Above recommended band flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRatioRawPct    : REAL;   // 钳制前的原始放风比 [%] / Raw bypass ratio before limiting [%]
    _fMidPct         : REAL;   // 推荐区间中值 [%] / Mid value of the recommended band [%]
    _fDevRawPct      : REAL;   // 钳制前的原始偏差 [%] / Raw deviation before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_HALF          : REAL := 0.5;       // 区间中值折算系数 [-] / Band mid-point factor [-]
    DL_DEV_LO_PCT    : REAL := -100.0;    // 偏差物理下限 [%] / Deviation physical low [%]
    DL_DEV_HI_PCT    : REAL := 100.0;     // 偏差物理上限 [%] / Deviation physical high [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fBypassNm3h > -DL_BIG AND fBypassNm3h < DL_BIG)
   OR NOT (fKilnTailNm3h > -DL_BIG AND fKilnTailNm3h < DL_BIG)
   OR NOT (fRatioLoPct > -DL_BIG AND fRatioLoPct < DL_BIG)
   OR NOT (fRatioHiPct > -DL_BIG AND fRatioHiPct < DL_BIG) THEN
    fBypassPct := 0.0;                      // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xBelowBand := FALSE;                    // 失效侧区间位保持假 / Band flags stay false
    xAboveBand := FALSE;                    // 失效侧区间位保持假 / Band flags stay false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_KilnBypassRatioCalc := FALSE;     // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（分母为窑尾总风量） —— *)
IF ABS(fKilnTailNm3h) <= DL_EPS THEN
    fBypassPct := 0.0;                      // 无总风量即无放风比 / No total flow, no ratio
    fDevPct := 0.0;                         // 偏差不可算 / Deviation not computable
    xBelowBand := FALSE;                    // 区间位保持假 / Band flags stay false
    xAboveBand := FALSE;                    // 区间位保持假 / Band flags stay false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_KilnBypassRatioCalc := FALSE;     // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fRatioRawPct := fBypassNm3h / fKilnTailNm3h * DL_PCT;                            // 原始放风比 [%]
_fMidPct := (fRatioLoPct + fRatioHiPct) * DL_HALF;                                // 区间中值 [%]
_fDevRawPct := _fRatioRawPct - _fMidPct;                                          // 相对中值偏差 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xBelowBand := (_fRatioRawPct < fRatioLoPct);                                      // 低于推荐下限
xAboveBand := (_fRatioRawPct > fRatioHiPct);                                      // 高于推荐上限
xValid := (fBypassNm3h >= 0.0)                                                    // 旁路风量不得为负
          AND (fKilnTailNm3h > 0.0)                                               // 总风量必须为正
          AND (fBypassNm3h <= fKilnTailNm3h)                                      // 旁路不得大于总量（守恒）
          AND (fRatioLoPct >= 0.0)                                                // 区间下限不得为负
          AND (fRatioHiPct > fRatioLoPct)                                         // 区间必须有效（hi > lo）
          AND (fRatioHiPct <= DL_PCT)                                             // 区间上限不得超过 100 %
          AND (_fRatioRawPct >= 0.0);                                             // 放风比不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fBypassPct := LIMIT(0.0, _fRatioRawPct, DL_PCT);                                   // 放风比钳 0..100 [%]
fDevPct := LIMIT(DL_DEV_LO_PCT, _fDevRawPct, DL_DEV_HI_PCT);                        // 偏差钳 -100..+100 [%]
FC_DL_KilnBypassRatioCalc := xValid;                                               // 返回码：TRUE = 计算可信

END_FUNCTION
