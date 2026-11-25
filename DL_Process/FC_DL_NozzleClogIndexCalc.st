(*
  ============================================================
  组件名 : FC_DL_NozzleClogIndexCalc
  分类   : DL_Process
  功能   : 喷嘴堵塞指数计算，由额定与实测流量求流量偏差率并折算堵塞百分比与报警位
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      偏差率 = (额定流量 - 实测流量) / 额定流量 * 100，限幅 0~100。
      实测高于额定时偏差为负，属超流而非堵塞，按 0 截断，堵塞指数不会为负。
      堵塞报警门限 15%，严格大于才置位。喷嘴数量仅用于产线级统计，不参与单嘴指数。
  ============================================================
*)
FUNCTION FC_DL_NozzleClogIndexCalc : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rFlowNom    : REAL; // 额定流量 [L/min] / rated flow [litre per minute]
    rFlowAct    : REAL; // 实测流量 [L/min] / measured flow [litre per minute]
    iNozzleCnt  : INT;  // 参与统计的喷嘴数量 [个] / number of nozzles in the survey [unit]
END_VAR
VAR_OUTPUT
    rDevPct    : REAL; // 限幅前的流量偏差率 [%] / raw flow deviation rate before clamping [percent]
    rClogPct   : REAL; // 堵塞指数，限幅 0~100 [%] / clogging index clamped to 0 to 100 [percent]
    bClogAlarm : BOOL; // 堵塞报警：TRUE 表示指数超过 15% / clog alarm, TRUE when the index exceeds 15 percent
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_ALARM_PCT : REAL := 15.0;  // 堵塞报警门限 [%] / clog alarm threshold [percent]
    DL_MAX_NOZ : INT := 512;      // 喷嘴数量合理上限 [个] / sanity upper bound of the nozzle count [unit]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rDevPct := 0.0;
    rClogPct := 0.0;
    bClogAlarm := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rFlowNom = rFlowNom) AND (ABS(rFlowNom) <= DL_R_MAX) AND (rFlowAct = rFlowAct) AND (ABS(rFlowAct) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：额定流量严格为正，实测流量非负，喷嘴数量 1~512
    IF ABS(rFlowNom) <= DL_EPS THEN
        RETURN;
    END_IF;
    IF (rFlowNom < DL_ZERO) OR (rFlowAct < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (iNozzleCnt < 1) OR (iNozzleCnt > DL_MAX_NOZ) THEN
        RETURN;
    END_IF;
    // 段 5｜偏差率
    rDevPct := (rFlowNom - rFlowAct) / rFlowNom * DL_PCT;
    // 段 6｜限幅到 0~100
    IF rDevPct < DL_ZERO THEN
        rClogPct := DL_ZERO;
    ELSIF rDevPct > DL_PCT THEN
        rClogPct := DL_PCT;
    ELSE
        rClogPct := rDevPct;
    END_IF;
    // 段 7｜报警位
    IF rClogPct > DL_ALARM_PCT THEN
        bClogAlarm := TRUE;
    ELSE
        bClogAlarm := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_NozzleClogIndexCalc := bValid;
END_FUNCTION
