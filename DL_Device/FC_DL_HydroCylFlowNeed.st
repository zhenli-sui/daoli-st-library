(*
  ============================================================
  组件名 : FC_DL_HydroCylFlowNeed
  分类   : DL_Device
  功能   : 液压缸动作所需流量计算，由有效面积、目标速度与容积效率求泵侧流量
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_HydroCylFlowNeed : REAL
VAR_INPUT
    rArea_cm2  : REAL; // 有效作用面积 [cm2] effective acting area [cm2]
    rSpeed_mm_s: REAL; // 目标速度 [mm/s] target speed [mm per second]
    rVolEff    : REAL; // 容积效率 0~1 [无量纲] volumetric efficiency from zero to one [dimensionless]
END_VAR
VAR_OUTPUT
    rFlow_lpm : REAL; // 所需流量 [l/min] required flow [litre per minute]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_MM_PER_CM    : REAL := 10.0; // 每厘米毫米数 millimetres per centimetre
    DL_SEC_PER_MIN  : REAL := 60.0; // 每分钟秒数 seconds per minute
    DL_CM3_PER_L    : REAL := 1000.0; // 每升立方厘米数 cubic centimetres per litre
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 三输入有限性判定 finiteness verdict of the three inputs
    _rVelCms : REAL := 0.0; // 速度折算 [cm/s] speed in centimetres per second [cm/s]
    _rFlow : REAL := 0.0; // 流量中间量 [l/min] intermediate flow [litre per minute]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_HydroCylFlowNeed := 0.0; // 缺省返回零 default zero return
rFlow_lpm := 0.0; // 流量预置零 flow preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rArea_cm2 = rArea_cm2) AND (rSpeed_mm_s = rSpeed_mm_s) AND (rVolEff = rVolEff); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜面积与效率闸 area and efficiency gate
IF (rArea_cm2 <= 0.0) OR (rSpeed_mm_s < 0.0) THEN
    RETURN; // 面积非正或负速度属配置非法 an illegal area or a negative speed
END_IF
IF (rVolEff <= 0.0) OR (rVolEff > 1.0) THEN
    RETURN; // 容积效率越出零到一 volumetric efficiency outside the open closed interval
END_IF
// 段 4｜主体换算 main unit conversion
_rVelCms := rSpeed_mm_s / DL_MM_PER_CM; // 毫米每秒折算为厘米每秒 convert millimetres to centimetres per second
_rFlow := rArea_cm2 * _rVelCms * DL_SEC_PER_MIN / DL_CM3_PER_L; // 面积乘速度得流量 area times speed gives the flow
_rFlow := _rFlow / rVolEff; // 容积效率折损修正 volumetric loss correction
rFlow_lpm := _rFlow; // 流量落定 land the flow
bValid := TRUE; // 结果可用 result usable
FC_DL_HydroCylFlowNeed := _rFlow; // 函数返回流量 return the flow
END_FUNCTION
