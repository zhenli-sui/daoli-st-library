(*
  ============================================================
  组件名 : FC_DL_HydroCylForceCalc
  分类   : DL_Device
  功能   : 液压缸理论推力计算，按缸径杆径、供油压力、背压与机械效率求伸出与缩回推力
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_HydroCylForceCalc : REAL
VAR_INPUT
    rBoreDia_mm  : REAL; // 缸径 [mm] bore diameter [mm]
    rRodDia_mm   : REAL; // 活塞杆径 [mm] rod diameter [mm]
    rPressBar    : REAL; // 供油压力 [bar] supply pressure [bar]
    rBackPressBar: REAL; // 回油背压 [bar] return line back pressure [bar]
    rMechEff     : REAL; // 机械效率 0~1 [无量纲] mechanical efficiency from zero to one [dimensionless]
    bExtend      : BOOL; // 真为伸出，假为缩回 extend when true, retract when false
END_VAR
VAR_OUTPUT
    rForce_kN : REAL; // 理论推力 [kN] theoretical force [kN]
    rArea_cm2 : REAL; // 有效作用面积 [cm2] effective acting area [cm2]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_PI_4     : REAL := 0.7853982; // 四分之圆周率 pi divided by four
    DL_MM2_PER_CM2 : REAL := 100.0; // 平方毫米到平方厘米换算 square millimetres per square centimetre
    DL_BAR_TO_KPA : REAL := 100.0; // 巴到千帕换算 kilopascal per bar
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 五实数输入有限性判定 finiteness verdict of the five real inputs
    _rAreaMM2 : REAL := 0.0; // 有效面积 [mm2] effective area [mm2]
    _rDpBar : REAL := 0.0; // 有效压差 [bar] effective pressure difference [bar]
    _rForce : REAL := 0.0; // 推力中间量 [kN] intermediate force [kN]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_HydroCylForceCalc := 0.0; // 缺省返回零 default zero return
rForce_kN := 0.0; // 推力预置零 force preset to zero
rArea_cm2 := 0.0; // 面积预置零 area preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rBoreDia_mm = rBoreDia_mm) AND (rRodDia_mm = rRodDia_mm) AND (rPressBar = rPressBar) AND (rBackPressBar = rBackPressBar) AND (rMechEff = rMechEff); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜几何与效率闸 geometry and efficiency gate
IF (rBoreDia_mm <= 0.0) OR (rRodDia_mm < 0.0) THEN
    RETURN; // 缸径非正或杆径为负属配置非法 an illegal bore or rod geometry
END_IF
IF (rMechEff <= 0.0) OR (rMechEff > 1.0) THEN
    RETURN; // 效率越出零到一 efficiency outside the open closed interval
END_IF
IF (rPressBar < 0.0) OR (rBackPressBar < 0.0) THEN
    RETURN; // 负压力属配置非法 a negative pressure is an illegal configuration
END_IF
// 段 4｜有效面积：伸出取缸径面积，缩回取环形面积 effective area of both directions
IF bExtend THEN
    _rAreaMM2 := DL_PI_4 * rBoreDia_mm * rBoreDia_mm; // 缸径全截面 full bore section
ELSE
    IF (rRodDia_mm <= 0.0) OR (rRodDia_mm >= rBoreDia_mm) THEN
        RETURN; // 缩回要求杆径在零与缸径之间 retraction needs a rod between zero and the bore
    END_IF
    _rAreaMM2 := DL_PI_4 * (rBoreDia_mm * rBoreDia_mm - rRodDia_mm * rRodDia_mm); // 环形截面 annulus section
END_IF
rArea_cm2 := _rAreaMM2 / DL_MM2_PER_CM2; // 面积换算为平方厘米 convert the area to square centimetres
// 段 5｜压差与推力 pressure difference and the force
_rDpBar := rPressBar - rBackPressBar; // 有效压差 effective pressure difference
_rForce := _rDpBar * DL_BAR_TO_KPA * rArea_cm2 / 10000.0 * rMechEff; // 千帕乘平方米得千牛 kilopascal times square metre gives kilonewton
rForce_kN := _rForce; // 推力落定 land the force
bValid := TRUE; // 结果可用 result usable
FC_DL_HydroCylForceCalc := _rForce; // 函数返回推力 return the force
END_FUNCTION
