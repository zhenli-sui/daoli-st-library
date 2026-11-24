(*
  ============================================================
  组件名 : FC_DL_DesiccantLifeEstimate
  分类   : DL_Process
  功能   : 干燥剂寿命估算，按累计吸湿量与温度降额后的有效容量求剩余寿命百分比
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      有效容量 = 额定吸附容量 * 温度降额系数，温度降额系数限定 0~1 区间且必须为正。
      剩余百分比 = (1 - 累计吸湿量/有效容量) * 100，限幅 0~100。
      剩余低于 20% 判更换到期；累计吸湿量超过有效容量时剩余按 0 截断，判定仍成立。
  ============================================================
*)
FUNCTION FC_DL_DesiccantLifeEstimate : BOOL
VAR_INPUT
    bEnable        : BOOL; // 使能：TRUE 时估算 / Enable: TRUE to estimate
    bErr           : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rMoistureLoad  : REAL; // 累计已吸附水汽质量 [g] / accumulated adsorbed moisture mass [gram]
    rCapG          : REAL; // 额定吸附容量 [g] / rated adsorption capacity [gram]
    rTempDerate    : REAL; // 温度降额系数，1 表示不降额 [无量纲] / temperature derating factor, one means no derating [dimensionless]
END_VAR
VAR_OUTPUT
    rEffCapG   : REAL; // 降额后的有效吸附容量 [g] / effective capacity after derating [gram]
    rLoadPct   : REAL; // 已消耗容量百分比 [%] / consumed capacity percentage [percent]
    rRemainPct : REAL; // 剩余寿命百分比，限幅 0~100 [%] / remaining life percentage clamped to 0 to 100 [percent]
    bReplaceDue : BOOL; // 更换到期：TRUE 表示剩余低于 20% / replacement due, TRUE when the remainder is below 20 percent
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ONE     : REAL := 1.0;     // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_DUE_PCT : REAL := 20.0;    // 更换到期门限 [%] / replacement due threshold [percent]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rUse : REAL := 0.0;   // 容量占用比 [无量纲] / capacity usage ratio [dimensionless]
END_VAR

    // 段 1｜出口预置：剩余先置 0（最不利），防止下游误判为充足
    rEffCapG := 0.0;
    rLoadPct := 0.0;
    rRemainPct := 0.0;
    bReplaceDue := TRUE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rMoistureLoad = rMoistureLoad) AND (ABS(rMoistureLoad) <= DL_R_MAX) AND (rCapG = rCapG) AND (ABS(rCapG) <= DL_R_MAX) AND (rTempDerate = rTempDerate) AND (ABS(rTempDerate) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：容量严格为正，降额系数落在 0~1 且严格为正
    IF (ABS(rCapG) <= DL_EPS) OR (rCapG < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (ABS(rTempDerate) <= DL_EPS) OR (rTempDerate < DL_ZERO) OR (rTempDerate > DL_ONE) THEN
        RETURN;
    END_IF;
    IF rMoistureLoad < DL_ZERO THEN
        RETURN;
    END_IF;
    // 段 5｜有效容量：容量乘降额系数，乘积仍须严格为正才可作分母
    rEffCapG := rCapG * rTempDerate;
    IF rEffCapG <= DL_EPS THEN
        RETURN;
    END_IF;
    // 段 6｜占用比与剩余百分比
    _rUse := rMoistureLoad / rEffCapG;
    rLoadPct := _rUse * DL_PCT;
    rRemainPct := (DL_ONE - _rUse) * DL_PCT;
    // 段 7｜限幅
    IF rRemainPct < DL_ZERO THEN
        rRemainPct := DL_ZERO;
    END_IF;
    IF rRemainPct > DL_PCT THEN
        rRemainPct := DL_PCT;
    END_IF;
    IF rLoadPct < DL_ZERO THEN
        rLoadPct := DL_ZERO;
    END_IF;
    // 段 8｜更换到期判定
    IF rRemainPct < DL_DUE_PCT THEN
        bReplaceDue := TRUE;
    ELSE
        bReplaceDue := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_DesiccantLifeEstimate := bValid;
END_FUNCTION
