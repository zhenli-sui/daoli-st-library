(*
  Name: FC_DL_TireCureTempGradientCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 胎面温差按「外表面温度与内表面温度之差」计算：dT = T_outer − T_inner；
           方向固定不可交换（热流由外模经胎体传向内腔），负值表示测温点接反。
        2) 温度梯度按温差除以导热路径长度折算：grad = dT / (path_mm / 1000)，单位 K/m，
           用于判断硫化过程中胎体内部是否处于「急热」状态（梯度大易产生内部应力与海绵）。
           同时给出以 K/mm 计的分级量 fGradKmm，方便工艺按毫米壁厚直观比对。
        3) 温差超限分级（nGrade）：0 = 正常（dT <= fDeltaWarnK）、1 = 预警（<= fDeltaMaxK）、
           2 = 超限（> fDeltaMaxK），供上层决定是否延长预热段或降低外模温度。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（温差与梯度强制 0.0 且分级置 2 = 超限），不得只置标志（R19）。
        2) 路径零闸：导热路径 fPathMm 必须 > DL_EPS（梯度的分母），否则判无效并清零。
        3) 分级阈值域闸：须满足 0.0 < fDeltaWarnK < fDeltaMaxK，否则两级判据区间为空、分级恒失效，
           越域判无效并把 nGrade 置 2（保守侧）。
        4) 温差方向闸：dT 必须 > 0（外表面必须比内表面热），为负属测点错位，判无效，
           不取绝对值掩盖符号错误。
        5) 判据取原始值（R24）：分级使用原始温差与原始梯度，钳制只作用于输出数值。
        6) 物理域钳制：温差钳 0.0 ~ DL_DELTA_HI；梯度钳 0.0 ~ DL_GRAD_HI。
  量纲自证：dT = (degC) − (degC) = (K)；
           grad = (K)/(m) = K/m，另 (K)/(mm) = K/mm；
           两条梯度量同源于 dT 与 path，属同一量纲族的不同长度基准，均已显式标注。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureTempGradientCalc : BOOL
VAR_INPUT
    fOuterC          : REAL;   // 胎面外表面温度 [degC] / Tread outer surface temperature [degC]
    fInnerC          : REAL;   // 胎体内表面温度 [degC] / Tyre inner surface temperature [degC]
    fPathMm          : REAL;   // 外表面到内表面的导热路径长度 [mm] / Conduction path length [mm]
    fDeltaWarnK      : REAL;   // 温差预警阈值 [K] / Temperature difference warning threshold [K]
    fDeltaMaxK       : REAL;   // 温差上限阈值 [K] / Temperature difference upper limit [K]
END_VAR
VAR_OUTPUT
    fDeltaTK         : REAL;   // 胎面温差 [K] / Tread temperature difference [K]
    fGradKmm         : REAL;   // 以毫米为基准的温度梯度 [K/mm] / Gradient per millimetre [K/mm]
    fGradKm          : REAL;   // 以米为基准的温度梯度 [K/m] / Gradient per metre [K/m]
    nGrade           : INT;    // 温差分级 0=正常 1=预警 2=超限 [level] / Difference grade 0/1/2 [level]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDeltaRawK      : REAL;   // 钳制前的原始温差 [K] / Raw temperature difference [K]
    _fGradRawKmm     : REAL;   // 钳制前的原始梯度 [K/mm] / Raw gradient before limiting [K/mm]
    _fGradRawKm      : REAL;   // 钳制前的原始梯度 [K/m] / Raw gradient per metre [K/m]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MM_PER_M      : REAL := 1000.0;    // 米到毫米的折算 [mm/m] / Millimetres per metre [mm/m]
    DL_DELTA_HI      : REAL := 500.0;     // 温差物理上限 [K] / Temperature difference upper bound [K]
    DL_GRAD_HI       : REAL := 1000.0;    // 梯度物理上限 [K/m] / Gradient upper bound [K/m]
    DL_GRADE_OK      : INT := 0;          // 分级：正常 [level] / Grade: normal [level]
    DL_GRADE_WARN    : INT := 1;          // 分级：预警 [level] / Grade: warning [level]
    DL_GRADE_BAD     : INT := 2;          // 分级：超限 [level] / Grade: out of limit [level]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧分级置超限） —— *)
IF NOT (fOuterC > -DL_BIG AND fOuterC < DL_BIG)
   OR NOT (fInnerC > -DL_BIG AND fInnerC < DL_BIG)
   OR NOT (fPathMm > -DL_BIG AND fPathMm < DL_BIG)
   OR NOT (fDeltaWarnK > -DL_BIG AND fDeltaWarnK < DL_BIG)
   OR NOT (fDeltaMaxK > -DL_BIG AND fDeltaMaxK < DL_BIG) THEN
    fDeltaTK := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fGradKmm := 0.0;                        // 梯度强制 0.0 / Gradient forced to zero
    fGradKm := 0.0;                         // 梯度强制 0.0 / Gradient forced to zero
    nGrade := DL_GRADE_BAD;                 // 失效侧按超限处理（保守侧）/ Treat as out of limit when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureTempGradientCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：路径零闸与阈值域闸 —— *)
IF (fPathMm <= DL_EPS)                                            // 路径不可为零（梯度分母）
   OR (fDeltaWarnK <= DL_EPS)                                     // 预警阈值必须为正
   OR (fDeltaMaxK <= fDeltaWarnK) THEN                            // 上限必须严格大于预警阈值
    fDeltaTK := 0.0;                        // 参数不可用即无温差 / No parameter, no difference
    fGradKmm := 0.0;                        // 梯度不可算 / Gradient not computable
    fGradKm := 0.0;                         // 梯度不可算 / Gradient not computable
    nGrade := DL_GRADE_BAD;                 // 按超限处理（保守侧）/ Treat as out of limit
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureTempGradientCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDeltaRawK := fOuterC - fInnerC;                                                 // 胎面温差 [K]
_fGradRawKmm := _fDeltaRawK / fPathMm;                                            // 梯度 [K/mm]
_fGradRawKm := _fDeltaRawK / (fPathMm / DL_MM_PER_M);                             // 梯度 [K/m]

(* —— 段 4：判据与分级（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (_fDeltaRawK > 0.0)                                                     // 外表面必须比内表面热（方向固定）
          AND (_fDeltaRawK <= DL_DELTA_HI)                                        // 不超温差物理上限
          AND (_fGradRawKm > 0.0)                                                 // 梯度必须为正
          AND (_fGradRawKm <= DL_GRAD_HI)                                         // 不超梯度物理上限
          AND (fDeltaMaxK <= DL_DELTA_HI);                                        // 上限阈值须在物理域内

IF NOT xValid THEN
    nGrade := DL_GRADE_BAD;                 // 参数非法：按超限处理（保守侧）
ELSIF _fDeltaRawK > fDeltaMaxK THEN
    nGrade := DL_GRADE_BAD;                 // 温差超上限
ELSIF _fDeltaRawK > fDeltaWarnK THEN
    nGrade := DL_GRADE_WARN;                // 预警带
ELSE
    nGrade := DL_GRADE_OK;                  // 正常
END_IF

(* —— 段 5：输出单点写盘（钳制到物理域内，分级已在段 4 定案） —— *)
fDeltaTK := LIMIT(0.0, _fDeltaRawK, DL_DELTA_HI);                                  // 温差钳物理域 [K]
fGradKmm := LIMIT(0.0, _fGradRawKmm, DL_GRAD_HI);                                  // 梯度钳物理域 [K/mm]
fGradKm := LIMIT(0.0, _fGradRawKm, DL_GRAD_HI);                                    // 梯度钳物理域 [K/m]
FC_DL_TireCureTempGradientCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
