(*
  ============================================================
  组件名 : FC_DL_SuctionCupCountCalc
  分类   : DL_Device
  功能   : 吸盘数量配置计算，按载荷重力与冗余倾覆系数求所需吸盘数并给出可行性判定
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      需求数 = 向上取整(载荷kg * 9.81 * 冗余系数 * 倾覆系数 / 单盘可用力N)。
      向上取整不调用 CEIL，而是先截断再按余量进位，且截断前先做实数上限兜底，防止 REAL_TO_INT 溢出。
      结果限幅 1~64；需求数超过 32 时可行性判 FALSE，表示超出常规单机吸盘阵列规模。
      需求数溢出上限时直接按 64 落定并判不可行，不做回绕。
  ============================================================
*)
FUNCTION FC_DL_SuctionCupCountCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLoadKg      : REAL; // 被吸持工件质量 [kg] / mass of the workpiece to be held [kilogram]
    rPerCupN     : REAL; // 单个吸盘可用吸附力 [N] / usable holding force of one cup [newton]
    rRedundancy  : REAL; // 冗余系数，常用 1.2~2.0 [无量纲] / redundancy factor, typically 1.2 to 2.0 [dimensionless]
    rTiltFactor  : REAL; // 倾覆与动态系数 [无量纲] / tilt and dynamic factor [dimensionless]
END_VAR
VAR_OUTPUT
    rNeedRaw  : REAL; // 向上取整前的需求数 [个] / raw required count before rounding up [unit]
    iCupCnt   : INT;  // 配置吸盘数量，限幅 1~64 [个] / configured cup count clamped to 1 to 64 [unit]
    bFeasible : BOOL; // 可行：TRUE 表示数量不超过 32 个 / feasible, TRUE when the count does not exceed 32 [unit]
    bOverflow : BOOL; // 需求溢出：TRUE 表示需求数超出整数可表范围 / requirement overflow, TRUE when the requirement exceeds the integer range
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX     : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_G         : REAL := 9.81;    // 重力加速度 [m/s2] / gravitational acceleration [metre per second squared]
    DL_CUP_MIN   : INT := 1;        // 吸盘数量下界 [个] / lower bound of the cup count [unit]
    DL_CUP_MAX   : INT := 64;       // 吸盘数量上界 [个] / upper bound of the cup count [unit]
    DL_CUP_OK    : INT := 32;       // 常规阵列规模上限 [个] / upper bound of a conventional array [unit]
    DL_INT_SAFE  : REAL := 32000.0; // 实数转整数前的安全上限 [无量纲] / safe upper bound before converting a real into an integer [dimensionless]
    DL_RESID_TOL : REAL := 1.0E-6;  // 截断余量判定容差 [无量纲] / tolerance deciding the rounding carry [dimensionless]
    DL_RED_MIN   : REAL := 1.0;     // 冗余系数下界 [无量纲] / lower bound of the redundancy factor [dimensionless]
    DL_RED_MAX   : REAL := 5.0;     // 冗余系数上界 [无量纲] / upper bound of the redundancy factor [dimensionless]
    DL_TILT_MIN  : REAL := 1.0;     // 倾覆系数下界 [无量纲] / lower bound of the tilt factor [dimensionless]
    DL_TILT_MAX  : REAL := 5.0;     // 倾覆系数上界 [无量纲] / upper bound of the tilt factor [dimensionless]
    DL_LOAD_MAX  : REAL := 100000.0; // 工件质量合理上限 [kg] / sanity upper bound of the workpiece mass [kilogram]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _iTmp  : INT := 0;      // 截断后的临时整数 [个] / temporary integer after truncation [unit]
    _rRes  : REAL := 0.0;   // 截断余量 [个] / residual after truncation [unit]
END_VAR

    // 段 1｜出口预置：数量先置 1，可行位先置 FALSE
    rNeedRaw := 0.0;
    iCupCnt := DL_CUP_MIN;
    bFeasible := FALSE;
    bOverflow := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLoadKg = rLoadKg) AND (ABS(rLoadKg) <= DL_R_MAX) AND (rPerCupN = rPerCupN) AND (ABS(rPerCupN) <= DL_R_MAX) AND (rRedundancy = rRedundancy) AND (ABS(rRedundancy) <= DL_R_MAX) AND (rTiltFactor = rTiltFactor) AND (ABS(rTiltFactor) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：单盘力严格为正，载荷非负且合理，两个系数落在工程区间
    IF (ABS(rPerCupN) <= DL_EPS) OR (rPerCupN < 0.0) THEN
        RETURN;
    END_IF;
    IF (rLoadKg < 0.0) OR (rLoadKg > DL_LOAD_MAX) THEN
        RETURN;
    END_IF;
    IF (rRedundancy < DL_RED_MIN) OR (rRedundancy > DL_RED_MAX) THEN
        RETURN;
    END_IF;
    IF (rTiltFactor < DL_TILT_MIN) OR (rTiltFactor > DL_TILT_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜需求数原值
    rNeedRaw := rLoadKg * DL_G * rRedundancy * rTiltFactor / rPerCupN;
    // 段 6｜临界零需求：无载荷时按最小 1 个配置，直接判定
    IF rNeedRaw <= DL_RESID_TOL THEN
        iCupCnt := DL_CUP_MIN;
        bFeasible := TRUE;
        bOverflow := FALSE;
        bValid := TRUE;
        FC_DL_SuctionCupCountCalc := bValid;
        RETURN;
    END_IF;
    // 段 7｜实数上限兜底：超界直接按上界落定并判不可行，杜绝 REAL_TO_INT 回头
    IF rNeedRaw >= DL_INT_SAFE THEN
        iCupCnt := DL_CUP_MAX;
        bFeasible := FALSE;
        bOverflow := TRUE;
        bValid := TRUE;
        FC_DL_SuctionCupCountCalc := bValid;
        RETURN;
    END_IF;
    // 段 8｜先截断再按余量进位，等价向上取整但不调用 CEIL
    _iTmp := REAL_TO_INT(rNeedRaw);
    _rRes := rNeedRaw - INT_TO_REAL(_iTmp);
    IF _rRes > DL_RESID_TOL THEN
        _iTmp := _iTmp + 1;
    END_IF;
    // 段 9｜限幅与可行性
    IF _iTmp < DL_CUP_MIN THEN
        _iTmp := DL_CUP_MIN;
    END_IF;
    IF _iTmp > DL_CUP_MAX THEN
        _iTmp := DL_CUP_MAX;
    END_IF;
    iCupCnt := _iTmp;
    IF _iTmp <= DL_CUP_OK THEN
        bFeasible := TRUE;
    ELSE
        bFeasible := FALSE;
    END_IF;
    bOverflow := FALSE;
    bValid := TRUE;
    FC_DL_SuctionCupCountCalc := bValid;
END_FUNCTION
