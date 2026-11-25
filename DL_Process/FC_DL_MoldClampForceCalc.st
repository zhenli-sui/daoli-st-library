(*
 * FC_DL_MoldClampForceCalc | C2 | DL_Process
 * 功能：浇注时铁水浮力（抬箱力）与合型压铁力（含安全系数）       单位：体积 [L]、密度 [kg/L]、重力 [m/s²]、力 [kN]、安全系数 [1]
 * 工况边界：按等效液柱静压简化 F=V×ρ×g（未计浇口杯高度附加压头与冲击动压）；型腔体积与安全系数须 >0、密度须 >0 且有限；小件压铁力偏小属正常，须由工艺员叠加砂箱自重判定
 * 代数值回代：V=12 L、ρ=7.0 kg/L、g=9.80665 → F=12×7×9.80665/1000=0.824 kN；SF=1.5 → clamp=1.24 kN（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_MoldClampForceCalc : BOOL
VAR_INPUT
    rCavityVolL      : REAL := 12.0;      // 型腔体积 | mould cavity volume [L]
    rMetalDensityKgL : REAL := 7.0;       // 铁水密度 | molten iron density [kg/L]
    rGravity         : REAL := 9.80665;   // 重力加速度 | gravitational acceleration [m/s²]
    rSf              : REAL := 1.5;       // 安全系数 | safety factor [1]
END_VAR
VAR_OUTPUT
    rBuoyancyKn : REAL;                   // 抬箱力（浮力）| lifting force [kN]
    rClampKn    : REAL;                   // 压铁力 | clamp force [kN]
    xValid      : BOOL;                   // 输出有效 | outputs valid
END_VAR
VAR
    xFinV   : BOOL;                       // 体积有限性 | volume is finite
    xFinRho : BOOL;                       // 密度有限性 | density is finite
    xFinG   : BOOL;                       // 重力有限性 | gravity is finite
    xFinSf  : BOOL;                       // 安全系数有限性 | safety factor is finite
END_VAR
VAR CONSTANT
    DL_MCF_N_TO_KN : REAL := 1000.0;      // 牛转千牛系数 | newtons to kilonewtons factor [N/kN]
END_VAR

// 段1｜非有限闸（R19）
xFinV := (rCavityVolL = rCavityVolL) AND ((rCavityVolL - rCavityVolL) = 0.0);
xFinRho := (rMetalDensityKgL = rMetalDensityKgL) AND ((rMetalDensityKgL - rMetalDensityKgL) = 0.0);
xFinG := (rGravity = rGravity) AND ((rGravity - rGravity) = 0.0);
xFinSf := (rSf = rSf) AND ((rSf - rSf) = 0.0);
IF (NOT xFinV) OR (NOT xFinRho) OR (NOT xFinG) OR (NOT xFinSf) THEN
    rBuoyancyKn := 0.0;                   // 安全值：力 0 | safe value, zero force
    rClampKn := 0.0;
    xValid := FALSE;
    FC_DL_MoldClampForceCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：体积、密度、安全系数须为正，重力须 >0
IF (rCavityVolL <= 0.0) OR (rMetalDensityKgL <= 0.0) OR (rGravity <= 0.0) OR (rSf <= 0.0) THEN
    rBuoyancyKn := 0.0;
    rClampKn := 0.0;
    xValid := FALSE;
    FC_DL_MoldClampForceCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：F = V×ρ×g/1000 kN；clamp = F×SF
rBuoyancyKn := rCavityVolL * rMetalDensityKgL * rGravity / DL_MCF_N_TO_KN;
rClampKn := rBuoyancyKn * rSf;

// 段4｜出口
xValid := TRUE;
FC_DL_MoldClampForceCalc := TRUE;
END_FUNCTION
