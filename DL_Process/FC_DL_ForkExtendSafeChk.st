(*
  ============================================================
  组件名 : FC_DL_ForkExtendSafeChk
  分类   : DL_Process
  功能   : 货叉伸出安全校核，同时校验通道余量是否足够与货位对齐误差是否在容差内
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      安全判据必须两条同时满足：需伸量 <= 通道余量 - 安全余量，且对齐误差绝对值 <= 容差。
      余量 rMargin_mm = 通道余量 - 安全余量 - 需伸量，为负表示越界，正值表示剩余空间。
      任一条不满足即 bSafe=FALSE，同时 bValid 仍为 TRUE，因为判定结论本身是确定的。
  ============================================================
*)
FUNCTION FC_DL_ForkExtendSafeChk : BOOL
VAR_INPUT
    bEnable        : BOOL; // 使能：TRUE 时校核 / Enable: TRUE to check
    bErr           : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rForkExt_mm    : REAL; // 本次需要伸出的货叉长度 [mm] / required fork extension for this cycle [mm]
    rAisleClear_mm : REAL; // 巷道侧向可用余量 [mm] / available lateral clearance in the aisle [mm]
    rAlignErr_mm   : REAL; // 货位对齐误差，带正负号 [mm] / cell alignment error with sign [mm]
    rAlignTol_mm   : REAL; // 允许的对齐误差容差 [mm] / permitted alignment tolerance [mm]
    rSafeMargin_mm : REAL; // 需保留的安全余量 [mm] / safety margin that must be preserved [mm]
END_VAR
VAR_OUTPUT
    bSafe      : BOOL; // 伸出安全：TRUE 表示两条判据同时满足 / extension safe, TRUE when both criteria hold
    rMargin_mm : REAL; // 伸出后剩余余量，负值表示越界 [mm] / remaining margin after extension, negative means overrun [mm]
    bAlignOk   : BOOL; // 对齐合格：TRUE 表示误差在容差内 / alignment acceptable, TRUE when the error is within tolerance
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS   : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ZERO  : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rAllow  : REAL := 0.0;   // 扣掉安全余量后的可伸长度 [mm] / allowable extension after removing the safety margin [mm]
    _rAbsErr : REAL := 0.0;   // 对齐误差绝对值 [mm] / absolute alignment error [mm]
END_VAR

    // 段 1｜出口预置：安全位保守置 FALSE，余量置零
    bSafe := FALSE;
    rMargin_mm := 0.0;
    bAlignOk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rForkExt_mm = rForkExt_mm) AND (ABS(rForkExt_mm) <= DL_R_MAX) AND (rAisleClear_mm = rAisleClear_mm) AND (ABS(rAisleClear_mm) <= DL_R_MAX) AND (rAlignErr_mm = rAlignErr_mm) AND (ABS(rAlignErr_mm) <= DL_R_MAX) AND (rAlignTol_mm = rAlignTol_mm) AND (ABS(rAlignTol_mm) <= DL_R_MAX) AND (rSafeMargin_mm = rSafeMargin_mm) AND (ABS(rSafeMargin_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：需伸量、通道余量、容差、安全余量均不得为负
    IF (rForkExt_mm < DL_ZERO) OR (rAisleClear_mm < DL_ZERO) OR (rAlignTol_mm < DL_ZERO) OR (rSafeMargin_mm < DL_ZERO) THEN
        RETURN;
    END_IF;
    // 段 5｜可伸长度与剩余余量
    _rAllow := rAisleClear_mm - rSafeMargin_mm;
    rMargin_mm := _rAllow - rForkExt_mm;
    // 段 6｜两条判据
    _rAbsErr := ABS(rAlignErr_mm);
    IF _rAbsErr <= rAlignTol_mm THEN
        bAlignOk := TRUE;
    ELSE
        bAlignOk := FALSE;
    END_IF;
    IF (rForkExt_mm <= _rAllow) AND bAlignOk THEN
        bSafe := TRUE;
    ELSE
        bSafe := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_ForkExtendSafeChk := bValid;
END_FUNCTION
