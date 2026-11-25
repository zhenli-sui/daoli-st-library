(*
  Name: FC_DL_CoaterSolventBalanceCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 溶剂衡算按「入料带入 − 烘干排出 = 残留」建立：湿涂层质量流量乘以浆料溶剂比例得到
           入料带入的溶剂量，减去排风侧实测带走的溶剂量，差值即留在极片中的残留溶剂量。
           差值的符号口径固定为「带入减排出」：正值 = 有残留（正常），负值 = 排出大于带入
           （物料不平衡，通常是排风侧传感器偏高或入料计量偏低）。
        2) 残留比例 = 残留量 / 带入量 × 100，与残留上限 fResidualLimitPct 比较给出超限标志 xOver。
           比例的分母是「带入量」而不是「排出量」或「湿涂层总量」：判据语义是
           「有多少比例的溶剂没被烘干」，故必须以带入量为基准。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0、xOver 强制 FALSE）
           并置无效（R19），无效数据不得判超限。
        2) 分母零闸：带入溶剂量（fCoatingKgH × fSolventPct/100）必须 ABS > DL_EPS，
           否则残留比例无定义；带入量为 0 表示未涂布，判无效而不输出比例。
        3) 溶剂比例窄闸：fSolventPct 必须落在 0 ~ 100 %，越域钳边界并置无效（超过 100 % 不可能）。
        4) 物料不平衡闸：排出量大于带入量时，差值物理上不可能为正残留，故残留量钳 0、
           残留比例钳 0，并置 xValid=FALSE 上报物料不平衡（不输出负残留掩盖问题）。
        5) 负值闸：涂层质量流量、排出量、上限比例任一为负判无效。
        6) 饱和钳制：残留量钳 0 ~ DL_RES_MAX(10000 kg/h)，残留比例钳 0 ~ 100 %。
  量纲自证：入料带入 = (kg/h) × (%/100) = kg/h；残留 = (kg/h) − (kg/h) = kg/h，减法同量纲；
           残留比例 = (kg/h) / (kg/h) × 100 = 无因次百分数 [%]，与上限比例同量纲；
           本件未出现 kg/h 与 % 直接相加的混算。
*)

FUNCTION FC_DL_CoaterSolventBalanceCalc : BOOL
VAR_INPUT
    fCoatingKgH      : REAL;   // 湿涂层质量流量 [kg/h] / Wet coating mass flow [kg/h]
    fSolventPct      : REAL;   // 浆料溶剂质量比例 [%] / Slurry solvent mass ratio [%]
    fExhaustKgH      : REAL;   // 排风带走溶剂量 [kg/h] / Solvent removed by exhaust [kg/h]
    fResidualLimitPct: REAL;   // 残留溶剂上限 [%] / Residual solvent upper limit [%]
END_VAR
VAR_OUTPUT
    fResidualKgH     : REAL;   // 残留溶剂量 [kg/h] / Residual solvent mass flow [kg/h]
    fResidualPct     : REAL;   // 残留溶剂比例 [%] / Residual solvent ratio [%]
    xOver            : BOOL;   // 残留超限标志 [bool] / Residual over-limit flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSolventRatio   : REAL;   // 归一化溶剂比例 [-] / Normalized solvent ratio [-]
    _fSolventInKgH   : REAL;   // 入料带入溶剂量 [kg/h] / Solvent carried in by coating [kg/h]
    _fResidualRaw    : REAL;   // 未钳制的残留量（可能为负）[kg/h] / Raw residual, may be negative [kg/h]
    _fResidualClamp  : REAL;   // 钳制后的残留量 [kg/h] / Clamped residual [kg/h]
    _fPctRaw         : REAL;   // 未饱和的残留比例 [%] / Raw residual ratio [%]
    _bBalanceOk      : BOOL;   // 物料平衡合法（排出不超过带入）[bool] / Mass balance valid [bool]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_RES_MAX       : REAL := 10000.0;   // 残留量饱和上限 [kg/h] / Residual saturation ceiling [kg/h]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fCoatingKgH > -DL_BIG AND fCoatingKgH < DL_BIG)
   OR NOT (fSolventPct > -DL_BIG AND fSolventPct < DL_BIG)
   OR NOT (fExhaustKgH > -DL_BIG AND fExhaustKgH < DL_BIG)
   OR NOT (fResidualLimitPct > -DL_BIG AND fResidualLimitPct < DL_BIG) THEN
    fResidualKgH := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fResidualPct := 0.0;                    // 比例强制 0.0 / Ratio forced to zero
    xOver := FALSE;                         // 超限强制 FALSE / Over-limit forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CoaterSolventBalanceCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：负值闸（流量与上限比例均不可为负） —— *)
IF (fCoatingKgH < 0.0) OR (fExhaustKgH < 0.0) OR (fResidualLimitPct < 0.0) THEN
    fResidualKgH := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fResidualPct := 0.0;                    // 比例强制 0.0 / Ratio forced to zero
    xOver := FALSE;                         // 超限强制 FALSE / Over-limit forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterSolventBalanceCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：带入溶剂量与分母零闸（R4：带入量是残留比例的分母） —— *)
_fSolventRatio := LIMIT(0.0, fSolventPct, DL_PCT) / DL_PCT;       // 溶剂比例归一并钳 0..100 %
_fSolventInKgH := fCoatingKgH * _fSolventRatio;                   // 入料带入溶剂量 [kg/h]
IF ABS(_fSolventInKgH) <= DL_EPS THEN
    fResidualKgH := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fResidualPct := 0.0;                    // 比例强制 0.0 / Ratio forced to zero
    xOver := FALSE;                         // 超限强制 FALSE / Over-limit forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterSolventBalanceCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：衡算主算式（R22 符号方向自核：带入减排出，正值 = 有残留） —— *)
_fResidualRaw := _fSolventInKgH - fExhaustKgH;                    // 残留量 [kg/h]（可能为负）
_bBalanceOk := (_fResidualRaw >= 0.0);                            // 物料平衡合法性
_fResidualClamp := MAX(0.0, _fResidualRaw);                       // 负残留钳 0，不输出负值
_fPctRaw := _fResidualClamp / _fSolventInKgH * DL_PCT;            // 残留比例 [%]

(* —— 段 5：输出单点写盘（饱和钳制后判超限，保证判据与出口同源） —— *)
fResidualKgH := LIMIT(0.0, _fResidualClamp, DL_RES_MAX);          // 残留量 [kg/h]
fResidualPct := LIMIT(0.0, _fPctRaw, DL_PCT);                     // 残留比例钳 0..100 [%]

(* —— 段 6：有效位单点聚合（溶剂比例窄闸 + 物料平衡 + 带入量可归一） —— *)
xValid := (fSolventPct >= 0.0) AND (fSolventPct <= DL_PCT)        // 溶剂比例在 0..100 %
          AND (_bBalanceOk)                                       // 排出不得超过带入
          AND (_fSolventInKgH > DL_EPS);                          // 带入量可作分母

(* —— 段 7：超限判定（无效数据不得判超限） —— *)
xOver := xValid AND (fResidualPct > fResidualLimitPct);
FC_DL_CoaterSolventBalanceCalc := xValid;                         // 返回码：TRUE = 计算可信

END_FUNCTION
