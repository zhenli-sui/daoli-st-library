(*
  Name: FC_DL_ClinkerCoolingRateCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 熟料冷却速率按「两测温点温差除以停留时间」计算，单位统一折算为 K/min：
           fRateKmin = (fTempUpC − fTempDownC) / fDwellMin，
           停留时间已在引脚上以分钟给出（min），故无需再乘 60，避免二次折算引入量纲错误。
        2) 速率上下限约束由 fRateLoKmin / fRateHiKmin 给出：低于下限说明冷却不足
           （急冷段不够，C3S 晶型转化不充分、易磨性变差）；高于上限说明冷却过激
           （篦床拉速过快或风量过大，篦板热应力与磨损加剧）。
        3) 输出温差 fDropK 与速率 fRateKmin，两个方向越限位各占一个布尔，便于上层分别处置。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 时间零闸：停留时间 fDwellMin <= DL_EPS 时不做除法（分母为零），判无效并清零全部输出。
        3) 温差方向闸：fTempUpC 必须严格高于 fTempDownC，温差为负属测点接反或标签错位，判无效，
           不取绝对值掩盖符号错误（取绝对值会把接反的测点伪装成正常冷却）。
        4) 限值域闸：0.0 <= fRateLoKmin < fRateHiKmin，否则上下限判据同时失效，视为组态错误判无效。
        5) 判据取原始值（R24）：越限判定使用钳制前的 _fRateRawKmin，不得先钳再判。
        6) 物理域钳制：速率钳 0.0 ~ DL_RATE_HI_KMIN；温差钳 >= 0。
  量纲自证：fDropK = (degC) − (degC) = (K)；
           fRateKmin = (K)/(min) = K/min，与 fRateLoKmin / fRateHiKmin 同量纲 [K/min]，可直接比较。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_ClinkerCoolingRateCalc : BOOL
VAR_INPUT
    fTempUpC         : REAL;   // 上游测点熟料温度 [degC] / Upstream clinker temperature [degC]
    fTempDownC       : REAL;   // 下游测点熟料温度 [degC] / Downstream clinker temperature [degC]
    fDwellMin        : REAL;   // 两测点间熟料停留时间 [min] / Clinker dwell time between the two points [min]
    fRateLoKmin      : REAL;   // 冷却速率工艺下限 [K/min] / Cooling rate process low limit [K/min]
    fRateHiKmin      : REAL;   // 冷却速率工艺上限 [K/min] / Cooling rate process high limit [K/min]
END_VAR
VAR_OUTPUT
    fRateKmin        : REAL;   // 熟料冷却速率 [K/min] / Clinker cooling rate [K/min]
    fDropK           : REAL;   // 两测点温差 [K] / Temperature drop across the two points [K]
    xRateLow         : BOOL;   // 速率低于下限标志 [bool] / Rate below low limit flag [bool]
    xRateHigh        : BOOL;   // 速率高于上限标志 [bool] / Rate above high limit flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDropRawK       : REAL;   // 钳制前的温差 [K] / Raw temperature drop [K]
    _fRateRawKmin    : REAL;   // 钳制前的原始速率 [K/min] / Raw cooling rate before limiting [K/min]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MIN_PER_MIN   : REAL := 1.0;       // 分钟基准折算（引脚已为 min）[min/min] / Minute basis, pin already in minutes [min/min]
    DL_RATE_HI_KMIN  : REAL := 500.0;     // 冷却速率物理上限 [K/min] / Cooling rate physical upper bound [K/min]
    DL_ZERO_K        : REAL := 0.0;       // 温差零基准 [K] / Zero temperature-difference reference [K]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fTempUpC > -DL_BIG AND fTempUpC < DL_BIG)
   OR NOT (fTempDownC > -DL_BIG AND fTempDownC < DL_BIG)
   OR NOT (fDwellMin > -DL_BIG AND fDwellMin < DL_BIG)
   OR NOT (fRateLoKmin > -DL_BIG AND fRateLoKmin < DL_BIG)
   OR NOT (fRateHiKmin > -DL_BIG AND fRateHiKmin < DL_BIG) THEN
    fRateKmin := 0.0;                       // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDropK := 0.0;                          // 温差强制 0.0 / Drop forced to zero
    xRateLow := FALSE;                      // 失效侧越限位保持假 / Limit flags stay false
    xRateHigh := FALSE;                     // 失效侧越限位保持假 / Limit flags stay false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_ClinkerCoolingRateCalc := FALSE;  // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：时间零闸与限值域闸（分母为停留时间） —— *)
IF (fDwellMin <= DL_EPS)                                          // 停留时间不可为零
   OR (fRateLoKmin < 0.0)                                         // 下限不得为负
   OR (fRateHiKmin <= fRateLoKmin) THEN                           // 上限必须严格大于下限
    fRateKmin := 0.0;                       // 分母为零即速率不可算 / No dwell, no rate
    fDropK := 0.0;                          // 温差不可用 / Drop not usable
    xRateLow := FALSE;                      // 越限位保持假 / Limit flags stay false
    xRateHigh := FALSE;                     // 越限位保持假 / Limit flags stay false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_ClinkerCoolingRateCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDropRawK := fTempUpC - fTempDownC;                                              // 两测点温差 [K]
_fRateRawKmin := _fDropRawK / fDwellMin * DL_MIN_PER_MIN;                          // 冷却速率 [K/min]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xRateLow := (_fRateRawKmin < fRateLoKmin);                                        // 低于工艺下限
xRateHigh := (_fRateRawKmin > fRateHiKmin);                                       // 高于工艺上限
xValid := (fRateLoKmin >= 0.0)                                                    // 下限须非负（已验）
          AND (fRateHiKmin <= DL_RATE_HI_KMIN)                                    // 上限不得超物理上限
          AND (_fDropRawK > DL_ZERO_K)                                            // 下游必须比上游冷（方向固定）
          AND (_fRateRawKmin >= DL_ZERO_K);                                       // 速率不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fRateKmin := LIMIT(0.0, _fRateRawKmin, DL_RATE_HI_KMIN);                           // 速率钳 0..物理上限 [K/min]
fDropK := MAX(DL_ZERO_K, _fDropRawK);                                              // 温差钳 >= 0 [K]
FC_DL_ClinkerCoolingRateCalc := xValid;                                            // 返回码：TRUE = 计算可信

END_FUNCTION
