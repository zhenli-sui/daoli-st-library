(*
  ============================================================
  组件名 : FC_DL_HydroAccumulatorSizing
  分类   : DL_Device
  功能   : 皮囊式蓄能器容积选型，按等温或绝热过程由需液量、最高最低压力与预充压力求公称容积
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_HydroAccumulatorSizing : REAL
VAR_INPUT
    rVolumeDemand_l    : REAL; // 需液量 [l] usable oil demand [litre]
    rPressMax_bar      : REAL; // 最高工作压力 [bar] maximum working pressure [bar]
    rPressMin_bar      : REAL; // 最低工作压力 [bar] minimum working pressure [bar]
    rPressPrecharge_bar: REAL; // 预充压力 [bar] precharge pressure [bar]
    bAdiabatic         : BOOL; // 真为绝热过程，假为等温过程 adiabatic when true, isothermal when false
END_VAR
VAR_OUTPUT
    rVolume_l     : REAL; // 蓄能器公称容积 [l] nominal accumulator volume [litre]
    rUsableRatio  : REAL; // 有效容积比 [无量纲] usable volume ratio [dimensionless]
    bValid        : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_ADIA_EXP : REAL := 0.7142857; // 绝热指数倒数值 1/1.4 reciprocal of the adiabatic index
    DL_EPS_R    : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 四实数输入有限性判定 finiteness verdict of the four real inputs
    _rRatio : REAL := 0.0; // 压比 the pressure ratio [dimensionless]
    _rProc  : REAL := 0.0; // 过程指数折算后的压比 the process weighted pressure ratio [dimensionless]
    _rDen   : REAL := 0.0; // 容积公式分母 [无量纲] denominator of the volume formula [dimensionless]
    _rVol   : REAL := 0.0; // 公称容积中间量 [l] intermediate nominal volume [litre]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_HydroAccumulatorSizing := 0.0; // 缺省返回零 default zero return
rVolume_l := 0.0; // 容积预置零 volume preset to zero
rUsableRatio := 0.0; // 有效容积比预置零 usable ratio preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rVolumeDemand_l = rVolumeDemand_l) AND (rPressMax_bar = rPressMax_bar) AND (rPressMin_bar = rPressMin_bar) AND (rPressPrecharge_bar = rPressPrecharge_bar); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜压力几何闸 pressure geometry gate
IF rPressMin_bar <= 0.0 THEN
    RETURN; // 最低压力非正无法形成压比 a non positive minimum cannot form a ratio
END_IF
IF (rPressMax_bar <= rPressMin_bar) OR (rPressMin_bar <= rPressPrecharge_bar) THEN
    RETURN; // 高压须大于低压，低压须大于预充 the maximum must exceed the minimum and the minimum must exceed the precharge
END_IF
IF rVolumeDemand_l < 0.0 THEN
    RETURN; // 需液量为负属配置非法 a negative demand is an illegal configuration
END_IF
// 段 4｜过程折算与分母 process weighting and the denominator
_rRatio := rPressMax_bar / rPressMin_bar; // 最高与最低压力比 ratio of the maximum to the minimum
IF bAdiabatic THEN
    _rProc := EXPT(_rRatio, DL_ADIA_EXP); // 绝热过程按一点四指数折算 adiabatic process weighted by the index of one point four
ELSE
    _rProc := _rRatio; // 等温过程压比直通 isothermal process keeps the plain ratio
END_IF
_rDen := _rProc - 1.0; // 容积公式分母 denominator of the volume formula
IF _rDen <= DL_EPS_R THEN
    RETURN; // 分母近零无法定容 a near zero denominator cannot size the volume
END_IF
// 段 5｜公称容积与有效容积比 nominal volume and the usable ratio
_rVol := rVolumeDemand_l / _rDen; // 公称容积 nominal volume
rVolume_l := _rVol; // 容积落定 land the volume
rUsableRatio := rVolumeDemand_l / _rVol; // 有效容积比 usable volume ratio
bValid := TRUE; // 结果可用 result usable
FC_DL_HydroAccumulatorSizing := _rVol; // 函数返回公称容积 return the nominal volume
END_FUNCTION
