(*
  ============================================================
  组件名 : FC_DL_CellOccupyRateCalc
  分类   : DL_Process
  功能   : 货位占用率计算，扣除封存货位后按可用货位求占用百分比与空闲数
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      可用货位 = 总货位 - 封存货位；占用率 = 已用 / 可用 * 100。
      可用货位 <= 0 时占用率无定义，直接判无效，不输出替代值。
      空闲货位 = 可用 - 已用，小于 0 表示超占（数据异常），本实现按 0 截断并保持比例可算。
      中间量用 DINT 承载，避免 INT 减法溢出。
  ============================================================
*)
FUNCTION FC_DL_CellOccupyRateCalc : BOOL
VAR_INPUT
    bEnable       : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr          : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    iCellTotal    : INT;  // 货位总数量 [个] / total number of storage cells [unit]
    iCellUsed     : INT;  // 已占用货位数量 [个] / number of occupied cells [unit]
    iCellBlocked  : INT;  // 封存禁用货位数量 [个] / number of blocked or disabled cells [unit]
END_VAR
VAR_OUTPUT
    rOccupyPct : REAL; // 可用货位占用率 [%] / occupancy rate over the available cells [percent]
    iCellFree  : INT;  // 空闲货位数量，负值按 0 截断 [个] / free cell count, negative clamped to zero [unit]
    iCellAvail : INT;  // 扣除封存后的可用货位数量 [个] / available cell count after removing blocked cells [unit]
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS   : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT   : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
END_VAR
VAR
    _diAvail : DINT := 0; // 可用货位中间量，DINT 防溢出 [个] / intermediate available count in DINT [unit]
    _diFree  : DINT := 0; // 空闲货位中间量，DINT 防溢出 [个] / intermediate free count in DINT [unit]
    _rAvail  : REAL := 0.0; // 可用货位折算实数 [个] / available count cast to real [unit]
END_VAR

    // 段 1｜出口预置
    rOccupyPct := 0.0;
    iCellFree := 0;
    iCellAvail := 0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜域闸：总数必须为正，已用与封存不得为负
    IF iCellTotal <= 0 THEN
        RETURN;
    END_IF;
    IF (iCellUsed < 0) OR (iCellBlocked < 0) THEN
        RETURN;
    END_IF;
    // 段 4｜可用货位：总数减封存
    _diAvail := INT_TO_DINT(iCellTotal) - INT_TO_DINT(iCellBlocked);
    // 段 5｜可用货位非正闸：此时占用率无定义，判无效
    IF _diAvail <= 0 THEN
        bValid := FALSE;
        FC_DL_CellOccupyRateCalc := bValid;
        RETURN;
    END_IF;
    iCellAvail := DINT_TO_INT(_diAvail);
    // 段 6｜空闲货位：超占按 0 截断
    _diFree := _diAvail - INT_TO_DINT(iCellUsed);
    IF _diFree < 0 THEN
        _diFree := 0;
    END_IF;
    iCellFree := DINT_TO_INT(_diFree);
    // 段 7｜占用率
    _rAvail := DINT_TO_REAL(_diAvail);
    IF ABS(_rAvail) <= DL_EPS THEN
        RETURN;
    END_IF;
    rOccupyPct := INT_TO_REAL(iCellUsed) / _rAvail * DL_PCT;
    bValid := TRUE;
    FC_DL_CellOccupyRateCalc := bValid;
END_FUNCTION
