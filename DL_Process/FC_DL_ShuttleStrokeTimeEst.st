(*
  ============================================================
  组件名 : FC_DL_ShuttleStrokeTimeEst
  分类   : DL_Process
  功能   : 穿梭车单行程时间估算，按梯形速度曲线求加速巡航减速时间并叠加装卸换向时间
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      输入 rDist_m / rAcc / rVmax / rTLoad 均为物理量，行尾注释带工程单位。
      输出 rCycle_s 为单行程总时间；bValid 仅在全部输入合法且分支计算完成时为 TRUE。
      曲线判据：行程 >= 加速段+减速段距离（Vmax^2/Acc）时走梯形，否则走三角波形。
  ============================================================
*)
FUNCTION FC_DL_ShuttleStrokeTimeEst : BOOL
VAR_INPUT
    bEnable  : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr     : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rDist_m  : REAL; // 单行程距离 [m] / single stroke distance [m]
    rAcc     : REAL; // 加速度 [m/s2] / acceleration [metre per second squared]
    rVmax    : REAL; // 最高速度 [m/s] / maximum speed [metre per second]
    rTLoad   : REAL; // 装卸与换向附加时间 [s] / load unload and reversal time [s]
END_VAR
VAR_OUTPUT
    rCycle_s : REAL; // 单行程总时间 [s] / total single stroke time [s]
    bValid   : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS   : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
END_VAR
VAR
    _bFin     : BOOL := FALSE; // 输入有限性判定汇总 / aggregated finiteness verdict of the inputs
    _rCrit    : REAL := 0.0;   // 梯形曲线临界距离 [m] / critical distance of the trapezoidal profile [m]
    _rAccDist : REAL := 0.0;   // 加速段与减速段距离之和 [m] / sum of acceleration and deceleration distance [m]
    _rT       : REAL := 0.0;   // 纯运动段耗时 [s] / pure motion time [s]
END_VAR

    // 段 1｜出口预置：先置零再置无效，任何提前返回都不会留下上一拍残值
    rCycle_s := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸：自反判 NaN，绝对值上界判 Inf，两条缺一不可
    _bFin := (rDist_m = rDist_m) AND (ABS(rDist_m) <= DL_R_MAX) AND (rAcc = rAcc) AND (ABS(rAcc) <= DL_R_MAX) AND (rVmax = rVmax) AND (ABS(rVmax) <= DL_R_MAX) AND (rTLoad = rTLoad) AND (ABS(rTLoad) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：加速度与最高速必须严格为正，否则后续必除零
    IF (ABS(rAcc) <= DL_EPS) OR (ABS(rVmax) <= DL_EPS) THEN
        RETURN;
    END_IF;
    IF (rDist_m < 0.0) OR (rAcc < 0.0) OR (rVmax < 0.0) OR (rTLoad < 0.0) THEN
        RETURN;
    END_IF;
    // 段 5｜临界距离：Vmax^2/Acc 即加速段加减速段总路程
    _rAccDist := rVmax * rVmax / rAcc;
    _rCrit := _rAccDist;
    // 段 6｜分支求纯运动时间
    IF rDist_m >= _rCrit THEN
        _rT := rDist_m / rVmax + rVmax / rAcc; // 梯形：全程含匀速段
    ELSE
        _rT := 2.0 * SQRT(rDist_m / rAcc); // 三角形：未达最高速即开始减速
    END_IF;
    // 段 7｜叠加装卸换向时间并落定
    rCycle_s := _rT + rTLoad;
    bValid := TRUE;
    FC_DL_ShuttleStrokeTimeEst := bValid;
END_FUNCTION
