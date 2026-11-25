(*
  Name: FC_DL_GrateCoolerAirBalanceCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 篦冷机风量收支：把各风室冷却风量逐室求和得总冷却风量 fTotalAirNm3h，
           与窑头抽风（二次风 + 三次风 + 余风）合计 fDraftNm3h 做差，
           差值为正即「多余风量」（须经余风排放），差值为负即「亏缺风量」（抽风大于鼓风）。
        2) 不平衡率 fImbalancePct = |鼓风 − 抽风| / 鼓风 * 100，分母取鼓风侧（可测且恒正），
           方向固定不可交换；该值用于判断风量平衡是否在工艺允许带内。
        3) 平衡判据 fImbalancePct <= fBalMaxPct 输出 xBalanced，供上层选择「投自动调节」或「报警」。
  边界条件：1) 非有限值闸：九路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：总冷却风量 |fTotalAirNm3h| <= DL_EPS 时不做除法，全部输出清零并判无效。
        3) 物理域闸：任一风室风量或抽风量为负即判无效（负风量属传感器反向或接线错误），
           不取绝对值掩盖符号错误；fBalMaxPct 须落在 (0.0, 100.0] 内，越域视为未组态。
        4) 判据取原始值（R24）：平衡判定使用钳制前的 _fImbalanceRawPct，不得先钳再判。
        5) 物理域钳制：不平衡率钳 0.0 ~ DL_PCT_HI；多余/亏缺风量钳 >= 0（两者互斥，只一支非零）。
        6) 单点赋值（R26）：多余与亏缺由同一差值按符号分支写入，先置 0 再按分支赋值一次，
           不在多处重复写同一变量；纯函数无状态，不做迟滞。
  量纲自证：fTotalAirNm3h / fDraftNm3h / fExcessNm3h / fDeficitNm3h 均为标态体积流量 [Nm3/h]，
           求和与求差两侧同量纲；
           fImbalancePct = |(Nm3/h) − (Nm3/h)| / (Nm3/h) * 100 = 无因次百分数 [%]，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_GrateCoolerAirBalanceCalc : BOOL
VAR_INPUT
    fChamber1Nm3h    : REAL;   // 1 风室冷却风量 [Nm3/h] / Chamber 1 cooling air flow [Nm3/h]
    fChamber2Nm3h    : REAL;   // 2 风室冷却风量 [Nm3/h] / Chamber 2 cooling air flow [Nm3/h]
    fChamber3Nm3h    : REAL;   // 3 风室冷却风量 [Nm3/h] / Chamber 3 cooling air flow [Nm3/h]
    fChamber4Nm3h    : REAL;   // 4 风室冷却风量 [Nm3/h] / Chamber 4 cooling air flow [Nm3/h]
    fChamber5Nm3h    : REAL;   // 5 风室冷却风量 [Nm3/h] / Chamber 5 cooling air flow [Nm3/h]
    fChamber6Nm3h    : REAL;   // 6 风室冷却风量 [Nm3/h] / Chamber 6 cooling air flow [Nm3/h]
    fDraftNm3h       : REAL;   // 窑头抽风合计（二次+三次+余风）[Nm3/h] / Total kiln-head draft [Nm3/h]
    fBalMaxPct       : REAL;   // 风量平衡允许不平衡率 [%] / Permitted imbalance ratio [%]
END_VAR
VAR_OUTPUT
    fTotalAirNm3h    : REAL;   // 各风室冷却风量合计 [Nm3/h] / Total cooling air flow [Nm3/h]
    fExcessNm3h      : REAL;   // 多余风量（鼓风大于抽风）[Nm3/h] / Excess air flow, blow over draft [Nm3/h]
    fDeficitNm3h     : REAL;   // 亏缺风量（抽风大于鼓风）[Nm3/h] / Deficit air flow, draft over blow [Nm3/h]
    fImbalancePct    : REAL;   // 风量不平衡率 [%] / Air balance imbalance ratio [%]
    xBalanced        : BOOL;   // 风量在允许带内 [bool] / Air balance within tolerance [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDiffNm3h       : REAL;   // 鼓风减抽风的有符号差值 [Nm3/h] / Signed difference, blow minus draft [Nm3/h]
    _fImbalanceRawPct : REAL;  // 钳制前的不平衡率 [%] / Raw imbalance ratio before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 不平衡率物理上限 [%] / Imbalance physical upper bound [%]
    DL_ZERO_NM3H     : REAL := 0.0;       // 风量零基准 [Nm3/h] / Zero flow reference [Nm3/h]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fChamber1Nm3h > -DL_BIG AND fChamber1Nm3h < DL_BIG)
   OR NOT (fChamber2Nm3h > -DL_BIG AND fChamber2Nm3h < DL_BIG)
   OR NOT (fChamber3Nm3h > -DL_BIG AND fChamber3Nm3h < DL_BIG)
   OR NOT (fChamber4Nm3h > -DL_BIG AND fChamber4Nm3h < DL_BIG)
   OR NOT (fChamber5Nm3h > -DL_BIG AND fChamber5Nm3h < DL_BIG)
   OR NOT (fChamber6Nm3h > -DL_BIG AND fChamber6Nm3h < DL_BIG)
   OR NOT (fDraftNm3h > -DL_BIG AND fDraftNm3h < DL_BIG)
   OR NOT (fBalMaxPct > -DL_BIG AND fBalMaxPct < DL_BIG) THEN
    fTotalAirNm3h := 0.0;                   // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fExcessNm3h := 0.0;                     // 多余风量强制 0.0 / Excess forced to zero
    fDeficitNm3h := 0.0;                    // 亏缺风量强制 0.0 / Deficit forced to zero
    fImbalancePct := 0.0;                   // 不平衡率强制 0.0 / Imbalance forced to zero
    xBalanced := FALSE;                     // 失效侧不得报平衡 / Must not report balanced when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GrateCoolerAirBalanceCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：风量求和（六室逐室相加，加法顺序不影响结果） —— *)
fTotalAirNm3h := fChamber1Nm3h + fChamber2Nm3h + fChamber3Nm3h
                 + fChamber4Nm3h + fChamber5Nm3h + fChamber6Nm3h;                  // 鼓风合计 [Nm3/h]
_fDiffNm3h := fTotalAirNm3h - fDraftNm3h;                                          // 鼓风 − 抽风 [Nm3/h]

(* —— 段 3：分母零闸（不平衡率的分母是鼓风合计） —— *)
IF ABS(fTotalAirNm3h) <= DL_EPS THEN
    fExcessNm3h := 0.0;                     // 无鼓风即无多余 / No blow, no excess
    fDeficitNm3h := 0.0;                    // 无鼓风即无亏缺 / No blow, no deficit
    fImbalancePct := 0.0;                   // 不平衡率不可算 / Imbalance not computable
    xBalanced := FALSE;                     // 判非平衡 / Not balanced
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GrateCoolerAirBalanceCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

_fImbalanceRawPct := ABS(_fDiffNm3h) / fTotalAirNm3h * DL_PCT;                    // 原始不平衡率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合） —— *)
xValid := (fChamber1Nm3h >= DL_ZERO_NM3H)                                         // 各室风量不得为负
          AND (fChamber2Nm3h >= DL_ZERO_NM3H)
          AND (fChamber3Nm3h >= DL_ZERO_NM3H)
          AND (fChamber4Nm3h >= DL_ZERO_NM3H)
          AND (fChamber5Nm3h >= DL_ZERO_NM3H)
          AND (fChamber6Nm3h >= DL_ZERO_NM3H)
          AND (fDraftNm3h >= DL_ZERO_NM3H)                                        // 抽风量不得为负
          AND (fBalMaxPct > DL_EPS)                                               // 允许带必须为正
          AND (fBalMaxPct <= DL_PCT_HI);                                          // 允许带不得超过 100 %
xBalanced := xValid AND (_fImbalanceRawPct <= fBalMaxPct);                         // 在允许带内才算平衡

(* —— 段 5：多余/亏缺单点分支写入（互斥两支，各自只写一次，R26） —— *)
fExcessNm3h := 0.0;                                                               // 先置零，避免上拍残值
fDeficitNm3h := 0.0;                                                              // 先置零，避免上拍残值
IF _fDiffNm3h > DL_EPS THEN
    fExcessNm3h := _fDiffNm3h;                                                    // 鼓风大于抽风：多余 [Nm3/h]
ELSIF _fDiffNm3h < -DL_EPS THEN
    fDeficitNm3h := ABS(_fDiffNm3h);                                               // 抽风大于鼓风：亏缺 [Nm3/h]
END_IF

(* —— 段 6：输出单点写盘（不平衡率钳制到物理域） —— *)
fImbalancePct := LIMIT(0.0, _fImbalanceRawPct, DL_PCT_HI);                         // 不平衡率钳 0..100 [%]
FC_DL_GrateCoolerAirBalanceCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
