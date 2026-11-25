(*
  Name: FC_DL_JiggerLiquorRatioCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  说明：本件与在册 FC_DL_DyeLiquorRatioCalc（由「重量 × 浴比」正算总液量）方向相反，
        本件由「实测液量 ÷ 实测布重」反算实际浴比并做工艺区间判定，输入输出契约无交集，
        属同族内的对偶量而非重复实现（R13 语义查重结论：非重复）。
  功能：1) 实际浴比按「染液体积 / 被染物质量」计算：ratio = V / m，单位 L/kg，
           分母取被染物质量、分子取染液体积，方向固定不可交换（浴比是「每公斤布配多少升液」）。
        2) 工艺区间判定：fRatioLoLkg <= ratio <= fRatioHiLkg 输出 xInBand；
           低于下限判 xRatioLow（浴比过小、布在缸内易打结起皱、染色不匀）；
           高于上限判 xRatioHigh（浴比过大、助剂浪费、污水负荷高）。
        3) 输出偏差量 fDevLkg = ratio − 区间中值，作为补液/排液的前馈修正量
           （正偏差需排液，负偏差需补液，方向由符号给出）。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（浴比与偏差强制 0.0），不得只置标志（R19）。
        2) 重量零闸：被染物质量 fFabricKg 必须 > DL_EPS（浴比式的分母）；
           为零时浴比发散，判无效并清零，绝不输出「无穷大浴比」。
        3) 液量非负闸：染液体积不得为负（负体积属液位计反向或组态错），判无效。
        4) 区间域闸：须满足 0.0 < fRatioLoLkg < fRatioHiLkg <= DL_RATIO_HI_LKG，
           否则两级判据重叠或倒置，越域判无效并把偏低位置真（保守侧）。
        5) 判据取原始值（R24）：区间判定使用钳制前的 _fRatioRawLkg，钳制只作用于输出。
        6) 纯函数无状态：补液/排液的累计与联锁由上层染缸批次序 FB 承担。
  量纲自证：ratio = (L)/(kg) = L/kg，与两个区间阈同量纲，可直接比较；
           fDevLkg = (L/kg) − (L/kg) = L/kg，减法两侧同量纲，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_JiggerLiquorRatioCalc : BOOL
VAR_INPUT
    fLiquorVolL      : REAL;   // 染液实际体积 [L] / Actual dye liquor volume [L]
    fFabricKg        : REAL;   // 被染物（布卷）质量 [kg] / Fabric batch mass [kg]
    fRatioLoLkg      : REAL;   // 工艺浴比下限 [L/kg] / Process liquor ratio low limit [L/kg]
    fRatioHiLkg      : REAL;   // 工艺浴比上限 [L/kg] / Process liquor ratio high limit [L/kg]
END_VAR
VAR_OUTPUT
    fRatioLkg        : REAL;   // 实际浴比 [L/kg] / Actual liquor ratio [L/kg]
    fDevLkg          : REAL;   // 相对区间中值的偏差 [L/kg] / Deviation from the band mid value [L/kg]
    xRatioLow        : BOOL;   // 低于下限标志 [bool] / Below the low limit flag [bool]
    xRatioHigh       : BOOL;   // 高于上限标志 [bool] / Above the high limit flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRatioRawLkg    : REAL;   // 钳制前的原始浴比 [L/kg] / Raw liquor ratio before limiting [L/kg]
    _fMidLkg         : REAL;   // 区间中值 [L/kg] / Mid value of the band [L/kg]
    _fDevRawLkg      : REAL;   // 钳制前的原始偏差 [L/kg] / Raw deviation before limiting [L/kg]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_HALF          : REAL := 0.5;       // 区间中值折算系数 [-] / Band mid-point factor [-]
    DL_RATIO_HI_LKG  : REAL := 100.0;     // 浴比物理上限 [L/kg] / Liquor ratio physical upper bound [L/kg]
    DL_DEV_SPAN      : REAL := 100.0;     // 偏差钳制跨度 [L/kg] / Deviation clamp span [L/kg]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fLiquorVolL > -DL_BIG AND fLiquorVolL < DL_BIG)
   OR NOT (fFabricKg > -DL_BIG AND fFabricKg < DL_BIG)
   OR NOT (fRatioLoLkg > -DL_BIG AND fRatioLoLkg < DL_BIG)
   OR NOT (fRatioHiLkg > -DL_BIG AND fRatioHiLkg < DL_BIG) THEN
    fRatioLkg := 0.0;                       // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDevLkg := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xRatioLow := TRUE;                      // 失效侧按偏低处理（保守侧：提示补液）
    xRatioHigh := FALSE;                    // 失效侧偏高位保持假 / High flag stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_JiggerLiquorRatioCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：重量零闸与区间域闸（分母为布重） —— *)
IF (fFabricKg <= DL_EPS)                                          // 布重不可为零
   OR (fLiquorVolL < 0.0)                                         // 液量不得为负
   OR (fRatioLoLkg <= 0.0)                                        // 区间下限必须为正
   OR (fRatioHiLkg <= fRatioLoLkg)                                // 区间必须有效（hi > lo）
   OR (fRatioHiLkg > DL_RATIO_HI_LKG) THEN                        // 上限须在物理域内
    fRatioLkg := 0.0;                       // 布重为零即不可算 / No mass, no ratio
    fDevLkg := 0.0;                         // 偏差不可算 / Deviation not computable
    xRatioLow := TRUE;                      // 按偏低处理（保守侧）/ Treat as low
    xRatioHigh := FALSE;                    // 偏高位保持假 / High flag stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_JiggerLiquorRatioCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fRatioRawLkg := fLiquorVolL / fFabricKg;                                         // 实际浴比 [L/kg]
_fMidLkg := (fRatioLoLkg + fRatioHiLkg) * DL_HALF;                                // 区间中值 [L/kg]
_fDevRawLkg := _fRatioRawLkg - _fMidLkg;                                          // 相对中值偏差 [L/kg]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xRatioLow := (_fRatioRawLkg < fRatioLoLkg);                                       // 低于下限
xRatioHigh := (_fRatioRawLkg > fRatioHiLkg);                                      // 高于上限
xValid := (_fRatioRawLkg >= 0.0)                                                  // 浴比不得为负
          AND (_fRatioRawLkg <= DL_RATIO_HI_LKG)                                  // 不超物理上限（量级异常）
          AND (_fMidLkg > 0.0);                                                   // 中值必须为正（区间已验）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fRatioLkg := LIMIT(0.0, _fRatioRawLkg, DL_RATIO_HI_LKG);                          // 浴比钳物理域 [L/kg]
fDevLkg := LIMIT(-DL_DEV_SPAN, _fDevRawLkg, DL_DEV_SPAN);                          // 偏差钳物理域 [L/kg]
FC_DL_JiggerLiquorRatioCalc := xValid;                                            // 返回码：TRUE = 计算可信

END_FUNCTION
