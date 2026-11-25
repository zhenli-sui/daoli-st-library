(*
  Name: FC_DL_TireCureMoldCycleTimeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 模压周期按「合模 + 升温 + 保温 + 排凝 + 开模」五段求和：
           fCycleMin = tClose + tHeat + tHold + tBlowDown + tOpen，各段以分钟给出，同量纲直加。
        2) 输出保温段占比 fHoldSharePct = tHold / 总周期 * 100，用于判断周期结构是否合理
           （硫化周期的绝大部分应为保温段；保温占比过低意味着辅助动作时间过长、机台利用率差）。
        3) 分段零值容错：允许任一段为 0（例如无排凝动作的机台把 tBlowDown 组态为 0），
           但总周期必须 > DL_EPS，否则「零周期」无法作为节拍基准，判无效。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（总周期与占比强制 0.0），不得只置标志（R19）。
        2) 分段非负闸：任一段为负即判无效（负时长属组态错，求和时会被掩盖成「周期偏短」），
           绝不取绝对值或按 0 处理。
        3) 总周期零闸：总周期 <= DL_EPS 时占比式分母为零，判无效并清零，不输出无穷大占比。
        4) 分段上限闸：单段超过 DL_SEG_HI_MIN（12 小时）判无效 —— 超过整模寿命量级的组态
           几乎必然是单位用错（秒当作分）。
        5) 判据取原始值（R24）：总周期与占比越域判定均使用钳制前的原始值，不先钳后判。
        6) 物理域钳制：总周期钳 0.0 ~ DL_CYCLE_HI_MIN；占比钳 0.0 ~ DL_PCT_HI。
  量纲自证：五段均为 [min]，直加得 [min]；
           fHoldSharePct = (min)/(min)*100 = 无因次百分数 [%]，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureMoldCycleTimeCalc : BOOL
VAR_INPUT
    fCloseMin        : REAL;   // 合模段时长 [min] / Mold closing segment duration [min]
    fHeatMin         : REAL;   // 升温段时长 [min] / Heat-up segment duration [min]
    fHoldMin         : REAL;   // 保温（硫化）段时长 [min] / Curing hold segment duration [min]
    fBlowDownMin     : REAL;   // 排凝段时长 [min] / Blowdown segment duration [min]
    fOpenMin         : REAL;   // 开模段时长 [min] / Mold opening segment duration [min]
END_VAR
VAR_OUTPUT
    fCycleMin        : REAL;   // 模压周期总时长 [min] / Total mold cycle time [min]
    fHoldSharePct    : REAL;   // 保温段占周期百分比 [%] / Hold segment share of the cycle [%]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fCycleRawMin    : REAL;   // 钳制前的原始总周期 [min] / Raw total cycle before limiting [min]
    _fShareRawPct    : REAL;   // 钳制前的原始占比 [%] / Raw share before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 占比物理上限 [%] / Share upper bound [%]
    DL_SEG_HI_MIN    : REAL := 720.0;     // 单段时长上限（12 小时）[min] / Single segment upper bound, 12 h [min]
    DL_CYCLE_HI_MIN  : REAL := 720.0;     // 总周期物理上限 [min] / Total cycle physical upper bound [min]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fCloseMin > -DL_BIG AND fCloseMin < DL_BIG)
   OR NOT (fHeatMin > -DL_BIG AND fHeatMin < DL_BIG)
   OR NOT (fHoldMin > -DL_BIG AND fHoldMin < DL_BIG)
   OR NOT (fBlowDownMin > -DL_BIG AND fBlowDownMin < DL_BIG)
   OR NOT (fOpenMin > -DL_BIG AND fOpenMin < DL_BIG) THEN
    fCycleMin := 0.0;                       // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fHoldSharePct := 0.0;                   // 占比强制 0.0 / Share forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureMoldCycleTimeCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分段非负闸与上限闸（负时长会把周期掩盖成偏短，必须判无效） —— *)
IF (fCloseMin < 0.0) OR (fHeatMin < 0.0) OR (fHoldMin < 0.0)
   OR (fBlowDownMin < 0.0) OR (fOpenMin < 0.0) THEN
    fCycleMin := 0.0;                       // 负时长即不可算 / Negative duration is not computable
    fHoldSharePct := 0.0;                   // 占比不可算 / Share not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureMoldCycleTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF
IF (fCloseMin > DL_SEG_HI_MIN) OR (fHeatMin > DL_SEG_HI_MIN)
   OR (fHoldMin > DL_SEG_HI_MIN) OR (fBlowDownMin > DL_SEG_HI_MIN)
   OR (fOpenMin > DL_SEG_HI_MIN) THEN
    fCycleMin := 0.0;                       // 段长越上限：单位多半用错 / Segment too long, unit error likely
    fHoldSharePct := 0.0;                   // 占比不可算 / Share not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureMoldCycleTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fCycleRawMin := fCloseMin + fHeatMin + fHoldMin + fBlowDownMin + fOpenMin;        // 总周期 [min]

(* —— 段 4：总周期零闸（占比式分母） —— *)
IF _fCycleRawMin <= DL_EPS THEN
    fCycleMin := 0.0;                       // 零周期即不可算 / Zero cycle is not computable
    fHoldSharePct := 0.0;                   // 占比不可算 / Share not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureMoldCycleTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

_fShareRawPct := fHoldMin / _fCycleRawMin * DL_PCT;                               // 保温段占比 [%]

(* —— 段 5：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (_fCycleRawMin <= DL_CYCLE_HI_MIN)                                      // 不超总周期物理上限
          AND (_fShareRawPct >= 0.0)                                              // 占比不得为负
          AND (_fShareRawPct <= DL_PCT_HI);                                       // 占比不得超 100 %

(* —— 段 6：输出单点写盘（钳制到物理域内，判定结果已在段 5 定案） —— *)
fCycleMin := LIMIT(0.0, _fCycleRawMin, DL_CYCLE_HI_MIN);                           // 总周期钳物理域 [min]
fHoldSharePct := LIMIT(0.0, _fShareRawPct, DL_PCT_HI);                             // 占比钳 0..100 [%]
FC_DL_TireCureMoldCycleTimeCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
