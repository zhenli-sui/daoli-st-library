(*
  Name: FC_DL_JiggerRampRateCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 升温速率按「目标与当前的温差 / 设定升温时间」计算：rate = dT / t，单位 degC/min，
           分母为设定升温时长（分钟），故无需再乘 60，避免二次折算引入量纲错误。
        2) 纤维允许速率上限校验：rate > fRateMaxKmin 输出 xRateOver（超纤维允许速率），
           这是「快速升温导致染料上染过快、产生色花与折痕」的直接判据；
           对涤纶等疏水纤维该上限通常只有 1.0 ~ 1.5 degC/min。
        3) 输出温差 fDeltaK 与速率 fRateKmin 两个量：温差供设备能力校核
           （蒸汽阀全开能否在设定时间内完成），速率供工艺合规校核。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（速率与温差强制 0.0 且置超限位，保守侧），不得只置标志（R19）。
        2) 时间零闸：设定升温时间 fRampMin 必须 > DL_EPS（速率式的分母），
           为零时速率发散，判无效并清零，绝不输出「无穷快升温」。
        3) 温差方向闸：目标温度必须高于当前温度（dT > 0）；dT <= 0 说明这不是升温段
           （可能是降温或保温），本件不适用，判无效而不输出负速率。
        4) 上限域闸：fRateMaxKmin 必须落在 (0.0, DL_RATE_ABS_HI] 内，越域判无效（上限未组态则判据恒假）。
        5) 判据取原始值（R24）：超上限判定使用钳制前的 _fRateRawKmin，钳制只作用于输出。
        6) 纯函数无状态：实际速率（由温度微分测得）与设定速率的比对由上层温控 FB 承担。
  量纲自证：rate = (degC)/(min) = degC/min（温差尺度上与 K/min 等价），
           与 fRateMaxKmin 同量纲，可直接比较；fDeltaK = (degC) − (degC) = K。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_JiggerRampRateCalc : BOOL
VAR_INPUT
    fStartC          : REAL;   // 当前（起点）染液温度 [degC] / Current dye liquor temperature [degC]
    fTargetC         : REAL;   // 目标染液温度 [degC] / Target dye liquor temperature [degC]
    fRampMin         : REAL;   // 设定升温时长 [min] / Planned heating duration [min]
    fRateMaxKmin     : REAL;   // 纤维允许升温速率上限 [K/min] / Fibre-permitted heating rate limit [K/min]
END_VAR
VAR_OUTPUT
    fRateKmin        : REAL;   // 设定升温速率 [K/min] / Planned heating rate [K/min]
    fDeltaK          : REAL;   // 需升高的温差 [K] / Temperature difference to be raised [K]
    xRateOver        : BOOL;   // 超纤维允许速率标志 [bool] / Over fibre-permitted rate flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDeltaRawK      : REAL;   // 未钳制的温差 [K] / Unclamped temperature difference [K]
    _fRateRawKmin    : REAL;   // 钳制前的原始速率 [K/min] / Raw rate before limiting [K/min]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_RATE_ABS_HI   : REAL := 50.0;      // 升温速率绝对物理上限 [K/min] / Absolute rate upper bound [K/min]
    DL_T_SPAN        : REAL := 500.0;     // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧置超限位，保守侧） —— *)
IF NOT (fStartC > -DL_BIG AND fStartC < DL_BIG)
   OR NOT (fTargetC > -DL_BIG AND fTargetC < DL_BIG)
   OR NOT (fRampMin > -DL_BIG AND fRampMin < DL_BIG)
   OR NOT (fRateMaxKmin > -DL_BIG AND fRateMaxKmin < DL_BIG) THEN
    fRateKmin := 0.0;                       // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDeltaK := 0.0;                         // 温差强制 0.0 / Difference forced to zero
    xRateOver := TRUE;                      // 失效侧按超限处理（保守侧：禁止放行升温）
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_JiggerRampRateCalc := FALSE;      // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：时间零闸与上限域闸（分母为设定升温时长） —— *)
IF (fRampMin <= DL_EPS)                                           // 升温时长不可为零
   OR (fRateMaxKmin <= 0.0)                                       // 上限必须为正
   OR (fRateMaxKmin > DL_RATE_ABS_HI)                             // 上限不得超物理上限
   OR (ABS(fStartC) > DL_T_SPAN)                                  // 起点温度量级闸
   OR (ABS(fTargetC) > DL_T_SPAN) THEN                            // 目标温度量级闸
    fRateKmin := 0.0;                       // 时长为零即不可算 / No duration, no rate
    fDeltaK := 0.0;                         // 温差不可用 / Difference not usable
    xRateOver := TRUE;                      // 按超限处理（保守侧）/ Treat as over the limit
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_JiggerRampRateCalc := FALSE;      // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDeltaRawK := fTargetC - fStartC;                                                // 需升温温差 [K]
_fRateRawKmin := _fDeltaRawK / fRampMin;                                          // 设定升温速率 [K/min]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xRateOver := (_fRateRawKmin > fRateMaxKmin);                                      // 超纤维允许速率
xValid := (_fDeltaRawK > 0.0)                                                     // 必须是升温段（方向固定）
          AND (_fRateRawKmin >= 0.0)                                              // 速率不得为负
          AND (_fRateRawKmin <= DL_RATE_ABS_HI);                                  // 不超绝对物理上限

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fRateKmin := LIMIT(0.0, _fRateRawKmin, DL_RATE_ABS_HI);                           // 速率钳物理域 [K/min]
fDeltaK := LIMIT(0.0, _fDeltaRawK, DL_T_SPAN);                                    // 温差钳物理域 [K]
FC_DL_JiggerRampRateCalc := xValid;                                               // 返回码：TRUE = 计算可信

END_FUNCTION
