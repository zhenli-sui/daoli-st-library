(*
  ============================================================
  组件名 : FC_DL_StocktakeVarianceCalc
  分类   : DL_Process
  功能   : 盘点差异计算，由账面数与实盘数求数量差、差异率与差异金额
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      数量差 = 实盘 - 账面，为正表示盘盈，为负表示盘亏。
      账面为 0 时差异率在数学上无定义，本实现置 0 并置 bBookZero 告警；
      此时数量差与差异金额仍然有效，故 bValid 仍为 TRUE，语义由 bBookZero 单独表达。
      数量差内部用 DINT 承载，防止 INT 减法溢出，落定前做双侧饱和。
  ============================================================
*)
FUNCTION FC_DL_StocktakeVarianceCalc : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    iBookQty    : INT;  // 账面库存数量 [件] / book quantity [piece]
    iActualQty  : INT;  // 实盘库存数量 [件] / actual counted quantity [piece]
    rUnitVal    : REAL; // 物料单价 [元/件] / unit value [currency per piece]
END_VAR
VAR_OUTPUT
    iDiffQty    : INT;  // 数量差异，实盘减账面 [件] / quantity difference actual minus book [piece]
    rDiffPct    : REAL; // 差异率，取绝对值后除账面 [%] / variance rate of the absolute difference over the book [percent]
    rDiffValue  : REAL; // 差异金额 [元] / variance value [currency]
    bBookZero   : BOOL; // 账面为零告警：TRUE 表示差异率无意义 / book zero alarm, TRUE means the rate is meaningless
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_I_MAX   : DINT := 32767;   // INT 类型可表上界 [件] / representable upper bound of INT [piece]
    DL_I_MIN   : DINT := -32768;  // INT 类型可表下界 [件] / representable lower bound of INT [piece]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _diDiff : DINT := 0;     // 数量差中间量，DINT 防溢出 [件] / intermediate difference in DINT to avoid overflow [piece]
    _rBook  : REAL := 0.0;   // 账面折算实数 [件] / book quantity cast to real [piece]
    _rAbs   : REAL := 0.0;   // 差异绝对值 [件] / absolute difference [piece]
END_VAR

    // 段 1｜出口预置
    iDiffQty := 0;
    rDiffPct := 0.0;
    rDiffValue := 0.0;
    bBookZero := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸：单价参与金额换算，必须有限
    _bFin := (rUnitVal = rUnitVal) AND (ABS(rUnitVal) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：单价允许为零（赠品），不允许为负
    IF rUnitVal < 0.0 THEN
        RETURN;
    END_IF;
    // 段 5｜数量差：DINT 承载后双侧饱和回 INT
    _diDiff := INT_TO_DINT(iActualQty) - INT_TO_DINT(iBookQty);
    IF _diDiff > DL_I_MAX THEN
        _diDiff := DL_I_MAX;
    ELSIF _diDiff < DL_I_MIN THEN
        _diDiff := DL_I_MIN;
    END_IF;
    iDiffQty := DINT_TO_INT(_diDiff);
    rDiffValue := DINT_TO_REAL(_diDiff) * rUnitVal;
    // 段 6｜差异率：账面为零时置 0 并告警，不做除法
    _rBook := INT_TO_REAL(iBookQty);
    IF ABS(_rBook) <= DL_EPS THEN
        rDiffPct := 0.0;
        bBookZero := TRUE;
        bValid := TRUE;
        FC_DL_StocktakeVarianceCalc := bValid;
        RETURN;
    END_IF;
    _rAbs := ABS(DINT_TO_REAL(_diDiff));
    rDiffPct := _rAbs / _rBook * DL_PCT;
    bValid := TRUE;
    FC_DL_StocktakeVarianceCalc := bValid;
END_FUNCTION
