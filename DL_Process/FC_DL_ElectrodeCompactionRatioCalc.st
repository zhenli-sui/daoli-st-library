(*
  Name: FC_DL_ElectrodeCompactionRatioCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 压实比按「辊压后密度 / 辊压前（来料）密度」计算，是无因次的密实化倍数。
           该比值与面密度、厚度无关，只反映辊压工序本身的密实效果，适合作为辊压工艺窗口判据。
        2) 工艺窗口判定 xInWindow：压实比落在 [fRatioMin, fRatioMax] 闭区间内即判合格。
           窗口上下限由组态给出，本件不硬编码工艺值；上下限本身做合法性校验（下限须 > 1，
           因为压实比 = 1 表示完全未压实，< 1 表示减薄的反向过程，均不属辊压工艺窗口）。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fRatio 强制 0.0、xInWindow 强制 FALSE）并置无效（R19），
           无效数据不得判合格。
        2) 分母零闸：ABS(fGreenGcm3) > DL_EPS 才允许相除（来料密度为 0 时比值无定义）。
        3) 负值闸：两个密度任一为负、窗口上下限任一为负均判无效。
        4) 窗口组态闸：fRatioMax 必须 >= fRatioMin，否则窗口为空集、合格判据恒假（组态错误）；
           fRatioMin 必须 >= 1.0，否则窗口包含「未压实或减薄」的非物理区间。
        5) 饱和钳制：压实比钳 0 ~ DL_RATIO_MAX(20)，防极小来料密度把比值放大到无意义量级。
  量纲自证：fRatio = (g/cm3) / (g/cm3) = 无因次 [-]；
           窗口上下限同为无因次，与 fRatio 同量纲后方可比较；本件无跨量纲相加。
*)

FUNCTION FC_DL_ElectrodeCompactionRatioCalc : BOOL
VAR_INPUT
    fCompactionGcm3 : REAL;   // 辊压后压实密度 [g/cm3] / Post-calendering compaction density [g/cm3]
    fGreenGcm3      : REAL;   // 辊压前来料密度 [g/cm3] / Incoming green density [g/cm3]
    fRatioMin       : REAL;   // 工艺窗口下限 [-] / Process window lower limit [-]
    fRatioMax       : REAL;   // 工艺窗口上限 [-] / Process window upper limit [-]
END_VAR
VAR_OUTPUT
    fRatio          : REAL;   // 压实比 [-] / Compaction ratio [-]
    xInWindow       : BOOL;   // 落在工艺窗口内 [bool] / Inside process window flag [bool]
    xValid          : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRatioRaw      : REAL;   // 未饱和的压实比 [-] / Raw compaction ratio [-]
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_RATIO_MAX    : REAL := 20.0;      // 压实比饱和上限 [-] / Compaction ratio saturation ceiling [-]
    DL_RATIO_MIN_OK : REAL := 1.0;       // 压实比物理下限（未压实）[-] / Physical lower bound [-]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fCompactionGcm3 > -DL_BIG AND fCompactionGcm3 < DL_BIG)
   OR NOT (fGreenGcm3 > -DL_BIG AND fGreenGcm3 < DL_BIG)
   OR NOT (fRatioMin > -DL_BIG AND fRatioMin < DL_BIG)
   OR NOT (fRatioMax > -DL_BIG AND fRatioMax < DL_BIG) THEN
    fRatio := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xInWindow := FALSE;                     // 窗口标志强制 FALSE / Window flag forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_ElectrodeCompactionRatioCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：来料密度是比值分母） —— *)
IF ABS(fGreenGcm3) <= DL_EPS THEN
    fRatio := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xInWindow := FALSE;                     // 窗口标志强制 FALSE / Window flag forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_ElectrodeCompactionRatioCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（密度与窗口限值均不可为负） —— *)
IF (fCompactionGcm3 < 0.0) OR (fGreenGcm3 < 0.0) OR (fRatioMin < 0.0) OR (fRatioMax < 0.0) THEN
    fRatio := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xInWindow := FALSE;                     // 窗口标志强制 FALSE / Window flag forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_ElectrodeCompactionRatioCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（R22 方向自核：压实后密度在分子、来料密度在分母，比值必 >= 1） —— *)
_fRatioRaw := fCompactionGcm3 / fGreenGcm3;                       // 压实比 [-]

(* —— 段 5：输出单点写盘（饱和钳制后判窗口，保证判据与出口同源） —— *)
fRatio := LIMIT(0.0, _fRatioRaw, DL_RATIO_MAX);                   // 压实比 [-]

(* —— 段 6：有效位单点聚合（窗口组态合法性 + 密度为正） —— *)
xValid := (fGreenGcm3 > DL_EPS)                                   // 来料密度为正
          AND (fCompactionGcm3 > DL_EPS)                          // 压实密度为正
          AND (fRatioMax >= fRatioMin)                            // 窗口非空
          AND (fRatioMin >= DL_RATIO_MIN_OK);                     // 下限不落入非物理区间

(* —— 段 7：工艺窗口判定（闭区间，边界值算合格） —— *)
xInWindow := xValid AND (fRatio >= fRatioMin) AND (fRatio <= fRatioMax);
FC_DL_ElectrodeCompactionRatioCalc := xValid;                     // 返回码：TRUE = 计算可信

END_FUNCTION
