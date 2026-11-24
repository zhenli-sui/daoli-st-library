(*
  ============================================================
  组件名 : FC_DL_ReceiverPressureDropCalc
  分类   : DL_Process
  功能   : 储气罐压降法流量估算，由起止压力与罐容时长求标准状态流量与压降速率
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      标准状态流量 = (起始压力 - 终止压力) * 罐容 / 时长 * 60，单位 Nm3/min，
      该式为忽略温度补偿的工程近似，仅在罐内温度稳定且压降不超过初始压力的前提下可用。
      压降速率 = (起始压力 - 终止压力) / 时长 * 3600，单位 bar/h。
      终止压力高于起始压力表示罐在充气而非放气，本组件判为不适用并置无效。
  ============================================================
*)
FUNCTION FC_DL_ReceiverPressureDropCalc : BOOL
VAR_INPUT
    bEnable   : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr      : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rP1_bar   : REAL; // 统计窗口起始压力 [bar] / pressure at the start of the window [bar]
    rP2_bar   : REAL; // 统计窗口终止压力 [bar] / pressure at the end of the window [bar]
    rVol_m3   : REAL; // 储气罐有效容积 [m3] / effective receiver volume [cubic metre]
    rDur_s    : REAL; // 统计窗口时长 [s] / duration of the window [second]
END_VAR
VAR_OUTPUT
    rFlow_nm3min : REAL; // 折算标准状态流量 [Nm3/min] / equivalent standard state flow [normal cubic metre per minute]
    rDropRate_barh : REAL; // 折算压降速率 [bar/h] / equivalent pressure drop rate [bar per hour]
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX  : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS    : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_S_PER_MIN : REAL := 60.0;   // 每分钟秒数 [s/min] / seconds per minute [second per minute]
    DL_S_PER_H   : REAL := 3600.0; // 每小时秒数 [s/h] / seconds per hour [second per hour]
    DL_DROP_MAX_PCT : REAL := 100.0; // 压降不得超过起始压力的百分比上限 [%] / pressure drop must not exceed this percentage of the start pressure [percent]
    DL_PCT    : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rDrop : REAL := 0.0;   // 窗口内压降 [bar] / pressure drop inside the window [bar]
END_VAR

    // 段 1｜出口预置
    rFlow_nm3min := 0.0;
    rDropRate_barh := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rP1_bar = rP1_bar) AND (ABS(rP1_bar) <= DL_R_MAX) AND (rP2_bar = rP2_bar) AND (ABS(rP2_bar) <= DL_R_MAX) AND (rVol_m3 = rVol_m3) AND (ABS(rVol_m3) <= DL_R_MAX) AND (rDur_s = rDur_s) AND (ABS(rDur_s) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：罐容与时长必须严格为正，压力不得为负
    IF (ABS(rVol_m3) <= DL_EPS) OR (ABS(rDur_s) <= DL_EPS) THEN
        RETURN;
    END_IF;
    IF (rVol_m3 < 0.0) OR (rDur_s < 0.0) OR (rP1_bar < 0.0) OR (rP2_bar < 0.0) THEN
        RETURN;
    END_IF;
    // 段 5｜压降必须为正，否则属充气工况，压降法不适用
    _rDrop := rP1_bar - rP2_bar;
    IF _rDrop <= DL_EPS THEN
        RETURN;
    END_IF;
    // 段 6｜压降相对起始压力不得越界，否则近似式失真
    IF rP1_bar > DL_EPS THEN
        IF _rDrop > rP1_bar * DL_DROP_MAX_PCT / DL_PCT THEN
            RETURN;
        END_IF;
    END_IF;
    // 段 7｜流量与压降速率
    rFlow_nm3min := _rDrop * rVol_m3 / rDur_s * DL_S_PER_MIN;
    rDropRate_barh := _rDrop / rDur_s * DL_S_PER_H;
    bValid := TRUE;
    FC_DL_ReceiverPressureDropCalc := bValid;
END_FUNCTION
